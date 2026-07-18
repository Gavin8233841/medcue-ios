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

    private func makeTodayRenderSnapshot() -> TodayRenderSnapshot {
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
        let now = Date()
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
                                mark(task, as: .skipped, action: .skip, reason: "用户忽略")
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
        let snapshot = makeTodayRenderSnapshot()

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

    private func mark(_ task: StoredDoseTask, as status: StoredDoseStatus, action: DoseActionKind, reason: String) {
        let occurredAt = Date()
        let group = logicalDoseGroup(for: task)
        let previousCompletionSnapshot = currentCompletionRateSnapshot
        let nextCompletionSnapshot = completionRateSnapshot(replacing: task, with: status)
        updateDoseState {
            for groupTask in group {
                let taskReason = groupTask.id == task.id ? reason : "同一剂量重复提醒已随本次操作合并。"
                let log = StoredDoseActionLog(
                    taskID: groupTask.id,
                    action: action,
                    previousStatus: groupTask.status,
                    previousDueAt: groupTask.dueAt,
                    previousRecordedAt: groupTask.recordedAt,
                    previousReason: groupTask.reason,
                    newStatus: status,
                    occurredAt: occurredAt,
                    undoExpiresAt: occurredAt.addingTimeInterval(10 * 60),
                    note: taskReason
                )
                modelContext.insert(log)
                groupTask.status = status
                groupTask.recordedAt = occurredAt
                groupTask.reason = taskReason
            }
            try? modelContext.save()
        }
        presentCompletionRateFeedbackIfNeeded(from: previousCompletionSnapshot, to: nextCompletionSnapshot)
        performDeferredSystemSurfaceSync {
            for groupTask in group {
                notificationService.cancelReminder(for: groupTask.id)
                await liveActivityService.end(for: groupTask.id)
            }
            scheduleLiveActivityRefresh(after: 0.35)
        }
    }

    private func delay(_ task: StoredDoseTask, fromPlannedTime: Bool = false) {
        let occurredAt = Date()
        let newDueAt = DoseDelayPolicy.delayedDueAtFromPlannedTime(task.dueAt)
        let group = logicalDoseGroup(for: task)
        updateDoseState {
            for groupTask in group {
                let primaryReason = fromPlannedTime ? "用户确认按原计划时间顺延 \(delayDurationText)提醒" : "用户选择按原计划时间顺延 \(delayDurationText)提醒"
                let taskReason = groupTask.id == task.id ? primaryReason : "同一剂量重复提醒已随本次稍后操作合并。"
                let log = StoredDoseActionLog(
                    taskID: groupTask.id,
                    action: .delay,
                    previousStatus: groupTask.status,
                    previousDueAt: groupTask.dueAt,
                    previousRecordedAt: groupTask.recordedAt,
                    previousReason: groupTask.reason,
                    newStatus: .delayed,
                    occurredAt: occurredAt,
                    undoExpiresAt: occurredAt.addingTimeInterval(10 * 60),
                    note: taskReason
                )
                modelContext.insert(log)
                groupTask.status = .delayed
                groupTask.recordedAt = occurredAt
                groupTask.reason = taskReason
                groupTask.dueAt = newDueAt
            }
            try? modelContext.save()
        }
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
            mark(task, as: .taken, action: .markTaken, reason: reason)
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

    private func performWithDoseFeedback(_ task: StoredDoseTask, action: PendingDoseFeedback.Action, commit: @escaping () -> Void) {
        let doseKey = logicalDoseKey(for: task)
        let migrationSnapshot = action.movesToHandledSection ? doseMigrationSnapshot(for: task, action: action) : nil
        resetDoseTransitionState(animated: false)
        if !prefersReducedAppMotion {
            withAnimation(.easeInOut(duration: 0.16)) {
                pendingDoseFeedback = PendingDoseFeedback(doseKey: doseKey, action: action)
            }
        }

        commitWithoutListMutationAnimation(commit)
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

    private func latestUndoableLog(for task: StoredDoseTask) -> StoredDoseActionLog? {
        fetchedActionLogs(for: [task.id]).first { log in
            log.canUndo && !isArchiveVisibilityAction(log)
        }
    }

    private func isArchiveVisibilityAction(_ log: StoredDoseActionLog) -> Bool {
        log.actionRaw == DoseActionKind.archiveToday.rawValue || log.actionRaw == DoseActionKind.restoreArchive.rawValue
    }

    private func undoLatestAction(for task: StoredDoseTask) {
        guard let log = latestUndoableLog(for: task) else {
            return
        }
        restore(task, using: log)
    }

    private func undoOrReopen(_ task: StoredDoseTask) {
        if let log = latestUndoableLog(for: task) {
            restore(task, using: log)
        } else {
            reopen(task)
        }
    }

    private func restore(_ task: StoredDoseTask, using log: StoredDoseActionLog) {
        let group = logicalDoseGroup(for: task)
        let groupLogs = undoableLogsForLogicalDoseGroup(group, primaryLog: log)
        let rollbackSnapshots = doseStateSnapshots(for: group)
        let reactivatedActionLogIDs = sortedLogIDs(from: groupLogs.values.map(\.id))
        performReopenTransition(task) {
            let reopenedAt = Date()
            let previousCompletionSnapshot = currentCompletionRateSnapshot
            let nextCompletionSnapshot = completionRateSnapshot(replacing: task, with: log.previousStatus)
            prepareReopenedTaskHighlightIfNeeded(task)
            updateDoseState(animated: false) {
                for groupTask in group {
                    if let groupLog = groupLogs[groupTask.id] {
                        restore(groupTask, usingSnapshotFrom: groupLog, reopenedAt: reopenedAt)
                        groupLog.undoneAt = Date()
                    } else if groupTask.id == task.id {
                        restore(groupTask, usingSnapshotFrom: log, reopenedAt: reopenedAt)
                        log.undoneAt = Date()
                    }
                }
                try? modelContext.save()
            }
            presentCompletionRateFeedbackIfNeeded(from: previousCompletionSnapshot, to: nextCompletionSnapshot)
            showDoseUndoBanner(
                for: task,
                rollbackSnapshots: rollbackSnapshots,
                reactivatedActionLogIDs: reactivatedActionLogIDs,
                closedActionLogIDs: []
            )
            clearReopenedTaskHighlightAfterDelay(task)
            performDeferredSystemSurfaceSync {
                await synchronizeSystemSurfacesAfterReopen(for: group, primaryTaskID: task.id)
                scheduleLiveActivityRefresh(after: 0.35)
            }
        }
    }

    private func reopen(_ task: StoredDoseTask) {
        let group = logicalDoseGroup(for: task)
        let rollbackSnapshots = doseStateSnapshots(for: group)
        performReopenTransition(task) {
            let occurredAt = Date()
            let reopenLogs = group.map { groupTask in
                StoredDoseActionLog(
                    taskID: groupTask.id,
                    action: .correct,
                    previousStatus: groupTask.status,
                    previousDueAt: groupTask.dueAt,
                    previousRecordedAt: groupTask.recordedAt,
                    previousReason: groupTask.reason,
                    newStatus: .pending,
                    occurredAt: occurredAt,
                    undoExpiresAt: occurredAt.addingTimeInterval(10 * 60),
                    note: groupTask.id == task.id
                        ? "用户将已处理记录撤销为待处理"
                        : "同一剂量重复提醒已随本次撤销操作合并；用户将已处理记录撤销为待处理"
                )
            }
            let previousCompletionSnapshot = currentCompletionRateSnapshot
            let nextCompletionSnapshot = completionRateSnapshot(replacing: task, with: .pending)
            prepareReopenedTaskHighlightIfNeeded(task)
            updateDoseState(animated: false) {
                for log in reopenLogs {
                    modelContext.insert(log)
                }
                for groupTask in group {
                    groupTask.status = .pending
                    groupTask.recordedAt = nil
                    groupTask.reason = reopenedReason(previousReason: "", status: .pending, previousDueAt: groupTask.dueAt, reopenedAt: occurredAt)
                }
                try? modelContext.save()
            }
            presentCompletionRateFeedbackIfNeeded(from: previousCompletionSnapshot, to: nextCompletionSnapshot)
            showDoseUndoBanner(
                for: task,
                rollbackSnapshots: rollbackSnapshots,
                reactivatedActionLogIDs: [],
                closedActionLogIDs: reopenLogs.map(\.id)
            )
            clearReopenedTaskHighlightAfterDelay(task)
            performDeferredSystemSurfaceSync {
                await synchronizeSystemSurfacesAfterReopen(for: group, primaryTaskID: task.id)
                scheduleLiveActivityRefresh(after: 0.35)
            }
        }
    }

    private func undoableLogsForLogicalDoseGroup(
        _ group: [StoredDoseTask],
        primaryLog: StoredDoseActionLog
    ) -> [UUID: StoredDoseActionLog] {
        var logsByTaskID: [UUID: StoredDoseActionLog] = [primaryLog.taskID: primaryLog]
        for groupTask in group where logsByTaskID[groupTask.id] == nil {
            if let matchingLog = latestUndoableLog(for: groupTask),
               matchingLog.actionRaw == primaryLog.actionRaw,
               Calendar.current.isDate(matchingLog.previousDueAt, equalTo: primaryLog.previousDueAt, toGranularity: .minute) {
                logsByTaskID[groupTask.id] = matchingLog
            }
        }
        return logsByTaskID
    }

    private func restore(_ task: StoredDoseTask, usingSnapshotFrom log: StoredDoseActionLog, reopenedAt: Date) {
        task.status = log.previousStatus
        task.dueAt = log.previousDueAt
        task.recordedAt = log.previousRecordedAt
        task.reason = reopenedReason(previousReason: log.previousReason, status: log.previousStatus, previousDueAt: log.previousDueAt, reopenedAt: reopenedAt)
    }

    private func reopenedReason(previousReason: String, status: StoredDoseStatus, previousDueAt: Date, reopenedAt: Date) -> String {
        let baseReason = unarchivedReason(previousReason)
        guard isOpenStatus(status), previousDueAt.addingTimeInterval(reminderPolicy.autoSkipInterval) <= reopenedAt else {
            return baseReason
        }
        let reopenNote = "用户撤销后等待确认"
        if baseReason.isEmpty {
            return reopenNote
        }
        if baseReason.contains(reopenNote) {
            return baseReason
        }
        return [baseReason, reopenNote].joined(separator: "；")
    }

    private func doseStateSnapshots(for tasks: [StoredDoseTask]) -> [DoseTaskRollbackSnapshot] {
        tasks.map { task in
            DoseTaskRollbackSnapshot(
                taskID: task.id,
                snapshot: doseStateSnapshot(for: task)
            )
        }
    }

    private func doseStateSnapshot(for task: StoredDoseTask) -> DoseStateSnapshot {
        DoseStateSnapshot(
            status: task.status,
            dueAt: task.dueAt,
            recordedAt: task.recordedAt,
            reason: task.reason
        )
    }

    private func showDoseUndoBanner(
        for task: StoredDoseTask,
        rollbackSnapshots: [DoseTaskRollbackSnapshot],
        reactivatedActionLogIDs: [UUID],
        closedActionLogIDs: [UUID]
    ) {
        doseUndoBannerTask?.cancel()
        isDoseUndoRollbackInFlight = false
        let medicationName = medication(for: task).map(userFacingMedicationName(for:)) ?? "这条记录"
        let banner = DoseUndoBanner(
            taskID: task.id,
            medicationName: medicationName,
            rollbackSnapshots: rollbackSnapshots,
            reactivatedActionLogIDs: sortedLogIDs(from: reactivatedActionLogIDs),
            closedActionLogIDs: sortedLogIDs(from: closedActionLogIDs)
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
        let currentTasks = fetchedDoseTasks()
        let currentActionLogs = fetchedActionLogs()
        var rollbackPairsByTaskID: [UUID: (StoredDoseTask, DoseTaskRollbackSnapshot)] = [:]
        for rollback in banner.rollbackSnapshots {
            guard let task = currentTasks.first(where: { $0.id == rollback.taskID }) else {
                continue
            }
            rollbackPairsByTaskID[task.id] = (task, rollback)
        }
        if let primaryTask = currentTasks.first(where: { $0.id == banner.taskID }),
           let fallbackRollback = banner.rollbackSnapshots.first(where: { $0.taskID == banner.taskID }) ?? banner.rollbackSnapshots.first {
            for groupTask in DoseLogicalGroup.group(containing: primaryTask, in: currentTasks) where rollbackPairsByTaskID[groupTask.id] == nil {
                rollbackPairsByTaskID[groupTask.id] = (
                    groupTask,
                    DoseTaskRollbackSnapshot(taskID: groupTask.id, snapshot: fallbackRollback.snapshot)
                )
            }
        }
        var rollbackTaskIDs = Set(rollbackPairsByTaskID.keys)
        if rollbackTaskIDs.isEmpty {
            rollbackTaskIDs = [banner.taskID]
        }
        let reactivatedLogs = logsToReactivate(
            for: banner,
            rollbackTaskIDs: rollbackTaskIDs,
            actionLogs: currentActionLogs
        )
        if rollbackPairsByTaskID.isEmpty {
            for log in reactivatedLogs {
                guard let task = currentTasks.first(where: { $0.id == log.taskID }),
                      let newStatus = StoredDoseStatus(rawValue: log.newStatusRaw)
                else {
                    continue
                }
                rollbackPairsByTaskID[task.id] = (
                    task,
                    DoseTaskRollbackSnapshot(
                        taskID: task.id,
                        snapshot: DoseStateSnapshot(
                            status: newStatus,
                            dueAt: task.dueAt,
                            recordedAt: log.occurredAt,
                            reason: log.note
                        )
                    )
                )
            }
        }
        let rollbackPairs = rollbackPairsByTaskID.values.sorted { lhs, rhs in
            lhs.0.id.uuidString < rhs.0.id.uuidString
        }
        guard !rollbackPairs.isEmpty else {
            dismissDoseUndoBanner()
            return
        }
        let previousCompletionSnapshot = currentCompletionRateSnapshot
        updateDoseState(animated: false) {
            for (task, rollback) in rollbackPairs {
                task.status = rollback.snapshot.status
                task.dueAt = rollback.snapshot.dueAt
                task.recordedAt = rollback.snapshot.recordedAt
                task.reason = rollback.snapshot.reason
            }
            for log in reactivatedLogs {
                log.undoneAt = nil
                if let task = currentTasks.first(where: { $0.id == log.taskID }) {
                    reapplyTodayActionState(from: log, to: task)
                }
            }
            for logID in banner.closedActionLogIDs {
                guard let log = currentActionLogs.first(where: { $0.id == logID }) else {
                    continue
                }
                log.undoneAt = Date()
            }
            try? modelContext.save()
        }
        let nextCompletionSnapshot = currentCompletionRateSnapshot
        presentCompletionRateFeedbackIfNeeded(from: previousCompletionSnapshot, to: nextCompletionSnapshot)
        withAnimation(.easeOut(duration: 0.18)) {
            for (task, _) in rollbackPairs {
                let doseKey = logicalDoseKey(for: task)
                _ = recentlyReopenedDoseKeys.remove(doseKey)
                _ = reopeningHandledDoseKeys.remove(doseKey)
            }
        }
        performDeferredSystemSurfaceSync {
            for (task, _) in rollbackPairs {
                await synchronizeSystemSurfacesAfterRollback(for: task, primaryTaskID: banner.taskID)
            }
            scheduleLiveActivityRefresh(after: 0.35)
        }
        dismissDoseUndoBanner()
    }

    private func fetchedDoseTasks() -> [StoredDoseTask] {
        do {
            return try modelContext.fetch(FetchDescriptor<StoredDoseTask>())
        } catch {
            return tasks
        }
    }

    private func fetchedActionLogs() -> [StoredDoseActionLog] {
        do {
            return try modelContext.fetch(FetchDescriptor<StoredDoseActionLog>())
        } catch {
            return []
        }
    }

    private func fetchedActionLogs(for taskIDs: Set<UUID>) -> [StoredDoseActionLog] {
        guard !taskIDs.isEmpty else {
            return []
        }
        do {
            let descriptor = FetchDescriptor<StoredDoseActionLog>(
                predicate: #Predicate<StoredDoseActionLog> { log in
                    taskIDs.contains(log.taskID)
                },
                sortBy: [SortDescriptor(\.occurredAt, order: .reverse)]
            )
            return try modelContext.fetch(descriptor)
        } catch {
            return []
        }
    }

    private func logsToReactivate(
        for banner: DoseUndoBanner,
        rollbackTaskIDs: Set<UUID>,
        actionLogs: [StoredDoseActionLog]
    ) -> [StoredDoseActionLog] {
        var logsByID: [UUID: StoredDoseActionLog] = [:]
        for logID in banner.reactivatedActionLogIDs {
            guard let log = actionLogs.first(where: { $0.id == logID }) else {
                continue
            }
            logsByID[log.id] = log
        }

        let recentUndoCutoff = Date().addingTimeInterval(-120)
        var coveredTaskIDs = Set(logsByID.values.map(\.taskID))
        let fallbackLogs = actionLogs
            .filter { log in
                rollbackTaskIDs.contains(log.taskID)
                    && log.undoneAt.map { $0 >= recentUndoCutoff } == true
                    && shouldReapplyTodayActionState(from: log)
            }
            .sorted { lhs, rhs in
                if lhs.occurredAt == rhs.occurredAt {
                    return lhs.id.uuidString < rhs.id.uuidString
                }
                return lhs.occurredAt > rhs.occurredAt
            }
        for log in fallbackLogs where !coveredTaskIDs.contains(log.taskID) {
            logsByID[log.id] = log
            coveredTaskIDs.insert(log.taskID)
        }
        return logsByID.values.sorted { lhs, rhs in
            if lhs.occurredAt == rhs.occurredAt {
                return lhs.id.uuidString < rhs.id.uuidString
            }
            return lhs.occurredAt > rhs.occurredAt
        }
    }

    private func shouldReapplyTodayActionState(from log: StoredDoseActionLog) -> Bool {
        log.actionRaw == DoseActionKind.markTaken.rawValue
            || log.actionRaw == DoseActionKind.delay.rawValue
            || log.actionRaw == DoseActionKind.skip.rawValue
    }

    private func reapplyTodayActionState(from log: StoredDoseActionLog) {
        guard let task = tasks.first(where: { $0.id == log.taskID }) else {
            return
        }
        reapplyTodayActionState(from: log, to: task)
    }

    private func reapplyTodayActionState(from log: StoredDoseActionLog, to task: StoredDoseTask) {
        guard let newStatus = StoredDoseStatus(rawValue: log.newStatusRaw),
              shouldReapplyTodayActionState(from: log)
        else {
            return
        }
        task.status = newStatus
        task.recordedAt = log.occurredAt
        task.reason = log.note
    }

    private func sortedLogIDs(from ids: some Sequence<UUID>) -> [UUID] {
        Array(Set(ids)).sorted { $0.uuidString < $1.uuidString }
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
        let occurredAt = Date()
        let archiveNote = "用户已归档"
        let log = StoredDoseActionLog(
            taskID: task.id,
            action: .archiveToday,
            previousStatus: task.status,
            previousDueAt: task.dueAt,
            previousRecordedAt: task.recordedAt,
            previousReason: task.reason,
            newStatus: task.status,
            occurredAt: occurredAt,
            undoExpiresAt: occurredAt,
            note: "用户将今日记录归档隐藏"
        )
        modelContext.insert(log)
        updateDoseState {
            task.reason = [task.reason, archiveNote].filter { !$0.isEmpty }.joined(separator: "；")
            try? modelContext.save()
        }
        performDeferredSystemSurfaceSync {
            await liveActivityService.end(for: task.id)
            scheduleLiveActivityRefresh(after: 0.35)
        }
    }

    private func unarchive(_ task: StoredDoseTask) {
        guard isArchived(task) else {
            return
        }
        let occurredAt = Date()
        let log = StoredDoseActionLog(
            taskID: task.id,
            action: .restoreArchive,
            previousStatus: task.status,
            previousDueAt: task.dueAt,
            previousRecordedAt: task.recordedAt,
            previousReason: task.reason,
            newStatus: task.status,
            occurredAt: occurredAt,
            undoExpiresAt: occurredAt,
            note: "用户恢复今日归档记录"
        )
        modelContext.insert(log)
        updateDoseState {
            task.reason = unarchivedReason(task.reason)
            try? modelContext.save()
        }
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

@MainActor
private enum TodayPerformanceGate {
    private static var lastOverdueSettlementAt: Date?
    private static let minimumOverdueSettlementInterval: TimeInterval = 45

    static func shouldRunOverdueSettlement(now: Date, force: Bool) -> Bool {
        if force {
            lastOverdueSettlementAt = now
            return true
        }
        guard let lastOverdueSettlementAt else {
            self.lastOverdueSettlementAt = now
            return true
        }
        guard now.timeIntervalSince(lastOverdueSettlementAt) >= minimumOverdueSettlementInterval else {
            return false
        }
        self.lastOverdueSettlementAt = now
        return true
    }
}

private struct PendingDoseFeedback: Equatable {
    enum Action: Equatable {
        case taken
        case delay
        case skip

        var movesToHandledSection: Bool {
            switch self {
            case .taken, .skip:
                return true
            case .delay:
                return false
            }
        }

        var targetStatus: StoredDoseStatus {
            switch self {
            case .taken:
                return .taken
            case .delay:
                return .delayed
            case .skip:
                return .skipped
            }
        }
    }

    let doseKey: String
    let action: Action
}

private struct PendingDoseConfirmation: Equatable {
    enum Kind: Equatable {
        case earlyTaken
        case plannedDelay

        var iconName: String {
            switch self {
            case .earlyTaken:
                return "exclamationmark.triangle.fill"
            case .plannedDelay:
                return "clock.arrow.circlepath"
            }
        }

        var title: String {
            switch self {
            case .earlyTaken:
                return "确认提前服用？"
            case .plannedDelay:
                return "按原计划顺延？"
            }
        }

        func message(delayDurationText: String) -> String {
            switch self {
            case .earlyTaken:
                return "距离计划时间较久。请确认已按医嘱、说明书或医生或药师建议服用。"
            case .plannedDelay:
                return "当前离计划时间较久。继续稍后会按原计划时间顺延 \(delayDurationText)，避免打乱今日时间线。"
            }
        }

        var confirmTitle: String {
            switch self {
            case .earlyTaken:
                return "确认已服用"
            case .plannedDelay:
                return "确认稍后"
            }
        }

        var tint: Color {
            switch self {
            case .earlyTaken:
                return .orange
            case .plannedDelay:
                return .blue
            }
        }
    }

    let doseKey: String
    let kind: Kind
}

private struct TodayRenderSnapshot {
    let visibleOpenTimelineTasks: [StoredDoseTask]
    let handledTodayTasks: [StoredDoseTask]
    let archivedTodayTasks: [StoredDoseTask]
    let nextReminderTask: StoredDoseTask?
    let overdueOpenTaskCount: Int
    let emptyOpenTimelineMessage: String
    let shouldShowSkippedMedicationSummary: Bool
    let shouldShowHandledSection: Bool
    let displayedOpenCount: Int
    let displayedHandledCount: Int
    let handledSummaryText: String
    let skippedMedicationSummary: String
    let completionRateSnapshot: CompletionRateSnapshot
}

private struct DoseMigrationSnapshot: Identifiable, Equatable {
    enum Direction: Equatable {
        case toHandled
        case toOpen
    }

    let id: UUID
    let medicationName: String
    let doseText: String
    let timeText: String
    let symbolName: String
    let statusText: String
    let direction: Direction
}

private struct DoseStateSnapshot: Equatable {
    let status: StoredDoseStatus
    let dueAt: Date
    let recordedAt: Date?
    let reason: String
}

private struct DoseTaskRollbackSnapshot: Equatable {
    let taskID: UUID
    let snapshot: DoseStateSnapshot
}

private struct DoseUndoBanner: Identifiable, Equatable {
    let id = UUID()
    let taskID: UUID
    let medicationName: String
    let rollbackSnapshots: [DoseTaskRollbackSnapshot]
    let reactivatedActionLogIDs: [UUID]
    let closedActionLogIDs: [UUID]
}

private struct DoseUndoBannerView: View {
    let banner: DoseUndoBanner
    let undoRollback: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "arrow.uturn.backward.circle.fill")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.blue)
                .frame(width: 32, height: 32)
                .background(.blue.opacity(0.12), in: Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text("已恢复到待处理")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(banner.medicationName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Button(action: undoRollback) {
                Text("撤回")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.blue)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.blue.opacity(0.10), in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .medicationGlassSurface(cornerRadius: 16, tint: .blue, fallbackMaterial: .ultraThinMaterial, isInteractive: true)
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(.blue.opacity(0.18), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.14), radius: 18, x: 0, y: 8)
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .onTapGesture(perform: undoRollback)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel("已恢复到待处理，\(banner.medicationName)，撤回")
        .accessibilityAction(named: Text("撤回"), undoRollback)
    }
}

private struct CompletionRateSnapshot: Equatable {
    let completedCount: Int
    let totalCount: Int

    var progressValue: Double {
        guard totalCount > 0 else {
            return 0
        }
        return Double(completedCount) / Double(totalCount)
    }

    var percentValue: Int {
        Int((progressValue * 100).rounded())
    }

    var percentText: String {
        "\(percentValue)%"
    }

    var isComplete: Bool {
        totalCount > 0 && completedCount == totalCount
    }

    func affectsCompletionRate(comparedWith other: CompletionRateSnapshot) -> Bool {
        completedCount != other.completedCount || totalCount != other.totalCount
    }
}

private struct CompletionRateFeedback: Identifiable, Equatable {
    let id = UUID()
    let previousSnapshot: CompletionRateSnapshot
    let nextSnapshot: CompletionRateSnapshot

    func title(for snapshot: CompletionRateSnapshot) -> String {
        snapshot.isComplete ? "今日用药已完成" : "今日完成率更新"
    }

    var subtitle: String {
        if nextSnapshot.completedCount > previousSnapshot.completedCount {
            return "刚刚完成 1 项记录"
        }
        if nextSnapshot.completedCount < previousSnapshot.completedCount {
            return "已撤销 1 条完成记录"
        }
        return "今日记录已更新"
    }

    var tint: Color {
        nextSnapshot.isComplete ? .green : .blue
    }
}

private struct CompletionRateFeedbackPanel: View {
    let feedback: CompletionRateFeedback
    let displayedSnapshot: CompletionRateSnapshot
    let isVisible: Bool
    @State private var sweepOffset: CGFloat = -1

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: displayedSnapshot.isComplete ? "checkmark.seal.fill" : "chart.line.uptrend.xyaxis")
                .font(.headline.weight(.semibold))
                .foregroundStyle(feedback.tint)
                .frame(width: 28, height: 28)
                .background(feedback.tint.opacity(0.14), in: Circle())

            VStack(alignment: .leading, spacing: 7) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(feedback.title(for: displayedSnapshot))
                        .font(.subheadline.weight(.semibold))
                        .contentTransition(.opacity)

                    Text(feedback.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    Spacer(minLength: 8)

                    Text(displayedSnapshot.percentText)
                        .font(.headline.weight(.bold))
                        .monospacedDigit()
                        .foregroundStyle(feedback.tint)
                        .contentTransition(.numericText(value: Double(displayedSnapshot.percentValue)))
                }

                ProgressView(value: displayedSnapshot.progressValue)
                    .tint(feedback.tint)
                    .accessibilityLabel("今日完成率")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .modifier(CompletionRateGlassSurface(tint: feedback.tint))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(feedback.tint.opacity(0.22), lineWidth: 1)
        }
        .overlay(alignment: .leading) {
            GeometryReader { proxy in
                LinearGradient(
                    colors: [.clear, feedback.tint.opacity(0.20), .white.opacity(0.22), .clear],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(width: 72)
                .offset(x: sweepOffset * (proxy.size.width + 72) - 72)
                .blendMode(.plusLighter)
                .allowsHitTesting(false)
            }
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .shadow(color: feedback.tint.opacity(0.14), radius: 16, x: 0, y: 8)
        .offset(y: isVisible ? 0 : -20)
        .scaleEffect(isVisible ? 1 : 0.985, anchor: .top)
        .opacity(isVisible ? 1 : 0)
        .accessibilityElement(children: .combine)
        .onAppear {
            runSweep()
        }
        .onChange(of: displayedSnapshot) { _, _ in
            runSweep()
        }
    }

    private func runSweep() {
        sweepOffset = -1
        withAnimation(.easeOut(duration: 0.42)) {
            sweepOffset = 1
        }
    }
}

private struct CompletionRateGlassSurface: ViewModifier {
    let tint: Color

    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
                .background {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(tint.opacity(0.07))
                }
                .glassEffect(.regular.tint(tint.opacity(0.12)), in: .rect(cornerRadius: 18))
        } else {
            content
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
    }
}

