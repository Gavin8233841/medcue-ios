import Foundation
import MedicationAdherenceCore
import SwiftData

#if canImport(ActivityKit)
import ActivityKit
#endif

enum MedicationReminderLiveActivityActionRejection: Equatable {
    case taskNotFound
    case taskClosed
    case medicationInactive
    case expired
    case readFailed
}

enum MedicationReminderLiveActivityActionCommandOutcome: Equatable {
    case committed(taskIDs: [UUID])
    case alreadyCommitted(taskIDs: [UUID])
    case rejected(MedicationReminderLiveActivityActionRejection)
    case saveFailed
}

@MainActor
struct MedicationReminderLiveActivityActionCommand {
    private let persistence: DoseActionPersistence

    init() {
        persistence = DoseActionPersistence()
    }

    init(persistence: DoseActionPersistence) {
        self.persistence = persistence
    }

    func execute(
        _ request: MedicationReminderLiveActivityActionRequest,
        occurredAt: Date,
        in modelContext: ModelContext
    ) -> MedicationReminderLiveActivityActionCommandOutcome {
        let tasks: [StoredDoseTask]
        let medications: [StoredMedication]
        let logs: [StoredDoseActionLog]
        do {
            tasks = try modelContext.fetch(FetchDescriptor<StoredDoseTask>())
            medications = try modelContext.fetch(FetchDescriptor<StoredMedication>())
            logs = try modelContext.fetch(FetchDescriptor<StoredDoseActionLog>())
        } catch {
            return .rejected(.readFailed)
        }

        let operationID = request.operationID ?? request.taskID
        if let existingLog = logs.first(where: { $0.id == operationID }) {
            guard let existingTask = tasks.first(where: { $0.id == existingLog.taskID }) else {
                return .alreadyCommitted(taskIDs: [existingLog.taskID])
            }
            let existingTaskIDs = DoseLogicalGroup.group(containing: existingTask, in: tasks).map(\.id)
            return .alreadyCommitted(taskIDs: existingTaskIDs)
        }

        guard let task = tasks.first(where: { $0.id == request.taskID }) else {
            return .rejected(.taskNotFound)
        }
        let expiresAt = request.expiresAt
            ?? task.dueAt.addingTimeInterval(MedicationLiveActivityPolicy.default.staleWindow)
        guard occurredAt <= expiresAt else {
            return .rejected(.expired)
        }
        guard task.status == .pending || task.status == .delayed else {
            return .rejected(.taskClosed)
        }
        guard medications.first(where: { $0.id == task.medicationID })?.lifecycleStatus == .active else {
            return .rejected(.medicationInactive)
        }

        let openTaskGroup = DoseLogicalGroup.group(containing: task, in: tasks)
            .filter { $0.status == .pending || $0.status == .delayed }
        guard !openTaskGroup.isEmpty else {
            return .rejected(.taskClosed)
        }

        let mutation: DoseActionMutation
        let primaryReason: String
        switch request.action {
        case .markTaken:
            mutation = .markTaken
            primaryReason = "通过实况活动标记已服用"
        case .delay:
            mutation = .delay
            primaryReason = "通过实况活动选择按原计划时间顺延 \(DoseDelayPolicy.delayMinutes) 分钟提醒"
        case .skip:
            mutation = .skip
            primaryReason = "通过实况活动忽略"
        }

        let transitions = DoseActionTransitionPlanner().makeTransitions(
            mutation: mutation,
            taskGroup: openTaskGroup,
            primaryTask: task,
            occurredAt: occurredAt,
            primaryReason: primaryReason,
            mergedReason: "同一剂量重复提醒已随本次实况活动操作合并。",
            primaryActionLogID: operationID
        )

        do {
            try persistence.commit(transitions, in: modelContext)
            return .committed(taskIDs: openTaskGroup.map(\.id))
        } catch {
            return .saveFailed
        }
    }
}

@MainActor
struct MedicationReminderLiveActivityActionService {
    var notificationService: NotificationService
    private let liveActivityService = MedicationLiveActivityService()
    private let command: MedicationReminderLiveActivityActionCommand

    init(notificationService: NotificationService) {
        self.notificationService = notificationService
        command = MedicationReminderLiveActivityActionCommand()
    }

    init(
        notificationService: NotificationService,
        command: MedicationReminderLiveActivityActionCommand
    ) {
        self.notificationService = notificationService
        self.command = command
    }

    func handle(_ request: MedicationReminderLiveActivityActionRequest, in modelContext: ModelContext) async {
        await handle(request, in: modelContext, occurredAt: Date())
    }

