import Foundation
import Testing
@testable import MedicationAdherenceApp

@MainActor
struct VisitSummaryDateRangeTests {
    @Test(arguments: ["UTC", "Asia/Shanghai", "America/New_York"])
    func selectedDayIncludesItsFinalFractionalSecond(timeZone: String) throws {
        let calendar = try calendar(timeZone)
        for (month, day) in [(10, 1), (3, 8), (11, 1)] {
            let selected = try date(2026, month, day, calendar: calendar)
            let start = calendar.startOfDay(for: selected)
            let nextDay = try #require(calendar.date(byAdding: .day, value: 1, to: start))
            let range = VisitSummaryDateRange.normalized(
                startDate: selected, endDate: selected, calendar: calendar
            )

            #expect(range.start == start)
            #expect(range.endExclusive == nextDay)
            for offset in [-1.0, -0.999, -0.5, -0.001] {
                let instant = nextDay.addingTimeInterval(offset)
                #expect(instant >= range.start && instant < range.endExclusive)
            }
            #expect(!(nextDay >= range.start && nextDay < range.endExclusive))
            #expect(VisitSummaryDateRange.inclusiveEndDate(
                endDateExclusive: range.endExclusive, calendar: calendar
            ) == start)

            if timeZone == "America/New_York" && month == 3 {
                #expect(range.endExclusive.timeIntervalSince(range.start) == 23 * 3600)
            } else if timeZone == "America/New_York" && month == 11 {
                #expect(range.endExclusive.timeIntervalSince(range.start) == 25 * 3600)
            } else {
                #expect(range.endExclusive.timeIntervalSince(range.start) == 24 * 3600)
            }
        }
    }

    @Test(arguments: ["UTC", "Asia/Shanghai", "America/New_York"])
    func reversedAndMultiDaySelectionsKeepBothSelectedDates(timeZone: String) throws {
        let calendar = try calendar(timeZone)
        for (startParts, endParts) in [
            ((2026, 12, 31), (2027, 1, 1)),
            ((2024, 2, 28), (2024, 2, 29)),
            ((2026, 3, 7), (2026, 3, 9)),
            ((2026, 10, 31), (2026, 11, 2))
        ] {
            let first = try date(startParts.0, startParts.1, startParts.2, calendar: calendar)
            let last = try date(endParts.0, endParts.1, endParts.2, calendar: calendar)
            let forward = VisitSummaryDateRange.normalized(startDate: first, endDate: last, calendar: calendar)
            let reversed = VisitSummaryDateRange.normalized(startDate: last, endDate: first, calendar: calendar)
            #expect(forward.start == reversed.start)
            #expect(forward.endExclusive == reversed.endExclusive)
            #expect(forward.start == calendar.startOfDay(for: first))
            #expect(VisitSummaryDateRange.inclusiveEndDate(
                endDateExclusive: forward.endExclusive, calendar: calendar
            ) == calendar.startOfDay(for: last))
        }
    }

    @Test
    func midnightOffsetChangeUsesCalendarDayBoundary() throws {
        let calendar = try calendar("America/Sao_Paulo")
        let selected = try date(2018, 11, 4, calendar: calendar)
        let nextDay = try date(2018, 11, 5, calendar: calendar)
        let range = VisitSummaryDateRange.normalized(startDate: selected, endDate: selected, calendar: calendar)
        #expect(calendar.component(.hour, from: range.start) == 1)
        #expect(range.endExclusive == calendar.startOfDay(for: nextDay))
        #expect(range.endExclusive.timeIntervalSince(range.start) == 23 * 3600)
        #expect(VisitSummaryDateRange.inclusiveEndDate(
            endDateExclusive: range.endExclusive, calendar: calendar
        ) == range.start)
    }

    @Test
    func reportLabelShowsInclusiveSelectedDates() throws {
        let calendar = Calendar.current
        let first = try date(2026, 10, 1, calendar: calendar)
        let last = try date(2026, 10, 3, calendar: calendar)
        for selectedEnd in [first, last] {
            let range = VisitSummaryDateRange.normalized(startDate: first, endDate: selectedEnd)
            let expected = "\(AppFormatters.day.string(from: first)) - \(AppFormatters.day.string(from: selectedEnd))"
            #expect(VisitSummaryDateRange.displayText(
                startDate: range.start, endDateExclusive: range.endExclusive
            ) == expected)
        }
    }

    private func calendar(_ timeZone: String) throws -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: timeZone))
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, calendar: Calendar) throws -> Date {
        try #require(calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12)))
    }
}
