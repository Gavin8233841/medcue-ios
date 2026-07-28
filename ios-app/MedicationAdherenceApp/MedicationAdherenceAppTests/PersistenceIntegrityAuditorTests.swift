import Foundation
import MedicationAdherenceCore
import SwiftData
import Testing
@testable import MedicationAdherenceApp

struct PersistenceIntegrityAuditorTests {
    @Test @MainActor
    func completeStoredGraphProducesACleanReport() throws {
        let container = try MedicationAdherenceModelContainer.make(isStoredInMemoryOnly: true)
        let context = ModelContext(container)
        let medication = StoredMedication(
            displayName: "测试药品",
            kind: .prescription,
            inputSource: .manual
        )
        let plan = StoredMedicationPlan(
            medicationID: medication.id,
            doseValue: 1,
            doseUnit: "片",
            timingSummary: "每日一次",
            timeZonePolicy: .localClock,
            sourceNote: "测试"
        )
        let task = StoredDoseTask(
            medicationID: medication.id,
            planID: plan.id,
            dueAt: Date(),
            doseValue: 1,
            doseUnit: "片"
        )
        context.insert(medication)
        context.insert(plan)
        context.insert(task)
        context.insert(StoredMedicationDoseChange(
            medicationID: medication.id,
            planID: plan.id,
            newDoseValue: 1,
            newDoseUnit: "片",
            effectiveFrom: Date()
        ))
        context.insert(StoredRiskCard(
            id: "test-risk",
            medicationID: medication.id,
            kindRaw: "labelRisk",
            displayPriority: 1,
            title: "测试",
            message: "测试",
            requiresProfessionalReview: true,
            safetyNote: "测试"
        ))
        context.insert(StoredMedicationLabel(
            medicationID: medication.id,
            medicationName: medication.displayName,
            rawText: "测试说明书",
            sourceTitle: "测试"
        ))
        context.insert(StoredMedicationStock(
            medicationID: medication.id,
            remainingQuantity: 10,
            unit: "片",
            lowStockThreshold: 2
        ))
        context.insert(StoredMedicationLifecycleEvent(
            medicationID: medication.id,
            status: .active
        ))
        context.insert(StoredDoseActionLog(
            taskID: task.id,
            action: .markTaken,
            previousStatus: .pending,
            previousDueAt: task.dueAt,
            previousRecordedAt: nil,
            previousReason: "",
            newStatus: .taken,
            undoExpiresAt: Date().addingTimeInterval(600)
        ))
        try context.save()

        let report = try PersistenceIntegrityAuditor(modelContext: context).audit()

        #expect(report.isClean)
        #expect(report.issues.isEmpty)
        #expect(!context.hasChanges)
    }

    @Test @MainActor
    func crossMedicationPlanReferencesAreReportedSeparatelyFromOrphans() throws {
        let container = try MedicationAdherenceModelContainer.make(isStoredInMemoryOnly: true)
        let context = ModelContext(container)
        let firstMedication = StoredMedication(
            displayName: "药品一",
            kind: .prescription,
            inputSource: .manual
        )
        let secondMedication = StoredMedication(
            displayName: "药品二",
            kind: .prescription,
            inputSource: .manual
        )
        let plan = StoredMedicationPlan(
            medicationID: firstMedication.id,
            doseValue: 1,
            doseUnit: "片",
            timingSummary: "每日一次",
            timeZonePolicy: .localClock,
            sourceNote: "测试"
        )
        context.insert(firstMedication)
        context.insert(secondMedication)
        context.insert(plan)
        context.insert(StoredDoseTask(
            medicationID: secondMedication.id,
            planID: plan.id,
            dueAt: Date(),
            doseValue: 1,
            doseUnit: "片"
        ))
        context.insert(StoredMedicationDoseChange(
            medicationID: secondMedication.id,
            planID: plan.id,
            newDoseValue: 1,
            newDoseUnit: "片",
            effectiveFrom: Date()
        ))
        try context.save()

        let report = try PersistenceIntegrityAuditor(modelContext: context).audit()

        #expect(Set(report.issues.map(\.kind)) == [
            .doseTaskPlanMedicationMismatch,
            .doseChangePlanMedicationMismatch
        ])
    }

    @Test @MainActor
    func orphanReferencesAreReportedWithoutMutatingStoredData() throws {
        let container = try MedicationAdherenceModelContainer.make(isStoredInMemoryOnly: true)
        let context = ModelContext(container)
        let missingMedicationID = UUID()
        let missingPlanID = UUID()
        let missingTaskID = UUID()
        context.insert(StoredMedicationPlan(
            medicationID: missingMedicationID,
            doseValue: 1,
            doseUnit: "片",
            timingSummary: "每日一次",
            timeZonePolicy: .localClock,
            sourceNote: "测试"
        ))
        context.insert(StoredDoseTask(
            medicationID: missingMedicationID,
            planID: missingPlanID,
            dueAt: Date(),
            doseValue: 1,
            doseUnit: "片"
        ))
        context.insert(StoredDoseActionLog(
            taskID: missingTaskID,
            action: .markTaken,
            previousStatus: .pending,
            previousDueAt: Date(),
            previousRecordedAt: nil,
            previousReason: "",
            newStatus: .taken,
            undoExpiresAt: Date().addingTimeInterval(600)
        ))
        try context.save()

        let report = try PersistenceIntegrityAuditor(modelContext: context).audit()

        let expectedKinds: Set<PersistenceIntegrityIssueKind> = [
            .orphanPlanMedication,
            .orphanDoseTaskMedication,
            .orphanDoseTaskPlan,
            .orphanActionLogTask
        ]
        #expect(Set(report.issues.map(\.kind)) == expectedKinds)
        #expect(try context.fetchCount(FetchDescriptor<StoredMedicationPlan>()) == 1)
        #expect(try context.fetchCount(FetchDescriptor<StoredDoseTask>()) == 1)
        #expect(try context.fetchCount(FetchDescriptor<StoredDoseActionLog>()) == 1)
        #expect(!context.hasChanges)
    }
}
