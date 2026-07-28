import Foundation
import Testing
@testable import MedicationAdherenceCore

@Test func fixedLocalTimeScheduleCreatesExpectedDoses() async throws {
    let medication = Medication(
        displayName: "Artificial Tears",
        kind: .overTheCounter,
        inputSource: .manual
    )
    let plan = try MedicationPlan(
        medicationID: medication.id,
        dose: DoseAmount(value: 1, unit: "drop"),
        startDate: DateOnly(year: 2026, month: 6, day: 1),
        endDate: DateOnly(year: 2026, month: 6, day: 2),
        timingRule: .fixedLocalTimes([
            TimeOfDay(hour: 8, minute: 0),
            TimeOfDay(hour: 21, minute: 30)
        ]),
        timeZonePolicy: .localClock,
        sourceNote: "User-confirmed reminder plan"
    )

    let doses = try ReminderScheduleEngine().scheduledDoses(
        for: plan,
        timeZone: TimeZone(identifier: "Asia/Shanghai")!
    )

    #expect(doses.count == 4)
    #expect(doses.map(\.dose.unit).allSatisfy { $0 == "drop" })
}

@Test func fixedIntervalScheduleCreatesExpectedDoses() async throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let start = calendar.date(from: DateComponents(year: 2026, month: 6, day: 1, hour: 0, minute: 0))!

    let plan = MedicationPlan(
        medicationID: UUID(),
        dose: DoseAmount(value: 1, unit: "tablet"),
        startDate: DateOnly(year: 2026, month: 6, day: 1),
        endDate: DateOnly(year: 2026, month: 6, day: 1),
        timingRule: .fixedInterval(start: start, intervalHours: 8),
        timeZonePolicy: .fixedInterval,
        sourceNote: "Interval-based plan"
    )

    let doses = try ReminderScheduleEngine().scheduledDoses(
        for: plan,
        timeZone: TimeZone(secondsFromGMT: 0)!
    )

    #expect(doses.count == 3)
}

@Test func adherenceSummaryCountsStatuses() async throws {
    let scheduled = [
        ScheduledDose(planID: UUID(), dueAt: Date(), dose: DoseAmount(value: 1, unit: "tablet")),
        ScheduledDose(planID: UUID(), dueAt: Date(), dose: DoseAmount(value: 1, unit: "tablet"))
    ]
    let events = [
        DoseEvent(scheduledDoseID: scheduled[0].id, status: .taken, recordedAt: Date()),
        DoseEvent(scheduledDoseID: scheduled[1].id, status: .skipped, recordedAt: Date(), reason: "Forgot")
    ]

    let summary = AdherenceCalculator().summarize(scheduledDoses: scheduled, events: events)

    #expect(summary.scheduledCount == 2)
    #expect(summary.takenCount == 1)
    #expect(summary.skippedCount == 1)
    #expect(summary.completionRate == 0.5)
}

@Test func adherenceSummaryUsesOnlyTheLatestEventForEachScheduledDose() {
    let scheduledDose = ScheduledDose(
        planID: UUID(),
        dueAt: Date(timeIntervalSince1970: 1_700_000_000),
        dose: DoseAmount(value: 1, unit: "tablet")
    )
    let events = [
        DoseEvent(
            scheduledDoseID: scheduledDose.id,
            status: .delayed,
            recordedAt: Date(timeIntervalSince1970: 1_700_000_010)
        ),
        DoseEvent(
            scheduledDoseID: scheduledDose.id,
            status: .taken,
            recordedAt: Date(timeIntervalSince1970: 1_700_000_020)
        ),
        DoseEvent(
            scheduledDoseID: scheduledDose.id,
            status: .corrected,
            recordedAt: Date(timeIntervalSince1970: 1_700_000_030)
        )
    ]

    let summary = AdherenceCalculator().summarize(
        scheduledDoses: [scheduledDose],
        events: events
    )

    #expect(summary.scheduledCount == 1)
    #expect(summary.takenCount == 1)
    #expect(summary.skippedCount == 0)
    #expect(summary.delayedCount == 0)
    #expect(summary.completionRate == 1)
}

@Test func adherenceRatesRemainWithinTheZeroToOneDomainInvariant() {
    let excessive = AdherenceSummary(
        scheduledCount: 1,
        takenCount: 2,
        skippedCount: 0,
        delayedCount: 0
    )
    let negative = AdherenceSummary(
        scheduledCount: 1,
        takenCount: -1,
        skippedCount: 0,
        delayedCount: 0
    )

    #expect(excessive.completionRate == 1)
    #expect(negative.completionRate == 0)
}

@Test func reminderScheduleRejectsAnInvalidCalendarDate() throws {
    let plan = MedicationPlan(
        medicationID: UUID(),
        dose: DoseAmount(value: 1, unit: "tablet"),
        startDate: DateOnly(year: 2026, month: 2, day: 31),
        endDate: DateOnly(year: 2026, month: 3, day: 1),
        timingRule: .fixedLocalTimes([try TimeOfDay(hour: 8, minute: 0)]),
        timeZonePolicy: .localClock,
        sourceNote: "Invalid-date regression"
    )

    #expect(throws: MedicationPlanError.invalidCalendarDate) {
        _ = try ReminderScheduleEngine().scheduledDoses(
            for: plan,
            timeZone: try #require(TimeZone(identifier: "Asia/Shanghai"))
        )
    }
}
