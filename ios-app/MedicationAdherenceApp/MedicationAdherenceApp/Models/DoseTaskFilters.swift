import Foundation
import MedicationAdherenceCore

extension StoredDoseTask {
    var isSystemDisabledFutureReminder: Bool {
        status == .skipped && reason.contains("未来提醒已停用")
    }

    var isUserAdherenceRecord: Bool {
        !isSystemDisabledFutureReminder
    }

    var isAutoSkippedByReminderSettlement: Bool {
        status == .skipped && reason.contains("自动记录为忽略")
    }

    var effectiveAdherenceRecordedAt: Date? {
        if isAutoSkippedByReminderSettlement {
            return DoseReminderPolicy.competitionDemo.autoSkipRecordedAt(for: dueAt)
        }
        return recordedAt
    }

    var effectiveAdherenceDate: Date {
        effectiveAdherenceRecordedAt ?? dueAt
    }

    var coreDoseEventUsingEffectiveAdherenceDate: DoseEvent? {
        guard let coreStatus = status.coreStatus else {
            return nil
        }
        return DoseEvent(
            scheduledDoseID: id,
            status: coreStatus,
            recordedAt: effectiveAdherenceRecordedAt ?? dueAt,
            reason: reason.isEmpty ? nil : reason
        )
    }

    var isAdherenceMeasurable: Bool {
        isUserAdherenceRecord
    }
}

extension Collection where Element == StoredDoseTask {
    var adherenceMeasurableTasks: [StoredDoseTask] {
        deduplicatedLogicalDoses(from: filter(\.isAdherenceMeasurable))
    }

    private func deduplicatedLogicalDoses(from tasks: [StoredDoseTask]) -> [StoredDoseTask] {
        var chosenTasks: [String: StoredDoseTask] = [:]
        for task in tasks {
            let key = logicalDoseKey(for: task)
            if let current = chosenTasks[key] {
                chosenTasks[key] = preferredLogicalDose(current, task)
            } else {
                chosenTasks[key] = task
            }
        }
        return chosenTasks.values.sorted { lhs, rhs in
            if lhs.dueAt != rhs.dueAt {
                return lhs.dueAt < rhs.dueAt
            }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }

    private func logicalDoseKey(for task: StoredDoseTask) -> String {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: task.dueAt)
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

    private func preferredLogicalDose(_ lhs: StoredDoseTask, _ rhs: StoredDoseTask) -> StoredDoseTask {
        let lhsScore = logicalDosePreferenceScore(lhs)
        let rhsScore = logicalDosePreferenceScore(rhs)
        if lhsScore != rhsScore {
            return lhsScore > rhsScore ? lhs : rhs
        }

        let lhsReferenceDate = lhs.effectiveAdherenceDate
        let rhsReferenceDate = rhs.effectiveAdherenceDate
        if lhsReferenceDate != rhsReferenceDate {
            return lhsReferenceDate > rhsReferenceDate ? lhs : rhs
        }

        return lhs.id.uuidString < rhs.id.uuidString ? lhs : rhs
    }

    private func logicalDosePreferenceScore(_ task: StoredDoseTask) -> Int {
        var score: Int
        switch task.status {
        case .taken, .corrected:
            score = 500
        case .delayed:
            score = 420
        case .skipped:
            score = 380
        case .pending:
            score = 300
        }
        if task.recordedAt != nil {
            score += 40
        }
        if !task.reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            score += 10
        }
        return score
    }
}
