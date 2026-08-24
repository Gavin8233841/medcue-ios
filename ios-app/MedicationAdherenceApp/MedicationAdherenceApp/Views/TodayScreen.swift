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
                        .snappy(duration: 0.28, extraBounce: 0.03),
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
                    .smooth(duration: 0.38, extraBounce: 0.04),
                    value: isCompletionRateFeedbackVisible
                )
                .animation(
                    .smooth(duration: 0.34, extraBounce: 0.03),
                    value: completionRateFeedback.id
                )
            }
        }
        .frame(height: completionRateFeedbackSlotHeight, alignment: .top)
        .accessibilityHidden(true)
        .allowsHitTesting(false)
        .animation(
            .smooth(duration: 0.38, extraBounce: 0.03),
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
            .smooth(duration: 0.30, extraBounce: 0.02),
            value: snapshot.visibleOpenTimelineTasks.map(\.id)
        )
        .animation(.easeInOut(duration: 0.16), value: pendingDoseFeedback)
        .animation(
            .snappy(duration: 0.24, extraBounce: 0.01),
            value: isOpenTimelineTemporarilyCollapsed
        )
        .animation(.easeInOut(duration: 0.18), value: closingOpenDoseKeys)
        .animation(
            .snappy(duration: 0.24, extraBounce: 0.02),
            value: recentlyReopenedDoseKeys
        )
        .accessibilityIdentifier(AppAccessibilityID.todayOpenTimeline)
    }

    private var handledTimelineSection: some View {
        todaySection("今日已处理") {
            let isExpanded = handledDisclosureBinding.wrappedValue
            let value = "\(snapshot.displayedHandledCount) 条，\(snapshot.handledSummaryText)，\(isExpanded ? "已展开" : "已折叠")"
            Button {
                withAnimation(.snappy(duration: 0.24, extraBounce: 0.01)) {
                    showingHandledTasks.toggle()
                }
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
            isDoseListReparenting
                ? nil
                : .snappy(duration: 0.22, extraBounce: 0.01),
            value: snapshot.handledTodayTasks.map(\.id)
        )
        .animation(
            .snappy(duration: 0.22, extraBounce: 0.01),
            value: isHandledTimelineTemporarilyCollapsed
        )
        .animation(.easeInOut(duration: 0.18), value: reopeningHandledDoseKeys)
        .animation(.easeInOut(duration: 0.2), value: handledDropTargetPulse)
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
    let openSettings: () -> Void
    let switchToCompleteMode: () -> Void
    let initialLoad: () async -> Void
    let timerTick: () -> Void
    let becameActive: () -> Void
    let cleanup: () -> Void
}

struct ElderTodayScreen: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let snapshot: ElderTodayRenderSnapshot
    let pendingDoseConfirmation: PendingDoseConfirmation?
    let pendingDoseFeedback: PendingDoseFeedback?
    @Binding var dosePersistenceErrorMessage: String?
    @Binding var helpOpeningErrorMessage: String?
    let actions: ElderTodayScreenActions
    private let liveActivityRefreshTimer = Timer
        .publish(every: 60, on: .main, in: .common)
        .autoconnect()

    private var activeConfirmation: PendingDoseConfirmation.Kind? {
        guard let task = snapshot.currentTask,
              pendingDoseConfirmation?.doseKey == actions.logicalDoseKey(task)
        else {
            return nil
        }
        return pendingDoseConfirmation?.kind
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if let task = snapshot.currentTask {
                    currentTaskCard(task)
                    if snapshot.remainingOpenTaskCount > 0 {
                        Text("还有 \(snapshot.remainingOpenTaskCount) 项待处理")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } else {
                    ContentUnavailableView("目前没有待处理用药", systemImage: "checkmark.circle")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 32)
                    .accessibilityElement(children: .combine)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 24)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("用药提醒")
        .navigationBarTitleDisplayMode(.inline)
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
        .onReceive(liveActivityRefreshTimer) { _ in
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
        } message: {
            Text(helpOpeningErrorMessage ?? "请在同机设置中检查帮助号码后重试。")
        }
        .onDisappear(perform: actions.cleanup)
    }

    private func currentTaskCard(_ task: StoredDoseTask) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            taskIdentity(task)

            if let confirmationKind = activeConfirmation {
                ElderDoseConfirmationPanel(
                    kind: confirmationKind,
                    confirm: { actions.confirm(task) },
                    cancel: { actions.cancelConfirmation(task) }
                )
            } else {
                VStack(spacing: 14) {
                    ElderDoseActionButton(
                        title: actions.completionVerb(snapshot.currentMedication),
                        systemImage: "checkmark.circle.fill",
                        tint: .green,
                        isProminent: true,
                        accessibilityIdentifier: AppAccessibilityID.elderMarkTaken,
                        action: { actions.markTaken(task) }
                    )
                    ElderDoseActionButton(
                        title: "\(DoseDelayPolicy.delayMinutes) 分钟后提醒",
                        systemImage: "clock.arrow.circlepath",
                        tint: .blue,
                        isProminent: false,
                        accessibilityIdentifier: AppAccessibilityID.elderDelay,
                        action: { actions.delay(task) }
                    )
                    ElderDoseActionButton(
                        title: "需要帮助",
                        systemImage: "phone.fill",
                        tint: .orange,
                        isProminent: false,
                        accessibilityIdentifier: AppAccessibilityID.elderRequestHelp,
                        action: actions.requestHelp
                    )
                }
                .disabled(pendingDoseFeedback?.doseKey == actions.logicalDoseKey(task))
            }
        }
        .padding(20)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.blue.opacity(0.16), lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(AppAccessibilityID.elderCurrentTask)
    }

    @ViewBuilder
    private func taskIdentity(_ task: StoredDoseTask) -> some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 16) {
                medicationPhoto
                taskDetails(task)
            }
        } else {
            HStack(alignment: .top, spacing: 16) {
                medicationPhoto
                taskDetails(task)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var medicationPhoto: some View {
        MedicationPhotoView(
            photoData: snapshot.currentMedication?.photoData,
            symbolName: snapshot.currentMedication?.photoSymbolName ?? "pills.fill",
            tint: snapshot.currentMedication.map(medicationColor(for:)) ?? .blue,
            size: 88
        )
    }

    private func taskDetails(_ task: StoredDoseTask) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(snapshot.currentMedication.map(userFacingMedicationName(for:)) ?? "待核对药品")
                .font(.title.bold())
                .fixedSize(horizontal: false, vertical: true)

            if let currentStatus = snapshot.currentStatus {
                Text(currentStatus.displayName)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.blue)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.blue.opacity(0.12), in: Capsule())
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text("每次 \(task.doseValue.formatted()) \(localizedMedicationUnit(task.doseUnit))")
                .font(.title3.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)

            Label(AppFormatters.time.string(from: task.dueAt), systemImage: "clock")
                .font(.title3)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct ElderDoseActionButton: View {
    let title: String
    let systemImage: String
    let tint: Color
    let isProminent: Bool
    let accessibilityIdentifier: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.title3.weight(.bold))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 64)
                .padding(.horizontal, 12)
                .foregroundStyle(isProminent ? Color.white : tint)
                .background(
                    isProminent ? tint : tint.opacity(0.12),
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                )
        }
        .buttonStyle(CompactDoseActionButtonStyle())
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityIdentifier(accessibilityIdentifier)
    }
}

private struct ElderDoseConfirmationPanel: View {
    let kind: PendingDoseConfirmation.Kind
    let confirm: () -> Void
    let cancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(kind.title, systemImage: kind.iconName)
                .font(.title2.bold())
                .foregroundStyle(kind.tint)
                .fixedSize(horizontal: false, vertical: true)
            Text(kind.message(delayDurationText: "\(DoseDelayPolicy.delayMinutes) 分钟"))
                .font(.title3)
                .fixedSize(horizontal: false, vertical: true)
            ElderDoseActionButton(
                title: kind.confirmTitle,
                systemImage: "checkmark",
                tint: kind.tint,
                isProminent: true,
                accessibilityIdentifier: AppAccessibilityID.elderConfirmationConfirm,
                action: confirm
            )
            ElderDoseActionButton(
                title: "取消",
                systemImage: "xmark",
                tint: .gray,
                isProminent: false,
                accessibilityIdentifier: AppAccessibilityID.elderConfirmationCancel,
                action: cancel
            )
        }
        .padding(16)
        .background(kind.tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
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
