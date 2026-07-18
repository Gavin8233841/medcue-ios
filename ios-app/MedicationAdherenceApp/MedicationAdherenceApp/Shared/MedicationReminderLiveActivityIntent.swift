import Foundation

#if canImport(ActivityKit) && canImport(AppIntents)
import ActivityKit
import AppIntents

@available(iOS 17.0, *)
struct MarkMedicationReminderTakenIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "标记已完成"
    static var description = IntentDescription("在灵动岛中确认本次用药已处理。")
    static var openAppWhenRun = false

    @Parameter(title: "提醒 ID")
    var taskID: String

    init() {
        taskID = ""
    }

    init(taskID: UUID) {
        self.taskID = taskID.uuidString
    }

    func perform() async throws -> some IntentResult {
        guard let uuid = UUID(uuidString: taskID) else {
            return .result()
        }
        let now = Date()
        for activity in Activity<MedicationReminderActivityAttributes>.activities where activity.attributes.taskID == uuid {
            let completedState = MedicationReminderActivityAttributes.ContentState(
                dueAt: now,
                statusText: "已完成",
                completedAt: now
            )
            await activity.update(
                ActivityContent(
                    state: completedState,
                    staleDate: now.addingTimeInterval(60)
                )
            )
        }
        return .result()
    }
}
#endif
