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
    #expect(dashboard.safetyNote.contains("不代表诊断"))
}

private func makeTrendFixtures(rates: [Double]) -> (planID: UUID, doses: [ScheduledDose], events: [DoseEvent]) {
    let planID = UUID()
    let calendar = Calendar(identifier: .gregorian)
    let start = calendar.date(from: DateComponents(year: 2026, month: 5, day: 1, hour: 8))!
    var doses: [ScheduledDose] = []
    var events: [DoseEvent] = []

    for (dayIndex, rate) in rates.enumerated() {
        let completedCount = Int((rate * 4).rounded())
        for doseIndex in 0..<4 {
            let dueAt = calendar.date(byAdding: .hour, value: doseIndex * 4, to: calendar.date(byAdding: .day, value: dayIndex, to: start)!)!
            let dose = ScheduledDose(
                planID: planID,
                dueAt: dueAt,
                dose: DoseAmount(value: Decimal(1), unit: "片")
            )
            doses.append(dose)
            if doseIndex < completedCount {
                events.append(DoseEvent(scheduledDoseID: dose.id, status: .taken, recordedAt: dueAt))
            } else {
                events.append(DoseEvent(scheduledDoseID: dose.id, status: .skipped, recordedAt: dueAt))
            }
        }
    }

    return (planID, doses, events)
}
