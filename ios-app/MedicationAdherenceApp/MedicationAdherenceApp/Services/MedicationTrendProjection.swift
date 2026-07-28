import Foundation
import MedicationAdherenceCore

struct MedicationTrendTimeContext: Sendable, Equatable {
    let now: Date
    let timeZone: TimeZone

    static func current(now: Date = Date()) -> MedicationTrendTimeContext {
        MedicationTrendTimeContext(now: now, timeZone: .current)
    }

    var calendar: Calendar {
        var calendar = Calendar.current
        calendar.timeZone = timeZone
        return calendar
    }

    var revision: String {
        [
            String(calendar.startOfDay(for: now).timeIntervalSinceReferenceDate),
            timeZone.identifier
        ].joined(separator: "|")
    }
}

struct MedicationTrendDashboardInput: Sendable {
    let scheduledDoses: [ScheduledDose]
    let events: [DoseEvent]
    let doseChanges: [MedicationDoseChange]
    let planContexts: [MedicationTrendPlanContext]
    let lifecycleEvents: [MedicationLifecycleEvent]
    let healthSignals: [HealthSignalSample]
    let timeZone: TimeZone
    let now: Date

    func build() -> MedicationTrendDashboard {
        MedicationTrendDashboardBuilder().build(
            scheduledDoses: scheduledDoses,
            events: events,
            doseChanges: doseChanges,
            planContexts: planContexts,
            lifecycleEvents: lifecycleEvents,
            healthSignals: healthSignals,
            timeZone: timeZone,
            now: now
        )
    }
}

enum MedicationTrendProjection {
    static func input(
        tasks: [StoredDoseTask],
        doseChanges: [StoredMedicationDoseChange],
        medications: [StoredMedication],
        plans: [StoredMedicationPlan],
        lifecycleEvents: [StoredMedicationLifecycleEvent] = [],
        healthSignals: [HealthSignalSample] = [],
        timeContext: MedicationTrendTimeContext = .current()
    ) -> MedicationTrendDashboardInput {
        MedicationTrendDashboardInput(
            scheduledDoses: tasks.map(\.coreScheduledDose),
            events: tasks.compactMap(
                \.coreDoseEventUsingEffectiveAdherenceDate
            ),
            doseChanges: doseChanges.map(\.coreDoseChange),
            planContexts: planContexts(
                tasks: tasks,
                medications: medications,
                plans: plans
            ),
            lifecycleEvents: projectedLifecycleEvents(
                tasks: tasks,
                storedEvents: lifecycleEvents
            ),
            healthSignals: healthSignals,
            timeZone: timeContext.timeZone,
            now: timeContext.now
        )
    }

    static func revision(
        tasks: [StoredDoseTask],
        doseChanges: [StoredMedicationDoseChange],
        medications: [StoredMedication],
        plans: [StoredMedicationPlan],
        lifecycleEvents: [StoredMedicationLifecycleEvent],
        healthSignals: [HealthSignalSample],
        timeContext: MedicationTrendTimeContext = .current()
    ) -> String {
        [
            String(stableTaskSignature(tasks)),
            String(stableDoseChangeSignature(doseChanges)),
            String(stableMedicationSignature(medications)),
            String(stablePlanSignature(plans)),
            String(stableLifecycleEventSignature(lifecycleEvents)),
            String(stableHealthSignalSignature(healthSignals)),
            timeContext.revision
        ].joined(separator: "|")
    }

    static func emptyDashboard(
        timeContext: MedicationTrendTimeContext = .current()
    ) -> MedicationTrendDashboard {
        MedicationTrendDashboardBuilder().build(
            scheduledDoses: [],
            events: [],
            timeZone: timeContext.timeZone,
            now: timeContext.now
        )
    }

    private static func planContexts(
        tasks: [StoredDoseTask],
        medications: [StoredMedication],
        plans: [StoredMedicationPlan]
    ) -> [MedicationTrendPlanContext] {
        var medicationIDByPlanID = Dictionary(
            uniqueKeysWithValues: plans.map { ($0.id, $0.medicationID) }
        )
        for task in tasks where medicationIDByPlanID[task.planID] == nil {
            medicationIDByPlanID[task.planID] = task.medicationID
        }

        return medicationIDByPlanID.compactMap { planID, medicationID in
            guard let medication = medications.first(where: {
                $0.id == medicationID
            }) else {
                return nil
            }
            return MedicationTrendPlanContext(
                planID: planID,
                medicationID: medicationID,
                medicationKind: MedicationKind(rawValue: medication.kindRaw)
                    ?? .unknown,
                inputSource: MedicationInputSource(
                    rawValue: medication.inputSourceRaw
                ) ?? .manual,
                lifecycleState: lifecycleState(
                    for: medication.lifecycleStatus
                )
            )
        }
    }

    private static func projectedLifecycleEvents(
        tasks: [StoredDoseTask],
        storedEvents: [StoredMedicationLifecycleEvent]
    ) -> [MedicationLifecycleEvent] {
        let taskArchiveEvents = tasks
            .filter { $0.reason.contains("用户已归档") }
            .map {
                MedicationLifecycleEvent(
                    medicationID: $0.medicationID,
                    state: .archived,
                    occurredAt: $0.effectiveAdherenceDate,
                    note: "用户归档今日记录"
                )
            }
        return storedEvents.map(\.coreLifecycleEvent) + taskArchiveEvents
    }

    private static func lifecycleState(
        for status: StoredMedicationLifecycleStatus
    ) -> MedicationLifecycleState {
        switch status {
        case .active:
            .active
        case .interrupted:
            .interrupted
        case .archived:
            .archived
        }
    }
}

func medicationTrendDashboardInput(
    tasks: [StoredDoseTask],
    doseChanges: [StoredMedicationDoseChange],
    medications: [StoredMedication],
    plans: [StoredMedicationPlan],
    lifecycleEvents: [StoredMedicationLifecycleEvent] = [],
    healthSignals: [HealthSignalSample] = [],
    now: Date = Date()
) -> MedicationTrendDashboardInput {
    MedicationTrendProjection.input(
        tasks: tasks,
        doseChanges: doseChanges,
        medications: medications,
        plans: plans,
        lifecycleEvents: lifecycleEvents,
        healthSignals: healthSignals,
        timeContext: .current(now: now)
    )
}

func medicationTrendDashboard(
    tasks: [StoredDoseTask],
    doseChanges: [StoredMedicationDoseChange],
    medications: [StoredMedication],
    plans: [StoredMedicationPlan],
    lifecycleEvents: [StoredMedicationLifecycleEvent] = [],
    healthSignals: [HealthSignalSample] = []
) -> MedicationTrendDashboard {
    MedicationTrendProjection.input(
        tasks: tasks,
        doseChanges: doseChanges,
        medications: medications,
        plans: plans,
        lifecycleEvents: lifecycleEvents,
        healthSignals: healthSignals
    ).build()
}
