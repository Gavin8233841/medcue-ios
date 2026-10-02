import Foundation
import Testing
@testable import MedicationAdherenceCore

@Test func medicationStockProjectionCountsTakenAndCorrectedDoses() {
    let medicationID = UUID()
    let stock = MedicationStock(
        medicationID: medicationID,
        remainingQuantity: 10,
        unit: "tablet",
        lowStockThreshold: 3
    )
    let scheduled = [
        ScheduledDose(planID: UUID(), dueAt: Date(), dose: DoseAmount(value: 1, unit: "tablet")),
        ScheduledDose(planID: UUID(), dueAt: Date(), dose: DoseAmount(value: 1, unit: "tablet")),
        ScheduledDose(planID: UUID(), dueAt: Date(), dose: DoseAmount(value: 1, unit: "tablet"))
    ]
    let events = [
        DoseEvent(scheduledDoseID: scheduled[0].id, status: .taken, recordedAt: Date()),
        DoseEvent(scheduledDoseID: scheduled[1].id, status: .corrected, recordedAt: Date()),
        DoseEvent(scheduledDoseID: scheduled[2].id, status: .skipped, recordedAt: Date())
    ]

    let projection = MedicationStockEstimator().project(
        stock: stock,
        scheduledDoses: scheduled,
        events: events
    )

    #expect(projection.consumedQuantity == 2)
    #expect(projection.projectedRemainingQuantity == 8)
    #expect(projection.isLowStock == false)
    #expect(projection.issues.isEmpty)
}

@Test func medicationStockProjectionUsesPhysicalCountAsCheckpointWithoutResettingConsumptionHistory() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let checkpoint = makeStockDate(calendar: calendar, day: 2, hour: 0)
    let stock = MedicationStock(
        medicationID: UUID(),
        remainingQuantity: 9,
        unit: "片",
        lowStockThreshold: 3,
        lastUpdated: checkpoint
    )
    let scheduled = [
        ScheduledDose(
            planID: UUID(),
            dueAt: makeStockDate(calendar: calendar, day: 1, hour: 8),
            dose: DoseAmount(value: 1, unit: "片")
        ),
        ScheduledDose(
            planID: UUID(),
            dueAt: makeStockDate(calendar: calendar, day: 2, hour: 8),
            dose: DoseAmount(value: 1, unit: "片")
        )
    ]
    let events = [
        DoseEvent(
            scheduledDoseID: scheduled[0].id,
            status: .taken,
            recordedAt: checkpoint.addingTimeInterval(-60)
        ),
        DoseEvent(
            scheduledDoseID: scheduled[1].id,
            status: .taken,
            recordedAt: checkpoint.addingTimeInterval(60)
        )
    ]

    let projection = MedicationStockEstimator().project(
        stock: stock,
        scheduledDoses: scheduled,
        events: events,
        calendar: calendar,
        timeZone: calendar.timeZone
    )

    #expect(projection.consumedQuantity == 1)
    #expect(projection.projectedRemainingQuantity == 8)
    #expect(projection.averageDailyConsumption == 1)
    #expect(projection.trackedDayCount == 2)
    #expect(projection.estimatedDaysRemaining == 8)
}

@Test func medicationStockProjectionDoesNotDeductEventRecordedAtCheckpoint() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let checkpoint = makeStockDate(calendar: calendar, day: 2, hour: 8)
    let scheduled = ScheduledDose(
        planID: UUID(),
        dueAt: checkpoint,
        dose: DoseAmount(value: 1, unit: "片")
    )
    let stock = MedicationStock(
        medicationID: UUID(),
        remainingQuantity: 9,
        unit: "片",
        lowStockThreshold: 3,
        lastUpdated: checkpoint
    )

    let projection = MedicationStockEstimator().project(
        stock: stock,
        scheduledDoses: [scheduled],
        events: [DoseEvent(
            scheduledDoseID: scheduled.id,
            status: .taken,
            recordedAt: checkpoint
        )],
        calendar: calendar,
        timeZone: calendar.timeZone
    )

    #expect(projection.consumedQuantity == 0)
    #expect(projection.projectedRemainingQuantity == 9)
    #expect(projection.averageDailyConsumption == 1)
    #expect(projection.trackedDayCount == 1)
    #expect(projection.estimatedDaysRemaining == 9)
}

