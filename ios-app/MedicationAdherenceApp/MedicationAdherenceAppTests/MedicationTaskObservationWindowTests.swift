import Foundation
import Testing
@testable import MedicationAdherenceApp

struct MedicationTaskObservationWindowTests {
    @Test
    func medicationOverviewWindowCoversNinetyHistoricalDaysAndEightFutureDays() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let referenceDate = Date(timeIntervalSince1970: 1_800_043_210)
        let dayStart = calendar.startOfDay(for: referenceDate)

        let window = MedicationTaskObservationWindow.medicationOverview(
            referenceDate: referenceDate,
            calendar: calendar
        )

        #expect(window.start == calendar.date(byAdding: .day, value: -90, to: dayStart))
        #expect(window.end == calendar.date(byAdding: .day, value: 8, to: dayStart))
    }

    @Test
    func todayWindowUsesStartOfDayAndExclusiveNextDayEnd() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let referenceDate = Date(timeIntervalSince1970: 1_800_043_210)
        let dayStart = calendar.startOfDay(for: referenceDate)

        let window = MedicationTaskObservationWindow.today(
            referenceDate: referenceDate,
            calendar: calendar
        )

        #expect(window.start == dayStart)
        #expect(window.end == calendar.date(byAdding: .day, value: 1, to: dayStart))
    }
}
