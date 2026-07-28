import Foundation
import MedicationAdherenceCore
import OSLog
import SwiftData

@MainActor
enum AppPersistenceCommitter {
    static let failureMessageDefaultsKey = "AppPersistenceCommitter.failureMessage"
    static let failureUserMessage = "更改未能可靠保存，已恢复到保存前状态。请重试。"
    private static let logger = Logger(
        subsystem: "com.gwyy.appcontest2026.medicationadherence",
        category: "Persistence"
    )

    @discardableResult
    static func save(
        _ modelContext: ModelContext,
        operation: StaticString = #function
    ) -> Bool {
        do {
            try modelContext.save()
            return true
        } catch {
            modelContext.rollback()
            reportFailure(operation: operation)
            return false
        }
    }

    static func reportFailure(operation: StaticString) {
        UserDefaults.standard.set(failureUserMessage, forKey: failureMessageDefaultsKey)
        logger.error("SwiftData save failed; rolled back operation=\(String(describing: operation), privacy: .public)")
    }
}

enum DoseActionPersistenceError: Error, Equatable {
    case saveFailed

    var userMessage: String {
        switch self {
        case .saveFailed:
            "用药记录未能保存，请重试。"
        }
    }
}

struct DoseActionTransition {
    let task: StoredDoseTask
    let action: DoseActionKind
    let newStatus: StoredDoseStatus
    let newDueAt: Date
    let newRecordedAt: Date?
    let newReason: String
    let occurredAt: Date
    let undoExpiresAt: Date
    let actionLogID: UUID

    init(
        task: StoredDoseTask,
        action: DoseActionKind,
        newStatus: StoredDoseStatus,
        newDueAt: Date,
        newRecordedAt: Date?,
        newReason: String,
        occurredAt: Date,
        undoExpiresAt: Date,
        actionLogID: UUID = UUID()
    ) {
        self.task = task
        self.action = action
        self.newStatus = newStatus
        self.newDueAt = newDueAt
        self.newRecordedAt = newRecordedAt
        self.newReason = newReason
        self.occurredAt = occurredAt
        self.undoExpiresAt = undoExpiresAt
        self.actionLogID = actionLogID
    }
}

enum DoseActionMutation: Equatable {
    case markTaken
    case delay
    case skip

    var actionKind: DoseActionKind {
        switch self {
        case .markTaken:
            .markTaken
        case .delay:
            .delay
        case .skip:
            .skip
        }
    }

    var newStatus: StoredDoseStatus {
        switch self {
        case .markTaken:
            .taken
        case .delay:
            .delayed
        case .skip:
            .skipped
        }
    }
}

struct DoseActionTransitionPlanner {
    static let undoWindow: TimeInterval = 10 * 60

    func makeTransitions(
        mutation: DoseActionMutation,
        taskGroup: [StoredDoseTask],
        primaryTask: StoredDoseTask,
        occurredAt: Date,
        primaryReason: String,
        mergedReason: String,
        primaryActionLogID: UUID = UUID()
    ) -> [DoseActionTransition] {
        let delayedDueAt = DoseDelayPolicy.delayedDueAtFromPlannedTime(primaryTask.dueAt)
        return taskGroup.map { task in
            DoseActionTransition(
                task: task,
                action: mutation.actionKind,
                newStatus: mutation.newStatus,
                newDueAt: mutation == .delay ? delayedDueAt : task.dueAt,
                newRecordedAt: occurredAt,
                newReason: task.id == primaryTask.id ? primaryReason : mergedReason,
                occurredAt: occurredAt,
                undoExpiresAt: occurredAt.addingTimeInterval(Self.undoWindow),
                actionLogID: task.id == primaryTask.id ? primaryActionLogID : UUID()
            )
        }
    }
}

@MainActor
struct DoseActionPersistence {
    static let failureMessageDefaultsKey = "DoseActionPersistence.failureMessage"

    typealias SaveOperation = (ModelContext) throws -> Void

    private let saveOperation: SaveOperation

    init(_ saveOperation: @escaping SaveOperation = { try $0.save() }) {
        self.saveOperation = saveOperation
    }

    @discardableResult
    func commit(
        _ transitions: [DoseActionTransition],
        in modelContext: ModelContext
    ) throws -> [StoredDoseActionLog] {
        guard !transitions.isEmpty else {
            return []
        }

        let snapshots = transitions.map(DoseTaskStateSnapshot.init)
        let logs = transitions.map { transition in
            StoredDoseActionLog(
                id: transition.actionLogID,
                taskID: transition.task.id,
                action: transition.action,
                previousStatus: transition.task.status,
                previousDueAt: transition.task.dueAt,
                previousRecordedAt: transition.task.recordedAt,
                previousReason: transition.task.reason,
                newStatus: transition.newStatus,
                occurredAt: transition.occurredAt,
                undoExpiresAt: transition.undoExpiresAt,
                note: transition.newReason
            )
        }

        for (transition, log) in zip(transitions, logs) {
            modelContext.insert(log)
            transition.task.status = transition.newStatus
            transition.task.dueAt = transition.newDueAt
            transition.task.recordedAt = transition.newRecordedAt
            transition.task.reason = transition.newReason
        }

        do {
            try saveOperation(modelContext)
            return logs
        } catch {
            for snapshot in snapshots {
                snapshot.restore()
            }
            for log in logs {
                modelContext.delete(log)
            }
            modelContext.rollback()
            throw DoseActionPersistenceError.saveFailed
        }
    }
}

private struct DoseTaskStateSnapshot {
    let task: StoredDoseTask
    let status: StoredDoseStatus
    let dueAt: Date
    let recordedAt: Date?
    let reason: String

    init(_ transition: DoseActionTransition) {
        task = transition.task
        status = transition.task.status
        dueAt = transition.task.dueAt
        recordedAt = transition.task.recordedAt
        reason = transition.task.reason
    }

    func restore() {
        task.status = status
        task.dueAt = dueAt
        task.recordedAt = recordedAt
        task.reason = reason
    }
}