private struct CompletionCompleteCelebrationCard: View {
    let snapshot: CompletionRateSnapshot
    let reduceMotion: Bool
    @State private var isCelebrating = false
    @State private var sweepOffset: CGFloat = -1

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            ZStack {
                Circle()
                    .fill(.green.opacity(0.14))
                    .frame(width: 48, height: 48)

                if !reduceMotion {
                    Circle()
                        .stroke(.green.opacity(isCelebrating ? 0 : 0.22), lineWidth: 8)
                        .frame(width: isCelebrating ? 72 : 48, height: isCelebrating ? 72 : 48)
                        .opacity(isCelebrating ? 0 : 1)
                }

                Image(systemName: "checkmark.seal.fill")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.green)
                    .scaleEffect(isCelebrating && !reduceMotion ? 1.06 : 1)
            }
            .frame(width: 54, height: 54)

            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("今日用药已完成")
                        .font(.headline.weight(.semibold))
                    Spacer(minLength: 8)
                    Text(snapshot.percentText)
                        .font(.title2.weight(.bold))
                        .monospacedDigit()
                        .foregroundStyle(.green)
                        .contentTransition(.numericText(value: Double(snapshot.percentValue)))
                }

                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(.green.opacity(0.13))
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [.green.opacity(0.78), .mint.opacity(0.88), .green],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: proxy.size.width)
                    }
                }
                .frame(height: 8)
                .accessibilityLabel("今日完成率")
                .accessibilityValue(snapshot.percentText)

                Text("已完成 \(snapshot.completedCount) / \(snapshot.totalCount) 项记录")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.green.opacity(0.16),
                            Color.mint.opacity(0.10),
                            Color(.secondarySystemGroupedBackground)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(.green.opacity(0.20), lineWidth: 1)
        }
        .overlay(alignment: .leading) {
            if !reduceMotion {
                GeometryReader { proxy in
                    LinearGradient(
                        colors: [.clear, .white.opacity(0.38), .green.opacity(0.16), .clear],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: 78)
                    .offset(x: sweepOffset * (proxy.size.width + 78) - 78)
                    .blendMode(.plusLighter)
                    .allowsHitTesting(false)
                }
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
        }
        .shadow(color: .green.opacity(isCelebrating && !reduceMotion ? 0.20 : 0.10), radius: isCelebrating && !reduceMotion ? 18 : 10, x: 0, y: 8)
        .accessibilityElement(children: .combine)
        .onAppear {
            runCelebration()
        }
        .onChange(of: snapshot) { _, _ in
            runCelebration()
        }
    }

    private func runCelebration() {
        guard !reduceMotion else {
            isCelebrating = false
            sweepOffset = 1
            return
        }
        isCelebrating = false
        sweepOffset = -1
        withAnimation(.interpolatingSpring(mass: 0.72, stiffness: 170, damping: 16, initialVelocity: 0.12)) {
            isCelebrating = true
        }
        withAnimation(.easeOut(duration: 0.86).delay(0.10)) {
            sweepOffset = 1
        }
    }
}
private struct WeatherMedicationHintCard: View {
    let hint: WeatherMedicationHint

