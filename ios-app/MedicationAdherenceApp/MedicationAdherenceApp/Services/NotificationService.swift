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
    static let reminderNotificationUnavailableMessageKey = "reminderNotificationUnavailableMessage"

    @Published private(set) var authorizationMessage = "尚未请求通知权限"
    @Published private(set) var pendingReminderCount = 0

    var notificationIdentifierPrefix: String { "dose." }
    private var escalationAlarmIdentifierPrefix: String { "dose.escalation." }
    private let maximumScheduledNotificationRequests = 60
    private let reminderPolicy = DoseReminderPolicy.competitionDemo
    private let defaults = UserDefaults.standard

    @discardableResult
    func requestAuthorization() async -> Bool {
        do {
            let granted = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            authorizationMessage = message(for: settings.authorizationStatus)
            updateNotificationUnavailableMessage(granted ? notificationUnavailableMessage(for: settings) : "普通提醒不可用：通知权限未开启，请在系统设置中允许通知。")
            return granted && notificationUnavailableMessage(for: settings) == nil
        } catch {
            authorizationMessage = "通知权限暂时无法开启，请稍后重试或前往系统设置检查。"
            updateNotificationUnavailableMessage("普通提醒不可用：暂时无法请求通知权限，请稍后重试或前往系统设置检查。")
            return false
        }
    }

    func refreshAuthorizationStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        authorizationMessage = message(for: settings.authorizationStatus)
        updateNotificationUnavailableMessage(notificationUnavailableMessage(for: settings))
    }

    @discardableResult
    func hasUsableNotificationAuthorization() async -> Bool {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        authorizationMessage = message(for: settings.authorizationStatus)
        if let unavailableMessage = notificationUnavailableMessage(for: settings) {
            updateNotificationUnavailableMessage(unavailableMessage)
            return false
        }

        updateNotificationUnavailableMessage(nil)
        return true
    }

    func refreshPendingReminderCount() async {
        let requests = await UNUserNotificationCenter.current().pendingNotificationRequests()
        pendingReminderCount = requests.filter { isBaseNotificationIdentifier($0.identifier) }.count
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
        deliveryMethod: StoredReminderDeliveryMethod = .notification,
        escalatesToAlarmWhenUnhandled: Bool = true,
        refreshPendingCount: Bool = true
    ) async {
        guard medication.lifecycleStatus == .active else {
            cancelReminder(for: task.id)
            authorizationMessage = "药物已归档或中断，未安排提醒"
            if refreshPendingCount {
                await refreshPendingReminderCount()
            }
            return
        }
        cancelReminder(for: task.id)
        await scheduleNotificationReminder(for: task, medication: medication, refreshPendingCount: refreshPendingCount)
        if deliveryMethod == .alarm {
            _ = await scheduleAlarmReminder(for: task, medication: medication)
        }
        if escalatesToAlarmWhenUnhandled {
            await scheduleEscalationAlarmIfNeeded(for: task, medication: medication)
        } else {
            cancelEscalationAlarmReminder(for: task.id)
        }
    }

    func settleOverdueDoseTasks(in modelContext: ModelContext, now: Date = Date()) -> MedicationReminderSettlement {
        let tasks = (try? modelContext.fetch(FetchDescriptor<StoredDoseTask>())) ?? []
        let medications = (try? modelContext.fetch(FetchDescriptor<StoredMedication>())) ?? []
        let activeMedicationIDs = Set(
            medications
                .filter { $0.lifecycleStatus == .active }
                .map(\.id)
        )
        let actionLogs = (try? modelContext.fetch(FetchDescriptor<StoredDoseActionLog>())) ?? []
        var updatedTaskIDs: [UUID] = []
        let inactiveOpenTaskIDs = tasks
            .filter { ($0.status == .pending || $0.status == .delayed) && !activeMedicationIDs.contains($0.medicationID) }
            .map(\.id)
        cancelReminders(for: inactiveOpenTaskIDs)
        let overdueTasks = tasks
            .filter { activeMedicationIDs.contains($0.medicationID) }
            .filter { shouldAutoSkip($0, actionLogs: actionLogs, now: now) }
            .sorted { lhs, rhs in
                if lhs.dueAt != rhs.dueAt {
                    return lhs.dueAt < rhs.dueAt
                }
                return lhs.id.uuidString < rhs.id.uuidString
            }
        let overdueTaskGroups = Dictionary(grouping: overdueTasks, by: logicalDoseKey(for:))
            .values
            .sorted { lhs, rhs in
                guard let lhsTask = lhs.first, let rhsTask = rhs.first else {
                    return lhs.count > rhs.count
                }
                if lhsTask.dueAt != rhsTask.dueAt {
                    return lhsTask.dueAt < rhsTask.dueAt
                }
                return lhsTask.id.uuidString < rhsTask.id.uuidString
            }

        for taskGroup in overdueTaskGroups {
            guard let primaryTask = preferredAutoSkipTask(from: taskGroup) else {
                continue
            }
            let autoSkipContext = autoSkipContext(for: primaryTask, actionLogs: actionLogs)
            let reason = autoSkipContext.reason
            let recordedAt = autoSkipContext.recordedAt
            for task in taskGroup {
                let taskReason = task.id == primaryTask.id ? reason : "同一剂量重复提醒已随本次自动忽略合并。"
                let log = StoredDoseActionLog(
                    taskID: task.id,
                    action: .skip,
                    previousStatus: task.status,
                    previousDueAt: task.dueAt,
                    previousRecordedAt: task.recordedAt,
                    previousReason: task.reason,
                    newStatus: .skipped,
                    occurredAt: recordedAt,
                    undoExpiresAt: now.addingTimeInterval(10 * 60),
                    note: taskReason
                )
                modelContext.insert(log)
                task.status = .skipped
                task.recordedAt = recordedAt
                task.reason = taskReason
                updatedTaskIDs.append(task.id)
            }
        }
        if !updatedTaskIDs.isEmpty {
            try? modelContext.save()
            cancelReminders(for: updatedTaskIDs)
        }
        return MedicationReminderSettlement(updatedTaskIDs: updatedTaskIDs)
    }

    func scheduleReminders(
        for tasks: [StoredDoseTask],
        medication: StoredMedication,
        deliveryMethod: StoredReminderDeliveryMethod = .notification
    ) async {
        guard medication.lifecycleStatus == .active else {
            cancelReminders(for: tasks.map(\.id))
            return
        }
        let scheduleableTasks = tasks
            .filter { ($0.status == .pending || $0.status == .delayed) && $0.dueAt > Date() }
            .sorted { $0.dueAt < $1.dueAt }
            .prefix(maximumScheduledNotificationRequests)

        for task in scheduleableTasks {
            await scheduleReminder(
                for: task,
                medication: medication,
                deliveryMethod: deliveryMethod,
                refreshPendingCount: false
            )
        }
        await refreshPendingReminderCount()
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
                    deliveryMethod: batch.deliveryMethod,
                    escalatesToAlarmWhenUnhandled: batch.escalatesToAlarmWhenUnhandled
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
                deliveryMethod: entry.deliveryMethod,
                escalatesToAlarmWhenUnhandled: entry.escalatesToAlarmWhenUnhandled,
                refreshPendingCount: false
            )
        }
        await refreshPendingReminderCount()
    }

    func cancelReminders(for taskIDs: [UUID]) {
        taskIDs.forEach { cancelReminder(for: $0) }
    }

    func cancelReminder(for taskID: UUID) {
        let identifier = notificationIdentifier(for: taskID)
        let escalationIdentifier = escalationAlarmNotificationIdentifier(for: taskID)
        let notificationIdentifiers = [identifier, escalationIdentifier]
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: notificationIdentifiers)
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: notificationIdentifiers)
        cancelAlarmReminder(for: taskID)
        cancelEscalationAlarmReminder(for: taskID)
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
                cancelReminder(for: taskID)
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

    private func cancelEscalationAlarmReminder(for taskID: UUID) {
        #if canImport(AlarmKit)
        if #available(iOS 26.0, *) {
            let escalationID = escalationAlarmID(for: taskID)
            try? AlarmManager.shared.cancel(id: escalationID)
            try? AlarmManager.shared.stop(id: escalationID)
        }
        #endif
    }

    private func scheduleNotificationReminder(
        for task: StoredDoseTask,
        medication: StoredMedication,
        refreshPendingCount: Bool = true
    ) async {
        guard task.dueAt > Date() else {
            authorizationMessage = "提醒时间已过，未安排本地提醒"
            if refreshPendingCount {
                await refreshPendingReminderCount()
            }
            return
        }
        guard await ensureNotificationAuthorizationForScheduling() else {
            return
        }

        let payload = NotificationPayload(
            scheduledDoseID: task.id,
            medicationID: medication.id,
            planID: task.planID,
            medicationName: userFacingMedicationName(for: medication),
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
            updateNotificationUnavailableMessage(nil)
            if refreshPendingCount {
                await refreshPendingReminderCount()
            }
        } catch {
            authorizationMessage = "本地提醒暂时无法安排，请稍后重试。"
            updateNotificationUnavailableMessage("普通提醒不可用：本地通知暂时无法安排，请稍后重试。")
        }
    }

    private func scheduleAlarmReminder(for task: StoredDoseTask, medication: StoredMedication) async -> Bool {
        #if canImport(AlarmKit)
        if #available(iOS 26.0, *) {
            do {
                guard AlarmManager.shared.authorizationState == .authorized else {
                    authorizationMessage = "iPhone 闹钟未授权，已改用推送通知"
                    return false
                }

                let payload = NotificationPayload(
                    scheduledDoseID: task.id,
                    medicationID: medication.id,
                    planID: task.planID,
                    medicationName: userFacingMedicationName(for: medication),
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
                authorizationMessage = "iPhone 闹钟暂时无法安排，已改用推送通知。"
                return false
            }
        }
        #endif
        authorizationMessage = "当前系统不支持 iPhone 闹钟提醒，已改用推送通知"
        return false
    }

    private func scheduleEscalationAlarmIfNeeded(for task: StoredDoseTask, medication: StoredMedication) async {
        guard task.status == .pending || task.status == .delayed else {
            return
        }
        let escalationAt = reminderPolicy.escalationDueAt(for: task.dueAt)
        guard escalationAt > Date() else {
            return
        }
        #if canImport(AlarmKit)
        if #available(iOS 26.0, *) {
            if await scheduleAlarmReminder(for: task, medication: medication, alarmID: escalationAlarmID(for: task.id), dueAt: escalationAt, titlePrefix: "仍未确认") {
                return
            }
        }
        #endif
        await scheduleEscalationNotification(for: task, medication: medication, escalationAt: escalationAt)
    }

    private func scheduleEscalationNotification(
        for task: StoredDoseTask,
        medication: StoredMedication,
        escalationAt: Date
    ) async {
        guard await ensureNotificationAuthorizationForScheduling() else {
            return
        }

        let content = UNMutableNotificationContent()
        content.title = "仍未确认服药"
        content.body = "\(userFacingMedicationName(for: medication)) · 请在 App 内确认已服用、稍后或忽略"
        content.sound = .default
        content.categoryIdentifier = MedicationNotificationDelegate.categoryIdentifier
        content.userInfo = [
            "scheduledDoseID": task.id.uuidString,
            "medicationID": medication.id.uuidString,
            "planID": task.planID.uuidString,
            "reminderKind": "escalation"
        ]

        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: escalationAt)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let identifier = escalationAlarmNotificationIdentifier(for: task.id)
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [identifier])
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        do {
            try await UNUserNotificationCenter.current().add(request)
            updateNotificationUnavailableMessage(nil)
        } catch {
            updateNotificationUnavailableMessage("普通提醒不可用：升级提醒暂时无法安排，请稍后重试。")
        }
    }

    #if canImport(AlarmKit)
    @available(iOS 26.0, *)
    private func scheduleAlarmReminder(
        for task: StoredDoseTask,
        medication: StoredMedication,
        alarmID: UUID,
        dueAt: Date,
        titlePrefix: String
    ) async -> Bool {
        do {
            guard AlarmManager.shared.authorizationState == .authorized else {
                return false
            }

            let payload = NotificationPayload(
                scheduledDoseID: task.id,
                medicationID: medication.id,
                planID: task.planID,
                medicationName: userFacingMedicationName(for: medication),
                doseText: "\(task.doseValue.formatted()) \(task.doseUnit)"
            )
            let title = LocalizedStringResource(stringLiteral: "\(titlePrefix)：\(payload.medicationName) · \(payload.doseText)")
            let stopButton = AlarmButton(
                text: "打开 App 确认",
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
                tintColor: .orange
            )
            let configuration = AlarmManager.AlarmConfiguration<MedicationAlarmMetadata>.alarm(
                schedule: .fixed(dueAt),
                attributes: attributes
            )
            _ = try await AlarmManager.shared.schedule(id: alarmID, configuration: configuration)
            return true
        } catch {
            return false
        }
    }
    #endif

    private func notificationIdentifier(for taskID: UUID) -> String {
        "\(notificationIdentifierPrefix)\(taskID.uuidString)"
    }

    private func escalationAlarmNotificationIdentifier(for taskID: UUID) -> String {
        "\(escalationAlarmIdentifierPrefix)\(taskID.uuidString)"
    }

    private func escalationAlarmID(for taskID: UUID) -> UUID {
        var rawUUID = taskID.uuid
        rawUUID.0 ^= 0x80
        return UUID(uuid: rawUUID)
    }

    private func shouldAutoSkip(_ task: StoredDoseTask, actionLogs: [StoredDoseActionLog], now: Date) -> Bool {
        guard task.status == .pending || task.status == .delayed,
              !task.reason.contains("自动记录为忽略")
        else {
            return false
        }
        if task.reason.contains("用户撤销后等待确认") {
            guard let reopenLog = latestReopenLog(for: task, actionLogs: actionLogs) else {
                return false
            }
            return reminderPolicy.shouldAutoSkipReopenedDose(reopenedAt: reopenLog.occurredAt, now: now)
        }
        return reminderPolicy.shouldAutoSkip(plannedDueAt: task.dueAt, now: now)
    }

    private func autoSkipContext(
        for task: StoredDoseTask,
        actionLogs: [StoredDoseActionLog]
    ) -> (recordedAt: Date, reason: String) {
        if task.reason.contains("用户撤销后等待确认"),
           let reopenLog = latestReopenLog(for: task, actionLogs: actionLogs) {
            return (
                reopenLog.occurredAt.addingTimeInterval(reminderPolicy.autoSkipInterval),
                "撤销后超过 \(reminderPolicy.autoSkipMinutes) 分钟仍未重新确认，已自动记录为忽略。"
            )
        }
        return (
            reminderPolicy.autoSkipRecordedAt(for: task.dueAt),
            "超过计划时间 \(reminderPolicy.autoSkipMinutes) 分钟未确认，已自动记录为忽略。"
        )
    }

    private func latestReopenLog(for task: StoredDoseTask, actionLogs: [StoredDoseActionLog]) -> StoredDoseActionLog? {
        actionLogs
            .filter { log in
                log.taskID == task.id
                    && log.undoneAt == nil
                    && log.actionRaw == DoseActionKind.correct.rawValue
                    && log.newStatusRaw == StoredDoseStatus.pending.rawValue
                    && log.note.contains("用户将已处理记录撤销为待处理")
            }
            .max { lhs, rhs in
                lhs.occurredAt < rhs.occurredAt
            }
    }

    private func preferredAutoSkipTask(from tasks: [StoredDoseTask]) -> StoredDoseTask? {
        tasks.sorted { lhs, rhs in
            if autoSkipPreferenceScore(lhs) == autoSkipPreferenceScore(rhs) {
                return lhs.id.uuidString < rhs.id.uuidString
            }
            return autoSkipPreferenceScore(lhs) > autoSkipPreferenceScore(rhs)
        }.first
    }

    private func autoSkipPreferenceScore(_ task: StoredDoseTask) -> Int {
        var score = 0
        if task.status == .delayed {
            score += 20
        }
        if task.recordedAt != nil {
            score += 10
        }
        if !task.reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            score += 5
        }
        return score
    }

    private func logicalDoseKey(for task: StoredDoseTask) -> String {
        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: task.dueAt)
        return [
            task.medicationID.uuidString,
            "\(components.year ?? 0)",
            "\(components.month ?? 0)",
            "\(components.day ?? 0)",
            "\(components.hour ?? 0)",
            "\(components.minute ?? 0)",
            task.doseValue.formatted(),
            task.doseUnit
        ].joined(separator: "|")
    }

    private func taskIDFromNotificationIdentifier(_ identifier: String) -> UUID? {
        if identifier.hasPrefix(escalationAlarmIdentifierPrefix) {
            let rawValue = String(identifier.dropFirst(escalationAlarmIdentifierPrefix.count))
            return UUID(uuidString: rawValue)
        }
        guard identifier.hasPrefix(notificationIdentifierPrefix) else {
            return nil
        }
        let rawValue = String(identifier.dropFirst(notificationIdentifierPrefix.count))
        return UUID(uuidString: rawValue)
    }

    private func isBaseNotificationIdentifier(_ identifier: String) -> Bool {
        identifier.hasPrefix(notificationIdentifierPrefix)
            && !identifier.hasPrefix(escalationAlarmIdentifierPrefix)
    }

    private func ensureNotificationAuthorizationForScheduling() async -> Bool {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        if settings.authorizationStatus == .notDetermined {
            return await requestAuthorization()
        }

        authorizationMessage = message(for: settings.authorizationStatus)
        if let unavailableMessage = notificationUnavailableMessage(for: settings) {
            updateNotificationUnavailableMessage(unavailableMessage)
            return false
        }

        updateNotificationUnavailableMessage(nil)
        return true
    }

    private func notificationUnavailableMessage(for settings: UNNotificationSettings) -> String? {
        switch settings.authorizationStatus {
        case .notDetermined:
            return "普通提醒不可用：尚未获得通知权限，请允许通知后再安排。"
        case .denied:
            return "普通提醒不可用：通知权限未开启，请在系统设置中允许通知。"
        case .authorized, .provisional, .ephemeral:
            if settings.alertSetting != .enabled
                && settings.lockScreenSetting != .enabled
                && settings.notificationCenterSetting != .enabled {
                return "普通提醒不可用：系统通知显示已关闭，请在设置中开启横幅、锁定屏幕或通知中心。"
            }
            if settings.soundSetting != .enabled {
                return "普通提醒不可用：系统通知声音已关闭，请在设置中开启声音或改用 iPhone 闹钟提醒。"
            }
            return nil
        @unknown default:
            return "普通提醒不可用：通知权限状态未知，请前往系统设置检查。"
        }
    }

    private func updateNotificationUnavailableMessage(_ message: String?) {
        if let message, !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            defaults.set(message, forKey: Self.reminderNotificationUnavailableMessageKey)
        } else {
            defaults.removeObject(forKey: Self.reminderNotificationUnavailableMessageKey)
        }
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

