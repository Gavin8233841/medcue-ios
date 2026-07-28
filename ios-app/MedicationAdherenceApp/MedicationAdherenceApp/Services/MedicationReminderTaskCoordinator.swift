import Foundation
import MedicationAdherenceCore
import SwiftData

struct MedicationReminderScheduleBatch {
    var medication: StoredMedication
    var deliveryMethod: StoredReminderDeliveryMethod
    var escalatesToAlarmWhenUnhandled: Bool
    var tasks: [StoredDoseTask]
    var cancelledTaskIDs: [UUID]
}

struct MedicationReminderSettlement {
    var updatedTaskIDs: [UUID]

    var updatedCount: Int {
        updatedTaskIDs.count
    }
}

struct MedicationReminderScheduleEntry {
    var task: StoredDoseTask
    var medication: StoredMedication
    var deliveryMethod: StoredReminderDeliveryMethod
    var escalatesToAlarmWhenUnhandled: Bool
}

@MainActor
struct MedicationReminderTaskCoordinator {
    var rollingTaskWindowDays = 30
    var calendar = Calendar.current

    func reconcileAllPlans(in modelContext: ModelContext) -> [MedicationReminderScheduleBatch] {
        let medications = (try? modelContext.fetch(FetchDescriptor<StoredMedication>())) ?? []
        let plans = (try? modelContext.fetch(FetchDescriptor<StoredMedicationPlan>())) ?? []
        let medicationByID = Dictionary(uniqueKeysWithValues: medications.map { ($0.id, $0) })

        return plans.compactMap { plan in
            guard let medication = medicationByID[plan.medicationID] else {
                return nil
            }
            guard medication.lifecycleStatus == .active else {
                let cancelledTaskIDs = tasksToCancelForInactiveMedication(plan, in: modelContext)
                cancelOpenFutureTasksForInactiveMedication(
                    for: plan,
                    status: medication.lifecycleStatus,
                    in: modelContext
                )
                return MedicationReminderScheduleBatch(
                    medication: medication,
                    deliveryMethod: plan.reminderDeliveryMethod,
                    escalatesToAlarmWhenUnhandled: plan.escalatesToAlarmWhenUnhandled,
                    tasks: [],
                    cancelledTaskIDs: cancelledTaskIDs
                )
            }
            return reconcilePlan(plan, medication: medication, in: modelContext)
        }
    }

    func reconcilePlan(
        _ plan: StoredMedicationPlan,
        medication: StoredMedication,
        in modelContext: ModelContext
    ) -> MedicationReminderScheduleBatch {
        let allTasks = (try? modelContext.fetch(FetchDescriptor<StoredDoseTask>())) ?? []
        let allLogs = (try? modelContext.fetch(FetchDescriptor<StoredDoseActionLog>())) ?? []
        let doseChanges = ((try? modelContext.fetch(FetchDescriptor<StoredMedicationDoseChange>())) ?? [])
            .filter { $0.planID == plan.id || ($0.planID == nil && $0.medicationID == medication.id) }
        let planTasks = allTasks.filter { $0.planID == plan.id }
        return reconcilePlan(
            plan,
            medication: medication,
            planTasks: planTasks,
            actionLogs: allLogs,
            doseChanges: doseChanges,
            in: modelContext
        )
    }

