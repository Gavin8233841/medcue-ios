import Foundation
import MedicationAdherenceCore
import SwiftData
import Testing
@testable import MedicationAdherenceApp

@Suite(.serialized)
struct MedicationCreationCommandTests {
    @Test @MainActor
    func creationCommitsMedicationPlanStockAndReminderBatchTogether() throws {
        let fixture = try MedicationCreationFixture()
        let morning = fixture.date(hour: 8, minute: 30)
        let evening = fixture.date(hour: 20, minute: 15)

        let outcome = MedicationCreationCommand(
            modelContext: fixture.context,
            calendar: fixture.calendar
        ).create(
            fixture.input(
                displayName: "  测试药  ",
                reminderTimes: [evening, morning, morning],
                initialStockQuantity: 12,
                lowStockThreshold: 3,
                stockUnit: " 片 "
            )
        )

        guard case let .committed(medicationID, planID, reminderBatch) = outcome else {
            Issue.record("Expected medication creation to commit")
            return
        }
        let medication = try #require(try fixture.context.fetch(FetchDescriptor<StoredMedication>()).first)
        let plan = try #require(try fixture.context.fetch(FetchDescriptor<StoredMedicationPlan>()).first)
        let stock = try #require(try fixture.context.fetch(FetchDescriptor<StoredMedicationStock>()).first)
        #expect(medication.id == medicationID)
        #expect(medication.displayName == "测试药")
        #expect(plan.id == planID)
        #expect(plan.medicationID == medicationID)
        #expect(plan.reminderTimesRaw == "08:30,20:15")
        #expect(plan.timingSummary == "每日 08:30、20:15")
        #expect(stock.medicationID == medicationID)
        #expect(stock.remainingQuantity == 12)
        #expect(stock.unit == "片")
        #expect(reminderBatch.medication.id == medicationID)
        #expect(reminderBatch.tasks.allSatisfy { $0.planID == planID })
        #expect(!reminderBatch.tasks.isEmpty)
    }

    @Test @MainActor
    func zeroStockInputDoesNotCreateAStockRecord() throws {
        let fixture = try MedicationCreationFixture()

        let outcome = MedicationCreationCommand(
            modelContext: fixture.context,
            calendar: fixture.calendar
        ).create(fixture.input())

        guard case .committed = outcome else {
            Issue.record("Expected medication creation to commit")
            return
        }
        #expect(try fixture.context.fetch(FetchDescriptor<StoredMedicationStock>()).isEmpty)
    }

    @Test @MainActor
    func invalidMedicationNameIsRejectedWithoutWriting() throws {
        let fixture = try MedicationCreationFixture()

        let outcome = MedicationCreationCommand(
            modelContext: fixture.context,
            calendar: fixture.calendar
        ).create(fixture.input(displayName: " \n "))

        #expect(outcome.isRejectedInvalidName)
        #expect(try fixture.context.fetch(FetchDescriptor<StoredMedication>()).isEmpty)
        #expect(try fixture.context.fetch(FetchDescriptor<StoredMedicationPlan>()).isEmpty)
    }

    @Test @MainActor
    func saveFailureLeavesNoPartialMedicationGraph() throws {
        let fixture = try MedicationCreationFixture()

        let outcome = MedicationCreationCommand(
            modelContext: fixture.context,
            calendar: fixture.calendar,
            saveOperation: { _ in throw SyntheticMedicationCreationSaveError.unavailable }
        ).create(
            fixture.input(
                initialStockQuantity: 8,
                lowStockThreshold: 2,
                stockUnit: "片"
            )
        )

        guard case .saveFailed = outcome else {
            Issue.record("Expected save failure")
            return
        }
        #expect(try fixture.context.fetch(FetchDescriptor<StoredMedication>()).isEmpty)
        #expect(try fixture.context.fetch(FetchDescriptor<StoredMedicationPlan>()).isEmpty)
        #expect(try fixture.context.fetch(FetchDescriptor<StoredMedicationStock>()).isEmpty)
        #expect(try fixture.context.fetch(FetchDescriptor<StoredDoseTask>()).isEmpty)
        #expect(!fixture.context.hasChanges)
    }
}

private extension MedicationCreationCommandOutcome {
    var isRejectedInvalidName: Bool {
        guard case .rejected(.invalidMedicationName) = self else {
            return false
        }
        return true
    }
}

private enum SyntheticMedicationCreationSaveError: Error {
    case unavailable
}

@MainActor
private struct MedicationCreationFixture {
    let container: ModelContainer
    let context: ModelContext
    let calendar: Calendar
    let courseStart: Date
    let courseEnd: Date

    init() throws {
        var configuredCalendar = Calendar(identifier: .gregorian)
        configuredCalendar.timeZone = TimeZone(secondsFromGMT: 8 * 60 * 60)!
        calendar = configuredCalendar
        courseStart = configuredCalendar.date(from: DateComponents(year: 2026, month: 7, day: 26))!
        courseEnd = configuredCalendar.date(byAdding: .day, value: 2, to: courseStart)!
        container = try ModelContainer(
            for: StoredMedication.self,
            StoredMedicationPlan.self,
            StoredMedicationStock.self,
            StoredDoseTask.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        context = ModelContext(container)
    }

    func date(hour: Int, minute: Int) -> Date {
        calendar.date(bySettingHour: hour, minute: minute, second: 0, of: courseStart)!
    }

    func input(
        displayName: String = "测试药",
        reminderTimes: [Date]? = nil,
        initialStockQuantity: Double = 0,
        lowStockThreshold: Double = 0,
        stockUnit: String = "片"
    ) -> MedicationCreationInput {
        MedicationCreationInput(
            displayName: displayName,
            genericName: "通用名",
            kind: .overTheCounter,
            form: "片剂",
            strength: "10 mg",
            inputSource: .manual,
            photoSymbolName: "pills.fill",
            photoData: nil,
            boxNumber: "A-1",
            notes: "来源说明",
            doseValue: 1,
            doseUnit: "片",
            courseStartAt: courseStart,
            courseEndAt: courseEnd,
            reminderTimes: reminderTimes ?? [date(hour: 8, minute: 30)],
            reminderDeliveryMethod: .notification,
            escalatesToAlarmWhenUnhandled: true,
            initialStockQuantity: initialStockQuantity,
            lowStockThreshold: lowStockThreshold,
            stockUnit: stockUnit,
            createdAt: courseStart
        )
    }
}
