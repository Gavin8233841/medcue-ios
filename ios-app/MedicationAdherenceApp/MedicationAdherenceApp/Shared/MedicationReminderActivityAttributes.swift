import Foundation

#if canImport(ActivityKit)
import ActivityKit
#endif

/// The controlled-device Beta sends only generic text to iPhone system surfaces.
/// This policy has no per-user override, including for existing installations.
enum MedicationSystemSurfacePrivacyPolicy {
    static let reminderTitle = "用药提醒"
    static let escalationTitle = "用药提醒待确认"
    static let reminderBody = "请打开 App 查看并确认本次提醒。"
    static let completedTitle = "提醒已结束"

    static func activityAttributes(taskID: UUID) -> MedicationReminderActivityAttributes {
        MedicationReminderActivityAttributes(
            taskID: taskID,
            medicationName: reminderTitle,
            doseText: ""
        )
    }
}

struct MedicationReminderActivityAttributes: Codable, Hashable {
    var taskID: UUID
    var medicationName: String
    var doseText: String
    var actionOperationID: UUID?

    init(
        taskID: UUID,
        medicationName: String,
        doseText: String,
        actionOperationID: UUID = UUID()
    ) {
        self.taskID = taskID
        self.medicationName = medicationName
        self.doseText = doseText
        self.actionOperationID = actionOperationID
    }
}

#if canImport(ActivityKit)
extension MedicationReminderActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        enum Phase: String, Codable, Hashable {
            case open
            case completed
        }

        var dueAt: Date
        var statusText: String
        var completedAt: Date?
        /// Missing only when decoding an activity created before semantic phases existed.
        var phase: Phase?

        init(dueAt: Date, statusText: String, completedAt: Date?, phase: Phase) {
            self.dueAt = dueAt
            self.statusText = statusText
            self.completedAt = completedAt
            self.phase = phase
        }

        var isCompleted: Bool {
            if let phase {
                return phase == .completed
            }
            // Older ActivityKit payloads had no phase. Read their Chinese
            // marker without writing or reclassifying the stored payload.
            return completedAt != nil || statusText.contains("已完成") || statusText.contains("已处理")
        }
    }
}
#endif