    func reconcilePlan(
        _ plan: StoredMedicationPlan,
        medication: StoredMedication,
        planTasks: [StoredDoseTask],
        actionLogs: [StoredDoseActionLog],
        doseChanges: [StoredMedicationDoseChange],
        in modelContext: ModelContext
    ) -> MedicationReminderScheduleBatch {
        guard medication.lifecycleStatus == .active else {
            let tasksToDisable = planTasks.filter(shouldDisableFutureTaskForInactiveMedication)
            tasksToDisable.forEach {
                disableFutureTaskForInactiveMedication($0, status: medication.lifecycleStatus)
            }
            return MedicationReminderScheduleBatch(
                medication: medication,
                deliveryMethod: plan.reminderDeliveryMethod,
                escalatesToAlarmWhenUnhandled: plan.escalatesToAlarmWhenUnhandled,
                tasks: [],
                cancelledTaskIDs: tasksToDisable.map(\.id)
            )
        }
        let planTaskIDs = Set(planTasks.map(\.id))
        restoreReopenedTasksDisabledByLegacyReconcile(planTasks, actionLogs: actionLogs)
        let delayedOriginalKeys = Set(actionLogs.compactMap { log -> String? in
            guard log.actionRaw == DoseActionKind.delay.rawValue,
                  log.undoneAt == nil,
                  planTaskIDs.contains(log.taskID)
            else {
                return nil
            }
            return logicalDoseKey(planID: plan.id, dueAt: log.previousDueAt)
        })
        let targetDoses = scheduledDoses(for: plan)
        let targetKeys = Set(targetDoses.map(logicalDoseKey(for:)))
        var taskGroupsByKey = Dictionary(grouping: planTasks, by: logicalDoseKey(for:))
        var activeTasks: [StoredDoseTask] = []
        var cancelledTaskIDs: [UUID] = []

        for dose in targetDoses {
            let key = logicalDoseKey(for: dose)
            if delayedOriginalKeys.contains(key) {
                continue
            }
            let existingTasks = taskGroupsByKey[key] ?? []
            let effectiveDose = effectiveDoseAmount(for: dose, plan: plan, medication: medication, doseChanges: doseChanges)
            if let task = preferredTask(from: existingTasks) {
                restoreFutureTaskDisabledByMedicationLifecycleIfNeeded(task)
                if task.status == .pending || task.status == .delayed {
                    task.dueAt = dose.dueAt
                    task.doseValue = effectiveDose.value
                    task.doseUnit = effectiveDose.unit
                    activeTasks.append(task)
                }
                let duplicateOpenTasks = existingTasks.filter { duplicate in
                    duplicate.id != task.id && (duplicate.status == .pending || duplicate.status == .delayed)
                }
                for duplicate in duplicateOpenTasks {
                    cancelledTaskIDs.append(duplicate.id)
                    disableFutureTask(duplicate)
                }
            } else {
                let task = StoredDoseTask(
                    medicationID: medication.id,
                    planID: plan.id,
                    dueAt: dose.dueAt,
                    doseValue: effectiveDose.value,
                    doseUnit: effectiveDose.unit
                )
                modelContext.insert(task)
                activeTasks.append(task)
                taskGroupsByKey[key] = [task]
            }
        }

        for task in planTasks where shouldDisableObsoleteFutureTask(task, targetKeys: targetKeys) {
            cancelledTaskIDs.append(task.id)
            disableFutureTask(task)
        }

        return MedicationReminderScheduleBatch(
            medication: medication,
            deliveryMethod: plan.reminderDeliveryMethod,
            escalatesToAlarmWhenUnhandled: plan.escalatesToAlarmWhenUnhandled,
            tasks: activeTasks.sorted { $0.dueAt < $1.dueAt },
            cancelledTaskIDs: cancelledTaskIDs
        )
    }

    private func cancelOpenFutureTasksForInactiveMedication(
        for plan: StoredMedicationPlan,
        status: StoredMedicationLifecycleStatus,
        in modelContext: ModelContext
    ) {
        let tasks = (try? modelContext.fetch(FetchDescriptor<StoredDoseTask>())) ?? []
        for task in tasks where task.planID == plan.id && shouldDisableFutureTaskForInactiveMedication(task) {
            disableFutureTaskForInactiveMedication(task, status: status)
        }
    }

    private func tasksToCancelForInactiveMedication(_ plan: StoredMedicationPlan, in modelContext: ModelContext) -> [UUID] {
        let tasks = (try? modelContext.fetch(FetchDescriptor<StoredDoseTask>())) ?? []
        return tasks
            .filter { $0.planID == plan.id && shouldDisableFutureTaskForInactiveMedication($0) }
            .map(\.id)
    }

