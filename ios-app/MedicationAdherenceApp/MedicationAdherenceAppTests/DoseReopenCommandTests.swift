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
