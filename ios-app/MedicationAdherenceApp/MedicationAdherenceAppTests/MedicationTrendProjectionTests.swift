import Foundation
import MedicationAdherenceCore
import Testing
@testable import MedicationAdherenceApp

struct MedicationTrendProjectionTests {
    @Test
    func inputCopiesValuesAwayFromLiveSwiftDataModels() {
        let task = StoredDoseTask(
            medicationID: UUID(),
            dueAt: Date(timeIntervalSince1970: 100),
            doseValue: 1,
            doseUnit: "片",
            status: .taken,
            recordedAt: Date(timeIntervalSince1970: 110)
        )

        let input = MedicationTrendProjection.input(
            tasks: [task],
            doseChanges: [],
            medications: [],
            plans: [],
            lifecycleEvents: [],
            healthSignals: [],
            timeContext: MedicationTrendTimeContext(
                now: Date(timeIntervalSince1970: 200),
                timeZone: .gmt
            )
        )
        task.doseValue = 9
        task.status = .pending

        #expect(input.scheduledDoses.first?.dose.value == 1)
        #expect(input.events.first?.status == .taken)
    }

    @Test
    func revisionChangesWhenTaskOrHealthSignalChanges() {
        let task = StoredDoseTask(
            medicationID: UUID(),
            dueAt: Date(timeIntervalSince1970: 100),
            doseValue: 1,
            doseUnit: "片"
        )
        let firstSignal = HealthSignalSample(
            kind: .heartRate,
            measuredAt: Date(timeIntervalSince1970: 120),
            value: 70,
            unit: "count/min"
        )
        let firstRevision = MedicationTrendProjection.revision(
            tasks: [task],
            doseChanges: [],
            medications: [],
            plans: [],
            lifecycleEvents: [],
            healthSignals: [firstSignal]
        )

        task.status = .skipped
        let taskRevision = MedicationTrendProjection.revision(
            tasks: [task],
            doseChanges: [],
            medications: [],
            plans: [],
            lifecycleEvents: [],
            healthSignals: [firstSignal]
        )
        let secondSignal = HealthSignalSample(
            kind: .heartRate,
            measuredAt: Date(timeIntervalSince1970: 130),
            value: 72,
            unit: "count/min"
        )
        let signalRevision = MedicationTrendProjection.revision(
            tasks: [task],
            doseChanges: [],
            medications: [],
            plans: [],
            lifecycleEvents: [],
            healthSignals: [firstSignal, secondSignal]
        )

        #expect(firstRevision != taskRevision)
        #expect(taskRevision != signalRevision)
    }

    @Test
    func revisionChangesAcrossDayOrTimeZone() {
        let utc = TimeZone(secondsFromGMT: 0)!
        let shanghai = TimeZone(identifier: "Asia/Shanghai")!
        let firstDay = MedicationTrendTimeContext(
            now: Date(timeIntervalSince1970: 1_700_000_000),
            timeZone: utc
        )
        let nextDay = MedicationTrendTimeContext(
            now: Date(timeIntervalSince1970: 1_700_086_400),
            timeZone: utc
        )
        let changedTimeZone = MedicationTrendTimeContext(
            now: firstDay.now,
            timeZone: shanghai
        )

        let firstRevision = MedicationTrendProjection.revision(
            tasks: [],
            doseChanges: [],
            medications: [],
            plans: [],
            lifecycleEvents: [],
            healthSignals: [],
            timeContext: firstDay
        )
        let nextDayRevision = MedicationTrendProjection.revision(
            tasks: [],
            doseChanges: [],
            medications: [],
            plans: [],
            lifecycleEvents: [],
            healthSignals: [],
            timeContext: nextDay
        )
        let changedTimeZoneRevision = MedicationTrendProjection.revision(
            tasks: [],
            doseChanges: [],
            medications: [],
            plans: [],
            lifecycleEvents: [],
            healthSignals: [],
            timeContext: changedTimeZone
        )

        #expect(firstRevision != nextDayRevision)
        #expect(firstRevision != changedTimeZoneRevision)
    }
}
