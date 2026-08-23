import Foundation
import MedicationAdherenceCore

enum LegacyAutoSkipRecordMarker {
    private static let archiveMarker = "用户已归档"
    static let overdue = "超过计划时间 15 分钟未确认，已自动记录为忽略。"
    static let reopened = "撤销后超过 15 分钟仍未重新确认，已自动记录为忽略。"
    static let mergedDuplicate = "同一剂量重复提醒已随本次自动忽略合并。"

    static func matches(_ note: String) -> Bool {
        note == overdue || note == reopened || note == mergedDuplicate
    }

    static func matchesCurrentTaskReason(_ reason: String, for logNote: String) -> Bool {
        reason == logNote || reason == [logNote, archiveMarker].joined(separator: "；")
    }
}

extension StoredDoseTask {
    var isSystemDisabledFutureReminder: Bool {
        status == .skipped && reason.contains("未来提醒已停用")
    }

    var isUserAdherenceRecord: Bool {
        !isSystemDisabledFutureReminder
    }

    var isAutoSkippedByReminderSettlement: Bool {
        status == .skipped && LegacyAutoSkipRecordMarker.matches(reason)
    }

    var effectiveAdherenceRecordedAt: Date? {
        recordedAt
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
