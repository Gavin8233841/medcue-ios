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
    static let title: LocalizedStringResource = "打开应用确认"
    static let description = IntentDescription("旧版实时活动操作已停用，请在应用内确认用药。")
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
        // Retain the type so an activity from an older build can deserialize,
        // but an intent without a proven unlock must never write a dose.
        return .result()
    }
}
#endif
