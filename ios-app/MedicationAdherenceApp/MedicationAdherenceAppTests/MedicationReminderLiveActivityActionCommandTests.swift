import Foundation
import MedicationAdherenceCore
import SwiftData
import Testing
@testable import MedicationAdherenceApp

@Suite(.serialized)
struct MedicationReminderLiveActivityActionCommandTests {
    @Test @MainActor
    func markTakenCommitsTaskAndStablePrimaryLogTogether() throws {
        let fixture = try LiveActivityDoseFixture()
        let operationID = UUID(uuidString: "00000000-0000-0000-0000-000000000901")!
        let occurredAt = fixture.dueAt.addingTimeInterval(60)

        let outcome = MedicationReminderLiveActivityActionCommand().execute(
            MedicationReminderLiveActivityActionRequest(
                taskID: fixture.primaryTask.id,
                action: .markTaken,
                operationID: operationID
            ),
            occurredAt: occurredAt,
            in: fixture.context
        )

        #expect(outcome == .committed(taskIDs: [fixture.primaryTask.id]))
        let verificationContext = ModelContext(fixture.container)
        let persistedTask = try #require(
            verificationContext.fetch(FetchDescriptor<StoredDoseTask>()).first
        )
        let persistedLog = try #require(
            verificationContext.fetch(FetchDescriptor<StoredDoseActionLog>()).first
        )
        #expect(persistedTask.status == .taken)
        #expect(persistedTask.recordedAt == occurredAt)
        #expect(persistedLog.id == operationID)
        #expect(persistedLog.taskID == fixture.primaryTask.id)
        #expect(persistedLog.actionRaw == DoseActionKind.markTaken.rawValue)
    }

    @Test @MainActor
    func saveFailureRollsBackTaskAndLeavesNoStablePrimaryLog() throws {
        let fixture = try LiveActivityDoseFixture()
        let operationID = UUID(uuidString: "00000000-0000-0000-0000-000000000902")!
        let command = MedicationReminderLiveActivityActionCommand(
            persistence: DoseActionPersistence { _ in
                throw SyntheticLiveActivitySaveError.unavailable
            }
        )

        let outcome = command.execute(
            MedicationReminderLiveActivityActionRequest(
                taskID: fixture.primaryTask.id,
                action: .markTaken,
                operationID: operationID
            ),
            occurredAt: fixture.dueAt.addingTimeInterval(60),
            in: fixture.context
        )

        #expect(outcome == .saveFailed)
        #expect(fixture.primaryTask.status == .pending)
        #expect(fixture.primaryTask.recordedAt == nil)
        #expect(fixture.primaryTask.reason == "原始状态")
        #expect(try fixture.context.fetch(FetchDescriptor<StoredDoseActionLog>()).isEmpty)

        let verificationContext = ModelContext(fixture.container)
        let persistedTask = try #require(
            verificationContext.fetch(FetchDescriptor<StoredDoseTask>()).first
        )
        #expect(persistedTask.status == .pending)
        #expect(persistedTask.recordedAt == nil)
        #expect(try verificationContext.fetch(FetchDescriptor<StoredDoseActionLog>()).isEmpty)
    }

    @Test @MainActor
    func duplicateDeliveryReturnsCommittedReceiptWithoutWritingAgain() throws {
        let fixture = try LiveActivityDoseFixture()
        let operationID = UUID(uuidString: "00000000-0000-0000-0000-000000000903")!
        let firstOccurredAt = fixture.dueAt.addingTimeInterval(60)
        let duplicateOccurredAt = fixture.dueAt.addingTimeInterval(180)
        let request = MedicationReminderLiveActivityActionRequest(
            taskID: fixture.primaryTask.id,
            action: .markTaken,
            operationID: operationID
        )
        let command = MedicationReminderLiveActivityActionCommand()

        let firstOutcome = command.execute(
            request,
            occurredAt: firstOccurredAt,
            in: fixture.context
        )
        let duplicateOutcome = command.execute(
            request,
            occurredAt: duplicateOccurredAt,
            in: fixture.context
        )

        #expect(firstOutcome == .committed(taskIDs: [fixture.primaryTask.id]))
        #expect(duplicateOutcome == .alreadyCommitted(taskIDs: [fixture.primaryTask.id]))
        let logs = try fixture.context.fetch(FetchDescriptor<StoredDoseActionLog>())
        #expect(logs.count == 1)
        #expect(logs.first?.id == operationID)
        #expect(fixture.primaryTask.recordedAt == firstOccurredAt)
    }

    @Test @MainActor
    func expiredActionDoesNotChangeTaskOrWriteLog() throws {
        let fixture = try LiveActivityDoseFixture()
        let operationID = UUID(uuidString: "00000000-0000-0000-0000-000000000904")!
        let expiresAt = fixture.dueAt.addingTimeInterval(10 * 60)

        let outcome = MedicationReminderLiveActivityActionCommand().execute(
            MedicationReminderLiveActivityActionRequest(
                taskID: fixture.primaryTask.id,
                action: .markTaken,
                operationID: operationID,
                expiresAt: expiresAt
            ),
            occurredAt: expiresAt.addingTimeInterval(1),
            in: fixture.context
        )

        #expect(outcome == .rejected(.expired))
        #expect(fixture.primaryTask.status == .pending)
        #expect(fixture.primaryTask.recordedAt == nil)
        #expect(try fixture.context.fetch(FetchDescriptor<StoredDoseActionLog>()).isEmpty)
        #expect(!fixture.context.hasChanges)
    }

    @Test @MainActor
    func closedTaskDoesNotChangeStateOrWriteLog() throws {
        let fixture = try LiveActivityDoseFixture()
        let recordedAt = fixture.dueAt.addingTimeInterval(30)
        fixture.primaryTask.status = .taken
        fixture.primaryTask.recordedAt = recordedAt
        fixture.primaryTask.reason = "此前已记录"
        try fixture.context.save()

        let outcome = MedicationReminderLiveActivityActionCommand().execute(
            MedicationReminderLiveActivityActionRequest(
                taskID: fixture.primaryTask.id,
                action: .markTaken,
                operationID: UUID(uuidString: "00000000-0000-0000-0000-000000000905")!
            ),
            occurredAt: recordedAt.addingTimeInterval(60),
            in: fixture.context
        )

        #expect(outcome == .rejected(.taskClosed))
        #expect(fixture.primaryTask.status == .taken)
        #expect(fixture.primaryTask.recordedAt == recordedAt)
        #expect(fixture.primaryTask.reason == "此前已记录")
        #expect(try fixture.context.fetch(FetchDescriptor<StoredDoseActionLog>()).isEmpty)
        #expect(!fixture.context.hasChanges)
    }

    @Test @MainActor
    func logicalDoseGroupWritesExactlyOnePrimaryLog() throws {
        let fixture = try LiveActivityDoseFixture()
        let duplicateTask = StoredDoseTask(
            medicationID: fixture.primaryTask.medicationID,
            dueAt: fixture.dueAt.addingTimeInterval(20),
            doseValue: fixture.primaryTask.doseValue,
            doseUnit: fixture.primaryTask.doseUnit,
            status: .delayed,
            reason: "重复提醒"
        )
        fixture.context.insert(duplicateTask)
        try fixture.context.save()
        let operationID = UUID(uuidString: "00000000-0000-0000-0000-000000000906")!

        let outcome = MedicationReminderLiveActivityActionCommand().execute(
            MedicationReminderLiveActivityActionRequest(
                taskID: fixture.primaryTask.id,
                action: .markTaken,
                operationID: operationID
            ),
            occurredAt: fixture.dueAt.addingTimeInterval(60),
            in: fixture.context
        )

        #expect(outcome == .committed(taskIDs: [fixture.primaryTask.id, duplicateTask.id]))
        let logs = try fixture.context.fetch(FetchDescriptor<StoredDoseActionLog>())
        #expect(logs.count == 2)
        #expect(logs.filter { $0.id == operationID && $0.taskID == fixture.primaryTask.id }.count == 1)
        #expect(logs.filter { $0.note == "通过实况活动标记已服用" }.count == 1)
        #expect(logs.filter { $0.note == "同一剂量重复提醒已随本次实况活动操作合并。" }.count == 1)
        #expect(fixture.primaryTask.status == .taken)
        #expect(duplicateTask.status == .taken)
    }

    @Test @MainActor
    func delayCommitsFromPlannedTimeAndDuplicateDeliveryDoesNotWriteAgain() throws {
        let fixture = try LiveActivityDoseFixture()
        let operationID = UUID(uuidString: "00000000-0000-0000-0000-000000000907")!
        let occurredAt = fixture.dueAt.addingTimeInterval(60)
        let request = MedicationReminderLiveActivityActionRequest(
            taskID: fixture.primaryTask.id,
            action: .delay,
            operationID: operationID
        )
        let command = MedicationReminderLiveActivityActionCommand()

        let firstOutcome = command.execute(request, occurredAt: occurredAt, in: fixture.context)
        let duplicateOutcome = command.execute(
            request,
            occurredAt: occurredAt.addingTimeInterval(60),
            in: fixture.context
        )

        #expect(firstOutcome == .committed(taskIDs: [fixture.primaryTask.id]))
        #expect(duplicateOutcome == .alreadyCommitted(taskIDs: [fixture.primaryTask.id]))
        #expect(fixture.primaryTask.status == .delayed)
        #expect(fixture.primaryTask.dueAt == DoseDelayPolicy.delayedDueAtFromPlannedTime(fixture.dueAt))
        #expect(fixture.primaryTask.recordedAt == occurredAt)
        let logs = try fixture.context.fetch(FetchDescriptor<StoredDoseActionLog>())
        #expect(logs.count == 1)
        #expect(logs.first?.id == operationID)
        #expect(logs.first?.actionRaw == DoseActionKind.delay.rawValue)
    }

    @Test @MainActor
    func skipCommitsWithStableOperationID() throws {
        let fixture = try LiveActivityDoseFixture()
        let operationID = UUID(uuidString: "00000000-0000-0000-0000-000000000908")!
        let occurredAt = fixture.dueAt.addingTimeInterval(60)

        let outcome = MedicationReminderLiveActivityActionCommand().execute(
            MedicationReminderLiveActivityActionRequest(
                taskID: fixture.primaryTask.id,
                action: .skip,
                operationID: operationID
            ),
            occurredAt: occurredAt,
            in: fixture.context
        )

        #expect(outcome == .committed(taskIDs: [fixture.primaryTask.id]))
        #expect(fixture.primaryTask.status == .skipped)
        #expect(fixture.primaryTask.dueAt == fixture.dueAt)
        #expect(fixture.primaryTask.recordedAt == occurredAt)
        let log = try #require(fixture.context.fetch(FetchDescriptor<StoredDoseActionLog>()).first)
        #expect(log.id == operationID)
        #expect(log.actionRaw == DoseActionKind.skip.rawValue)
    }

    @Test @MainActor
    func legacyRequestUsesTaskIDAsStableOperationIDAndCannotRepeatDelay() throws {
        let fixture = try LiveActivityDoseFixture()
        let occurredAt = fixture.dueAt.addingTimeInterval(60)
        let request = MedicationReminderLiveActivityActionRequest(
            taskID: fixture.primaryTask.id,
            action: .delay
        )
        let command = MedicationReminderLiveActivityActionCommand()

        let firstOutcome = command.execute(request, occurredAt: occurredAt, in: fixture.context)
        let firstDelayedDueAt = fixture.primaryTask.dueAt
        let duplicateOutcome = command.execute(
            request,
            occurredAt: occurredAt.addingTimeInterval(60),
            in: fixture.context
        )

        #expect(firstOutcome == .committed(taskIDs: [fixture.primaryTask.id]))
        #expect(duplicateOutcome == .alreadyCommitted(taskIDs: [fixture.primaryTask.id]))
        #expect(fixture.primaryTask.dueAt == firstDelayedDueAt)
        let logs = try fixture.context.fetch(FetchDescriptor<StoredDoseActionLog>())
        #expect(logs.count == 1)
        #expect(logs.first?.id == fixture.primaryTask.id)
    }

    @Test @MainActor
    func legacyRequestExpiresAtTheExistingActivityStaleBoundary() throws {
        let fixture = try LiveActivityDoseFixture()

        let outcome = MedicationReminderLiveActivityActionCommand().execute(
            MedicationReminderLiveActivityActionRequest(
                taskID: fixture.primaryTask.id,
                action: .markTaken
            ),
            occurredAt: fixture.dueAt.addingTimeInterval(10 * 60 + 1),
            in: fixture.context
        )

        #expect(outcome == .rejected(.expired))
        #expect(fixture.primaryTask.status == .pending)
        #expect(try fixture.context.fetch(FetchDescriptor<StoredDoseActionLog>()).isEmpty)
    }

    @Test
    func actionURLRoundTripsStableOperationAndExpiry() throws {
        let taskID = UUID(uuidString: "00000000-0000-0000-0000-000000000911")!
        let operationID = UUID(uuidString: "00000000-0000-0000-0000-000000000912")!
        let expiresAt = Date(timeIntervalSince1970: 1_700_000_600)

        let url = MedicationReminderLiveActivityActionURL.url(
            for: taskID,
            action: .markTaken,
            operationID: operationID,
            expiresAt: expiresAt
        )
        let request = try #require(MedicationReminderLiveActivityActionURL.request(from: url))

        #expect(request.taskID == taskID)
        #expect(request.action == .markTaken)
        #expect(request.operationID == operationID)
        #expect(request.expiresAt == expiresAt)
    }

    @Test
    func legacyActionURLWithoutTransactionMetadataRemainsAccepted() throws {
        let taskID = UUID(uuidString: "00000000-0000-0000-0000-000000000913")!
        let url = MedicationReminderLiveActivityActionURL.url(for: taskID, action: .delay)

        let request = try #require(MedicationReminderLiveActivityActionURL.request(from: url))

        #expect(request.taskID == taskID)
        #expect(request.action == .delay)
        #expect(request.operationID == nil)
        #expect(request.expiresAt == nil)
    }

    @Test
    func legacyActivityAttributesDecodeWithoutOperationID() throws {
        let taskID = UUID(uuidString: "00000000-0000-0000-0000-000000000914")!
        let legacyPayload = """
        {
          "taskID": "\(taskID.uuidString)",
          "medicationName": "测试药品",
          "doseText": "1 片"
        }
        """

        let attributes = try JSONDecoder().decode(
            MedicationReminderActivityAttributes.self,
            from: Data(legacyPayload.utf8)
        )

        #expect(attributes.taskID == taskID)
        #expect(attributes.medicationName == "测试药品")
        #expect(attributes.doseText == "1 片")
        #expect(attributes.actionOperationID == nil)
    }
}

@MainActor
private struct LiveActivityDoseFixture {
    let container: ModelContainer
    let context: ModelContext
    let dueAt: Date
    let primaryTask: StoredDoseTask

    init() throws {
        container = try MedicationAdherenceModelContainer.make(isStoredInMemoryOnly: true)
        context = ModelContext(container)
        context.autosaveEnabled = false
        dueAt = Date(timeIntervalSince1970: 1_700_000_000)

        let medicationID = UUID()
        let medication = StoredMedication(
            id: medicationID,
            displayName: "测试药品",
            kind: .prescription,
            inputSource: .manual
        )
        primaryTask = StoredDoseTask(
            medicationID: medicationID,
            dueAt: dueAt,
            doseValue: 1,
            doseUnit: "片",
            status: .pending,
            reason: "原始状态"
        )
        context.insert(medication)
        context.insert(primaryTask)
        try context.save()
    }
}

private enum SyntheticLiveActivitySaveError: Error {
    case unavailable
}
