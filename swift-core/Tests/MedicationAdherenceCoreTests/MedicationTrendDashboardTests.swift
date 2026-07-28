import Foundation
import Testing
@testable import MedicationAdherenceCore

@Test func medicationTrendDashboardRequiresOneWeekBeforeJudgement() {
    let fixtures = makeTrendFixtures(rates: [1, 1, 1, 1, 1, 1])

    let dashboard = MedicationTrendDashboardBuilder().build(
        scheduledDoses: fixtures.doses,
        events: fixtures.events,
        timeZone: .gmt
    )

    #expect(dashboard.direction == .needsData)
    #expect(dashboard.metrics.first { $0.topic == .discipline }?.direction == .needsData)
    #expect(dashboard.summary.contains("至少记录 7 个有提醒日期"))
}

@Test func medicationTrendDashboardDetectsDecliningDiscipline() throws {
    let fixtures = makeTrendFixtures(rates: [
        1, 1, 1, 1, 1, 1, 1,
        0.25, 0.25, 0.25, 0.5, 0.25, 0.5, 0.25
    ])

    let dashboard = MedicationTrendDashboardBuilder().build(
        scheduledDoses: fixtures.doses,
        events: fixtures.events,
        timeZone: .gmt
    )
    let discipline = try #require(dashboard.metrics.first { $0.topic == .discipline })

    #expect(discipline.direction == .declining)
    #expect(dashboard.direction == .declining)
    #expect(discipline.summary.contains("最近 7 天"))
    #expect(discipline.comparison.recentDayCount == 7)
    #expect(discipline.comparison.previousDayCount == 7)
    #expect(discipline.comparison.delta ?? 0 < -0.4)
    #expect(discipline.comparison.confidenceScore > 0.85)
    #expect(discipline.contributorSummary.contains { $0.contains("忽略记录") })
    #expect(discipline.formulaComponents.count == 3)
    #expect(discipline.formulaComponents.reduce(0) { $0 + $1.weight } > 0.99)
    #expect(discipline.formulaComponents.contains { $0.title == "完成覆盖" && $0.source.contains("已服用") })
    #expect(discipline.points.allSatisfy { $0.formulaComponents.count == 3 })
    #expect(discipline.points.contains { point in
        point.formulaComponents.contains { $0.title == "忽略影响" && $0.score < 1 }
    })
    #expect(discipline.formulaSummary.contains("纪律分"))
    #expect(discipline.formulaSummary.contains("62%"))
    #expect(dashboard.dataQualitySummary.contains("记录较完整"))
}

@Test func medicationTrendDashboardTreatsHighScoreSmallDeclineAsFluctuation() throws {
    let fixtures = makeTrendFixtures(
        dailyOutcomes: Array(repeating: (taken: 12, delayed: 0, skipped: 0), count: 7)
            + Array(repeating: (taken: 10, delayed: 2, skipped: 0), count: 7)
    )

    let dashboard = MedicationTrendDashboardBuilder().build(
        scheduledDoses: fixtures.doses,
        events: fixtures.events,
        timeZone: .gmt
    )
    let discipline = try #require(dashboard.metrics.first { $0.topic == .discipline })

    #expect(discipline.score >= 0.85)
    #expect(discipline.comparison.delta ?? 0 < -0.08)
    #expect(discipline.comparison.delta ?? -1 > -0.18)
    #expect(discipline.direction == .fluctuating)
    #expect(dashboard.direction == .fluctuating)
    #expect(dashboard.title.contains("近期波动"))
}

@Test func medicationTrendDashboardKeepsHighOverallWithSingleRecentTimingDropAsFluctuation() throws {
    let fixtures = makeTrendFixtures(
        dailyOutcomes: Array(repeating: (taken: 4, delayed: 0, skipped: 0), count: 14),
        recentTimingOffsetMinutes: 75
    )

    let dashboard = MedicationTrendDashboardBuilder().build(
        scheduledDoses: fixtures.doses,
        events: fixtures.events,
        timeZone: .gmt
    )
    let timing = try #require(dashboard.metrics.first { $0.topic == .timing })

    #expect(timing.direction == .declining)
    #expect(timing.comparison.recentScore < 0.85)
    #expect(dashboard.overallScore >= 0.85)
    #expect(dashboard.direction == .fluctuating)
    #expect(dashboard.title.contains("近期波动"))
}

