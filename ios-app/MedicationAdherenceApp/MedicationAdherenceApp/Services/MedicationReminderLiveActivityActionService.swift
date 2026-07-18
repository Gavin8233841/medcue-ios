import Foundation
import MedicationAdherenceCore
import SwiftData

#if canImport(ActivityKit)
import ActivityKit
#endif

@MainActor
struct MedicationReminderLiveActivityActionService {
    var notificationService: NotificationService
    private let liveActivityService = MedicationLiveActivityService()

    private var delayMinutesText: String {
        "\(DoseDelayPolicy.delayMinutes) 分钟"
    }

    func handle(_ request: MedicationReminderLiveActivityActionRequest, in modelContext: ModelContext) async {
        await handle(request, in: modelContext, occurredAt: Date())
    }

    func consumeCompletedLiveActivities(in modelContext: ModelContext) async {
        #if canImport(ActivityKit)
        guard #available(iOS 16.2, *) else {
            return
        }
        for activity in Activity<MedicationReminderActivityAttributes>.activities where activity.content.state.isCompleted {
            await handle(
                MedicationReminderLiveActivityActionRequest(taskID: activity.attributes.taskID, action: .markTaken),
                in: modelContext,
                occurredAt: activity.content.state.completedAt ?? Date()
            )
        }
        #endif
    }

    private func handle(
        _ request: MedicationReminderLiveActivityActionRequest,
        in modelContext: ModelContext,
        occurredAt: Date
    ) async {
        let tasks = (try? modelContext.fetch(FetchDescriptor<StoredDoseTask>())) ?? []
        guard let task = tasks.first(where: { $0.id == request.taskID }) else {
            return
        }

        let taskGroup = DoseLogicalGroup.group(containing: task, in: tasks)
        let openTaskGroup = taskGroup.filter { $0.status == .pending || $0.status == .delayed }
        guard !openTaskGroup.isEmpty else {
            notificationService.cancelReminder(for: task.id)
            await liveActivityService.end(for: task.id)
            return
        }

        let medications = (try? modelContext.fetch(FetchDescriptor<StoredMedication>())) ?? []
        let medication = medications.first { $0.id == task.medicationID }
        let plans = (try? modelContext.fetch(FetchDescriptor<StoredMedicationPlan>())) ?? []
        let plan = plans.first { $0.id == task.planID }
        guard medication?.lifecycleStatus == .active else {
            for groupTask in openTaskGroup {
                notificationService.cancelReminder(for: groupTask.id)
                await liveActivityService.end(for: groupTask.id)
            }
            return
        }

        switch request.action {
        case .markTaken:
            applyAction(
                .markTaken,
                to: openTaskGroup,
                primaryTaskID: task.id,
                newStatus: .taken,
                newDueAt: task.dueAt,
                recordedAt: occurredAt,
                reason: "通过实况活动标记已服用",
                in: modelContext
            )
            for groupTask in openTaskGroup {
                notificationService.cancelReminder(for: groupTask.id)
                await liveActivityService.end(for: groupTask.id)
            }
        case .delay:
            let occurredAt = Date()
            let newDueAt = DoseDelayPolicy.delayedDueAtFromPlannedTime(task.dueAt)
            applyAction(
                .delay,
                to: openTaskGroup,
                primaryTaskID: task.id,
                newStatus: .delayed,
                newDueAt: newDueAt,
                recordedAt: occurredAt,
                reason: "通过实况活动选择按原计划时间顺延 \(delayMinutesText)提醒",
                in: modelContext
            )
            if let medication {
                for groupTask in openTaskGroup {
                    if groupTask.id == task.id {
                        await notificationService.scheduleReminder(
                            for: groupTask,
                            medication: medication,
                            deliveryMethod: plan?.reminderDeliveryMethod ?? .notification
                        )
                    } else {
                        notificationService.cancelReminder(for: groupTask.id)
                    }
                }
            }
            for groupTask in openTaskGroup {
                await liveActivityService.end(for: groupTask.id)
            }
        case .skip:
            applyAction(
                .skip,
                to: openTaskGroup,
                primaryTaskID: task.id,
                newStatus: .skipped,
                newDueAt: task.dueAt,
                recordedAt: occurredAt,
                reason: "通过实况活动忽略",
                in: modelContext
            )
            for groupTask in openTaskGroup {
                notificationService.cancelReminder(for: groupTask.id)
                await liveActivityService.end(for: groupTask.id)
            }
        }

        await startNextLiveActivityIfNeeded(in: modelContext)
    }

    private func applyAction(
        _ action: DoseActionKind,
        to tasks: [StoredDoseTask],
        primaryTaskID: UUID,
        newStatus: StoredDoseStatus,
        newDueAt: Date,
        recordedAt: Date,
        reason: String,
        in modelContext: ModelContext
    ) {
        for task in tasks {
            let taskReason = task.id == primaryTaskID ? reason : "同一剂量重复提醒已随本次实况活动操作合并。"
            let log = StoredDoseActionLog(
                taskID: task.id,
                action: action,
                previousStatus: task.status,
                previousDueAt: task.dueAt,
                previousRecordedAt: task.recordedAt,
                previousReason: task.reason,
                newStatus: newStatus,
                occurredAt: recordedAt,
                undoExpiresAt: recordedAt.addingTimeInterval(10 * 60),
                note: taskReason
            )
            modelContext.insert(log)
            task.status = newStatus
            task.dueAt = newDueAt
            task.recordedAt = recordedAt
            task.reason = taskReason
        }
        try? modelContext.save()
    }

    private func startNextLiveActivityIfNeeded(in modelContext: ModelContext) async {
        let tasks = ((try? modelContext.fetch(FetchDescriptor<StoredDoseTask>())) ?? [])
            .filter { $0.status == .pending || $0.status == .delayed }
            .sorted { $0.dueAt < $1.dueAt }
        let medications = (try? modelContext.fetch(FetchDescriptor<StoredMedication>())) ?? []
        for task in tasks {
            guard let medication = medications.first(where: { $0.id == task.medicationID }),
                  medication.lifecycleStatus == .active
            else {
                await liveActivityService.end(for: task.id)
                continue
            }
            await liveActivityService.startIfNeeded(for: task, medication: medication)
        }
    }
}
