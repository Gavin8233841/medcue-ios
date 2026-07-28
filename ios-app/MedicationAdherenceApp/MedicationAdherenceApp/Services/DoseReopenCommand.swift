import Foundation
import MedicationAdherenceCore
import SwiftData

enum DoseReopenMode: Equatable {
    case restoredAction
    case reopenedHandledDose
}

struct DoseReopenTaskState: Equatable {
    let taskID: UUID
    let status: StoredDoseStatus
    let dueAt: Date
    let recordedAt: Date?
    let reason: String
}

struct DoseReopenRollbackToken: Equatable {
    let primaryTaskID: UUID
    let taskStates: [DoseReopenTaskState]
    let reactivatedActionLogIDs: [UUID]
    let closedActionLogIDs: [UUID]
}

struct DoseReopenCommit: Equatable {
    let mode: DoseReopenMode
    let taskIDs: [UUID]
    let rollbackToken: DoseReopenRollbackToken
}

enum DoseReopenRejection: Equatable {
    case taskNotFound
    case readFailed
    case alreadyOpen
}

enum DoseReopenCommandOutcome: Equatable {
    case committed(DoseReopenCommit)
    case rejected(DoseReopenRejection)
    case saveFailed
}

enum DoseReopenRollbackRejection: Equatable {
    case readFailed
    case taskNotFound
}

enum DoseReopenRollbackOutcome: Equatable {
    case committed([UUID])
    case rejected(DoseReopenRollbackRejection)
    case saveFailed
}

@MainActor
struct DoseReopenCommand {
    typealias SaveOperation = (ModelContext) throws -> Void

    private static let archiveMarker = "用户已归档"
    private static let reopenNote = "用户撤销后等待确认"
    private let modelContext: ModelContext
    private let saveOperation: SaveOperation
    private let reminderPolicy = DoseReminderPolicy.competitionDemo

    init(
        modelContext: ModelContext,
        saveOperation: @escaping SaveOperation = { try $0.save() }
    ) {
        self.modelContext = modelContext
        self.saveOperation = saveOperation
    }

    func perform(taskID: UUID, at occurredAt: Date) -> DoseReopenCommandOutcome {
        let primaryTask: StoredDoseTask
        do {
            guard let storedTask = try fetchTask(id: taskID) else {
                return .rejected(.taskNotFound)
            }
            primaryTask = storedTask
        } catch {
            return .rejected(.readFailed)
        }

        guard !Self.isOpen(primaryTask.status) else {
            return .rejected(.alreadyOpen)
        }

        let group: [StoredDoseTask]
        let actionLogs: [StoredDoseActionLog]
        do {
            group = try fetchLogicalGroup(containing: primaryTask)
            actionLogs = try fetchActionLogs(taskIDs: Set(group.map(\.id)))
        } catch {
            return .rejected(.readFailed)
        }

        let snapshots = group.map(Self.snapshot)
        if let primaryLog = actionLogs.first(where: {
            $0.taskID == primaryTask.id && Self.isUndoable($0, at: occurredAt)
        }) {
            return restoreLatestAction(
                primaryTask: primaryTask,
                group: group,
                actionLogs: actionLogs,
                primaryLog: primaryLog,
                snapshots: snapshots,
                occurredAt: occurredAt
            )
        }

        return reopenHandledDose(
            primaryTask: primaryTask,
            group: group,
            snapshots: snapshots,
            occurredAt: occurredAt
        )
    }

    func rollback(
        _ token: DoseReopenRollbackToken,
        at occurredAt: Date
    ) -> DoseReopenRollbackOutcome {
        let taskIDs = Set(token.taskStates.map(\.taskID))
        let logIDs = Set(token.reactivatedActionLogIDs + token.closedActionLogIDs)
        let tasks: [StoredDoseTask]
        let logs: [StoredDoseActionLog]
        do {
            tasks = try fetchTasks(ids: taskIDs)
            logs = try fetchActionLogs(ids: logIDs)
        } catch {
            return .rejected(.readFailed)
        }
        guard tasks.count == taskIDs.count else {
            return .rejected(.taskNotFound)
        }

        let currentTaskStates = tasks.map(Self.snapshot)
        let currentLogStates = logs.map { ($0, $0.undoneAt) }
        let tasksByID = Dictionary(uniqueKeysWithValues: tasks.map { ($0.id, $0) })
        let reactivatedIDs = Set(token.reactivatedActionLogIDs)
        let closedIDs = Set(token.closedActionLogIDs)

        for state in token.taskStates {
            guard let task = tasksByID[state.taskID] else { continue }
            Self.restore(task, from: state)
        }
        for log in logs {
            if reactivatedIDs.contains(log.id) {
                log.undoneAt = nil
            } else if closedIDs.contains(log.id) {
                log.undoneAt = occurredAt
            }
        }

        do {
            try saveOperation(modelContext)
            return .committed(token.taskStates.map(\.taskID))
        } catch {
            Self.restoreTasks(tasksByID: tasksByID, states: currentTaskStates)
            currentLogStates.forEach { $0.0.undoneAt = $0.1 }
            modelContext.rollback()
            AppPersistenceCommitter.reportFailure(operation: "today-reopen-dose-rollback")
            return .saveFailed
        }
    }