@Test func medicationTrendDashboardCarriesDoseArchiveAndHealthSignals() throws {
    let medicationID = UUID()
    let fixtures = makeTrendFixtures(rates: [
        1, 1, 1, 1, 1, 1, 1,
        0.75, 0.75, 1, 1, 0.75, 1, 1
    ])
    let changeDate = fixtures.doses[8].dueAt
    let doseChange = MedicationDoseChange(
        medicationID: medicationID,
        planID: fixtures.planID,
        previousDose: DoseAmount(value: Decimal(1), unit: "片"),
        newDose: DoseAmount(value: Decimal(2), unit: "片"),
        effectiveFrom: changeDate,
        note: "用户确认后记录。"
    )
    let archived = MedicationLifecycleEvent(
        medicationID: medicationID,
        state: .archived,
        occurredAt: fixtures.doses[10].dueAt,
        note: "用户归档。"
    )
    let health = HealthSignalSample(
        kind: .heartRate,
        measuredAt: fixtures.doses[11].dueAt,
        value: 78,
        unit: "count/min"
    )

    let dashboard = MedicationTrendDashboardBuilder().build(
        scheduledDoses: fixtures.doses,
        events: fixtures.events,
        doseChanges: [doseChange],
        lifecycleEvents: [archived],
        healthSignals: [health],
        timeZone: .gmt
    )

    let doseMetric = try #require(dashboard.metrics.first { $0.topic == .doseChange })
    let loadMetric = try #require(dashboard.metrics.first { $0.topic == .regimenLoad })
    let healthMetric = try #require(dashboard.metrics.first { $0.topic == .healthSignal })

    #expect(doseMetric.summary.contains("剂量变化"))
    #expect(doseMetric.points.contains { $0.doseChangeCount == 1 })
    #expect(loadMetric.points.contains { $0.archivedMedicationCount > 0 })
    #expect(healthMetric.summary.contains("授权健康数据"))
    #expect(healthMetric.points.contains { $0.healthSignalCount == 1 })
    #expect(healthMetric.points.contains { point in
        point.formulaComponents.contains { $0.title == "样本覆盖" }
    })
    #expect(dashboard.safetyNote.contains("不代表诊断"))
}

@Test func medicationTrendDashboardUsesMedicationTypeSourceAndLifecycleContext() throws {
    let medicationID = UUID()
    let fixtures = makeTrendFixtures(rates: [
        1, 1, 1, 1, 1, 1, 1,
        1, 1, 1, 1, 1, 1, 1
    ])
    let context = MedicationTrendPlanContext(
        planID: fixtures.planID,
        medicationID: medicationID,
        medicationKind: .prescription,
        inputSource: .prescriptionImage,
        lifecycleState: .interrupted
    )

    let dashboard = MedicationTrendDashboardBuilder().build(
        scheduledDoses: fixtures.doses,
        events: fixtures.events,
        planContexts: [context],
        timeZone: .gmt
    )

    let loadMetric = try #require(dashboard.metrics.first { $0.topic == .regimenLoad })
    let point = try #require(loadMetric.points.first { $0.prescriptionMedicationCount > 0 })

    #expect(point.interruptedMedicationCount == 1)
    #expect(point.prescriptionMedicationCount == 1)
    #expect(point.importedMedicationCount == 1)
    #expect(point.annotation.contains("中断"))
    #expect(loadMetric.dataSourceSummary.contains("药物类型"))
    #expect(loadMetric.formulaSummary.contains("用药负担分"))
    #expect(loadMetric.formulaSummary.contains("状态变化"))
    #expect(loadMetric.formulaComponents.contains { $0.title == "提醒负担" })
    #expect(loadMetric.formulaComponents.contains { $0.source.contains("归档") || $0.source.contains("中断") })
}

