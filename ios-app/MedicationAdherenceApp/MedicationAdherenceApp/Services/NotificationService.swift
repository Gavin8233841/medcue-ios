import Foundation
import MedicationAdherenceCore
import SwiftData
import UserNotifications
#if canImport(AlarmKit)
import AlarmKit
import SwiftUI
#endif

@MainActor
final class NotificationService: ObservableObject {
    @Published private(set) var authorizationMessage = "尚未请求通知权限"
    @Published private(set) var pendingReminderCount = 0

    var notificationIdentifierPrefix: String { "dose." }
    private let maximumScheduledNotificationRequests = 60

    @discardableResult
    func requestAuthorization() async -> Bool {
        do {
            let granted = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
            authorizationMessage = granted ? "通知权限已开启" : "通知权限未开启"
            return granted
        } catch {
            authorizationMessage = "通知权限请求失败：\(error.localizedDescription)"
            return false
        }
    }

    func refreshAuthorizationStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        authorizationMessage = message(for: settings.authorizationStatus)
    }

    func refreshPendingReminderCount() async {
        let requests = await UNUserNotificationCenter.current().pendingNotificationRequests()
        pendingReminderCount = requests.filter { $0.identifier.hasPrefix(notificationIdentifierPrefix) }.count
    }

    func reconcileAndScheduleReminders(in modelContext: ModelContext) async {
        let batches = MedicationReminderTaskCoordinator().reconcileAllPlans(in: modelContext)
        try? modelContext.save()
        cancelReminders(for: batches.flatMap(\.cancelledTaskIDs))
        await scheduleReminderBatches(batches, pruneExistingPrefixRequests: true)
        await refreshPendingReminderCount()
    }

    func scheduleReminder(
        for task: StoredDoseTask,
        medication: StoredMedication,
        deliveryMethod: StoredReminderDeliveryMethod = .notification
    ) async {
        cancelReminder(for: task.id)
        if deliveryMethod == .alarm {
            let didScheduleAlarm = await scheduleAlarmReminder(for: task, medication: medication)
            if didScheduleAlarm {
                return
            }
        }
        await scheduleNotificationReminder(for: task, medication: medication)
    }

    func scheduleReminders(
        for tasks: [StoredDoseTask],
        medication: StoredMedication,
        deliveryMethod: StoredReminderDeliveryMethod = .notification
    ) async {
        let scheduleableTasks = tasks
            .filter { ($0.status == .pending || $0.status == .delayed) && $0.dueAt > Date() }
            .sorted { $0.dueAt < $1.dueAt }
            .prefix(maximumScheduledNotificationRequests)

        for task in scheduleableTasks {
            await scheduleReminder(for: task, medication: medication, deliveryMethod: deliveryMethod)
        }
    }

    func scheduleReminderBatches(
        _ batches: [MedicationReminderScheduleBatch],
        pruneExistingPrefixRequests: Bool = false
    ) async {
        var entries: [MedicationReminderScheduleEntry] = []
        for batch in batches {
            for task in batch.tasks {
                guard (task.status == .pending || task.status == .delayed) && task.dueAt > Date() else {
                    continue
                }
                entries.append(MedicationReminderScheduleEntry(
                    task: task,
                    medication: batch.medication,
                    deliveryMethod: batch.deliveryMethod
                ))
            }
        }
        let sortedEntries = entries
            .sorted { $0.task.dueAt < $1.task.dueAt }
        let nearTermEntries = Array(sortedEntries.prefix(maximumScheduledNotificationRequests))
        let overflowTaskIDs = sortedEntries
            .dropFirst(maximumScheduledNotificationRequests)
            .map(\.task.id)

        cancelReminders(for: overflowTaskIDs)
        if pruneExistingPrefixRequests {
            await cancelScheduledNotificationRequests(except: Set(nearTermEntries.map { notificationIdentifier(for: $0.task.id) }))
        }

        for entry in nearTermEntries {
            await scheduleReminder(
                for: entry.task,
                medication: entry.medication,
                deliveryMethod: entry.deliveryMethod
            )
        }
    }

    func cancelReminders(for taskIDs: [UUID]) {
        taskIDs.forEach { cancelReminder(for: $0) }
    }

    func cancelReminder(for taskID: UUID) {
        let identifier = notificationIdentifier(for: taskID)
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [identifier])
        cancelAlarmReminder(for: taskID)
    }

    private func cancelScheduledNotificationRequests(except identifiersToKeep: Set<String>) async {
        let pendingRequests = await UNUserNotificationCenter.current().pendingNotificationRequests()
        let staleIdentifiers = pendingRequests
            .map(\.identifier)
            .filter { $0.hasPrefix(notificationIdentifierPrefix) && !identifiersToKeep.contains($0) }
        guard !staleIdentifiers.isEmpty else {
            return
        }
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: staleIdentifiers)
        staleIdentifiers
            .compactMap(taskIDFromNotificationIdentifier)
            .forEach { taskID in
                cancelAlarmReminder(for: taskID)
            }
    }

    private func cancelAlarmReminder(for taskID: UUID) {
        #if canImport(AlarmKit)
        if #available(iOS 26.0, *) {
            try? AlarmManager.shared.cancel(id: taskID)
            try? AlarmManager.shared.stop(id: taskID)
        }
        #endif
    }

    private func scheduleNotificationReminder(for task: StoredDoseTask, medication: StoredMedication) async {
        guard task.dueAt > Date() else {
            authorizationMessage = "提醒时间已过，未安排本地提醒"
            return
        }
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional || settings.authorizationStatus == .ephemeral else {
            authorizationMessage = message(for: settings.authorizationStatus)
            return
        }

        let payload = NotificationPayload(
            scheduledDoseID: task.id,
            medicationID: medication.id,
            planID: task.planID,
            medicationName: medication.displayName,
            doseText: "\(task.doseValue.formatted()) \(task.doseUnit)"
        )

        let content = UNMutableNotificationContent()
        content.title = "该服药了"
        content.body = "\(payload.medicationName) · \(payload.doseText)"
        content.sound = .default
        content.categoryIdentifier = MedicationNotificationDelegate.categoryIdentifier
        content.userInfo = [
            "scheduledDoseID": payload.scheduledDoseID.uuidString,
            "medicationID": payload.medicationID.uuidString,
            "planID": payload.planID.uuidString
        ]

        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: task.dueAt)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let identifier = notificationIdentifier(for: task.id)
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [identifier])
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        do {
            try await UNUserNotificationCenter.current().add(request)
            authorizationMessage = "已安排下一次本地提醒"
            await refreshPendingReminderCount()
        } catch {
            authorizationMessage = "本地提醒安排失败：\(error.localizedDescription)"
        }
    }

    private func scheduleAlarmReminder(for task: StoredDoseTask, medication: StoredMedication) async -> Bool {
        #if canImport(AlarmKit)
        if #available(iOS 26.0, *) {
            do {
                let authorizationState = try await AlarmManager.shared.requestAuthorization()
                guard authorizationState == .authorized else {
                    authorizationMessage = "iPhone 闹钟未授权，已改用推送通知"
                    return false
                }

                let payload = NotificationPayload(
                    scheduledDoseID: task.id,
                    medicationID: medication.id,
                    planID: task.planID,
                    medicationName: medication.displayName,
                    doseText: "\(task.doseValue.formatted()) \(task.doseUnit)"
                )
                let title = LocalizedStringResource(stringLiteral: "\(payload.medicationName) · \(payload.doseText)")
                let stopButton = AlarmButton(
                    text: "完成",
                    textColor: .white,
                    systemImageName: "checkmark"
                )
                let presentation = AlarmPresentation(alert: AlarmPresentation.Alert(title: title, stopButton: stopButton))
                let attributes = AlarmAttributes<MedicationAlarmMetadata>(
                    presentation: presentation,
                    metadata: MedicationAlarmMetadata(
                        scheduledDoseID: payload.scheduledDoseID,
                        medicationID: payload.medicationID,
                        planID: payload.planID
                    ),
                    tintColor: .teal
                )
                let configuration = AlarmManager.AlarmConfiguration<MedicationAlarmMetadata>.alarm(
                    schedule: .fixed(task.dueAt),
                    attributes: attributes
                )
                _ = try await AlarmManager.shared.schedule(id: task.id, configuration: configuration)
                authorizationMessage = "已安排 iPhone 闹钟提醒"
                return true
            } catch {
                authorizationMessage = "iPhone 闹钟安排失败，已改用推送通知：\(error.localizedDescription)"
                return false
            }
        }
        #endif
        authorizationMessage = "当前系统不支持 iPhone 闹钟提醒，已改用推送通知"
        return false
    }

    private func notificationIdentifier(for taskID: UUID) -> String {
        "\(notificationIdentifierPrefix)\(taskID.uuidString)"
    }

    private func taskIDFromNotificationIdentifier(_ identifier: String) -> UUID? {
        guard identifier.hasPrefix(notificationIdentifierPrefix) else {
            return nil
        }
        let rawValue = String(identifier.dropFirst(notificationIdentifierPrefix.count))
        return UUID(uuidString: rawValue)
    }

    private func message(for status: UNAuthorizationStatus) -> String {
        switch status {
        case .notDetermined:
            return "尚未请求通知权限"
        case .denied:
            return "通知权限未开启"
        case .authorized:
            return "通知权限已开启"
        case .provisional:
            return "通知权限已临时开启"
        case .ephemeral:
            return "通知权限已开启"
        @unknown default:
            return "通知权限状态未知"
        }
    }
}

