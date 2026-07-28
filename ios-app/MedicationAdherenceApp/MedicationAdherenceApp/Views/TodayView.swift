import Combine
import MedicationAdherenceCore
import SwiftData
import SwiftUI
import UIKit

struct TodayView: View {
    @Environment(\.scenePhase) private var scenePhase
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
    @State private var renderSnapshotCache = RevisionSnapshotCache<TodayRenderSnapshot>()
    private let reminderPolicy = DoseReminderPolicy.competitionDemo
    private let liveActivityRefreshTimer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

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

    private var todayTasks: [StoredDoseTask] {
        let calendar = Calendar.current
        return tasks.filter { task in
            guard task.isAdherenceMeasurable else {
                return false
            }
            guard isMedicationActiveForToday(task) else {
                return false
            }
            if calendar.isDateInToday(task.dueAt) {
                return true
            }
            let doseKey = logicalDoseKey(for: task)
            if closingOpenDoseKeys.contains(doseKey) || pendingDoseFeedback?.doseKey == doseKey {
                return true
            }
            return task.status == .delayed
                && task.recordedAt.map(calendar.isDateInToday) == true
                && isOpenStatus(task.status)
        }
    }

    private var displayTodayTasks: [StoredDoseTask] {
        deduplicatedTodayTasks(
            todayTasks.sorted { lhs, rhs in
                if lhs.dueAt == rhs.dueAt {
                    return lhs.id.uuidString < rhs.id.uuidString
                }
                return lhs.dueAt < rhs.dueAt
            }
        )
    }

    private var openTasks: [StoredDoseTask] {
        displayTodayTasks.filter { $0.status == .pending || $0.status == .delayed }
    }

    private var delayDurationText: String {
        "\(DoseDelayPolicy.delayMinutes) 分钟"
    }

    private var nextReminderTask: StoredDoseTask? {
        let now = Date()
        return openTasks
            .filter { $0.dueAt >= now }
            .sorted { lhs, rhs in
                if lhs.dueAt == rhs.dueAt {
                    return lhs.id.uuidString < rhs.id.uuidString
                }
                return lhs.dueAt < rhs.dueAt
            }
            .first
    }

    private var overdueOpenTaskCount: Int {
        let now = Date()
        return openTasks.filter { $0.dueAt < now }.count
    }

    private var visibleOpenTimelineTasks: [StoredDoseTask] {
        displayTodayTasks
            .filter { !isArchived($0) && isOpenStatus($0.status) }
            .sorted { lhs, rhs in
                if lhs.dueAt == rhs.dueAt {
                    return lhs.id.uuidString < rhs.id.uuidString
                }
                return lhs.dueAt < rhs.dueAt
            }
    }

    private var handledTodayTasks: [StoredDoseTask] {
        displayTodayTasks
            .filter { !isArchived($0) && !isOpenStatus($0.status) }
            .sorted { lhs, rhs in
                let lhsRecordedAt = lhs.effectiveAdherenceDate
                let rhsRecordedAt = rhs.effectiveAdherenceDate
                if lhsRecordedAt == rhsRecordedAt {
                    return lhs.id.uuidString < rhs.id.uuidString
                }
                return lhsRecordedAt > rhsRecordedAt
            }
    }

    private var archivedTodayTasks: [StoredDoseTask] {
        displayTodayTasks
            .filter { isArchived($0) }
            .sorted { lhs, rhs in
                if lhs.dueAt == rhs.dueAt {
                    return lhs.id.uuidString < rhs.id.uuidString
                }
                return lhs.dueAt < rhs.dueAt
            }
    }

    private var skippedTodayTasks: [StoredDoseTask] {
        displayTodayTasks
            .filter { !isArchived($0) && $0.status == .skipped }
            .sorted { lhs, rhs in
                if lhs.dueAt == rhs.dueAt {
                    return lhs.id.uuidString < rhs.id.uuidString
                }
                return lhs.dueAt < rhs.dueAt
            }
    }

    private var emptyOpenTimelineMessage: String {
        if todayTasks.isEmpty {
            return "今天还没有用药任务。"
        }
        if !skippedTodayTasks.isEmpty && !isAllTaken {
            return "待处理已清空，今日有 \(skippedTodayTasks.count) 项已忽略。"
        }
        if isAllTaken {
            return "今日用药已完成。"
        }
        return "当前没有待处理用药。"
    }

    private var isAfterLastReminderToday: Bool {
        guard let lastDueAt = displayTodayTasks.map(\.dueAt).max() else {
            return false
        }
        return Date() >= lastDueAt
    }

    private var shouldShowSkippedMedicationSummary: Bool {
        !skippedTodayTasks.isEmpty && (isAfterLastReminderToday || visibleOpenTimelineTasks.isEmpty)
    }

