import Foundation
import MedicationAdherenceCore
import SwiftData
import Testing
@testable import MedicationAdherenceApp

@Suite(.serialized)
struct DoseReopenCommandTests {
    @Test @MainActor
    func undoableLogicalDoseRestoresEveryTaskAndClosesLogs() throws {
        let fixture = try DoseReopenFixture()

        let outcome = DoseReopenCommand(modelContext: fixture.context).perform(
            taskID: fixture.primaryTask.id,
            at: fixture.now
        )

        guard case let .committed(commit) = outcome else {
            Issue.record("Expected reopen to commit")
            return
        }
        #expect(commit.mode == .restoredAction)
        #expect(Set(commit.taskIDs) == Set(fixture.group.map(\.id)))
        #expect(fixture.group.allSatisfy { $0.status == .pending && $0.recordedAt == nil })
        #expect(fixture.logs.allSatisfy { $0.undoneAt == fixture.now })
        #expect(commit.rollbackToken.reactivatedActionLogIDs.count == 2)
        #expect(!fixture.context.hasChanges)
    }

    @Test @MainActor
    func handledDoseWithoutUndoWindowCreatesReopenAuditLogs() throws {
        let fixture = try DoseReopenFixture(undoIsAvailable: false)

        let outcome = DoseReopenCommand(modelContext: fixture.context).perform(
            taskID: fixture.primaryTask.id,
            at: fixture.now
        )

        guard case let .committed(commit) = outcome else {
            Issue.record("Expected handled dose to reopen")
            return
        }
        #expect(commit.mode == .reopenedHandledDose)
        #expect(fixture.group.allSatisfy { $0.status == .pending && $0.recordedAt == nil })
        #expect(commit.rollbackToken.closedActionLogIDs.count == 2)
        let newLogIDs = Set(commit.rollbackToken.closedActionLogIDs)
        let persistedLogs = try fixture.context.fetch(FetchDescriptor<StoredDoseActionLog>())
        #expect(persistedLogs.filter { newLogIDs.contains($0.id) }.count == 2)
    }

    @Test @MainActor
    func repeatedReopenIsRejectedWithoutAdditionalLogs() throws {
        let fixture = try DoseReopenFixture(undoIsAvailable: false)
        let command = DoseReopenCommand(modelContext: fixture.context)
        guard case .committed = command.perform(taskID: fixture.primaryTask.id, at: fixture.now) else {
            Issue.record("Expected first reopen to commit")
            return
        }
        let logCount = try fixture.context.fetchCount(FetchDescriptor<StoredDoseActionLog>())

        let secondOutcome = command.perform(
            taskID: fixture.primaryTask.id,
            at: fixture.now.addingTimeInterval(1)
        )

        #expect(secondOutcome == .rejected(.alreadyOpen))
        #expect(try fixture.context.fetchCount(FetchDescriptor<StoredDoseActionLog>()) == logCount)
    }

    @Test @MainActor
    func saveFailureRestoresTasksAndActionLogs() throws {
        let fixture = try DoseReopenFixture()

        let outcome = DoseReopenCommand(
            modelContext: fixture.context,
            saveOperation: { _ in throw SyntheticDoseReopenSaveError.unavailable }
        ).perform(taskID: fixture.primaryTask.id, at: fixture.now)

        #expect(outcome == .saveFailed)
        #expect(fixture.group.allSatisfy { $0.status == .taken && $0.recordedAt != nil })
        #expect(fixture.logs.allSatisfy { $0.undoneAt == nil })
        #expect(!fixture.context.hasChanges)
    }

    @Test @MainActor
    func rollbackTokenReappliesHandledStateAndReactivatesOriginalLogs() throws {
        let fixture = try DoseReopenFixture()
        let command = DoseReopenCommand(modelContext: fixture.context)
        guard case let .committed(commit) = command.perform(
            taskID: fixture.primaryTask.id,
            at: fixture.now
        ) else {
            Issue.record("Expected reopen to commit")
            return
        }

        let rollbackOutcome = command.rollback(
            commit.rollbackToken,
            at: fixture.now.addingTimeInterval(2)
        )

        guard case let .committed(taskIDs) = rollbackOutcome else {
            Issue.record("Expected rollback to commit")
            return
        }
        #expect(Set(taskIDs) == Set(fixture.group.map(\.id)))
        #expect(fixture.group.allSatisfy { $0.status == .taken && $0.recordedAt != nil })
        #expect(fixture.logs.allSatisfy { $0.undoneAt == nil })
        #expect(!fixture.context.hasChanges)
    }

