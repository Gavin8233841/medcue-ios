import Foundation
import MedicationAdherenceCore
import SwiftData

struct MedicationLifecycleUpdate {
    let medicationID: UUID
    let status: StoredMedicationLifecycleStatus
    let note: String
    let occurredAt: Date
}

struct MedicationLifecycleCommit {
    let medicationID: UUID
    let disabledTaskIDs: [UUID]
    let reminderBatches: [MedicationReminderScheduleBatch]
}

enum MedicationLifecycleRejection: Equatable {
    case medicationNotFound
    case readFailed
    case unchangedStatus
}

enum MedicationLifecycleCommandOutcome {
    case committed(MedicationLifecycleCommit)
    case rejected(MedicationLifecycleRejection)
    case scheduleFailed
    case saveFailed
}

@MainActor
struct MedicationLifecycleCommand {
    typealias SaveOperation = (ModelContext) throws -> Void

    private let modelContext: ModelContext
    private let calendar: Calendar
    private let saveOperation: SaveOperation
    private let scheduleDoses: MedicationReminderTaskCoordinator.ScheduleDoses

    init(
        modelContext: ModelContext,
        calendar: Calendar = .current,
        saveOperation: @escaping SaveOperation = { try $0.save() },
        scheduleDoses: @escaping MedicationReminderTaskCoordinator.ScheduleDoses = {
            try ReminderScheduleEngine().scheduledDoses(for: $0, calendar: $1, timeZone: $2)
        }
    ) {
        self.modelContext = modelContext
        self.calendar = calendar
        self.saveOperation = saveOperation
        self.scheduleDoses = scheduleDoses
    }

    func update(_ input: MedicationLifecycleUpdate) -> MedicationLifecycleCommandOutcome {
        let medicationID = input.medicationID
        var medicationDescriptor = FetchDescriptor<StoredMedication>(
            predicate: #Predicate<StoredMedication> { medication in
                medication.id == medicationID
            }
        )
        medicationDescriptor.fetchLimit = 1

        let medication: StoredMedication
        let plans: [StoredMedicationPlan]
        let tasks: [StoredDoseTask]
        do {
            guard let storedMedication = try modelContext.fetch(medicationDescriptor).first else {
                return .rejected(.medicationNotFound)
            }
            medication = storedMedication
            plans = try modelContext.fetch(
                FetchDescriptor<StoredMedicationPlan>(
                    predicate: #Predicate<StoredMedicationPlan> { plan in
                        plan.medicationID == medicationID
                    },
                    sortBy: [SortDescriptor(\.createdAt)]
                )
            )
            tasks = try modelContext.fetch(
                FetchDescriptor<StoredDoseTask>(
                    predicate: #Predicate<StoredDoseTask> { task in
                        task.medicationID == medicationID
                    },
                    sortBy: [SortDescriptor(\.dueAt)]
                )
            )
        } catch {
            return .rejected(.readFailed)
        }

        let previousStatus = medication.lifecycleStatus
        guard previousStatus != input.status else {
            return .rejected(.unchangedStatus)
        }

        let isReactivating =
            (previousStatus == .archived || previousStatus == .interrupted)
            && input.status == .active
        let actionLogs: [StoredDoseActionLog]
        let doseChanges: [StoredMedicationDoseChange]
        if isReactivating {
            do {
                let taskIDs = tasks.map(\.id)
                if taskIDs.isEmpty {
                    actionLogs = []
                } else {
                    actionLogs = try modelContext.fetch(
                        FetchDescriptor<StoredDoseActionLog>(
                            predicate: #Predicate<StoredDoseActionLog> { log in
                                taskIDs.contains(log.taskID)
                            }
                        )
                    )
                }
                doseChanges = try modelContext.fetch(
                    FetchDescriptor<StoredMedicationDoseChange>(
                        predicate: #Predicate<StoredMedicationDoseChange> { change in
                            change.medicationID == medicationID
                        }
                    )
                )
            } catch {
                return .rejected(.readFailed)
            }
        } else {
            actionLogs = []
            doseChanges = []
        }

        let coordinator = MedicationReminderTaskCoordinator(
            calendar: calendar,
            referenceDate: input.occurredAt,
            scheduleDoses: scheduleDoses
        )
        let preparedPlans: [PreparedMedicationReminderPlan]
        if isReactivating {
            let tasksByPlanID = Dictionary(grouping: tasks, by: \.planID)
            do {
                preparedPlans = try plans.map { plan in
                    try coordinator.preparePlan(
                        plan,
                        medication: medication,
                        planTasks: tasksByPlanID[plan.id] ?? [],
                        actionLogs: actionLogs,
                        doseChanges: doseChanges.filter {
                            $0.planID == plan.id || ($0.planID == nil && $0.medicationID == medication.id)
                        },
                        treatingMedicationAsActive: true
                    )
                }
            } catch {
                return .scheduleFailed
            }
        } else {
            preparedPlans = []
        }

        let snapshots = tasks.map(MedicationLifecycleTaskSnapshot.init)
        medication.lifecycleStatus = input.status
        modelContext.insert(
            StoredMedicationLifecycleEvent(
                medicationID: medication.id,
                status: input.status,
                occurredAt: input.occurredAt,
                note: input.note
            )
        )

        var disabledTaskIDs: [UUID] = []
        var reminderBatches: [MedicationReminderScheduleBatch] = []
        let operation: StaticString
        if input.status == .archived || input.status == .interrupted {
            operation = "medication-deactivate-with-future-tasks"
            let todayStart = calendar.startOfDay(for: input.occurredAt)
            let affectedTasks = tasks.filter { task in
                (task.status == .pending || task.status == .delayed)
                    && task.dueAt >= todayStart
            }
            let reason = input.status == .interrupted
                ? "药物已中断，未来提醒已停用。"
                : "药物已归档，未来提醒已停用。"
            for task in affectedTasks {
                task.status = .skipped
                task.recordedAt = nil
                task.reason = reason
            }
            disabledTaskIDs = affectedTasks.map(\.id).sorted { $0.uuidString < $1.uuidString }
        } else if isReactivating {
            operation = "medication-reactivate-with-future-tasks"
            reminderBatches = preparedPlans.map { coordinator.applyPreparedPlan($0, in: modelContext) }
        } else {
            operation = "medication-lifecycle-update"
        }

        do {
            try saveOperation(modelContext)
            return .committed(
                MedicationLifecycleCommit(
                    medicationID: medication.id,
                    disabledTaskIDs: disabledTaskIDs,
                    reminderBatches: reminderBatches
                )
            )
        } catch {
            medication.lifecycleStatus = previousStatus
            snapshots.forEach { $0.restore() }
            modelContext.rollback()
            AppPersistenceCommitter.reportFailure(operation: operation)
            return .saveFailed
        }
    }
}

private struct MedicationLifecycleTaskSnapshot {
    let task: StoredDoseTask
    let status: StoredDoseStatus
    let dueAt: Date
    let recordedAt: Date?
    let reason: String

    init(_ task: StoredDoseTask) {
        self.task = task
        status = task.status
        dueAt = task.dueAt
        recordedAt = task.recordedAt
        reason = task.reason
    }

    func restore() {
        task.status = status
        task.dueAt = dueAt
        task.recordedAt = recordedAt
        task.reason = reason
    }
}
