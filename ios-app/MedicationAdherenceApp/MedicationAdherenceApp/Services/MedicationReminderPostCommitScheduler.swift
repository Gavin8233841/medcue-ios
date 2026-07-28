import Foundation
import MedicationAdherenceCore
import UserNotifications
#if canImport(AlarmKit)
import AlarmKit
import SwiftUI
#endif

struct MedicationReminderPostCommitEntry: Sendable, Equatable {
    let taskID: UUID
    let medicationID: UUID
    let planID: UUID
    let medicationName: String
    let doseText: String
    let dueAt: Date
    let deliveryMethodRaw: String
    let escalatesToAlarmWhenUnhandled: Bool
}

struct MedicationReminderPostCommitPlan: Sendable, Equatable {
    let entries: [MedicationReminderPostCommitEntry]
    let taskIDsToCancel: [UUID]
}

struct MedicationReminderPostCommitSnapshot: Sendable, Equatable {
    let entries: [MedicationReminderPostCommitEntry]
    let cancelledTaskIDs: [UUID]

    @MainActor
    init(batch: MedicationReminderScheduleBatch) {
        let medicationName = userFacingMedicationName(for: batch.medication)
        entries = batch.tasks.map { task in
            MedicationReminderPostCommitEntry(
                taskID: task.id,
                medicationID: batch.medication.id,
                planID: task.planID,
                medicationName: medicationName,
                doseText: "\(task.doseValue.formatted()) \(localizedMedicationUnit(task.doseUnit))",
                dueAt: task.dueAt,
                deliveryMethodRaw: batch.deliveryMethod.rawValue,
                escalatesToAlarmWhenUnhandled: batch.escalatesToAlarmWhenUnhandled
            )
        }
        cancelledTaskIDs = batch.cancelledTaskIDs
    }

    func schedulingPlan(
        now: Date,
        maximumScheduledEntries: Int
    ) -> MedicationReminderPostCommitPlan {
        let futureEntries = entries
            .filter { $0.dueAt > now }
            .sorted { lhs, rhs in
                if lhs.dueAt != rhs.dueAt {
                    return lhs.dueAt < rhs.dueAt
                }
                return lhs.taskID.uuidString < rhs.taskID.uuidString
            }
        let scheduledEntries = Array(futureEntries.prefix(max(0, maximumScheduledEntries)))
        let unscheduledTaskIDs = entries
            .filter { entry in
                entry.dueAt <= now || !scheduledEntries.contains { $0.taskID == entry.taskID }
            }
            .map(\.taskID)
        let taskIDsToCancel = Array(Set(cancelledTaskIDs + unscheduledTaskIDs))
            .sorted { $0.uuidString < $1.uuidString }
        return MedicationReminderPostCommitPlan(
            entries: scheduledEntries,
            taskIDsToCancel: taskIDsToCancel
        )
    }
}

enum MedicationReminderPostCommitDispatcher {
    @MainActor
    static func dispatch(_ snapshot: MedicationReminderPostCommitSnapshot) {
        Task.detached(priority: .utility) {
            await MedicationReminderPostCommitScheduler.shared.apply(snapshot)
        }
    }
}