    private func restoreLatestAction(
        primaryTask: StoredDoseTask,
        group: [StoredDoseTask],
        actionLogs: [StoredDoseActionLog],
        primaryLog: StoredDoseActionLog,
        snapshots: [DoseReopenTaskState],
        occurredAt: Date
    ) -> DoseReopenCommandOutcome {
        var matchingLogsByTaskID: [UUID: StoredDoseActionLog] = [:]
        for task in group {
            if let matchingLog = actionLogs.first(where: {
                $0.taskID == task.id
                    && Self.isUndoable($0, at: occurredAt)
                    && $0.actionRaw == primaryLog.actionRaw
                    && Self.isSameMinute($0.previousDueAt, primaryLog.previousDueAt)
            }) {
                matchingLogsByTaskID[task.id] = matchingLog
            }
        }

        for task in group {
            let snapshotLog = matchingLogsByTaskID[task.id] ?? primaryLog
            task.status = snapshotLog.previousStatus
            task.dueAt = snapshotLog.previousDueAt
            task.recordedAt = snapshotLog.previousRecordedAt
            task.reason = reopenedReason(
                previousReason: snapshotLog.previousReason,
                status: snapshotLog.previousStatus,
                previousDueAt: snapshotLog.previousDueAt,
                reopenedAt: occurredAt
            )
        }
        let reactivatedLogs = matchingLogsByTaskID.values.sorted(by: Self.logOrder)
        reactivatedLogs.forEach { $0.undoneAt = occurredAt }

        let token = DoseReopenRollbackToken(
            primaryTaskID: primaryTask.id,
            taskStates: snapshots,
            reactivatedActionLogIDs: reactivatedLogs.map(\.id),
            closedActionLogIDs: []
        )
        return save(
            mode: .restoredAction,
            group: group,
            originalStates: snapshots,
            insertedLogs: [],
            changedLogs: reactivatedLogs,
            rollbackToken: token,
            operation: "today-restore-dose-action"
        )
    }

    private func reopenHandledDose(
        primaryTask: StoredDoseTask,
        group: [StoredDoseTask],
        snapshots: [DoseReopenTaskState],
        occurredAt: Date
    ) -> DoseReopenCommandOutcome {
        let reopenLogs = group.map { task in
            StoredDoseActionLog(
                taskID: task.id,
                action: .correct,
                previousStatus: task.status,
                previousDueAt: task.dueAt,
                previousRecordedAt: task.recordedAt,
                previousReason: task.reason,
                newStatus: .pending,
                occurredAt: occurredAt,
                undoExpiresAt: occurredAt.addingTimeInterval(10 * 60),
                note: task.id == primaryTask.id
                    ? "用户将已处理记录撤销为待处理"
                    : "同一剂量重复提醒已随本次撤销操作合并；用户将已处理记录撤销为待处理"
            )
        }
        reopenLogs.forEach(modelContext.insert)
        for task in group {
            task.status = .pending
            task.recordedAt = nil
            task.reason = reopenedReason(
                previousReason: "",
                status: .pending,
                previousDueAt: task.dueAt,
                reopenedAt: occurredAt
            )
        }

        let token = DoseReopenRollbackToken(
            primaryTaskID: primaryTask.id,
            taskStates: snapshots,
            reactivatedActionLogIDs: [],
            closedActionLogIDs: reopenLogs.map(\.id).sorted { $0.uuidString < $1.uuidString }
        )
        return save(
            mode: .reopenedHandledDose,
            group: group,
            originalStates: snapshots,
            insertedLogs: reopenLogs,
            changedLogs: [],
            rollbackToken: token,
            operation: "today-reopen-dose"
        )
    }

    private func save(
        mode: DoseReopenMode,
        group: [StoredDoseTask],
        originalStates: [DoseReopenTaskState],
        insertedLogs: [StoredDoseActionLog],
        changedLogs: [StoredDoseActionLog],
        rollbackToken: DoseReopenRollbackToken,
        operation: StaticString
    ) -> DoseReopenCommandOutcome {
        let previousUndoneDates = Dictionary(
            uniqueKeysWithValues: changedLogs.map { ($0.id, Optional<Date>.none) }
        )
        do {
            try saveOperation(modelContext)
            return .committed(
                DoseReopenCommit(
                    mode: mode,
                    taskIDs: group.map(\.id),
                    rollbackToken: rollbackToken
                )
            )
        } catch {
            let tasksByID = Dictionary(uniqueKeysWithValues: group.map { ($0.id, $0) })
            Self.restoreTasks(tasksByID: tasksByID, states: originalStates)
            for log in changedLogs {
                log.undoneAt = previousUndoneDates[log.id] ?? nil
            }
            insertedLogs.forEach(modelContext.delete)
            modelContext.rollback()
            AppPersistenceCommitter.reportFailure(operation: operation)
            return .saveFailed
        }
    }

