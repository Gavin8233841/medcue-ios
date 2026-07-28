import Foundation

enum DoseLogicalGroup {
    static func key(for task: StoredDoseTask) -> String {
        let minuteKey = Int(task.dueAt.timeIntervalSince1970 / 60)
        return [
            task.medicationID.uuidString,
            "\(minuteKey)",
            task.doseValue.formatted(),
            task.doseUnit
        ].joined(separator: "|")
    }

    static func group(containing task: StoredDoseTask, in tasks: [StoredDoseTask]) -> [StoredDoseTask] {
        let targetKey = key(for: task)
        return tasks
            .filter { $0.isAdherenceMeasurable && key(for: $0) == targetKey }
            .sorted { lhs, rhs in
                if lhs.id == task.id {
                    return true
                }
                if rhs.id == task.id {
                    return false
                }
                return lhs.id.uuidString < rhs.id.uuidString
            }
    }
}