    private var tint: Color {
        switch hint.tintName {
        case "orange":
            .orange
        case "teal":
            .teal
        case "indigo":
            .indigo
        case "yellow":
            .yellow
        case "green":
            .green
        default:
            .blue
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: hint.iconName)
                .font(.title3.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 32, height: 32)
                .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 6) {
                Text(hint.title)
                    .font(.headline)
                Text(hint.message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(hint.sourceSummary)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 6)
    }
}

private struct TimelineDoseTaskRow: View {
    let task: StoredDoseTask
    let medication: StoredMedication?
    let completionText: String
    let statusText: String
    let isOpen: Bool
    let feedbackAction: PendingDoseFeedback.Action?
    let isClosing: Bool
    let isRecentlyReopened: Bool
    let confirmationKind: PendingDoseConfirmation.Kind?
    let markTaken: () -> Void
    let delay: () -> Void
    let skip: () -> Void
    let confirm: () -> Void
    let cancelConfirmation: () -> Void

    private var tint: Color {
        switch task.status {
        case .taken, .corrected:
            .green
        case .skipped:
            .orange
        case .delayed:
            .blue
        case .pending:
            .blue
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            timeRail
            VStack(alignment: .leading, spacing: 10) {
                if let medication {
                    NavigationLink {
                        MedicationDetailView(medication: medication)
                    } label: {
                        rowHeader
                    }
                    .buttonStyle(.plain)
                } else {
                    rowHeader
                }

                if isOpen {
                    HStack(spacing: 8) {
                        CompactDoseActionButton(
                            title: completionText,
                            confirmationIconName: "checkmark",
                            tint: TodayDoseActionPalette.primary,
                            isProminent: true,
                            isConfirming: feedbackAction == .taken,
                            action: markTaken
                        )
                        .id("\(task.id.uuidString)-taken")
                        CompactDoseActionButton(
                            title: "稍后",
                            confirmationIconName: "clock",
                            tint: .gray,
                            isProminent: false,
                            isConfirming: feedbackAction == .delay,
                            action: delay
                        )
                        .id("\(task.id.uuidString)-delay")
                        CompactDoseActionButton(
                            title: "忽略",
                            confirmationIconName: "minus.circle",
                            tint: .orange,
                            isProminent: false,
                            isConfirming: feedbackAction == .skip,
                            action: skip
                        )
                        .id("\(task.id.uuidString)-skip")
                    }
                    .padding(.leading, 50)
                    if let confirmationKind {
                        InlineDoseConfirmationCard(
                            kind: confirmationKind,
                            delayDurationText: "\(DoseDelayPolicy.delayMinutes) 分钟",
                            confirm: confirm,
                            cancel: cancelConfirmation
                        )
                        .transition(.asymmetric(
                            insertion: .opacity
                                .combined(with: .move(edge: .top))
                                .combined(with: .scale(scale: 0.98, anchor: .top)),
                            removal: .opacity
                                .combined(with: .scale(scale: 0.98, anchor: .top))
                        ))
                        .padding(.leading, 50)
                    }
                }
            }
            .padding(12)
            .background(rowBackground, in: RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(rowBorder, lineWidth: isRecentlyReopened ? 1.2 : 0.8)
            )
            .shadow(color: Color.black.opacity(isOpen ? 0.045 : 0.025), radius: isOpen ? 7 : 4, x: 0, y: 3)
            .opacity(isClosing ? 0.08 : (isRecentlyReopened ? 0.96 : 1))
            .blur(radius: isClosing ? 4 : 0)
            .scaleEffect(isClosing ? 0.96 : 1)
            .offset(y: isClosing ? 14 : (isRecentlyReopened ? -2 : 0))
            .animation(.snappy(duration: 0.26, extraBounce: 0.03), value: isRecentlyReopened)
            .animation(.easeInOut(duration: 0.18), value: isClosing)
            .animation(.snappy(duration: 0.22, extraBounce: 0.02), value: confirmationKind)
        }
        .padding(.vertical, 4)
        .transition(.asymmetric(
            insertion: .opacity
                .combined(with: .move(edge: .top))
                .combined(with: .scale(scale: 0.985, anchor: .top)),
            removal: .opacity.combined(with: .move(edge: .bottom))
        ))
        .allowsHitTesting(!isClosing)
    }

