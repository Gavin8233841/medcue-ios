import SwiftData
import SwiftUI

struct AppRootView: View {
    @Environment(\.modelContext) private var modelContext
    @AppStorage("appColorSchemePreference") private var appColorSchemePreference = AppColorSchemePreference.system.rawValue
    @AppStorage("hasCompletedFirstLaunchSetup") private var hasCompletedFirstLaunchSetup = false
    @StateObject private var notificationService = NotificationService()
    @State private var selectedTab: AppTab = .today
    @State private var pendingAIQuestion = ""

    private var shouldShowFirstLaunchSetup: Bool {
        !hasCompletedFirstLaunchSetup || ProcessInfo.processInfo.arguments.contains("-showFirstLaunch")
    }

    var body: some View {
        ZStack {
            TabView(selection: $selectedTab) {
                ForEach(AppTab.allCases) { tab in
                    NavigationStack {
                        tab.content
                    }
                    .tabItem { tab.label }
                    .tag(tab)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .environment(\.openMedicationAIQuestion) { question in
                pendingAIQuestion = question
                selectedTab = .assistant
            }
            .environment(\.pendingMedicationAIQuestion, pendingAIQuestion)
            .environment(\.clearPendingMedicationAIQuestion) {
                pendingAIQuestion = ""
            }

            if shouldShowFirstLaunchSetup {
                FirstLaunchSetupView { shouldOpenAccountSettings in
                    if shouldOpenAccountSettings {
                        selectedTab = .profile
                    }
                    withAnimation(.snappy(duration: 0.35)) {
                        hasCompletedFirstLaunchSetup = true
                    }
                }
                .transition(.opacity.combined(with: .scale(scale: 1.02)))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .zIndex(10)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task {
            DemoDataSeeder.seedIfNeeded(in: modelContext)
            await notificationService.reconcileAndScheduleReminders(in: modelContext)
        }
        .preferredColorScheme(AppColorSchemePreference(rawValue: appColorSchemePreference)?.colorScheme)
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

enum AppTab: String, CaseIterable, Identifiable {
    case today
    case medications
    case assistant
    case risks
    case profile

    var id: String { rawValue }

    @ViewBuilder
    var content: some View {
        switch self {
        case .today:
            TodayView()
        case .medications:
            MedicationsView()
        case .assistant:
            AIAssistantView()
        case .risks:
            RisksView()
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
            Label("AI 助手", systemImage: "stethoscope")
        case .risks:
            Label("风险", systemImage: "exclamationmark.triangle")
        case .profile:
            Label("个人", systemImage: "person.crop.circle")
        }
    }
}

private struct FirstLaunchSetupView: View {
    @Environment(\.modelContext) private var modelContext
    @AppStorage("profileHeightCM") private var profileHeightCM = ""
    @AppStorage("profileWeightKG") private var profileWeightKG = ""
    @AppStorage("prefersReducedAppMotion") private var prefersReducedAppMotion = false
    @StateObject private var notificationService = NotificationService()
    let finish: (Bool) -> Void
    @State private var pageIndex = ProcessInfo.processInfo.arguments.contains("-showFirstLaunchPage2") ? 1 : 0
    @State private var animationPhase = false

    private var pages: [FirstLaunchPage] {
        [
            FirstLaunchPage(
                eyebrow: "安心服药",
                title: "今天从哪里开始，一眼看清",
                subtitle: "提醒、药盒、记录和天气关注放在同一个节奏里。",
                iconName: "calendar.badge.checkmark",
                tint: .blue,
                features: [
                    FirstLaunchFeature(iconName: "checkmark.circle.fill", title: "今日任务", subtitle: "完成后自动收起，误操作可撤销"),
                    FirstLaunchFeature(iconName: "cloud.sun.fill", title: "天气关注", subtitle: "干燥、降温等环境变化可提醒留意"),
                    FirstLaunchFeature(iconName: "stethoscope", title: "AI 助手", subtitle: "今天从哪里开始")
                ]
            ),
            FirstLaunchPage(
                eyebrow: "添加药品",
                title: "从右上角加号开始",
                subtitle: "手动录入、扫描药名、选择规格和剂型，照片与库存都可稍后补。",
                iconName: "plus.circle.fill",
                tint: .green,
                features: [
                    FirstLaunchFeature(iconName: "text.cursor", title: "手动添加", subtitle: "药名、规格、剂型先选后改"),
                    FirstLaunchFeature(iconName: "camera.fill", title: "扫描药名", subtitle: "用 iPhone 相机辅助录入"),
                    FirstLaunchFeature(iconName: "photo.on.rectangle", title: "非必填项", subtitle: "药品照片和药盒库存可稍后补充")
                ]
            ),
            FirstLaunchPage(
                eyebrow: "大模型协助",
                title: "复杂说明，换成能听懂的话",
                subtitle: "授权后读取 App 内记录，帮你整理风险和复诊问题。",
                iconName: "brain.head.profile",
                tint: .purple,
                features: [
                    FirstLaunchFeature(iconName: "text.bubble.fill", title: "说明书可读化", subtitle: "把禁忌和注意事项说清楚"),
                    FirstLaunchFeature(iconName: "waveform.path.ecg.rectangle.fill", title: "记录复核", subtitle: "结合近期服药记录整理提醒"),
                    FirstLaunchFeature(iconName: "exclamationmark.circle", title: "参考提醒", subtitle: "回答仅供参考，不能替代医生或药师判断。")
                ]
            ),
            FirstLaunchPage(
                eyebrow: "隐私",
                title: "你的记录，由你决定怎么用",
                subtitle: "隐私是每个人的基本权利，健康记录由你决定何时共享。",
                iconName: "lock.shield.fill",
                tint: .orange,
                features: [
                    FirstLaunchFeature(iconName: "internaldrive.fill", title: "本地记录", subtitle: "默认保存在设备内"),
                    FirstLaunchFeature(iconName: "stethoscope", title: "医疗 AI", subtitle: "只在授权后读取记录"),
                    FirstLaunchFeature(iconName: "square.and.arrow.up", title: "主动分享", subtitle: "服药记录由你导出")
                ]
            )
        ]
    }

    var body: some View {
        ZStack {
            Color(red: 0.015, green: 0.018, blue: 0.022)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    Button("跳过") {
                        finish(false)
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.58))
                    .padding(.horizontal, 20)
                    .padding(.top, 10)
                }

                ZStack {
                    let page = pages[pageIndex]
                    FirstLaunchPageView(
                        page: page,
                        pageIndex: pageIndex,
                        selectedPageIndex: pageIndex,
                        animationPhase: animationPhase
                    ) {
                        if pageIndex == 0 {
                            FirstLaunchPermissionPrompt(
                                title: "开启服药提醒",
                                message: notificationService.authorizationMessage,
                                iconName: "bell.badge.fill"
                            ) {
                                Task {
                                    let granted = await notificationService.requestAuthorization()
                                    if granted {
                                        await notificationService.reconcileAndScheduleReminders(in: modelContext)
                                    }
                                }
                            }
                        }
                    }
                    .id(pageIndex)
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .move(edge: .leading).combined(with: .opacity)
                    ))
                }
                .animation(.snappy(duration: 0.45), value: pageIndex)
                .onChange(of: pageIndex) { _, newValue in
                    playPageIntro(for: newValue)
                }

                VStack(spacing: 14) {
                    FirstLaunchPageDots(count: pages.count, selectedIndex: pageIndex)
                    Button(pageIndex == 3 ? "开始使用" : "下一步") {
                        if pageIndex < 3 {
                            withAnimation(.snappy) {
                                pageIndex += 1
                            }
                        } else {
                            finish(false)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .frame(maxWidth: .infinity)
                }
                .padding(.horizontal, 22)
                .padding(.bottom, 18)
            }
            .task {
                playPageIntro(for: pageIndex)
                await swingFirstPageCalendar()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func swingFirstPageCalendar() async {
        guard !prefersReducedAppMotion else {
            return
        }
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(pageIndex == 0 ? 1.15 : 2.6))
            await MainActor.run {
                guard pageIndex == 0 else {
                    return
                }
                withAnimation(.smooth(duration: 0.72)) {
                    animationPhase.toggle()
                }
            }
        }
    }

    private func playPageIntro(for index: Int) {
        guard !prefersReducedAppMotion else {
            animationPhase = true
            return
        }
        animationPhase = false
        Task {
            try? await Task.sleep(for: .milliseconds(index == 0 ? 80 : 140))
            await MainActor.run {
                withAnimation(.snappy(duration: 0.58)) {
                    animationPhase = true
                }
            }
        }
    }
}

private struct FirstLaunchPage {
    let eyebrow: String
    let title: String
    let subtitle: String
    let iconName: String
    let tint: Color
    let features: [FirstLaunchFeature]
}

private struct FirstLaunchFeature {
    let iconName: String
    let title: String
    let subtitle: String
}

private struct FirstLaunchPageView<Accessory: View>: View {
    let page: FirstLaunchPage
    let pageIndex: Int
    let selectedPageIndex: Int
    let animationPhase: Bool
    @ViewBuilder var accessory: Accessory

    private var isSelected: Bool {
        pageIndex == selectedPageIndex
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                OnboardingHeroView(page: page, pageIndex: pageIndex, isSelected: isSelected, animationPhase: animationPhase)

                VStack(spacing: 8) {
                    Text(page.eyebrow)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.46))
                    Text(page.title)
                        .font(.title.weight(.bold))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .offset(x: isSelected ? 0 : 28)
                        .opacity(isSelected ? 1 : 0.2)
                    Text(page.subtitle)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white.opacity(0.62))
                        .multilineTextAlignment(.center)
                        .offset(x: animationPhase && isSelected ? 0 : -10)
                }
                .animation(.snappy(duration: 0.45), value: selectedPageIndex)

                VStack(spacing: 10) {
                    ForEach(Array(page.features.enumerated()), id: \.offset) { index, feature in
                        if index < 2 {
                            FeaturePill(feature: feature, tint: page.tint)
                                .offset(x: isSelected ? 0 : 24)
                                .opacity(isSelected ? 1 : 0.35)
                                .animation(.snappy(duration: 0.38).delay(Double(index) * 0.06), value: selectedPageIndex)
                        } else {
                            Text(feature.subtitle)
                                .font(pageIndex == 2 ? .caption.weight(.medium) : .title3.weight(.semibold))
                                .foregroundStyle(.white.opacity(pageIndex == 2 ? 0.5 : 1))
                                .multilineTextAlignment(.center)
                                .padding(.top, 4)
                                .offset(y: isSelected ? 0 : 12)
                                .opacity(isSelected ? 1 : 0.3)
                                .animation(.snappy(duration: 0.42).delay(0.12), value: selectedPageIndex)
                        }
                    }
                }

                accessory
            }
            .padding(.horizontal, 30)
            .padding(.top, 8)
            .padding(.bottom, 18)
        }
        .scrollIndicators(.hidden)
    }
}