struct MedicationReminderScheduleBatch {
    var medication: StoredMedication
    var deliveryMethod: StoredReminderDeliveryMethod
    var tasks: [StoredDoseTask]
    var cancelledTaskIDs: [UUID]
}

private struct MedicationReminderScheduleEntry {
    var task: StoredDoseTask
    var medication: StoredMedication
    var deliveryMethod: StoredReminderDeliveryMethod
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
        let planTasks = allTasks.filter { $0.planID == plan.id }
        let planTaskIDs = Set(planTasks.map(\.id))
        let delayedOriginalKeys = Set(allLogs.compactMap { log -> String? in
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
            if let task = preferredTask(from: existingTasks) {
                task.dueAt = dose.dueAt
                task.doseValue = NSDecimalNumber(decimal: dose.dose.value).doubleValue
                task.doseUnit = dose.dose.unit
                if task.status == .pending || task.status == .delayed {
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
                    doseValue: NSDecimalNumber(decimal: dose.dose.value).doubleValue,
                    doseUnit: dose.dose.unit
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
            tasks: activeTasks.sorted { $0.dueAt < $1.dueAt },
            cancelledTaskIDs: cancelledTaskIDs
        )
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
            && !targetKeys.contains(logicalDoseKey(for: task))
    }

    private func disableFutureTask(_ task: StoredDoseTask) {
        task.status = .skipped
        task.recordedAt = Date()
        task.reason = "疗程与提醒已更新，此次未来提醒已停用。"
    }

    private func maxDate(_ lhs: Date, _ rhs: Date) -> Date {
        lhs >= rhs ? lhs : rhs
    }

    private func minDate(_ lhs: Date, _ rhs: Date) -> Date {
        lhs <= rhs ? lhs : rhs
    }
}

final class MedicationNotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = MedicationNotificationDelegate()
    static let categoryIdentifier = "MEDICATION_DOSE_REMINDER"

    private static let markTakenActionIdentifier = "MEDICATION_MARK_TAKEN"
    private static let delayActionIdentifier = "MEDICATION_DELAY_30_MINUTES"
    private static let skipActionIdentifier = "MEDICATION_SKIP"

    private var modelContainer: ModelContainer?

    private override init() {
        super.init()
    }

    func install(modelContainer: ModelContainer? = nil) {
        if let modelContainer {
            self.modelContainer = modelContainer
        }
        registerNotificationCategories()
        UNUserNotificationCenter.current().delegate = self
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound, .badge]
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        await handleNotificationResponse(response)
    }

