import Foundation

#if canImport(ActivityKit) && canImport(AppIntents)
import ActivityKit
import AppIntents

enum MedicationReminderLiveActivityIntentExecutionOutcome: Sendable {
    case committed
    case alreadyCommitted
    case rejected
    case saveFailed
}

struct MedicationReminderLiveActivityIntentExecutor: Sendable {
    let execute: @MainActor @Sendable (
        MedicationReminderLiveActivityActionRequest,
        Date
    ) async -> MedicationReminderLiveActivityIntentExecutionOutcome
}

@available(iOS 17.0, *)
struct MarkMedicationReminderTakenIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "标记已完成"
    static let description = IntentDescription("在灵动岛中确认本次用药已处理。")
    static let openAppWhenRun = false

    @Parameter(title: "提醒 ID")
    var taskID: String

    @Parameter(title: "操作 ID")
    var operationID: String

    @Parameter(title: "有效截止时间")
    var expiresAt: Double

    @Dependency
    private var executor: MedicationReminderLiveActivityIntentExecutor

    init() {
        taskID = ""
        operationID = ""
        expiresAt = 0
    }

    init(taskID: UUID, operationID: UUID, expiresAt: Date) {
        self.taskID = taskID.uuidString
        self.operationID = operationID.uuidString
        self.expiresAt = expiresAt.timeIntervalSince1970
    }

    func perform() async throws -> some IntentResult {
        guard let taskID = UUID(uuidString: taskID),
              let operationID = UUID(uuidString: operationID)
        else {
            return .result()
        }
        let now = Date()
        let request = MedicationReminderLiveActivityActionRequest(
            taskID: taskID,
            action: .markTaken,
            operationID: operationID,
            expiresAt: Date(timeIntervalSince1970: expiresAt)
        )
        let outcome = await executor.execute(request, now)

        for activity in Activity<MedicationReminderActivityAttributes>.activities where activity.attributes.taskID == taskID {
            switch outcome {
            case .committed, .alreadyCommitted:
                let completedState = MedicationReminderActivityAttributes.ContentState(
                    dueAt: now,
                    statusText: "已完成",
                    completedAt: now
                )
                await activity.end(
                    ActivityContent(state: completedState, staleDate: nil),
                    dismissalPolicy: .after(now.addingTimeInterval(5))
                )
            case .saveFailed:
                let retryState = MedicationReminderActivityAttributes.ContentState(
                    dueAt: activity.content.state.dueAt,
                    statusText: "记录失败，请重试",
                    completedAt: nil
                )
                await activity.update(
                    ActivityContent(
                        state: retryState,
                        staleDate: activity.content.staleDate
                    )
                )
            case .rejected:
                let rejectedState = MedicationReminderActivityAttributes.ContentState(
                    dueAt: activity.content.state.dueAt,
                    statusText: "任务已关闭",
                    completedAt: nil
                )
                await activity.end(
                    ActivityContent(state: rejectedState, staleDate: nil),
                    dismissalPolicy: .after(now.addingTimeInterval(2))
                )
            }
        }
        return .result()
    }
}
#endif
