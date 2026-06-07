import Foundation
import Testing
@testable import MedicationAdherenceCore

@Test func adherenceInsightCalculatesDailyStatusAndStreaks() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!

    let scheduled = [
        ScheduledDose(planID: UUID(), dueAt: makeDate(calendar: calendar, day: 1, hour: 8), dose: DoseAmount(value: 1, unit: "tablet")),
        ScheduledDose(planID: UUID(), dueAt: makeDate(calendar: calendar, day: 1, hour: 20), dose: DoseAmount(value: 1, unit: "tablet")),
        ScheduledDose(planID: UUID(), dueAt: makeDate(calendar: calendar, day: 2, hour: 8), dose: DoseAmount(value: 1, unit: "tablet")),
        ScheduledDose(planID: UUID(), dueAt: makeDate(calendar: calendar, day: 3, hour: 8), dose: DoseAmount(value: 1, unit: "tablet"))
    ]
    let events = [
        DoseEvent(scheduledDoseID: scheduled[0].id, status: .taken, recordedAt: makeDate(calendar: calendar, day: 1, hour: 8)),
        DoseEvent(scheduledDoseID: scheduled[1].id, status: .taken, recordedAt: makeDate(calendar: calendar, day: 1, hour: 20)),
        DoseEvent(scheduledDoseID: scheduled[2].id, status: .taken, recordedAt: makeDate(calendar: calendar, day: 2, hour: 8)),
        DoseEvent(scheduledDoseID: scheduled[3].id, status: .skipped, recordedAt: makeDate(calendar: calendar, day: 3, hour: 8))
    ]

    let insight = AdherenceInsightBuilder().build(
        scheduledDoses: scheduled,
        events: events,
        calendar: calendar,
        timeZone: calendar.timeZone,
        now: makeDate(calendar: calendar, day: 4, hour: 12)
    )

    #expect(insight.scheduledCount == 4)
    #expect(insight.takenCount == 3)
    #expect(insight.skippedCount == 1)
    #expect(insight.currentStreakDays == 0)
    #expect(insight.longestStreakDays == 2)
    #expect(insight.dayStatuses.count == 3)
    #expect(insight.safetyNote.contains("不代表疗效判断"))
}

@Test func adherenceInsightUsesLatestDoseEvent() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let scheduled = [
        ScheduledDose(planID: UUID(), dueAt: makeDate(calendar: calendar, day: 1, hour: 8), dose: DoseAmount(value: 1, unit: "tablet"))
    ]
    let events = [
        DoseEvent(scheduledDoseID: scheduled[0].id, status: .skipped, recordedAt: makeDate(calendar: calendar, day: 1, hour: 9)),
        DoseEvent(scheduledDoseID: scheduled[0].id, status: .corrected, recordedAt: makeDate(calendar: calendar, day: 1, hour: 10))
    ]

    let insight = AdherenceInsightBuilder().build(
        scheduledDoses: scheduled,
        events: events,
        calendar: calendar,
        timeZone: calendar.timeZone,
        now: makeDate(calendar: calendar, day: 1, hour: 12)
    )

    #expect(insight.takenCount == 1)
    #expect(insight.skippedCount == 0)
    #expect(insight.currentStreakDays == 1)
    #expect(insight.message.contains("连续完成 1 天"))
}

