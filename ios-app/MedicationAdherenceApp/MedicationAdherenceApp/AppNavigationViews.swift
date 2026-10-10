import SwiftData
import SwiftUI

enum AppAccessibilityID {
    static let tabToday = "tab.today"
    static let tabMedications = "tab.medications"
    static let tabAssistant = "tab.assistant"
    static let tabRecords = "tab.records"
    static let tabProfile = "tab.profile"
    static let profileRoot = "profile.root"
    static let todayOpenTimeline = "today.timeline.open"
    static let todayHandledTimeline = "today.timeline.handled"
    static let todayTimelineTaken = "today.timeline.action.taken"
    static let todayTimelineDelay = "today.timeline.action.delay"
    static let todayTimelineSkip = "today.timeline.action.skip"
    static let todayTimelineConfirmationConfirm = "today.timeline.confirmation.confirm"
    static let todayTimelineConfirmationCancel = "today.timeline.confirmation.cancel"
    static let medicationAdd = "medication.add"
    static let medicationEditSave = "medication.edit.save"
    static let medicationPlanSave = "medication.plan.save"
    static let assistantArchive = "assistant.archive"
    static let assistantInput = "assistant.input"
    static let assistantSend = "assistant.send"
    static let firstLaunchSkip = "firstLaunch.skip"
    static let firstLaunchNext = "firstLaunch.next"
    static let settingsExperienceMode = "settings.experience-mode"
    static let elderHome = "elder.home"
    static let elderCurrentTask = "elder.current-task"
    static let elderMarkTaken = "elder.action.taken"
    static let elderDelay = "elder.action.delay"
    static let elderRequestHelp = "elder.action.help"
    static let elderConfirmationConfirm = "elder.confirmation.confirm"
    static let elderConfirmationCancel = "elder.confirmation.cancel"
    static let elderOpenSettings = "elder.settings"
    static let elderSwitchToComplete = "elder.switch-to-complete"
}

enum AppExperienceMode: String, CaseIterable, Identifiable {
    static let storageKey = "appExperienceMode"
    static let firstLaunchChoiceKey = "hasResolvedFirstLaunchExperienceMode"

    case complete
    case elder

    var id: String { rawValue }

    static func resolve(_ rawValue: String) -> Self {
        Self(rawValue: rawValue) ?? .complete
    }

    var displayName: String {
        switch self {
        case .complete:
            "完整模式"
        case .elder:
            "适老模式"
        }
    }
}

enum AppExperienceModeRequestSource: Equatable {
    case settings, elderExit, firstLaunch
}

struct AppExperienceModeRequest: Identifiable, Equatable {
    let id = UUID()
    let current: AppExperienceMode
    let target: AppExperienceMode
    let source: AppExperienceModeRequestSource

    var title: String { target == .elder ? "启用适老模式？" : "返回完整模式？" }
    var confirmationTitle: String { target == .elder ? "启用适老模式" : "返回完整模式" }
    var message: String {
        target == .elder
            ? "首页将突出当前任务和大按钮。你可以在设置中切回完整模式。"
            : "将显示今日、药品、智能体、记录和个人页面。用药记录不会改变。"
    }
}

/// Owns only a UI request. Persistence and medical actions remain outside it.
struct AppExperienceModeTransition {
    private(set) var pending: AppExperienceModeRequest?

    mutating func request(
        _ target: AppExperienceMode,
        current: AppExperienceMode,
        source: AppExperienceModeRequestSource
    ) -> AppExperienceModeRequest? {
        guard pending == nil, target != current || (source == .firstLaunch && target == .elder) else { return nil }
        let request = AppExperienceModeRequest(current: current, target: target, source: source)
        pending = request
        return request
    }

    mutating func confirm(
        _ id: UUID,
        current: AppExperienceMode,
        canCommit: Bool
    ) -> AppExperienceModeRequest? {
        guard let request = pending, request.id == id else { return nil }
        pending = nil
        guard canCommit, request.current == current else { return nil }
        return request
    }

    mutating func cancel(_ id: UUID? = nil) {
        guard id == nil || pending?.id == id else { return }
        pending = nil
    }
}

/// These callbacks read live page state again when the root commits a mode.
struct AppExperienceModeRequestGuard {
    var canCommit: @MainActor () -> Bool = { true }
    var onBlocked: @MainActor () -> Void = {}
}

private struct PendingExperienceModeKey: EnvironmentKey {
    static let defaultValue: AppExperienceModeRequest? = nil
}
private struct RequestExperienceModeKey: EnvironmentKey {
    static let defaultValue: @MainActor (AppExperienceMode, AppExperienceModeRequestSource, AppExperienceModeRequestGuard) -> Void = { _, _, _ in }
}
private struct ConfirmExperienceModeKey: EnvironmentKey {
    static let defaultValue: @MainActor (UUID) -> Void = { _ in }
}
private struct CancelExperienceModeKey: EnvironmentKey {
    static let defaultValue: @MainActor (UUID) -> Void = { _ in }
}

