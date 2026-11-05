import Combine
import ImageIO
import MedicationAdherenceCore
import SwiftUI
import UIKit

struct ElderTodayScreenActions {
    let logicalDoseKey: (StoredDoseTask) -> String
    let completionVerb: (StoredMedication?) -> String
    let markTaken: (StoredDoseTask) -> Void
    let delay: (StoredDoseTask) -> Void
    let skip: (StoredDoseTask) -> Void
    let undoSuccess: (UUID) -> Void
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
    @State private var medicationPhotoPreview: ElderMedicationPhotoPreview?
    @ScaledMetric(relativeTo: .title2) private var elderTitlePointSize: CGFloat = 34
    let snapshot: ElderTodayRenderSnapshot
    let pendingDoseConfirmation: PendingDoseConfirmation?
    let pendingDoseFeedback: PendingDoseFeedback?
    let inFlightDoseKeys: Set<String>
    @Binding var dosePersistenceErrorMessage: String?
    @Binding var helpOpeningErrorMessage: String?
    @Binding var helpMissingMessage: String?
    @Binding var helpConfirmationPhone: ElderHelpPhoneNumber?
    @Binding var successFeedback: ElderDoseSuccessState?
    let currentTime: Date
    let notificationUnavailableMessage: String
    let loadErrorMessage: String?
    let isLoading: Bool
    let actions: ElderTodayScreenActions
    @State private var showingExitConfirmation = false
    @State private var showingHelpCenter = false
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
        elderContent
            .alert("退出适老模式？", isPresented: $showingExitConfirmation) {
                Button("取消", role: .cancel) {}
                Button("退出") { actions.switchToCompleteMode() }
            }
            .sheet(isPresented: $showingHelpCenter) { HelpCenterView() }
    }

    private var elderContent: some View {
        GeometryReader { geometry in
            ScrollViewReader { scrollProxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
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
                                    .foregroundStyle(Color.primary.opacity(0.7))
                                    .frame(maxWidth: .infinity, alignment: .center)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        } else {
                            elderEmptyState
                                .frame(maxWidth: .infinity)
                        }
                        if let successFeedback {
                            ElderDoseSuccessFeedback(
                                feedback: successFeedback,
                                currentTime: currentTime,
                                undo: { taskID in actions.undoSuccess(taskID) }
                            )
                                .transition(.opacity)
                                .accessibilityFocused($accessibilityFocus, equals: .success)
                        }
                        reminderWarning
                    }
                    .id("elder.task.top")
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 28)
                }
                .accessibilityIdentifier("elder.scroll")
                .onChange(of: snapshot.currentTask?.id) { _, _ in
                    scrollProxy.scrollTo("elder.task.top", anchor: .top)
                }
            }
        }
        .background(Color(.systemGroupedBackground))
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if loadErrorMessage == nil, let task = snapshot.currentTask {
                taskActions(task)
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 8)
                    .background(Color(.systemGroupedBackground))
                    .overlay(alignment: .top) { Divider() }
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("elder.actions")
            }
        }
        .sheet(item: $medicationPhotoPreview) { preview in
            NavigationStack {
                GeometryReader { geometry in
                    ScrollView {
                        ElderMedicationPhotoView(
                            photoData: preview.data,
                            medicationName: preview.medicationName,
                            width: max(0, geometry.size.width - 40)
                        )
                        .padding(20)
                    }
                }
                .navigationTitle(preview.medicationName ?? "药品照片")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("完成") { medicationPhotoPreview = nil }
                            .accessibilityIdentifier("elder.photo.close")
                    }
                }
            }
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
            ToolbarItem(placement: .topBarTrailing) {
                Button { showingExitConfirmation = true } label: {
                    if dynamicTypeSize.isAccessibilitySize {
                        Image(systemName: "arrow.backward")
                    } else {
                        Text("完整模式")
                    }
                }
                .accessibilityLabel("完整模式")
                .accessibilityIdentifier(AppAccessibilityID.elderSwitchToComplete)
            }
            ToolbarItemGroup(placement: .topBarLeading) {
                Button(action: actions.openSettings) {
                    Label("设置", systemImage: "gearshape")
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
            "帮助暂不可用",
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
        .onChange(of: successFeedback) { _, feedback in
            guard let feedback else { return }
            UIAccessibility.post(notification: .announcement, argument: feedback.message)
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
            let opensSettings = message.contains("权限")
                || message.contains("系统设置") || message.contains("通知设置")
            if opensSettings {
                Button(action: actions.openNotificationSettings) {
                    reminderWarningCard(message: message, showsSettingsAction: true)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("elder.reminder.settings")
            } else {
                reminderWarningCard(message: message, showsSettingsAction: false)
                    .accessibilityIdentifier("elder.reminder.warning")
            }
        }
    }

    private func reminderWarningCard(message: String, showsSettingsAction: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(message, systemImage: "bell.slash.fill")
                .font(.title3.bold())
            if showsSettingsAction {
                Label("打开系统设置", systemImage: "gearshape")
                    .font(.title3.bold())
            }
        }
        .foregroundStyle(.primary)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
        .padding(16)
        .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .combine)
    }

    private func currentTaskCard(_ task: StoredDoseTask, availableWidth: CGFloat) -> some View {
        taskIdentity(task, availableWidth: availableWidth)
            .padding(isAccessibilityLayout ? ElderTaskLayoutMetrics.accessibilityCardPadding : ElderTaskLayoutMetrics.regularCardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier(AppAccessibilityID.elderCurrentTask)
    }

    @ViewBuilder
    private func taskActions(_ task: StoredDoseTask) -> some View {
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
                    requiresHold: true,
                    action: { actions.markTaken(task) }
                )
                ElderDoseActionButton(
                    title: "\(DoseDelayPolicy.delayMinutes) 分钟后",
                    systemImage: "clock.arrow.circlepath",
                    tone: .reminder,
                    prominence: .secondary,
                    accessibilityIdentifier: AppAccessibilityID.elderDelay,
                    requiresHold: true,
                    action: { actions.delay(task) }
                )
                .accessibilityLabel("\(DoseDelayPolicy.delayMinutes) 分钟后提醒")
                ElderDoseActionButton(
                    title: "使用帮助",
                    systemImage: "questionmark.circle",
                    tone: .help,
                    prominence: .tertiary,
                    accessibilityIdentifier: AppAccessibilityID.elderRequestHelp,
                    action: { showingHelpCenter = true }
                )
            }
            .disabled(
                pendingDoseFeedback?.doseKey == actions.logicalDoseKey(task)
                    || inFlightDoseKeys.contains(actions.logicalDoseKey(task))
            )
        }
    }

    @ViewBuilder
    private func taskIdentity(_ task: StoredDoseTask, availableWidth: CGFloat) -> some View {
        if isAccessibilityLayout {
            compactTaskIdentity(task, availableWidth: availableWidth)
        } else {
            VStack(spacing: 16) {
                medicationPhotoButton(availableWidth: availableWidth)
                taskDetails(task, centered: true)
                taskSchedule(task, centered: true)
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func medicationPhotoButton(availableWidth: CGFloat) -> some View {
        Button {
            guard let data = snapshot.currentMedication?.photoData else { return }
            medicationPhotoPreview = ElderMedicationPhotoPreview(
                data: data,
                medicationName: snapshot.currentMedication.map(userFacingMedicationName(for:))
            )
        } label: {
            medicationPhoto(size: medicationPhotoWidth(for: availableWidth))
                .overlay(alignment: .bottomTrailing) {
                    if snapshot.currentMedication?.photoData != nil {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(.system(size: 14, weight: .semibold))
                            .padding(6)
                            .background(.regularMaterial, in: Circle())
                            .padding(4)
                            .accessibilityHidden(true)
                    }
                }
        }
        .buttonStyle(.plain)
        .disabled(snapshot.currentMedication?.photoData == nil)
        .accessibilityLabel(snapshot.currentMedication?.photoData == nil ? "尚未添加药品照片" : "查看药品照片")
        .accessibilityHint(snapshot.currentMedication?.photoData == nil ? "" : "放大查看当前药品的照片")
        .accessibilityIdentifier("elder.photo.open")
    }

    private func compactTaskIdentity(_ task: StoredDoseTask, availableWidth: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                taskDetails(task, centered: false, showsStatus: !isAccessibilityLayout)
                medicationPhotoButton(availableWidth: availableWidth)
            }
            if isAccessibilityLayout {
                doseText(task)
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    taskStatus
                    Spacer(minLength: 0)
                    Text(AppFormatters.time.string(from: task.dueAt))
                        .font(.body)
                        .foregroundStyle(Color.primary.opacity(0.7))
                        .fixedSize(horizontal: true, vertical: true)
                }
                .accessibilityElement(children: .combine)
            } else {
                taskSchedule(task, centered: false)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func medicationPhoto(size: CGFloat) -> some View {
        ElderMedicationPhotoView(
            photoData: snapshot.currentMedication?.photoData,
            medicationName: snapshot.currentMedication.map(userFacingMedicationName(for:)),
            width: size,
            usesDemoVitaminPhoto: snapshot.currentMedication.map { $0.isDemoContent && $0.displayName.localizedCaseInsensitiveContains("D3") } ?? false
        )
        .id(snapshot.currentMedication?.id)
    }

    private func taskDetails(_ task: StoredDoseTask, centered: Bool, showsStatus: Bool = true) -> some View {
        VStack(alignment: centered ? .center : .leading, spacing: 8) {
            Text(snapshot.currentMedication.map(userFacingMedicationName(for:)) ?? "待核对药品")
                .font(.system(size: elderTitlePointSize, weight: .bold))
                .multilineTextAlignment(centered ? .center : .leading)
                .fixedSize(horizontal: false, vertical: true)

            if showsStatus { taskStatus }

        }
        .frame(maxWidth: .infinity, alignment: centered ? .center : .leading)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var taskStatus: some View {
        if let currentStatus = snapshot.currentStatus {
            let fullTitle = currentStatus == .pendingBeforeDue && actions.completionVerb(snapshot.currentMedication) == "已使用"
                ? "待使用" : currentStatus.displayName
            let compactTitle = currentStatus == .delayedBeforeDue ? "已延后"
                : currentStatus == .delayedAtOrAfterDue ? "未确认" : fullTitle
            Text(isAccessibilityLayout ? compactTitle : fullTitle)
                .accessibilityLabel(fullTitle)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(ElderDoseActionTone.reminder.foregroundColor(for: colorScheme))
                .padding(.horizontal, isAccessibilityLayout ? 4 : 10)
                .padding(.vertical, isAccessibilityLayout ? 4 : 6)

                .fixedSize(horizontal: false, vertical: true)
        }
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
            .font(.title.weight(.semibold))
            .fixedSize(horizontal: false, vertical: true)
    }

    private func timeText(_ task: StoredDoseTask) -> some View {
        Label(AppFormatters.time.string(from: task.dueAt), systemImage: "clock")
            .font(.body)
            .foregroundStyle(Color.primary.opacity(0.7))
            .fixedSize(horizontal: false, vertical: true)
    }
}

enum ElderTaskLayoutMetrics {
    // Prioritize recognition with a large photo in the standard elder layout.
    static let regularPhotoWidth: CGFloat = 200
    static let regularPhotoMinimumWidth: CGFloat = 64
    static let accessibilityPhotoWidth: CGFloat = 64
    // Keep user-supplied portrait packaging from being narrowed by an overly wide frame.
    static let photoContainerAspectRatio: CGFloat = 1.25
    static let regularCardPadding: CGFloat = 18
    static let accessibilityCardPadding: CGFloat = 16
    static let regularIdentitySpacing: CGFloat = 12
    static let regularDetailsSpacing: CGFloat = 12
    static let accessibilityIdentitySpacing: CGFloat = 16
    static let actionSpacing: CGFloat = 8

    static func regularPhotoWidth(for availableWidth: CGFloat) -> CGFloat {
        let contentWidth = max(0, availableWidth - (2 * 16) - (2 * regularCardPadding))
        return min(max(contentWidth * 0.68, regularPhotoMinimumWidth), min(regularPhotoWidth, contentWidth))
    }

    static func accessibilityPhotoWidth(for availableWidth: CGFloat) -> CGFloat {
        let contentWidth = max(0, availableWidth - (2 * 16) - (2 * accessibilityCardPadding))
        return min(accessibilityPhotoWidth, contentWidth)
    }
}

// Keep the selected photo stable if the current task changes while its sheet is open.
private struct ElderMedicationPhotoPreview: Identifiable {
    let id = UUID()
    let data: Data
    let medicationName: String?
}

private enum ElderAccessibilityFocus: Hashable {
    case confirmation
    case success
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


private struct ElderDoseActionButton: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("prefersReducedAppMotion") private var prefersReducedAppMotion = false
    @GestureState private var isHolding = false
    @State private var showingAccessibleConfirmation = false
    @State private var holdFeedback = UIImpactFeedbackGenerator(style: .light)

    let title: String
    let systemImage: String
    let tone: ElderDoseActionTone
    let prominence: ElderDoseActionProminence
    let accessibilityIdentifier: String
    var requiresHold: Bool = false
    let action: () -> Void

    var body: some View {
        Button {
            if !requiresHold { action() }
        } label: {
            ElderDoseActionLabelLayout(
                visibleWidthRatio: 1,
                minimumHeight: prominence.minimumHeight
            ) {
                actionLabel
                    .font(prominence.font)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, dynamicTypeSize.isAccessibilitySize ? 16 : 10)
                    .padding(.vertical, dynamicTypeSize.isAccessibilitySize ? 10 : 16)
                    .frame(minHeight: prominence.minimumHeight)
                    .foregroundStyle(prominence == .primary ? Color.white : tone.foregroundColor(for: colorScheme))
                    .background(actionBackground)
            }
            .frame(maxWidth: .infinity, minHeight: prominence.minimumHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 1.2, maximumDistance: 36)
                .updating($isHolding) { pressing, state, _ in state = pressing }
                .onEnded { _ in
                    guard requiresHold, isEnabled, scenePhase == .active else { return }
                    holdFeedback.impactOccurred(intensity: 0.85)
                    action()
                },
            isEnabled: requiresHold && isEnabled
        )
        .onChange(of: isHolding) { _, holding in
            guard holding, isEnabled, scenePhase == .active else { return }
            holdFeedback.impactOccurred(intensity: 0.4)
            holdFeedback.prepare()
        }
        .scaleEffect(isHolding && !reduceMotion && !prefersReducedAppMotion ? 1.025 : 1)
        .animation(.easeOut(duration: 0.16), value: isHolding)
        .frame(maxWidth: .infinity, minHeight: prominence.minimumHeight)
        .contentShape(Rectangle())
        .accessibilityLabel(title)
        .accessibilityHint(requiresHold ? "长按至进度填满后执行，松手取消" : "")
        .accessibilityAction {
            if requiresHold { showingAccessibleConfirmation = true } else { action() }
        }
        .accessibilityIdentifier(accessibilityIdentifier)
        .alert("确认\(title)？", isPresented: $showingAccessibleConfirmation) {
            Button("取消", role: .cancel) {}
            Button("确认") { if isEnabled { action() } }
        }
    }

    private var actionBackground: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                (prominence == .primary ? tone.solidColor : tone.foregroundColor(for: colorScheme).opacity(0.12))
                Rectangle()
                    .fill(prominence == .primary ? Color.white.opacity(0.25) : tone.foregroundColor(for: colorScheme).opacity(0.22))
                    .frame(width: isHolding ? geometry.size.width : 0)
                    .animation(isHolding ? .linear(duration: 1.2) : .easeOut(duration: 0.12), value: isHolding)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var actionLabel: some View {
        VStack(spacing: 6) {
            if dynamicTypeSize.isAccessibilitySize {
                Text(title).fixedSize(horizontal: false, vertical: true)
            } else {
                Label(title, systemImage: systemImage)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if requiresHold && isHolding {
                Text("保持按住，松手取消")
                    .font(.caption)
                    .opacity(0.85)
                    .accessibilityHidden(true)
            }
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
