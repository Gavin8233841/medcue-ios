import CoreFoundation
import Foundation
import MedicationAdherenceCore
import SwiftData
import Testing
@testable import MedicationAdherenceApp

@MainActor
struct ModelContextPerformanceTests {
    private let modelContainer: ModelContainer

    init() throws {
        modelContainer = try MedicationAdherenceModelContainer.make(isStoredInMemoryOnly: true)
    }

    private func makeMedication(index: Int = 0) -> StoredMedication {
        StoredMedication(
            displayName: "Test medication \(index)",
            genericName: "Generic medication \(index)",
            kind: .overTheCounter,
            form: "tablet",
            strength: "500 mg",
            inputSource: .manual
        )
    }

    private func makePlan(for medication: StoredMedication) -> StoredMedicationPlan {
        StoredMedicationPlan(
            medicationID: medication.id,
            doseValue: 1,
            doseUnit: "tablet",
            timingSummary: "Daily 08:00",
            timeZonePolicy: .localClock,
            sourceNote: "Performance test",
            courseStartAt: Date(),
            reminderTimesRaw: "08:00"
        )
    }

    @Test("Fetch single medication should complete within performance threshold")
    func fetchSingleMedication() throws {
        let context = modelContainer.mainContext
        let medication = makeMedication()
        context.insert(medication)
        try context.save()

        let startTime = CFAbsoluteTimeGetCurrent()
        let result = try ModelContextPerformanceMetrics.measureFetch(operation: "fetch-single-medication") {
            let medicationID = medication.id
            let descriptor = FetchDescriptor<StoredMedication>(
                predicate: #Predicate { $0.id == medicationID }
            )
            return try context.fetch(descriptor).first
        }
        let duration = CFAbsoluteTimeGetCurrent() - startTime

        #expect(result?.id == medication.id)
        #expect(duration < 0.100, "Fetch single medication should complete within 100ms")
    }

    @Test("Fetch multiple medications should complete within performance threshold")
    func fetchMultipleMedications() throws {
        let context = modelContainer.mainContext
        for index in 0..<20 {
            context.insert(makeMedication(index: index))
        }
        try context.save()

        let startTime = CFAbsoluteTimeGetCurrent()
        let results = try ModelContextPerformanceMetrics.measureFetch(operation: "fetch-all-medications") {
            try context.fetch(FetchDescriptor<StoredMedication>())
        }
        let duration = CFAbsoluteTimeGetCurrent() - startTime

        #expect(results.count == 20)
        #expect(duration < 0.100, "Fetch 20 medications should complete within 100ms")
    }

    @Test("Save single medication should complete within performance threshold")
    func saveSingleMedication() throws {
        let context = modelContainer.mainContext
        context.insert(makeMedication())

        let startTime = CFAbsoluteTimeGetCurrent()
        try ModelContextPerformanceMetrics.measureSave(operation: "save-single-medication") {
            try context.save()
        }
        let duration = CFAbsoluteTimeGetCurrent() - startTime

        #expect(duration < 0.100, "Save single medication should complete within 100ms")
    }

    @Test("Save medication with plan should complete within performance threshold")
    func saveMedicationWithPlan() throws {
        let context = modelContainer.mainContext
        let medication = makeMedication()
        context.insert(medication)
        context.insert(makePlan(for: medication))

        let startTime = CFAbsoluteTimeGetCurrent()
        try ModelContextPerformanceMetrics.measureSave(operation: "save-medication-with-plan") {
            try context.save()
        }
        let duration = CFAbsoluteTimeGetCurrent() - startTime

        #expect(duration < 0.100, "Save medication with plan should complete within 100ms")
    }

    @Test("Fetch tasks by plan ID should complete within performance threshold")
    func fetchTasksByPlanID() throws {
        let context = modelContainer.mainContext
        let medication = makeMedication()
        let plan = makePlan(for: medication)
        context.insert(medication)
        context.insert(plan)
        for index in 0..<10 {
            context.insert(StoredDoseTask(
                medicationID: medication.id,
                planID: plan.id,
                dueAt: Date().addingTimeInterval(Double(index) * 3600),
                doseValue: 1,
                doseUnit: "tablet"
            ))
        }
        try context.save()

        let startTime = CFAbsoluteTimeGetCurrent()
        let results = try ModelContextPerformanceMetrics.measureFetch(operation: "fetch-tasks-by-plan") {
            let planID = plan.id
            let descriptor = FetchDescriptor<StoredDoseTask>(
                predicate: #Predicate { $0.planID == planID }
            )
            return try context.fetch(descriptor)
        }
        let duration = CFAbsoluteTimeGetCurrent() - startTime

        #expect(results.count == 10)
        #expect(duration < 0.100, "Fetch 10 tasks by plan ID should complete within 100ms")
    }

    @Test("Delete medication should complete within performance threshold")
    func deleteMedication() throws {
        let context = modelContainer.mainContext
        let medication = makeMedication()
        context.insert(medication)
        try context.save()

        let startTime = CFAbsoluteTimeGetCurrent()
        try ModelContextPerformanceMetrics.measureDelete(operation: "delete-medication") {
            context.delete(medication)
            try context.save()
        }
        let duration = CFAbsoluteTimeGetCurrent() - startTime

        #expect(try context.fetch(FetchDescriptor<StoredMedication>()).isEmpty)
        #expect(duration < 0.150, "Delete medication should complete within 150ms")
    }

    @Test("Complex query with predicates should complete within performance threshold")
    func complexQueryWithPredicates() throws {
        let context = modelContainer.mainContext
        for index in 0..<30 {
            let medication = makeMedication(index: index)
            medication.form = index.isMultiple(of: 3) ? "tablet" : "capsule"
            if index.isMultiple(of: 5) {
                medication.lifecycleStatusRaw = StoredMedicationLifecycleStatus.archived.rawValue
            }
            context.insert(medication)
        }
        try context.save()

        let archivedStatus = StoredMedicationLifecycleStatus.archived.rawValue
        let startTime = CFAbsoluteTimeGetCurrent()
        let results = try ModelContextPerformanceMetrics.measureFetch(operation: "complex-query-with-predicates") {
            let descriptor = FetchDescriptor<StoredMedication>(
                predicate: #Predicate {
                    $0.lifecycleStatusRaw != archivedStatus &&
                    $0.form == "tablet"
                }
            )
            return try context.fetch(descriptor)
        }
        let duration = CFAbsoluteTimeGetCurrent() - startTime

        #expect(results.count > 0)
        #expect(duration < 0.100, "Complex query should complete within 100ms")
    }

    @Test("Batch insert should complete within performance threshold")
    func batchInsert() throws {
        let context = modelContainer.mainContext
        let startTime = CFAbsoluteTimeGetCurrent()
        try ModelContextPerformanceMetrics.measureOperation(
            name: "modelcontext.batch-insert",
            operation: "insert-50-medications"
        ) {
            for index in 0..<50 {
                context.insert(makeMedication(index: index))
            }
            try context.save()
        }
        let duration = CFAbsoluteTimeGetCurrent() - startTime

        #expect(try context.fetch(FetchDescriptor<StoredMedication>()).count == 50)
        #expect(duration < 0.200, "Batch insert 50 medications should complete within 200ms")
    }
}