@Test func medicationTrendDashboardDoesNotBackfillCurrentLifecycleStateIntoHistory() throws {
    let medicationID = UUID()
    let fixtures = makeTrendFixtures(rates: [
        1, 1, 1, 1, 1, 1, 1,
        1, 1, 1, 1, 1, 1, 1
    ])
    let context = MedicationTrendPlanContext(
        planID: fixtures.planID,
        medicationID: medicationID,
        medicationKind: .prescription,
        inputSource: .manual,
        lifecycleState: .interrupted
    )
    let interruptedAt = fixtures.doses[9].dueAt
    let lifecycleEvent = MedicationLifecycleEvent(
        medicationID: medicationID,
        state: .interrupted,
        occurredAt: interruptedAt,
        note: "用户确认服用中断"
    )

    let dashboard = MedicationTrendDashboardBuilder().build(
        scheduledDoses: fixtures.doses,
        events: fixtures.events,
        planContexts: [context],
        lifecycleEvents: [lifecycleEvent],
        timeZone: .gmt
    )

    let loadMetric = try #require(dashboard.metrics.first { $0.topic == .regimenLoad })
    let eventComponents = Calendar(identifier: .gregorian).dateComponents([.year, .month, .day], from: interruptedAt)
    let eventDate = DateOnly(
        year: try #require(eventComponents.year),
        month: try #require(eventComponents.month),
        day: try #require(eventComponents.day)
    )
    let beforeEvent = loadMetric.points.filter { $0.date < eventDate }
    let afterEvent = loadMetric.points.filter { $0.date >= eventDate }

    #expect(!beforeEvent.isEmpty)
    #expect(!afterEvent.isEmpty)
    #expect(beforeEvent.allSatisfy { $0.interruptedMedicationCount == 0 })
    #expect(afterEvent.allSatisfy { $0.interruptedMedicationCount >= 1 })
    #expect(beforeEvent.allSatisfy { $0.activeMedicationCount == 1 })
}

@Test func medicationTrendDashboardUsesLifecycleEventTimingForRegimenLoadPoint() throws {
    let medicationID = UUID()
    let fixtures = makeTrendFixtures(rates: [
        1, 1, 1, 1, 1, 1, 1,
        1, 1, 1, 1, 1, 1, 1
    ])
    let interruptedAt = fixtures.doses[9].dueAt
    let lifecycleEvent = MedicationLifecycleEvent(
        medicationID: medicationID,
        state: .interrupted,
        occurredAt: interruptedAt,
        note: "用户确认服用中断"
    )

    let dashboard = MedicationTrendDashboardBuilder().build(
        scheduledDoses: fixtures.doses,
        events: fixtures.events,
        lifecycleEvents: [lifecycleEvent],
        timeZone: .gmt
    )

    let loadMetric = try #require(dashboard.metrics.first { $0.topic == .regimenLoad })
    let affectedPoint = try #require(loadMetric.points.first { $0.interruptedMedicationCount == 1 })

    #expect(affectedPoint.annotation.contains("中断"))
    #expect(affectedPoint.formulaComponents.contains { $0.title == "状态变化" && $0.score < 1 })
    #expect(loadMetric.dataSourceSummary.contains("归档"))
    #expect(loadMetric.formulaSummary.contains("状态变化"))
}

@Test func medicationTrendDashboardMarksHealthSignalAsNeedsDataWithoutSamples() throws {
    let fixtures = makeTrendFixtures(rates: [
        1, 1, 1, 1, 1, 1, 1,
        1, 1, 1, 1, 1, 1, 1
    ])

    let dashboard = MedicationTrendDashboardBuilder().build(
        scheduledDoses: fixtures.doses,
        events: fixtures.events,
        healthSignals: [],
        timeZone: .gmt
    )

    let healthMetric = try #require(dashboard.metrics.first { $0.topic == .healthSignal })

    #expect(healthMetric.direction == .needsData)
    #expect(healthMetric.summary.contains("等待用户授权"))
    #expect(healthMetric.points.allSatisfy { $0.healthSignalCount == 0 })
    #expect(healthMetric.formulaComponents.contains { $0.title == "样本覆盖" && $0.score == 0 })
}

