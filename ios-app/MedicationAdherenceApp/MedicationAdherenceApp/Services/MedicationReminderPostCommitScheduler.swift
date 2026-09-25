import Foundation
import MedicationAdherenceCore
import SwiftData

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
    let preservedDeliveredNotificationIDs: Set<String>

    func preservedDeliveredNotificationIDs(at now: Date) -> Set<String> {
        var identifiers = preservedDeliveredNotificationIDs
        for entry in entries where entry.medicationIsActive && entry.taskIsOpen {
            if entry.dueAt <= now {
                identifiers.insert(MedicationReminderSystemIdentifiers.baseNotification(for: entry.taskID))
            }
            if entry.escalatesToAlarmWhenUnhandled,
               DoseReminderPolicy.competitionDemo.escalationDueAt(for: entry.dueAt) <= now {
                identifiers.insert(MedicationReminderSystemIdentifiers.escalationNotification(for: entry.taskID))
            }
        }
        return identifiers
    }

    init(
        entries: [MedicationReminderPostCommitEntry],
        cancelledTaskIDs: [UUID],
        preservedDeliveredNotificationIDs: Set<String> = []
    ) {
        self.entries = entries
        self.cancelledTaskIDs = cancelledTaskIDs
        self.preservedDeliveredNotificationIDs = preservedDeliveredNotificationIDs
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
        preservedDeliveredNotificationIDs = []
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
        preservedDeliveredNotificationIDs = []
    }
}

@MainActor
enum MedicationReminderCommittedSnapshotReader {
    static func read(in modelContext: ModelContext) throws -> MedicationReminderPostCommitSnapshot {
        // A fresh context sees committed records without unrelated unsaved view edits.
        let committed = ModelContext(modelContext.container)
        let medications = try committed.fetch(FetchDescriptor<StoredMedication>())
        let plans = try committed.fetch(FetchDescriptor<StoredMedicationPlan>())
        let tasks = try committed.fetch(FetchDescriptor<StoredDoseTask>())
        let medicationByID = Dictionary(uniqueKeysWithValues: medications.map { ($0.id, $0) })
        let planByID = Dictionary(uniqueKeysWithValues: plans.map { ($0.id, $0) })
        let now = Date()
        let preservedDeliveredNotificationIDs = Set(tasks.flatMap { task -> [String] in
            guard let plan = planByID[task.planID],
                  let medication = medicationByID[plan.medicationID],
                  medication.lifecycleStatus == .active,
                  task.status == .pending || task.status == .delayed else { return [] }
            var identifiers: [String] = []
            if task.dueAt <= now {
                identifiers.append(MedicationReminderSystemIdentifiers.baseNotification(for: task.id))
            }
            if plan.escalatesToAlarmWhenUnhandled,
               DoseReminderPolicy.competitionDemo.escalationDueAt(for: task.dueAt) <= now {
                identifiers.append(MedicationReminderSystemIdentifiers.escalationNotification(for: task.id))
            }
            return identifiers
        })
        let entries = tasks.compactMap { task -> MedicationReminderPostCommitEntry? in
            guard let plan = planByID[task.planID],
                  let medication = medicationByID[plan.medicationID],
                  medication.lifecycleStatus == .active,
                  task.status == .pending || task.status == .delayed,
                  task.dueAt > now || (plan.escalatesToAlarmWhenUnhandled
                      && DoseReminderPolicy.competitionDemo.escalationDueAt(for: task.dueAt) > now)
            else { return nil }
            return MedicationReminderPostCommitEntry(
                task: task,
                medication: medication,
                deliveryMethod: plan.reminderDeliveryMethod,
                escalatesToAlarmWhenUnhandled: plan.escalatesToAlarmWhenUnhandled
            )
        }
        return MedicationReminderPostCommitSnapshot(
            entries: entries,
            cancelledTaskIDs: [],
            preservedDeliveredNotificationIDs: preservedDeliveredNotificationIDs
        )
    }
}

enum MedicationReminderSystemOperationQueue {
    static let shared = ReminderOperationQueue()
}

enum MedicationReminderPostCommitDispatcher {
    @discardableResult
    @MainActor
    static func dispatch(in modelContext: ModelContext) -> Task<Void, Never> {
        let operation = NotificationService().beginApplyCommittedReminderState(in: modelContext)
        return Task { _ = await operation.value }
    }
}
