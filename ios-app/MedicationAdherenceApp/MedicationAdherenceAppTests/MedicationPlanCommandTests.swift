import Foundation
import MedicationAdherenceCore
import SwiftData
import Testing
@testable import MedicationAdherenceApp

@Suite(.serialized)
struct MedicationPlanCommandTests {
    @Test @MainActor
    func createsPlanAndReturnsCommittedReminderBatch() throws {
        let fixture = try MedicationPlanFixture()
        let reminderTime = fixture.calendar.date(
            bySettingHour: 8,
            minute: 30,
            second: 0,
            of: fixture.courseStart
        )!

        let outcome = MedicationPlanCommand(
            modelContext: fixture.context,
            calendar: fixture.calendar
        ).update(
            MedicationPlanUpdate(
                medicationID: fixture.medication.id,
                planID: nil,
                doseValue: 1,
                doseUnit: " 片 ",
                doseEffectiveFrom: fixture.courseStart,
                doseChangeNote: "首次计划",
                courseStartAt: fixture.courseStart,
                courseEndAt: fixture.courseEnd,
                reminderTimes: [reminderTime],
                reminderDeliveryMethod: .notification,
                escalatesToAlarmWhenUnhandled: true,
                sourceNote: " 复诊确认 "
            )
        )

        guard case let .committed(planID, created, reminderBatch) = outcome else {
            Issue.record("Expected plan creation to commit")
            return
        }
        #expect(created)
        #expect(reminderBatch.medication.id == fixture.medication.id)
        #expect(reminderBatch.tasks.allSatisfy { $0.planID == planID })

        let verificationContext = ModelContext(fixture.container)
        let plans = try verificationContext.fetch(FetchDescriptor<StoredMedicationPlan>())
        let plan = try #require(plans.first)
        #expect(plans.count == 1)
        #expect(plan.id == planID)
        #expect(plan.doseValue == 1)
        #expect(plan.doseUnit == "片")
        #expect(plan.reminderTimesRaw == "08:30")
        #expect(plan.timingSummary == "每日 08:30")
        #expect(plan.sourceNote == "复诊确认")
        #expect(try verificationContext.fetch(FetchDescriptor<StoredMedicationDoseChange>()).count == 1)
        #expect(!reminderBatch.tasks.isEmpty)
    }

    @Test @MainActor
    func saveFailureRestoresPlanAndTasksWithoutLeavingDoseChange() throws {
        let fixture = try MedicationPlanFixture()
        let (plan, task) = try fixture.insertExistingPlan()
        let originalDueAt = task.dueAt
        let originalReminderTimes = plan.reminderTimesRaw
        let command = MedicationPlanCommand(
            modelContext: fixture.context,
            calendar: fixture.calendar
        ) { _ in
            throw SyntheticPlanSaveError.unavailable
        }
        let changedReminderTime = fixture.calendar.date(
            bySettingHour: 9,
            minute: 45,
            second: 0,
            of: fixture.courseStart
        )!

        let outcome = command.update(
            MedicationPlanUpdate(
                medicationID: fixture.medication.id,
                planID: plan.id,
                doseValue: 2,
                doseUnit: "粒",
                doseEffectiveFrom: fixture.courseStart,
                doseChangeNote: "复诊调整",
                courseStartAt: fixture.courseStart,
                courseEndAt: fixture.courseEnd,
                reminderTimes: [changedReminderTime],
                reminderDeliveryMethod: .alarm,
                escalatesToAlarmWhenUnhandled: false,
                sourceNote: "变更备注"
            )
        )

        guard case .saveFailed = outcome else {
            Issue.record("Expected save failure")
            return
        }
        #expect(plan.doseValue == 1)
        #expect(plan.doseUnit == "片")
        #expect(plan.reminderTimesRaw == originalReminderTimes)
        #expect(plan.reminderDeliveryMethod == .notification)
        #expect(plan.escalatesToAlarmWhenUnhandled)
        #expect(task.dueAt == originalDueAt)
        #expect(task.doseValue == 1)
        #expect(task.doseUnit == "片")
        #expect(task.status == .pending)
        #expect(try fixture.context.fetch(FetchDescriptor<StoredMedicationDoseChange>()).isEmpty)
        #expect(!fixture.context.hasChanges)
    }

    @Test @MainActor
    func updatesExistingPlanWithoutCreatingDuplicate() throws {
        let fixture = try MedicationPlanFixture()
        let (plan, _) = try fixture.insertExistingPlan()
        let reminderTime = fixture.calendar.date(
            bySettingHour: 7,
            minute: 15,
            second: 0,
            of: fixture.courseStart
        )!

        let outcome = MedicationPlanCommand(
            modelContext: fixture.context,
            calendar: fixture.calendar
        ).update(
            MedicationPlanUpdate(
                medicationID: fixture.medication.id,
                planID: plan.id,
                doseValue: 1,
                doseUnit: "片",
                doseEffectiveFrom: fixture.courseStart,
                doseChangeNote: "",
                courseStartAt: fixture.courseStart,
                courseEndAt: fixture.courseEnd,
                reminderTimes: [reminderTime],
                reminderDeliveryMethod: .notification,
                escalatesToAlarmWhenUnhandled: true,
                sourceNote: "更新时间"
            )
        )

        guard case let .committed(planID, created, _) = outcome else {
            Issue.record("Expected existing plan update to commit")
            return
        }
        #expect(planID == plan.id)
        #expect(!created)
        let verificationContext = ModelContext(fixture.container)
        let plans = try verificationContext.fetch(FetchDescriptor<StoredMedicationPlan>())
        #expect(plans.count == 1)
        #expect(plans.first?.reminderTimesRaw == "07:15")
        #expect(plans.first?.sourceNote == "更新时间")
        #expect(try verificationContext.fetch(FetchDescriptor<StoredMedicationDoseChange>()).isEmpty)
    }