private actor MedicationReminderPostCommitScheduler {
    static let shared = MedicationReminderPostCommitScheduler()

    private let notificationPolicy = MedicationNotificationPolicy.default
    private let reminderPolicy = DoseReminderPolicy.competitionDemo
    private let notificationIdentifierPrefix = "dose."
    private let escalationIdentifierPrefix = "dose.escalation."

    func apply(_ snapshot: MedicationReminderPostCommitSnapshot) async {
        let plan = snapshot.schedulingPlan(
            now: Date(),
            maximumScheduledEntries: notificationPolicy.maximumScheduledEntries
        )
        cancel(taskIDs: plan.taskIDsToCancel)
        for entry in plan.entries {
            cancel(taskIDs: [entry.taskID])
            await scheduleNotification(for: entry)
            if entry.deliveryMethodRaw == StoredReminderDeliveryMethod.alarm.rawValue {
                _ = await scheduleAlarm(for: entry, id: entry.taskID, dueAt: entry.dueAt, titlePrefix: nil)
            }
            if entry.escalatesToAlarmWhenUnhandled {
                await scheduleEscalation(for: entry)
            }
        }
    }

    private func cancel(taskIDs: [UUID]) {
        guard !taskIDs.isEmpty else {
            return
        }
        let identifiers = taskIDs.flatMap { taskID in
            [notificationIdentifier(for: taskID), escalationIdentifier(for: taskID)]
        }
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
        center.removeDeliveredNotifications(withIdentifiers: identifiers)
        #if canImport(AlarmKit)
        if #available(iOS 26.0, *) {
            for taskID in taskIDs {
                try? AlarmManager.shared.cancel(id: taskID)
                try? AlarmManager.shared.stop(id: taskID)
                let escalationID = escalationAlarmID(for: taskID)
                try? AlarmManager.shared.cancel(id: escalationID)
                try? AlarmManager.shared.stop(id: escalationID)
            }
        }
        #endif
    }

    private func scheduleNotification(for entry: MedicationReminderPostCommitEntry) async {
        let content = notificationContent(
            title: "该服药了",
            body: "\(entry.medicationName) · \(entry.doseText)",
            entry: entry,
            reminderKind: nil
        )
        let request = UNNotificationRequest(
            identifier: notificationIdentifier(for: entry.taskID),
            content: content,
            trigger: calendarTrigger(for: entry.dueAt)
        )
        try? await UNUserNotificationCenter.current().add(request)
    }

    private func scheduleEscalation(for entry: MedicationReminderPostCommitEntry) async {
        let dueAt = reminderPolicy.escalationDueAt(for: entry.dueAt)
        guard dueAt > Date() else {
            return
        }
        if await scheduleAlarm(
            for: entry,
            id: escalationAlarmID(for: entry.taskID),
            dueAt: dueAt,
            titlePrefix: "仍未确认"
        ) {
            return
        }
        let content = notificationContent(
            title: "仍未确认服药",
            body: "\(entry.medicationName) · 请在 App 内确认已服用、稍后或忽略",
            entry: entry,
            reminderKind: "escalation"
        )
        let request = UNNotificationRequest(
            identifier: escalationIdentifier(for: entry.taskID),
            content: content,
            trigger: calendarTrigger(for: dueAt)
        )
        try? await UNUserNotificationCenter.current().add(request)
    }

    private func notificationContent(
        title: String,
        body: String,
        entry: MedicationReminderPostCommitEntry,
        reminderKind: String?
    ) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.categoryIdentifier = MedicationNotificationDelegate.categoryIdentifier
        var userInfo = [
            "scheduledDoseID": entry.taskID.uuidString,
            "medicationID": entry.medicationID.uuidString,
            "planID": entry.planID.uuidString
        ]
        if let reminderKind {
            userInfo["reminderKind"] = reminderKind
        }
        content.userInfo = userInfo
        return content
    }

    private func calendarTrigger(for date: Date) -> UNCalendarNotificationTrigger {
        let components = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: date
        )
        return UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
    }

    private func notificationIdentifier(for taskID: UUID) -> String {
        "\(notificationIdentifierPrefix)\(taskID.uuidString)"
    }

    private func escalationIdentifier(for taskID: UUID) -> String {
        "\(escalationIdentifierPrefix)\(taskID.uuidString)"
    }

    private func escalationAlarmID(for taskID: UUID) -> UUID {
        var rawUUID = taskID.uuid
        rawUUID.0 ^= 0x80
        return UUID(uuid: rawUUID)
    }

    private func scheduleAlarm(
        for entry: MedicationReminderPostCommitEntry,
        id: UUID,
        dueAt: Date,
        titlePrefix: String?
    ) async -> Bool {
        #if canImport(AlarmKit)
        if #available(iOS 26.0, *) {
            do {
                guard AlarmManager.shared.authorizationState == .authorized else {
                    return false
                }
                let baseTitle = "\(entry.medicationName) · \(entry.doseText)"
                let displayTitle = titlePrefix.map { "\($0)：\(baseTitle)" } ?? baseTitle
                let title = LocalizedStringResource(stringLiteral: displayTitle)
                let stopButton = AlarmButton(
                    text: titlePrefix == nil ? "完成" : "打开 App 确认",
                    textColor: .white,
                    systemImageName: "checkmark"
                )
                let presentation = AlarmPresentation(
                    alert: AlarmPresentation.Alert(title: title, stopButton: stopButton)
                )
                let attributes = AlarmAttributes<MedicationAlarmMetadata>(
                    presentation: presentation,
                    metadata: MedicationAlarmMetadata(
                        scheduledDoseID: entry.taskID,
                        medicationID: entry.medicationID,
                        planID: entry.planID
                    ),
                    tintColor: titlePrefix == nil ? .teal : .orange
                )
                let configuration = AlarmManager.AlarmConfiguration<MedicationAlarmMetadata>.alarm(
                    schedule: .fixed(dueAt),
                    attributes: attributes
                )
                _ = try await AlarmManager.shared.schedule(id: id, configuration: configuration)
                return true
            } catch {
                return false
            }
        }
        #endif
        return false
    }
}
