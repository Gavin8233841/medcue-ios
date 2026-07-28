import Foundation
import MedicationAdherenceCore
import SwiftData
import Testing
@testable import MedicationAdherenceApp

@Suite(.serialized)
struct MedicationDeletionCommandTests {
    @Test @MainActor
    func archivedMedicationDeletesOnlyItsCompleteStoredGraph() throws {
        let fixture = try MedicationDeletionFixture()

        let outcome = MedicationDeletionCommand(modelContext: fixture.context).delete(
            medicationID: fixture.targetMedication.id
        )

        guard case let .committed(commit) = outcome else {
            Issue.record("Expected archived medication deletion to commit")
            return
        }
        #expect(commit.medicationID == fixture.targetMedication.id)
        #expect(commit.taskIDs == [fixture.targetTask.id])
        try fixture.expectTargetGraph(isPresent: false)
        try fixture.expectOtherGraphIsPresent()
        #expect(!fixture.context.hasChanges)
    }

    @Test @MainActor
    func activeMedicationIsRejectedWithoutDeletingAnything() throws {
        let fixture = try MedicationDeletionFixture(targetStatus: .active)

        let outcome = MedicationDeletionCommand(modelContext: fixture.context).delete(
            medicationID: fixture.targetMedication.id
        )

        guard case .rejected(.medicationNotArchived) = outcome else {
            Issue.record("Expected active medication deletion to be rejected")
            return
        }
        try fixture.expectTargetGraph(isPresent: true)
        try fixture.expectOtherGraphIsPresent()
        #expect(!fixture.context.hasChanges)
    }

    @Test @MainActor
    func saveFailureRollsBackEveryDeletedModel() throws {
        let fixture = try MedicationDeletionFixture()

        let outcome = MedicationDeletionCommand(
            modelContext: fixture.context,
            saveOperation: { _ in throw SyntheticMedicationDeletionSaveError.unavailable }
        ).delete(medicationID: fixture.targetMedication.id)

        guard case .saveFailed = outcome else {
            Issue.record("Expected medication deletion save failure")
            return
        }
        try fixture.expectTargetGraph(isPresent: true)
        try fixture.expectOtherGraphIsPresent()
        #expect(!fixture.context.hasChanges)
    }
}

private enum SyntheticMedicationDeletionSaveError: Error {
    case unavailable
}

@MainActor
private struct MedicationDeletionFixture {
    let context: ModelContext
    let targetMedication: StoredMedication
    let targetTask: StoredDoseTask
    let otherMedication: StoredMedication