    private var timeRail: some View {
        VStack(spacing: 6) {
            Text(AppFormatters.time.string(from: task.dueAt))
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 50, height: 26)
                .background(Color(.secondarySystemGroupedBackground), in: Capsule())
            Capsule()
                .fill(tint.opacity(isOpen ? 0.22 : 0.14))
                .frame(width: 2)
                .frame(maxHeight: .infinity)
        }
        .frame(width: 52)
        .frame(minHeight: isOpen ? (confirmationKind == nil ? 106 : 172) : 84, alignment: .top)
    }

    private var rowBackground: Color {
        if isRecentlyReopened {
            return Color.blue.opacity(0.12)
        }
        return Color(.secondarySystemGroupedBackground)
    }

    private var rowBorder: Color {
        if isRecentlyReopened {
            return Color.blue.opacity(0.34)
        }
        return Color.primary.opacity(0.045)
    }

    private var rowHeader: some View {
        HStack(alignment: .center, spacing: 10) {
            MedicationPhotoView(
                photoData: medication?.photoData,
                symbolName: medication?.photoSymbolName ?? "pills.fill",
                tint: medication.map(medicationColor(for:)) ?? tint,
                size: 40
            )
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 7) {
                    if let medication {
                        MedicationColorMarker(color: medicationColor(for: medication), size: 8)
                    }
                    Text(medication.map(userFacingMedicationName(for:)) ?? "未知药品")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.86)
                }
                Text("\(task.doseValue.formatted()) \(localizedMedicationUnit(task.doseUnit))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            StatusBadge(text: statusText, color: tint)
        }
    }
}