extension EnvironmentValues {
    var pendingExperienceMode: AppExperienceModeRequest? {
        get { self[PendingExperienceModeKey.self] }
        set { self[PendingExperienceModeKey.self] = newValue }
    }
    var requestExperienceMode: @MainActor (AppExperienceMode, AppExperienceModeRequestSource, AppExperienceModeRequestGuard) -> Void {
        get { self[RequestExperienceModeKey.self] }
        set { self[RequestExperienceModeKey.self] = newValue }
    }
    var confirmExperienceMode: @MainActor (UUID) -> Void {
        get { self[ConfirmExperienceModeKey.self] }
        set { self[ConfirmExperienceModeKey.self] = newValue }
    }
    var cancelExperienceMode: @MainActor (UUID) -> Void {
        get { self[CancelExperienceModeKey.self] }
        set { self[CancelExperienceModeKey.self] = newValue }
    }
}

private struct ExperienceModeConfirmation: ViewModifier {
    @Environment(\.pendingExperienceMode) private var pending
    @Environment(\.confirmExperienceMode) private var confirm
    @Environment(\.cancelExperienceMode) private var cancel
    let source: AppExperienceModeRequestSource

    private var request: AppExperienceModeRequest? {
        pending?.source == source ? pending : nil
    }

    func body(content: Content) -> some View {
        content.alert(
            request?.title ?? "切换使用模式？",
            isPresented: Binding(
                get: { request != nil },
                // A native alert can clear presentation before invoking its
                // button. Only the explicit action consumes this request;
                // host dismissal and backgrounding cancel it separately.
                set: { _ in }
            ),
            presenting: request
        ) { request in
            Button(request.confirmationTitle) { confirm(request.id) }
                .accessibilityIdentifier("experience-mode.confirm")
            Button("取消", role: .cancel) { cancel(request.id) }
                .accessibilityIdentifier("experience-mode.cancel")
        } message: { request in
            Text(request.message)
        }
        .onDisappear { if let request { cancel(request.id) } }
    }
}

extension View {
    func appExperienceModeConfirmation(source: AppExperienceModeRequestSource) -> some View {
        modifier(ExperienceModeConfirmation(source: source))
    }
}

struct AppTabContentView: View, Equatable {
    let tab: AppTab
    let isLoaded: Bool

    var body: some View {
        if isLoaded {
            tab.content
        } else {
            Color.clear
        }
    }
}

enum AppColorSchemePreference: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system:
            "跟随系统"
        case .light:
            "浅色"
        case .dark:
            "深色"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system:
            nil
        case .light:
            .light
        case .dark:
            .dark
        }
    }
}

enum AppTab: String, CaseIterable, Identifiable, Hashable {
    case today
    case medications
    case assistant
    case records
    case profile

    var id: String { rawValue }

    var accessibilityIdentifier: String {
        switch self {
        case .today:
            AppAccessibilityID.tabToday
        case .medications:
            AppAccessibilityID.tabMedications
        case .assistant:
            AppAccessibilityID.tabAssistant
        case .records:
            AppAccessibilityID.tabRecords
        case .profile:
            AppAccessibilityID.tabProfile
        }
    }

    @MainActor
    @ViewBuilder
    var content: some View {
        switch self {
        case .today:
            TodayView()
        case .medications:
            MedicationsView()
        case .assistant:
            AIAssistantView()
        case .records:
            RecordsView(hidesTabBar: false)
        case .profile:
            ProfileView()
        }
    }

    @ViewBuilder
    var label: some View {
        switch self {
        case .today:
            Label("今日", systemImage: "calendar")
        case .medications:
            Label("药品", systemImage: "pills")
        case .assistant:
            Label("智能体", systemImage: "stethoscope")
        case .records:
            Label("记录", systemImage: "calendar.badge.clock")
        case .profile:
            Label("个人", systemImage: "person.crop.circle")
        }
    }
}

final class AppTabTopGradientState: ObservableObject {
    @Published private(set) var selectedTab: AppTab = .today
    @Published private var progressByTab: [AppTab: CGFloat] = [:]

    func select(_ tab: AppTab) {
        guard selectedTab != tab else {
            return
        }
        selectedTab = tab
    }

    func progress(for tab: AppTab) -> CGFloat {
        progressByTab[tab] ?? 1
    }

    func updateProgress(for tab: AppTab, progress: CGFloat, activeTab: AppTab) {
        guard tab == activeTab else {
            return
        }
        let clampedProgress = max(0, min(1, progress))
        let quantizedProgress = (clampedProgress * 6).rounded() / 6
        let previousProgress = progressByTab[tab] ?? 1
        guard abs(previousProgress - quantizedProgress) > 0.14 else {
            return
        }
        progressByTab[tab] = quantizedProgress
    }
}