@Test func medicationStockProjectionDoesNotDeductDoseWhoseLatestEventIsSkipped() {
    let checkpoint = Date(timeIntervalSince1970: 1_750_000_000)
    let scheduled = ScheduledDose(
        planID: UUID(),
        dueAt: checkpoint.addingTimeInterval(60),
        dose: DoseAmount(value: 1, unit: "tablet")
    )
    let stock = MedicationStock(
        medicationID: UUID(),
        remainingQuantity: 9,
        unit: "tablet",
        lowStockThreshold: 3,
        lastUpdated: checkpoint
    )
    let events = [
        DoseEvent(
            scheduledDoseID: scheduled.id,
            status: .taken,
            recordedAt: checkpoint.addingTimeInterval(60)
        ),
        DoseEvent(
            scheduledDoseID: scheduled.id,
            status: .skipped,
            recordedAt: checkpoint.addingTimeInterval(120)
        )
    ]

    let projection = MedicationStockEstimator().project(
        stock: stock,
        scheduledDoses: [scheduled],
        events: events
    )

    #expect(projection.consumedQuantity == 0)
    #expect(projection.projectedRemainingQuantity == 9)
}

@Test func medicationStockProjectionDeductsLatestCorrectedDoseOnlyOnce() {
    let checkpoint = Date(timeIntervalSince1970: 1_750_000_000)
    let scheduled = ScheduledDose(
        planID: UUID(),
        dueAt: checkpoint.addingTimeInterval(60),
        dose: DoseAmount(value: 2, unit: "tablet")
    )
    let stock = MedicationStock(
        medicationID: UUID(),
        remainingQuantity: 10,
        unit: "tablet",
        lowStockThreshold: 3,
        lastUpdated: checkpoint
    )
    let events = [
        DoseEvent(
            scheduledDoseID: scheduled.id,
            status: .taken,
            recordedAt: checkpoint.addingTimeInterval(60)
        ),
        DoseEvent(
            scheduledDoseID: scheduled.id,
            status: .corrected,
            recordedAt: checkpoint.addingTimeInterval(120)
        )
    ]

    let projection = MedicationStockEstimator().project(
        stock: stock,
        scheduledDoses: [scheduled],
        events: events
    )

    #expect(projection.consumedQuantity == 2)
    #expect(projection.projectedRemainingQuantity == 8)
    #expect(projection.averageDailyConsumption == 2)
    #expect(projection.trackedDayCount == 1)
}

@Test func medicationStockProjectionFlagsLowStock() {
    let medicationID = UUID()
    let stock = MedicationStock(
        medicationID: medicationID,
        remainingQuantity: 3,
        unit: "tablet",
        lowStockThreshold: 2
    )
    let scheduled = [
        ScheduledDose(planID: UUID(), dueAt: Date(), dose: DoseAmount(value: 1, unit: "tablet"))
    ]
    let events = [
        DoseEvent(scheduledDoseID: scheduled[0].id, status: .taken, recordedAt: Date())
    ]

    let projection = MedicationStockEstimator().project(
        stock: stock,
        scheduledDoses: scheduled,
        events: events
    )

    #expect(projection.projectedRemainingQuantity == 2)
    #expect(projection.isLowStock)
    #expect(projection.needsRefillReminder)
    #expect(projection.message.contains("低库存"))
}