    private func effectiveDoseAmount(
        for dose: ScheduledDose,
        plan: StoredMedicationPlan,
        medication: StoredMedication,
        doseChanges: [StoredMedicationDoseChange]
    ) -> (value: Double, unit: String) {
        let doseDay = calendar.startOfDay(for: dose.dueAt)
        let sortedChanges = doseChanges.sorted { lhs, rhs in
            if lhs.effectiveFrom != rhs.effectiveFrom {
                return lhs.effectiveFrom < rhs.effectiveFrom
            }
            return lhs.changedAt < rhs.changedAt
        }
        if let latestAppliedChange = sortedChanges.last(where: { change in
            change.medicationID == medication.id
                && (change.planID == nil || change.planID == plan.id)
                && calendar.startOfDay(for: change.effectiveFrom) <= doseDay
        }) {
            return (latestAppliedChange.newDoseValue, latestAppliedChange.newDoseUnit)
        }
        if let firstFutureChange = sortedChanges.first(where: { change in
            change.medicationID == medication.id
                && (change.planID == nil || change.planID == plan.id)
                && calendar.startOfDay(for: change.effectiveFrom) > doseDay
                && change.previousDoseValue != nil
        }) {
            return (firstFutureChange.previousDoseValue ?? plan.doseValue, firstFutureChange.previousDoseUnit)
        }
        return (NSDecimalNumber(decimal: dose.dose.value).doubleValue, dose.dose.unit)
    }

    private func scheduledDoses(for plan: StoredMedicationPlan) -> [ScheduledDose] {
        guard let corePlan = rollingCorePlan(for: plan) else {
            return []
        }
        return (try? ReminderScheduleEngine().scheduledDoses(
            for: corePlan,
            calendar: calendar,
            timeZone: calendar.timeZone
        )) ?? []
    }

    private func rollingCorePlan(for plan: StoredMedicationPlan) -> MedicationPlan? {
        let today = calendar.startOfDay(for: Date())
        let courseStart = calendar.startOfDay(for: plan.courseStartAt ?? today)
        let windowStart = maxDate(courseStart, today)
        let rollingEnd = calendar.date(byAdding: .day, value: rollingTaskWindowDays, to: windowStart) ?? windowStart
        let windowEnd = minDate(plan.courseEndAt.map { calendar.startOfDay(for: $0) } ?? rollingEnd, rollingEnd)
        guard windowStart <= windowEnd else {
            return nil
        }
        let times = reminderTimes(for: plan)
        guard !times.isEmpty else {
            return nil
        }
        return MedicationPlan(
            id: plan.id,
            medicationID: plan.medicationID,
            dose: DoseAmount(value: Decimal(plan.doseValue), unit: plan.doseUnit),
            startDate: dateOnly(from: windowStart),
            endDate: dateOnly(from: windowEnd),
            timingRule: .fixedLocalTimes(times),
            timeZonePolicy: ReminderTimeZonePolicy(rawValue: plan.timeZonePolicyRaw) ?? .localClock,
            sourceNote: plan.sourceNote,
            requiresUserConfirmation: plan.requiresUserConfirmation
        )
    }

    private func reminderTimes(for plan: StoredMedicationPlan) -> [TimeOfDay] {
        let times = plan.reminderTimesRaw?
            .split(separator: ",")
            .compactMap { timeOfDay(from: String($0)) } ?? []
        var seen: Set<String> = []
        let deduplicatedTimes = times
            .sorted()
            .filter { time in
                let key = "\(time.hour):\(time.minute)"
                guard !seen.contains(key) else {
                    return false
                }
                seen.insert(key)
                return true
            }
        if !deduplicatedTimes.isEmpty {
            return deduplicatedTimes
        }
        return (try? TimeOfDay(hour: 21, minute: 0)).map { [$0] } ?? []
    }

    private func timeOfDay(from rawValue: String) -> TimeOfDay? {
        let parts = rawValue.split(separator: ":")
        guard parts.count == 2, let hour = Int(parts[0]), let minute = Int(parts[1]) else {
            return nil
        }
        return try? TimeOfDay(hour: hour, minute: minute)
    }

    private func dateOnly(from date: Date) -> DateOnly {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return DateOnly(
            year: components.year ?? 1970,
            month: components.month ?? 1,
            day: components.day ?? 1
        )
    }

    private func logicalDoseKey(for dose: ScheduledDose) -> String {
        logicalDoseKey(planID: dose.planID, dueAt: dose.dueAt)
    }

    private func logicalDoseKey(for task: StoredDoseTask) -> String {
        logicalDoseKey(planID: task.planID, dueAt: task.dueAt)
    }

