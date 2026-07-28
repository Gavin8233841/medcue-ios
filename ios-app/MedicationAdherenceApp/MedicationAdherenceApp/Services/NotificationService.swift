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
    private let notificationPolicy = MedicationNotificationPolicy.default
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
        guard AppPersistenceCommitter.save(modelContext, operation: "reminder-reconciliation") else {
            return
        }
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
            guard AppPersistenceCommitter.save(modelContext, operation: "overdue-dose-settlement") else {
                return MedicationReminderSettlement(updatedTaskIDs: [])
            }
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
        let sortedTasks = tasks
            .filter { ($0.status == .pending || $0.status == .delayed) && $0.dueAt > Date() }
            .sorted { $0.dueAt < $1.dueAt }
        let scheduleableTasks = notificationPolicy.boundedUniqueEntries(
            from: sortedTasks,
            identifiedBy: \.id
        )

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
        let nearTermEntries = notificationPolicy.boundedUniqueEntries(
            from: sortedEntries,
            identifiedBy: \.task.id
        )
        let overflowTaskIDs = sortedEntries
            .dropFirst(notificationPolicy.maximumScheduledEntries)
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

        let components = notificationPolicy.triggerDateComponents(for: task.dueAt, calendar: .current)
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

        let components = notificationPolicy.triggerDateComponents(for: escalationAt, calendar: .current)
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
        let status: MedicationNotificationAuthorizationStatus
        switch settings.authorizationStatus {
        case .notDetermined:
            status = .notDetermined
        case .denied:
            status = .denied
        case .authorized, .provisional, .ephemeral:
            status = .authorized
        @unknown default:
            status = .unknown
        }
        let disposition = notificationPolicy.authorizationDisposition(
            status: status,
            hasPresentationSurface: settings.alertSetting == .enabled
                || settings.lockScreenSetting == .enabled
                || settings.notificationCenterSetting == .enabled,
            hasSound: settings.soundSetting == .enabled
        )
        return notificationPolicy.unavailableMessage(for: disposition)
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
