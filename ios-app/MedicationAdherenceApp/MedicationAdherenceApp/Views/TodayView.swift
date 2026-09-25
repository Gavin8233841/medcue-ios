import MedicationAdherenceCore
import SwiftData
import SwiftUI
import UIKit

enum TodayPresentation {
    case complete
    case elder
}

struct TodayView: View {
    @State private var displayedNow: Date
    private let presentation: TodayPresentation
    private let openElderSettings: () -> Void
    private let switchToCompleteMode: () -> Void
    private let elderHelpContactStore: any ElderHelpContactStoring
    private let elderHelpOpener: any ElderHelpOpening
    private let now: () -> Date
    private let dosePersistence: DoseActionPersistence
    private let systemSurfaceAdapter: TodaySystemSurfaceAdapter?

    init(
        presentation: TodayPresentation = .complete,
        openElderSettings: @escaping () -> Void = {},
        switchToCompleteMode: @escaping () -> Void = {},
        elderHelpContactStore: any ElderHelpContactStoring = UserDefaultsElderHelpContactStore(),
        elderHelpOpener: any ElderHelpOpening = SystemElderHelpOpener(),
        now: @escaping () -> Date = Date.init,
        dosePersistence: DoseActionPersistence = DoseActionPersistence(),
        systemSurfaceAdapter: TodaySystemSurfaceAdapter? = nil
    ) {
        self.presentation = presentation
        self.openElderSettings = openElderSettings
        self.switchToCompleteMode = switchToCompleteMode
        self.elderHelpContactStore = elderHelpContactStore
        self.elderHelpOpener = elderHelpOpener
        self.now = now
        self.dosePersistence = dosePersistence
        self.systemSurfaceAdapter = systemSurfaceAdapter
        _displayedNow = State(initialValue: now())
    }

    var body: some View {
        // Re-evaluate the bounded query when the clock crosses a day boundary,
        // without resetting the content view's confirmation or write state.
        TodayContentView(
            presentation: presentation,
            openElderSettings: openElderSettings,
            switchToCompleteMode: switchToCompleteMode,
            elderHelpContactStore: elderHelpContactStore,
            elderHelpOpener: elderHelpOpener,
            now: now,
            displayedNow: displayedNow,
            refreshClock: { displayedNow = now() },
            dosePersistence: dosePersistence,
            systemSurfaceAdapter: systemSurfaceAdapter
        )
    }
}

