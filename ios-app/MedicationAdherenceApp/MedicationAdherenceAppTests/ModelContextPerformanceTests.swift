import Testing
import SwiftData
@testable import MedicationAdherenceApp

@MainActor
struct ModelContextPerformanceTests {
    private let modelContainer: ModelContainer

    init() throws {
        let schema = Schema([
            StoredMedication.self,
            StoredMedicationPlan.self,
            StoredDoseTask.self,
            StoredDoseActionLog.self,
            StoredMedicationDoseChange.self,
            StoredMedicationInventoryRecord.self,
            StoredMedicationRiskDetection.self,
            StoredDrugLabelSection.self
        ])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        modelContainer = try ModelContainer(for: schema, configurations: config)
    }

    @Test("Fetch single medication should complete within performance threshold")
    func fetchSingleMedication() throws {
        let context = modelContainer.mainContext
        let medication = StoredMedication(
            brandName: "测试药品",
            genericName: nil,
            formulation: "片剂"
        )
        context.insert(medication)
        try context.save()

        let startTime = CFAbsoluteTimeGetCurrent()
        let result = try ModelContextPerformanceMetrics.measureFetch(operation: "fetch-single-medication") {
            let descriptor = FetchDescriptor<StoredMedication>(
                predicate: #Predicate { $0.id == medication.id }
            )
            return try context.fetch(descriptor).first
        }
        let duration = CFAbsoluteTimeGetCurrent() - startTime

        #expect(result != nil)
        #expect(duration < 0.100, "Fetch single medication should complete within 100ms")
    }

    @Test("Fetch multiple medications should complete within performance threshold")
    func fetchMultipleMedications() throws {
        let context = modelContainer.mainContext

        for i in 0..<20 {
            let medication = StoredMedication(
                brandName: "测试药品\(i)",
                genericName: nil,
                formulation: "片剂"
            )
            context.insert(medication)
        }
        try context.save()

        let startTime = CFAbsoluteTimeGetCurrent()
        let results = try ModelContextPerformanceMetrics.measureFetch(operation: "fetch-all-medications") {
            let descriptor = FetchDescriptor<StoredMedication>()
            return try context.fetch(descriptor)
        }
        let duration = CFAbsoluteTimeGetCurrent() - startTime

        #expect(results.count == 20)
        #expect(duration < 0.100, "Fetch 20 medications should complete within 100ms")
    }

    @Test("Save single medication should complete within performance threshold")
    func saveSingleMedication() throws {
        let context = modelContainer.mainContext
        let medication = StoredMedication(
            brandName: "测试药品",
            genericName: nil,
            formulation: "片剂"
        )
        context.insert(medication)

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
        let medication = StoredMedication(
            brandName: "测试药品",
            genericName: nil,
            formulation: "片剂"
        )
        context.insert(medication)

        let plan = StoredMedicationPlan(
            medicationID: medication.id,
            doseValue: 1.0,
            doseUnit: "片",
            timingSummary: "每日 08:00",
            timeZonePolicy: .localClock,
            sourceNote: "测试计划",
            requiresUserConfirmation: true,
            courseStartAt: Date(),
            courseEndAt: nil,
            reminderTimesRaw: "08:00",
            reminderDelivery: .notification,
            escalatesToAlarmWhenUnhandled: false
        )
        context.insert(plan)

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
        let medication = StoredMedication(
            brandName: "测试药品",
            genericName: nil,
            formulation: "片剂"
        )
        context.insert(medication)

        let plan = StoredMedicationPlan(
            medicationID: medication.id,
            doseValue: 1.0,
            doseUnit: "片",
            timingSummary: "每日 08:00",
            timeZonePolicy: .localClock,
            sourceNote: "测试计划",
            requiresUserConfirmation: true,
            courseStartAt: Date(),
            courseEndAt: nil,
            reminderTimesRaw: "08:00",
            reminderDelivery: .notification,
            escalatesToAlarmWhenUnhandled: false
        )
        context.insert(plan)

        for i in 0..<10 {
            let task = StoredDoseTask(
                medicationID: medication.id,
                planID: plan.id,
                dueAt: Date().addingTimeInterval(Double(i) * 3600),
                doseValue: 1.0,
                doseUnit: "片",
                status: .pending
            )
            context.insert(task)
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

    @Test("Delete medication cascade should complete within performance threshold")
    func deleteMedicationCascade() throws {
        let context = modelContainer.mainContext
        let medication = StoredMedication(
            brandName: "测试药品",
            genericName: nil,
            formulation: "片剂"
        )
        context.insert(medication)

        let plan = StoredMedicationPlan(
            medicationID: medication.id,
            doseValue: 1.0,
            doseUnit: "片",
            timingSummary: "每日 08:00",
            timeZonePolicy: .localClock,
            sourceNote: "测试计划",
            requiresUserConfirmation: true,
            courseStartAt: Date(),
            courseEndAt: nil,
            reminderTimesRaw: "08:00",
            reminderDelivery: .notification,
            escalatesToAlarmWhenUnhandled: false
        )
        context.insert(plan)
        try context.save()

        let startTime = CFAbsoluteTimeGetCurrent()
        try ModelContextPerformanceMetrics.measureDelete(operation: "delete-medication-cascade") {
            context.delete(medication)
            try context.save()
        }
        let duration = CFAbsoluteTimeGetCurrent() - startTime

        #expect(duration < 0.150, "Delete medication with cascade should complete within 150ms")
    }

    @Test("Complex query with predicates should complete within performance threshold")
    func complexQueryWithPredicates() throws {
        let context = modelContainer.mainContext

        for i in 0..<30 {
            let medication = StoredMedication(
                brandName: "测试药品\(i)",
                genericName: i % 2 == 0 ? "通用名\(i)" : nil,
                formulation: i % 3 == 0 ? "片剂" : "胶囊"
            )
            if i % 5 == 0 {
                medication.lifecycleStatusRaw = "archived"
            }
            context.insert(medication)
        }
        try context.save()

        let startTime = CFAbsoluteTimeGetCurrent()
        let results = try ModelContextPerformanceMetrics.measureFetch(operation: "complex-query-with-predicates") {
            let descriptor = FetchDescriptor<StoredMedication>(
                predicate: #Predicate { medication in
                    medication.lifecycleStatusRaw != "archived" && medication.formulation == "片剂"
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
            for i in 0..<50 {
                let medication = StoredMedication(
                    brandName: "测试药品\(i)",
                    genericName: nil,
                    formulation: "片剂"
                )
                context.insert(medication)
            }
            try context.save()
        }
        let duration = CFAbsoluteTimeGetCurrent() - startTime

        #expect(duration < 0.200, "Batch insert 50 medications should complete within 200ms")
    }
}
