import Foundation

#if canImport(ActivityKit)
import ActivityKit
#endif

struct MedicationReminderActivityAttributes: Codable, Hashable {
    var taskID: UUID
    var medicationName: String
    var doseText: String
}

#if canImport(ActivityKit)
extension MedicationReminderActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var dueAt: Date
        var statusText: String
        var completedAt: Date?

        var isCompleted: Bool {
            completedAt != nil || statusText.contains("已完成") || statusText.contains("已处理")
        }
    }
}
#endif
