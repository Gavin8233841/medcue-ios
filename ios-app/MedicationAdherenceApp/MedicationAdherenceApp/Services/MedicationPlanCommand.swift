import Foundation
import OSLog
import SwiftData

struct MedicationPlanUpdate: Sendable {
    let medicationID: UUID
    let planID: UUID?
    let doseValue: Double
    let doseUnit: String
    let doseEffectiveFrom: Date
    let doseChangeNote: String
    let courseStartAt: Date
    let courseEndAt: Date?
    let reminderTimes: [Date]
    let reminderDeliveryMethod: StoredReminderDeliveryMethod
    let escalatesToAlarmWhenUnhandled: Bool
    let sourceNote: String
}

enum MedicationPlanRejection: Equatable {
    case emptyDoseUnit
    case emptyReminderTimes
    case medicationNotFound
    case planNotFound
    case readFailed
}

enum MedicationPlanCommandOutcome {
    case committed(
        planID: UUID,
        created: Bool,
        reminderBatch: MedicationReminderScheduleBatch
    )
    case rejected(MedicationPlanRejection)
    case saveFailed
}

@MainActor
struct MedicationPlanCommand {
    typealias SaveOperation = (ModelContext) throws -> Void

    private let modelContext: ModelContext
    private let saveOperation: SaveOperation
    private var calendar: Calendar
    private static let signposter = OSSignposter(
        subsystem: "com.gwyy.appcontest2026.medicationadherence",
        category: "Performance"
    )

    init(
        modelContext: ModelContext,
        calendar: Calendar = .current,
        saveOperation: @escaping SaveOperation = { try $0.save() }
    ) {
        self.modelContext = modelContext
        self.calendar = calendar
        self.saveOperation = saveOperation
    }

