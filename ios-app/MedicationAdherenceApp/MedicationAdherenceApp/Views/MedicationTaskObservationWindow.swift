import Foundation

struct MedicationTaskObservationWindow: Equatable {
    let start: Date
    let end: Date

    static func medicationOverview(
        referenceDate: Date = Date(),
        calendar: Calendar = .current
    ) -> MedicationTaskObservationWindow {
        make(
            referenceDate: referenceDate,
            calendar: calendar,
            historicalDayCount: 90,
            futureDayCount: 8
        )
    }

    static func today(
        referenceDate: Date = Date(),
        calendar: Calendar = .current
    ) -> MedicationTaskObservationWindow {
        make(
            referenceDate: referenceDate,
            calendar: calendar,
            historicalDayCount: 0,
            futureDayCount: 1
        )
    }

    private static func make(
        referenceDate: Date,
        calendar: Calendar,
        historicalDayCount: Int,
        futureDayCount: Int
    ) -> MedicationTaskObservationWindow {
        let dayStart = calendar.startOfDay(for: referenceDate)
        let start = calendar.date(
            byAdding: .day,
            value: -historicalDayCount,
            to: dayStart
        ) ?? dayStart.addingTimeInterval(TimeInterval(-historicalDayCount * 86_400))
        let end = calendar.date(
            byAdding: .day,
            value: futureDayCount,
            to: dayStart
        ) ?? dayStart.addingTimeInterval(TimeInterval(futureDayCount * 86_400))
        return MedicationTaskObservationWindow(start: start, end: end)
    }
}