@Test func medicationTrendDashboardIgnoresFutureDosesWithoutEvents() throws {
    let fixtures = makeTrendFixtures(rates: [1, 1, 1])
    let calendar = Calendar(identifier: .gregorian)
    let futureDoses = (0..<12).map { offset in
        ScheduledDose(
            planID: fixtures.planID,
            dueAt: calendar.date(from: DateComponents(year: 2026, month: 6, day: 1 + offset, hour: 8))!,
            dose: DoseAmount(value: Decimal(1), unit: "片")
        )
    }

    let dashboard = MedicationTrendDashboardBuilder().build(
        scheduledDoses: fixtures.doses + futureDoses,
        events: fixtures.events,
        timeZone: .gmt,
        now: calendar.date(from: DateComponents(year: 2026, month: 5, day: 4, hour: 12))!
    )

    let discipline = try #require(dashboard.metrics.first { $0.topic == .discipline })
    #expect(discipline.points.count == 3)
    #expect(discipline.direction == .needsData)
    #expect(discipline.points.allSatisfy { $0.scheduledCount == 4 })
}

@Test func medicationTrendDashboardIgnoresFutureContextUntilItHappens() throws {
    let medicationID = UUID()
    let fixtures = makeTrendFixtures(rates: [1, 1, 1, 1, 1, 1, 1])
    let calendar = Calendar(identifier: .gregorian)
    let now = calendar.date(from: DateComponents(year: 2026, month: 5, day: 8, hour: 12))!
    let futureDate = calendar.date(from: DateComponents(year: 2026, month: 6, day: 1, hour: 8))!
    let futureDoseChange = MedicationDoseChange(
        medicationID: medicationID,
        planID: fixtures.planID,
        previousDose: DoseAmount(value: Decimal(1), unit: "片"),
        newDose: DoseAmount(value: Decimal(2), unit: "片"),
        effectiveFrom: futureDate,
        note: "未来复诊后再生效。"
    )
    let futureLifecycleEvent = MedicationLifecycleEvent(
        medicationID: medicationID,
        state: .archived,
        occurredAt: futureDate,
        note: "未来归档。"
    )
    let futureHealthSignal = HealthSignalSample(
        kind: .heartRate,
        measuredAt: futureDate,
        value: 80,
        unit: "次/分"
    )

    let dashboard = MedicationTrendDashboardBuilder().build(
        scheduledDoses: fixtures.doses,
        events: fixtures.events,
        doseChanges: [futureDoseChange],
        lifecycleEvents: [futureLifecycleEvent],
        healthSignals: [futureHealthSignal],
        timeZone: .gmt,
        now: now
    )

    let doseMetric = try #require(dashboard.metrics.first { $0.topic == .doseChange })
    let loadMetric = try #require(dashboard.metrics.first { $0.topic == .regimenLoad })
    let healthMetric = try #require(dashboard.metrics.first { $0.topic == .healthSignal })

    #expect(doseMetric.summary.contains("没有剂量变化"))
    #expect(doseMetric.points.allSatisfy { $0.doseChangeCount == 0 })
    #expect(loadMetric.points.allSatisfy { $0.archivedMedicationCount == 0 })
    #expect(healthMetric.summary.contains("等待用户授权"))
    #expect(healthMetric.points.allSatisfy { $0.healthSignalCount == 0 })
}

@Test func medicationTrendDashboardIncludesFutureDoseWhenUserAlreadyRecordedIt() throws {
    let fixtures = makeTrendFixtures(rates: [1, 1, 1])
    let calendar = Calendar(identifier: .gregorian)
    let now = calendar.date(from: DateComponents(year: 2026, month: 5, day: 4, hour: 12))!
    let futureDueAt = calendar.date(from: DateComponents(year: 2026, month: 6, day: 1, hour: 8))!
    let futureDose = ScheduledDose(
        planID: fixtures.planID,
        dueAt: futureDueAt,
        dose: DoseAmount(value: Decimal(1), unit: "片")
    )
    let earlyRecord = DoseEvent(
        scheduledDoseID: futureDose.id,
        status: .taken,
        recordedAt: now,
        reason: "用户确认提前服用。"
    )

    let dashboard = MedicationTrendDashboardBuilder().build(
        scheduledDoses: fixtures.doses + [futureDose],
        events: fixtures.events + [earlyRecord],
        timeZone: .gmt,
        now: now
    )

    let discipline = try #require(dashboard.metrics.first { $0.topic == .discipline })
    let todayComponents = Calendar(identifier: .gregorian).dateComponents([.year, .month, .day], from: now)
    let today = DateOnly(
        year: try #require(todayComponents.year),
        month: try #require(todayComponents.month),
        day: try #require(todayComponents.day)
    )
    let todayPoint = try #require(discipline.points.first { $0.date == today })

    #expect(todayPoint.scheduledCount == 1)
    #expect(todayPoint.completedCount == 1)
    #expect(discipline.points.count == 4)
}

