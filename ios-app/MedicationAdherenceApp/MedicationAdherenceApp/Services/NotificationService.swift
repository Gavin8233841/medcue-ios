import Foundation
import MedicationAdherenceCore
import UserNotifications
#if canImport(AlarmKit)
import AlarmKit
import SwiftUI
#endif

@MainActor
final class NotificationService: ObservableObject {
    @Published private(set) var authorizationMessage = "尚未请求通知权限"

    func requestAuthorization() async {
        do {
            let granted = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
            authorizationMessage = granted ? "通知权限已开启" : "通知权限未开启"
        } catch {
            authorizationMessage = "通知权限请求失败：\(error.localizedDescription)"
        }
    }

    func scheduleReminder(
        for task: StoredDoseTask,
        medication: StoredMedication,
        deliveryMethod: StoredReminderDeliveryMethod = .notification
    ) async {
        if deliveryMethod == .alarm {
            let didScheduleAlarm = await scheduleAlarmReminder(for: task, medication: medication)
            if didScheduleAlarm {
                return
            }
        }
        await scheduleNotificationReminder(for: task, medication: medication)
    }

    private func scheduleNotificationReminder(for task: StoredDoseTask, medication: StoredMedication) async {
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
        content.userInfo = [
            "scheduledDoseID": payload.scheduledDoseID.uuidString,
            "medicationID": payload.medicationID.uuidString,
            "planID": payload.planID.uuidString
        ]

        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: task.dueAt)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let request = UNNotificationRequest(identifier: "dose.\(task.id.uuidString)", content: content, trigger: trigger)
        do {
            try await UNUserNotificationCenter.current().add(request)
            authorizationMessage = "已安排下一次本地提醒"
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
}

#if canImport(AlarmKit)
@available(iOS 26.0, *)
private struct MedicationAlarmMetadata: AlarmMetadata {
    let scheduledDoseID: UUID
    let medicationID: UUID
    let planID: UUID
}
#endif
