import Foundation

@MainActor
struct TodaySystemSurfaceAdapter {
    var applyReminderSnapshot: @MainActor (MedicationReminderPostCommitSnapshot) -> Task<[UUID: MedicationReminderSchedulingResult], Never>
    var endLiveActivity: @MainActor (UUID) async -> Void
    var startLiveActivity: @MainActor (StoredDoseTask, StoredMedication?) async -> Void
}

enum TodaySystemSurfaceSyncIntent {
    case handled([StoredDoseTask])
    case delayed([StoredDoseTask], primaryTaskID: UUID)
    case reopened([StoredDoseTask], primaryTaskID: UUID)
    case rollback([StoredDoseTask], primaryTaskID: UUID)
}

enum TodaySystemSurfaceSyncResult: Sendable, Equatable {
    case completed
    case reminder(MedicationReminderSchedulingResult)
}

@MainActor
struct TodaySystemSurfaceSynchronizer {
    let adapter: TodaySystemSurfaceAdapter
    let medicationForTask: (StoredDoseTask) -> StoredMedication?
    let deliveryMethodForTask: (StoredDoseTask) -> StoredReminderDeliveryMethod
    let now: () -> Date

    init(
        adapter: TodaySystemSurfaceAdapter,
        medicationForTask: @escaping (StoredDoseTask) -> StoredMedication?,
        deliveryMethodForTask: @escaping (StoredDoseTask) -> StoredReminderDeliveryMethod,
        now: @escaping () -> Date
    ) {
        self.adapter = adapter
        self.medicationForTask = medicationForTask
        self.deliveryMethodForTask = deliveryMethodForTask
        self.now = now
    }

    init(
        notificationService: NotificationService,
        liveActivityService: MedicationLiveActivityService,
        medicationForTask: @escaping (StoredDoseTask) -> StoredMedication?,
        deliveryMethodForTask: @escaping (StoredDoseTask) -> StoredReminderDeliveryMethod,
        now: @escaping () -> Date = Date.init
    ) {
        self.init(
            adapter: TodaySystemSurfaceAdapter(
                applyReminderSnapshot: { snapshot in
                    notificationService.beginApplyReminderSnapshot(snapshot)
                },
                endLiveActivity: liveActivityService.end(for:),
                startLiveActivity: liveActivityService.startIfNeeded(for:medication:)
            ),
            medicationForTask: medicationForTask,
            deliveryMethodForTask: deliveryMethodForTask,
            now: now
        )
    }

    @discardableResult
    func synchronize(_ intent: TodaySystemSurfaceSyncIntent) async -> TodaySystemSurfaceSyncResult {
        await beginSynchronize(intent).value
    }

    func beginSynchronize(
        _ intent: TodaySystemSurfaceSyncIntent
    ) -> Task<TodaySystemSurfaceSyncResult, Never> {
        switch intent {
        case let .handled(tasks):
            let reminderOperation = adapter.applyReminderSnapshot(MedicationReminderPostCommitSnapshot(
                entries: [],
                cancelledTaskIDs: tasks.map(\.id)
            ))
            return Task { @MainActor in
                _ = await reminderOperation.value
                for task in tasks {
                    await adapter.endLiveActivity(task.id)
                }
                return .completed
            }
        case let .delayed(tasks, primaryTaskID):
            let snapshot = reminderSnapshot(
                tasks: tasks,
                primaryTaskID: primaryTaskID,
                requiresFutureDueAt: false
            )
            let reminderOperation = adapter.applyReminderSnapshot(snapshot)
            return Task { @MainActor in
                let results = await reminderOperation.value
                for task in tasks {
                    await adapter.endLiveActivity(task.id)
                }
                return .reminder(results[primaryTaskID] ?? .unavailable(
                    message: "提醒未安排，请重新查看这项用药。"
                ))
            }
        case let .reopened(tasks, primaryTaskID):
            let snapshot = reminderSnapshot(
                tasks: tasks,
                primaryTaskID: primaryTaskID,
                requiresFutureDueAt: true
            )
            let reminderOperation = adapter.applyReminderSnapshot(snapshot)
            return Task { @MainActor in
                let results = await reminderOperation.value
                for task in tasks {
                    await adapter.endLiveActivity(task.id)
                }
                return results[primaryTaskID].map(TodaySystemSurfaceSyncResult.reminder) ?? .completed
            }
        case let .rollback(tasks, primaryTaskID):
            let snapshot = reminderSnapshot(
                tasks: tasks,
                primaryTaskID: primaryTaskID,
                requiresFutureDueAt: true
            )
            let reminderOperation = adapter.applyReminderSnapshot(snapshot)
            return Task { @MainActor in
                let results = await reminderOperation.value
                for task in tasks {
                    if task.id == primaryTaskID,
                       results[primaryTaskID] != nil,
                       let medication = medicationForTask(task) {
                        await adapter.startLiveActivity(task, medication)
                    } else {
                        await adapter.endLiveActivity(task.id)
                    }
                }
                return results[primaryTaskID].map(TodaySystemSurfaceSyncResult.reminder) ?? .completed
            }
        }
    }

    private func reminderSnapshot(
        tasks: [StoredDoseTask],
        primaryTaskID: UUID,
        requiresFutureDueAt: Bool
    ) -> MedicationReminderPostCommitSnapshot {
        guard let primaryTask = tasks.first(where: { $0.id == primaryTaskID }),
              (!requiresFutureDueAt || primaryTask.dueAt > now()),
              isOpen(primaryTask),
              let medication = medicationForTask(primaryTask)
        else {
            return MedicationReminderPostCommitSnapshot(
                entries: [],
                cancelledTaskIDs: tasks.map(\.id)
            )
        }
        return MedicationReminderPostCommitSnapshot(
            entries: [MedicationReminderPostCommitEntry(
                task: primaryTask,
                medication: medication,
                deliveryMethod: deliveryMethodForTask(primaryTask),
                escalatesToAlarmWhenUnhandled: true
            )],
            cancelledTaskIDs: tasks.filter { $0.id != primaryTaskID }.map(\.id)
        )
    }

    private func isOpen(_ task: StoredDoseTask) -> Bool {
        task.status == .pending || task.status == .delayed
    }
}