@Test func medicationTrendDashboardScoresHealthSignalStability() throws {
    let fixtures = makeTrendFixtures(rates: [
        1, 1, 1, 1, 1, 1, 1,
        1, 1, 1, 1, 1, 1, 1
    ])
    let stableSignals = fixtures.doses.enumerated().map { index, dose in
        HealthSignalSample(
            kind: .heartRate,
            measuredAt: dose.dueAt,
            value: index.isMultiple(of: 2) ? 72 : 74,
            unit: "次/分"
        )
    }
    let volatileSignals = fixtures.doses.enumerated().map { index, dose in
        HealthSignalSample(
            kind: .heartRate,
            measuredAt: dose.dueAt,
            value: index.isMultiple(of: 2) ? 60 : 125,
            unit: "次/分"
        )
    }

    let stableDashboard = MedicationTrendDashboardBuilder().build(
        scheduledDoses: fixtures.doses,
        events: fixtures.events,
        healthSignals: stableSignals,
        timeZone: .gmt
    )
    let volatileDashboard = MedicationTrendDashboardBuilder().build(
        scheduledDoses: fixtures.doses,
        events: fixtures.events,
        healthSignals: volatileSignals,
        timeZone: .gmt
    )
    let stableHealth = try #require(stableDashboard.metrics.first { $0.topic == .healthSignal })
    let volatileHealth = try #require(volatileDashboard.metrics.first { $0.topic == .healthSignal })

    #expect(stableHealth.score > volatileHealth.score)
    #expect(stableHealth.summary.contains("授权健康数据"))
    #expect(stableHealth.summary.contains("趋势和复诊资料"))
    #expect(!stableHealth.summary.contains("风险提示"))
    #expect(stableHealth.points.contains { $0.healthSignalCount > 0 })
    #expect(stableHealth.comparison.confidenceScore > volatileHealth.comparison.confidenceScore - 0.001)
    #expect(stableHealth.contributorSummary.contains { $0.contains("授权健康数据") })
    #expect(stableHealth.formulaSummary.contains("健康信号分"))
    #expect(stableHealth.formulaSummary.contains("不生成诊断"))
    #expect(stableHealth.formulaComponents.contains { $0.source.contains("Apple 健康") })
    #expect(stableHealth.formulaComponents.allSatisfy { !$0.explanation.contains("诊断") || $0.explanation.contains("不生成诊断") })
}

@Test func medicationTrendDashboardProvidesTransparentFormulaSummaryForEveryTopic() throws {
    let fixtures = makeTrendFixtures(rates: [
        1, 1, 1, 1, 1, 1, 1,
        0.75, 0.75, 1, 1, 0.75, 1, 1
    ])

    let dashboard = MedicationTrendDashboardBuilder().build(
        scheduledDoses: fixtures.doses,
        events: fixtures.events,
        timeZone: .gmt
    )

    #expect(dashboard.metrics.count == MedicationTrendTopic.allCases.count)
    for topic in MedicationTrendTopic.allCases {
        let metric = try #require(dashboard.metrics.first { $0.topic == topic })
        #expect(!metric.formulaSummary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        #expect(metric.formulaSummary.contains("="))
        #expect(!metric.formulaSummary.contains("处方建议"))
        #expect(!metric.formulaSummary.contains("诊断结果"))
        #expect(metric.points.allSatisfy { !$0.formulaComponents.isEmpty })
    }
}

