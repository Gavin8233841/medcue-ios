import SwiftData
import SwiftUI

struct FirstLaunchSetupView: View {
    @AppStorage("prefersReducedAppMotion") private var prefersReducedAppMotion = false
    let finish: (Bool) -> Void
    let startDemoMode: () -> Void
    @State private var pageIndex = FirstLaunchSetupView.initialPageIndex()
    @State private var activeIntroPageIndex = FirstLaunchSetupView.initialPageIndex()
    @State private var animationPhase = false
    @State private var animationStep = 0
    @State private var introTask: Task<Void, Never>?

    init(
        finish: @escaping (Bool) -> Void,
        startDemoMode: @escaping () -> Void
    ) {
        self.finish = finish
        self.startDemoMode = startDemoMode
    }

    private var pages: [FirstLaunchPage] {
        [
            FirstLaunchPage(
                eyebrow: "今日",
                title: "今天要处理的用药",
                subtitle: "避免忘记、重复或误触造成记录混乱。",
                iconName: "bell.badge.fill",
                tint: Color(red: 0.42, green: 0.58, blue: 0.78)
            ),
            FirstLaunchPage(
                eyebrow: "添加",
                title: "把药品资料填完整",
                subtitle: "把药名、时间和药盒编号整理成可核对资料。",
                iconName: "pills.fill",
                tint: Color(red: 0.42, green: 0.64, blue: 0.50)
            ),
            FirstLaunchPage(
                eyebrow: "记录",
                title: "看见坚持和变化",
                subtitle: "周历和月历帮你复盘每一天发生了什么。",
                iconName: "calendar",
                tint: Color(red: 0.38, green: 0.65, blue: 0.66)
            ),
            FirstLaunchPage(
                eyebrow: "趋势",
                title: "看见用药趋势",
                subtitle: "依靠完成率、延迟和剂量变化的数学模型，展示规律变化。",
                iconName: "chart.line.uptrend.xyaxis",
                tint: Color(red: 0.38, green: 0.65, blue: 0.66)
            ),
            FirstLaunchPage(
                eyebrow: "智能体",
                title: "支持双端智能体",
                subtitle: "设备端模型可在本机整理记录；云端模式由你主动选择后再使用。",
                iconName: "lock.shield.fill",
                tint: Color(red: 0.38, green: 0.58, blue: 0.66)
            ),
            FirstLaunchPage(
                eyebrow: "提醒",
                title: "提醒跟着你走",
                subtitle: "锁屏、灵动岛和闹钟让关键提醒更难错过。",
                iconName: "iphone",
                tint: Color(red: 0.46, green: 0.68, blue: 0.62)
            ),
            FirstLaunchPage(
                eyebrow: "风险",
                title: "风险要说清楚原因",
                subtitle: "具体到药品、饮食和病症，避免只给模糊警示。",
                iconName: "shield.lefthalf.filled",
                tint: Color(red: 0.50, green: 0.50, blue: 0.74)
            )
        ]
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.018, green: 0.021, blue: 0.026),
                    Color(red: 0.042, green: 0.045, blue: 0.055),
                    Color(red: 0.014, green: 0.016, blue: 0.020)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
                .ignoresSafeArea()

