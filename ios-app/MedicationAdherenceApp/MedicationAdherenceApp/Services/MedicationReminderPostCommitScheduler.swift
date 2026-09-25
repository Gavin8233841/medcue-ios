import Foundation
import MedicationAdherenceCore

struct MedicationReminderPostCommitEntry: Sendable, Equatable {
    let taskID: UUID
    let medicationID: UUID
    let planID: UUID
    let medicationName: String
    let doseText: String
    let dueAt: Date
    let deliveryMethodRaw: String
    let escalatesToAlarmWhenUnhandled: Bool
    let medicationIsActive: Bool
    let taskIsOpen: Bool

    @MainActor
    init(
        task: StoredDoseTask,
        medication: StoredMedication,
        deliveryMethod: StoredReminderDeliveryMethod,
        escalatesToAlarmWhenUnhandled: Bool
    ) {
        taskID = task.id
        medicationID = medication.id
        planID = task.planID
        medicationName = userFacingMedicationName(for: medication)
        doseText = "\(task.doseValue.formatted()) \(localizedMedicationUnit(task.doseUnit))"
        dueAt = task.dueAt
        deliveryMethodRaw = deliveryMethod.rawValue
        self.escalatesToAlarmWhenUnhandled = escalatesToAlarmWhenUnhandled
        medicationIsActive = medication.lifecycleStatus == .active
        taskIsOpen = task.status == .pending || task.status == .delayed
    }
}

struct MedicationReminderPostCommitSnapshot: Sendable, Equatable {
    let entries: [MedicationReminderPostCommitEntry]
    let cancelledTaskIDs: [UUID]

    init(
        entries: [MedicationReminderPostCommitEntry],
        cancelledTaskIDs: [UUID]
    ) {
        self.entries = entries
        self.cancelledTaskIDs = cancelledTaskIDs
    }

    @MainActor
    init(batch: MedicationReminderScheduleBatch) {
        entries = batch.tasks.map { task in
            MedicationReminderPostCommitEntry(
                task: task,
                medication: batch.medication,
                deliveryMethod: batch.deliveryMethod,
                escalatesToAlarmWhenUnhandled: batch.escalatesToAlarmWhenUnhandled
            )
        }
        cancelledTaskIDs = batch.cancelledTaskIDs
    }

    @MainActor
    init(
        batches: [MedicationReminderScheduleBatch],
        additionalCancelledTaskIDs: [UUID] = []
    ) {
        entries = batches.flatMap { batch in
            batch.tasks.map { task in
                MedicationReminderPostCommitEntry(
                    task: task,
                    medication: batch.medication,
                    deliveryMethod: batch.deliveryMethod,
                    escalatesToAlarmWhenUnhandled: batch.escalatesToAlarmWhenUnhandled
                )
            }
        }
        cancelledTaskIDs = batches.flatMap(\.cancelledTaskIDs) + additionalCancelledTaskIDs
    }
}

enum MedicationReminderSystemOperationQueue {
    static let shared = ReminderOperationQueue()
}

enum MedicationReminderPostCommitDispatcher {
    @discardableResult
    @MainActor
    static func dispatch(_ snapshot: MedicationReminderPostCommitSnapshot) -> Task<Void, Never> {
        let operation = NotificationService().beginApplyReminderSnapshot(snapshot)
        return Task { _ = await operation.value }
    }
}