@Test func medicationTrendDashboardKeepsLowConfidenceWhenPreviousPeriodIsThin() throws {
    let fixtures = makeTrendFixtures(rates: [
        1, 1, 1,
        0.75, 0.75, 1, 1, 0.75, 1, 1
    ])

    let dashboard = MedicationTrendDashboardBuilder().build(
        scheduledDoses: fixtures.doses,
        events: fixtures.events,
        timeZone: .gmt
    )
    let discipline = try #require(dashboard.metrics.first { $0.topic == .discipline })

    #expect(discipline.direction == .stable)
    #expect(discipline.comparison.recentDayCount == 7)
    #expect(discipline.comparison.previousDayCount == 3)
    #expect(discipline.comparison.confidenceScore < 0.9)
    #expect(discipline.comparison.evidenceSummary.contains("前 7 天覆盖 3"))
    #expect(dashboard.dataQualitySummary.contains("前一周期不足"))
}

@Test func medicationTrendDashboardUsesRecentSlopeWhenPreviousPeriodIsMissing() throws {
    let fixtures = makeTrendFixtures(rates: [
        1, 1, 0.75, 0.75, 0.5, 0.5, 0.25
    ])

    let dashboard = MedicationTrendDashboardBuilder().build(
        scheduledDoses: fixtures.doses,
        events: fixtures.events,
        timeZone: .gmt
    )
    let discipline = try #require(dashboard.metrics.first { $0.topic == .discipline })

    #expect(discipline.comparison.previousScore == nil)
    #expect(discipline.comparison.trendSlopePerDay < 0)
    #expect(discipline.comparison.trendStrengthScore >= 0.08)
    #expect(discipline.direction == .declining)
    #expect(discipline.comparison.evidenceSummary.contains("前 7 天覆盖 0"))
}

private func makeTrendFixtures(rates: [Double]) -> (planID: UUID, doses: [ScheduledDose], events: [DoseEvent]) {
    makeTrendFixtures(
        dailyOutcomes: rates.map { rate in
            let completedCount = Int((rate * 4).rounded())
            return (taken: completedCount, delayed: 0, skipped: 4 - completedCount)
        }
    )
}

private func makeTrendFixtures(dailyOutcomes: [(taken: Int, delayed: Int, skipped: Int)]) -> (planID: UUID, doses: [ScheduledDose], events: [DoseEvent]) {
    makeTrendFixtures(dailyOutcomes: dailyOutcomes, recentTimingOffsetMinutes: 0)
}

private func makeTrendFixtures(
    dailyOutcomes: [(taken: Int, delayed: Int, skipped: Int)],
    recentTimingOffsetMinutes: Int
) -> (planID: UUID, doses: [ScheduledDose], events: [DoseEvent]) {
    let planID = UUID()
    let calendar = Calendar(identifier: .gregorian)
    let start = calendar.date(from: DateComponents(year: 2026, month: 5, day: 1, hour: 8))!
    var doses: [ScheduledDose] = []
    var events: [DoseEvent] = []

    for (dayIndex, outcome) in dailyOutcomes.enumerated() {
        let scheduledCount = outcome.taken + outcome.delayed + outcome.skipped
        for doseIndex in 0..<scheduledCount {
            let dueAt = calendar.date(byAdding: .minute, value: doseIndex * 60, to: calendar.date(byAdding: .day, value: dayIndex, to: start)!)!
            let dose = ScheduledDose(
                planID: planID,
                dueAt: dueAt,
                dose: DoseAmount(value: Decimal(1), unit: "片")
            )
            doses.append(dose)
            if doseIndex < outcome.taken {
                let recordedAt = dayIndex >= max(0, dailyOutcomes.count - 7)
                    ? calendar.date(byAdding: .minute, value: recentTimingOffsetMinutes, to: dueAt)!
                    : dueAt
                events.append(DoseEvent(scheduledDoseID: dose.id, status: .taken, recordedAt: recordedAt))
            } else if doseIndex < outcome.taken + outcome.delayed {
                events.append(DoseEvent(scheduledDoseID: dose.id, status: .delayed, recordedAt: dueAt))
            } else {
                events.append(DoseEvent(scheduledDoseID: dose.id, status: .skipped, recordedAt: dueAt))
            }
        }
    }

    return (planID, doses, events)
}
