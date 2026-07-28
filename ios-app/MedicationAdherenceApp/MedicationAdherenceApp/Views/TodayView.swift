import MedicationAdherenceCore
import SwiftData
import SwiftUI

struct TodayView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var tasks: [StoredDoseTask]
    @Query(sort: \StoredMedication.displayName) private var medications: [StoredMedication]
    @Query(sort: \StoredMedicationPlan.createdAt) private var plans: [StoredMedicationPlan]
    @AppStorage("prefersReducedAppMotion") private var prefersReducedAppMotion = false
    @AppStorage(NotificationService.reminderNotificationUnavailableMessageKey) private var reminderNotificationUnavailableMessage = ""
    @AppStorage(DoseActionPersistence.failureMessageDefaultsKey) private var externalDosePersistenceErrorMessage = ""
    @StateObject private var notificationService = NotificationService()
    @StateObject private var liveActivityService = MedicationLiveActivityService()
    @StateObject private var weatherMedicationService = WeatherMedicationService()
    @State private var taskPendingArchive: StoredDoseTask?
    @State private var showingArchiveConfirmation = false
    @State private var showingHandledTasks = false
    @State private var pendingDoseConfirmation: PendingDoseConfirmation?
    @State private var pendingDoseFeedback: PendingDoseFeedback?
    @State private var isOpenTimelineTemporarilyCollapsed = false
    @State private var isHandledTimelineTemporarilyCollapsed = false
    @State private var pendingHandledArrivalCount = 0
    @State private var closingOpenDoseKeys: Set<String> = []
    @State private var reopeningHandledDoseKeys: Set<String> = []
    @State private var handledDropTargetPulse = false
    @State private var doseMigrationSnapshot: DoseMigrationSnapshot?
    @State private var recentlyReopenedDoseKeys: Set<String> = []
    @State private var pendingDoseFeedbackTask: Task<Void, Never>?
    @State private var doseLayoutTransitionTask: Task<Void, Never>?
    @State private var reopenHighlightTasks: [String: Task<Void, Never>] = [:]
    @State private var liveActivityRefreshTask: Task<Void, Never>?
    @State private var completionRateFeedback: CompletionRateFeedback?
    @State private var completionRateDisplayedSnapshot: CompletionRateSnapshot?
    @State private var isCompletionRateFeedbackVisible = false
    @State private var completionRateFeedbackTask: Task<Void, Never>?
    @State private var isCompletionCelebrationDeferred = false
    @State private var completionCelebrationTask: Task<Void, Never>?
    @State private var doseUndoBanner: DoseUndoBanner?
    @State private var doseUndoBannerTask: Task<Void, Never>?
    @State private var isDoseUndoRollbackInFlight = false
    @State private var didRunInitialTodayMaintenance = false
    @State private var showingHelpCenter = false
    @State private var pendingPermissionGate: AppPermissionGate?
    @State private var dosePersistenceErrorMessage: String?
    @State private var doseProjectionStore = TodayDoseProjectionStore()
    private let reminderPolicy = DoseReminderPolicy.competitionDemo

    init() {
        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: Date())
        let queryStart = calendar.date(byAdding: .day, value: -1, to: todayStart) ?? todayStart.addingTimeInterval(-86_400)
        let queryEnd = calendar.date(byAdding: .day, value: 2, to: todayStart) ?? todayStart.addingTimeInterval(172_800)
        _tasks = Query(
            filter: #Predicate<StoredDoseTask> { task in
                task.dueAt >= queryStart && task.dueAt < queryEnd
            },
            sort: \StoredDoseTask.dueAt
        )
    }

    private var delayDurationText: String {
        "\(DoseDelayPolicy.delayMinutes) 分钟"
    }

    private var isDoseInteractionAnimationActive: Bool {
        pendingDoseFeedback != nil
            || pendingDoseFeedbackTask != nil
            || doseLayoutTransitionTask != nil
            || isOpenTimelineTemporarilyCollapsed
            || isHandledTimelineTemporarilyCollapsed
            || handledDropTargetPulse
            || !closingOpenDoseKeys.isEmpty
            || !reopeningHandledDoseKeys.isEmpty
            || doseMigrationSnapshot != nil
    }

    private func doseProjectionInput(now: Date) -> TodayDoseProjectionInput {
        TodayDoseProjectionInput(
            tasks: tasks,
            medications: medications,
            now: now,
            transition: TodayDoseProjectionTransition(
                pendingDoseFeedback: pendingDoseFeedback,
                closingOpenDoseKeys: closingOpenDoseKeys,
                reopeningHandledDoseKeys: reopeningHandledDoseKeys,
                recentlyReopenedDoseKeys: recentlyReopenedDoseKeys,
                isHandledTimelineTemporarilyCollapsed: isHandledTimelineTemporarilyCollapsed,
                handledDropTargetPulse: handledDropTargetPulse,
                pendingHandledArrivalCount: pendingHandledArrivalCount
            )
        )
    }

    private var currentDoseProjection: TodayRenderSnapshot {
        doseProjectionStore.projection(for: doseProjectionInput(now: Date()))
    }

    private var currentCompletionRateSnapshot: CompletionRateSnapshot {
        currentDoseProjection.completionRateSnapshot
    }

    private var weatherMedicationSignature: String {
        medications
            .filter { $0.lifecycleStatus == .active }
            .map { medication in
                [
                    medication.id.uuidString,
                    userFacingMedicationName(for: medication),
                    medication.genericName,
                    medication.form,
                    medication.notes
                ].joined(separator: "::")
            }
            .sorted()
            .joined(separator: "|")
    }

    var body: some View {
        let snapshot = doseProjectionStore.projection(
            for: doseProjectionInput(now: Date())
        )
        TodayScreen(
            snapshot: snapshot,
            notificationUnavailableMessage: reminderNotificationUnavailableMessage,
            completionRateFeedback: completionRateFeedback,
            completionRateDisplayedSnapshot: completionRateDisplayedSnapshot,
            isCompletionRateFeedbackVisible: isCompletionRateFeedbackVisible,
            shouldShowCompletionCelebration: !isCompletionCelebrationDeferred
                && completionRateFeedback == nil,
            prefersReducedMotion: prefersReducedAppMotion,
            isOpenTimelineTemporarilyCollapsed: isOpenTimelineTemporarilyCollapsed,
            isHandledTimelineTemporarilyCollapsed: isHandledTimelineTemporarilyCollapsed,
            pendingDoseConfirmation: pendingDoseConfirmation,
            pendingDoseFeedback: pendingDoseFeedback,
            handledDropTargetPulse: handledDropTargetPulse,
            pendingHandledArrivalCount: pendingHandledArrivalCount,
            closingOpenDoseKeys: closingOpenDoseKeys,
            reopeningHandledDoseKeys: reopeningHandledDoseKeys,
            recentlyReopenedDoseKeys: recentlyReopenedDoseKeys,
            doseMigrationSnapshot: doseMigrationSnapshot,
            weatherHints: weatherMedicationService.hints,
            weatherStatusText: weatherMedicationService.statusText,
            isWeatherLoading: weatherMedicationService.isLoading,
            shouldShowWeatherAuthorization: weatherMedicationService.shouldShowAuthorizationButton,
            doseUndoBanner: doseUndoBanner,
            weatherMedicationSignature: weatherMedicationSignature,
            showingHandledTasks: $showingHandledTasks,
            taskPendingArchive: $taskPendingArchive,
            showingArchiveConfirmation: $showingArchiveConfirmation,
            showingHelpCenter: $showingHelpCenter,
            pendingPermissionGate: $pendingPermissionGate,
            dosePersistenceErrorMessage: $dosePersistenceErrorMessage,
            actions: TodayScreenActions(
                medication: medication,
                logicalDoseKey: logicalDoseKey,
                completionVerb: todayCompletionVerb,
                statusText: { task in
                    todayDoseStatusText(
                        for: task,
                        medication: medication(for: task),
                        delayDurationText: delayDurationText
                    )
                },
                markTaken: requestMarkTaken,
                delay: requestDelay,
                skip: { task in
                    performWithDoseFeedback(task, action: .skip) {
                        mark(task, mutation: .skip, reason: "用户忽略")
                    }
                },
                confirm: confirmPendingDoseConfirmation,
                cancelConfirmation: clearPendingDoseConfirmation,
                undoOrReopen: undoOrReopen,
                archive: archive,
                unarchive: unarchive,
                rollbackUndo: rollbackDoseUndo,
                requestWeatherRefresh: { requestAuthorization in
                    await weatherMedicationService.refresh(
                        medications: medications,
                        requestAuthorization: requestAuthorization
                    )
                },
                initialLoad: {
                    consumeExternalDosePersistenceFailure()
                    runInitialTodayMaintenanceIfNeeded()
                    await notificationService.refreshAuthorizationStatus()
                    await notificationService.refreshPendingReminderCount()
                },
                timerTick: {
                    settleOverdueTasksIfNeeded()
                    Task {
                        await refreshLiveActivities()
                    }
                },
                becameActive: {
                    consumeExternalDosePersistenceFailure()
                    settleOverdueTasksIfNeeded()
                    scheduleLiveActivityRefresh()
                    Task {
                        await notificationService.refreshAuthorizationStatus()
                        await notificationService.refreshPendingReminderCount()
                    }
                },
                cleanup: cleanupTodayScreen
            )
        )
    }

    private func cleanupTodayScreen() {
        cancelDoseTransitionTasks()
        resetDoseTransitionState(animated: false)
        pendingDoseConfirmation = nil
        reopenHighlightTasks.values.forEach { $0.cancel() }
        reopenHighlightTasks = [:]
        liveActivityRefreshTask?.cancel()
        liveActivityRefreshTask = nil
        completionRateFeedbackTask?.cancel()
        completionRateFeedbackTask = nil
        completionCelebrationTask?.cancel()
        completionCelebrationTask = nil
        completionRateFeedback = nil
        completionRateDisplayedSnapshot = nil
        isCompletionRateFeedbackVisible = false
        isCompletionCelebrationDeferred = false
        doseUndoBannerTask?.cancel()
        doseUndoBannerTask = nil
        doseUndoBanner = nil
        isDoseUndoRollbackInFlight = false
    }

    private func cancelDoseTransitionTasks() {
        pendingDoseFeedbackTask?.cancel()
        pendingDoseFeedbackTask = nil
        doseLayoutTransitionTask?.cancel()
        doseLayoutTransitionTask = nil
    }

    private func consumeExternalDosePersistenceFailure() {
        let message = externalDosePersistenceErrorMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty else { return }
        dosePersistenceErrorMessage = message
        externalDosePersistenceErrorMessage = ""
    }

    private func medication(for task: StoredDoseTask) -> StoredMedication? {
        medications.first { $0.id == task.medicationID }
    }

    private func logicalDoseKey(for task: StoredDoseTask) -> String {
        DoseLogicalGroup.key(for: task)
    }

    private func logicalDoseGroup(for task: StoredDoseTask) -> [StoredDoseTask] {
        DoseLogicalGroup.group(containing: task, in: tasks)
    }

    private func isOpenStatus(_ status: StoredDoseStatus) -> Bool {
        status == .pending || status == .delayed
    }

    @discardableResult
    private func mark(_ task: StoredDoseTask, mutation: DoseActionMutation, reason: String) -> Bool {
        let occurredAt = Date()
        let group = logicalDoseGroup(for: task)
        let projection = currentDoseProjection
        let previousCompletionSnapshot = projection.completionRateSnapshot
        let nextCompletionSnapshot = projection.completionRateSnapshot(
            replacingDoseKey: logicalDoseKey(for: task),
            with: mutation.newStatus
        )
        let transitions = DoseActionTransitionPlanner().makeTransitions(
            mutation: mutation,
            taskGroup: group,
            primaryTask: task,
            occurredAt: occurredAt,
            primaryReason: reason,
            mergedReason: "同一剂量重复提醒已随本次操作合并。"
        )
        var didCommit = false
        updateDoseState {
            do {
                try DoseActionPersistence().commit(transitions, in: modelContext)
                didCommit = true
            } catch {
                dosePersistenceErrorMessage = (error as? DoseActionPersistenceError)?.userMessage
                    ?? DoseActionPersistenceError.saveFailed.userMessage
            }
        }
        guard didCommit else { return false }
        presentCompletionRateFeedbackIfNeeded(from: previousCompletionSnapshot, to: nextCompletionSnapshot)
        performDeferredSystemSurfaceSync {
            for groupTask in group {
                notificationService.cancelReminder(for: groupTask.id)
                await liveActivityService.end(for: groupTask.id)
            }
            scheduleLiveActivityRefresh(after: 0.35)
        }
        return true
    }

    @discardableResult
    private func delay(_ task: StoredDoseTask, fromPlannedTime: Bool = false) -> Bool {
        let occurredAt = Date()
        let group = logicalDoseGroup(for: task)
        let primaryReason = fromPlannedTime ? "用户确认按原计划时间顺延 \(delayDurationText)提醒" : "用户选择按原计划时间顺延 \(delayDurationText)提醒"
        let transitions = DoseActionTransitionPlanner().makeTransitions(
            mutation: .delay,
            taskGroup: group,
            primaryTask: task,
            occurredAt: occurredAt,
            primaryReason: primaryReason,
            mergedReason: "同一剂量重复提醒已随本次稍后操作合并。"
        )
        var didCommit = false
        updateDoseState {
            do {
                try DoseActionPersistence().commit(transitions, in: modelContext)
                didCommit = true
            } catch {
                dosePersistenceErrorMessage = (error as? DoseActionPersistenceError)?.userMessage
                    ?? DoseActionPersistenceError.saveFailed.userMessage
            }
        }
        guard didCommit else { return false }
        performDeferredSystemSurfaceSync {
            for groupTask in group {
                await liveActivityService.end(for: groupTask.id)
            }
            scheduleLiveActivityRefresh(after: 0.35)
        }
        if let medication = medication(for: task) {
            performDeferredSystemSurfaceSync(after: 0.95) {
                for groupTask in group {
                    if groupTask.id == task.id {
                        await notificationService.scheduleReminder(
                            for: groupTask,
                            medication: medication,
                            deliveryMethod: reminderDeliveryMethod(for: groupTask)
                        )
                    } else {
                        notificationService.cancelReminder(for: groupTask.id)
                    }
                }
            }
        }
        return true
    }

    private func requestMarkTaken(_ task: StoredDoseTask) {
        guard reminderPolicy.requiresEarlyTakenConfirmation(plannedDueAt: task.dueAt, now: Date()) else {
            performMarkTaken(task, reason: "")
            return
        }
        showPendingDoseConfirmation(for: task, kind: .earlyTaken)
    }

    private func performMarkTaken(_ task: StoredDoseTask, reason: String) {
        performWithDoseFeedback(task, action: .taken) {
            mark(task, mutation: .markTaken, reason: reason)
        }
    }

    private func requestDelay(_ task: StoredDoseTask) {
        guard DoseDelayPolicy.requiresPlannedTimeDelayConfirmation(plannedDueAt: task.dueAt, now: Date()) else {
            performDelay(task, fromPlannedTime: false)
            return
        }
        showPendingDoseConfirmation(for: task, kind: .plannedDelay)
    }

    private func performDelay(_ task: StoredDoseTask, fromPlannedTime: Bool) {
        performWithDoseFeedback(task, action: .delay) {
            delay(task, fromPlannedTime: fromPlannedTime)
        }
    }

    private func showPendingDoseConfirmation(for task: StoredDoseTask, kind: PendingDoseConfirmation.Kind) {
        withAnimation(.snappy(duration: 0.20, extraBounce: 0.02)) {
            pendingDoseConfirmation = PendingDoseConfirmation(doseKey: logicalDoseKey(for: task), kind: kind)
        }
    }

    private func confirmPendingDoseConfirmation(for task: StoredDoseTask) {
        guard pendingDoseConfirmation?.doseKey == logicalDoseKey(for: task),
              let kind = pendingDoseConfirmation?.kind
        else {
            return
        }
        clearPendingDoseConfirmation(for: task)
        switch kind {
        case .earlyTaken:
            performMarkTaken(task, reason: "用户确认提前服用。")
        case .plannedDelay:
            performDelay(task, fromPlannedTime: true)
        }
    }

    private func clearPendingDoseConfirmation(for task: StoredDoseTask) {
        guard pendingDoseConfirmation?.doseKey == logicalDoseKey(for: task) else {
            return
        }
        withAnimation(.easeInOut(duration: 0.16)) {
            pendingDoseConfirmation = nil
        }
    }

    private func settleOverdueTasksIfNeeded(force: Bool = false) {
        let now = Date()
        if isDoseInteractionAnimationActive {
            guard !force else {
                return
            }
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 1_400_000_000)
                guard !Task.isCancelled else {
                    return
                }
                settleOverdueTasksIfNeeded(force: true)
            }
            return
        }
        guard TodayPerformanceGate.shouldRunOverdueSettlement(now: now, force: force) else {
            return
        }
        guard hasPotentialOverdueDoseTask(now: now) else {
            return
        }
        let settlement = NotificationService().settleOverdueDoseTasks(in: modelContext)
        guard settlement.updatedCount > 0 else {
            return
        }
        for taskID in settlement.updatedTaskIDs {
            Task {
                notificationService.cancelReminder(for: taskID)
                await liveActivityService.end(for: taskID)
            }
        }
        scheduleLiveActivityRefresh(after: 0.35)
    }

    private func hasPotentialOverdueDoseTask(now: Date) -> Bool {
        tasks.contains { task in
            guard task.isAdherenceMeasurable,
                  isOpenStatus(task.status),
                  !task.reason.contains("自动记录为忽略")
            else {
                return false
            }
            if task.reason.contains("用户撤销后等待确认") {
                return true
            }
            return reminderPolicy.shouldAutoSkip(plannedDueAt: task.dueAt, now: now)
        }
    }

    private func reminderDeliveryMethod(for task: StoredDoseTask) -> StoredReminderDeliveryMethod {
        plans.first { $0.id == task.planID }?.reminderDeliveryMethod ?? .notification
    }

    private func performWithDoseFeedback(_ task: StoredDoseTask, action: PendingDoseFeedback.Action, commit: @escaping () -> Bool) {
        let doseKey = logicalDoseKey(for: task)
        let migrationSnapshot = action.movesToHandledSection ? doseMigrationSnapshot(for: task, action: action) : nil
        resetDoseTransitionState(animated: false)
        if !prefersReducedAppMotion {
            withAnimation(.easeInOut(duration: 0.16)) {
                pendingDoseFeedback = PendingDoseFeedback(doseKey: doseKey, action: action)
            }
        }

        let didCommit = commit()
        guard didCommit else {
            resetDoseTransitionState(animated: false)
            return
        }
        if pendingDoseFeedback != nil {
            pendingDoseFeedback = PendingDoseFeedback(doseKey: logicalDoseKey(for: task), action: action)
        }

        pendingDoseFeedbackTask?.cancel()
        pendingDoseFeedbackTask = nil
        doseLayoutTransitionTask?.cancel()
        doseLayoutTransitionTask = nil
        guard !prefersReducedAppMotion else {
            return
        }

        pendingDoseFeedbackTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled else {
                return
            }

            if action.movesToHandledSection {
                doseMigrationSnapshot = migrationSnapshot
                prepareHandledDropTarget()
                try? await Task.sleep(nanoseconds: 60_000_000)
                guard !Task.isCancelled else {
                    return
                }
                stageHandledArrival(forDoseKey: doseKey)
            }

            withAnimation(.easeOut(duration: 0.14)) {
                pendingDoseFeedback = nil
            }

            if action.movesToHandledSection {
                try? await Task.sleep(nanoseconds: 120_000_000)
                guard !Task.isCancelled else {
                    return
                }
            }

            guard action.movesToHandledSection else {
                pendingDoseFeedbackTask = nil
                return
            }

            try? await Task.sleep(nanoseconds: 180_000_000)
            guard !Task.isCancelled else {
                return
            }
            withAnimation(.easeOut(duration: 0.14)) {
                _ = closingOpenDoseKeys.remove(doseKey)
                pendingHandledArrivalCount = 0
                handledDropTargetPulse = false
                doseMigrationSnapshot = nil
            }

            try? await Task.sleep(nanoseconds: 80_000_000)
            guard !Task.isCancelled else {
                return
            }
            pendingDoseFeedbackTask = nil
        }
    }

    private func prepareHandledDropTarget() {
        guard !prefersReducedAppMotion else {
            return
        }
        withAnimation(.easeInOut(duration: 0.16)) {
            handledDropTargetPulse = true
            pendingHandledArrivalCount = 1
        }
    }

    private func stageHandledArrival(forDoseKey doseKey: String) {
        guard !prefersReducedAppMotion else {
            return
        }
        withAnimation(.easeInOut(duration: 0.18)) {
            _ = closingOpenDoseKeys.insert(doseKey)
        }
    }

    private func performReopenTransition(_ task: StoredDoseTask, restore: @escaping () -> Void) {
        let migrationSnapshot = doseMigrationSnapshotForReopen(task)
        let doseKey = logicalDoseKey(for: task)
        resetDoseTransitionState(animated: false)
        if !prefersReducedAppMotion {
            withAnimation(.easeInOut(duration: 0.16)) {
                _ = reopeningHandledDoseKeys.insert(doseKey)
                doseMigrationSnapshot = migrationSnapshot
            }
        }

        restore()

        pendingDoseFeedbackTask?.cancel()
        pendingDoseFeedbackTask = nil
        doseLayoutTransitionTask?.cancel()
        doseLayoutTransitionTask = nil
        guard !prefersReducedAppMotion else {
            return
        }

        doseLayoutTransitionTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 460_000_000)
            guard !Task.isCancelled else {
                return
            }
            withAnimation(.easeInOut(duration: 0.18)) {
                _ = reopeningHandledDoseKeys.remove(doseKey)
                doseMigrationSnapshot = nil
            }
            doseLayoutTransitionTask = nil
        }
    }

    private func resetDoseTransitionState(animated: Bool = true) {
        let updates = {
            pendingDoseFeedback = nil
            isOpenTimelineTemporarilyCollapsed = false
            isHandledTimelineTemporarilyCollapsed = false
            handledDropTargetPulse = false
            pendingHandledArrivalCount = 0
            closingOpenDoseKeys = []
            reopeningHandledDoseKeys = []
            doseMigrationSnapshot = nil
        }
        if animated {
            withAnimation(.easeOut(duration: 0.16), updates)
        } else {
            updates()
        }
    }

    private func undoOrReopen(_ task: StoredDoseTask) {
        performReopenTransition(task) {
            let previousCompletionSnapshot = currentCompletionRateSnapshot
            prepareReopenedTaskHighlightIfNeeded(task)
            var outcome: DoseReopenCommandOutcome?
            updateDoseState(animated: false) {
                outcome = DoseReopenCommand(modelContext: modelContext).perform(
                    taskID: task.id,
                    at: Date()
                )
            }
            guard case let .committed(commit) = outcome else {
                resetDoseTransitionState(animated: false)
                return
            }
            let committedTaskIDs = Set(commit.taskIDs)
            let group = tasks.filter { committedTaskIDs.contains($0.id) }
            let nextCompletionSnapshot = currentCompletionRateSnapshot
            presentCompletionRateFeedbackIfNeeded(from: previousCompletionSnapshot, to: nextCompletionSnapshot)
            showDoseUndoBanner(for: task, rollbackToken: commit.rollbackToken)
            clearReopenedTaskHighlightAfterDelay(task)
            performDeferredSystemSurfaceSync {
                await synchronizeSystemSurfacesAfterReopen(for: group, primaryTaskID: task.id)
                scheduleLiveActivityRefresh(after: 0.35)
            }
        }
    }

    private func showDoseUndoBanner(
        for task: StoredDoseTask,
        rollbackToken: DoseReopenRollbackToken
    ) {
        doseUndoBannerTask?.cancel()
        isDoseUndoRollbackInFlight = false
        let medicationName = medication(for: task).map(userFacingMedicationName(for:)) ?? "这条记录"
        let banner = DoseUndoBanner(
            taskID: task.id,
            medicationName: medicationName,
            rollbackToken: rollbackToken
        )
        withAnimation(.snappy(duration: 0.18, extraBounce: 0.01)) {
            doseUndoBanner = banner
        }
        doseUndoBannerTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 30_000_000_000)
            guard !Task.isCancelled, doseUndoBanner?.id == banner.id else {
                return
            }
            dismissDoseUndoBanner()
        }
    }

    private func rollbackDoseUndo(_ banner: DoseUndoBanner) {
        guard !isDoseUndoRollbackInFlight, doseUndoBanner?.id == banner.id else {
            return
        }
        isDoseUndoRollbackInFlight = true
        defer {
            isDoseUndoRollbackInFlight = false
        }
        let previousCompletionSnapshot = currentCompletionRateSnapshot
        var outcome: DoseReopenRollbackOutcome?
        updateDoseState(animated: false) {
            outcome = DoseReopenCommand(modelContext: modelContext).rollback(
                banner.rollbackToken,
                at: Date()
            )
        }
        guard case let .committed(taskIDs) = outcome else { return }
        let restoredTaskIDs = Set(taskIDs)
        let restoredTasks = tasks.filter { restoredTaskIDs.contains($0.id) }
        let nextCompletionSnapshot = currentCompletionRateSnapshot
        presentCompletionRateFeedbackIfNeeded(from: previousCompletionSnapshot, to: nextCompletionSnapshot)
        withAnimation(.easeOut(duration: 0.18)) {
            for task in restoredTasks {
                let doseKey = logicalDoseKey(for: task)
                _ = recentlyReopenedDoseKeys.remove(doseKey)
                _ = reopeningHandledDoseKeys.remove(doseKey)
            }
        }
        performDeferredSystemSurfaceSync {
            for task in restoredTasks {
                await synchronizeSystemSurfacesAfterRollback(for: task, primaryTaskID: banner.taskID)
            }
            scheduleLiveActivityRefresh(after: 0.35)
        }
        dismissDoseUndoBanner()
    }

    private func dismissDoseUndoBanner() {
        doseUndoBannerTask?.cancel()
        doseUndoBannerTask = nil
        withAnimation(.easeInOut(duration: 0.20)) {
            doseUndoBanner = nil
        }
    }

    private func rescheduleReminderIfNeeded(for task: StoredDoseTask) async {
        guard task.dueAt > Date(), isOpenStatus(task.status), let medication = medication(for: task) else {
            notificationService.cancelReminder(for: task.id)
            return
        }
        await notificationService.scheduleReminder(
            for: task,
            medication: medication,
            deliveryMethod: reminderDeliveryMethod(for: task)
        )
    }

    private func synchronizeSystemSurfacesAfterReopen(for group: [StoredDoseTask], primaryTaskID: UUID) async {
        for groupTask in group {
            if groupTask.id == primaryTaskID {
                await rescheduleReminderIfNeeded(for: groupTask)
            } else {
                notificationService.cancelReminder(for: groupTask.id)
            }
            await liveActivityService.end(for: groupTask.id)
        }
    }

    private func synchronizeSystemSurfacesAfterRollback(for task: StoredDoseTask, primaryTaskID: UUID) async {
        if isOpenStatus(task.status) {
            if task.id == primaryTaskID {
                await rescheduleReminderIfNeeded(for: task)
                await liveActivityService.startIfNeeded(for: task, medication: medication(for: task))
            } else {
                notificationService.cancelReminder(for: task.id)
                await liveActivityService.end(for: task.id)
            }
        } else {
            notificationService.cancelReminder(for: task.id)
            await liveActivityService.end(for: task.id)
        }
    }

    private func prepareReopenedTaskHighlightIfNeeded(_ task: StoredDoseTask) {
        guard !prefersReducedAppMotion else {
            return
        }
        let doseKey = logicalDoseKey(for: task)
        reopenHighlightTasks[doseKey]?.cancel()
        _ = recentlyReopenedDoseKeys.insert(doseKey)
    }

    private func clearReopenedTaskHighlightAfterDelay(_ task: StoredDoseTask) {
        guard !prefersReducedAppMotion else {
            return
        }
        let doseKey = logicalDoseKey(for: task)
        reopenHighlightTasks[doseKey] = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 620_000_000)
            guard !Task.isCancelled else {
                return
            }
            withAnimation(.easeOut(duration: 0.12)) {
                _ = recentlyReopenedDoseKeys.remove(doseKey)
            }
            reopenHighlightTasks[doseKey] = nil
        }
    }

    private func archive(_ task: StoredDoseTask) {
        guard !isArchived(task) else {
            return
        }
        var outcome: TodayArchiveVisibilityCommandOutcome?
        updateDoseState {
            outcome = TodayArchiveVisibilityCommand(modelContext: modelContext).perform(
                .archive(taskID: task.id, occurredAt: Date())
            )
        }
        guard case .committed = outcome else { return }
        performDeferredSystemSurfaceSync {
            await liveActivityService.end(for: task.id)
            scheduleLiveActivityRefresh(after: 0.35)
        }
    }

    private func unarchive(_ task: StoredDoseTask) {
        guard isArchived(task) else {
            return
        }
        var outcome: TodayArchiveVisibilityCommandOutcome?
        updateDoseState {
            outcome = TodayArchiveVisibilityCommand(modelContext: modelContext).perform(
                .restore(taskID: task.id, occurredAt: Date())
            )
        }
        guard case .committed = outcome else { return }
        performDeferredSystemSurfaceSync {
            await liveActivityService.end(for: task.id)
            scheduleLiveActivityRefresh(after: 0.35)
        }
    }

    private func isArchived(_ task: StoredDoseTask) -> Bool {
        task.reason.contains("用户已归档")
    }

    private func updateDoseState(animated: Bool = true, _ updates: () -> Void) {
        guard animated, !prefersReducedAppMotion else {
            commitWithoutListMutationAnimation(updates)
            return
        }
        withAnimation(.snappy(duration: 0.24, extraBounce: 0.02)) {
            updates()
        }
    }

    private func commitWithoutListMutationAnimation(_ updates: () -> Void) {
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            updates()
        }
    }

    private func presentCompletionRateFeedbackIfNeeded(from previousSnapshot: CompletionRateSnapshot, to nextSnapshot: CompletionRateSnapshot) {
        guard previousSnapshot.affectsCompletionRate(comparedWith: nextSnapshot), nextSnapshot.totalCount > 0 else {
            return
        }
        deferCompletionCelebrationIfNeeded(nextSnapshot)
        presentCompletionRateFeedback(from: previousSnapshot, to: nextSnapshot)
    }

    private func deferCompletionCelebrationIfNeeded(_ snapshot: CompletionRateSnapshot) {
        guard snapshot.isComplete, !prefersReducedAppMotion else {
            isCompletionCelebrationDeferred = false
            completionCelebrationTask?.cancel()
            completionCelebrationTask = nil
            return
        }
        completionCelebrationTask?.cancel()
        isCompletionCelebrationDeferred = true
        completionCelebrationTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_700_000_000)
            guard !Task.isCancelled else {
                return
            }
            withAnimation(.smooth(duration: 0.30, extraBounce: 0.02)) {
                isCompletionCelebrationDeferred = false
            }
            completionCelebrationTask = nil
        }
    }

    private func presentCompletionRateFeedback(from previousSnapshot: CompletionRateSnapshot, to nextSnapshot: CompletionRateSnapshot) {
        completionRateFeedbackTask?.cancel()
        let feedback = CompletionRateFeedback(previousSnapshot: previousSnapshot, nextSnapshot: nextSnapshot)
        if prefersReducedAppMotion {
            isCompletionRateFeedbackVisible = true
            completionRateFeedback = feedback
            completionRateDisplayedSnapshot = nextSnapshot
            completionRateFeedbackTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                guard !Task.isCancelled, completionRateFeedback?.id == feedback.id else {
                    return
                }
                isCompletionRateFeedbackVisible = false
                completionRateFeedback = nil
                completionRateDisplayedSnapshot = nil
                isCompletionCelebrationDeferred = false
                completionRateFeedbackTask = nil
            }
            return
        }

        withAnimation(.interpolatingSpring(mass: 0.72, stiffness: 170, damping: 19, initialVelocity: 0.10)) {
            completionRateFeedback = feedback
            completionRateDisplayedSnapshot = previousSnapshot
            isCompletionRateFeedbackVisible = true
        }

        completionRateFeedbackTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled, completionRateFeedback?.id == feedback.id else {
                return
            }
            withAnimation(.snappy(duration: 0.14, extraBounce: 0.01)) {
                completionRateDisplayedSnapshot = nextSnapshot
            }

            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard !Task.isCancelled, completionRateFeedback?.id == feedback.id else {
                return
            }
            withAnimation(.interpolatingSpring(mass: 0.78, stiffness: 190, damping: 22, initialVelocity: 0.0)) {
                isCompletionRateFeedbackVisible = false
            }

            try? await Task.sleep(nanoseconds: 260_000_000)
            guard !Task.isCancelled, completionRateFeedback?.id == feedback.id else {
                return
            }
            withAnimation(.snappy(duration: 0.18, extraBounce: 0.0)) {
                completionRateFeedback = nil
                completionRateDisplayedSnapshot = nil
            }
            if nextSnapshot.isComplete {
                withAnimation(.smooth(duration: 0.30, extraBounce: 0.02)) {
                    isCompletionCelebrationDeferred = false
                }
            }
            completionRateFeedbackTask = nil
        }
    }

    private func doseMigrationSnapshot(for task: StoredDoseTask, action: PendingDoseFeedback.Action) -> DoseMigrationSnapshot {
        let medication = medication(for: task)
        let statusText: String
        switch action {
        case .taken:
            statusText = todayCompletionVerb(for: medication)
        case .skip:
            statusText = "已忽略"
        case .delay:
            statusText = "\(delayDurationText)后"
        }
        return DoseMigrationSnapshot(
            id: task.id,
            medicationName: medication.map(userFacingMedicationName(for:)) ?? "未知药品",
            doseText: "\(task.doseValue.formatted()) \(localizedMedicationUnit(task.doseUnit))",
            timeText: AppFormatters.time.string(from: task.dueAt),
            symbolName: medication?.photoSymbolName ?? "pills.fill",
            statusText: statusText,
            direction: .toHandled
        )
    }

    private func doseMigrationSnapshotForReopen(_ task: StoredDoseTask) -> DoseMigrationSnapshot {
        let medication = medication(for: task)
        return DoseMigrationSnapshot(
            id: task.id,
            medicationName: medication.map(userFacingMedicationName(for:)) ?? "未知药品",
            doseText: "\(task.doseValue.formatted()) \(localizedMedicationUnit(task.doseUnit))",
            timeText: AppFormatters.time.string(from: task.dueAt),
            symbolName: medication?.photoSymbolName ?? "pills.fill",
            statusText: "待处理",
            direction: .toOpen
        )
    }

    private func refreshLiveActivities() async {
        for task in currentDoseProjection.eligibleTodayTasks {
            if task.status == .pending || task.status == .delayed {
                await liveActivityService.startIfNeeded(for: task, medication: medication(for: task))
            } else {
                await liveActivityService.end(for: task.id)
            }
        }
    }

    private func scheduleLiveActivityRefresh(after delay: TimeInterval = 0.2) {
        liveActivityRefreshTask?.cancel()
        liveActivityRefreshTask = Task { @MainActor in
            if delay > 0 {
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
            guard !Task.isCancelled else {
                return
            }
            await refreshLiveActivities()
        }
    }

    private func performDeferredSystemSurfaceSync(
        after delay: TimeInterval = 0.75,
        operation: @escaping @MainActor () async -> Void
    ) {
        Task { @MainActor in
            if delay > 0 {
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
            guard !Task.isCancelled else {
                return
            }
            await operation()
        }
    }

    private func runInitialTodayMaintenanceIfNeeded() {
        guard !didRunInitialTodayMaintenance else {
            return
        }
        didRunInitialTodayMaintenance = true
        settleOverdueTasksIfNeeded()
        scheduleLiveActivityRefresh()
    }

}