private struct OnboardingHeroView: View {
    let page: FirstLaunchPage
    let pageIndex: Int
    let isSelected: Bool
    let animationPhase: Bool

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(red: 0.025, green: 0.035, blue: 0.043))
                .opacity(0.72)
            heroCard
                .shadow(color: page.tint.opacity(0.28), radius: 22, x: 0, y: 12)
                .scaleEffect(cardScale)
                .offset(cardOffset)
            animatedAccent
        }
        .frame(height: 208)
        .clipped()
        .animation(.smooth(duration: 0.8), value: animationPhase)
        .animation(.snappy(duration: 0.45), value: isSelected)
    }

    private var cardScale: CGFloat {
        guard isSelected else {
            return 0.9
        }
        switch pageIndex {
        case 1:
            return animationPhase ? 1.0 : 0.86
        case 3:
            return animationPhase ? 0.99 : 1.02
        default:
            return 1
        }
    }

    private var cardOffset: CGSize {
        guard isSelected else {
            return CGSize(width: 0, height: 8)
        }
        switch pageIndex {
        case 0:
            return CGSize(width: animationPhase ? 8 : -8, height: animationPhase ? -3 : 3)
        case 1:
            return CGSize(width: animationPhase ? 0 : 42, height: animationPhase ? 0 : 10)
        case 2:
            return CGSize(width: animationPhase ? -16 : 16, height: 0)
        default:
            return .zero
        }
    }

    @ViewBuilder
    private var animatedAccent: some View {
        switch pageIndex {
        case 0:
            ZStack {
                calendarTile(day: "今", time: "08:00", highlighted: true)
                    .offset(x: animationPhase ? -116 : -104, y: animationPhase ? -58 : -48)
                    .rotationEffect(.degrees(animationPhase ? -7 : 5))
                calendarTile(day: "药", time: "13:00", highlighted: false)
                    .offset(x: animationPhase ? 72 : 58, y: animationPhase ? 70 : 58)
                    .rotationEffect(.degrees(animationPhase ? 6 : -5))
                VStack(spacing: 7) {
                    ForEach(0..<3, id: \.self) { index in
                        Capsule()
                            .fill(index == 0 ? page.tint : .white.opacity(0.26))
                            .frame(width: index == 0 ? 38 : 24, height: 5)
                            .offset(x: animationPhase ? CGFloat(index * 4) : CGFloat(-index * 5))
                    }
                }
                .offset(x: 96, y: animationPhase ? -78 : -66)
            }
        case 1:
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(page.tint.opacity(0.22))
                    .frame(width: 70, height: 70)
                    .overlay(
                        Image(systemName: "plus")
                            .font(.system(size: 31, weight: .bold))
                            .foregroundStyle(.white)
                    )
                    .offset(x: animationPhase ? 90 : 118, y: animationPhase ? -70 : -92)
                    .rotationEffect(.degrees(animationPhase ? 0 : 18))
                VStack(alignment: .leading, spacing: 7) {
                    tutorialPointer("点这里添加药品", width: 112)
                    tutorialPointer("选择规格和剂型", width: 132)
                }
                .offset(x: animationPhase ? -84 : -116, y: animationPhase ? 46 : 78)
                .opacity(animationPhase ? 1 : 0)
            }
        case 2:
            VStack(alignment: .leading, spacing: 8) {
                chatBubble(width: 74, tint: .white.opacity(0.2))
                chatBubble(width: 104, tint: page.tint.opacity(0.65))
            }
            .offset(x: animationPhase ? -86 : 76, y: animationPhase ? 64 : -64)
        default:
            Image(systemName: page.iconName)
                .font(.system(size: 42, weight: .semibold))
                .foregroundStyle(page.tint)
                .offset(x: animationPhase ? -84 : 84, y: animationPhase ? 56 : -56)
                .rotationEffect(.degrees(animationPhase ? -6 : 6))
        }
    }

    private func chatBubble(width: CGFloat, tint: Color) -> some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(tint)
            .frame(width: width, height: 26)
    }

    private func tutorialPointer(_ title: String, width: CGFloat) -> some View {
        HStack(spacing: 7) {
            Image(systemName: "arrow.up.right")
                .font(.caption2.weight(.bold))
            Text(title)
                .font(.caption2.weight(.semibold))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .frame(width: width)
        .background(page.tint.opacity(0.72), in: Capsule())
    }

    private func calendarTile(day: String, time: String, highlighted: Bool) -> some View {
        VStack(spacing: 3) {
            Text(day)
                .font(.caption.weight(.bold))
            Text(time)
                .font(.system(size: 8, weight: .semibold))
        }
        .foregroundStyle(highlighted ? .white : .white.opacity(0.68))
        .frame(width: 48, height: 42)
        .background((highlighted ? page.tint.opacity(0.76) : .white.opacity(0.14)), in: RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private var heroCard: some View {
        switch pageIndex {
        case 0:
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("今日服药")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(.white)
                    Spacer()
                    Text("5")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(page.tint)
                }
                ForEach(0..<3, id: \.self) { index in
                    HStack(spacing: 12) {
                        Capsule()
                            .fill(index == 0 ? Color(red: 1, green: 0.65, blue: 0.66) : .white.opacity(0.28))
                            .frame(width: 5, height: 38)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(["08:00", "13:00", "18:30"][index])
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(.white.opacity(index == 0 ? 0.95 : 0.58))
                            Text(["布洛芬 1 片", "对乙酰氨基酚 1 片", "氯雷他定 1 片"][index])
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.white.opacity(0.46))
                        }
                    }
                }
            }
            .padding(18)
            .frame(width: 252, height: 168)
            .background(Color.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(.white.opacity(0.08), lineWidth: 1)
            )
        case 1:
            VStack(alignment: .leading, spacing: 13) {
                HStack {
                    Image(systemName: "pills.fill")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(page.tint)
                    Text("添加药品")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(.white)
                    Spacer()
                }
                addFormLine(title: "药名", value: "扫描或输入")
                addFormLine(title: "规格", value: "200 mg")
                HStack(spacing: 8) {
                    addOptionChip("片剂", isSelected: true)
                    addOptionChip("胶囊", isSelected: false)
                    addOptionChip("滴剂", isSelected: false)
                }
                Text("照片与库存非必填")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.48))
            }
            .padding(18)
            .frame(width: 258, height: 168)
            .background(Color.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
        case 2:
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Image(systemName: "sparkles")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(page.tint)
                    Text("百川/豆包医疗智能体")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(.white)
                    Spacer()
                }
                VStack(alignment: .leading, spacing: 10) {
                    aiLine("读取近五次对话")
                    aiLine("结合 App 内服药记录")
                    aiLine("输出短句提醒")
                }
            }
            .padding(20)
            .frame(width: 258, height: 162)
            .background(Color.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
        default:
            VStack(spacing: 10) {
                Image(systemName: "lock.shield.fill")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(page.tint)
                Text("AI 授权")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.white)
                VStack(spacing: 8) {
                    permissionLine("药品信息", enabled: true)
                    permissionLine("服药记录", enabled: true)
                    permissionLine("说明书摘要", enabled: false)
                }
            }
            .padding(20)
            .frame(width: 224, height: 178)
            .background(Color.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
        }
    }

    private func permissionLine(_ title: String, enabled: Bool) -> some View {
        HStack {
            Circle()
                .fill(enabled ? page.tint : .white.opacity(0.18))
                .frame(width: 9, height: 9)
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(enabled ? 0.82 : 0.42))
            Spacer()
        }
        .frame(width: 142)
    }

    private func addFormLine(title: String, value: String) -> some View {
        HStack {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.48))
            Spacer()
            Text(value)
                .font(.caption.weight(.bold))
                .foregroundStyle(.white.opacity(0.82))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
    }

    private func addOptionChip(_ title: String, isSelected: Bool) -> some View {
        Text(title)
            .font(.caption.weight(.bold))
            .foregroundStyle(isSelected ? .white : .white.opacity(0.52))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(isSelected ? page.tint.opacity(0.7) : .white.opacity(0.10), in: Capsule())
    }

    private func aiLine(_ title: String) -> some View {
        HStack(spacing: 10) {
            Circle()
                .fill(page.tint)
                .frame(width: 8, height: 8)
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.72))
            Spacer()
        }
    }
}