@Test func medicationStockProjectionReportsUnitMismatch() {
    let stock = MedicationStock(
        medicationID: UUID(),
        remainingQuantity: 5,
        unit: "tablet",
        lowStockThreshold: 1
    )
    let scheduled = [
        ScheduledDose(planID: UUID(), dueAt: Date(), dose: DoseAmount(value: 1, unit: "drop"))
    ]
    let events = [
        DoseEvent(scheduledDoseID: scheduled[0].id, status: .taken, recordedAt: Date())
    ]

    let projection = MedicationStockEstimator().project(
        stock: stock,
        scheduledDoses: scheduled,
        events: events
    )

    #expect(projection.consumedQuantity == 0)
    #expect(projection.projectedRemainingQuantity == 5)
    #expect(projection.issues.contains { $0.kind == .doseUnitMismatch })
}

@Test func medicationStockProjectionEstimatesDaysRemainingFromRecordedConsumptionDays() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let stock = MedicationStock(
        medicationID: UUID(),
        remainingQuantity: 20,
        unit: "片",
        lowStockThreshold: 3,
        lastUpdated: makeStockDate(calendar: calendar, day: 1, hour: 0)
    )
    let scheduled = [
        ScheduledDose(planID: UUID(), dueAt: makeStockDate(calendar: calendar, day: 1, hour: 8), dose: DoseAmount(value: 1, unit: "片")),
        ScheduledDose(planID: UUID(), dueAt: makeStockDate(calendar: calendar, day: 1, hour: 20), dose: DoseAmount(value: 1, unit: "片")),
        ScheduledDose(planID: UUID(), dueAt: makeStockDate(calendar: calendar, day: 2, hour: 8), dose: DoseAmount(value: 1, unit: "片")),
        ScheduledDose(planID: UUID(), dueAt: makeStockDate(calendar: calendar, day: 2, hour: 20), dose: DoseAmount(value: 1, unit: "片"))
    ]
    let events = scheduled.map {
        DoseEvent(scheduledDoseID: $0.id, status: .taken, recordedAt: $0.dueAt)
    }

    let projection = MedicationStockEstimator().project(
        stock: stock,
        scheduledDoses: scheduled,
        events: events,
        calendar: calendar,
        timeZone: calendar.timeZone
    )

    #expect(projection.consumedQuantity == 4)
    #expect(projection.averageDailyConsumption == 2)
    #expect(projection.estimatedDaysRemaining == 8)
    #expect(projection.trackedDayCount == 2)
    #expect(projection.message.contains("约可用 8 天"))
}

@Test func medicationStockProjectionReportsInsufficientConsumptionDataForDaysRemaining() {
    let scheduled = [
        ScheduledDose(planID: UUID(), dueAt: Date(), dose: DoseAmount(value: 1, unit: "片"))
    ]
    let stock = MedicationStock(
        medicationID: UUID(),
        remainingQuantity: 20,
        unit: "片",
        lowStockThreshold: 3
    )

    let projection = MedicationStockEstimator().project(
        stock: stock,
        scheduledDoses: scheduled,
        events: []
    )

    #expect(projection.averageDailyConsumption == nil)
    #expect(projection.estimatedDaysRemaining == nil)
    #expect(projection.issues.contains { $0.kind == .insufficientConsumptionData })
}

@Test func medicationStockProjectionAcceptsEstablishedDoseUnitAliases() {
    let aliases = [
        ("片", "tablet"),
        ("tablet", "tablets"),
        ("粒", "capsules"),
        ("毫升", "mL"),
        ("滴", "drops"),
        ("袋", "包"),
        ("喷", "spray")
    ]
    for (first, second) in aliases {
        for (stockUnit, doseUnit) in [(first, second), (second, first)] {
            let projection = makeStockUnitProjection(stockUnit: stockUnit, doseUnit: doseUnit)

            #expect(projection.consumedQuantity == 2)
            #expect(projection.projectedRemainingQuantity == 1)
            #expect(projection.isLowStock)
            #expect(projection.needsRefillReminder)
            #expect(projection.averageDailyConsumption == 2)
            #expect(projection.estimatedDaysRemaining == 1)
            #expect(projection.trackedDayCount == 1)
            #expect(projection.issues.isEmpty)
            #expect(projection.unit == stockUnit)
        }
    }
}