    func update(_ update: MedicationPlanUpdate) -> MedicationPlanCommandOutcome {
        let saveInterval = Self.signposter.beginInterval("plan.save")
        defer { Self.signposter.endInterval("plan.save", saveInterval) }
        let doseUnit = update.doseUnit.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !doseUnit.isEmpty else {
            return .rejected(.emptyDoseUnit)
        }
        let reminderTimes = normalizedReminderTimes(update.reminderTimes)
        guard !reminderTimes.isEmpty else {
            return .rejected(.emptyReminderTimes)
        }

        let medication: StoredMedication
        do {
            let medicationID = update.medicationID
            let descriptor = FetchDescriptor<StoredMedication>(
                predicate: #Predicate { $0.id == medicationID }
            )
            guard let storedMedication = try modelContext.fetch(descriptor).first else {
                return .rejected(.medicationNotFound)
            }
            medication = storedMedication
        } catch {
            return .rejected(.readFailed)
        }

        let existingPlan: StoredMedicationPlan?
        do {
            if let planID = update.planID {
                let descriptor = FetchDescriptor<StoredMedicationPlan>(
                    predicate: #Predicate { $0.id == planID }
                )
                guard let storedPlan = try modelContext.fetch(descriptor).first else {
                    return .rejected(.planNotFound)
                }
                existingPlan = storedPlan
            } else {
                existingPlan = nil
            }
        } catch {
            return .rejected(.readFailed)
        }

        let planSnapshot = existingPlan.map(MedicationPlanSnapshot.init)
        let planTasks: [StoredDoseTask]
        let actionLogs: [StoredDoseActionLog]
        let existingDoseChanges: [StoredMedicationDoseChange]
        do {
            if let existingPlanID = existingPlan?.id {
                let descriptor = FetchDescriptor<StoredDoseTask>(
                    predicate: #Predicate { $0.planID == existingPlanID }
                )
                planTasks = try modelContext.fetch(descriptor)
            } else {
                planTasks = []
            }
            let taskIDs = planTasks.map(\.id)
            if taskIDs.isEmpty {
                actionLogs = []
            } else {
                let descriptor = FetchDescriptor<StoredDoseActionLog>(
                    predicate: #Predicate { taskIDs.contains($0.taskID) }
                )
                actionLogs = try modelContext.fetch(descriptor)
            }
            let medicationID = update.medicationID
            let descriptor = FetchDescriptor<StoredMedicationDoseChange>(
                predicate: #Predicate { $0.medicationID == medicationID }
            )
            existingDoseChanges = try modelContext.fetch(descriptor).filter {
                $0.planID == existingPlan?.id || $0.planID == nil
            }
        } catch {
            return .rejected(.readFailed)
        }
        let taskSnapshots = planTasks.map(MedicationPlanTaskSnapshot.init)

        let previousDoseValue = existingPlan?.doseValue
        let previousDoseUnit = existingPlan?.doseUnit ?? ""
        let plan: StoredMedicationPlan
        let created: Bool
        if let existingPlan {
            plan = existingPlan
            created = false
            plan.doseValue = update.doseValue
            plan.doseUnit = doseUnit
            plan.timingSummary = reminderSummary(reminderTimes)
            plan.sourceNote = update.sourceNote.trimmingCharacters(in: .whitespacesAndNewlines)
            plan.courseStartAt = update.courseStartAt
            plan.courseEndAt = update.courseEndAt
            plan.reminderTimesRaw = encodedReminderTimes(reminderTimes)
            plan.reminderDeliveryMethod = update.reminderDeliveryMethod
            plan.escalatesToAlarmWhenUnhandled = update.escalatesToAlarmWhenUnhandled
        } else {
            plan = StoredMedicationPlan(
                medicationID: medication.id,
                doseValue: update.doseValue,
                doseUnit: doseUnit,
                timingSummary: reminderSummary(reminderTimes),
                timeZonePolicy: .localClock,
                sourceNote: update.sourceNote.trimmingCharacters(in: .whitespacesAndNewlines),
                requiresUserConfirmation: true,
                courseStartAt: update.courseStartAt,
                courseEndAt: update.courseEndAt,
                reminderTimesRaw: encodedReminderTimes(reminderTimes),
                reminderDelivery: update.reminderDeliveryMethod,
                escalatesToAlarmWhenUnhandled: update.escalatesToAlarmWhenUnhandled
            )
            modelContext.insert(plan)
            created = true
        }

        var doseChanges = existingDoseChanges
        if doseChanged(
            previousValue: previousDoseValue,
            previousUnit: previousDoseUnit,
            newValue: update.doseValue,
            newUnit: doseUnit
        ) {
            let trimmedNote = update.doseChangeNote.trimmingCharacters(in: .whitespacesAndNewlines)
            let note = trimmedNote.isEmpty
                ? (previousDoseValue == nil
                    ? "初始剂量记录，用户已确认。"
                    : "用户确认后修改剂量；请按医嘱、说明书或药师建议核对。")
                : trimmedNote
            let doseChange = StoredMedicationDoseChange(
                medicationID: medication.id,
                planID: plan.id,
                previousDoseValue: previousDoseValue,
                previousDoseUnit: previousDoseUnit,
                newDoseValue: update.doseValue,
                newDoseUnit: doseUnit,
                effectiveFrom: calendar.startOfDay(for: update.doseEffectiveFrom),
                note: note
            )
            modelContext.insert(doseChange)
            doseChanges.append(doseChange)
        }

        let reconcileInterval = Self.signposter.beginInterval("plan.reconcile")
        let reminderBatch = MedicationReminderTaskCoordinator(calendar: calendar).reconcilePlan(
            plan,
            medication: medication,
            planTasks: planTasks,
            actionLogs: actionLogs,
            doseChanges: doseChanges,
            in: modelContext
        )
        Self.signposter.endInterval("plan.reconcile", reconcileInterval)

        do {
            try saveOperation(modelContext)
            return .committed(planID: plan.id, created: created, reminderBatch: reminderBatch)
        } catch {
            planSnapshot?.restore()
            taskSnapshots.forEach { $0.restore() }
            modelContext.rollback()
            AppPersistenceCommitter.reportFailure(operation: "medication-plan-update")
            return .saveFailed
        }
    }