private struct InlineDoseConfirmationCard: View {
    let kind: PendingDoseConfirmation.Kind
    let delayDurationText: String
    let confirm: () -> Void
    let cancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 9) {
                Image(systemName: kind.iconName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(kind.tint)
                    .frame(width: 24, height: 24)
                    .background(kind.tint.opacity(0.12), in: Circle())

                VStack(alignment: .leading, spacing: 3) {
                    Text(kind.title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(kind.message(delayDurationText: delayDurationText))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            HStack(spacing: 8) {
                Button("取消", action: cancel)
                    .font(.caption.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 30)
                    .foregroundStyle(.secondary)
                    .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8))

                Button(kind.confirmTitle, action: confirm)
                    .font(.caption.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 30)
                    .foregroundStyle(.white)
                    .background(kind.tint, in: RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
        }
        .padding(10)
        .background(kind.tint.opacity(0.07), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(kind.tint.opacity(0.16), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
    }
}

private struct OpenDoseSummaryRow: View {
    let count: Int
    let latestText: String
    let isReceiving: Bool
    let migrationSnapshot: DoseMigrationSnapshot?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Image(systemName: "tray.and.arrow.up.fill")
                    .font(.title3)
                    .foregroundStyle(.blue)
                    .frame(width: 30, height: 30)
                    .background(Color.blue.opacity(isReceiving ? 0.18 : 0.12), in: Circle())
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(count) 条待处理")
                        .font(.headline)
                    Text(latestText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
            }
            if let migrationSnapshot {
                DoseMigrationPill(snapshot: migrationSnapshot, tint: .blue)
                    .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .leading)))
            }
        }
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.blue.opacity(isReceiving ? 0.08 : 0))
        )
        .scaleEffect(isReceiving ? 1.01 : 1)
        .animation(.easeInOut(duration: 0.18), value: isReceiving)
        .accessibilityElement(children: .combine)
    }
}