    @Test @MainActor
    func recentDelayUndoRestoresOriginalDueTimeAndClosesEveryGroupLog() throws {
        let fixture = try DoseRecentDelayFixture()

        let command = DoseReopenCommand(modelContext: fixture.context)
        let outcome = command.undoRecentDelay(
            taskID: fixture.primaryTask.id,
            at: fixture.now
        )

        guard case let .committed(commit) = outcome else {
            Issue.record("Expected recent delay to undo")
            return
        }
        #expect(commit.mode == .restoredAction)
        #expect(fixture.tasks.allSatisfy { $0.status == .pending && $0.dueAt == fixture.previousDueAt && $0.recordedAt == nil })
        #expect(fixture.logs.allSatisfy { $0.undoneAt == fixture.now })
        #expect(commit.rollbackToken.reactivatedActionLogIDs.count == 2)
        #expect(command.undoRecentDelay(taskID: fixture.primaryTask.id, at: fixture.now.addingTimeInterval(1)) == .rejected(.notUndoable))
        #expect(!fixture.context.hasChanges)
    }

    @Test @MainActor
    func repeatedDelayUndoRestoresThePreviousDelayedTime() throws {
        let fixture = try DoseRecentDelayFixture(previousStatus: .delayed)

        let outcome = DoseReopenCommand(modelContext: fixture.context).undoRecentDelay(
            taskID: fixture.primaryTask.id,
            at: fixture.now
        )

        guard case .committed = outcome else {
            Issue.record("Expected latest delay to undo")
            return
        }
        #expect(fixture.tasks.allSatisfy { $0.status == .delayed && $0.dueAt == fixture.previousDueAt })
        #expect(fixture.tasks.allSatisfy { $0.recordedAt == fixture.previousRecordedAt })
        #expect(fixture.logs.allSatisfy { $0.undoneAt == fixture.now })
    }

    @Test @MainActor
    func expiredOrIncompleteDelayUndoNeverMutatesTheGroup() throws {
        for missingSiblingLog in [false, true] {
            let fixture = try DoseRecentDelayFixture(
                undoExpiresAt: missingSiblingLog ? nil : Date(timeIntervalSince1970: 1_800_500_000 - 1),
                missingSiblingLog: missingSiblingLog
            )
            let outcome = DoseReopenCommand(modelContext: fixture.context).undoRecentDelay(
                taskID: fixture.primaryTask.id,
                at: fixture.now
            )
            #expect(outcome == .rejected(.notUndoable))
            #expect(fixture.tasks.allSatisfy { $0.status == .delayed && $0.dueAt == fixture.delayedDueAt })
            #expect(fixture.logs.allSatisfy { $0.undoneAt == nil })
            #expect(!fixture.context.hasChanges)
        }
    }

    @Test @MainActor
    func failedDelayUndoSaveRestoresTasksAndLogs() throws {
        let fixture = try DoseRecentDelayFixture()

        let outcome = DoseReopenCommand(
            modelContext: fixture.context,
            saveOperation: { _ in throw SyntheticDoseReopenSaveError.unavailable }
        ).undoRecentDelay(taskID: fixture.primaryTask.id, at: fixture.now)

        #expect(outcome == .saveFailed)
        #expect(fixture.tasks.allSatisfy { $0.status == .delayed && $0.dueAt == fixture.delayedDueAt })
        #expect(fixture.logs.allSatisfy { $0.undoneAt == nil })
        #expect(!fixture.context.hasChanges)
    }
}

private enum SyntheticDoseReopenSaveError: Error {
    case unavailable
}

@MainActor
private struct DoseReopenFixture {
    let context: ModelContext
    let now = Date(timeIntervalSince1970: 1_800_500_000)
    let primaryTask: StoredDoseTask
    let duplicateTask: StoredDoseTask
    let primaryLog: StoredDoseActionLog
    let duplicateLog: StoredDoseActionLog

    var group: [StoredDoseTask] { [primaryTask, duplicateTask] }
    var logs: [StoredDoseActionLog] { [primaryLog, duplicateLog] }

