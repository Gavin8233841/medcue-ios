import Combine
import MedicationAdherenceCore
import SwiftUI
import UIKit

struct TodayScreenActions {
    let medication: (StoredDoseTask) -> StoredMedication?
    let logicalDoseKey: (StoredDoseTask) -> String
    let completionVerb: (StoredMedication?) -> String
    let statusText: (StoredDoseTask) -> String
    let markTaken: (StoredDoseTask) -> Void
    let delay: (StoredDoseTask) -> Void
    let skip: (StoredDoseTask) -> Void
    let confirm: (StoredDoseTask) -> Void
    let cancelConfirmation: (StoredDoseTask) -> Void
    let undoOrReopen: (StoredDoseTask) -> Void
    let archive: (StoredDoseTask) -> Void
    let unarchive: (StoredDoseTask) -> Void
    let rollbackUndo: (DoseUndoBanner) -> Void
    let switchToElderMode: () -> Void
    let initialLoad: () async -> Void
    let timerTick: () -> Void
    let becameActive: () -> Void
    let cleanup: () -> Void
}

struct TodayScreen: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @AppStorage(AppExperienceMode.storageKey) private var experienceMode = AppExperienceMode.complete.rawValue
    @State private var showingElderConfirmation = false
    let snapshot: TodayRenderSnapshot
    let notificationUnavailableMessage: String
    let completionRateFeedback: CompletionRateFeedback?
    let completionRateDisplayedSnapshot: CompletionRateSnapshot?
    let isCompletionRateFeedbackVisible: Bool
    let shouldShowCompletionCelebration: Bool
    let prefersReducedMotion: Bool
    let isOpenTimelineTemporarilyCollapsed: Bool
    let isHandledTimelineTemporarilyCollapsed: Bool
    let pendingDoseConfirmation: PendingDoseConfirmation?
    let pendingDoseFeedback: PendingDoseFeedback?
    let inFlightDoseKeys: Set<String>
    let handledDropTargetPulse: Bool
    let pendingHandledArrivalCount: Int
    let closingOpenDoseKeys: Set<String>
    let reopeningHandledDoseKeys: Set<String>
    let recentlyReopenedDoseKeys: Set<String>
    let doseMigrationSnapshot: DoseMigrationSnapshot?
    let doseUndoBanner: DoseUndoBanner?
    @Binding var showingHandledTasks: Bool
    @Binding var taskPendingArchive: StoredDoseTask?
    @Binding var showingArchiveConfirmation: Bool
    @Binding var showingHelpCenter: Bool
    @Binding var pendingPermissionGate: AppPermissionGate?
    @Binding var dosePersistenceErrorMessage: String?
    let actions: TodayScreenActions
    private let liveActivityRefreshTimer = Timer
        .publish(every: 60, on: .main, in: .common)
        .autoconnect()

    var notificationUnavailableDetailText: String? {
        #if targetEnvironment(simulator) && (DEBUG || MEDCUE_DEMO)
        // Explicit capture-only presentation. Scheduling and its real failure
        // state remain untouched; this switch cannot affect physical devices.
        if ProcessInfo.processInfo.arguments.contains("--recording-hide-reminder-banner") {
            return nil
        }
        #endif
        let message = notificationUnavailableMessage
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty else {
            return nil
        }
        return message.replacingOccurrences(of: "普通提醒不可用：", with: "")
    }

    private var completionRateFeedbackSlotHeight: CGFloat {
        guard completionRateFeedback != nil else {
            return 0
        }
        return isCompletionRateFeedbackVisible ? 88 : 0
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

    var body: some View {
        ZStack(alignment: .top) {
            VStack(spacing: 0) {
                completionRateFeedbackSlot
                timeline
            }

            if let doseUndoBanner {
                VStack {
                    Spacer(minLength: 0)
                    DoseUndoBannerView(
                        banner: doseUndoBanner,
                        undoRollback: { actions.rollbackUndo(doseUndoBanner) }
                    )
                    .padding(.horizontal, 16)
                    .padding(.bottom, 10)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                .zIndex(5)
                .allowsHitTesting(true)
            }
        }
        .transaction { transaction in
            if prefersReducedMotion {
                transaction.animation = nil
                transaction.disablesAnimations = true
            }
        }
        .navigationTitle("今日")
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button("适老模式") { showingElderConfirmation = true }
                    .font(.subheadline.weight(.medium))
                    .accessibilityIdentifier("today.enter-elder")
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
        .alert("进入适老模式？", isPresented: $showingElderConfirmation) {
            Button("取消", role: .cancel) {}
            Button("进入适老模式") { experienceMode = AppExperienceMode.elder.rawValue }
        } message: {
            Text("一次查看一项用药任务，长按按钮确认操作。可随时返回完整模式。")
        }
        .task {
            await actions.initialLoad()
        }
        .onReceive(liveActivityRefreshTimer) { _ in
            actions.timerTick()
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else {
                return
            }
            actions.becameActive()
        }
        .confirmationDialog(
            "归档这条今日记录？",
            isPresented: $showingArchiveConfirmation
        ) {
            Button("归档记录", role: .destructive) {
                if let taskPendingArchive {
                    actions.archive(taskPendingArchive)
                    self.taskPendingArchive = nil
                }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text(
                "\(taskPendingArchive.flatMap { actions.medication($0).map(userFacingMedicationName(for:)) } ?? "这条记录") 会从今日已处理列表隐藏，但仍保留在服药历史中。"
            )
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
        .onDisappear(perform: actions.cleanup)
    }

    private var timeline: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 22) {
                notificationUnavailableBanner
                if snapshot.visibleOpenTimelineTasks.isEmpty && !isDoseListReparenting {
                    TodaySettledCard(snapshot: snapshot, reduceMotion: prefersReducedMotion || systemReduceMotion)
                        .transition(.opacity.combined(with: .scale(scale: 0.98)))
                } else {
                    openTimelineSection
                }

                if snapshot.shouldShowHandledSection {
                    handledTimelineSection
                }

                archivedTimelineSection
                if snapshot.nextReminderTask != nil || snapshot.overdueOpenTaskCount > 0 {
                    nextReminderSection
                }
            }
            .animation(prefersReducedMotion || systemReduceMotion ? nil : .smooth(duration: 0.3), value: snapshot.visibleOpenTimelineTasks.isEmpty)
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 180)
            .background(alignment: .top) {
                AppTopGradientScrollReader(
                    tab: .today,
                    coordinateSpaceName: "TodayTopGradientScroll"
                )
            }
        }
        .coordinateSpace(name: "TodayTopGradientScroll")
        .background(Color(.systemGroupedBackground))
    }

    private var completionRateFeedbackSlot: some View {
        ZStack(alignment: .top) {
            if let completionRateFeedback,
               let completionRateDisplayedSnapshot {
                CompletionRateFeedbackPanel(
                    feedback: completionRateFeedback,
                    displayedSnapshot: completionRateDisplayedSnapshot,
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
                .animation(
                    prefersReducedMotion ? nil : .smooth(duration: 0.38, extraBounce: 0.04),
                    value: isCompletionRateFeedbackVisible
                )
                .animation(
                    prefersReducedMotion ? nil : .smooth(duration: 0.34, extraBounce: 0.03),
                    value: completionRateFeedback.id
                )
            }
        }
        .frame(height: completionRateFeedbackSlotHeight, alignment: .top)
        .accessibilityHidden(true)
        .allowsHitTesting(false)
        .animation(
            prefersReducedMotion ? nil : .smooth(duration: 0.38, extraBounce: 0.03),
            value: completionRateFeedbackSlotHeight
        )
    }

    @ViewBuilder
    private var notificationUnavailableBanner: some View {
        if let notificationUnavailableDetailText {
            Button(action: openSystemNotificationSettings) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "bell.slash.fill")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.orange)
                        .frame(width: 26, height: 26)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("普通提醒不可用")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                        Text(notificationUnavailableDetailText)
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
                .medicationGlassSurface(
                    cornerRadius: 18,
                    tint: .orange,
                    fallbackMaterial: .thinMaterial,
                    isInteractive: true
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(.orange.opacity(0.16), lineWidth: 1)
                }
            }
            .buttonStyle(.plain)
            .accessibilityHint("打开系统设置检查通知权限")
        }
    }

    private var openTimelineSection: some View {
        todaySection(
            "今日待处理",
            titleAccessibilityIdentifier: AppAccessibilityID.todayOpenTimeline
        ) {
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
                    let doseKey = actions.logicalDoseKey(task)
                    let medication = actions.medication(task)
                    TimelineDoseTaskRow(
                        task: task,
                        medication: medication,
                        completionText: actions.completionVerb(medication),
                        statusText: actions.statusText(task),
                        isOpen: task.status == .pending
                            || task.status == .delayed
                            || closingOpenDoseKeys.contains(doseKey)
                            || pendingDoseFeedback?.doseKey == doseKey,
                        isActionInFlight: inFlightDoseKeys.contains(doseKey),
                        feedbackAction: pendingDoseFeedback?.doseKey == doseKey
                            ? pendingDoseFeedback?.action
                            : nil,
                        isClosing: closingOpenDoseKeys.contains(doseKey),
                        isRecentlyReopened: recentlyReopenedDoseKeys.contains(doseKey),
                        confirmationKind: pendingDoseConfirmation?.doseKey == doseKey
                            ? pendingDoseConfirmation?.kind
                            : nil,
                        markTaken: { actions.markTaken(task) },
                        delay: { actions.delay(task) },
                        skip: { actions.skip(task) },
                        confirm: { actions.confirm(task) },
                        cancelConfirmation: { actions.cancelConfirmation(task) }
                    )
                }
            }
        }
        .animation(
            prefersReducedMotion ? nil : .smooth(duration: 0.30, extraBounce: 0.02),
            value: snapshot.visibleOpenTimelineTasks.map(\.id)
        )
        .animation(prefersReducedMotion ? nil : .easeInOut(duration: 0.16), value: pendingDoseFeedback)
        .animation(
            prefersReducedMotion ? nil : .snappy(duration: 0.24, extraBounce: 0.01),
            value: isOpenTimelineTemporarilyCollapsed
        )
        .animation(prefersReducedMotion ? nil : .easeInOut(duration: 0.18), value: closingOpenDoseKeys)
        .animation(
            prefersReducedMotion ? nil : .snappy(duration: 0.24, extraBounce: 0.02),
            value: recentlyReopenedDoseKeys
        )
    }

    private var handledTimelineSection: some View {
        todaySection("今日记录", hasCardBackground: false) {
            let isExpanded = handledDisclosureBinding.wrappedValue
            let value = "\(snapshot.displayedHandledCount) 条，\(snapshot.handledSummaryText)，\(isExpanded ? "已展开" : "已折叠")"
            Button {
                toggleHandledTasks()
            } label: {
                HStack(spacing: 8) {
                    Label("\(snapshot.displayedHandledCount) 条记录", systemImage: "list.bullet.rectangle")
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Spacer()
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }
                .contentShape(Rectangle())
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("今日记录")
                .accessibilityValue(value)
            }
            .buttonStyle(.plain)
            .padding(8)
            .medicationGlassSurface(cornerRadius: 16, isInteractive: true)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("今日记录")
            .accessibilityValue(value)
            .accessibilityHint(isExpanded ? "收起已处理记录" : "展开已处理记录")
            .accessibilityIdentifier("today.records.toggle")

            if isExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(snapshot.handledTodayTasks) { task in
                        let doseKey = actions.logicalDoseKey(task)
                        HandledDoseTaskRow(
                            task: task,
                            medication: actions.medication(task),
                            statusText: actions.statusText(task),
                            undo: { actions.undoOrReopen(task) },
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
        .animation(
            prefersReducedMotion || isDoseListReparenting
                ? nil
                : .snappy(duration: 0.22, extraBounce: 0.01),
            value: snapshot.handledTodayTasks.map(\.id)
        )
        .animation(
            prefersReducedMotion ? nil : .snappy(duration: 0.22, extraBounce: 0.01),
            value: isHandledTimelineTemporarilyCollapsed
        )
        .animation(prefersReducedMotion ? nil : .easeInOut(duration: 0.18), value: reopeningHandledDoseKeys)
        .animation(prefersReducedMotion ? nil : .easeInOut(duration: 0.2), value: handledDropTargetPulse)
        .accessibilityIdentifier(AppAccessibilityID.todayHandledTimeline)
    }

    @ViewBuilder
    private var archivedTimelineSection: some View {
        if !snapshot.archivedTodayTasks.isEmpty {
            todaySection("今日已归档") {
                ForEach(snapshot.archivedTodayTasks) { task in
                    ArchivedDoseTaskRow(
                        task: task,
                        medication: actions.medication(task),
                        statusText: actions.statusText(task),
                        restore: { actions.unarchive(task) },
                        reopen: { actions.undoOrReopen(task) }
                    )
                }
            }
        }
    }

    private var nextReminderSection: some View {
        todaySection("下一次提醒") {
            if let nextTask = snapshot.nextReminderTask {
                HStack {
                    Image(systemName: "bell.badge")
                        .foregroundStyle(.blue)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(
                            actions.medication(nextTask)
                                .map(userFacingMedicationName(for:))
                                ?? "用药提醒"
                        )
                        .font(.headline)
                        Text(AppFormatters.time.string(from: nextTask.dueAt))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 6)
            } else if snapshot.overdueOpenTaskCount > 0 {
                Label(
                    "还有 \(snapshot.overdueOpenTaskCount) 项待确认",
                    systemImage: "clock.badge.exclamationmark"
                )
                .font(.headline)
                .foregroundStyle(.orange)
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

    private func todaySection<Content: View>(
        _ title: String,
        titleAccessibilityIdentifier: String? = nil,
        hasCardBackground: Bool = true,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            todaySectionTitle(title, accessibilityIdentifier: titleAccessibilityIdentifier)

            VStack(alignment: .leading, spacing: 10) {
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(hasCardBackground ? 12 : 0)
            .background(
                hasCardBackground ? Color(.secondarySystemGroupedBackground) : .clear,
                in: RoundedRectangle(cornerRadius: 18, style: .continuous)
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func todaySectionTitle(
        _ title: String,
        accessibilityIdentifier: String?
    ) -> some View {
        let label = Text(title)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)

        if let accessibilityIdentifier {
            label.accessibilityIdentifier(accessibilityIdentifier)
        } else {
            label
        }
    }

    private func openSystemNotificationSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else {
            return
        }
        UIApplication.shared.open(url)
    }

    private func toggleHandledTasks() {
        if prefersReducedMotion {
            var transaction = Transaction(animation: nil)
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                showingHandledTasks.toggle()
            }
        } else {
            withAnimation(.snappy(duration: 0.24, extraBounce: 0.01)) {
                showingHandledTasks.toggle()
            }
        }
    }
}

func todayDoseStatusText(
    for task: StoredDoseTask,
    medication: StoredMedication?,
    delayDurationText: String
) -> String {
    switch task.status {
    case .taken, .corrected:
        todayCompletionVerb(for: medication)
    case .skipped:
        "已忽略"
    case .pending:
        task.status.displayName
    case .delayed:
        "\(delayDurationText)后"
    }
}

func todayCompletionVerb(for medication: StoredMedication?) -> String {
    guard let medication else {
        return "已完成"
    }
    let combined = "\(medication.displayName) \(medication.form)".lowercased()
    let nonOralMarkers = ["tear", "drop", "滴", "眼", "喷", "贴", "膏"]
    return nonOralMarkers.contains(where: combined.contains) ? "已使用" : "已服用"
}