            VStack(spacing: 0) {
                HStack {
                    #if DEBUG || MEDCUE_DEMO
                    Button("Demo") {
                        startDemoMode()
                    }
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.white.opacity(0.34))
                    .buttonStyle(.plain)
                    .padding(.leading, 24)
                    .accessibilityLabel("载入演示数据")
                    .accessibilityHint("仅在受控调试或演示版本中载入合成演示数据")
                    #endif
                    Spacer()
                    Button("跳过") {
                        finish(false)
                    }
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.62))
                    .padding(.horizontal, 24)
                    .padding(.top, 12)
                    .accessibilityIdentifier(AppAccessibilityID.firstLaunchSkip)
                }
                .frame(height: 48)

                TabView(selection: $pageIndex) {
                    ForEach(pages.indices, id: \.self) { index in
                        let isIntroActiveForPage = activeIntroPageIndex == index
                        FirstLaunchPageView(
                            page: pages[index],
                            pageIndex: index,
                            selectedPageIndex: pageIndex,
                            animationPhase: isIntroActiveForPage ? animationPhase : false,
                            animationStep: isIntroActiveForPage ? animationStep : 0
                        )
                        .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .onChange(of: pageIndex) { _, newValue in
                    playPageIntro(for: newValue)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                VStack(spacing: 14) {
                    FirstLaunchPageDots(count: pages.count, selectedIndex: pageIndex, selectedTint: pages[pageIndex].tint)
                    Button(pageIndex == pages.count - 1 ? "开始使用" : "下一步") {
                        if pageIndex < pages.count - 1 {
                            withAnimation(.snappy) {
                                pageIndex += 1
                            }
                        } else {
                            finish(false)
                        }
                    }
                    .firstLaunchCTAStyle(tint: pages[pageIndex].tint)
                    .frame(maxWidth: .infinity)
                    .accessibilityIdentifier(AppAccessibilityID.firstLaunchNext)
                }
                .padding(.horizontal, 22)
                .padding(.top, 8)
            .padding(.bottom, 22)
            }
            .task {
                playPageIntro(for: pageIndex)
            }
            .onDisappear {
                introTask?.cancel()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func playPageIntro(for index: Int) {
        introTask?.cancel()
        var resetTransaction = Transaction()
        resetTransaction.disablesAnimations = true
        guard !prefersReducedAppMotion else {
            withTransaction(resetTransaction) {
                activeIntroPageIndex = index
                animationStep = 3
                animationPhase = true
            }
            return
        }
        withTransaction(resetTransaction) {
            activeIntroPageIndex = index
            animationStep = 0
            animationPhase = false
        }
        introTask = Task {
            try? await Task.sleep(for: .milliseconds(420))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                withAnimation(.smooth(duration: 0.55)) { animationStep = 1 }
            }
            try? await Task.sleep(for: .milliseconds(700))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                withAnimation(.smooth(duration: 0.60)) { animationStep = 2 }
            }
            try? await Task.sleep(for: .milliseconds(760))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                withAnimation(.smooth(duration: 0.68)) { animationStep = 3 }
                withAnimation(.smooth(duration: 0.52).delay(0.12)) { animationPhase = true }
            }
        }
    }

    private static func initialPageIndex() -> Int {
        let arguments = ProcessInfo.processInfo.arguments
        for pageNumber in 1...7 where arguments.contains("-showFirstLaunchPage\(pageNumber)") {
            return pageNumber - 1
        }
        return 0
    }
}

struct FirstLaunchPage {
    let eyebrow: String
    let title: String
    let subtitle: String
    let iconName: String
    let tint: Color
}

struct FirstLaunchPageView: View {
    let page: FirstLaunchPage
    let pageIndex: Int
    let selectedPageIndex: Int
    let animationPhase: Bool
    let animationStep: Int

    private var isSelected: Bool {
        pageIndex == selectedPageIndex
    }

    var body: some View {
        GeometryReader { proxy in
            let heightProgress = min(max((proxy.size.height - 500) / 200, 0), 1)
            let isCompactHeight = proxy.size.height < 650
            let verticalSpacing = 10 + (6 * heightProgress)
            let verticalReserve = min(196, max(164, proxy.size.height * 0.28))
            let heroHeight = min(412, max(280, proxy.size.height - verticalReserve))
            let titleSize = 27 + (4 * heightProgress)

            VStack(spacing: verticalSpacing) {
                VStack(spacing: 8) {
                    Text(page.eyebrow)
                        .font(.callout.weight(.bold))
                        .foregroundStyle(page.tint.opacity(0.78))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(page.tint.opacity(0.10), in: Capsule())
                    Text(page.title)
                        .font(.system(size: titleSize, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.82)
                }
                .frame(maxWidth: 340)
                .padding(.top, isCompactHeight ? 0 : 4)
                .opacity(isSelected ? 1 : 0.25)
                .offset(y: isSelected ? 0 : 12)
                .animation(.smooth(duration: 0.55), value: selectedPageIndex)

                OnboardingHeroView(
                    page: page,
                    pageIndex: pageIndex,
                    isSelected: isSelected,
                    animationPhase: animationPhase,
                    animationStep: animationStep,
                    heroHeight: heroHeight
                )

                Text(page.subtitle)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.white.opacity(0.90))
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 340)
                    .opacity(animationPhase && isSelected ? 1 : 0)
                    .offset(y: animationPhase && isSelected ? 0 : 12)
                    .animation(.smooth(duration: 0.58).delay(1.05), value: animationPhase)
            }
            .padding(.horizontal, 22)
            .padding(.top, isCompactHeight ? 0 : 8)
            .padding(.bottom, 2)
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
    }
}
