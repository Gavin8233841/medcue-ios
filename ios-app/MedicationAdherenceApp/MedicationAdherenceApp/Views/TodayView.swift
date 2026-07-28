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
    @State private var doseInteraction = TodayDoseInteractionState()
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
        doseInteraction.isAnimationActive
    }

    private var systemSurfaceSynchronizer: TodaySystemSurfaceSynchronizer {
        TodaySystemSurfaceSynchronizer(
            notificationService: notificationService,
            liveActivityService: liveActivityService,
            medicationForTask: medication(for:),
            deliveryMethodForTask: reminderDeliveryMethod(for:)
        )
    }

    private func doseProjectionInput(now: Date) -> TodayDoseProjectionInput {
        TodayDoseProjectionInput(
            tasks: tasks,
            medications: medications,
            now: now,
            transition: doseInteraction.projectionTransition
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
            isOpenTimelineTemporarilyCollapsed: doseInteraction.isOpenTimelineTemporarilyCollapsed,
            isHandledTimelineTemporarilyCollapsed: doseInteraction.isHandledTimelineTemporarilyCollapsed,
            pendingDoseConfirmation: pendingDoseConfirmation,
            pendingDoseFeedback: doseInteraction.pendingDoseFeedback,
            handledDropTargetPulse: doseInteraction.handledDropTargetPulse,
            pendingHandledArrivalCount: doseInteraction.pendingHandledArrivalCount,
            closingOpenDoseKeys: doseInteraction.closingOpenDoseKeys,
            reopeningHandledDoseKeys: doseInteraction.reopeningHandledDoseKeys,
            recentlyReopenedDoseKeys: doseInteraction.recentlyReopenedDoseKeys,
            doseMigrationSnapshot: doseInteraction.doseMigrationSnapshot,
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
        doseInteraction.cancelScheduledTransitions()
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
            await systemSurfaceSynchronizer.synchronize(.handled(group))
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
            await systemSurfaceSynchronizer.synchronize(
                .delayed(group, primaryTaskID: task.id)
            )
            scheduleLiveActivityRefresh(after: 0.35)
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
                doseInteraction.pendingDoseFeedback = PendingDoseFeedback(doseKey: doseKey, action: action)
            }
        }

        let didCommit = commit()
        guard didCommit else {
            resetDoseTransitionState(animated: false)
            return
        }
        if doseInteraction.pendingDoseFeedback != nil {
            doseInteraction.pendingDoseFeedback = PendingDoseFeedback(doseKey: logicalDoseKey(for: task), action: action)
        }

        doseInteraction.cancelScheduledTransitions()
        guard !prefersReducedAppMotion else {
            return
        }

        doseInteraction.pendingDoseFeedbackTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled else {
                return
            }

            if action.movesToHandledSection {
                doseInteraction.doseMigrationSnapshot = migrationSnapshot
                prepareHandledDropTarget()
                try? await Task.sleep(nanoseconds: 60_000_000)
                guard !Task.isCancelled else {
                    return
                }
                stageHandledArrival(forDoseKey: doseKey)
            }

            withAnimation(.easeOut(duration: 0.14)) {
                doseInteraction.pendingDoseFeedback = nil
            }

            if action.movesToHandledSection {
                try? await Task.sleep(nanoseconds: 120_000_000)
                guard !Task.isCancelled else {
                    return
                }
            }

            guard action.movesToHandledSection else {
                doseInteraction.pendingDoseFeedbackTask = nil
                return
            }

            try? await Task.sleep(nanoseconds: 180_000_000)
            guard !Task.isCancelled else {
                return
            }
            withAnimation(.easeOut(duration: 0.14)) {
                _ = doseInteraction.closingOpenDoseKeys.remove(doseKey)
                doseInteraction.pendingHandledArrivalCount = 0
                doseInteraction.handledDropTargetPulse = false
                doseInteraction.doseMigrationSnapshot = nil
            }

            try? await Task.sleep(nanoseconds: 80_000_000)
            guard !Task.isCancelled else {
                return
            }
            doseInteraction.pendingDoseFeedbackTask = nil
        }
    }

    private func prepareHandledDropTarget() {
        guard !prefersReducedAppMotion else {
            return
        }
        withAnimation(.easeInOut(duration: 0.16)) {
            doseInteraction.handledDropTargetPulse = true
            doseInteraction.pendingHandledArrivalCount = 1
        }
    }

    private func stageHandledArrival(forDoseKey doseKey: String) {
        guard !prefersReducedAppMotion else {
            return
        }
        withAnimation(.easeInOut(duration: 0.18)) {
            _ = doseInteraction.closingOpenDoseKeys.insert(doseKey)
        }
    }

    private func performReopenTransition(_ task: StoredDoseTask, restore: @escaping () -> Void) {
        let migrationSnapshot = doseMigrationSnapshotForReopen(task)
        let doseKey = logicalDoseKey(for: task)
        resetDoseTransitionState(animated: false)
        if !prefersReducedAppMotion {
            withAnimation(.easeInOut(duration: 0.16)) {
                _ = doseInteraction.reopeningHandledDoseKeys.insert(doseKey)
                doseInteraction.doseMigrationSnapshot = migrationSnapshot
            }
        }

        restore()

        doseInteraction.cancelScheduledTransitions()
        guard !prefersReducedAppMotion else {
            return
        }

        doseInteraction.doseLayoutTransitionTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 460_000_000)
            guard !Task.isCancelled else {
                return
            }
            withAnimation(.easeInOut(duration: 0.18)) {
                _ = doseInteraction.reopeningHandledDoseKeys.remove(doseKey)
                doseInteraction.doseMigrationSnapshot = nil
            }
            doseInteraction.doseLayoutTransitionTask = nil
        }
    }

    private func resetDoseTransitionState(animated: Bool = true) {
        let updates = {
            doseInteraction.resetTransientVisuals()
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
                await systemSurfaceSynchronizer.synchronize(
                    .reopened(group, primaryTaskID: task.id)
                )
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
                _ = doseInteraction.recentlyReopenedDoseKeys.remove(doseKey)
                _ = doseInteraction.reopeningHandledDoseKeys.remove(doseKey)
            }
        }
        performDeferredSystemSurfaceSync {
            await systemSurfaceSynchronizer.synchronize(
                .rollback(restoredTasks, primaryTaskID: banner.taskID)
            )
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

    private func prepareReopenedTaskHighlightIfNeeded(_ task: StoredDoseTask) {
        guard !prefersReducedAppMotion else {
            return
        }
        let doseKey = logicalDoseKey(for: task)
        reopenHighlightTasks[doseKey]?.cancel()
        _ = doseInteraction.recentlyReopenedDoseKeys.insert(doseKey)
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
                _ = doseInteraction.recentlyReopenedDoseKeys.remove(doseKey)
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