private struct TodayContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Query private var tasks: [StoredDoseTask]
    @Query(sort: \StoredMedication.displayName) private var medications: [StoredMedication]
    @Query(sort: \StoredMedicationPlan.createdAt) private var plans: [StoredMedicationPlan]
    @AppStorage(AppExperienceMode.storageKey) private var appExperienceModeRaw = AppExperienceMode.complete.rawValue
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
    @State private var elderHelpOpeningErrorMessage: String?
    @State private var elderHelpMissingMessage: String?
    @State private var elderHelpConfirmationPhone: ElderHelpPhoneNumber?
    @State private var elderDoseSuccessMessage: String?
    @State private var elderReminderUnavailableMessage = ""
    @State private var elderActionInProgress = false
    @State private var elderReminderSyncInProgress = false
    @State private var elderOperationID = UUID()
    @State private var elderTapGuardTask: Task<Void, Never>?
    @State private var elderIsLoading = true
    @State private var lastTimerSystemSurfaceRefreshAt: Date?
    @State private var doseProjectionStore = TodayDoseProjectionStore()
    private let presentation: TodayPresentation
    private let openElderSettings: () -> Void
    private let switchToCompleteMode: () -> Void
    private let elderHelpContactStore: any ElderHelpContactStoring
    private let elderHelpOpener: any ElderHelpOpening
    private let now: () -> Date
    private let displayedNow: Date
    private let refreshClock: () -> Void
    private let dosePersistence: DoseActionPersistence
    private let systemSurfaceAdapter: TodaySystemSurfaceAdapter?
    private let reminderPolicy = DoseReminderPolicy.competitionDemo

    private var reduceMotionEnabled: Bool {
        prefersReducedAppMotion || systemReduceMotion
    }

    init(
        presentation: TodayPresentation = .complete,
        openElderSettings: @escaping () -> Void = {},
        switchToCompleteMode: @escaping () -> Void = {},
        elderHelpContactStore: any ElderHelpContactStoring = UserDefaultsElderHelpContactStore(),
        elderHelpOpener: any ElderHelpOpening,
        now: @escaping () -> Date,
        displayedNow: Date,
        refreshClock: @escaping () -> Void,
        dosePersistence: DoseActionPersistence,
        systemSurfaceAdapter: TodaySystemSurfaceAdapter?
    ) {
        self.presentation = presentation
        self.openElderSettings = openElderSettings
        self.switchToCompleteMode = switchToCompleteMode
        self.elderHelpContactStore = elderHelpContactStore
        self.elderHelpOpener = elderHelpOpener
        self.now = now
        self.displayedNow = displayedNow
        self.refreshClock = refreshClock
        self.dosePersistence = dosePersistence
        self.systemSurfaceAdapter = systemSurfaceAdapter
        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: displayedNow)
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

    private var systemSurfaceSynchronizer: TodaySystemSurfaceSynchronizer {
        if let systemSurfaceAdapter {
            return TodaySystemSurfaceSynchronizer(
                adapter: systemSurfaceAdapter,
                medicationForTask: medication(for:),
                deliveryMethodForTask: reminderDeliveryMethod(for:),
                now: now
            )
        }
        return TodaySystemSurfaceSynchronizer(
            notificationService: notificationService,
            liveActivityService: liveActivityService,
            medicationForTask: medication(for:),
            deliveryMethodForTask: reminderDeliveryMethod(for:),
            now: now
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
        doseProjectionStore.projection(for: doseProjectionInput(now: now()))
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
        let now = displayedNow
        let snapshot = doseProjectionStore.projection(
            for: doseProjectionInput(now: now)
        )
        if presentation == .elder {
            ElderTodayScreen(
                snapshot: snapshot.elderSnapshot(medications: medications, now: now),
                pendingDoseConfirmation: pendingDoseConfirmation,
                pendingDoseFeedback: doseInteraction.pendingDoseFeedback,
                inFlightDoseKeys: (elderActionInProgress || elderReminderSyncInProgress)
                    ? Set(snapshot.visibleOpenTimelineTasks.map(logicalDoseKey(for:)))
                        .union(doseInteraction.inFlightDoseKeys)
                    : doseInteraction.inFlightDoseKeys,
                dosePersistenceErrorMessage: $dosePersistenceErrorMessage,
                helpOpeningErrorMessage: $elderHelpOpeningErrorMessage,
                helpMissingMessage: $elderHelpMissingMessage,
                helpConfirmationPhone: $elderHelpConfirmationPhone,
                successFeedback: $elderDoseSuccessMessage,
                notificationUnavailableMessage: elderReminderUnavailableMessage.isEmpty
                    ? (systemSurfaceAdapter == nil ? reminderNotificationUnavailableMessage : "")
                    : elderReminderUnavailableMessage,
                loadErrorMessage: _tasks.fetchError != nil
                    || _medications.fetchError != nil || _plans.fetchError != nil
                    ? "用药信息未能加载。" : nil,
                isLoading: elderIsLoading,
                actions: ElderTodayScreenActions(
                    logicalDoseKey: logicalDoseKey,
                    completionVerb: todayCompletionVerb,
                    markTaken: requestMarkTaken,
                    delay: requestDelay,
                    confirm: confirmPendingDoseConfirmation,
                    cancelConfirmation: clearPendingDoseConfirmation,
                    requestHelp: prepareElderHelp,
                    confirmHelp: confirmElderHelp,
                    cancelHelp: { elderHelpConfirmationPhone = nil },
                    openSettings: openElderSettings,
                    openNotificationSettings: openNotificationSettings,
                    switchToCompleteMode: switchToCompleteMode,
                    initialLoad: initialTodayLoad,
                    timerTick: refreshTodayTimer,
                    becameActive: todayBecameActive,
                    cleanup: cleanupTodayScreen
                )
            )
            .environment(\.medcueReduceMotionEnabled, reduceMotionEnabled)
        } else {
            TodayScreen(
                snapshot: snapshot,
                notificationUnavailableMessage: reminderNotificationUnavailableMessage,
                completionRateFeedback: completionRateFeedback,
                completionRateDisplayedSnapshot: completionRateDisplayedSnapshot,
                isCompletionRateFeedbackVisible: isCompletionRateFeedbackVisible,
                shouldShowCompletionCelebration: !isCompletionCelebrationDeferred
                    && completionRateFeedback == nil,
                prefersReducedMotion: reduceMotionEnabled,
                isOpenTimelineTemporarilyCollapsed: doseInteraction.isOpenTimelineTemporarilyCollapsed,
                isHandledTimelineTemporarilyCollapsed: doseInteraction.isHandledTimelineTemporarilyCollapsed,
                pendingDoseConfirmation: pendingDoseConfirmation,
                pendingDoseFeedback: doseInteraction.pendingDoseFeedback,
                inFlightDoseKeys: doseInteraction.inFlightDoseKeys,
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
                    switchToElderMode: {
                        appExperienceModeRaw = AppExperienceMode.elder.rawValue
                    },
                    requestWeatherRefresh: { requestAuthorization in
                        // The isolated UI fixture must not query real location
                        // or weather services while exercising the complete view.
                        guard systemSurfaceAdapter == nil else { return false }
                        return await weatherMedicationService.refresh(
                            medications: medications,
                            requestAuthorization: requestAuthorization
                        )
                    },
                    initialLoad: initialTodayLoad,
                    timerTick: refreshTodayTimer,
                    becameActive: todayBecameActive,
                    cleanup: cleanupTodayScreen
                )
            )
            .environment(\.medcueReduceMotionEnabled, reduceMotionEnabled)
        }
    }

    @MainActor
    private func initialTodayLoad() async {
        refreshClock()
        elderIsLoading = true
        defer {
            elderIsLoading = false
        }
        consumeExternalDosePersistenceFailure()
        runInitialTodayMaintenanceIfNeeded()
        guard systemSurfaceAdapter == nil else { return }
        await notificationService.refreshAuthorizationStatus()
        await notificationService.refreshPendingReminderCount()
    }

    private func refreshTodayTimer() {
        refreshClock()
        let refreshTime = now()
        if let previous = lastTimerSystemSurfaceRefreshAt {
            let elapsed = refreshTime.timeIntervalSince(previous)
            guard elapsed >= 60 || elapsed < 0 else { return }
        }
        lastTimerSystemSurfaceRefreshAt = refreshTime
        Task {
            await refreshLiveActivities()
        }
    }

    private func todayBecameActive() {
        refreshClock()
        lastTimerSystemSurfaceRefreshAt = now()
        consumeExternalDosePersistenceFailure()
        scheduleLiveActivityRefresh()
        guard systemSurfaceAdapter == nil else { return }
        Task {
            await notificationService.refreshAuthorizationStatus()
            await notificationService.refreshPendingReminderCount()
        }
    }

    private func openNotificationSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    private func prepareElderHelp() {
        let coordinator = ElderHelpRequestCoordinator(
            contactStore: elderHelpContactStore,
            opener: elderHelpOpener
        )
        do {
            guard let phoneNumber = try coordinator.loadPhoneNumber() else {
                elderHelpMissingMessage = "请先添加帮助号码。"
                return
            }
            elderHelpConfirmationPhone = phoneNumber
        } catch let error as ElderHelpContactError {
            elderHelpOpeningErrorMessage = error.userMessage
        } catch {
            elderHelpOpeningErrorMessage = ElderHelpContactError.localStorageUnavailable.userMessage
        }
    }

    private func confirmElderHelp() {
        guard let phoneNumber = elderHelpConfirmationPhone else {
            return
        }
        elderHelpConfirmationPhone = nil
        ElderHelpRequestCoordinator(
            contactStore: elderHelpContactStore,
            opener: elderHelpOpener
        ).open(phoneNumber: phoneNumber) { outcome in
            if outcome == .failed {
                elderHelpOpeningErrorMessage = "电话确认界面没有打开，请检查帮助号码后重试。"
            }
        }
    }

    private func cleanupTodayScreen() {
        elderTapGuardTask?.cancel()
        elderTapGuardTask = nil
        elderActionInProgress = false
        elderReminderSyncInProgress = false
        elderOperationID = UUID()
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
        elderDoseSuccessMessage = nil
        elderHelpConfirmationPhone = nil
        elderHelpMissingMessage = nil
        doseInteraction.inFlightDoseKeys.removeAll()
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
        guard isOpenStatus(task.status) else {
            return false
        }
        let occurredAt = now()
        let group = logicalDoseGroup(for: task).filter { isOpenStatus($0.status) }
        guard !group.isEmpty else {
            return false
        }
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
                try dosePersistence.commit(transitions, in: modelContext)
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
        guard isOpenStatus(task.status) else {
            return false
        }
        let occurredAt = now()
        let group = logicalDoseGroup(for: task).filter { isOpenStatus($0.status) }
        guard !group.isEmpty else {
            return false
        }
        let primaryReason = presentation == .elder
            ? "用户选择 \(delayDurationText)后提醒"
            : fromPlannedTime ? "用户确认按原计划时间顺延 \(delayDurationText)提醒" : "用户选择按原计划时间顺延 \(delayDurationText)提醒"
        let transitions = DoseActionTransitionPlanner().makeTransitions(
            mutation: .delay,
            taskGroup: group,
            primaryTask: task,
            occurredAt: occurredAt,
            primaryReason: primaryReason,
            mergedReason: "同一剂量重复提醒已随本次稍后操作合并。",
            delayedDueAt: presentation == .elder
                ? occurredAt.addingTimeInterval(TimeInterval(DoseDelayPolicy.delayMinutes * 60))
                : nil
        )
        var didCommit = false
        updateDoseState {
            do {
                try dosePersistence.commit(transitions, in: modelContext)
                didCommit = true
            } catch {
                dosePersistenceErrorMessage = (error as? DoseActionPersistenceError)?.userMessage
                    ?? DoseActionPersistenceError.saveFailed.userMessage
            }
        }
        guard didCommit else { return false }
        let operationID = elderOperationID
        if presentation == .elder {
            elderReminderSyncInProgress = true
        }
        performDeferredSystemSurfaceSync(after: presentation == .elder ? 0 : 0.75) {
            let result = await systemSurfaceSynchronizer.synchronize(
                .delayed(group, primaryTaskID: task.id)
            )
            if presentation == .elder, operationID == elderOperationID {
                elderReminderSyncInProgress = false
                switch result {
                case .reminder(.scheduled):
                    elderReminderUnavailableMessage = ""
                    elderDoseSuccessMessage = "已设置 \(delayDurationText)后提醒"
                case .reminder(.unavailable), .completed:
                    elderDoseSuccessMessage = nil
                    elderReminderUnavailableMessage = "记录已保存，提醒未能开启。"
                    UIAccessibility.post(notification: .announcement, argument: elderReminderUnavailableMessage)
                }
            }
            scheduleLiveActivityRefresh(after: 0.35)
        }
        return true
    }

    private func requestMarkTaken(_ task: StoredDoseTask) {
        guard isOpenStatus(task.status),
              presentation != .elder || (!elderActionInProgress && !elderReminderSyncInProgress) else {
            return
        }
        guard reminderPolicy.requiresEarlyTakenConfirmation(plannedDueAt: task.dueAt, now: now()) else {
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
        guard isOpenStatus(task.status),
              presentation != .elder || (!elderActionInProgress && !elderReminderSyncInProgress) else {
            return
        }
        guard presentation != .elder,
              DoseDelayPolicy.requiresPlannedTimeDelayConfirmation(plannedDueAt: task.dueAt, now: now()) else {
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
        let updates = {
            pendingDoseConfirmation = PendingDoseConfirmation(doseKey: logicalDoseKey(for: task), kind: kind)
        }
        if reduceMotionEnabled {
            commitWithoutListMutationAnimation(updates)
        } else {
            withAnimation(.snappy(duration: 0.20, extraBounce: 0.02), updates)
        }
    }

    private func confirmPendingDoseConfirmation(for task: StoredDoseTask) {
        guard pendingDoseConfirmation?.doseKey == logicalDoseKey(for: task),
              let kind = pendingDoseConfirmation?.kind
        else {
            return
        }
        guard isOpenStatus(task.status) else {
            clearPendingDoseConfirmation(for: task)
            announceUpdatedDoseStatus(for: task)
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
        let updates = {
            pendingDoseConfirmation = nil
        }
        if reduceMotionEnabled {
            commitWithoutListMutationAnimation(updates)
        } else {
            withAnimation(.easeInOut(duration: 0.16), updates)
        }
    }

    private func announceUpdatedDoseStatus(for task: StoredDoseTask) {
        let medication = medication(for: task)
        let medicationName = medication.map(userFacingMedicationName(for:)) ?? "用药"
        let status = todayDoseStatusText(
            for: task,
            medication: medication,
            delayDurationText: delayDurationText
        )
        UIAccessibility.post(
            notification: .announcement,
            argument: medicationName + "，" + status
        )
    }

    private func reminderDeliveryMethod(for task: StoredDoseTask) -> StoredReminderDeliveryMethod {
        plans.first { $0.id == task.planID }?.reminderDeliveryMethod ?? .notification
    }

    private func performWithDoseFeedback(_ task: StoredDoseTask, action: PendingDoseFeedback.Action, commit: @escaping () -> Bool) {
        let doseKey = logicalDoseKey(for: task)
        guard presentation != .elder || (!elderActionInProgress && !elderReminderSyncInProgress),
              isOpenStatus(task.status), doseInteraction.beginDoseAction(for: doseKey) else {
            return
        }
        var didCommit = false
        if presentation == .elder {
            elderActionInProgress = true
            elderOperationID = UUID()
        }
        defer {
            if presentation == .elder, didCommit {
                // A double tap must not spill onto the next medication. This guard
                // is independent of animation and Reduce Motion preferences.
                elderTapGuardTask?.cancel()
                elderTapGuardTask = Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(750))
                    guard !Task.isCancelled else { return }
                    doseInteraction.finishDoseAction(for: doseKey)
                    elderActionInProgress = false
                    elderTapGuardTask = nil
                }
            } else {
                doseInteraction.finishDoseAction(for: doseKey)
                elderActionInProgress = false
            }
        }
        let migrationSnapshot = action.movesToHandledSection ? doseMigrationSnapshot(for: task, action: action) : nil
        resetDoseTransitionState(animated: false)
        // Keep a previous success from masking a later save failure; a new success is shown only after commit.
        if presentation == .elder {
            elderDoseSuccessMessage = nil
        }
        let pendingFeedback = PendingDoseFeedback(doseKey: doseKey, action: action)
        if reduceMotionEnabled {
            commitWithoutListMutationAnimation {
                doseInteraction.pendingDoseFeedback = pendingFeedback
            }
        } else {
            withAnimation(.easeInOut(duration: 0.16)) {
                doseInteraction.pendingDoseFeedback = pendingFeedback
            }
        }

        didCommit = commit()
        guard didCommit else {
            resetDoseTransitionState(animated: false)
            return
        }
        showElderDoseSuccess(for: task, action: action)
        if doseInteraction.pendingDoseFeedback != nil {
            doseInteraction.pendingDoseFeedback = PendingDoseFeedback(doseKey: logicalDoseKey(for: task), action: action)
        }

        doseInteraction.cancelScheduledTransitions()
        guard !reduceMotionEnabled else {
            commitWithoutListMutationAnimation {
                doseInteraction.pendingDoseFeedback = nil
            }
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

    private func showElderDoseSuccess(for task: StoredDoseTask, action: PendingDoseFeedback.Action) {
        guard presentation == .elder else {
            return
        }
        let medicationName = medication(for: task).map(userFacingMedicationName(for:)) ?? "这项用药"
        let message: String
        switch action {
        case .taken:
            message = "\(medicationName)\(todayCompletionVerb(for: medication(for: task)))"
        case .delay:
            // The separate post-commit scheduling result owns reminder feedback.
            return
        case .skip:
            message = "\(medicationName)已跳过"
        }
        let present = {
            elderDoseSuccessMessage = message
        }
        if reduceMotionEnabled {
            present()
        } else {
            withAnimation(.easeOut(duration: 0.16), present)
        }
    }

    private func prepareHandledDropTarget() {
        guard !reduceMotionEnabled else {
            return
        }
        withAnimation(.easeInOut(duration: 0.16)) {
            doseInteraction.handledDropTargetPulse = true
            doseInteraction.pendingHandledArrivalCount = 1
        }
    }

    private func stageHandledArrival(forDoseKey doseKey: String) {
        guard !reduceMotionEnabled else {
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
        if !reduceMotionEnabled {
            withAnimation(.easeInOut(duration: 0.16)) {
                _ = doseInteraction.reopeningHandledDoseKeys.insert(doseKey)
                doseInteraction.doseMigrationSnapshot = migrationSnapshot
            }
        }

        restore()

        doseInteraction.cancelScheduledTransitions()
        guard !reduceMotionEnabled else {
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
                    at: now()
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
        if reduceMotionEnabled {
            commitWithoutListMutationAnimation {
                doseUndoBanner = banner
            }
        } else {
            withAnimation(.snappy(duration: 0.18, extraBounce: 0.01)) {
                doseUndoBanner = banner
            }
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
                at: now()
            )
        }
        guard case let .committed(taskIDs) = outcome else { return }
        let restoredTaskIDs = Set(taskIDs)
        let restoredTasks = tasks.filter { restoredTaskIDs.contains($0.id) }
        let nextCompletionSnapshot = currentCompletionRateSnapshot
        presentCompletionRateFeedbackIfNeeded(from: previousCompletionSnapshot, to: nextCompletionSnapshot)
        let clearReopenState = {
            for task in restoredTasks {
                let doseKey = logicalDoseKey(for: task)
                _ = doseInteraction.recentlyReopenedDoseKeys.remove(doseKey)
                _ = doseInteraction.reopeningHandledDoseKeys.remove(doseKey)
            }
        }
        if reduceMotionEnabled {
            commitWithoutListMutationAnimation(clearReopenState)
        } else {
            withAnimation(.easeOut(duration: 0.18), clearReopenState)
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
        if reduceMotionEnabled {
            commitWithoutListMutationAnimation {
                doseUndoBanner = nil
            }
        } else {
            withAnimation(.easeInOut(duration: 0.20)) {
                doseUndoBanner = nil
            }
        }
    }

    private func prepareReopenedTaskHighlightIfNeeded(_ task: StoredDoseTask) {
        guard !reduceMotionEnabled else {
            return
        }
        let doseKey = logicalDoseKey(for: task)
        reopenHighlightTasks[doseKey]?.cancel()
        _ = doseInteraction.recentlyReopenedDoseKeys.insert(doseKey)
    }

    private func clearReopenedTaskHighlightAfterDelay(_ task: StoredDoseTask) {
        guard !reduceMotionEnabled else {
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
                .archive(taskID: task.id, occurredAt: now())
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
                .restore(taskID: task.id, occurredAt: now())
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
        guard animated, !reduceMotionEnabled else {
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
        guard snapshot.isComplete, !reduceMotionEnabled else {
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
        if reduceMotionEnabled {
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
        if let systemSurfaceAdapter {
            for task in currentDoseProjection.eligibleTodayTasks {
                if isOpenStatus(task.status) {
                    await systemSurfaceAdapter.startLiveActivity(task, medication(for: task))
                } else {
                    await systemSurfaceAdapter.endLiveActivity(task.id)
                }
            }
            return
        }
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
        scheduleLiveActivityRefresh()
    }

}
