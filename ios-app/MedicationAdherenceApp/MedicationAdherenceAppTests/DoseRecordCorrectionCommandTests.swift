import Foundation
import MedicationAdherenceCore
import SwiftData
import Testing
@testable import MedicationAdherenceApp

@Suite(.serialized)
struct DoseRecordCorrectionCommandTests {
    @Test @MainActor
    func correctionCommitsTheLogicalDoseGroupAndOneLogPerTask() throws {
        let fixture = try DoseRecordCorrectionFixture()
        let occurredAt = fixture.dueAt.addingTimeInterval(600)
        let recordedAt = fixture.dueAt.addingTimeInterval(300)

        let outcome = DoseRecordCorrectionCommand(modelContext: fixture.context).perform(
            DoseRecordCorrectionInput(
                taskID: fixture.primary.id,
                status: .corrected,
                plannedAt: fixture.dueAt.addingTimeInterval(60),
                recordedAt: recordedAt,
                note: " 复诊确认 ",
                confirmedEarlyRecord: true,
                occurredAt: occurredAt
            )
        )

        guard case let .committed(commit) = outcome else {
            Issue.record("Expected record correction to commit")
            return
        }
        #expect(commit.primaryTaskID == fixture.primary.id)
        #expect(commit.taskIDs == [fixture.primary.id, fixture.duplicate.id])
        #expect(fixture.primary.status == .corrected)
        #expect(fixture.duplicate.status == .corrected)
        #expect(fixture.primary.recordedAt == recordedAt)
        #expect(fixture.duplicate.recordedAt == recordedAt)
        #expect(fixture.primary.reason == "复诊确认")
        #expect(fixture.duplicate.reason == "复诊确认")

        let logs = try fixture.context.fetch(FetchDescriptor<StoredDoseActionLog>())
            .sorted { $0.taskID.uuidString < $1.taskID.uuidString }
        #expect(logs.count == 2)
        #expect(logs.allSatisfy { $0.actionRaw == DoseActionKind.correct.rawValue })
        #expect(logs.allSatisfy { $0.occurredAt == occurredAt })
        #expect(logs.first(where: { $0.taskID == fixture.primary.id })?.note == "复诊确认；用户确认提前服用。")
        #expect(logs.first(where: { $0.taskID == fixture.duplicate.id })?.note == "同一剂量重复提醒已随本次记录修正合并。；复诊确认；用户确认提前服用。")
    }

    @Test @MainActor
    func correctionDoesNotMutateTasksOutsideTheExactLogicalDose() throws {
        let fixture = try DoseRecordCorrectionFixture()

        let outcome = DoseRecordCorrectionCommand(modelContext: fixture.context).perform(
            DoseRecordCorrectionInput(
                taskID: fixture.primary.id,
                status: .taken,
                plannedAt: fixture.dueAt,
                recordedAt: fixture.dueAt,
                note: "",
                confirmedEarlyRecord: false,
                occurredAt: fixture.dueAt.addingTimeInterval(10)
            )
        )

        guard case let .committed(commit) = outcome else {
            Issue.record("Expected record correction to commit")
            return
        }
        #expect(commit.taskIDs == [fixture.primary.id, fixture.duplicate.id])
        #expect(fixture.outsideMinute.status == .pending)
        #expect(fixture.outsideMedication.status == .pending)
    }

    @Test @MainActor
    func saveFailureRestoresEveryTaskAndLeavesNoCorrectionLogs() throws {
        let fixture = try DoseRecordCorrectionFixture()
        let originalPrimaryDueAt = fixture.primary.dueAt
        let originalDuplicateDueAt = fixture.duplicate.dueAt

        let outcome = DoseRecordCorrectionCommand(
            modelContext: fixture.context,
            saveOperation: { _ in throw SyntheticDoseRecordCorrectionSaveError.unavailable }
        ).perform(
            DoseRecordCorrectionInput(
                taskID: fixture.primary.id,
                status: .corrected,
                plannedAt: fixture.dueAt.addingTimeInterval(120),
                recordedAt: fixture.dueAt.addingTimeInterval(30),
                note: "修正",
                confirmedEarlyRecord: false,
                occurredAt: fixture.dueAt.addingTimeInterval(300)
            )
        )

        #expect(outcome == .saveFailed)
        #expect(fixture.primary.status == .taken)
        #expect(fixture.primary.dueAt == originalPrimaryDueAt)
        #expect(fixture.primary.recordedAt == fixture.dueAt.addingTimeInterval(5))
        #expect(fixture.primary.reason == "原主记录")
        #expect(fixture.duplicate.status == .taken)
        #expect(fixture.duplicate.dueAt == originalDuplicateDueAt)
        #expect(fixture.duplicate.recordedAt == fixture.dueAt.addingTimeInterval(6))
        #expect(fixture.duplicate.reason == "原重复记录")
        #expect(try fixture.context.fetch(FetchDescriptor<StoredDoseActionLog>()).isEmpty)
        #expect(!fixture.context.hasChanges)
    }

    @Test @MainActor
    func missingTaskIsRejectedWithoutWriting() throws {
        let fixture = try DoseRecordCorrectionFixture()

        let outcome = DoseRecordCorrectionCommand(modelContext: fixture.context).perform(
            DoseRecordCorrectionInput(
                taskID: UUID(),
                status: .taken,
                plannedAt: fixture.dueAt,
                recordedAt: fixture.dueAt,
                note: "",
                confirmedEarlyRecord: false,
                occurredAt: fixture.dueAt
            )
        )

        #expect(outcome == .rejected(.taskNotFound))
        #expect(try fixture.context.fetch(FetchDescriptor<StoredDoseActionLog>()).isEmpty)
    }
}

private enum SyntheticDoseRecordCorrectionSaveError: Error {
    case unavailable
}

@MainActor
private struct DoseRecordCorrectionFixture {
    let container: ModelContainer
    let context: ModelContext
    let dueAt = Date(timeIntervalSince1970: 1_699_999_985)
    let primary: StoredDoseTask
    let duplicate: StoredDoseTask
    let outsideMinute: StoredDoseTask
    let outsideMedication: StoredDoseTask

    init() throws {
        container = try ModelContainer(
            for: StoredDoseTask.self,
            StoredDoseActionLog.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        context = ModelContext(container)
        let medicationID = UUID()
        let planID = UUID()
        primary = StoredDoseTask(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            medicationID: medicationID,
            planID: planID,
            dueAt: dueAt,
            doseValue: 1,
            doseUnit: "片",
            status: .taken,
            recordedAt: dueAt.addingTimeInterval(5),
            reason: "原主记录"
        )
        duplicate = StoredDoseTask(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
            medicationID: medicationID,
            planID: UUID(),
            dueAt: dueAt.addingTimeInterval(20),
            doseValue: 1,
            doseUnit: "片",
            status: .taken,
            recordedAt: dueAt.addingTimeInterval(6),
            reason: "原重复记录"
        )
        outsideMinute = StoredDoseTask(
            medicationID: medicationID,
            planID: planID,
            dueAt: dueAt.addingTimeInterval(60),
            doseValue: 1,
            doseUnit: "片"
        )
        outsideMedication = StoredDoseTask(
            medicationID: UUID(),
            planID: planID,
            dueAt: dueAt,
            doseValue: 1,
            doseUnit: "片"
        )
        [primary, duplicate, outsideMinute, outsideMedication].forEach(context.insert)
        try context.save()
    }
}