    @Test @MainActor
    func doseChangeDoesNotRewriteCompletedTaskHistory() throws {
        let fixture = try MedicationPlanFixture()
        let (plan, task) = try fixture.insertExistingPlan()
        task.status = .taken
        task.recordedAt = task.dueAt.addingTimeInterval(120)
        try fixture.context.save()

        let outcome = MedicationPlanCommand(
            modelContext: fixture.context,
            calendar: fixture.calendar
        ).update(
            MedicationPlanUpdate(
                medicationID: fixture.medication.id,
                planID: plan.id,
                doseValue: 2,
                doseUnit: "粒",
                doseEffectiveFrom: fixture.courseStart,
                doseChangeNote: "复诊调整",
                courseStartAt: fixture.courseStart,
                courseEndAt: fixture.courseEnd,
                reminderTimes: [task.dueAt],
                reminderDeliveryMethod: .notification,
                escalatesToAlarmWhenUnhandled: true,
                sourceNote: ""
            )
        )

        guard case .committed = outcome else {
            Issue.record("Expected plan update to commit")
            return
        }
        let verificationContext = ModelContext(fixture.container)
        let persistedTask = try #require(
            verificationContext.fetch(FetchDescriptor<StoredDoseTask>())
                .first { $0.id == task.id }
        )
        #expect(persistedTask.status == .taken)
        #expect(persistedTask.doseValue == 1)
        #expect(persistedTask.doseUnit == "片")
    }

    @Test @MainActor
    func emptyDoseUnitIsRejectedWithoutWriting() throws {
        let fixture = try MedicationPlanFixture()
        let reminderTime = fixture.calendar.date(
            bySettingHour: 8,
            minute: 30,
            second: 0,
            of: fixture.courseStart
        )!

        let outcome = MedicationPlanCommand(
            modelContext: fixture.context,
            calendar: fixture.calendar
        ).update(
            MedicationPlanUpdate(
                medicationID: fixture.medication.id,
                planID: nil,
                doseValue: 1,
                doseUnit: "   ",
                doseEffectiveFrom: fixture.courseStart,
                doseChangeNote: "",
                courseStartAt: fixture.courseStart,
                courseEndAt: fixture.courseEnd,
                reminderTimes: [reminderTime],
                reminderDeliveryMethod: .notification,
                escalatesToAlarmWhenUnhandled: true,
                sourceNote: ""
            )
        )

        guard case .rejected(.emptyDoseUnit) = outcome else {
            Issue.record("Expected empty dose unit rejection")
            return
        }
        #expect(try fixture.context.fetch(FetchDescriptor<StoredMedicationPlan>()).isEmpty)
        #expect(!fixture.context.hasChanges)
    }
}

@MainActor
private struct MedicationPlanFixture {
    let container: ModelContainer
    let context: ModelContext
    let medication: StoredMedication
    var calendar: Calendar
    let courseStart: Date
    let courseEnd: Date

    init() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 8 * 60 * 60)!
        self.calendar = calendar
        courseStart = calendar.date(from: DateComponents(year: 2026, month: 7, day: 27))!
        courseEnd = calendar.date(from: DateComponents(year: 2026, month: 8, day: 27))!
        container = try MedicationAdherenceModelContainer.make(isStoredInMemoryOnly: true)
        context = ModelContext(container)
        context.autosaveEnabled = false
        medication = StoredMedication(
            displayName: "测试药品",
            kind: .prescription,
            inputSource: .manual
        )
        context.insert(medication)
        try context.save()
    }

    func insertExistingPlan() throws -> (StoredMedicationPlan, StoredDoseTask) {
        let reminderTime = calendar.date(
            bySettingHour: 8,
            minute: 30,
            second: 0,
            of: courseStart
        )!
        let plan = StoredMedicationPlan(
            medicationID: medication.id,
            doseValue: 1,
            doseUnit: "片",
            timingSummary: "每日 08:30",
            timeZonePolicy: .localClock,
            sourceNote: "原始备注",
            courseStartAt: courseStart,
            courseEndAt: courseEnd,
            reminderTimesRaw: "08:30",
            reminderDelivery: .notification,
            escalatesToAlarmWhenUnhandled: true
        )
        let task = StoredDoseTask(
            medicationID: medication.id,
            planID: plan.id,
            dueAt: reminderTime,
            doseValue: 1,
            doseUnit: "片"
        )
        context.insert(plan)
        context.insert(task)
        try context.save()
        return (plan, task)
    }
}

private enum SyntheticPlanSaveError: Error {
    case unavailable
}
