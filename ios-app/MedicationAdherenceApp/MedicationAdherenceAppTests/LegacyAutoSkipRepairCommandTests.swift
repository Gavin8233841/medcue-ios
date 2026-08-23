import Foundation
import MedicationAdherenceCore
import SwiftData
import Testing
@testable import MedicationAdherenceApp

@Suite(.serialized)
struct LegacyAutoSkipRepairCommandTests {
    @Test @MainActor
    func repairsPrimaryDuplicateAndReopenedRecordsOnceAndPersistsAcrossContexts() throws {
        let fixture = try LegacyAutoSkipRepairFixture()
        let baseDueAt = Date(timeIntervalSince1970: 1_700_000_000)
        let repairAt = baseDueAt.addingTimeInterval(7_200)
        let primary = fixture.insertLegacyAutoSkip(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000101")!,
            previousStatus: .pending,
            previousDueAt: baseDueAt,
            previousRecordedAt: nil,
            previousReason: "",
            autoSkipAt: baseDueAt.addingTimeInterval(900),
            note: LegacyAutoSkipRecordMarker.overdue
        )
        let duplicate = fixture.insertLegacyAutoSkip(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000102")!,
            previousStatus: .delayed,
            previousDueAt: baseDueAt.addingTimeInterval(1_800),
            previousRecordedAt: baseDueAt.addingTimeInterval(120),
            previousReason: "用户稍后提醒",
            autoSkipAt: baseDueAt.addingTimeInterval(2_700),
            note: LegacyAutoSkipRecordMarker.mergedDuplicate
        )
        duplicate.task.reason += "；用户已归档"
        let reopened = fixture.insertLegacyAutoSkip(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000103")!,
            previousStatus: .pending,
            previousDueAt: baseDueAt.addingTimeInterval(3_600),
            previousRecordedAt: nil,
            previousReason: "用户撤销后等待确认",
            autoSkipAt: baseDueAt.addingTimeInterval(4_500),
            note: LegacyAutoSkipRecordMarker.reopened
        )
        try fixture.context.save()

        let result = try LegacyAutoSkipRepairCommand().perform(
            in: fixture.context,
            occurredAt: repairAt
        )

        #expect(result.correctedTaskIDs == [primary.task.id, duplicate.task.id, reopened.task.id])
        #expect(primary.task.status == .pending)
        #expect(primary.task.recordedAt == nil)
        #expect(primary.task.reason.isEmpty)
        #expect(duplicate.task.status == .delayed)
        #expect(duplicate.task.dueAt == baseDueAt.addingTimeInterval(1_800))
        #expect(duplicate.task.recordedAt == baseDueAt.addingTimeInterval(120))
        #expect(duplicate.task.reason == "用户稍后提醒")
        #expect(reopened.task.status == .pending)
        #expect(reopened.task.reason == "用户撤销后等待确认")
        #expect(primary.log.undoneAt == repairAt)
        #expect(duplicate.log.undoneAt == repairAt)
        #expect(reopened.log.undoneAt == repairAt)

        let logsAfterRepair = try fixture.context.fetch(FetchDescriptor<StoredDoseActionLog>())
        let correctionLogs = logsAfterRepair.filter { $0.actionRaw == DoseActionKind.correct.rawValue }
        #expect(logsAfterRepair.count == 6)
        #expect(correctionLogs.count == 3)
        #expect(correctionLogs.allSatisfy { $0.note == LegacyAutoSkipRepairCommand.auditNote })
        #expect(correctionLogs.allSatisfy { !$0.canUndo })

        let secondResult = try LegacyAutoSkipRepairCommand().perform(
            in: fixture.context,
            occurredAt: repairAt.addingTimeInterval(60)
        )
        #expect(secondResult.correctedTaskIDs.isEmpty)
        #expect(try fixture.context.fetch(FetchDescriptor<StoredDoseActionLog>()).count == 6)

        let restartedContext = ModelContext(fixture.container)
        let restartedTasks = try restartedContext.fetch(FetchDescriptor<StoredDoseTask>())
        #expect(restartedTasks.first { $0.id == primary.task.id }?.status == .pending)
        #expect(restartedTasks.first { $0.id == duplicate.task.id }?.status == .delayed)
        #expect(restartedTasks.first { $0.id == reopened.task.id }?.status == .pending)
        #expect(try restartedContext.fetch(FetchDescriptor<StoredDoseActionLog>()).count == 6)
    }

