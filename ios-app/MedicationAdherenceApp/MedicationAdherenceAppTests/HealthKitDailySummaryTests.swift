import Foundation
import HealthKit
import MedicationAdherenceCore
import Testing
@testable import MedicationAdherenceApp

struct HealthKitDailySummaryTests {
    @Test
    func overnightSleepMergesDuplicatesAndKeepsStagesFromOneSource() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let day = try #require(calendar.date(from: DateComponents(year: 2026, month: 1, day: 2)))
        func time(_ hours: Double) -> Date { day.addingTimeInterval(hours * 3600) }
        let core = HKCategoryValueSleepAnalysis.asleepCore.rawValue
        let deep = HKCategoryValueSleepAnalysis.asleepDeep.rawValue
        let records: [HealthKitSleepRecord] = [
            .init(start: time(-1), end: time(3), stage: core, source: "watch"),
            .init(start: time(0), end: time(3), stage: core, source: "watch"),
            .init(start: time(3), end: time(5), stage: deep, source: "watch"),
            .init(start: time(-2), end: time(7), stage: HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue, source: "other"),
            .init(start: time(-3), end: time(8), stage: HKCategoryValueSleepAnalysis.inBed.rawValue, source: "watch")
        ]
        let samples = HealthKitSleepSummary.samples(from: records, start: day, end: time(10), calendar: calendar)
        #expect(samples.first { $0.kind == .sleepDuration }?.value == 6)
        #expect(samples.first { $0.kind == .sleepCore }?.value == 4)
        #expect(samples.first { $0.kind == .sleepDeep }?.value == 2)
        #expect(samples.allSatisfy { calendar.isDate($0.measuredAt, inSameDayAs: day) })
        #expect(HealthKitSleepSummary.samples(from: [], start: day, end: time(10), calendar: calendar).isEmpty)
    }

    @Test
    func sleepCrossingNoonIsClippedToEachDay() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let day = try #require(calendar.date(from: DateComponents(year: 2026, month: 1, day: 2)))
        let records = [HealthKitSleepRecord(start: day.addingTimeInterval(10 * 3600),
            end: day.addingTimeInterval(14 * 3600), stage: HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue, source: "one")]
        let samples = HealthKitSleepSummary.samples(from: records, start: day,
            end: day.addingTimeInterval(36 * 3600), calendar: calendar).filter { $0.kind == .sleepDuration }
        #expect(samples.count == 2)
        #expect(samples.map(\.value) == [2, 2])
        #expect(calendar.isDate(samples[0].measuredAt, inSameDayAs: day))
        #expect(!calendar.isDate(samples[1].measuredAt, inSameDayAs: day))
    }
}
