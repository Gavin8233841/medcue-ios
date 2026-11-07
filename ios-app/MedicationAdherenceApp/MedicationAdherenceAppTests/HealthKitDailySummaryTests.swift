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


struct MedicationSleepReviewTests {
    @Test @MainActor
    func usesActualDoseTimeAndKeepsUnknownTimesAndMissingSleep() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let day = try #require(calendar.date(from: DateComponents(year: 2026, month: 1, day: 2)))
        let drug = StoredMedication(displayName: "合成测试药", kind: .overTheCounter, inputSource: .manual)
        let task = StoredDoseTask(medicationID: drug.id, dueAt: day.addingTimeInterval(-7200), doseValue: 1,
            doseUnit: "片", status: .taken, recordedAt: day.addingTimeInterval(13 * 3600))
        let unknown = StoredDoseTask(medicationID: drug.id, dueAt: day.addingTimeInterval(14 * 3600), doseValue: 1,
            doseUnit: "片", status: .taken)
        let skipped = StoredDoseTask(medicationID: drug.id, dueAt: day.addingTimeInterval(16 * 3600), doseValue: 1,
            doseUnit: "片", status: .skipped, recordedAt: day.addingTimeInterval(10 * 3600))
        let review = MedicationSleepReview(samples: [], tasks: [task, unknown, skipped], medications: [drug],
            dayCount: 2, now: day.addingTimeInterval(36 * 3600), calendar: calendar)
        #expect(review.days[0].medicationRecords.isEmpty)
        #expect(review.days[1].medicationRecords.count == 3)
        #expect(review.days[1].actualDoseCount == 1)
        #expect(review.context.contains("skipped/计划01-02 16:00"))
        #expect(review.context.contains("实际时间未知"))
        #expect(review.days.allSatisfy { $0.sleepHours == nil })
        #expect(review.sleepSummary.contains("0/2"))
    }

    @Test @MainActor
    func analysisInputChangesWithRealSleepValues() throws {
        let now = Date()
        let date = Calendar.current.startOfDay(for: now)
        func review(_ value: Double) -> MedicationSleepReview {
            MedicationSleepReview(samples: [.init(kind: .sleepDuration, measuredAt: date, value: value, unit: "小时")],
                tasks: [], medications: [], dayCount: 14, now: now)
        }
        #expect(review(5).context != review(8).context)
        #expect(review(5).sleepSummary != review(8).sleepSummary)
        #expect(review(5).days.count == 14)
    }

    @Test func sleepIntentSeparatesKnowledgeFromPersonalReview() {
        for question in ["睡眠是什么", "如何改善睡眠", "我想了解什么是深度睡眠"] {
            #expect(!MedicationSleepAnalysisIntent.matches(question))
        }
        #expect(MedicationSleepAnalysisIntent.matches("分析最近14天的睡眠与用药记录"))
        #expect(MedicationSleepAnalysisIntent.matches("我昨晚睡得怎么样"))
    }
}
