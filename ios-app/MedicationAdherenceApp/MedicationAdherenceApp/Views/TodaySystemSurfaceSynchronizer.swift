import Foundation

@MainActor
struct TodaySystemSurfaceAdapter {
    var cancelReminder: @MainActor (UUID) -> Void
    var scheduleReminder: @MainActor (StoredDoseTask, StoredMedication, StoredReminderDeliveryMethod) async -> MedicationReminderSchedulingResult
    var endLiveActivity: @MainActor (UUID) async -> Void
    var startLiveActivity: @MainActor (StoredDoseTask, StoredMedication?) async -> Void
}

enum TodaySystemSurfaceSyncIntent {
    case handled([StoredDoseTask])
    case delayed([StoredDoseTask], primaryTaskID: UUID)
    case reopened([StoredDoseTask], primaryTaskID: UUID)
    case rollback([StoredDoseTask], primaryTaskID: UUID)
}

enum TodaySystemSurfaceSyncResult: Equatable {
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
                cancelReminder: notificationService.cancelReminder(for:),
                scheduleReminder: { task, medication, deliveryMethod in
                    await notificationService.scheduleReminder(
                        for: task,
                        medication: medication,
                        deliveryMethod: deliveryMethod
                    )
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
        switch intent {
        case let .handled(tasks):
            for task in tasks {
                adapter.cancelReminder(task.id)
                await adapter.endLiveActivity(task.id)
            }
            return .completed
        case let .delayed(tasks, primaryTaskID):
            var result = MedicationReminderSchedulingResult.unavailable(
                message: "提醒未安排，请重新查看这项用药。"
            )
            for task in tasks {
                await adapter.endLiveActivity(task.id)
                if task.id == primaryTaskID,
                   isOpen(task),
                   let medication = medicationForTask(task) {
                    result = await adapter.scheduleReminder(
                        task,
                        medication,
                        deliveryMethodForTask(task)
                    )
                } else {
                    adapter.cancelReminder(task.id)
                }
            }
            return .reminder(result)
        case let .reopened(tasks, primaryTaskID):
            var result = TodaySystemSurfaceSyncResult.completed
            for task in tasks {
                if task.id == primaryTaskID,
                   task.dueAt > now(),
                   isOpen(task),
                   let medication = medicationForTask(task) {
                    result = .reminder(await adapter.scheduleReminder(
                        task,
                        medication,
                        deliveryMethodForTask(task)
                    ))
                } else {
                    adapter.cancelReminder(task.id)
                }
                await adapter.endLiveActivity(task.id)
            }
            return result
        case let .rollback(tasks, primaryTaskID):
            var result = TodaySystemSurfaceSyncResult.completed
            for task in tasks {
                if task.id == primaryTaskID,
                   task.dueAt > now(),
                   isOpen(task),
                   let medication = medicationForTask(task) {
                    result = .reminder(await adapter.scheduleReminder(
                        task,
                        medication,
                        deliveryMethodForTask(task)
                    ))
                    await adapter.startLiveActivity(task, medication)
                } else {
                    adapter.cancelReminder(task.id)
                    await adapter.endLiveActivity(task.id)
                }
            }
            return result
        }
    }

    private func isOpen(_ task: StoredDoseTask) -> Bool {
        task.status == .pending || task.status == .delayed
    }
}