private struct HandledDoseSummaryRow: View {
    let count: Int
    let latestText: String
    let isReceiving: Bool
    let migrationSnapshot: DoseMigrationSnapshot?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.green)
                    .frame(width: 30, height: 30)
                    .background(Color.green.opacity(isReceiving ? 0.18 : 0.12), in: Circle())
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(count) 条已处理")
                        .font(.headline)
                    Text(latestText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
            }
            if let migrationSnapshot {
                DoseMigrationPill(snapshot: migrationSnapshot, tint: .green)
                    .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .leading)))
            }
        }
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.green.opacity(isReceiving ? 0.08 : 0))
        )
        .scaleEffect(isReceiving ? 1.01 : 1)
        .animation(.easeInOut(duration: 0.18), value: isReceiving)
        .accessibilityElement(children: .combine)
    }
}

private struct DoseMigrationPill: View {
    let snapshot: DoseMigrationSnapshot
    let tint: Color

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: snapshot.symbolName)
                .font(.caption.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 22, height: 22)
                .background(tint.opacity(0.14), in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(snapshot.medicationName)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
                Text("\(snapshot.timeText) · \(snapshot.doseText)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Text(snapshot.statusText)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(tint)
                .lineLimit(1)
        }
        .frame(height: 40)
        .padding(.horizontal, 8)
        .background(tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(tint.opacity(0.12), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
    }
}

private struct HandledDoseTaskRow: View {
    let task: StoredDoseTask
    let medication: StoredMedication?
    let statusText: String
    let undo: () -> Void
    let archive: () -> Void

    private var tint: Color {
        switch task.status {
        case .taken, .corrected:
            .green
        case .skipped:
            .orange
        case .pending, .delayed:
            .blue
        }
    }

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Text(AppFormatters.time.string(from: task.dueAt))
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 46, height: 26)
                .background(Color(.tertiarySystemGroupedBackground), in: Capsule())
            MedicationPhotoView(
                photoData: medication?.photoData,
                symbolName: medication?.photoSymbolName ?? "pills.fill",
                tint: medication.map(medicationColor(for:)) ?? tint,
                size: 34
            )
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 7) {
                    if let medication {
                        MedicationColorMarker(color: medicationColor(for: medication), size: 8)
                    }
                    Text(medication.map(userFacingMedicationName(for:)) ?? "未知药品")
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                }
                Text("\(task.doseValue.formatted()) \(localizedMedicationUnit(task.doseUnit))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            StatusBadge(text: statusText, color: tint)
            Button("撤销") {
                undo()
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.orange)
            .buttonStyle(.borderless)
            .accessibilityLabel("撤销\(medication.map(userFacingMedicationName(for:)) ?? "这条记录")")
        }
        .padding(.vertical, 7)
        .contentShape(Rectangle())
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button {
                undo()
            } label: {
                Label("撤销", systemImage: "arrow.uturn.backward")
            }
            .tint(.orange)

            Button {
                archive()
            } label: {
                Label("归档", systemImage: "archivebox")
            }
            .tint(.gray)
        }
    }
}