    init(targetStatus: StoredMedicationLifecycleStatus = .archived) throws {
        let container = try ModelContainer(
            for: StoredMedication.self,
            StoredMedicationPlan.self,
            StoredMedicationDoseChange.self,
            StoredDoseTask.self,
            StoredDoseActionLog.self,
            StoredRiskCard.self,
            StoredMedicationStock.self,
            StoredMedicationLabel.self,
            StoredMedicationLifecycleEvent.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        context = ModelContext(container)
        let now = Date(timeIntervalSince1970: 1_785_030_000)
        targetMedication = StoredMedication(
            displayName: "目标药",
            kind: .overTheCounter,
            inputSource: .manual,
            lifecycleStatus: targetStatus,
            createdAt: now
        )
        otherMedication = StoredMedication(
            displayName: "保留药",
            kind: .prescription,
            inputSource: .manual,
            lifecycleStatus: .archived,
            createdAt: now
        )
        context.insert(targetMedication)
        context.insert(otherMedication)

        let targetPlan = makePlan(medicationID: targetMedication.id, now: now)
        let otherPlan = makePlan(medicationID: otherMedication.id, now: now)
        context.insert(targetPlan)
        context.insert(otherPlan)
        targetTask = makeTask(medicationID: targetMedication.id, planID: targetPlan.id, now: now)
        let otherTask = makeTask(medicationID: otherMedication.id, planID: otherPlan.id, now: now)
        context.insert(targetTask)
        context.insert(otherTask)

        for pair in [(targetMedication, targetPlan, targetTask), (otherMedication, otherPlan, otherTask)] {
            let medication = pair.0
            let plan = pair.1
            let task = pair.2
            context.insert(StoredMedicationDoseChange(
                medicationID: medication.id,
                planID: plan.id,
                newDoseValue: 1,
                newDoseUnit: "片",
                effectiveFrom: now
            ))
            context.insert(StoredDoseActionLog(
                taskID: task.id,
                action: .markTaken,
                previousStatus: .pending,
                previousDueAt: now,
                previousRecordedAt: nil,
                previousReason: "",
                newStatus: .taken,
                occurredAt: now,
                undoExpiresAt: now.addingTimeInterval(300)
            ))
            context.insert(StoredRiskCard(
                id: "risk-\(medication.id.uuidString)",
                medicationID: medication.id,
                kindRaw: RiskAssessmentCardKind.labelRisk.rawValue,
                displayPriority: 1,
                title: "风险",
                message: "测试风险",
                requiresProfessionalReview: true,
                safetyNote: "测试"
            ))
            context.insert(StoredMedicationStock(
                medicationID: medication.id,
                remainingQuantity: 10,
                unit: "片",
                lowStockThreshold: 2,
                lastUpdated: now
            ))
            context.insert(StoredMedicationLabel(
                medicationID: medication.id,
                medicationName: medication.displayName,
                rawText: "说明书正文",
                sourceTitle: "用户录入",
                importedAt: now
            ))
            context.insert(StoredMedicationLifecycleEvent(
                medicationID: medication.id,
                status: .archived,
                occurredAt: now,
                note: "归档"
            ))
        }
        try context.save()
    }

    func expectTargetGraph(isPresent: Bool) throws {
        #expect(try count(StoredMedication.self, medicationID: targetMedication.id) == (isPresent ? 1 : 0))
        #expect(try count(StoredMedicationPlan.self, medicationID: targetMedication.id) == (isPresent ? 1 : 0))
        #expect(try count(StoredMedicationDoseChange.self, medicationID: targetMedication.id) == (isPresent ? 1 : 0))
        #expect(try count(StoredDoseTask.self, medicationID: targetMedication.id) == (isPresent ? 1 : 0))
        #expect(try count(StoredDoseActionLog.self, taskID: targetTask.id) == (isPresent ? 1 : 0))
        #expect(try count(StoredRiskCard.self, medicationID: targetMedication.id) == (isPresent ? 1 : 0))
        #expect(try count(StoredMedicationStock.self, medicationID: targetMedication.id) == (isPresent ? 1 : 0))
        #expect(try count(StoredMedicationLabel.self, medicationID: targetMedication.id) == (isPresent ? 1 : 0))
        #expect(try count(StoredMedicationLifecycleEvent.self, medicationID: targetMedication.id) == (isPresent ? 1 : 0))
    }

    func expectOtherGraphIsPresent() throws {
        #expect(try count(StoredMedication.self, medicationID: otherMedication.id) == 1)
        #expect(try count(StoredMedicationPlan.self, medicationID: otherMedication.id) == 1)
        #expect(try count(StoredMedicationDoseChange.self, medicationID: otherMedication.id) == 1)
        #expect(try count(StoredDoseTask.self, medicationID: otherMedication.id) == 1)
        #expect(try count(StoredRiskCard.self, medicationID: otherMedication.id) == 1)
        #expect(try count(StoredMedicationStock.self, medicationID: otherMedication.id) == 1)
        #expect(try count(StoredMedicationLabel.self, medicationID: otherMedication.id) == 1)
        #expect(try count(StoredMedicationLifecycleEvent.self, medicationID: otherMedication.id) == 1)
    }

    private func count(_ type: StoredMedication.Type, medicationID: UUID) throws -> Int {
        try context.fetchCount(FetchDescriptor<StoredMedication>(
            predicate: #Predicate { $0.id == medicationID }
        ))
    }

    private func count(_ type: StoredMedicationPlan.Type, medicationID: UUID) throws -> Int {
        try context.fetchCount(FetchDescriptor<StoredMedicationPlan>(
            predicate: #Predicate { $0.medicationID == medicationID }
        ))
    }

    private func count(_ type: StoredMedicationDoseChange.Type, medicationID: UUID) throws -> Int {
        try context.fetchCount(FetchDescriptor<StoredMedicationDoseChange>(
            predicate: #Predicate { $0.medicationID == medicationID }
        ))
    }

    private func count(_ type: StoredDoseTask.Type, medicationID: UUID) throws -> Int {
        try context.fetchCount(FetchDescriptor<StoredDoseTask>(
            predicate: #Predicate { $0.medicationID == medicationID }
        ))
    }

    private func count(_ type: StoredDoseActionLog.Type, taskID: UUID) throws -> Int {
        try context.fetchCount(FetchDescriptor<StoredDoseActionLog>(
            predicate: #Predicate { $0.taskID == taskID }
        ))
    }

    private func count(_ type: StoredRiskCard.Type, medicationID: UUID) throws -> Int {
        try context.fetchCount(FetchDescriptor<StoredRiskCard>(
            predicate: #Predicate { $0.medicationID == medicationID }
        ))
    }

    private func count(_ type: StoredMedicationStock.Type, medicationID: UUID) throws -> Int {
        try context.fetchCount(FetchDescriptor<StoredMedicationStock>(
            predicate: #Predicate { $0.medicationID == medicationID }
        ))
    }

    private func count(_ type: StoredMedicationLabel.Type, medicationID: UUID) throws -> Int {
        try context.fetchCount(FetchDescriptor<StoredMedicationLabel>(
            predicate: #Predicate { $0.medicationID == medicationID }
        ))
    }

    private func count(_ type: StoredMedicationLifecycleEvent.Type, medicationID: UUID) throws -> Int {
        try context.fetchCount(FetchDescriptor<StoredMedicationLifecycleEvent>(
            predicate: #Predicate { $0.medicationID == medicationID }
        ))
    }
}

@MainActor
private func makePlan(medicationID: UUID, now: Date) -> StoredMedicationPlan {
    StoredMedicationPlan(
        medicationID: medicationID,
        doseValue: 1,
        doseUnit: "片",
        timingSummary: "每日一次",
        timeZonePolicy: .localClock,
        sourceNote: "",
        courseStartAt: now,
        reminderTimesRaw: "08:00",
        createdAt: now
    )
}

@MainActor
private func makeTask(medicationID: UUID, planID: UUID, now: Date) -> StoredDoseTask {
    StoredDoseTask(
        medicationID: medicationID,
        planID: planID,
        dueAt: now,
        doseValue: 1,
        doseUnit: "片"
    )
}