private struct MedicationReminderScheduleEntry {
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
        let allTasks = (try? modelContext.fetch(FetchDescriptor<StoredDoseTask>())) ?? []
        let allLogs = (try? modelContext.fetch(FetchDescriptor<StoredDoseActionLog>())) ?? []
        let doseChanges = ((try? modelContext.fetch(FetchDescriptor<StoredMedicationDoseChange>())) ?? [])
            .filter { $0.planID == plan.id || ($0.planID == nil && $0.medicationID == medication.id) }
        let planTasks = allTasks.filter { $0.planID == plan.id }
        let planTaskIDs = Set(planTasks.map(\.id))
        restoreReopenedTasksDisabledByLegacyReconcile(planTasks, actionLogs: allLogs)
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
            let effectiveDose = effectiveDoseAmount(for: dose, plan: plan, medication: medication, doseChanges: doseChanges)
            if let task = preferredTask(from: existingTasks) {
                task.dueAt = dose.dueAt
                task.doseValue = effectiveDose.value
                task.doseUnit = effectiveDose.unit
                restoreFutureTaskDisabledByMedicationLifecycleIfNeeded(task)
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

final class MedicationNotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = MedicationNotificationDelegate()
    static let categoryIdentifier = "MEDICATION_DOSE_REMINDER"

    private static let markTakenActionIdentifier = "MEDICATION_MARK_TAKEN"
    private static let delayActionIdentifier = "MEDICATION_DELAY_30_MINUTES"
    private static let skipActionIdentifier = "MEDICATION_SKIP"
    private var delayActionTitle: String {
        "\(DoseDelayPolicy.delayMinutes) 分钟后"
    }

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
            title: delayActionTitle,
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
        let taskGroup = DoseLogicalGroup.group(containing: task, in: tasks)
        let openTaskGroup = taskGroup.filter { $0.status == .pending || $0.status == .delayed }
        guard !openTaskGroup.isEmpty else {
            NotificationService().cancelReminder(for: task.id)
            await MedicationLiveActivityService().end(for: task.id)
            return
        }
        let medications = (try? context.fetch(FetchDescriptor<StoredMedication>())) ?? []
        let medication = medications.first { $0.id == task.medicationID }
        let plans = (try? context.fetch(FetchDescriptor<StoredMedicationPlan>())) ?? []
        let plan = plans.first { $0.id == task.planID }
        guard medication?.lifecycleStatus == .active else {
            for groupTask in openTaskGroup {
                NotificationService().cancelReminder(for: groupTask.id)
                await MedicationLiveActivityService().end(for: groupTask.id)
            }
            return
        }

        switch response.actionIdentifier {
        case Self.markTakenActionIdentifier:
            applyNotificationAction(
                .markTaken,
                to: openTaskGroup,
                primaryTaskID: task.id,
                newStatus: .taken,
                newDueAt: task.dueAt,
                recordedAt: Date(),
                reason: "通过通知标记已服用",
                context: context
            )
            for groupTask in openTaskGroup {
                NotificationService().cancelReminder(for: groupTask.id)
                await MedicationLiveActivityService().end(for: groupTask.id)
            }
        case Self.delayActionIdentifier:
            let occurredAt = Date()
            let newDueAt = DoseDelayPolicy.delayedDueAtFromPlannedTime(task.dueAt)
            applyNotificationAction(
                .delay,
                to: openTaskGroup,
                primaryTaskID: task.id,
                newStatus: .delayed,
                newDueAt: newDueAt,
                recordedAt: occurredAt,
                reason: "通过通知选择按原计划时间顺延 \(DoseDelayPolicy.delayMinutes) 分钟提醒",
                context: context
            )
            if let medication {
                for groupTask in openTaskGroup {
                    if groupTask.id == task.id {
                        await NotificationService().scheduleReminder(
                            for: groupTask,
                            medication: medication,
                            deliveryMethod: plan?.reminderDeliveryMethod ?? .notification
                        )
                    } else {
                        NotificationService().cancelReminder(for: groupTask.id)
                    }
                }
            }
            for groupTask in openTaskGroup {
                await MedicationLiveActivityService().end(for: groupTask.id)
            }
        case Self.skipActionIdentifier:
            applyNotificationAction(
                .skip,
                to: openTaskGroup,
                primaryTaskID: task.id,
                newStatus: .skipped,
                newDueAt: task.dueAt,
                recordedAt: Date(),
                reason: "通过通知忽略",
                context: context
            )
            for groupTask in openTaskGroup {
                NotificationService().cancelReminder(for: groupTask.id)
                await MedicationLiveActivityService().end(for: groupTask.id)
            }
        default:
            break
        }

        await startNextLiveActivityIfNeeded(in: context)
    }