    private func registerNotificationCategories() {
        let markTakenAction = UNNotificationAction(
            identifier: Self.markTakenActionIdentifier,
            title: "已服用",
            options: []
        )
        let delayAction = UNNotificationAction(
            identifier: Self.delayActionIdentifier,
            title: "30 分钟后",
            options: []
        )
        let skipAction = UNNotificationAction(
            identifier: Self.skipActionIdentifier,
            title: "忽略",
            options: [.destructive]
        )
        let category = UNNotificationCategory(
            identifier: Self.categoryIdentifier,
            actions: [markTakenAction, delayAction, skipAction],
            intentIdentifiers: [],
            options: [.customDismissAction]
        )
        UNUserNotificationCenter.current().setNotificationCategories([category])
    }

    @MainActor
    private func handleNotificationResponse(_ response: UNNotificationResponse) async {
        guard response.actionIdentifier == Self.markTakenActionIdentifier
            || response.actionIdentifier == Self.delayActionIdentifier
            || response.actionIdentifier == Self.skipActionIdentifier
        else {
            return
        }
        guard let modelContainer,
              let taskID = uuidValue(for: "scheduledDoseID", in: response.notification.request.content.userInfo)
        else {
            return
        }

        let context = ModelContext(modelContainer)
        let tasks = (try? context.fetch(FetchDescriptor<StoredDoseTask>())) ?? []
        guard let task = tasks.first(where: { $0.id == taskID }) else {
            return
        }
        guard task.status == .pending || task.status == .delayed else {
            NotificationService().cancelReminder(for: task.id)
            await MedicationLiveActivityService().end(for: task.id)
            return
        }
        let medications = (try? context.fetch(FetchDescriptor<StoredMedication>())) ?? []
        let medication = medications.first { $0.id == task.medicationID }
        let plans = (try? context.fetch(FetchDescriptor<StoredMedicationPlan>())) ?? []
        let plan = plans.first { $0.id == task.planID }

        switch response.actionIdentifier {
        case Self.markTakenActionIdentifier:
            applyNotificationAction(
                .markTaken,
                to: task,
                newStatus: .taken,
                newDueAt: task.dueAt,
                recordedAt: Date(),
                reason: "通过通知标记已服用",
                context: context
            )
            NotificationService().cancelReminder(for: task.id)
            await MedicationLiveActivityService().end(for: task.id)
        case Self.delayActionIdentifier:
            let occurredAt = Date()
            let newDueAt = Calendar.current.date(byAdding: .minute, value: 30, to: occurredAt) ?? task.dueAt
            applyNotificationAction(
                .delay,
                to: task,
                newStatus: .delayed,
                newDueAt: newDueAt,
                recordedAt: occurredAt,
                reason: "通过通知选择 30 分钟后提醒",
                context: context
            )
            if let medication {
                await NotificationService().scheduleReminder(
                    for: task,
                    medication: medication,
                    deliveryMethod: plan?.reminderDeliveryMethod ?? .notification
                )
            }
            await MedicationLiveActivityService().end(for: task.id)
        case Self.skipActionIdentifier:
            applyNotificationAction(
                .skip,
                to: task,
                newStatus: .skipped,
                newDueAt: task.dueAt,
                recordedAt: Date(),
                reason: "通过通知忽略",
                context: context
            )
            NotificationService().cancelReminder(for: task.id)
            await MedicationLiveActivityService().end(for: task.id)
        default:
            break
        }
    }

