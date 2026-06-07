import Foundation
import Testing
@testable import MedicationAdherenceCore

@Test func adherenceTrendRequiresOneWeekOfRecordedDays() {
    let statuses = makeDayStatuses([1, 1, 1, 1, 1, 1])

    let trend = AdherenceTrendBuilder().build(dayStatuses: statuses)

    #expect(trend.state == .insufficientData)
    #expect(trend.daysAnalyzed == 6)
    #expect(trend.message.contains("至少记录 7 个有提醒的日期"))
    #expect(trend.points.count == 6)
}

@Test func adherenceTrendDetectsImprovingRecentCompletion() {
    let statuses = makeDayStatuses([
        0.4, 0.4, 0.6, 0.4, 0.6, 0.4, 0.6,
        0.8, 0.8, 1.0, 0.8, 1.0, 0.8, 1.0
    ])

    let trend = AdherenceTrendBuilder().build(dayStatuses: statuses)

    #expect(trend.state == .improving)
    #expect((trend.changeFromPrevious ?? 0) > 0.2)
    #expect(trend.message.contains("正在改善"))
}

@Test func adherenceTrendDetectsDecliningRecentCompletion() {
    let statuses = makeDayStatuses([
        1.0, 1.0, 0.8, 1.0, 0.8, 1.0, 0.8,
        0.6, 0.6, 0.4, 0.6, 0.4, 0.4, 0.4
    ])

    let trend = AdherenceTrendBuilder().build(dayStatuses: statuses)

    #expect(trend.state == .declining)
    #expect((trend.changeFromPrevious ?? 0) < -0.2)
    #expect(trend.message.contains("建议复盘"))
}

@Test func adherenceTrendKeepsStableWhenChangeIsSmall() {
    let statuses = makeDayStatuses([
        0.8, 0.8, 0.8, 0.8, 1.0, 0.8, 0.8,
        0.8, 0.8, 1.0, 0.8, 0.8, 0.8, 0.8
    ])

    let trend = AdherenceTrendBuilder().build(dayStatuses: statuses)

    #expect(trend.state == .stable)
    #expect(abs(trend.changeFromPrevious ?? 1) < 0.08)
    #expect(trend.consistencyScore > 0.7)
}

@Test func adherenceTrendIncludesDoseChangeContext() {
    let medicationID = UUID()
    let planID = UUID()
    let doseChange = MedicationDoseChange(
        medicationID: medicationID,
        planID: planID,
        previousDose: DoseAmount(value: Decimal(1), unit: "片"),
        newDose: DoseAmount(value: Decimal(2), unit: "片"),
        effectiveFrom: Date(timeIntervalSince1970: 1_781_078_400),
        note: "用户确认后修改剂量。"
    )
    let statuses = makeDayStatuses([
        0.8, 0.8, 0.8, 0.8, 1.0, 0.8, 0.8,
        0.8, 0.8, 1.0, 0.8, 0.8, 0.8, 0.8
    ])

    let trend = AdherenceTrendBuilder().build(
        dayStatuses: statuses,
        doseChanges: [doseChange]
    )

    #expect(trend.doseChangeCount == 1)
    #expect(trend.doseChangeSummary.contains("剂量变化"))
    #expect(trend.supportingSummary.contains("剂量变化"))
    #expect(trend.safetyNote.contains("不代表疗效"))
}

@Test func adherenceTrendInsufficientDataStillCarriesDoseChangeContext() {
    let doseChange = MedicationDoseChange(
        medicationID: UUID(),
        previousDose: nil,
        newDose: DoseAmount(value: Decimal(1), unit: "粒"),
        effectiveFrom: Date(timeIntervalSince1970: 1_781_078_400),
        note: "初始剂量记录。"
    )

    let trend = AdherenceTrendBuilder().build(
        dayStatuses: makeDayStatuses([1, 1, 1]),
        doseChanges: [doseChange]
    )

    #expect(trend.state == .insufficientData)
    #expect(trend.doseChangeCount == 1)
    #expect(trend.doseChangeSummary.contains("剂量变化"))
    #expect(trend.supportingSummary.contains("数据不足"))
}

private func makeDayStatuses(_ completionRates: [Double]) -> [AdherenceDayStatus] {
    completionRates.enumerated().map { index, rate in
        let scheduledCount = 5
        let takenCount = Int((rate * Double(scheduledCount)).rounded())
        let skippedCount = max(0, scheduledCount - takenCount)
        return AdherenceDayStatus(
            date: DateOnly(year: 2026, month: 6, day: index + 1),
            scheduledCount: scheduledCount,
            takenCount: takenCount,
            skippedCount: skippedCount,
            delayedCount: skippedCount > 0 ? 1 : 0
        )
    }
}