    @MainActor
    private func applyNotificationAction(
        _ action: DoseActionKind,
        to tasks: [StoredDoseTask],
        primaryTaskID: UUID,
        newStatus: StoredDoseStatus,
        newDueAt: Date,
        recordedAt: Date,
        reason: String,
        context: ModelContext
    ) {
        for task in tasks {
            let taskReason = task.id == primaryTaskID ? reason : "同一剂量重复提醒已随本次通知操作合并。"
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
                note: taskReason
            )
            context.insert(log)
            task.status = newStatus
            task.dueAt = newDueAt
            task.recordedAt = recordedAt
            task.reason = taskReason
        }
        try? context.save()
    }

    @MainActor
    private func startNextLiveActivityIfNeeded(in context: ModelContext) async {
        let tasks = ((try? context.fetch(FetchDescriptor<StoredDoseTask>())) ?? [])
            .filter { $0.status == .pending || $0.status == .delayed }
            .sorted { $0.dueAt < $1.dueAt }
        let medications = (try? context.fetch(FetchDescriptor<StoredMedication>())) ?? []
        let liveActivityService = MedicationLiveActivityService()
        for task in tasks {
            guard let medication = medications.first(where: { $0.id == task.medicationID }),
                  medication.lifecycleStatus == .active
            else {
                await liveActivityService.end(for: task.id)
                continue
            }
            await liveActivityService.startIfNeeded(for: task, medication: medication)
        }
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