@Test func medicationStockProjectionPreservesRawUnitMatchingAndOutput() {
    for (stockUnit, doseUnit) in [
        ("片", "片"),
        ("tablet", "tablet"),
        (" tablet ", "TABLET"),
        ("微量勺", " 微量勺 "),
        ("custom scoop", "CUSTOM SCOOP")
    ] {
        let projection = makeStockUnitProjection(stockUnit: stockUnit, doseUnit: doseUnit)

        #expect(projection.consumedQuantity == 2)
        #expect(projection.projectedRemainingQuantity == 1)
        #expect(projection.needsRefillReminder)
        #expect(projection.issues.isEmpty)
        #expect(projection.unit == stockUnit)
    }
}

@Test func medicationStockProjectionDoesNotConvertIncompatibleOrUnknownUnits() {
    for (stockUnit, doseUnit) in [
        ("片", "capsules"),
        ("毫升", "drops"),
        ("mg", "片"),
        ("mg", "mL"),
        ("微量勺", "包"),
        ("微量勺", "未知勺")
    ] {
        let projection = makeStockUnitProjection(stockUnit: stockUnit, doseUnit: doseUnit)

        #expect(projection.consumedQuantity == 0)
        #expect(projection.projectedRemainingQuantity == 3)
        #expect(!projection.needsRefillReminder)
        #expect(projection.averageDailyConsumption == nil)
        #expect(projection.issues.contains { $0.kind == .doseUnitMismatch })
    }
}

@Test func medicationStockProjectionAliasesRespectCheckpointsAndEventStatuses() {
    let cases: [(DoseEventStatus, TimeInterval, Decimal, Decimal?)] = [
        (.taken, -1, 0, 2),
        (.taken, 0, 0, 2),
        (.taken, 1, 2, 2),
        (.corrected, 1, 2, 2),
        (.skipped, 1, 0, nil),
        (.delayed, 1, 0, nil)
    ]
    for (status, offset, expectedConsumption, expectedAverage) in cases {
        let projection = makeStockUnitProjection(
            stockUnit: "片",
            doseUnit: "tablets",
            status: status,
            recordedOffset: offset
        )

        #expect(projection.consumedQuantity == expectedConsumption)
        #expect(projection.projectedRemainingQuantity == 3 - expectedConsumption)
        #expect(projection.averageDailyConsumption == expectedAverage)
        #expect(projection.needsRefillReminder == (expectedConsumption > 0))
        #expect(!projection.issues.contains { $0.kind == .doseUnitMismatch })
    }
}

private func makeStockUnitProjection(
    stockUnit: String,
    doseUnit: String,
    status: DoseEventStatus = .taken,
    recordedOffset: TimeInterval = 1
) -> MedicationStockProjection {
    let checkpoint = Date(timeIntervalSince1970: 1_750_000_000)
    let dose = ScheduledDose(
        planID: UUID(),
        dueAt: checkpoint.addingTimeInterval(60),
        dose: DoseAmount(value: 2, unit: doseUnit)
    )
    return MedicationStockEstimator().project(
        stock: MedicationStock(
            medicationID: UUID(),
            remainingQuantity: 3,
            unit: stockUnit,
            lowStockThreshold: 2,
            lastUpdated: checkpoint
        ),
        scheduledDoses: [dose],
        events: [DoseEvent(
            scheduledDoseID: dose.id,
            status: status,
            recordedAt: checkpoint.addingTimeInterval(recordedOffset)
        )],
        timeZone: TimeZone(secondsFromGMT: 0)!
    )
}

private func makeStockDate(calendar: Calendar, day: Int, hour: Int) -> Date {
    calendar.date(from: DateComponents(
        timeZone: calendar.timeZone,
        year: 2026,
        month: 6,
        day: day,
        hour: hour
    ))!
}
