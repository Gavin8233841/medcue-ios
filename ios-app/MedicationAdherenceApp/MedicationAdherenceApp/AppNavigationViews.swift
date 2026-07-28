import SwiftData
import SwiftUI

enum AppAccessibilityID {
    static let tabToday = "tab.today"
    static let tabMedications = "tab.medications"
    static let tabAssistant = "tab.assistant"
    static let tabRecords = "tab.records"
    static let tabProfile = "tab.profile"
    static let todayOpenTimeline = "today.timeline.open"
    static let todayHandledTimeline = "today.timeline.handled"
    static let medicationAdd = "medication.add"
    static let medicationEditSave = "medication.edit.save"
    static let medicationPlanSave = "medication.plan.save"
    static let assistantArchive = "assistant.archive"
    static let assistantInput = "assistant.input"
    static let assistantSend = "assistant.send"
    static let firstLaunchSkip = "firstLaunch.skip"
    static let firstLaunchNext = "firstLaunch.next"
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

struct FirstLaunchCompletionBridgeView: View {
    @State private var didAppear = false

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.014, green: 0.016, blue: 0.020),
                    Color(red: 0.032, green: 0.040, blue: 0.048),
                    Color(red: 0.010, green: 0.012, blue: 0.016)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 18) {
                ZStack {
                    Circle()
                        .fill(Color(red: 0.42, green: 0.58, blue: 0.78).opacity(didAppear ? 0.18 : 0.06))
                        .frame(width: 104, height: 104)
                        .blur(radius: didAppear ? 18 : 26)
                    Image(systemName: "pills.fill")
                        .font(.system(size: 42, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 76, height: 76)
                        .background(.white.opacity(0.075), in: Circle())
                        .overlay(
                            Circle()
                                .stroke(.white.opacity(0.10), lineWidth: 1)
                        )
                        .medicationGlassSurface(
                            cornerRadius: 38,
                            tint: Color(red: 0.42, green: 0.58, blue: 0.78),
                            fallbackMaterial: .ultraThinMaterial,
                            isInteractive: false
                        )
                }
                .scaleEffect(didAppear ? 1 : 0.92)
                .opacity(didAppear ? 1 : 0)

                VStack(spacing: 7) {
                    Text("用药跟踪")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Text("安心记录每一次用药")
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.54))
                }
                .opacity(didAppear ? 1 : 0)
                .offset(y: didAppear ? 0 : 10)
            }
        }
        .onAppear {
            withAnimation(.smooth(duration: 0.56)) {
                didAppear = true
            }
        }
        .accessibilityLabel("用药跟踪")
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
        colorScheme == .dark ? 0.90 : 0.86
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
                leading: Color(red: 0.62, green: 0.54, blue: 0.98),
                trailing: Color(red: 0.34, green: 0.82, blue: 0.90),
                background: Color(red: 0.88, green: 0.88, blue: 0.98)
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
