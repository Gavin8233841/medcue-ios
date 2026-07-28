import SwiftData
import SwiftUI

struct OnboardingHeroView: View {
    let page: FirstLaunchPage
    let pageIndex: Int
    let isSelected: Bool
    let animationPhase: Bool
    let animationStep: Int
    let heroHeight: CGFloat

    private var stepOne: Bool { animationStep >= 1 }
    private var stepTwo: Bool { animationStep >= 2 }
    private var stepThree: Bool { animationStep >= 3 }

    var body: some View {
        GeometryReader { proxy in
            let fittedCardScale = cardScale(in: proxy.size)
            let stageHeight = min(proxy.size.height, (cardBaseSize.height * fittedCardScale) + 12)

            ZStack {
                RoundedRectangle(cornerRadius: 38, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                page.tint.opacity(0.075),
                                Color(red: 0.055, green: 0.063, blue: 0.076).opacity(0.18),
                                Color(red: 0.014, green: 0.016, blue: 0.020).opacity(0.02)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 38, style: .continuous)
                            .strokeBorder(
                                LinearGradient(
                                    colors: [
                                        .white.opacity(0.035),
                                        page.tint.opacity(0.035),
                                        .clear
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1
                            )
                    }
                    .frame(height: stageHeight)
                    .padding(.horizontal, 8)
                    .shadow(color: page.tint.opacity(0.04), radius: 34, x: 0, y: 20)
                heroCard
                    .shadow(color: page.tint.opacity(0.14), radius: 18, x: 0, y: 10)
                    .scaleEffect(fittedCardScale)
                    .offset(cardOffset)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .frame(maxWidth: 356)
        .frame(height: heroHeight)
        .animation(.smooth(duration: 1.30), value: animationPhase)
        .animation(.smooth(duration: 0.55), value: isSelected)
    }

    private func cardScale(in containerSize: CGSize) -> CGFloat {
        let horizontalScale = max(0.1, (containerSize.width - 24) / cardBaseSize.width)
        let verticalScale = max(0.1, (containerSize.height - 40) / cardBaseSize.height)
        let selectedLimit: CGFloat = isSelected ? 0.965 : 0.92
        return min(selectedLimit, horizontalScale, verticalScale)
    }

    private var cardBaseSize: CGSize {
        let height: CGFloat
        switch pageIndex {
        case 0:
            height = 392
        case 1, 2:
            height = 372
        case 3:
            height = 342
        case 4, 5:
            height = 330
        case 6:
            height = 386
        default:
            height = 356
        }
        return CGSize(width: 338, height: height)
    }

    private var cardOffset: CGSize {
        isSelected ? .zero : CGSize(width: 0, height: 8)
    }

    @ViewBuilder
    private var animatedAccent: some View {
        switch pageIndex {
        case 0:
            ZStack {
                calendarTile(day: "今", time: "08:00", highlighted: true)
                    .offset(x: animationPhase ? -152 : -140, y: animationPhase ? -110 : -100)
                    .rotationEffect(.degrees(animationPhase ? -7 : 5))
                calendarTile(day: "药", time: "13:00", highlighted: false)
                    .offset(x: animationPhase ? 112 : 98, y: animationPhase ? 96 : 82)
                    .rotationEffect(.degrees(animationPhase ? 6 : -5))
                VStack(spacing: 6) {
                    ForEach(0..<3, id: \.self) { index in
                        Capsule()
                            .fill(index == 0 ? page.tint.opacity(0.82) : .white.opacity(0.20))
                            .frame(width: index == 0 ? 34 : 22, height: 4)
                            .offset(x: animationPhase ? CGFloat(index * 3) : CGFloat(-index * 4))
                    }
                }
                .offset(x: animationPhase ? 130 : 118, y: animationPhase ? 28 : 40)
                .opacity(0.88)
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
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(page.tint.opacity(0.55), lineWidth: 2)
                    .frame(width: animationPhase ? 116 : 66, height: animationPhase ? 74 : 48)
                    .offset(x: animationPhase ? -30 : 50, y: animationPhase ? -18 : 28)
                Image(systemName: "magnifyingglass")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(page.tint)
                    .offset(x: animationPhase ? 46 : 94, y: animationPhase ? 34 : 58)
            }
        case 3:
            ZStack {
                Circle()
                    .fill(page.tint.opacity(0.18))
                    .frame(width: animationPhase ? 58 : 26, height: animationPhase ? 58 : 26)
                    .offset(x: animationPhase ? 74 : -72, y: animationPhase ? -44 : 52)
                Text(animationPhase ? "+12%" : "7天")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(page.tint.opacity(0.74), in: Capsule())
                    .offset(x: animationPhase ? 78 : -72, y: animationPhase ? -80 : 78)
            }
        case 4:
            ZStack {
                Image(systemName: "square.and.arrow.up")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(13)
                    .background(page.tint.opacity(0.8), in: Circle())
                    .offset(x: animationPhase ? 100 : 132, y: animationPhase ? -70 : -96)
                    .scaleEffect(animationPhase ? 1 : 0.72)
                RoundedRectangle(cornerRadius: 6)
                    .fill(.white.opacity(0.14))
                    .frame(width: 86, height: 112)
                    .rotationEffect(.degrees(animationPhase ? -7 : -15))
                    .offset(x: animationPhase ? -112 : -138, y: animationPhase ? 56 : 84)
            }
        case 5:
            VStack(alignment: .leading, spacing: 8) {
                chatBubble(width: 74, tint: .white.opacity(0.2))
                chatBubble(width: 104, tint: page.tint.opacity(0.65))
            }
            .offset(x: animationPhase ? -96 : 86, y: animationPhase ? 66 : -68)
        case 6:
            ZStack {
                Capsule()
                    .stroke(page.tint.opacity(0.46), lineWidth: 2)
                    .frame(width: animationPhase ? 178 : 132, height: animationPhase ? 48 : 34)
                    .offset(y: -74)
                ForEach(0..<3, id: \.self) { index in
                    Circle()
                        .stroke(page.tint.opacity(0.22 - Double(index) * 0.04), lineWidth: 2)
                        .frame(width: CGFloat(70 + index * 34), height: CGFloat(70 + index * 34))
                        .scaleEffect(animationPhase ? 1.0 + CGFloat(index) * 0.04 : 0.78)
                        .opacity(animationPhase ? 0.92 : 0.28)
                        .offset(y: 42)
                }
            }
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
            todayKeynoteCard
        case 1:
            addMedicineKeynoteCard
        case 2:
            recordsKeynoteCard
        case 3:
            trendKeynoteCard
        case 4:
            aiKeynoteCard
        case 5:
            reminderKeynoteCard
        case 6:
            riskKeynoteCard
        default:
            EmptyView()
        }
    }

    private var todayKeynoteCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("6月10日 星期三")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.white.opacity(0.58))
                Text(stepThree ? "已完成全部用药" : "还有 \(stepTwo ? 1 : 2) 项待处理")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                Text(stepThree ? "已处理 3 / 3 项" : "沿时间线逐项确认")
                    .font(.callout.weight(.bold))
                    .foregroundStyle(.white.opacity(0.52))
            }

            VStack(spacing: 14) {
                keynoteDoseRow(
                    time: "上午 8:00",
                    title: "氯雷他定",
                    subtitle: "1 片",
                    tint: Color(red: 1.0, green: 0.68, blue: 0.72),
                    isDone: stepOne,
                    isFocused: !stepOne
                )
                keynoteDoseRow(
                    time: "中午 1:00",
                    title: "维生素 D3",
                    subtitle: "随餐",
                    tint: page.tint,
                    isDone: stepTwo,
                    isFocused: stepOne && !stepTwo
                )
                keynoteDoseRow(
                    time: "晚上 8:30",
                    title: "人工泪液",
                    subtitle: "双眼各 1 滴",
                    tint: Color(red: 0.62, green: 0.80, blue: 0.68),
                    isDone: stepThree,
                    isFocused: stepTwo && !stepThree
                )
            }
        }
        .padding(24)
        .frame(width: 338, height: 392, alignment: .topLeading)
        .onboardingPreviewPanel(tint: page.tint)
    }

    private var addMedicineKeynoteCard: some View {
        VStack(alignment: .leading, spacing: 17) {
            HStack(alignment: .center) {
                Text("药品资料")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.white)
                Spacer()
                Image(systemName: "camera.viewfinder")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(page.tint)
                    .frame(width: 44, height: 44)
                    .background(page.tint.opacity(0.14), in: Circle())
            }

            addFieldRow(title: "药名", value: stepOne ? "维生素 C" : "正在输入")
            addColorSelector
            addFieldRow(title: "提醒", value: stepTwo ? "每天 上午 8:00" : "选择时间")

            addMedicineCompletionStage
        }
        .padding(24)
        .frame(width: 338, height: 372, alignment: .topLeading)
        .onboardingPreviewPanel(tint: page.tint)
    }

    private var riskKeynoteCard: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack {
                Text("按分类复核")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.white)
                Spacer()
                Text(stepThree ? "2 条需复核" : "复核中")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(stepThree ? Color(red: 1.0, green: 0.72, blue: 0.56) : .white.opacity(0.56))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.white.opacity(0.075), in: Capsule())
            }

            riskCategoryRow(icon: "pills.fill", title: "药物相互作用", detail: "氯雷他定与酮康唑同用时，需咨询医生或药师复核。", tint: page.tint, highlighted: stepOne)
                .opacity(stepOne ? 1 : 0)
                .offset(y: stepOne ? 0 : 12)
            riskCategoryRow(icon: "fork.knife", title: "饮食生活方式", detail: "布洛芬服用期间饮酒，会增加胃肠不适风险。", tint: Color(red: 0.48, green: 0.72, blue: 0.66), highlighted: stepTwo)
                .opacity(stepTwo ? 1 : 0)
                .offset(y: stepTwo ? 0 : 12)
            riskCategoryRow(icon: "heart.text.square", title: "病症症状", detail: "胃部不适或既往胃病时，止痛药使用需复核。", tint: Color(red: 0.84, green: 0.58, blue: 0.62), highlighted: stepThree)
                .opacity(stepThree ? 1 : 0)
                .offset(y: stepThree ? 0 : 12)
        }
        .padding(24)
        .frame(width: 338, height: 386, alignment: .topLeading)
        .onboardingPreviewPanel(tint: page.tint)
    }

    private var recordsKeynoteCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("近 7 天")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.white)
                Spacer()
                Text(stepThree ? "28 天" : "本周")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(page.tint)
            }

            recordsWeekStrip

            insightRow(icon: "calendar.badge.clock", title: "剂量变化已标记", detail: stepTwo ? "维生素 D3 从 6 月 3 日开始调整剂量。" : "正在读取本周记录。", tint: Color(red: 0.94, green: 0.62, blue: 0.26))
            insightRow(icon: "clock.arrow.circlepath", title: "误操作可追溯", detail: stepThree ? "撤销、稍后和忽略都会保留操作记录。" : "等待生成日期详情。", tint: page.tint)
        }
        .padding(24)
        .frame(width: 338, height: 372, alignment: .topLeading)
        .onboardingPreviewPanel(tint: page.tint)
    }

    private var recordsWeekStrip: some View {
        HStack(spacing: 0) {
            ForEach(0..<7, id: \.self) { index in
                VStack(spacing: 7) {
                    Text(["一", "二", "三", "四", "五", "六", "日"][index])
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white.opacity(0.50))
                    weekProgressRing(index: index)
                }
                .frame(width: 38, height: 56)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
        .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .frame(width: 286, alignment: .center)
        .frame(maxWidth: .infinity, alignment: .center)
        .accessibilityHidden(true)
    }

    private var trendKeynoteCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("数学模型")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white.opacity(0.48))
                    Text(stepThree ? "综合趋势 89%" : "综合趋势生成中")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(.white)
                }
                Spacer()
                Text(stepTwo ? "近 28 天" : "7 天起算")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(page.tint)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(page.tint.opacity(0.13), in: Capsule())
            }

            trendFunctionChart
                .frame(height: 162)
                .padding(.vertical, 8)

            HStack(spacing: 10) {
                trendFactor("完成率", value: stepOne ? "86%" : "--")
                trendFactor("延迟", value: stepTwo ? "-8 分" : "--")
                trendFactor("剂量", value: stepThree ? "1 次" : "--")
            }
        }
        .padding(24)
        .frame(width: 338, height: 342, alignment: .topLeading)
        .onboardingPreviewPanel(tint: page.tint)
    }

    private var visitSummaryKeynoteCard: some View {
        ZStack {
            pdfPage(rotation: animationPhase ? -4 : -10, offset: CGSize(width: -30, height: 20), opacity: 0.26)
            pdfPage(rotation: animationPhase ? 5 : 9, offset: CGSize(width: 26, height: 4), opacity: 0.44)
            VStack(alignment: .leading, spacing: 14) {
                Text(page.title)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.primary)
                HStack(spacing: 10) {
                    reportMetricCard(title: "完成率", value: animationPhase ? "86%" : "--")
                    reportMetricCard(title: "异常节点", value: animationPhase ? "3" : "--")
                    reportMetricCard(title: "剂量变化", value: animationPhase ? "1" : "--")
                }
                VStack(spacing: 8) {
                    pdfMetric("复诊时间段", value: "近 60 天")
                    pdfMetric("需沟通风险", value: animationPhase ? "布洛芬 · 饮酒" : "整理中")
                    pdfMetric("最近调整", value: animationPhase ? "维生素 D3 剂量变化" : "整理中")
                }
                HStack(spacing: 6) {
                    ForEach(0..<5, id: \.self) { index in
                        Capsule()
                            .fill(index < (animationPhase ? 4 : 1) ? page.tint.opacity(0.78) : .secondary.opacity(0.16))
                            .frame(height: 6)
                    }
                }
            }
            .padding(20)
            .frame(width: 296, height: 248, alignment: .topLeading)
            .background(.white, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(page.tint.opacity(0.16), lineWidth: 1)
            )
        }
        .frame(width: 338, height: 356)
    }

    private var aiKeynoteCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("智能体运行方式")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.white)
                Spacer()
                Image(systemName: "lock.shield.fill")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(page.tint)
                    .frame(width: 34, height: 34)
                    .background(page.tint.opacity(0.14), in: Circle())
            }

            VStack(spacing: 10) {
                aiRuntimePreviewRow(
                    icon: "iphone.gen3.radiowaves.left.and.right",
                    title: "本地智能体",
                    detail: "在 iPhone 上整理用药记录",
                    highlighted: stepOne
                )
                aiRuntimePreviewRow(
                    icon: "network",
                    title: "云端智能体",
                    detail: "主动选择后连接外部 API",
                    highlighted: stepTwo
                )
            }

            HStack(spacing: 8) {
                Image(systemName: "lock.shield.fill")
                Text(stepThree ? "数据共享前会先确认范围" : "离线模式默认留在设备上")
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.white.opacity(0.56))
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(.white.opacity(0.07), in: Capsule())

            chatMessage(stepThree ? "已整理近期记录和说明书重点。" : "正在整理说明书和记录。", isUser: false)
                .opacity(stepThree ? 1 : 0.56)
        }
        .padding(24)
        .frame(width: 338, height: 330, alignment: .topLeading)
        .onboardingPreviewPanel(tint: page.tint)
    }

    private func aiRuntimePreviewRow(icon: String, title: String, detail: String, highlighted: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(highlighted ? page.tint : .white.opacity(0.42))
                .frame(width: 32, height: 32)
                .background((highlighted ? page.tint.opacity(0.16) : .white.opacity(0.055)), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.white.opacity(highlighted ? 0.94 : 0.62))
                Text(detail)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.46))
            }
            Spacer()
            if highlighted {
                Text("可用")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(page.tint)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(page.tint.opacity(0.14), in: Capsule())
            }
        }
        .padding(13)
        .background(.white.opacity(highlighted ? 0.09 : 0.055), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var reminderKeynoteCard: some View {
        VStack(spacing: 18) {
                Capsule()
                    .fill(.black.opacity(0.84))
                    .frame(width: stepOne ? 178 : 126, height: stepOne ? 46 : 34)
                    .overlay {
                        HStack(spacing: 8) {
                        Image(systemName: "pills.fill")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(page.tint)
                            onboardingBlurSwapText(
                                from: "提醒",
                                to: "20:30 人工泪液",
                                showsFinal: stepOne,
                                font: .caption.weight(.bold),
                                initialColor: .white.opacity(0.55),
                                finalColor: .white.opacity(0.90),
                                alignment: .center
                            )
                        }
                    }

            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("实况活动")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(.white)
                    Spacer()
                    onboardingBlurSwapText(
                        from: "待处理",
                        to: "已写回",
                        showsFinal: stepThree,
                        font: .caption.weight(.bold),
                        initialColor: page.tint,
                        finalColor: Color(red: 0.62, green: 0.80, blue: 0.68)
                    )
                }
                HStack(spacing: 12) {
                    Gauge(value: stepThree ? 1 : (stepTwo ? 0.72 : 0.42)) {
                        Image(systemName: "pills.fill")
                    }
                    .gaugeStyle(.accessoryCircularCapacity)
                    .tint(page.tint)
                    .frame(width: 62, height: 62)
                    VStack(alignment: .leading, spacing: 4) {
                        onboardingBlurSwapText(
                            from: "氯雷他定",
                            to: "记录已同步",
                            showsFinal: stepThree,
                            font: .title3.weight(.bold),
                            initialColor: .white,
                            finalColor: .white
                        )
                        onboardingBlurSwapText(
                            from: "20:30 应处理",
                            to: "已服用 · 现在",
                            showsFinal: stepTwo,
                            font: .caption.weight(.semibold),
                            initialColor: .white.opacity(0.56),
                            finalColor: .white.opacity(0.56)
                        )
                    }
                    Spacer()
                }
                HStack(spacing: 10) {
                    liveActivityPrimaryAction(isComplete: stepThree)
                    liveActivityAction("稍后", selected: false)
                }
                .opacity(stepTwo ? 1 : 0)
                .offset(y: stepTwo ? 0 : 10)
            }
            .padding(18)
            .background(.white.opacity(0.060), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .padding(22)
        .frame(width: 338, height: 330)
        .onboardingPreviewPanel(tint: page.tint)
    }

    private func onboardingBlurSwapText(
        from initialText: String,
        to finalText: String,
        showsFinal: Bool,
        font: Font,
        initialColor: Color,
        finalColor: Color,
        alignment: Alignment = .leading
    ) -> some View {
        OnboardingBlurSwapText(
            initialText: initialText,
            finalText: finalText,
            showsFinal: showsFinal,
            font: font,
            initialColor: initialColor,
            finalColor: finalColor,
            alignment: alignment
        )
    }

    private func liveActivityPrimaryAction(isComplete: Bool) -> some View {
        onboardingBlurSwapText(
            from: "已服用",
            to: "完成",
            showsFinal: isComplete,
            font: .system(size: 10, weight: .bold),
            initialColor: .black,
            finalColor: .black,
            alignment: .center
        )
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(page.tint, in: Capsule())
    }

    private func keynoteDoseRow(time: String, title: String, subtitle: String, tint: Color, isDone: Bool, isFocused: Bool) -> some View {
        HStack(spacing: 12) {
            Text(time)
                .font(.caption.weight(.bold))
                .foregroundStyle(isFocused ? .white : .white.opacity(0.46))
                .padding(.horizontal, 9)
                .padding(.vertical, 6)
                .background(isFocused ? page.tint.opacity(0.82) : .white.opacity(0.07), in: Capsule())
                .frame(width: 86)
            HStack(spacing: 12) {
                Capsule()
                    .fill(tint)
                    .frame(width: 5, height: 44)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline.weight(.bold))
                        .foregroundStyle(.white)
                    Text(subtitle)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.50))
                }
                Spacer()
                ZStack {
                    Image(systemName: "circle")
                        .foregroundStyle(.white.opacity(0.42))
                        .opacity(isDone ? 0 : 1)
                        .blur(radius: isDone ? 4 : 0)
                        .scaleEffect(isDone ? 0.82 : 1)
                    Image(systemName: "checkmark")
                        .foregroundStyle(tint)
                        .opacity(isDone ? 1 : 0)
                        .blur(radius: isDone ? 0 : 4)
                        .scaleEffect(isDone ? 1 : 0.82)
                }
                    .font(.title3.weight(.bold))
                    .frame(width: 36, height: 36)
                    .background(tint.opacity(isDone ? 0.18 : 0), in: Circle())
                    .compositingGroup()
                    .animation(.smooth(duration: 0.34), value: isDone)
            }
            .padding(12)
            .background(isFocused ? page.tint.opacity(0.11) : .white.opacity(0.045), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(isFocused ? page.tint.opacity(0.82) : .white.opacity(0.055), lineWidth: isFocused ? 2 : 1)
            )
        }
    }

    private var addMedicineCompletionStage: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(.white.opacity(0.06))
                .overlay(alignment: .leading) {
                    Text("保存后生成药品卡")
                        .font(.callout.weight(.bold))
                        .foregroundStyle(.white.opacity(0.40))
                        .padding(.leading, 16)
                }
                .opacity(stepThree ? 0 : 1)
                .blur(radius: stepThree ? 8 : 0)
                .scaleEffect(stepThree ? 0.985 : 1)
                .animation(.easeOut(duration: 0.16), value: stepThree)

            HStack(spacing: 13) {
                Capsule()
                    .fill(Color(red: 1.0, green: 0.68, blue: 0.72))
                    .frame(width: 5, height: 52)
                VStack(alignment: .leading, spacing: 5) {
                    Text("维生素 C")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(.white)
                    Text("每天 · 03.01 起")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.52))
                }
                Spacer()
                Toggle("", isOn: .constant(true))
                    .labelsHidden()
                    .tint(Color(red: 1.0, green: 0.68, blue: 0.72))
                    .scaleEffect(0.82)
            }
            .padding(16)
            .background(.white.opacity(0.075), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .opacity(stepThree ? 1 : 0)
            .blur(radius: stepThree ? 0 : 8)
            .scaleEffect(stepThree ? 1 : 0.985)
            .animation(
                stepThree
                    ? .smooth(duration: 0.32).delay(0.12)
                    : .easeOut(duration: 0.16),
                value: stepThree
            )
        }
        .frame(height: 82)
        .compositingGroup()
    }

    private func addFieldRow(title: String, value: String) -> some View {
        HStack {
            Text(title)
                .font(.caption.weight(.bold))
                .foregroundStyle(.white.opacity(0.48))
            Spacer()
            Text(value)
                .font(.callout.weight(.bold))
                .foregroundStyle(.white.opacity(stepOne ? 0.90 : 0.48))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(.white.opacity(0.060), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var addColorSelector: some View {
        HStack(spacing: 14) {
            ForEach(0..<4, id: \.self) { index in
                Circle()
                    .fill([Color(red: 1.0, green: 0.68, blue: 0.72), Color(red: 0.68, green: 0.80, blue: 0.96), Color(red: 0.70, green: 0.86, blue: 0.72), Color(red: 0.76, green: 0.66, blue: 0.92)][index])
                    .frame(width: 30, height: 30)
                    .overlay(
                        Circle()
                            .stroke(index == 0 ? .white : .clear, lineWidth: 3)
                    )
                    .scaleEffect(stepOne || index == 0 ? 1 : 0.82)
                    .opacity(stepOne || index == 0 ? 1 : 0.45)
            }
            Spacer()
        }
        .padding(.vertical, 4)
    }

    private func riskCategoryRow(icon: String, title: String, detail: String, tint: Color, highlighted: Bool) -> some View {
        HStack(spacing: 13) {
            Image(systemName: icon)
                .font(.headline.weight(.bold))
                .foregroundStyle(tint)
                .frame(width: 38, height: 38)
                .background(tint.opacity(0.13), in: Circle())
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.white)
                Text(detail)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.54))
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
        .padding(14)
        .background(highlighted ? tint.opacity(0.10) : .white.opacity(0.045), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(highlighted ? tint.opacity(0.35) : .white.opacity(0.055), lineWidth: 1)
        )
    }

    private func weekProgressRing(index: Int) -> some View {
        ZStack {
            Circle()
                .stroke(.white.opacity(index > 4 ? 0.045 : 0.10), lineWidth: 5)
            if index <= 4 {
                Circle()
                    .trim(from: 0, to: weekProgressValue(index: index))
                    .stroke(page.tint, style: StrokeStyle(lineWidth: 4.5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            if index == 4 {
                Text("今")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white.opacity(0.66))
            }
        }
        .frame(width: 30, height: 30)
    }

    private func weekProgressValue(index: Int) -> CGFloat {
        let completedDays: [CGFloat] = [0.82, 0.70, 0.94, 0.88, 0.76, 0.0, 0.0]
        guard index < completedDays.count else {
            return 0
        }
        if index > 4 || !stepOne {
            return 0
        }
        return completedDays[index]
    }

    private func insightRow(icon: String, title: String, detail: String, tint: Color) -> some View {
        HStack(alignment: .top, spacing: 13) {
            Image(systemName: icon)
                .font(.headline.weight(.bold))
                .foregroundStyle(tint)
                .frame(width: 36, height: 36)
                .background(tint.opacity(0.12), in: Circle())
            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.white)
                Text(detail)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.50))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
        .padding(14)
        .background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func reportMetricCard(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(.headline.weight(.bold))
                .foregroundStyle(.primary)
            Text(title)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(page.tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var trendFunctionChart: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let height = proxy.size.height
            let progress = stepThree ? 1.0 : (stepTwo ? 0.70 : (stepOne ? 0.36 : 0.0))

            ZStack {
                VStack(spacing: height / 4) {
                    ForEach(0..<4, id: \.self) { _ in
                        Rectangle()
                            .fill(.white.opacity(0.055))
                            .frame(height: 1)
                    }
                }

                Path { path in
                    path.move(to: CGPoint(x: width * 0.04, y: height * 0.84))
                    path.addCurve(
                        to: CGPoint(x: width * 0.36, y: height * 0.58),
                        control1: CGPoint(x: width * 0.14, y: height * 0.86),
                        control2: CGPoint(x: width * 0.25, y: height * 0.50)
                    )
                    path.addCurve(
                        to: CGPoint(x: width * 0.62, y: height * 0.42),
                        control1: CGPoint(x: width * 0.44, y: height * 0.74),
                        control2: CGPoint(x: width * 0.54, y: height * 0.30)
                    )
                    path.addCurve(
                        to: CGPoint(x: width * 0.95, y: height * 0.24),
                        control1: CGPoint(x: width * 0.72, y: height * 0.48),
                        control2: CGPoint(x: width * 0.82, y: height * 0.20)
                    )
                }
                .trim(from: 0, to: progress)
                .stroke(page.tint, style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))

                HStack(spacing: 8) {
                    Image(systemName: "function")
                    Text(stepThree ? "模型稳定" : "计算中")
                }
                .font(.caption.weight(.bold))
                .foregroundStyle(.white.opacity(0.72))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(.white.opacity(0.070), in: Capsule())
                .position(x: width * 0.23, y: height * 0.18)
                .opacity(stepTwo ? 1 : 0)
            }
        }
    }

    private func trendFactor(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(.headline.weight(.bold))
                .foregroundStyle(.white)
            Text(title)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white.opacity(0.46))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(.white.opacity(0.050), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func chatMessage(_ text: String, isUser: Bool) -> some View {
        Text(text)
            .font(.callout.weight(.semibold))
            .foregroundStyle(.white.opacity(isUser ? 0.92 : 0.78))
            .lineLimit(3)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: 250, alignment: .leading)
            .background(isUser ? page.tint.opacity(0.22) : .white.opacity(0.070), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .frame(maxWidth: .infinity, alignment: isUser ? .trailing : .leading)
    }

    private func riskLine(title: String, detail: String) -> some View {
        HStack(spacing: 9) {
            RoundedRectangle(cornerRadius: 4)
                .fill(page.tint.opacity(0.45))
                .frame(width: 4, height: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white.opacity(0.88))
                Text(detail)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.white.opacity(0.54))
            }
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func trendBadge(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.white.opacity(0.44))
            Text(value)
                .font(.caption.weight(.bold))
                .foregroundStyle(.white.opacity(0.86))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func pdfMetric(_ title: String, value: String) -> some View {
        HStack {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.caption.weight(.bold))
                .foregroundStyle(.primary)
        }
    }

    private func pdfPage(rotation: Double, offset: CGSize, opacity: Double) -> some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(.white.opacity(opacity))
            .frame(width: 202, height: 140)
            .rotationEffect(.degrees(rotation))
            .offset(offset)
    }

    private func liveActivityAction(_ title: String, selected: Bool) -> some View {
        Text(title)
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(selected ? .black : .white.opacity(0.74))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(selected ? page.tint : .white.opacity(0.12), in: Capsule())
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

struct OnboardingBlurSwapText: View {
    @AppStorage("prefersReducedAppMotion") private var prefersReducedAppMotion = false
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion

    let initialText: String
    let finalText: String
    let showsFinal: Bool
    let font: Font
    let initialColor: Color
    let finalColor: Color
    let alignment: Alignment

    @State private var displaysFinal: Bool
    @State private var contentOpacity = 1.0
    @State private var blurRadius = 0.0
    @State private var contentScale = 1.0

    init(
        initialText: String,
        finalText: String,
        showsFinal: Bool,
        font: Font,
        initialColor: Color,
        finalColor: Color,
        alignment: Alignment
    ) {
        self.initialText = initialText
        self.finalText = finalText
        self.showsFinal = showsFinal
        self.font = font
        self.initialColor = initialColor
        self.finalColor = finalColor
        self.alignment = alignment
        _displaysFinal = State(initialValue: showsFinal)
    }

    var body: some View {
        ZStack(alignment: alignment) {
            Text(initialText)
                .font(font)
                .hidden()
                .accessibilityHidden(true)
            Text(finalText)
                .font(font)
                .hidden()
                .accessibilityHidden(true)
            Text(displaysFinal ? finalText : initialText)
                .font(font)
                .foregroundStyle(displaysFinal ? finalColor : initialColor)
                .opacity(contentOpacity)
                .blur(radius: blurRadius)
                .scaleEffect(contentScale)
        }
        .compositingGroup()
            .task(id: showsFinal) {
                await replaceDisplayedTextIfNeeded()
            }
    }

    @MainActor
    private func replaceDisplayedTextIfNeeded() async {
        guard displaysFinal != showsFinal else {
            contentOpacity = 1
            blurRadius = 0
            contentScale = 1
            return
        }

        guard !prefersReducedAppMotion, !accessibilityReduceMotion else {
            displaysFinal = showsFinal
            contentOpacity = 1
            blurRadius = 0
            contentScale = 1
            return
        }

        withAnimation(.easeOut(duration: 0.13)) {
            contentOpacity = 0
            blurRadius = 6
            contentScale = 0.985
        }
        try? await Task.sleep(for: .milliseconds(150))
        guard !Task.isCancelled else { return }

        displaysFinal = showsFinal
        withAnimation(.smooth(duration: 0.24)) {
            contentOpacity = 1
            blurRadius = 0
            contentScale = 1
        }
    }
}

extension View {
    func firstLaunchCTAStyle(tint: Color) -> some View {
        modifier(FirstLaunchCTAStyle(tint: tint))
    }

    func onboardingPreviewPanel(tint: Color) -> some View {
        self
            .background(
                LinearGradient(
                    colors: [
                        Color(red: 0.078, green: 0.088, blue: 0.104).opacity(0.52),
                        tint.opacity(0.070),
                        Color(red: 0.028, green: 0.033, blue: 0.042).opacity(0.40)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: RoundedRectangle(cornerRadius: 30, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .stroke(
                        LinearGradient(colors: [.white.opacity(0.045), tint.opacity(0.045), .clear], startPoint: .topLeading, endPoint: .bottomTrailing),
                        lineWidth: 1
                    )
            )
    }
}

struct FirstLaunchCTAStyle: ViewModifier {
    let tint: Color

    func body(content: Content) -> some View {
        let cornerRadius: CGFloat = 28
        let styledContent = content
            .font(.headline.weight(.bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 32)
            .frame(height: 56)
            .frame(minWidth: 156)
            .background(
                LinearGradient(
                    colors: [
                        tint.opacity(0.78),
                        tint.opacity(0.56),
                        Color.white.opacity(0.06)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(.white.opacity(0.13), lineWidth: 1)
            )
            .shadow(color: tint.opacity(0.20), radius: 18, x: 0, y: 10)
            .buttonStyle(.plain)

        if #available(iOS 26.0, *) {
            styledContent
                .glassEffect(.regular.tint(tint.opacity(0.16)).interactive(), in: .rect(cornerRadius: cornerRadius))
        } else {
            styledContent
        }
    }
}

struct FirstLaunchPageDots: View {
    let count: Int
    let selectedIndex: Int
    let selectedTint: Color

    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<count, id: \.self) { index in
                Capsule()
                    .fill(index == selectedIndex ? selectedTint : Color.white.opacity(0.20))
                    .frame(width: index == selectedIndex ? 24 : 8, height: 8)
                    .animation(.snappy(duration: 0.25), value: selectedIndex)
            }
        }
        .accessibilityLabel("第 \(selectedIndex + 1) 页，共 \(count) 页")
    }
}
