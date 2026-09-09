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
    let requestWeatherRefresh: (Bool) async -> Bool
    let initialLoad: () async -> Void
    let timerTick: () -> Void
    let becameActive: () -> Void
    let cleanup: () -> Void
}

struct TodayScreen: View {
    @Environment(\.scenePhase) private var scenePhase
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
    let weatherHints: [WeatherMedicationHint]
    let weatherStatusText: String
    let isWeatherLoading: Bool
    let shouldShowWeatherAuthorization: Bool
    let doseUndoBanner: DoseUndoBanner?
    let weatherMedicationSignature: String
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

    private var notificationUnavailableDetailText: String? {
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

    private var shouldShowWeatherMedicationSection: Bool {
        isWeatherLoading || shouldShowWeatherAuthorization || !visibleWeatherHints.isEmpty
    }

    private var visibleWeatherHints: [WeatherMedicationHint] {
        weatherHints.filter(\.isActionableForToday)
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
                if await actions.requestWeatherRefresh(true) {
                    AppPermissionGate.markAuthorizationCompleted(for: .location)
                }
            }
        }
        .task(id: weatherMedicationSignature) {
            _ = await actions.requestWeatherRefresh(false)
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
                if snapshot.completionRateSnapshot.isComplete,
                   shouldShowCompletionCelebration {
                    CompletionCompleteCelebrationCard(
                        snapshot: snapshot.completionRateSnapshot,
                        reduceMotion: prefersReducedMotion
                    )
                    .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .top)))
                    .animation(
                        prefersReducedMotion ? nil : .snappy(duration: 0.28, extraBounce: 0.03),
                        value: snapshot.completionRateSnapshot
                    )
                }

                elderModeEntryCard
                notificationUnavailableBanner
                openTimelineSection

                if snapshot.shouldShowHandledSection {
                    handledTimelineSection
                }

                archivedTimelineSection
                nextReminderSection
                if shouldShowWeatherMedicationSection {
                    weatherMedicationSection
                }
            }
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

    private var elderModeEntryCard: some View {
        Button(action: actions.switchToElderMode) {
            HStack(spacing: 14) {
                Image(systemName: "checklist")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.blue)
                    .frame(width: 42, height: 42)
                    .background(
                        Color.blue.opacity(0.12),
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                    )

                Text("适老模式")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 8)

                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .medicationGlassSurface(
                cornerRadius: 20,
                tint: .blue,
                fallbackMaterial: .thinMaterial,
                isInteractive: true
            )
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(Color.blue.opacity(0.16), lineWidth: 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("适老模式")
        .accessibilityIdentifier(AppAccessibilityID.todayElderModeEntry)
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
        .accessibilityIdentifier(AppAccessibilityID.todayOpenTimeline)
    }

    private var handledTimelineSection: some View {
        todaySection("今日已处理") {
            let isExpanded = handledDisclosureBinding.wrappedValue
            let value = "\(snapshot.displayedHandledCount) 条，\(snapshot.handledSummaryText)，\(isExpanded ? "已展开" : "已折叠")"
            Button {
                toggleHandledTasks()
            } label: {
                HStack(spacing: 8) {
                    HandledDoseSummaryRow(
                        count: snapshot.displayedHandledCount,
                        latestText: snapshot.handledSummaryText,
                        isReceiving: handledDropTargetPulse
                            || !reopeningHandledDoseKeys.isEmpty,
                        migrationSnapshot: handledDropTargetPulse
                            ? doseMigrationSnapshot
                            : nil
                    )
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }
                .contentShape(Rectangle())
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("今日已处理")
                .accessibilityValue(value)
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("今日已处理")
            .accessibilityValue(value)
            .accessibilityHint(isExpanded ? "收起已处理记录" : "展开已处理记录")

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

    private var weatherMedicationSection: some View {
        todaySection("天气与用药关注") {
            if isWeatherLoading && weatherHints.isEmpty {
                ProgressView("正在读取今日天气")
            }
            ForEach(visibleWeatherHints) { hint in
                WeatherMedicationHintCard(hint: hint)
            }
            if shouldShowWeatherAuthorization {
                Button {
                    Task {
                        if await actions.requestWeatherRefresh(true) {
                            AppPermissionGate.markAuthorizationCompleted(for: .location)
                        }
                    }
                } label: {
                    Label("允许天气提醒", systemImage: "location.fill")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            if !weatherStatusText.isEmpty {
                Text(weatherStatusText)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
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
            .background(
                Color(.secondarySystemGroupedBackground),
                in: RoundedRectangle(cornerRadius: 18, style: .continuous)
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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

struct ElderTodayScreenActions {
    let logicalDoseKey: (StoredDoseTask) -> String
    let completionVerb: (StoredMedication?) -> String
    let markTaken: (StoredDoseTask) -> Void
    let delay: (StoredDoseTask) -> Void
    let confirm: (StoredDoseTask) -> Void
    let cancelConfirmation: (StoredDoseTask) -> Void
    let requestHelp: () -> Void
    let confirmHelp: () -> Void
    let cancelHelp: () -> Void
    let openSettings: () -> Void
    let openNotificationSettings: () -> Void
    let switchToCompleteMode: () -> Void
    let initialLoad: () async -> Void
    let timerTick: () -> Void
    let becameActive: () -> Void
    let cleanup: () -> Void
}

struct ElderTodayScreen: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.medcueReduceMotionEnabled) private var reduceMotionEnabled
    @AccessibilityFocusState private var accessibilityFocus: ElderAccessibilityFocus?
    @ScaledMetric(relativeTo: .largeTitle) private var elderTitlePointSize: CGFloat = 46
    @ScaledMetric(relativeTo: .title2) private var elderDosePointSize: CGFloat = 26
    @ScaledMetric(relativeTo: .title3) private var elderMetaPointSize: CGFloat = 22
    let snapshot: ElderTodayRenderSnapshot
    let pendingDoseConfirmation: PendingDoseConfirmation?
    let pendingDoseFeedback: PendingDoseFeedback?
    let inFlightDoseKeys: Set<String>
    @Binding var dosePersistenceErrorMessage: String?
    @Binding var helpOpeningErrorMessage: String?
    @Binding var helpMissingMessage: String?
    @Binding var helpConfirmationPhone: ElderHelpPhoneNumber?
    @Binding var successFeedback: String?
    let notificationUnavailableMessage: String
    let loadErrorMessage: String?
    let isLoading: Bool
    let actions: ElderTodayScreenActions
    private let currentTaskRefreshTimer = Timer
        .publish(every: 1, on: .main, in: .common)
        .autoconnect()

    private var isAccessibilityLayout: Bool {
        dynamicTypeSize.isAccessibilitySize
    }

    private func medicationPhotoWidth(for availableWidth: CGFloat) -> CGFloat {
        if isAccessibilityLayout {
            return ElderTaskLayoutMetrics.accessibilityPhotoWidth(for: availableWidth)
        }
        return ElderTaskLayoutMetrics.regularPhotoWidth(for: availableWidth)
    }

    private var helpConfirmationPresented: Binding<Bool> {
        Binding(
            get: { helpConfirmationPhone != nil },
            set: { isPresented in
                if !isPresented {
                    actions.cancelHelp()
                }
            }
        )
    }

    private var helpMissingPresented: Binding<Bool> {
        Binding(
            get: { helpMissingMessage != nil },
            set: { isPresented in
                if !isPresented {
                    helpMissingMessage = nil
                }
            }
        )
    }

    private var activeConfirmation: PendingDoseConfirmation.Kind? {
        guard let task = snapshot.currentTask,
              pendingDoseConfirmation?.doseKey == actions.logicalDoseKey(task)
        else {
            return nil
        }
        return pendingDoseConfirmation?.kind
    }

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if let successFeedback {
                        ElderDoseSuccessFeedback(message: successFeedback)
                            .transition(.opacity)
                            .accessibilityFocused($accessibilityFocus, equals: .success)
                    }

                    reminderWarning

                    if isLoading && snapshot.currentTask == nil {
                        ProgressView()
                            .controlSize(.large)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 96)
                            .accessibilityLabel("正在加载用药任务")
                    } else if loadErrorMessage != nil {
                        loadErrorState
                    } else if let task = snapshot.currentTask {
                        currentTaskCard(task, availableWidth: geometry.size.width)
                        if snapshot.remainingOpenTaskCount > 0 {
                            Text("还有 \(snapshot.remainingOpenTaskCount) 项待处理")
                                .font(.headline)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    } else {
                        elderEmptyState
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 28)
            }
            .accessibilityIdentifier("elder.scroll")
        }
        .background(Color(.systemGroupedBackground))
        .safeAreaInset(edge: .top, spacing: 0) {
            Color(.systemGroupedBackground)
                .frame(height: 8)
                .accessibilityHidden(true)
        }
        .transaction { transaction in
            if reduceMotionEnabled {
                transaction.animation = nil
                transaction.disablesAnimations = true
            }
        }
        .navigationTitle("用药提醒")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color(.systemGroupedBackground), for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(colorScheme, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button(action: actions.switchToCompleteMode) {
                    if dynamicTypeSize.isAccessibilitySize {
                        Image(systemName: "arrow.backward")
                    } else {
                        Text("完整模式")
                    }
                }
                .accessibilityLabel("完整模式")
                .accessibilityIdentifier(AppAccessibilityID.elderSwitchToComplete)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button(action: actions.openSettings) {
                    Label("同机设置", systemImage: "gearshape")
                }
                .accessibilityIdentifier(AppAccessibilityID.elderOpenSettings)
            }
        }
        .task {
            await actions.initialLoad()
        }
        .onReceive(currentTaskRefreshTimer) { _ in
            actions.timerTick()
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else {
                return
            }
            actions.becameActive()
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
        .alert(
            "未能打开电话确认界面",
            isPresented: Binding(
                get: { helpOpeningErrorMessage != nil },
                set: { isPresented in
                    if !isPresented {
                        helpOpeningErrorMessage = nil
                    }
                }
            )
        ) {
            Button("好", role: .cancel) {
                helpOpeningErrorMessage = nil
            }
            .accessibilityIdentifier("elder.help.error.dismiss")
        } message: {
            Text(helpOpeningErrorMessage ?? "请在同机设置中检查帮助号码后重试。")
        }
        .alert("还没有帮助号码", isPresented: helpMissingPresented) {
            Button("去设置") {
                helpMissingMessage = nil
                actions.openSettings()
            }
            .accessibilityIdentifier("elder.help.missing.settings")
            Button("取消", role: .cancel) {
                helpMissingMessage = nil
            }
            .accessibilityIdentifier("elder.help.missing.cancel")
        } message: {
            Text(helpMissingMessage ?? "请先添加帮助号码。")
        }
        .alert(
            "联系帮助？",
            isPresented: helpConfirmationPresented
        ) {
            Button("拨打 \(helpConfirmationPhone?.storageValue ?? "")") {
                actions.confirmHelp()
            }
            Button("取消", role: .cancel) {
                actions.cancelHelp()
            }
            .accessibilityIdentifier("elder.help.cancel")
        } message: {
            Text("帮助号码：\(helpConfirmationPhone?.storageValue ?? "")")
        }
        .onChange(of: successFeedback) { _, message in
            guard let message else { return }
            UIAccessibility.post(notification: .announcement, argument: message)
            DispatchQueue.main.async {
                accessibilityFocus = .success
            }
        }
        .onChange(of: pendingDoseConfirmation) { _, confirmation in
            guard let confirmation else { return }
            UIAccessibility.post(
                notification: .announcement,
                argument: confirmation.kind.elderTitle(completionVerb: actions.completionVerb(snapshot.currentMedication))
            )
            DispatchQueue.main.async {
                accessibilityFocus = .confirmation
            }
        }
        .onDisappear(perform: actions.cleanup)
    }

    private var loadErrorState: some View {
        VStack(spacing: 20) {
            Label("用药信息未能加载", systemImage: "exclamationmark.triangle.fill")
                .font(.title2.bold())
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            ElderDoseActionButton(
                title: "重试",
                systemImage: "arrow.clockwise",
                tone: .reminder,
                prominence: .primary,
                accessibilityIdentifier: "elder.load.retry",
                action: { Task { await actions.initialLoad() } }
            )
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
        .accessibilityElement(children: .contain)
    }

    private var elderEmptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: snapshot.emptyState?.systemImage ?? "checkmark.circle")
                .font(.system(size: 44, weight: .semibold))
                .foregroundStyle(.green)
            Text(snapshot.emptyState?.title ?? "没有待处理用药")
                .font(.title2.bold())
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 52)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var reminderWarning: some View {
        let message = notificationUnavailableMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        if !message.isEmpty {
            Button(action: actions.openNotificationSettings) {
                VStack(alignment: .leading, spacing: 8) {
                    Label(
                        message == "记录已保存，提醒未能开启。" ? message : "提醒暂不可用",
                        systemImage: "bell.slash.fill"
                    )
                        .font(.title3.bold())
                    Label("打开系统设置", systemImage: "gearshape")
                        .font(.title3.bold())
                }
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
                .padding(16)
                .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("elder.reminder.settings")
        }
    }

    private func currentTaskCard(_ task: StoredDoseTask, availableWidth: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            taskIdentity(task, availableWidth: availableWidth)

            Divider()
                .padding(.horizontal, 4)

            if let confirmationKind = activeConfirmation {
                ElderDoseConfirmationPanel(
                    kind: confirmationKind,
                    completionVerb: actions.completionVerb(snapshot.currentMedication),
                    confirm: { actions.confirm(task) },
                    cancel: { actions.cancelConfirmation(task) }
                )
                .accessibilityFocused($accessibilityFocus, equals: .confirmation)
            } else {
                VStack(spacing: ElderTaskLayoutMetrics.actionSpacing) {
                    ElderDoseActionButton(
                        title: actions.completionVerb(snapshot.currentMedication),
                        systemImage: "checkmark.circle.fill",
                        tone: .completion,
                        prominence: .primary,
                        accessibilityIdentifier: AppAccessibilityID.elderMarkTaken,
                        action: { actions.markTaken(task) }
                    )
                    ElderDoseActionButton(
                        title: "\(DoseDelayPolicy.delayMinutes) 分钟后提醒",
                        systemImage: "clock.arrow.circlepath",
                        tone: .reminder,
                        prominence: .secondary,
                        accessibilityIdentifier: AppAccessibilityID.elderDelay,
                        action: { actions.delay(task) }
                    )
                    ElderDoseActionButton(
                        title: "需要帮助",
                        systemImage: "phone.fill",
                        tone: .help,
                        prominence: .tertiary,
                        accessibilityIdentifier: AppAccessibilityID.elderRequestHelp,
                        action: actions.requestHelp
                    )
                }
                .disabled(
                    pendingDoseFeedback?.doseKey == actions.logicalDoseKey(task)
                        || inFlightDoseKeys.contains(actions.logicalDoseKey(task))
                )
            }
        }
        .padding(isAccessibilityLayout ? ElderTaskLayoutMetrics.accessibilityCardPadding : ElderTaskLayoutMetrics.regularCardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.blue.opacity(0.16), lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(AppAccessibilityID.elderCurrentTask)
    }

    @ViewBuilder
    private func taskIdentity(_ task: StoredDoseTask, availableWidth: CGFloat) -> some View {
        let photoWidth = medicationPhotoWidth(for: availableWidth)
        if isAccessibilityLayout {
            VStack(alignment: .center, spacing: ElderTaskLayoutMetrics.accessibilityIdentitySpacing) {
                medicationPhoto(size: photoWidth)
                taskDetails(task, centered: true)
                taskSchedule(task, centered: true)
            }
            .frame(maxWidth: .infinity)
        } else {
            // Share the recognition band even on short screens. Stacking a full-width
            // portrait at regular text size pushes the primary action below the fold.
            HStack(alignment: .center, spacing: ElderTaskLayoutMetrics.regularIdentitySpacing) {
                medicationPhoto(size: photoWidth)
                VStack(alignment: .leading, spacing: ElderTaskLayoutMetrics.regularDetailsSpacing) {
                    taskDetails(task, centered: false)
                    taskSchedule(task, centered: false)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func medicationPhoto(size: CGFloat) -> some View {
        ElderMedicationPhotoView(
            photoData: snapshot.currentMedication?.photoData,
            medicationName: snapshot.currentMedication.map(userFacingMedicationName(for:)),
            width: size
        )
        .id(snapshot.currentMedication?.id)
    }

    private func taskDetails(_ task: StoredDoseTask, centered: Bool) -> some View {
        VStack(alignment: centered ? .center : .leading, spacing: 8) {
            Text(snapshot.currentMedication.map(userFacingMedicationName(for:)) ?? "待核对药品")
                .font(.system(size: elderTitlePointSize, weight: .bold))
                .multilineTextAlignment(centered ? .center : .leading)
                .fixedSize(horizontal: false, vertical: true)

            if let currentStatus = snapshot.currentStatus {
                Text(currentStatus == .pendingBeforeDue && actions.completionVerb(snapshot.currentMedication) == "已使用"
                     ? "待使用" : currentStatus.displayName)
                    .font(.system(size: elderMetaPointSize, weight: .semibold))
                    .foregroundStyle(ElderDoseActionTone.reminder.foregroundColor(for: colorScheme))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(ElderDoseActionTone.reminder.foregroundColor(for: colorScheme).opacity(0.12), in: Capsule())
                    .fixedSize(horizontal: false, vertical: true)
            }

        }
        .frame(maxWidth: .infinity, alignment: centered ? .center : .leading)
        .accessibilityElement(children: .combine)
    }

    private func taskSchedule(_ task: StoredDoseTask, centered: Bool) -> some View {
        VStack(alignment: centered ? .center : .leading, spacing: 6) {
            doseText(task)
            timeText(task)
        }
        .frame(maxWidth: .infinity, alignment: centered ? .center : .leading)
        .accessibilityElement(children: .combine)
    }

    private func doseText(_ task: StoredDoseTask) -> some View {
        Text("每次 \(task.doseValue.formatted()) \(localizedMedicationUnit(task.doseUnit))")
            .font(.system(size: elderDosePointSize, weight: .semibold))
            .fixedSize(horizontal: false, vertical: true)
    }

    private func timeText(_ task: StoredDoseTask) -> some View {
        Label(AppFormatters.time.string(from: task.dueAt), systemImage: "clock")
            .font(.system(size: elderDosePointSize, weight: .regular))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

enum ElderTaskLayoutMetrics {
    // The regular recognition stage reserves roughly 54% of the card content width for a legible real photo.
    static let regularPhotoWidth: CGFloat = 180
    static let regularPhotoMinimumWidth: CGFloat = 176
    static let accessibilityPhotoWidth: CGFloat = 300
    // DemoAdvil is 960x1258; this fallback keeps portrait packaging from being narrowed by an overly wide frame.
    static let photoContainerAspectRatio: CGFloat = 0.76
    static let regularCardPadding: CGFloat = 18
    static let accessibilityCardPadding: CGFloat = 20
    static let regularIdentitySpacing: CGFloat = 12
    static let regularDetailsSpacing: CGFloat = 12
    static let accessibilityIdentitySpacing: CGFloat = 16
    static let actionSpacing: CGFloat = 12

    static func regularPhotoWidth(for availableWidth: CGFloat) -> CGFloat {
        let contentWidth = max(0, availableWidth - (2 * 16) - (2 * regularCardPadding))
        return min(max(contentWidth * 0.54, regularPhotoMinimumWidth), min(regularPhotoWidth, contentWidth))
    }

    static func accessibilityPhotoWidth(for availableWidth: CGFloat) -> CGFloat {
        let contentWidth = max(0, availableWidth - (2 * 16) - (2 * accessibilityCardPadding))
        return min(accessibilityPhotoWidth, contentWidth)
    }
}

private enum ElderAccessibilityFocus: Hashable {
    case confirmation
    case success
}

private struct ElderDoseSuccessFeedback: View {
    @Environment(\.colorScheme) private var colorScheme
    let message: String

    var body: some View {
        Label(message, systemImage: "checkmark.circle.fill")
            .font(.headline.weight(.semibold))
            .foregroundStyle(ElderDoseActionTone.completion.foregroundColor(for: colorScheme))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(ElderDoseActionTone.completion.foregroundColor(for: colorScheme).opacity(0.12), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("elder.feedback.success")
    }
}

enum ElderDoseActionProminence: Equatable {
    case primary
    case secondary
    case tertiary

    var font: Font {
        switch self {
        case .primary:
            return .title2.bold()
        case .secondary:
            return .title3.bold()
        case .tertiary:
            return .title3.weight(.semibold)
        }
    }

    var minimumHeight: CGFloat {
        switch self {
        case .primary:
            return 76
        case .secondary:
            return 68
        case .tertiary:
            return 60
        }
    }

    var visibleWidthRatio: CGFloat {
        switch self {
        case .primary:
            return 1
        case .secondary:
            return 0.92
        case .tertiary:
            return 0.80
        }
    }

    func contentWidth(availableWidth: CGFloat) -> CGFloat {
        max(0, availableWidth * visibleWidthRatio)
    }
}

private struct ElderDoseActionButton: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.colorScheme) private var colorScheme

    let title: String
    let systemImage: String
    let tone: ElderDoseActionTone
    let prominence: ElderDoseActionProminence
    let accessibilityIdentifier: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ElderDoseActionLabelLayout(
                visibleWidthRatio: dynamicTypeSize.isAccessibilitySize ? 1 : prominence.visibleWidthRatio,
                minimumHeight: prominence.minimumHeight
            ) {
                actionLabel
                    .font(prominence.font)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, dynamicTypeSize.isAccessibilitySize ? 16 : 10)
                    .padding(.vertical, 16)
                    .frame(minHeight: prominence.minimumHeight)
                    .foregroundStyle(prominence == .primary ? Color.white : tone.foregroundColor(for: colorScheme))
                    .background(actionBackground)
            }
            .frame(maxWidth: .infinity, minHeight: prominence.minimumHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(CompactDoseActionButtonStyle())
        .frame(maxWidth: .infinity, minHeight: prominence.minimumHeight)
        .contentShape(Rectangle())
        .accessibilityLabel(title)
        .accessibilityIdentifier(accessibilityIdentifier)
    }

    private var actionBackground: some View {
        (prominence == .primary ? tone.solidColor : tone.foregroundColor(for: colorScheme).opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    @ViewBuilder
    private var actionLabel: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(spacing: 6) {
                Image(systemName: systemImage)
                    .imageScale(.large)
                    .accessibilityHidden(true)
                Text(title)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } else {
            Label(title, systemImage: systemImage)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct ElderDoseActionLabelLayout: Layout {
    let visibleWidthRatio: CGFloat
    let minimumHeight: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let label = subviews.first else { return .zero }
        let intrinsicWidth = label.sizeThatFits(.unspecified).width
        let proposedWidth = proposal.width ?? intrinsicWidth
        let availableWidth = proposedWidth.isFinite ? max(0, proposedWidth) : intrinsicWidth
        let visibleWidth = availableWidth * visibleWidthRatio
        let labelSize = label.sizeThatFits(ProposedViewSize(width: visibleWidth, height: nil))
        // Text may wrap before Accessibility sizes too; its measured height defines the full-row hit region.
        return CGSize(width: availableWidth, height: max(minimumHeight, labelSize.height))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard let label = subviews.first else { return }
        label.place(
            at: CGPoint(x: bounds.midX, y: bounds.midY),
            anchor: .center,
            proposal: ProposedViewSize(width: bounds.width * visibleWidthRatio, height: bounds.height)
        )
    }
}

private struct ElderDoseConfirmationPanel: View {
    @Environment(\.colorScheme) private var colorScheme
    let kind: PendingDoseConfirmation.Kind
    let completionVerb: String
    let confirm: () -> Void
    let cancel: () -> Void

    private var tone: ElderDoseActionTone {
        kind == .earlyTaken ? .help : .reminder
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(kind.elderTitle(completionVerb: completionVerb), systemImage: kind.iconName)
                .font(.title2.bold())
                .foregroundStyle(tone.foregroundColor(for: colorScheme))
                .fixedSize(horizontal: false, vertical: true)
            if kind == .plannedDelay {
                Text("提醒时间按原计划延后 \(DoseDelayPolicy.delayMinutes) 分钟。")
                    .font(.title3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ElderDoseActionButton(
                title: kind.elderConfirmTitle(completionVerb: completionVerb),
                systemImage: "checkmark",
                tone: tone,
                prominence: .primary,
                accessibilityIdentifier: AppAccessibilityID.elderConfirmationConfirm,
                action: confirm
            )
            ElderDoseActionButton(
                title: "取消",
                systemImage: "xmark",
                tone: .neutral,
                prominence: .secondary,
                accessibilityIdentifier: AppAccessibilityID.elderConfirmationCancel,
                action: cancel
            )
        }
        .padding(16)
        .background(tone.foregroundColor(for: colorScheme).opacity(0.08), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityElement(children: .contain)
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
