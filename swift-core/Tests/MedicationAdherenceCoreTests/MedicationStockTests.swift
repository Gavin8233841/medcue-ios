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
        lowStockThreshold: 3
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

private func makeStockDate(calendar: Calendar, day: Int, hour: Int) -> Date {
    calendar.date(from: DateComponents(
        timeZone: calendar.timeZone,
        year: 2026,
        month: 6,
        day: day,
        hour: hour
    ))!
}