private struct CompactDoseActionButton: View {
    let title: String
    let confirmationIconName: String
    let tint: Color
    let isProminent: Bool
    let isConfirming: Bool
    let action: () -> Void

    var body: some View {
        Button {
            action()
        } label: {
            ZStack {
                Text(title)
                    .opacity(isConfirming ? 0 : 1)
                    .blur(radius: isConfirming ? 3 : 0)
                    .scaleEffect(isConfirming ? 0.94 : 1)
                Image(systemName: confirmationIconName)
                    .font(.caption.weight(.bold))
                    .opacity(isConfirming ? 1 : 0)
                    .blur(radius: isConfirming ? 0 : 2)
                    .scaleEffect(isConfirming ? 1 : 0.86)
            }
            .font(.caption.weight(.semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.9)
            .frame(maxWidth: .infinity)
            .frame(height: 36)
            .foregroundStyle(isProminent ? TodayDoseActionPalette.primaryText : tint)
            .background(background, in: RoundedRectangle(cornerRadius: 8))
            .animation(.easeInOut(duration: 0.16), value: isConfirming)
        }
        .buttonStyle(CompactDoseActionButtonStyle())
        .disabled(isConfirming)
        .accessibilityLabel(title)
    }

    private var background: Color {
        if isProminent {
            return tint
        }
        return tint.opacity(tint == .gray ? 0.14 : 0.16)
    }
}

private struct CompactDoseActionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.78 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

private enum TodayDoseActionPalette {
    static let primary = Color(red: 0.82, green: 0.94, blue: 0.99)
    static let primaryText = Color(red: 0.12, green: 0.38, blue: 0.56)
}

private struct ArchivedDoseTaskRow: View {
    let task: StoredDoseTask
    let medication: StoredMedication?
    let statusText: String
    let restore: () -> Void
    let reopen: () -> Void