    func consumeCompletedLiveActivities(in modelContext: ModelContext) async {
        #if canImport(ActivityKit)
        guard #available(iOS 16.2, *) else {
            return
        }
        // Legacy completed activities are presentation state, not proof that
        // the device owner authenticated or that a dose was taken.
        for activity in Activity<MedicationReminderActivityAttributes>.activities where activity.content.state.isCompleted {
            await activity.end(activity.content, dismissalPolicy: .immediate)
        }
        #endif
    }

    func executeIntentMarkTaken(
        _ request: MedicationReminderLiveActivityActionRequest,
        occurredAt: Date,
        in modelContext: ModelContext
    ) async -> MedicationReminderLiveActivityIntentExecutionOutcome {
        let outcome = command.execute(request, occurredAt: occurredAt, in: modelContext)
        switch outcome {
        case .committed:
            UserDefaults.standard.removeObject(forKey: DoseActionPersistence.failureMessageDefaultsKey)
            await synchronizeCommittedIntentAction(in: modelContext)
            return .committed
        case .alreadyCommitted:
            UserDefaults.standard.removeObject(forKey: DoseActionPersistence.failureMessageDefaultsKey)
            await synchronizeCommittedIntentAction(in: modelContext)
            return .alreadyCommitted
        case .saveFailed:
            UserDefaults.standard.set(
                DoseActionPersistenceError.saveFailed.userMessage,
                forKey: DoseActionPersistence.failureMessageDefaultsKey
            )
            return .saveFailed
        case .rejected:
            return .rejected
        }
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
            notificationService.beginApplyCommittedReminderState(in: modelContext)
            await liveActivityService.end(for: task.id)
            return
        }

        let medications = (try? modelContext.fetch(FetchDescriptor<StoredMedication>())) ?? []
        let medication = medications.first { $0.id == task.medicationID }
        guard medication?.lifecycleStatus == .active else {
            let reminderSync = notificationService.beginApplyCommittedReminderState(in: modelContext)
            _ = await reminderSync.value
            for groupTask in openTaskGroup {
                await liveActivityService.end(for: groupTask.id)
            }
            return
        }

        switch request.action {
        case .markTaken:
            let outcome = command.execute(request, occurredAt: occurredAt, in: modelContext)
            guard outcome.isCommitted else {
                if outcome == .saveFailed {
                    UserDefaults.standard.set(
                        DoseActionPersistenceError.saveFailed.userMessage,
                        forKey: DoseActionPersistence.failureMessageDefaultsKey
                    )
                }
                return
            }
            UserDefaults.standard.removeObject(forKey: DoseActionPersistence.failureMessageDefaultsKey)
            let reminderSync = notificationService.beginApplyCommittedReminderState(in: modelContext)
            _ = await reminderSync.value
            for groupTask in openTaskGroup {
                await liveActivityService.end(for: groupTask.id)
            }
        case .delay:
            let outcome = command.execute(request, occurredAt: occurredAt, in: modelContext)
            guard outcome.isCommitted else {
                reportSaveFailureIfNeeded(outcome)
                return
            }
            UserDefaults.standard.removeObject(forKey: DoseActionPersistence.failureMessageDefaultsKey)
            _ = await notificationService.beginApplyCommittedReminderState(in: modelContext).value
            for groupTask in openTaskGroup {
                await liveActivityService.end(for: groupTask.id)
            }
        case .skip:
            let outcome = command.execute(request, occurredAt: occurredAt, in: modelContext)
            guard outcome.isCommitted else {
                reportSaveFailureIfNeeded(outcome)
                return
            }
            UserDefaults.standard.removeObject(forKey: DoseActionPersistence.failureMessageDefaultsKey)
            let reminderSync = notificationService.beginApplyCommittedReminderState(in: modelContext)
            _ = await reminderSync.value
            for groupTask in openTaskGroup {
                await liveActivityService.end(for: groupTask.id)
            }
        }

        await startNextLiveActivityIfNeeded(in: modelContext)
    }

    private func reportSaveFailureIfNeeded(
        _ outcome: MedicationReminderLiveActivityActionCommandOutcome
    ) {
        if outcome == .saveFailed {
            UserDefaults.standard.set(
                DoseActionPersistenceError.saveFailed.userMessage,
                forKey: DoseActionPersistence.failureMessageDefaultsKey
            )
        }
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

    private func synchronizeCommittedIntentAction(in modelContext: ModelContext) async {
        let reminderSync = notificationService.beginApplyCommittedReminderState(in: modelContext)
        _ = await reminderSync.value
        let tasks = (try? modelContext.fetch(FetchDescriptor<StoredDoseTask>())) ?? []
        let medications = (try? modelContext.fetch(FetchDescriptor<StoredMedication>())) ?? []
        MedicationWatchSnapshotPublisher().publish(tasks: tasks, medications: medications)
        await startNextLiveActivityIfNeeded(in: modelContext)
    }
}

private extension MedicationReminderLiveActivityActionCommandOutcome {
    var isCommitted: Bool {
        switch self {
        case .committed, .alreadyCommitted:
            true
        case .rejected, .saveFailed:
            false
        }
    }
}