    private func fetchTask(id: UUID) throws -> StoredDoseTask? {
        var descriptor = FetchDescriptor<StoredDoseTask>(
            predicate: #Predicate<StoredDoseTask> { task in
                task.id == id
            }
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    private func fetchLogicalGroup(containing primaryTask: StoredDoseTask) throws -> [StoredDoseTask] {
        let medicationID = primaryTask.medicationID
        let minuteStart = Date(
            timeIntervalSince1970: floor(primaryTask.dueAt.timeIntervalSince1970 / 60) * 60
        )
        let minuteEnd = minuteStart.addingTimeInterval(60)
        let nearbyTasks = try modelContext.fetch(
            FetchDescriptor<StoredDoseTask>(
                predicate: #Predicate<StoredDoseTask> { task in
                    task.medicationID == medicationID
                        && task.dueAt >= minuteStart
                        && task.dueAt < minuteEnd
                }
            )
        )
        let group = DoseLogicalGroup.group(containing: primaryTask, in: nearbyTasks)
        return group.isEmpty ? [primaryTask] : group
    }

    private func fetchTasks(ids: Set<UUID>) throws -> [StoredDoseTask] {
        guard !ids.isEmpty else { return [] }
        return try modelContext.fetch(
            FetchDescriptor<StoredDoseTask>(
                predicate: #Predicate<StoredDoseTask> { task in
                    ids.contains(task.id)
                }
            )
        )
    }

    private func fetchActionLogs(taskIDs: Set<UUID>) throws -> [StoredDoseActionLog] {
        guard !taskIDs.isEmpty else { return [] }
        return try modelContext.fetch(
            FetchDescriptor<StoredDoseActionLog>(
                predicate: #Predicate<StoredDoseActionLog> { log in
                    taskIDs.contains(log.taskID)
                },
                sortBy: [SortDescriptor(\.occurredAt, order: .reverse)]
            )
        )
    }

    private func fetchActionLogs(ids: Set<UUID>) throws -> [StoredDoseActionLog] {
        guard !ids.isEmpty else { return [] }
        return try modelContext.fetch(
            FetchDescriptor<StoredDoseActionLog>(
                predicate: #Predicate<StoredDoseActionLog> { log in
                    ids.contains(log.id)
                }
            )
        )
    }

    private func reopenedReason(
        previousReason: String,
        status: StoredDoseStatus,
        previousDueAt: Date,
        reopenedAt: Date
    ) -> String {
        let baseReason = previousReason
            .split(separator: "；")
            .map(String.init)
            .filter { $0 != Self.archiveMarker }
            .joined(separator: "；")
        guard Self.isOpen(status),
              previousDueAt.addingTimeInterval(reminderPolicy.autoSkipInterval) <= reopenedAt
        else {
            return baseReason
        }
        if baseReason.isEmpty {
            return Self.reopenNote
        }
        if baseReason.contains(Self.reopenNote) {
            return baseReason
        }
        return [baseReason, Self.reopenNote].joined(separator: "；")
    }

    private static func snapshot(_ task: StoredDoseTask) -> DoseReopenTaskState {
        DoseReopenTaskState(
            taskID: task.id,
            status: task.status,
            dueAt: task.dueAt,
            recordedAt: task.recordedAt,
            reason: task.reason
        )
    }

    private static func restore(_ task: StoredDoseTask, from state: DoseReopenTaskState) {
        task.status = state.status
        task.dueAt = state.dueAt
        task.recordedAt = state.recordedAt
        task.reason = state.reason
    }

    private static func restoreTasks(
        tasksByID: [UUID: StoredDoseTask],
        states: [DoseReopenTaskState]
    ) {
        for state in states {
            guard let task = tasksByID[state.taskID] else { continue }
            restore(task, from: state)
        }
    }

    private static func isUndoable(_ log: StoredDoseActionLog, at date: Date) -> Bool {
        log.undoneAt == nil
            && date <= log.undoExpiresAt
            && log.actionRaw != DoseActionKind.archiveToday.rawValue
            && log.actionRaw != DoseActionKind.restoreArchive.rawValue
    }

    private static func isSameMinute(_ lhs: Date, _ rhs: Date) -> Bool {
        Int(lhs.timeIntervalSince1970 / 60) == Int(rhs.timeIntervalSince1970 / 60)
    }

    private static func isOpen(_ status: StoredDoseStatus) -> Bool {
        status == .pending || status == .delayed
    }

    private static func logOrder(_ lhs: StoredDoseActionLog, _ rhs: StoredDoseActionLog) -> Bool {
        if lhs.occurredAt == rhs.occurredAt {
            return lhs.id.uuidString < rhs.id.uuidString
        }
        return lhs.occurredAt > rhs.occurredAt
    }
}