    private var tint: Color {
        switch task.status {
        case .taken, .corrected:
            .green
        case .skipped:
            .orange
        case .pending, .delayed:
            .blue
        }
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            MedicationPhotoView(
                photoData: medication?.photoData,
                symbolName: medication?.photoSymbolName ?? "pills.fill",
                tint: medication.map(medicationColor(for:)) ?? tint,
                size: 40
            )
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 7) {
                    if let medication {
                        MedicationColorMarker(color: medicationColor(for: medication), size: 8)
                    }
                    Text(medication.map(userFacingMedicationName(for:)) ?? "未知药品")
                        .font(.subheadline.weight(.semibold))
                }
                Text("\(AppFormatters.time.string(from: task.dueAt)) · \(task.doseValue.formatted()) \(localizedMedicationUnit(task.doseUnit))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                StatusBadge(text: statusText, color: tint)
            }
            Spacer()
            Button("恢复") {
                restore()
            }
            .font(.caption.weight(.semibold))
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(.vertical, 6)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button {
                restore()
            } label: {
                Label("恢复", systemImage: "tray.and.arrow.up")
            }
            .tint(.blue)

            Button {
                reopen()
            } label: {
                Label("撤销", systemImage: "arrow.uturn.backward")
            }
            .tint(.orange)
        }
    }
}

private struct DoseTaskRow: View {
    let task: StoredDoseTask
    let medication: StoredMedication?
    let completionText: String
    let markTaken: () -> Void
    let delay: () -> Void
    let skip: () -> Void
    let undo: () -> Void
    let undoLog: StoredDoseActionLog?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let medication {
                NavigationLink {
                    MedicationDetailView(medication: medication)
                } label: {
                    DoseTaskHeader(task: task, medication: medication)
                }
            } else {
                HStack(alignment: .top, spacing: 14) {
                    MedicationPhotoView(photoData: nil, symbolName: "pills.fill", tint: .blue)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("未知药品")
                            .font(.headline)
                        Text("\(task.doseValue.formatted()) \(localizedMedicationUnit(task.doseUnit)) · \(AppFormatters.time.string(from: task.dueAt))")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        StatusBadge(text: task.status.displayName, color: .orange)
                    }
                    Spacer()
                }
            }

            HStack(spacing: 10) {
                Button(action: markTaken) {
                    Label(completionText, systemImage: "checkmark")
                }
                .buttonStyle(.borderedProminent)
                .tint(TodayDoseActionPalette.primary)
                Button(action: delay) {
                    Label("稍后", systemImage: "clock")
                }
                .buttonStyle(.bordered)
                Button(action: skip) {
                    Label("忽略", systemImage: "minus.circle")
                }
                .buttonStyle(.bordered)
                .tint(.orange)
                if undoLog != nil {
                    Button(action: undo) {
                        Label("撤销", systemImage: "arrow.uturn.backward")
                    }
                    .buttonStyle(.bordered)
                }
            }
            .controlSize(.large)
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
    }
}

private struct DoseTaskHeader: View {
    let task: StoredDoseTask
    let medication: StoredMedication

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            MedicationPhotoView(photoData: medication.photoData, symbolName: medication.photoSymbolName, tint: medicationColor(for: medication))
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    MedicationColorMarker(color: medicationColor(for: medication), size: 9)
                    Text(userFacingMedicationName(for: medication))
                        .font(.headline)
                }
                if medicationNeedsNameReview(medication) {
                    Text("药名待补全")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.orange)
                }
                Text("\(task.doseValue.formatted()) \(localizedMedicationUnit(task.doseUnit)) · \(AppFormatters.time.string(from: task.dueAt))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                StatusBadge(text: task.status.displayName, color: task.status == .taken ? .green : .orange)
            }
            Spacer()
        }
    }
}

private struct ResolvedDoseTaskRow: View {
    let task: StoredDoseTask
    let medication: StoredMedication?
    let undoLog: StoredDoseActionLog?
    let statusText: String
    let reopen: () -> Void
    let archive: () -> Void
    let showDetail: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            MedicationPhotoView(
                photoData: medication?.photoData,
                symbolName: medication?.photoSymbolName ?? "pills.fill",
                tint: medication.map(medicationColor(for:)) ?? (task.status == .taken || task.status == .corrected ? .green : .orange),
                size: 44
            )
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    if let medication {
                        MedicationColorMarker(color: medicationColor(for: medication), size: 9)
                    }
                    Text(medication.map(userFacingMedicationName(for:)) ?? "未知药品")
                        .font(.headline)
                }
                Text("\(task.doseValue.formatted()) \(localizedMedicationUnit(task.doseUnit)) · \(AppFormatters.time.string(from: task.dueAt))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            StatusBadge(text: statusText, color: task.status == .taken || task.status == .corrected ? .green : .orange)
        }
        .padding(.vertical, 6)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(action: reopen) {
                Label("撤销", systemImage: "arrow.uturn.backward")
            }
            .tint(.orange)

            Button(action: archive) {
                Label("归档", systemImage: "archivebox")
            }
            .tint(.gray)

            Button(action: showDetail) {
                Label("详情", systemImage: "info.circle")
            }
            .tint(.blue)
        }
    }
}