struct AppTabTopGradientOverlay: View {
    @ObservedObject var state: AppTabTopGradientState
    @Environment(\.colorScheme) private var colorScheme

    private var tab: AppTab {
        state.selectedTab
    }

    private var progress: CGFloat {
        state.progress(for: tab)
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .topLeading) {
                Rectangle()
                    .fill(
                        LinearGradient(
                            gradient: Gradient(stops: atmosphericStops),
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(height: overlayHeight)

                LinearGradient(
                    gradient: Gradient(stops: colorWashStops),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .frame(height: colorWashHeight)
                .mask(
                    LinearGradient(
                        colors: [.black, .black.opacity(0.72), .clear],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

                RadialGradient(
                    colors: [
                        paletteColors.leading.opacity(leadingGlowOpacity),
                        paletteColors.leading.opacity(leadingGlowOpacity * 0.34),
                        Color.clear
                    ],
                    center: .topLeading,
                    startRadius: 0,
                    endRadius: colorScheme == .dark ? 210 : 185
                )
                .frame(height: colorWashHeight)
                .offset(x: -18, y: -24)

                RadialGradient(
                    colors: [
                        paletteColors.trailing.opacity(trailingGlowOpacity),
                        paletteColors.trailing.opacity(trailingGlowOpacity * 0.28),
                        Color.clear
                    ],
                    center: .topTrailing,
                    startRadius: 0,
                    endRadius: colorScheme == .dark ? 230 : 205
                )
                .frame(height: colorWashHeight)
                .offset(x: 18, y: -28)
            }
            .frame(height: overlayHeight)
            .opacity(Double(max(0, min(1, progress))) * overallOpacity)
            .blendMode(colorScheme == .dark ? .screen : .multiply)
            .animation(.smooth(duration: 0.22), value: tab)
            .transaction { transaction in
                transaction.animation = nil
            }

            Spacer(minLength: 0)
        }
        .ignoresSafeArea()
    }

    private var atmosphericStops: [Gradient.Stop] {
        [
            .init(color: paletteColors.background.opacity(colorScheme == .dark ? 0.40 : 0.88), location: 0.00),
            .init(color: paletteColors.background.opacity(colorScheme == .dark ? 0.22 : 0.58), location: 0.50),
            .init(color: Color.clear, location: 1.00)
        ]
    }

    private var colorWashStops: [Gradient.Stop] {
        [
            .init(color: paletteColors.leading.opacity(colorScheme == .dark ? 0.24 : 0.46), location: 0.00),
            .init(color: paletteColors.trailing.opacity(colorScheme == .dark ? 0.16 : 0.36), location: 0.54),
            .init(color: Color.clear, location: 1.00)
        ]
    }

    private var overlayHeight: CGFloat {
        colorScheme == .dark ? 214 : 230
    }

    private var colorWashHeight: CGFloat {
        colorScheme == .dark ? 168 : 184
    }

    private var leadingGlowOpacity: Double {
        colorScheme == .dark ? 0.24 : 0.42
    }

    private var trailingGlowOpacity: Double {
        colorScheme == .dark ? 0.18 : 0.32
    }

    private var overallOpacity: Double {
        if tab == .assistant {
            return colorScheme == .dark ? 0.52 : 0.50
        }
        return colorScheme == .dark ? 0.90 : 0.86
    }

    private var paletteColors: AppTabTopGradientPalette {
        switch tab {
        case .today:
            AppTabTopGradientPalette(
                leading: Color(red: 0.42, green: 0.82, blue: 0.96),
                trailing: Color(red: 0.32, green: 0.66, blue: 0.98),
                background: Color(red: 0.82, green: 0.95, blue: 0.96)
            )
        case .medications:
            AppTabTopGradientPalette(
                leading: Color(red: 0.38, green: 0.86, blue: 0.72),
                trailing: Color(red: 0.38, green: 0.62, blue: 0.98),
                background: Color(red: 0.82, green: 0.95, blue: 0.90)
            )
        case .assistant:
            AppTabTopGradientPalette(
                leading: Color(red: 0.54, green: 0.66, blue: 0.76),
                trailing: Color(red: 0.70, green: 0.75, blue: 0.79),
                background: Color(red: 0.91, green: 0.94, blue: 0.96)
            )
        case .records:
            AppTabTopGradientPalette(
                leading: Color(red: 0.50, green: 0.62, blue: 0.98),
                trailing: Color(red: 0.42, green: 0.86, blue: 0.80),
                background: Color(red: 0.84, green: 0.93, blue: 0.94)
            )
        case .profile:
            AppTabTopGradientPalette(
                leading: Color(red: 0.96, green: 0.70, blue: 0.42),
                trailing: Color(red: 0.84, green: 0.54, blue: 0.78),
                background: Color(red: 0.97, green: 0.88, blue: 0.82)
            )
        }
    }
}

struct AppTabTopGradientPalette {
    let leading: Color
    let trailing: Color
    let background: Color
}