@Test func adherenceInsightKeepsHistoricalStreakWhenLatestDayIsStillOpen() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!

    let scheduled = [
        ScheduledDose(planID: UUID(), dueAt: makeDate(calendar: calendar, day: 1, hour: 8), dose: DoseAmount(value: 1, unit: "片")),
        ScheduledDose(planID: UUID(), dueAt: makeDate(calendar: calendar, day: 2, hour: 8), dose: DoseAmount(value: 1, unit: "片")),
        ScheduledDose(planID: UUID(), dueAt: makeDate(calendar: calendar, day: 3, hour: 8), dose: DoseAmount(value: 1, unit: "片"))
    ]
    let events = [
        DoseEvent(scheduledDoseID: scheduled[0].id, status: .taken, recordedAt: makeDate(calendar: calendar, day: 1, hour: 8)),
        DoseEvent(scheduledDoseID: scheduled[1].id, status: .taken, recordedAt: makeDate(calendar: calendar, day: 2, hour: 8))
    ]

    let insight = AdherenceInsightBuilder().build(
        scheduledDoses: scheduled,
        events: events,
        calendar: calendar,
        timeZone: calendar.timeZone,
        now: makeDate(calendar: calendar, day: 3, hour: 12)
    )

    #expect(insight.currentStreakDays == 2)
    #expect(insight.longestStreakDays == 2)
    #expect(insight.dayStatuses.last?.isComplete == false)
}

@Test func adherenceInsightKeepsHistoricalStreakWhileTodayIsPartlyHandled() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!

    let scheduled = [
        ScheduledDose(planID: UUID(), dueAt: makeDate(calendar: calendar, day: 1, hour: 8), dose: DoseAmount(value: 1, unit: "片")),
        ScheduledDose(planID: UUID(), dueAt: makeDate(calendar: calendar, day: 2, hour: 8), dose: DoseAmount(value: 1, unit: "片")),
        ScheduledDose(planID: UUID(), dueAt: makeDate(calendar: calendar, day: 3, hour: 8), dose: DoseAmount(value: 1, unit: "片")),
        ScheduledDose(planID: UUID(), dueAt: makeDate(calendar: calendar, day: 3, hour: 20), dose: DoseAmount(value: 1, unit: "片"))
    ]
    let events = [
        DoseEvent(scheduledDoseID: scheduled[0].id, status: .taken, recordedAt: makeDate(calendar: calendar, day: 1, hour: 8)),
        DoseEvent(scheduledDoseID: scheduled[1].id, status: .taken, recordedAt: makeDate(calendar: calendar, day: 2, hour: 8)),
        DoseEvent(scheduledDoseID: scheduled[2].id, status: .delayed, recordedAt: makeDate(calendar: calendar, day: 3, hour: 9))
    ]

    let insight = AdherenceInsightBuilder().build(
        scheduledDoses: scheduled,
        events: events,
        calendar: calendar,
        timeZone: calendar.timeZone,
        now: makeDate(calendar: calendar, day: 3, hour: 12)
    )

    #expect(insight.currentStreakDays == 2)
    #expect(insight.longestStreakDays == 2)
}

@Test func adherenceInsightStopsCurrentStreakAtHistoricalOpenDay() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!

    let scheduled = [
        ScheduledDose(planID: UUID(), dueAt: makeDate(calendar: calendar, day: 1, hour: 8), dose: DoseAmount(value: 1, unit: "片")),
        ScheduledDose(planID: UUID(), dueAt: makeDate(calendar: calendar, day: 2, hour: 8), dose: DoseAmount(value: 1, unit: "片")),
        ScheduledDose(planID: UUID(), dueAt: makeDate(calendar: calendar, day: 3, hour: 8), dose: DoseAmount(value: 1, unit: "片"))
    ]
    let events = [
        DoseEvent(scheduledDoseID: scheduled[0].id, status: .taken, recordedAt: makeDate(calendar: calendar, day: 1, hour: 8))
    ]

    let insight = AdherenceInsightBuilder().build(
        scheduledDoses: scheduled,
        events: events,
        calendar: calendar,
        timeZone: calendar.timeZone,
        now: makeDate(calendar: calendar, day: 3, hour: 12)
    )

    #expect(insight.currentStreakDays == 0)
    #expect(insight.longestStreakDays == 1)
}

private func makeDate(calendar: Calendar, day: Int, hour: Int) -> Date {
    calendar.date(from: DateComponents(
        timeZone: calendar.timeZone,
        year: 2026,
        month: 6,
        day: day,
        hour: hour
    ))!
}