    @MainActor
    private func applyNotificationAction(
        _ action: DoseActionKind,
        to task: StoredDoseTask,
        newStatus: StoredDoseStatus,
        newDueAt: Date,
        recordedAt: Date,
        reason: String,
        context: ModelContext
    ) {
        let log = StoredDoseActionLog(
            taskID: task.id,
            action: action,
            previousStatus: task.status,
            previousDueAt: task.dueAt,
            previousRecordedAt: task.recordedAt,
            previousReason: task.reason,
            newStatus: newStatus,
            occurredAt: recordedAt,
            undoExpiresAt: recordedAt.addingTimeInterval(10 * 60),
            note: reason
        )
        context.insert(log)
        task.status = newStatus
        task.dueAt = newDueAt
        task.recordedAt = recordedAt
        task.reason = reason
        try? context.save()
    }

    private func uuidValue(for key: String, in userInfo: [AnyHashable: Any]) -> UUID? {
        guard let rawValue = userInfo[key] as? String else {
            return nil
        }
        return UUID(uuidString: rawValue)
    }
}

#if canImport(AlarmKit)
@available(iOS 26.0, *)
private struct MedicationAlarmMetadata: AlarmMetadata {
    let scheduledDoseID: UUID
    let medicationID: UUID
    let planID: UUID
}
#endif
