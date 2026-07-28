import Foundation
import MedicationAdherenceCore
import SwiftData
import Testing
@testable import MedicationAdherenceApp

@Suite(.serialized)
struct TodayArchiveVisibilityCommandTests {
    @Test @MainActor
    func archiveCommitsMarkerAndAuditLogTogether() throws {
        let fixture = try TodayArchiveVisibilityFixture(reason: "既有说明")
        let occurredAt = fixture.dueAt.addingTimeInterval(30)

        let outcome = TodayArchiveVisibilityCommand(modelContext: fixture.context).perform(
            .archive(taskID: fixture.task.id, occurredAt: occurredAt)
        )

        #expect(outcome == .committed(taskID: fixture.task.id))
        #expect(fixture.task.reason == "既有说明；用户已归档")
        let log = try #require(try fixture.context.fetch(FetchDescriptor<StoredDoseActionLog>()).first)
        #expect(log.actionRaw == DoseActionKind.archiveToday.rawValue)
        #expect(log.previousReason == "既有说明")
        #expect(log.note == "用户将今日记录归档隐藏")
        #expect(log.occurredAt == occurredAt)
    }

    @Test @MainActor
    func restoreRemovesOnlyTheExactArchiveMarker() throws {
        let fixture = try TodayArchiveVisibilityFixture(reason: "用户已归档；仍需关注；用户已归档说明")

        let outcome = TodayArchiveVisibilityCommand(modelContext: fixture.context).perform(
            .restore(taskID: fixture.task.id, occurredAt: fixture.dueAt.addingTimeInterval(60))
        )

        #expect(outcome == .committed(taskID: fixture.task.id))
        #expect(fixture.task.reason == "仍需关注；用户已归档说明")
        let log = try #require(try fixture.context.fetch(FetchDescriptor<StoredDoseActionLog>()).first)
        #expect(log.actionRaw == DoseActionKind.restoreArchive.rawValue)
        #expect(log.note == "用户恢复今日归档记录")
    }

    @Test @MainActor
    func invalidVisibilityTransitionIsRejectedWithoutWriting() throws {
        let fixture = try TodayArchiveVisibilityFixture(reason: "")

        let outcome = TodayArchiveVisibilityCommand(modelContext: fixture.context).perform(
            .restore(taskID: fixture.task.id, occurredAt: fixture.dueAt)
        )

        #expect(outcome == .rejected(.notArchived))
        #expect(try fixture.context.fetch(FetchDescriptor<StoredDoseActionLog>()).isEmpty)
    }

    @Test @MainActor
    func saveFailureRestoresReasonAndLeavesNoAuditLog() throws {
        let fixture = try TodayArchiveVisibilityFixture(reason: "原说明")

        let outcome = TodayArchiveVisibilityCommand(
            modelContext: fixture.context,
            saveOperation: { _ in throw SyntheticTodayArchiveSaveError.unavailable }
        ).perform(.archive(taskID: fixture.task.id, occurredAt: fixture.dueAt))

        #expect(outcome == .saveFailed)
        #expect(fixture.task.reason == "原说明")
        #expect(try fixture.context.fetch(FetchDescriptor<StoredDoseActionLog>()).isEmpty)
        #expect(!fixture.context.hasChanges)
    }
}

private enum SyntheticTodayArchiveSaveError: Error {
    case unavailable
}

@MainActor
private struct TodayArchiveVisibilityFixture {
    let container: ModelContainer
    let context: ModelContext
    let dueAt = Date(timeIntervalSinceReferenceDate: 20_000)
    let task: StoredDoseTask

    init(reason: String) throws {
        container = try ModelContainer(
            for: StoredDoseTask.self,
            StoredDoseActionLog.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        context = ModelContext(container)
        task = StoredDoseTask(
            medicationID: UUID(),
            dueAt: dueAt,
            doseValue: 1,
            doseUnit: "片",
            status: .taken,
            recordedAt: dueAt,
            reason: reason
        )
        context.insert(task)
        try context.save()
    }
}