    private var shouldShowHandledSection: Bool {
        !handledTodayTasks.isEmpty || isHandledTimelineTemporarilyCollapsed || handledDropTargetPulse || !reopeningHandledDoseKeys.isEmpty
    }

    private var displayedOpenCount: Int {
        guard !reopeningHandledDoseKeys.isEmpty else {
            return visibleOpenTimelineTasks.count
        }
        let visibleKeys = Set(visibleOpenTimelineTasks.map(logicalDoseKey(for:)))
        let reopeningCount = reopeningHandledDoseKeys.filter { !visibleKeys.contains($0) }.count
        return visibleOpenTimelineTasks.count + reopeningCount
    }

    private var displayedHandledCount: Int {
        if !closingOpenDoseKeys.isEmpty {
            let handledKeys = Set(handledTodayTasks.map(logicalDoseKey(for:)))
            let incomingCount = closingOpenDoseKeys.filter { !handledKeys.contains($0) }.count
            return handledTodayTasks.count + incomingCount
        }
        guard !reopeningHandledDoseKeys.isEmpty else {
            return handledTodayTasks.count + pendingHandledArrivalCount
        }
        let handledKeys = Set(handledTodayTasks.map(logicalDoseKey(for:)))
        let leavingVisibleCount = reopeningHandledDoseKeys.filter { handledKeys.contains($0) }.count
        return max(0, handledTodayTasks.count - leavingVisibleCount)
    }

    private var handledSummaryText: String {
        if handledDropTargetPulse {
            return "正在收起刚刚处理的记录"
        }
        if !reopeningHandledDoseKeys.isEmpty {
            return "正在恢复到待处理记录"
        }
        return handledTodayTasks.first.map { handledTaskSummary(for: $0) } ?? "已处理记录可在这里找回"
    }

    private var handledDisclosureBinding: Binding<Bool> {
        Binding(
            get: { showingHandledTasks && !isHandledTimelineTemporarilyCollapsed },
            set: { showingHandledTasks = $0 }
        )
    }

    private var isDoseListReparenting: Bool {
        isOpenTimelineTemporarilyCollapsed
            || isHandledTimelineTemporarilyCollapsed
            || handledDropTargetPulse
            || !closingOpenDoseKeys.isEmpty
            || !reopeningHandledDoseKeys.isEmpty
            || doseMigrationSnapshot != nil
    }

    private var isDoseInteractionAnimationActive: Bool {
        pendingDoseFeedback != nil
            || pendingDoseFeedbackTask != nil
            || doseLayoutTransitionTask != nil
            || isDoseListReparenting
    }

    private var completedCount: Int {
        displayTodayTasks.filter { $0.status == .taken || $0.status == .corrected }.count
    }

    private var isAllTaken: Bool {
        !displayTodayTasks.isEmpty && completedCount == displayTodayTasks.count
    }

    private var currentCompletionRateSnapshot: CompletionRateSnapshot {
        CompletionRateSnapshot(
            completedCount: completedCount,
            totalCount: displayTodayTasks.count
        )
    }