    @Test @MainActor
    func leavesUserSkipLookalikeNoteAndStaleLegacyLogUntouched() throws {
        let fixture = try LegacyAutoSkipRepairFixture()
        let dueAt = Date(timeIntervalSince1970: 1_700_100_000)
        let userSkip = fixture.insertSkip(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000201")!,
            dueAt: dueAt,
            recordedAt: dueAt.addingTimeInterval(60),
            note: "用户忽略"
        )
        let lookalike = fixture.insertSkip(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000202")!,
            dueAt: dueAt.addingTimeInterval(300),
            recordedAt: dueAt.addingTimeInterval(360),
            note: LegacyAutoSkipRecordMarker.overdue + " 用户随后确认这是主动忽略。"
        )
        let stale = fixture.insertLegacyAutoSkip(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000203")!,
            previousStatus: .pending,
            previousDueAt: dueAt.addingTimeInterval(600),
            previousRecordedAt: nil,
            previousReason: "",
            autoSkipAt: dueAt.addingTimeInterval(1_500),
            note: LegacyAutoSkipRecordMarker.overdue
        )
        stale.task.status = .taken
        stale.task.recordedAt = dueAt.addingTimeInterval(1_800)
        stale.task.reason = "用户后来确认已服用"
        try fixture.context.save()

        let result = try LegacyAutoSkipRepairCommand().perform(
            in: fixture.context,
            occurredAt: dueAt.addingTimeInterval(3_600)
        )

        #expect(result.correctedTaskIDs.isEmpty)
        #expect(userSkip.task.status == .skipped)
        #expect(userSkip.task.reason == "用户忽略")
        #expect(lookalike.task.status == .skipped)
        #expect(stale.task.status == .taken)
        #expect(userSkip.log.undoneAt == nil)
        #expect(lookalike.log.undoneAt == nil)
        #expect(stale.log.undoneAt == nil)
        #expect(try fixture.context.fetch(FetchDescriptor<StoredDoseActionLog>()).count == 3)
    }

    @Test @MainActor
    func saveFailureRestoresTaskAndLegacyLogWithoutPartialAudit() throws {
        let fixture = try LegacyAutoSkipRepairFixture()
        let dueAt = Date(timeIntervalSince1970: 1_700_200_000)
        let legacy = fixture.insertLegacyAutoSkip(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000301")!,
            previousStatus: .pending,
            previousDueAt: dueAt,
            previousRecordedAt: nil,
            previousReason: "",
            autoSkipAt: dueAt.addingTimeInterval(900),
            note: LegacyAutoSkipRecordMarker.overdue
        )
        try fixture.context.save()

        #expect(throws: LegacyAutoSkipRepairError.saveFailed) {
            try LegacyAutoSkipRepairCommand(saveOperation: { _ in
                throw SyntheticLegacyAutoSkipSaveError.unavailable
            }).perform(in: fixture.context, occurredAt: dueAt.addingTimeInterval(1_800))
        }

        #expect(legacy.task.status == .skipped)
        #expect(legacy.task.dueAt == dueAt)
        #expect(legacy.task.recordedAt == dueAt.addingTimeInterval(900))
        #expect(legacy.task.reason == LegacyAutoSkipRecordMarker.overdue)
        #expect(legacy.log.undoneAt == nil)
        #expect(try fixture.context.fetch(FetchDescriptor<StoredDoseActionLog>()).count == 1)
        #expect(!fixture.context.hasChanges)
    }
}

private enum SyntheticLegacyAutoSkipSaveError: Error {
    case unavailable
}

@MainActor
private struct LegacyAutoSkipRepairFixture {
    let container: ModelContainer
    let context: ModelContext

    init() throws {
        container = try ModelContainer(
            for: StoredDoseTask.self,
            StoredDoseActionLog.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        context = ModelContext(container)
    }

    func insertLegacyAutoSkip(
        id: UUID,
        previousStatus: StoredDoseStatus,
        previousDueAt: Date,
        previousRecordedAt: Date?,
        previousReason: String,
        autoSkipAt: Date,
        note: String
    ) -> (task: StoredDoseTask, log: StoredDoseActionLog) {
        let task = StoredDoseTask(
            id: id,
            medicationID: UUID(),
            dueAt: previousDueAt,
            doseValue: 1,
            doseUnit: "片",
            status: .skipped,
            recordedAt: autoSkipAt,
            reason: note
        )
        let log = StoredDoseActionLog(
            taskID: id,
            action: .skip,
            previousStatus: previousStatus,
            previousDueAt: previousDueAt,
            previousRecordedAt: previousRecordedAt,
            previousReason: previousReason,
            newStatus: .skipped,
            occurredAt: autoSkipAt,
            undoExpiresAt: autoSkipAt.addingTimeInterval(600),
            note: note
        )
        context.insert(task)
        context.insert(log)
        return (task, log)
    }

    func insertSkip(
        id: UUID,
        dueAt: Date,
        recordedAt: Date,
        note: String
    ) -> (task: StoredDoseTask, log: StoredDoseActionLog) {
        let task = StoredDoseTask(
            id: id,
            medicationID: UUID(),
            dueAt: dueAt,
            doseValue: 1,
            doseUnit: "片",
            status: .skipped,
            recordedAt: recordedAt,
            reason: note
        )
        let log = StoredDoseActionLog(
            taskID: id,
            action: .skip,
            previousStatus: .pending,
            previousDueAt: dueAt,
            previousRecordedAt: nil,
            previousReason: "",
            newStatus: .skipped,
            occurredAt: recordedAt,
            undoExpiresAt: recordedAt.addingTimeInterval(600),
            note: note
        )
        context.insert(task)
        context.insert(log)
        return (task, log)
    }
}