    private func logicalDoseKey(planID: UUID, dueAt: Date) -> String {
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: dueAt)
        return [
            planID.uuidString,
            "\(components.year ?? 0)",
            "\(components.month ?? 0)",
            "\(components.day ?? 0)",
            "\(components.hour ?? 0)",
            "\(components.minute ?? 0)"
        ].joined(separator: "|")
    }

    private func preferredTask(from tasks: [StoredDoseTask]) -> StoredDoseTask? {
        tasks.sorted { lhs, rhs in
            if taskPreferenceScore(lhs) == taskPreferenceScore(rhs) {
                return lhs.dueAt < rhs.dueAt
            }
            return taskPreferenceScore(lhs) > taskPreferenceScore(rhs)
        }.first
    }

    private func taskPreferenceScore(_ task: StoredDoseTask) -> Int {
        switch task.status {
        case .pending, .delayed:
            return 3
        case .taken, .corrected:
            return 2
        case .skipped:
            return 1
        }
    }

    private func shouldDisableObsoleteFutureTask(_ task: StoredDoseTask, targetKeys: Set<String>) -> Bool {
        return task.status == .pending
            && task.dueAt >= calendar.startOfDay(for: Date())
            && !task.reason.contains("用户撤销后等待确认")
            && !targetKeys.contains(logicalDoseKey(for: task))
    }

    private func shouldDisableFutureTaskForInactiveMedication(_ task: StoredDoseTask) -> Bool {
        return (task.status == .pending || task.status == .delayed)
            && task.dueAt >= calendar.startOfDay(for: Date())
            && !task.reason.contains("用户撤销后等待确认")
    }

    private func restoreFutureTaskDisabledByMedicationLifecycleIfNeeded(_ task: StoredDoseTask) {
        guard isFutureTaskDisabledByMedicationLifecycle(task) else {
            return
        }
        task.status = .pending
        task.recordedAt = nil
        task.reason = ""
    }

    private func isFutureTaskDisabledByMedicationLifecycle(_ task: StoredDoseTask) -> Bool {
        task.status == .skipped
            && task.dueAt >= calendar.startOfDay(for: Date())
            && (task.reason.contains("药物已归档，未来提醒已停用") || task.reason.contains("药物已中断，未来提醒已停用"))
    }

    private func restoreReopenedTasksDisabledByLegacyReconcile(
        _ tasks: [StoredDoseTask],
        actionLogs: [StoredDoseActionLog]
    ) {
        let logsByTaskID = Dictionary(grouping: actionLogs, by: \.taskID)
        for task in tasks where isLegacyDisabledReopenedTask(task) {
            guard let latestLog = logsByTaskID[task.id]?.max(by: { $0.occurredAt < $1.occurredAt }),
                  latestLog.undoneAt == nil,
                  latestLog.actionRaw == DoseActionKind.correct.rawValue,
                  latestLog.newStatusRaw == StoredDoseStatus.pending.rawValue,
                  latestLog.note.contains("用户将已处理记录撤销为待处理")
            else {
                continue
            }
            task.status = .pending
            task.recordedAt = nil
            task.reason = reopenedConfirmationReason(from: latestLog.note)
        }
    }

    private func isLegacyDisabledReopenedTask(_ task: StoredDoseTask) -> Bool {
        task.status == .skipped
            && task.reason.contains("未来提醒已停用")
    }

    private func reopenedConfirmationReason(from note: String) -> String {
        let confirmationReason = "用户撤销后等待确认"
        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedNote.isEmpty, !trimmedNote.contains(confirmationReason) else {
            return confirmationReason
        }
        return "\(trimmedNote)；\(confirmationReason)"
    }

    private func disableFutureTask(_ task: StoredDoseTask) {
        task.status = .skipped
        task.recordedAt = Date()
        task.reason = "疗程与提醒已更新，此次未来提醒已停用。"
    }

    private func disableFutureTaskForInactiveMedication(
        _ task: StoredDoseTask,
        status: StoredMedicationLifecycleStatus
    ) {
        task.status = .skipped
        task.recordedAt = nil
        task.reason = status == .interrupted ? "药物已中断，未来提醒已停用。" : "药物已归档，未来提醒已停用。"
    }

    private func maxDate(_ lhs: Date, _ rhs: Date) -> Date {
        lhs >= rhs ? lhs : rhs
    }

    private func minDate(_ lhs: Date, _ rhs: Date) -> Date {
        lhs <= rhs ? lhs : rhs
    }
}