    private func makeTodayRenderSnapshot(now: Date) -> TodayRenderSnapshot {
        let calendar = Calendar.current
        let todayTasks = tasks.filter { task in
            guard task.isAdherenceMeasurable else {
                return false
            }
            guard isMedicationActiveForToday(task) else {
                return false
            }
            if calendar.isDateInToday(task.dueAt) {
                return true
            }
            let doseKey = logicalDoseKey(for: task)
            if closingOpenDoseKeys.contains(doseKey) || pendingDoseFeedback?.doseKey == doseKey {
                return true
            }
            return task.status == .delayed
                && task.recordedAt.map(calendar.isDateInToday) == true
                && isOpenStatus(task.status)
        }
        let displayTasks = deduplicatedTodayTasks(
            todayTasks.sorted { lhs, rhs in
                if lhs.dueAt == rhs.dueAt {
                    return lhs.id.uuidString < rhs.id.uuidString
                }
                return lhs.dueAt < rhs.dueAt
            }
        )
        let visibleOpenTasks = displayTasks
            .filter { !isArchived($0) && isOpenStatus($0.status) }
            .sorted { lhs, rhs in
                if lhs.dueAt == rhs.dueAt {
                    return lhs.id.uuidString < rhs.id.uuidString
                }
                return lhs.dueAt < rhs.dueAt
            }
        let visibleOpenKeys = Set(visibleOpenTasks.map(logicalDoseKey(for:)))
        var transitionOpenDoseKeys = closingOpenDoseKeys
        if let pendingDoseFeedback {
            transitionOpenDoseKeys.insert(pendingDoseFeedback.doseKey)
        }
        let transitionOpenTasks = displayTasks
            .filter { task in
                !isArchived(task)
                    && transitionOpenDoseKeys.contains(logicalDoseKey(for: task))
                    && !visibleOpenKeys.contains(logicalDoseKey(for: task))
            }
        let displayOpenTasks = (visibleOpenTasks + transitionOpenTasks)
            .sorted { lhs, rhs in
                if lhs.dueAt == rhs.dueAt {
                    return lhs.id.uuidString < rhs.id.uuidString
                }
                return lhs.dueAt < rhs.dueAt
            }
        let handledTasks = displayTasks
            .filter { !isArchived($0) && !isOpenStatus($0.status) }
            .sorted { lhs, rhs in
                let lhsRecordedAt = lhs.effectiveAdherenceDate
                let rhsRecordedAt = rhs.effectiveAdherenceDate
                if lhsRecordedAt == rhsRecordedAt {
                    return lhs.id.uuidString < rhs.id.uuidString
                }
                return lhsRecordedAt > rhsRecordedAt
            }
        let archivedTasks = displayTasks
            .filter { isArchived($0) }
            .sorted { lhs, rhs in
                if lhs.dueAt == rhs.dueAt {
                    return lhs.id.uuidString < rhs.id.uuidString
                }
                return lhs.dueAt < rhs.dueAt
            }
        let skippedTasks = displayTasks
            .filter { !isArchived($0) && $0.status == .skipped }
            .sorted { lhs, rhs in
                if lhs.dueAt == rhs.dueAt {
                    return lhs.id.uuidString < rhs.id.uuidString
                }
                return lhs.dueAt < rhs.dueAt
            }
        let openTasks = displayTasks.filter { $0.status == .pending || $0.status == .delayed }
        let nextReminderTask = openTasks
            .filter { $0.dueAt >= now }
            .sorted { lhs, rhs in
                if lhs.dueAt == rhs.dueAt {
                    return lhs.id.uuidString < rhs.id.uuidString
                }
                return lhs.dueAt < rhs.dueAt
            }
            .first
        let overdueOpenTaskCount = openTasks.filter { $0.dueAt < now }.count
        let completedCount = displayTasks.filter { $0.status == .taken || $0.status == .corrected }.count
        let completionSnapshot = CompletionRateSnapshot(
            completedCount: completedCount,
            totalCount: displayTasks.count
        )
        let isAfterLastReminderToday = displayTasks.map(\.dueAt).max().map { now >= $0 } ?? false
        let isAllTaken = completionSnapshot.isComplete
        let emptyOpenMessage: String
        if todayTasks.isEmpty {
            emptyOpenMessage = "今天还没有用药任务。"
        } else if !skippedTasks.isEmpty && !isAllTaken {
            emptyOpenMessage = "待处理已清空，今日有 \(skippedTasks.count) 项已忽略。"
        } else if isAllTaken {
            emptyOpenMessage = "今日用药已完成。"
        } else {
            emptyOpenMessage = "当前没有待处理用药。"
        }

        let shouldShowSkippedMedicationSummary = !skippedTasks.isEmpty && (isAfterLastReminderToday || visibleOpenTasks.isEmpty)
        let shouldShowHandledSection = !handledTasks.isEmpty
            || isHandledTimelineTemporarilyCollapsed
            || handledDropTargetPulse
            || !reopeningHandledDoseKeys.isEmpty
        let displayedOpenCount: Int
        if reopeningHandledDoseKeys.isEmpty {
            displayedOpenCount = displayOpenTasks.count
        } else {
            let visibleKeys = Set(displayOpenTasks.map(logicalDoseKey(for:)))
            let reopeningCount = reopeningHandledDoseKeys.filter { !visibleKeys.contains($0) }.count
            displayedOpenCount = displayOpenTasks.count + reopeningCount
        }
        let displayedHandledCount: Int
        if !closingOpenDoseKeys.isEmpty {
            let handledKeys = Set(handledTasks.map(logicalDoseKey(for:)))
            let incomingCount = closingOpenDoseKeys.filter { !handledKeys.contains($0) }.count
            displayedHandledCount = handledTasks.count + incomingCount
        } else if reopeningHandledDoseKeys.isEmpty {
            let handledKeys = Set(handledTasks.map(logicalDoseKey(for:)))
            let pendingTaskIsAlreadyHandled = pendingDoseFeedback.map { feedback in
                feedback.action.movesToHandledSection && handledKeys.contains(feedback.doseKey)
            } ?? false
            displayedHandledCount = handledTasks.count + (pendingTaskIsAlreadyHandled ? 0 : pendingHandledArrivalCount)
        } else {
            let handledKeys = Set(handledTasks.map(logicalDoseKey(for:)))
            let leavingVisibleCount = reopeningHandledDoseKeys.filter { handledKeys.contains($0) }.count
            displayedHandledCount = max(0, handledTasks.count - leavingVisibleCount)
        }
        let handledSummaryText: String
        if handledDropTargetPulse {
            handledSummaryText = "正在收起刚刚处理的记录"
        } else if !reopeningHandledDoseKeys.isEmpty {
            handledSummaryText = "正在恢复到待处理记录"
        } else {
            handledSummaryText = handledTasks.first.map { handledTaskSummary(for: $0) } ?? "已处理记录可在这里找回"
        }
        let skippedMedicationSummary = skippedTasks
            .map { medication(for: $0).map(userFacingMedicationName(for:)) ?? "未知药品" }
            .joined(separator: "、")

        return TodayRenderSnapshot(
            visibleOpenTimelineTasks: displayOpenTasks,
            handledTodayTasks: handledTasks,
            archivedTodayTasks: archivedTasks,
            nextReminderTask: nextReminderTask,
            overdueOpenTaskCount: overdueOpenTaskCount,
            emptyOpenTimelineMessage: emptyOpenMessage,
            shouldShowSkippedMedicationSummary: shouldShowSkippedMedicationSummary,
            shouldShowHandledSection: shouldShowHandledSection,
            displayedOpenCount: displayedOpenCount,
            displayedHandledCount: displayedHandledCount,
            handledSummaryText: handledSummaryText,
            skippedMedicationSummary: skippedMedicationSummary,
            completionRateSnapshot: completionSnapshot
        )
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

    private func todayRenderRevision(now: Date) -> String {
        let pendingFeedbackRevision: String
        if let pendingDoseFeedback {
            let action: String
            switch pendingDoseFeedback.action {
            case .taken:
                action = "taken"
            case .delay:
                action = "delay"
            case .skip:
                action = "skip"
            }
            pendingFeedbackRevision = "\(pendingDoseFeedback.doseKey):\(action)"
        } else {
            pendingFeedbackRevision = "none"
        }
        return [
            String(stableTaskSignature(tasks)),
            String(stableMedicationSignature(medications)),
            closingOpenDoseKeys.sorted().joined(separator: ","),
            reopeningHandledDoseKeys.sorted().joined(separator: ","),
            pendingFeedbackRevision,
            String(isHandledTimelineTemporarilyCollapsed),
            String(handledDropTargetPulse),
            String(pendingHandledArrivalCount),
            String(Int(now.timeIntervalSinceReferenceDate / 60))
        ].joined(separator: "|")
    }

    private func startWeatherPermissionFlow() {
        if AppPermissionGate.hasCompletedAuthorization(for: .location) || weatherMedicationService.hasLocationAuthorization {
            if weatherMedicationService.hasLocationAuthorization {
                AppPermissionGate.markAuthorizationCompleted(for: .location)
            }
            Task {
                let granted = await weatherMedicationService.refresh(medications: medications, requestAuthorization: true)
                if granted {
                    AppPermissionGate.markAuthorizationCompleted(for: .location)
                }
            }
        } else {
            pendingPermissionGate = .location
        }
    }

    private var notificationUnavailableDetailText: String? {
        let trimmedMessage = reminderNotificationUnavailableMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedMessage.isEmpty else {
            return nil
        }
        return trimmedMessage.replacingOccurrences(of: "普通提醒不可用：", with: "")
    }

    private var completionRateFeedbackSlotHeight: CGFloat {
        guard completionRateFeedback != nil else {
            return 0
        }
        return isCompletionRateFeedbackVisible ? 88 : 0
    }

    @ViewBuilder
    private var completionRateFeedbackOverlay: some View {
        if let feedback = completionRateFeedback,
           let displayedSnapshot = completionRateDisplayedSnapshot {
            CompletionRateFeedbackPanel(
                feedback: feedback,
                displayedSnapshot: displayedSnapshot,
                isVisible: isCompletionRateFeedbackVisible
            )
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .transition(.asymmetric(
                insertion: .move(edge: .top)
                    .combined(with: .opacity)
                    .combined(with: .scale(scale: 0.985, anchor: .top)),
                removal: .move(edge: .top)
                    .combined(with: .opacity)
                    .combined(with: .scale(scale: 0.99, anchor: .top))
            ))
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .animation(.smooth(duration: 0.38, extraBounce: 0.04), value: isCompletionRateFeedbackVisible)
            .animation(.smooth(duration: 0.34, extraBounce: 0.03), value: feedback.id)
        }
    }

    private var completionRateFeedbackSlot: some View {
        ZStack(alignment: .top) {
            completionRateFeedbackOverlay
        }
        .frame(height: completionRateFeedbackSlotHeight, alignment: .top)
        .accessibilityHidden(true)
        .allowsHitTesting(false)
        .animation(.smooth(duration: 0.38, extraBounce: 0.03), value: completionRateFeedbackSlotHeight)
    }

    private var shouldShowCompletionCelebrationCard: Bool {
        !isCompletionCelebrationDeferred && completionRateFeedback == nil
    }

    private func todaySection<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: 10) {
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func openTimelineSection(snapshot: TodayRenderSnapshot) -> some View {
        todaySection("今日待处理") {
            if isOpenTimelineTemporarilyCollapsed {
                OpenDoseSummaryRow(
                    count: snapshot.displayedOpenCount,
                    latestText: "正在恢复待处理记录",
                    isReceiving: !reopeningHandledDoseKeys.isEmpty,
                    migrationSnapshot: doseMigrationSnapshot
                )
                .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .top)))
            } else if snapshot.visibleOpenTimelineTasks.isEmpty {
                Text(snapshot.emptyOpenTimelineMessage)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
            } else {
                ForEach(snapshot.visibleOpenTimelineTasks) { task in
                    let doseKey = logicalDoseKey(for: task)
                                    TimelineDoseTaskRow(
                                        task: task,
                                        medication: medication(for: task),
                                        completionText: completionVerb(for: medication(for: task)),
                                        statusText: statusText(for: task),
                                        isOpen: task.status == .pending
                                            || task.status == .delayed
                                            || closingOpenDoseKeys.contains(doseKey)
                                            || pendingDoseFeedback?.doseKey == doseKey,
                                        feedbackAction: pendingDoseFeedback?.doseKey == doseKey ? pendingDoseFeedback?.action : nil,
                                        isClosing: closingOpenDoseKeys.contains(doseKey),
                                        isRecentlyReopened: recentlyReopenedDoseKeys.contains(doseKey),
                                        confirmationKind: pendingDoseConfirmation?.doseKey == doseKey ? pendingDoseConfirmation?.kind : nil,
                        markTaken: {
                            requestMarkTaken(task)
                        },
                        delay: {
                            requestDelay(task)
                        },
                        skip: {
                            performWithDoseFeedback(task, action: .skip) {
                                mark(task, mutation: .skip, reason: "用户忽略")
                            }
                        },
                        confirm: {
                            confirmPendingDoseConfirmation(for: task)
                        },
                        cancelConfirmation: {
                            clearPendingDoseConfirmation(for: task)
                        }
                    )
                }
            }
        }
        .animation(.smooth(duration: 0.30, extraBounce: 0.02), value: snapshot.visibleOpenTimelineTasks.map(\.id))
        .animation(.easeInOut(duration: 0.16), value: pendingDoseFeedback)
        .animation(.snappy(duration: 0.24, extraBounce: 0.01), value: isOpenTimelineTemporarilyCollapsed)
        .animation(.easeInOut(duration: 0.18), value: closingOpenDoseKeys)
        .animation(.snappy(duration: 0.24, extraBounce: 0.02), value: recentlyReopenedDoseKeys)
    }

    @ViewBuilder
    private var notificationUnavailableBanner: some View {
        if let detailText = notificationUnavailableDetailText {
            Button {
                openSystemNotificationSettings()
            } label: {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "bell.slash.fill")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.orange)
                        .frame(width: 26, height: 26)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("普通提醒不可用")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                        Text(detailText)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 8)

                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .padding(.top, 4)
                }
                .padding(14)
                .medicationGlassSurface(cornerRadius: 18, tint: .orange, fallbackMaterial: .thinMaterial, isInteractive: true)
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(.orange.opacity(0.16), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .accessibilityHint("打开系统设置检查通知权限")
        }
    }

    @ViewBuilder
    private func handledTimelineSection(snapshot: TodayRenderSnapshot) -> some View {
        todaySection("今日已处理") {
            let isExpanded = handledDisclosureBinding.wrappedValue
            let handledAccessibilityValue = "\(snapshot.displayedHandledCount) 条，\(snapshot.handledSummaryText)，\(isExpanded ? "已展开" : "已折叠")"
            Button {
                withAnimation(.snappy(duration: 0.24, extraBounce: 0.01)) {
                    showingHandledTasks.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    HandledDoseSummaryRow(
                        count: snapshot.displayedHandledCount,
                        latestText: snapshot.handledSummaryText,
                        isReceiving: handledDropTargetPulse || !reopeningHandledDoseKeys.isEmpty,
                        migrationSnapshot: handledDropTargetPulse ? doseMigrationSnapshot : nil
                    )
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }
                .contentShape(Rectangle())
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("今日已处理")
                .accessibilityValue(handledAccessibilityValue)
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("今日已处理")
            .accessibilityValue(handledAccessibilityValue)
            .accessibilityHint(isExpanded ? "收起已处理记录" : "展开已处理记录")

            if isExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(snapshot.handledTodayTasks) { task in
                        let doseKey = logicalDoseKey(for: task)
                        HandledDoseTaskRow(
                            task: task,
                            medication: medication(for: task),
                            statusText: statusText(for: task),
                            undo: { undoOrReopen(task) },
                            archive: {
                                taskPendingArchive = task
                                showingArchiveConfirmation = true
                            }
                        )
                        .opacity(reopeningHandledDoseKeys.contains(doseKey) ? 0.12 : 1)
                        .blur(radius: reopeningHandledDoseKeys.contains(doseKey) ? 4 : 0)
                        .scaleEffect(reopeningHandledDoseKeys.contains(doseKey) ? 0.97 : 1)
                        .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .top)))
                    }
                }
                .padding(.top, 8)
            }
        }
        .animation(isDoseListReparenting ? nil : .snappy(duration: 0.22, extraBounce: 0.01), value: snapshot.handledTodayTasks.map(\.id))
        .animation(.snappy(duration: 0.22, extraBounce: 0.01), value: isHandledTimelineTemporarilyCollapsed)
        .animation(.easeInOut(duration: 0.18), value: reopeningHandledDoseKeys)
        .animation(.easeInOut(duration: 0.2), value: handledDropTargetPulse)
    }

    @ViewBuilder
    private func archivedTimelineSection(snapshot: TodayRenderSnapshot) -> some View {
        if !snapshot.archivedTodayTasks.isEmpty {
            todaySection("今日已归档") {
                ForEach(snapshot.archivedTodayTasks) { task in
                    ArchivedDoseTaskRow(
                        task: task,
                        medication: medication(for: task),
                        statusText: statusText(for: task),
                        restore: { unarchive(task) },
                        reopen: { undoOrReopen(task) }
                    )
                }
            }
        }
    }

    private func nextReminderSection(snapshot: TodayRenderSnapshot) -> some View {
        todaySection("下一次提醒") {
            if let nextTask = snapshot.nextReminderTask {
                HStack {
                    Image(systemName: "bell.badge")
                        .foregroundStyle(.blue)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(medication(for: nextTask).map(userFacingMedicationName(for:)) ?? "用药提醒")
                            .font(.headline)
                        Text(AppFormatters.time.string(from: nextTask.dueAt))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 6)
            } else if snapshot.overdueOpenTaskCount > 0 {
                VStack(alignment: .leading, spacing: 6) {
                    Label("还有 \(snapshot.overdueOpenTaskCount) 项待确认", systemImage: "clock.badge.exclamationmark")
                        .font(.headline)
                        .foregroundStyle(.orange)
                }
                .padding(.vertical, 6)
            } else {
                Text("今天没有待提醒任务。")
                    .foregroundStyle(.secondary)
            }
            if snapshot.shouldShowSkippedMedicationSummary {
                VStack(alignment: .leading, spacing: 8) {
                    Label("今日忽略记录", systemImage: "exclamationmark.circle")
                        .font(.headline)
                        .foregroundStyle(.orange)
                    Text(snapshot.skippedMedicationSummary)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 6)
            }
        }
    }

    private var weatherMedicationSection: some View {
        todaySection("天气与用药关注") {
            if weatherMedicationService.isLoading && weatherMedicationService.hints.isEmpty {
                ProgressView("正在读取今日天气")
            }
            ForEach(visibleWeatherMedicationHints) { hint in
                WeatherMedicationHintCard(hint: hint)
            }
            if weatherMedicationService.shouldShowAuthorizationButton {
                Button {
                    startWeatherPermissionFlow()
                } label: {
                    Label("允许天气提醒", systemImage: "location.fill")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            if !weatherMedicationService.statusText.isEmpty {
                Text(weatherMedicationService.statusText)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var visibleWeatherMedicationHints: [WeatherMedicationHint] {
        weatherMedicationService.hints.filter(\.isActionableForToday)
    }

    private var shouldShowWeatherMedicationSection: Bool {
        weatherMedicationService.isLoading
            || weatherMedicationService.shouldShowAuthorizationButton
            || !visibleWeatherMedicationHints.isEmpty
    }

    var body: some View {
        let renderNow = Date()
        let snapshot = renderSnapshotCache.value(for: todayRenderRevision(now: renderNow)) {
            makeTodayRenderSnapshot(now: renderNow)
        }

        ZStack(alignment: .top) {
            VStack(spacing: 0) {
                completionRateFeedbackSlot

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 22) {
                        if snapshot.completionRateSnapshot.isComplete && shouldShowCompletionCelebrationCard {
                            CompletionCompleteCelebrationCard(
                                snapshot: snapshot.completionRateSnapshot,
                                reduceMotion: prefersReducedAppMotion
                            )
                            .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .top)))
                            .animation(.snappy(duration: 0.28, extraBounce: 0.03), value: snapshot.completionRateSnapshot)
                        }

                        notificationUnavailableBanner

                        openTimelineSection(snapshot: snapshot)

                        if snapshot.shouldShowHandledSection {
                            handledTimelineSection(snapshot: snapshot)
                        }

                        archivedTimelineSection(snapshot: snapshot)
                        nextReminderSection(snapshot: snapshot)
                        if shouldShowWeatherMedicationSection {
                            weatherMedicationSection
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    .padding(.bottom, 180)
                    .background(alignment: .top) {
                        AppTopGradientScrollReader(tab: .today, coordinateSpaceName: "TodayTopGradientScroll")
                    }
                }
                .coordinateSpace(name: "TodayTopGradientScroll")
                .background(Color(.systemGroupedBackground))
            }

            if let currentDoseUndoBanner = doseUndoBanner {
                VStack {
                    Spacer(minLength: 0)
                    DoseUndoBannerView(
                        banner: currentDoseUndoBanner,
                        undoRollback: { rollbackDoseUndo(currentDoseUndoBanner) }
                    )
                    .padding(.horizontal, 16)
                    .padding(.bottom, 10)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                .zIndex(5)
                .allowsHitTesting(true)
            }
        }
        .navigationTitle("今日")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingHelpCenter = true
                } label: {
                    Image(systemName: "questionmark.circle")
                        .accessibilityLabel("使用帮助")
                }
            }
        }
        .sheet(isPresented: $showingHelpCenter) {
            HelpCenterView()
        }
        .appPermissionPrimer(pendingGate: $pendingPermissionGate) { gate in
            guard gate == .location else {
                return
            }
            Task {
                let granted = await weatherMedicationService.refresh(medications: medications, requestAuthorization: true)
                if granted {
                    AppPermissionGate.markAuthorizationCompleted(for: .location)
                }
            }
        }
        .task(id: weatherMedicationSignature) {
            await weatherMedicationService.refresh(medications: medications)
        }
        .task {
            consumeExternalDosePersistenceFailure()
            runInitialTodayMaintenanceIfNeeded()
            await notificationService.refreshAuthorizationStatus()
            await notificationService.refreshPendingReminderCount()
        }
        .onReceive(liveActivityRefreshTimer) { _ in
            settleOverdueTasksIfNeeded()
            Task {
                await refreshLiveActivities()
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else {
                return
            }
            consumeExternalDosePersistenceFailure()
            settleOverdueTasksIfNeeded()
            scheduleLiveActivityRefresh()
            Task {
                await notificationService.refreshAuthorizationStatus()
                await notificationService.refreshPendingReminderCount()
            }
        }
        .confirmationDialog("归档这条今日记录？", isPresented: $showingArchiveConfirmation) {
            Button("归档记录", role: .destructive) {
                if let task = taskPendingArchive {
                    archive(task)
                    taskPendingArchive = nil
                }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("\(taskPendingArchive.flatMap { medication(for: $0).map(userFacingMedicationName(for:)) } ?? "这条记录") 会从今日已处理列表隐藏，但仍保留在服药历史中。")
        }
        .alert(
            "用药记录未保存",
            isPresented: Binding(
                get: { dosePersistenceErrorMessage != nil },
                set: { isPresented in
                    if !isPresented {
                        dosePersistenceErrorMessage = nil
                    }
                }
            )
        ) {
            Button("好", role: .cancel) {
                dosePersistenceErrorMessage = nil
            }
        } message: {
            Text(dosePersistenceErrorMessage ?? DoseActionPersistenceError.saveFailed.userMessage)
        }
        .onDisappear {
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

    private func isMedicationActiveForToday(_ task: StoredDoseTask) -> Bool {
        guard let medication = medication(for: task) else {
            return false
        }
        return medication.lifecycleStatus == .active
    }

    private func deduplicatedTodayTasks(_ tasks: [StoredDoseTask]) -> [StoredDoseTask] {
        var tasksByLogicalDose: [String: StoredDoseTask] = [:]
        for task in tasks {
            let key = logicalDoseKey(for: task)
            if let current = tasksByLogicalDose[key] {
                tasksByLogicalDose[key] = preferredDisplayTask(current, task)
            } else {
                tasksByLogicalDose[key] = task
            }
        }
        return tasksByLogicalDose.values.sorted { lhs, rhs in
            if lhs.dueAt == rhs.dueAt {
                return lhs.id.uuidString < rhs.id.uuidString
            }
            return lhs.dueAt < rhs.dueAt
        }
    }

    private func logicalDoseKey(for task: StoredDoseTask) -> String {
        DoseLogicalGroup.key(for: task)
    }

    private func logicalDoseGroup(for task: StoredDoseTask) -> [StoredDoseTask] {
        DoseLogicalGroup.group(containing: task, in: tasks)
    }

    private func preferredDisplayTask(_ lhs: StoredDoseTask, _ rhs: StoredDoseTask) -> StoredDoseTask {
        let lhsScore = displayPriorityScore(for: lhs)
        let rhsScore = displayPriorityScore(for: rhs)
        if lhsScore != rhsScore {
            return lhsScore > rhsScore ? lhs : rhs
        }
        let lhsReferenceDate = lhs.effectiveAdherenceDate
        let rhsReferenceDate = rhs.effectiveAdherenceDate
        if lhsReferenceDate != rhsReferenceDate {
            return lhsReferenceDate > rhsReferenceDate ? lhs : rhs
        }
        return lhs.id.uuidString < rhs.id.uuidString ? lhs : rhs
    }

    private func displayPriorityScore(for task: StoredDoseTask) -> Int {
        var score = 0
        if recentlyReopenedDoseKeys.contains(logicalDoseKey(for: task)) {
            score += 1_000
        }
        if pendingDoseFeedback?.doseKey == logicalDoseKey(for: task) {
            score += 900
        }
        if task.recordedAt != nil {
            score += 120
        }
        switch task.status {
        case .taken, .corrected:
            score += 500
        case .skipped:
            score += 480
        case .delayed:
            score += 360
        case .pending:
            score += 300
        }
        return score
    }

    private func isOpenStatus(_ status: StoredDoseStatus) -> Bool {
        status == .pending || status == .delayed
    }

    @discardableResult
    private func mark(_ task: StoredDoseTask, mutation: DoseActionMutation, reason: String) -> Bool {
        let occurredAt = Date()
        let group = logicalDoseGroup(for: task)
        let previousCompletionSnapshot = currentCompletionRateSnapshot
        let nextCompletionSnapshot = completionRateSnapshot(replacing: task, with: mutation.newStatus)
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

    private func unarchivedReason(_ reason: String) -> String {
        reason
            .split(separator: "；")
            .map(String.init)
            .filter { $0 != "用户已归档" }
            .joined(separator: "；")
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

    private func completionRateSnapshot(replacing task: StoredDoseTask, with status: StoredDoseStatus) -> CompletionRateSnapshot {
        let targetDoseKey = logicalDoseKey(for: task)
        let completedCount = displayTodayTasks.reduce(into: 0) { count, currentTask in
            let effectiveStatus = logicalDoseKey(for: currentTask) == targetDoseKey ? status : currentTask.status
            if isCompletionStatus(effectiveStatus) {
                count += 1
            }
        }
        return CompletionRateSnapshot(
            completedCount: completedCount,
            totalCount: displayTodayTasks.count
        )
    }

    private func isCompletionStatus(_ status: StoredDoseStatus) -> Bool {
        status == .taken || status == .corrected
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

    private func statusText(for task: StoredDoseTask) -> String {
        switch task.status {
        case .taken, .corrected:
            return completionVerb(for: medication(for: task))
        case .skipped:
            return "已忽略"
        case .pending:
            return task.status.displayName
        case .delayed:
            return "\(delayDurationText)后"
        }
    }

    private func doseMigrationSnapshot(for task: StoredDoseTask, action: PendingDoseFeedback.Action) -> DoseMigrationSnapshot {
        let medication = medication(for: task)
        let statusText: String
        switch action {
        case .taken:
            statusText = completionVerb(for: medication)
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

    private func handledTaskSummary(for task: StoredDoseTask) -> String {
        let name = medication(for: task).map(userFacingMedicationName(for:)) ?? "用药记录"
        return "\(statusText(for: task)) · \(name)"
    }

    private var skippedMedicationSummary: String {
        skippedTodayTasks
            .map { medication(for: $0).map(userFacingMedicationName(for:)) ?? "未知药品" }
            .joined(separator: "、")
    }

    private func completionVerb(for medication: StoredMedication?) -> String {
        guard let medication else {
            return "已完成"
        }
        let combined = "\(medication.displayName) \(medication.form)".lowercased()
        if combined.contains("tear") || combined.contains("drop") || combined.contains("滴") || combined.contains("眼") || combined.contains("喷") || combined.contains("贴") || combined.contains("膏") {
            return "已使用"
        }
        return "已服用"
    }

    private func refreshLiveActivities() async {
        for task in todayTasks {
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

    private func openSystemNotificationSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else {
            return
        }
        UIApplication.shared.open(url)
    }
}