    private func normalizedReminderTimes(_ dates: [Date]) -> [(hour: Int, minute: Int)] {
        var uniqueTimes: Set<ReminderTime> = []
        for date in dates {
            uniqueTimes.insert(ReminderTime(
                hour: calendar.component(.hour, from: date),
                minute: calendar.component(.minute, from: date)
            ))
        }
        return uniqueTimes.sorted { lhs, rhs in
            lhs.hour == rhs.hour ? lhs.minute < rhs.minute : lhs.hour < rhs.hour
        }
        .map { ($0.hour, $0.minute) }
    }

    private func encodedReminderTimes(_ times: [(hour: Int, minute: Int)]) -> String {
        times.map { String(format: "%02d:%02d", $0.hour, $0.minute) }.joined(separator: ",")
    }

    private func reminderSummary(_ times: [(hour: Int, minute: Int)]) -> String {
        "每日 " + times.map { String(format: "%02d:%02d", $0.hour, $0.minute) }.joined(separator: "、")
    }

    private func doseChanged(
        previousValue: Double?,
        previousUnit: String,
        newValue: Double,
        newUnit: String
    ) -> Bool {
        guard let previousValue else {
            return true
        }
        return abs(previousValue - newValue) > 0.0001 || previousUnit != newUnit
    }
}

private struct ReminderTime: Hashable {
    let hour: Int
    let minute: Int
}

private struct MedicationPlanSnapshot {
    let plan: StoredMedicationPlan
    let doseValue: Double
    let doseUnit: String
    let timingSummary: String
    let sourceNote: String
    let courseStartAt: Date?
    let courseEndAt: Date?
    let reminderTimesRaw: String?
    let reminderDeliveryRaw: String?
    let escalatesToAlarmWhenUnhandledRaw: Bool?

    init(_ plan: StoredMedicationPlan) {
        self.plan = plan
        doseValue = plan.doseValue
        doseUnit = plan.doseUnit
        timingSummary = plan.timingSummary
        sourceNote = plan.sourceNote
        courseStartAt = plan.courseStartAt
        courseEndAt = plan.courseEndAt
        reminderTimesRaw = plan.reminderTimesRaw
        reminderDeliveryRaw = plan.reminderDeliveryRaw
        escalatesToAlarmWhenUnhandledRaw = plan.escalatesToAlarmWhenUnhandledRaw
    }

    func restore() {
        plan.doseValue = doseValue
        plan.doseUnit = doseUnit
        plan.timingSummary = timingSummary
        plan.sourceNote = sourceNote
        plan.courseStartAt = courseStartAt
        plan.courseEndAt = courseEndAt
        plan.reminderTimesRaw = reminderTimesRaw
        plan.reminderDeliveryRaw = reminderDeliveryRaw
        plan.escalatesToAlarmWhenUnhandledRaw = escalatesToAlarmWhenUnhandledRaw
    }
}

private struct MedicationPlanTaskSnapshot {
    let task: StoredDoseTask
    let dueAt: Date
    let doseValue: Double
    let doseUnit: String
    let statusRaw: String
    let recordedAt: Date?
    let reason: String

    init(_ task: StoredDoseTask) {
        self.task = task
        dueAt = task.dueAt
        doseValue = task.doseValue
        doseUnit = task.doseUnit
        statusRaw = task.statusRaw
        recordedAt = task.recordedAt
        reason = task.reason
    }

    func restore() {
        task.dueAt = dueAt
        task.doseValue = doseValue
        task.doseUnit = doseUnit
        task.statusRaw = statusRaw
        task.recordedAt = recordedAt
        task.reason = reason
    }
}
