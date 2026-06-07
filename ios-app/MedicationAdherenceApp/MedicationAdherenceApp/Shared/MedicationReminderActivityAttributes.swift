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
    }
}
#endif
