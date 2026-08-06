import Foundation
import MedicationAdherenceCore
import SwiftData
import Testing
@testable import MedicationAdherenceApp

@Suite(.serialized)
struct MedicationReminderTaskCoordinatorTests {
    @Test @MainActor
    func inactiveReconcileUsesReferenceDayForCancellationAndReportsSameTask() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 8 * 60 * 60)!
        let referenceDate = calendar.date(
            from: DateComponents(year: 2026, month: 7, day: 26, hour: 12)
        )!
        let container = try MedicationAdherenceModelContainer.make(isStoredInMemoryOnly: true)
        let context = ModelContext(container)
        context.autosaveEnabled = false
        let medication = StoredMedication(
            displayName: "测试药",
            kind: .overTheCounter,
            inputSource: .manual,
            lifecycleStatus: .interrupted,
            createdAt: referenceDate
        )
        let plan = StoredMedicationPlan(
            medicationID: medication.id,
            doseValue: 1,
            doseUnit: "片",
            timingSummary: "每日 08:00",
            timeZonePolicy: .localClock,
            sourceNote: "",
            courseStartAt: calendar.startOfDay(for: referenceDate),
            reminderTimesRaw: "08:00"
        )
        let task = StoredDoseTask(
            medicationID: medication.id,
            planID: plan.id,
            dueAt: calendar.date(bySettingHour: 8, minute: 0, second: 0, of: referenceDate)!,
            doseValue: 1,
            doseUnit: "片"
        )
        context.insert(medication)
        context.insert(plan)
        context.insert(task)
        try context.save()

        let batches = MedicationReminderTaskCoordinator(
            calendar: calendar,
            referenceDate: referenceDate
        ).reconcileAllPlans(in: context)

        let batch = try #require(batches.first)
        #expect(batches.count == 1)
        #expect(batch.tasks.isEmpty)
        #expect(batch.cancelledTaskIDs == [task.id])
        #expect(task.status == .skipped)
        #expect(task.recordedAt == nil)
        #expect(task.reason == "药物已中断，未来提醒已停用。")
    }
}