    init(undoIsAvailable: Bool = true) throws {
        let container = try ModelContainer(
            for: StoredDoseTask.self,
            StoredDoseActionLog.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let localContext = ModelContext(container)
        let medicationID = UUID()
        let dueAt = now.addingTimeInterval(-3_600)
        let recordedAt = now.addingTimeInterval(-60)
        let localPrimaryTask = StoredDoseTask(
            medicationID: medicationID,
            dueAt: dueAt,
            doseValue: 1,
            doseUnit: "片",
            status: .taken,
            recordedAt: recordedAt,
            reason: "已服用"
        )
        let localDuplicateTask = StoredDoseTask(
            medicationID: medicationID,
            dueAt: dueAt,
            doseValue: 1,
            doseUnit: "片",
            status: .taken,
            recordedAt: recordedAt,
            reason: "同一剂量重复提醒已合并"
        )
        localContext.insert(localPrimaryTask)
        localContext.insert(localDuplicateTask)
        let undoExpiry = undoIsAvailable
            ? now.addingTimeInterval(60)
            : now.addingTimeInterval(-1)
        let localPrimaryLog = Self.makeLog(
            task: localPrimaryTask,
            occurredAt: recordedAt,
            undoExpiresAt: undoExpiry,
            note: "已服用"
        )
        let localDuplicateLog = Self.makeLog(
            task: localDuplicateTask,
            occurredAt: recordedAt,
            undoExpiresAt: undoExpiry,
            note: "同一剂量重复提醒已合并"
        )
        localContext.insert(localPrimaryLog)
        localContext.insert(localDuplicateLog)
        try localContext.save()

        context = localContext
        primaryTask = localPrimaryTask
        duplicateTask = localDuplicateTask
        primaryLog = localPrimaryLog
        duplicateLog = localDuplicateLog
    }

    private static func makeLog(
        task: StoredDoseTask,
        occurredAt: Date,
        undoExpiresAt: Date,
        note: String
    ) -> StoredDoseActionLog {
        StoredDoseActionLog(
            taskID: task.id,
            action: .markTaken,
            previousStatus: .pending,
            previousDueAt: task.dueAt,
            previousRecordedAt: nil,
            previousReason: "",
            newStatus: .taken,
            occurredAt: occurredAt,
            undoExpiresAt: undoExpiresAt,
            note: note
        )
    }
}

@MainActor
private struct DoseRecentDelayFixture {
    private static let fixedNow = Date(timeIntervalSince1970: 1_800_500_000)
    let context: ModelContext
    var now: Date { Self.fixedNow }
    let previousDueAt: Date
    let delayedDueAt: Date
    let previousRecordedAt: Date?
    let primaryTask: StoredDoseTask
    let duplicateTask: StoredDoseTask
    let primaryLog: StoredDoseActionLog
    let duplicateLog: StoredDoseActionLog?

    var tasks: [StoredDoseTask] { [primaryTask, duplicateTask] }
    var logs: [StoredDoseActionLog] { duplicateLog.map { [primaryLog, $0] } ?? [primaryLog] }

    init(
        previousStatus: StoredDoseStatus = .pending,
        undoExpiresAt: Date? = nil,
        missingSiblingLog: Bool = false
    ) throws {
        let container = try ModelContainer(
            for: StoredDoseTask.self,
            StoredDoseActionLog.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let localContext = ModelContext(container)
        let medicationID = UUID()
        let originalDueAt = Self.fixedNow.addingTimeInterval(-3_600)
        let nextDueAt = Self.fixedNow.addingTimeInterval(1_800)
        let actionAt = Self.fixedNow.addingTimeInterval(-60)
        let priorRecordedAt = previousStatus == .delayed ? Self.fixedNow.addingTimeInterval(-3_600) : nil
        let localTasks = (0..<2).map { _ in
            StoredDoseTask(
                medicationID: medicationID,
                dueAt: nextDueAt,
                doseValue: 1,
                doseUnit: "片",
                status: .delayed,
                recordedAt: actionAt,
                reason: "用户选择 30 分钟后提醒"
            )
        }
        localTasks.forEach(localContext.insert)
        let localLogs = localTasks.map { task in
            StoredDoseActionLog(
                taskID: task.id,
                action: .delay,
                previousStatus: previousStatus,
                previousDueAt: originalDueAt,
                previousRecordedAt: priorRecordedAt,
                previousReason: "",
                newStatus: .delayed,
                occurredAt: actionAt,
                undoExpiresAt: undoExpiresAt ?? Self.fixedNow.addingTimeInterval(60),
                note: "稍后提醒"
            )
        }
        localContext.insert(localLogs[0])
        if !missingSiblingLog { localContext.insert(localLogs[1]) }
        try localContext.save()

        context = localContext
        previousDueAt = originalDueAt
        delayedDueAt = nextDueAt
        previousRecordedAt = priorRecordedAt
        primaryTask = localTasks[0]
        duplicateTask = localTasks[1]
        primaryLog = localLogs[0]
        duplicateLog = missingSiblingLog ? nil : localLogs[1]
    }
}