private struct FeaturePill: View {
    let feature: FirstLaunchFeature
    let tint: Color

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: feature.iconName)
                .font(.title2.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 38)
            VStack(alignment: .leading, spacing: 4) {
                Text(feature.title)
                    .font(.headline)
                    .foregroundStyle(.white)
                Text(feature.subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.58))
                    .lineLimit(2)
            }
            Spacer()
        }
        .padding(14)
        .frame(minHeight: 62)
        .background(Color.white.opacity(0.105), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(.white.opacity(0.055), lineWidth: 1)
        )
    }
}

private struct FirstLaunchPermissionPrompt: View {
    let title: String
    let message: String
    let iconName: String
    let request: () -> Void

    var body: some View {
        Button(action: request) {
            HStack(spacing: 12) {
                Image(systemName: iconName)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .background(Color.blue, in: Circle())
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.white)
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.6))
                        .lineLimit(1)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(.white.opacity(0.46))
            }
            .padding(14)
            .background(Color.white.opacity(0.105), in: RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(.white.opacity(0.055), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .padding(.top, 4)
    }
}

private struct FirstLaunchPageDots: View {
    let count: Int
    let selectedIndex: Int

    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<count, id: \.self) { index in
                Capsule()
                    .fill(index == selectedIndex ? Color.blue : Color.white.opacity(0.22))
                    .frame(width: index == selectedIndex ? 24 : 8, height: 8)
                    .animation(.snappy(duration: 0.25), value: selectedIndex)
            }
        }
        .accessibilityLabel("第 \(selectedIndex + 1) 页，共 \(count) 页")
    }
}
