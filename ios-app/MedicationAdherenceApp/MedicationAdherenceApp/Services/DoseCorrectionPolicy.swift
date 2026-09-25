import Foundation
import MedicationAdherenceCore
import SwiftData

enum DoseCorrectionPolicy {
    static func taskReasonForSavedStatus(
        previousStatus: StoredDoseStatus,
        newStatus: StoredDoseStatus,
        trimmedNote: String
    ) -> String {
        if newStatus == .pending {
            return ""
        }
        if newStatus != previousStatus && isSystemGeneratedRecordNote(trimmedNote) {
            return ""
        }
        return trimmedNote
    }

    static func isSystemGeneratedRecordNote(_ text: String) -> Bool {
        if LegacyAutoSkipRecordMarker.matches(text) {
            return true
        }
        return [
            "未来提醒已停用",
            "用户撤销后等待确认",
            "用户将已处理记录撤销为待处理",
            "同一剂量重复提醒已随本次记录修正合并"
        ].contains { marker in
            text.contains(marker)
        }
    }
}

enum LegacyAutoSkipRepairError: Error, Equatable {
    case saveFailed
}

struct LegacyAutoSkipRepairResult: Equatable {
    let correctedTaskIDs: [UUID]

    var correctedCount: Int {
        correctedTaskIDs.count
    }
}

@MainActor
struct LegacyAutoSkipRepairCommand {
    static let auditNote = "系统曾把未操作记录为忽略；现已审计修正为未确认，未推断用户行为。"

    typealias SaveOperation = (ModelContext) throws -> Void

    private let saveOperation: SaveOperation

    init(saveOperation: @escaping SaveOperation = { try $0.save() }) {
        self.saveOperation = saveOperation
    }

    func perform(
        in modelContext: ModelContext,
        occurredAt: Date = Date()
    ) throws -> LegacyAutoSkipRepairResult {
        let tasks = try modelContext.fetch(FetchDescriptor<StoredDoseTask>())
        let logs = try modelContext.fetch(FetchDescriptor<StoredDoseActionLog>())
        let tasksByID = Dictionary(uniqueKeysWithValues: tasks.map { ($0.id, $0) })
        let eligibleLogs = logs
            .filter(isEligibleLegacyLog)
            .sorted { lhs, rhs in
                if lhs.occurredAt != rhs.occurredAt {
                    return lhs.occurredAt > rhs.occurredAt
                }
                return lhs.id.uuidString > rhs.id.uuidString
            }

        var selectedTaskIDs = Set<UUID>()
        var repairs: [(task: StoredDoseTask, log: StoredDoseActionLog)] = []
        for log in eligibleLogs {
            guard !selectedTaskIDs.contains(log.taskID),
                  let task = tasksByID[log.taskID],
                  taskMatchesCurrentLegacyState(task, log: log)
            else {
                continue
            }
            selectedTaskIDs.insert(log.taskID)
            repairs.append((task, log))
        }

        guard !repairs.isEmpty else {
            return LegacyAutoSkipRepairResult(correctedTaskIDs: [])
        }

        let taskSnapshots = repairs.map { LegacyAutoSkipTaskSnapshot(task: $0.task) }
        let logSnapshots = repairs.map { LegacyAutoSkipLogSnapshot(log: $0.log) }
        var correctionLogs: [StoredDoseActionLog] = []

        for repair in repairs {
            let task = repair.task
            let legacyLog = repair.log
            let correctionLog = StoredDoseActionLog(
                taskID: task.id,
                action: .correct,
                previousStatus: task.status,
                previousDueAt: task.dueAt,
                previousRecordedAt: task.recordedAt,
                previousReason: task.reason,
                newStatus: legacyLog.previousStatus,
                occurredAt: occurredAt,
                undoExpiresAt: occurredAt.addingTimeInterval(-1),
                note: Self.auditNote
            )

            legacyLog.undoneAt = occurredAt
            task.status = legacyLog.previousStatus
            task.dueAt = legacyLog.previousDueAt
            task.recordedAt = legacyLog.previousRecordedAt
            task.reason = LegacyAutoSkipRecordMarker.restoredTaskReason(
                previousReason: legacyLog.previousReason,
                currentReason: task.reason,
                logNote: legacyLog.note
            )
            modelContext.insert(correctionLog)
            correctionLogs.append(correctionLog)
        }

        do {
            try saveOperation(modelContext)
            return LegacyAutoSkipRepairResult(
                correctedTaskIDs: repairs.map(\.task.id).sorted { $0.uuidString < $1.uuidString }
            )
        } catch {
            taskSnapshots.forEach { $0.restore() }
            logSnapshots.forEach { $0.restore() }
            correctionLogs.forEach(modelContext.delete)
            modelContext.rollback()
            throw LegacyAutoSkipRepairError.saveFailed
        }
    }

    private func isEligibleLegacyLog(_ log: StoredDoseActionLog) -> Bool {
        guard log.undoneAt == nil,
              log.actionRaw == DoseActionKind.skip.rawValue,
              log.newStatusRaw == StoredDoseStatus.skipped.rawValue,
              let previousStatus = StoredDoseStatus(rawValue: log.previousStatusRaw),
              previousStatus == .pending || previousStatus == .delayed
        else {
            return false
        }
        return LegacyAutoSkipRecordMarker.matches(log.note)
    }

    private func taskMatchesCurrentLegacyState(
        _ task: StoredDoseTask,
        log: StoredDoseActionLog
    ) -> Bool {
        task.status == .skipped
            && task.dueAt == log.previousDueAt
            && task.recordedAt == log.occurredAt
            && LegacyAutoSkipRecordMarker.matchesCurrentTaskReason(task.reason, for: log.note)
    }
}

private struct LegacyAutoSkipTaskSnapshot {
    let task: StoredDoseTask
    let status: StoredDoseStatus
    let dueAt: Date
    let recordedAt: Date?
    let reason: String

    init(task: StoredDoseTask) {
        self.task = task
        status = task.status
        dueAt = task.dueAt
        recordedAt = task.recordedAt
        reason = task.reason
    }

    func restore() {
        task.status = status
        task.dueAt = dueAt
        task.recordedAt = recordedAt
        task.reason = reason
    }
}

private struct LegacyAutoSkipLogSnapshot {
    let log: StoredDoseActionLog
    let undoneAt: Date?

    init(log: StoredDoseActionLog) {
        self.log = log
        undoneAt = log.undoneAt
    }

    func restore() {
        log.undoneAt = undoneAt
    }
}
