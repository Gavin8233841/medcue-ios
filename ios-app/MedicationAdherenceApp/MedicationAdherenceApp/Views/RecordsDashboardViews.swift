import MedicationAdherenceCore
import SwiftData
import SwiftUI

struct RecordsPanelContainer<Content: View>: View {
    let title: String
    let subtitle: String?
    let tint: Color
    @ViewBuilder var content: Content

    init(title: String, subtitle: String? = nil, tint: Color = .blue, @ViewBuilder content: () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.tint = tint
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline)
                if let subtitle {
                    Text(subtitle)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .medicationGlassSurface(cornerRadius: 16, tint: tint, fallbackMaterial: .thinMaterial)
        .shadow(color: Color.black.opacity(0.03), radius: 9, x: 0, y: 4)
    }
}

struct RecordsEmptyStateLine: View {
    let systemImage: String
    let title: String
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(.secondary.opacity(0.09))
                Image(systemName: systemImage)
                    .foregroundStyle(.secondary)
            }
            .frame(width: 38, height: 38)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 4)
    }
}

struct RecordsTrendPreviewCard: View {
    let dashboard: MedicationTrendDashboard?

    private var direction: MedicationTrendDirection {
        dashboard?.direction ?? .needsData
    }

    private var tint: Color {
        trendDirectionTint(direction)
    }

    private var scoreText: String {
        guard let dashboard else {
            return "--"
        }
        return "\(Int((dashboard.overallScore * 100).rounded()))%"
    }

    private var subtitle: String {
        dashboard?.summary ?? "至少一周记录后生成趋势。"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: trendDirectionIconName(direction))
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(tint)
                    .frame(width: 44, height: 44)
                    .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                VStack(alignment: .leading, spacing: 5) {
                    Text("用药趋势")
                        .font(.title3.weight(.semibold))
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)

                VStack(alignment: .trailing, spacing: 3) {
                    Text(scoreText)
                        .font(.system(.title3, design: .rounded).weight(.bold))
                        .foregroundStyle(tint)
                        .monospacedDigit()
                        .contentTransition(.numericText())
                    Text(trendDirectionTitle(direction))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }

            ProgressView(value: dashboard?.overallScore ?? 0)
                .tint(tint)

            HStack(spacing: 8) {
                ForEach(Array((dashboard?.metrics ?? []).prefix(3)), id: \.topic) { metric in
                    RecordsTrendMiniMetric(metric: metric)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .medicationGlassSurface(cornerRadius: 16, tint: tint, fallbackMaterial: .thinMaterial)
        .shadow(color: Color.black.opacity(0.035), radius: 10, x: 0, y: 4)
    }
}

struct RecordsTrendMiniMetric: View {
    let metric: MedicationTrendMetric

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(metric.title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text(metric.direction == .needsData ? "暂无" : "\(Int((metric.score * 100).rounded()))%")
                .font(.caption.weight(.bold))
                .foregroundStyle(trendDirectionTint(metric.direction))
                .monospacedDigit()
                .contentTransition(.numericText())
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(trendDirectionTint(metric.direction).opacity(0.09), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

enum RecordsTrendPreviewSignature {
    static func id(
        tasks: [StoredDoseTask],
        doseChanges: [StoredMedicationDoseChange],
        medications: [StoredMedication],
        plans: [StoredMedicationPlan],
        lifecycleEvents: [StoredMedicationLifecycleEvent]
    ) -> String {
        [
            stableTaskSignature(tasks),
            stableDoseChangeSignature(doseChanges),
            stableMedicationSignature(medications),
            stablePlanSignature(plans),
            stableLifecycleEventSignature(lifecycleEvents)
        ]
        .map(String.init)
        .joined(separator: "|")
    }
}

struct RecordsDisclosureButtonLabel: View {
    let title: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 10) {
            Text(title)
                .font(.subheadline.weight(.semibold))
            Spacer()
            Image(systemName: systemImage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .foregroundStyle(.primary.opacity(0.86))
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .background(.secondary.opacity(0.055), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

struct RecordsModuleIndexCard<
    OverviewDestination: View,
    CalendarDestination: View,
    TrendDestination: View,
    HistoryDestination: View
>: View {
    let insight: AdherenceInsight
    let historyCount: Int
    let latestHistoryTask: StoredDoseTask?
    let weekSummaryCounts: (completed: Int, total: Int, skipped: Int, delayed: Int)
    let weekDays: [Date]
    let tasksForDay: (Date) -> [StoredDoseTask]
    let doseChangesForDay: (Date) -> [StoredMedicationDoseChange]
    let dashboard: MedicationTrendDashboard?
    private let overviewDestination: () -> OverviewDestination
    private let calendarDestination: () -> CalendarDestination
    private let trendDestination: () -> TrendDestination
    private let historyDestination: () -> HistoryDestination

    init(
        insight: AdherenceInsight,
        historyCount: Int,
        latestHistoryTask: StoredDoseTask?,
        weekSummaryCounts: (completed: Int, total: Int, skipped: Int, delayed: Int),
        weekDays: [Date],
        tasksForDay: @escaping (Date) -> [StoredDoseTask],
        doseChangesForDay: @escaping (Date) -> [StoredMedicationDoseChange],
        dashboard: MedicationTrendDashboard?,
        @ViewBuilder overviewDestination: @escaping () -> OverviewDestination,
        @ViewBuilder calendarDestination: @escaping () -> CalendarDestination,
        @ViewBuilder trendDestination: @escaping () -> TrendDestination,
        @ViewBuilder historyDestination: @escaping () -> HistoryDestination
    ) {
        self.insight = insight
        self.historyCount = historyCount
        self.latestHistoryTask = latestHistoryTask
        self.weekSummaryCounts = weekSummaryCounts
        self.weekDays = weekDays
        self.tasksForDay = tasksForDay
        self.doseChangesForDay = doseChangesForDay
        self.dashboard = dashboard
        self.overviewDestination = overviewDestination
        self.calendarDestination = calendarDestination
        self.trendDestination = trendDestination
        self.historyDestination = historyDestination
    }

    private var completionPercent: Int {
        Int((insight.completionRate * 100).rounded())
    }

    private var trendValue: String {
        guard let dashboard else {
            return "待积累"
        }
        return "\(Int((dashboard.overallScore * 100).rounded()))%"
    }

    private var trendSubtitle: String {
        guard let dashboard else {
            return "继续记录 · 满 7 天生成"
        }
        return "\(trendDirectionTitle(dashboard.direction)) · 置信度 \(Int((dashboard.confidenceScore * 100).rounded()))%"
    }

    private var historySubtitle: String {
        guard let latestHistoryTask else {
            return "暂无过去记录"
        }
        return "最近 \(AppFormatters.day.string(from: latestHistoryTask.effectiveAdherenceDate))"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            MedicationGlassGroup(spacing: 10) {
                RecordsModuleNavigationTile(
                    title: "概览",
                    value: "\(completionPercent)%",
                    detail: "连续 \(insight.currentStreakDays) 天 · \(historyCount) 条",
                    tint: RecordsModulePalette.overview,
                    systemImage: "chart.bar.fill",
                    destination: overviewDestination
                ) {
                    RecordsModuleProgressPreview(
                        progress: insight.completionRate,
                        leadingText: "完成率",
                        trailingText: "\(completionPercent)%",
                        tint: RecordsModulePalette.overview
                    )
                }
                RecordsCalendarModuleNavigationTile(
                    title: "日历",
                    value: "\(weekSummaryCounts.completed)/\(weekSummaryCounts.total)",
                    detail: "本周完成",
                    tint: RecordsModulePalette.calendar,
                    systemImage: "calendar",
                    days: weekDays,
                    tasksForDay: tasksForDay,
                    doseChangesForDay: doseChangesForDay,
                    destination: calendarDestination
                )
                RecordsModuleNavigationTile(
                    title: "趋势",
                    value: trendValue,
                    detail: trendSubtitle,
                    tint: RecordsModulePalette.trend,
                    systemImage: "chart.line.uptrend.xyaxis",
                    destination: trendDestination
                ) {
                    RecordsModuleTrendPreview(dashboard: dashboard, tint: RecordsModulePalette.trend)
                }
                RecordsModuleNavigationTile(
                    title: "记录",
                    value: "\(historyCount)",
                    detail: historySubtitle,
                    tint: RecordsModulePalette.history,
                    systemImage: "clock.arrow.circlepath",
                    destination: historyDestination
                ) {
                    RecordsModuleHistoryPreview(latestTask: latestHistoryTask, tint: RecordsModulePalette.history)
                }
            }
        }
    }
}

enum RecordsModulePalette {
    static let overview = Color(red: 0.46, green: 0.58, blue: 0.64)
    static let calendar = Color(red: 0.42, green: 0.60, blue: 0.51)
    static let trend = Color(red: 0.56, green: 0.50, blue: 0.69)
    static let history = Color(red: 0.62, green: 0.55, blue: 0.44)
}

struct RecordsModuleNavigationTile<Destination: View, Preview: View>: View {
    let title: String
    let value: String
    let detail: String
    let tint: Color
    let systemImage: String
    private let destination: () -> Destination
    @ViewBuilder private let preview: Preview

    init(
        title: String,
        value: String,
        detail: String,
        tint: Color,
        systemImage: String,
        @ViewBuilder destination: @escaping () -> Destination,
        @ViewBuilder preview: () -> Preview
    ) {
        self.title = title
        self.value = value
        self.detail = detail
        self.tint = tint
        self.systemImage = systemImage
        self.destination = destination
        self.preview = preview()
    }

    var body: some View {
        NavigationLink {
            destination()
        } label: {
            RecordsModuleTileChrome(title: title, value: value, detail: detail, tint: tint, systemImage: systemImage) {
                preview
            }
        }
        .buttonStyle(.plain)
    }
}

extension RecordsModuleNavigationTile where Preview == EmptyView {
    init(
        title: String,
        value: String,
        detail: String,
        tint: Color,
        systemImage: String,
        @ViewBuilder destination: @escaping () -> Destination
    ) {
        self.init(
            title: title,
            value: value,
            detail: detail,
            tint: tint,
            systemImage: systemImage,
            destination: destination
        ) {
            EmptyView()
        }
    }
}

struct RecordsCalendarModuleNavigationTile<Destination: View>: View {
    let title: String
    let value: String
    let detail: String
    let tint: Color
    let systemImage: String
    let days: [Date]
    let tasksForDay: (Date) -> [StoredDoseTask]
    let doseChangesForDay: (Date) -> [StoredMedicationDoseChange]
    private let destination: () -> Destination

    init(
        title: String,
        value: String,
        detail: String,
        tint: Color,
        systemImage: String,
        days: [Date],
        tasksForDay: @escaping (Date) -> [StoredDoseTask],
        doseChangesForDay: @escaping (Date) -> [StoredMedicationDoseChange],
        @ViewBuilder destination: @escaping () -> Destination
    ) {
        self.title = title
        self.value = value
        self.detail = detail
        self.tint = tint
        self.systemImage = systemImage
        self.days = days
        self.tasksForDay = tasksForDay
        self.doseChangesForDay = doseChangesForDay
        self.destination = destination
    }

    var body: some View {
        NavigationLink {
            destination()
        } label: {
            RecordsModuleTileChrome(title: title, value: value, detail: detail, tint: tint, systemImage: systemImage) {
                RecordsIndexWeekStrip(
                    days: days,
                    tasksForDay: tasksForDay,
                    doseChangesForDay: doseChangesForDay,
                    tint: tint
                )
            }
        }
        .buttonStyle(.plain)
    }
}

struct RecordsModuleTileChrome<Preview: View>: View {
    let title: String
    let value: String
    let detail: String
    let tint: Color
    let systemImage: String
    @ViewBuilder var preview: Preview

    init(
        title: String,
        value: String,
        detail: String,
        tint: Color,
        systemImage: String,
        @ViewBuilder preview: () -> Preview
    ) {
        self.title = title
        self.value = value
        self.detail = detail
        self.tint = tint
        self.systemImage = systemImage
        self.preview = preview()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 15, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [tint.opacity(0.18), tint.opacity(0.08)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    Image(systemName: systemImage)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(tint)
                }
                .frame(width: 42, height: 42)

                Text(title)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Spacer(minLength: 8)

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }

            HStack(alignment: .lastTextBaseline, spacing: 10) {
                Text(value)
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(tint)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)

                Text(detail)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)

                Spacer(minLength: 0)
            }

            preview
                .frame(height: 42, alignment: .bottom)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 15)
        .frame(maxWidth: .infinity, minHeight: 164, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            tint.opacity(0.105),
                            tint.opacity(0.045),
                            Color(.systemBackground).opacity(0.05)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        }
        .medicationGlassSurface(cornerRadius: 22, tint: tint, fallbackMaterial: .thinMaterial, isInteractive: true)
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [tint.opacity(0.18), Color.white.opacity(0.08), tint.opacity(0.08)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.8
                )
        }
        .shadow(color: tint.opacity(0.07), radius: 14, x: 0, y: 6)
    }
}

extension RecordsModuleTileChrome where Preview == EmptyView {
    init(title: String, value: String, detail: String, tint: Color, systemImage: String) {
        self.init(title: title, value: value, detail: detail, tint: tint, systemImage: systemImage) {
            EmptyView()
        }
    }
}

struct RecordsModuleProgressPreview: View {
    let progress: Double
    let leadingText: String
    let trailingText: String
    let tint: Color

    private var clampedProgress: Double {
        min(max(progress, 0), 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(tint.opacity(0.11))
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [tint.opacity(0.56), tint.opacity(0.30)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: max(8, proxy.size.width * clampedProgress))
                }
            }
            .frame(height: 5)

            HStack(spacing: 8) {
                Text(leadingText)
                Spacer(minLength: 8)
                Text(trailingText)
                    .monospacedDigit()
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
        }
        .padding(.top, 2)
    }
}

struct RecordsModuleTrendPreview: View {
    let dashboard: MedicationTrendDashboard?
    let tint: Color

    private var progress: Double {
        guard let dashboard else {
            return 0.18
        }
        return min(max(dashboard.overallScore, 0), 1)
    }

    private var leadingText: String {
        dashboard == nil ? "趋势准备中" : "综合趋势"
    }

    private var trailingText: String {
        guard let dashboard else {
            return "继续记录"
        }
        return trendDirectionTitle(dashboard.direction)
    }

    var body: some View {
        RecordsModuleProgressPreview(
            progress: progress,
            leadingText: leadingText,
            trailingText: trailingText,
            tint: tint
        )
    }
}

struct RecordsModuleHistoryPreview: View {
    let latestTask: StoredDoseTask?
    let tint: Color

    var body: some View {
        HStack(spacing: 8) {
            statusCapsule(text: latestStatusText, emphasized: latestTask != nil)
            statusCapsule(text: "可修正", emphasized: false)
            Spacer(minLength: 0)
        }
        .padding(.top, 1)
    }

    private var latestStatusText: String {
        guard let latestTask else {
            return "暂无记录"
        }
        switch latestTask.status {
        case .taken:
            return "最近已服用"
        case .corrected:
            return "最近已修正"
        case .skipped:
            return "最近已忽略"
        case .delayed:
            return "最近稍后"
        case .pending:
            return "最近待处理"
        }
    }

    private func statusCapsule(text: String, emphasized: Bool) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(emphasized ? tint : Color.secondary)
            .lineLimit(1)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule(style: .continuous)
                    .fill(emphasized ? tint.opacity(0.12) : Color.secondary.opacity(0.075))
            )
    }
}

struct RecordsCalendarProgressRing: View {
    let progress: Double
    let color: Color
    let isEmpty: Bool
    var size: CGFloat = 34
    var lineWidth: CGFloat = 4

    private var clampedProgress: Double {
        min(max(progress, 0), 1)
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.secondary.opacity(isEmpty ? 0.12 : 0.16), lineWidth: lineWidth)
            if !isEmpty {
                Circle()
                    .trim(from: 0, to: max(clampedProgress, 0.06))
                    .stroke(
                        color.opacity(clampedProgress == 0 ? 0.34 : 0.76),
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
            }
        }
        .frame(width: size, height: size)
    }
}

struct RecordsIndexWeekStrip: View {
    let days: [Date]
    let tasksForDay: (Date) -> [StoredDoseTask]
    let doseChangesForDay: (Date) -> [StoredMedicationDoseChange]
    let tint: Color

    private let calendar = Calendar.current

    var body: some View {
        HStack(spacing: 5) {
            ForEach(days, id: \.self) { day in
                let tasks = tasksForDay(day)
                let completed = tasks.filter { $0.status == .taken || $0.status == .corrected }.count
                let total = tasks.count
                let hasDoseChange = !doseChangesForDay(day).isEmpty
                VStack(spacing: 3) {
                    Text(weekdayText(for: day))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                    ZStack(alignment: .center) {
                        RecordsCalendarProgressRing(
                            progress: progress(completed: completed, total: total),
                            color: dayIndicatorColor(completed: completed, total: total, hasDoseChange: hasDoseChange),
                            isEmpty: total == 0,
                            size: 26,
                            lineWidth: 3
                        )
                        Text(dayNumberText(for: day))
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(calendar.isDateInToday(day) ? tint : .primary.opacity(0.76))
                        if hasDoseChange {
                            Circle()
                                .fill(Color.purple.opacity(0.76))
                                .frame(width: 5.5, height: 5.5)
                                .frame(width: 26, height: 26, alignment: .topTrailing)
                                .offset(x: 1.5, y: -1.5)
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(calendar.isDateInToday(day) ? tint.opacity(0.12) : Color.secondary.opacity(0.035))
                        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                )
                .accessibilityHidden(true)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
    }

    private var accessibilitySummary: String {
        let daySummaries = days.map { day in
            let tasks = tasksForDay(day)
            let completed = tasks.filter { $0.status == .taken || $0.status == .corrected }.count
            return "\(weekdayText(for: day)) \(dayNumberText(for: day)) \(summaryText(completed: completed, total: tasks.count))"
        }
        return "本周日历预览，\(daySummaries.joined(separator: "，"))"
    }

    private func weekdayText(for date: Date) -> String {
        let index = calendar.component(.weekday, from: date) - 1
        let symbols = ["日", "一", "二", "三", "四", "五", "六"]
        return symbols.indices.contains(index) ? symbols[index] : ""
    }

    private func dayNumberText(for date: Date) -> String {
        String(calendar.component(.day, from: date))
    }

    private func summaryText(completed: Int, total: Int) -> String {
        guard total > 0 else {
            return "—"
        }
        if completed == 0 {
            return "\(total)项"
        }
        return "\(completed)/\(total)"
    }

    private func progress(completed: Int, total: Int) -> Double {
        total == 0 ? 0 : Double(completed) / Double(total)
    }

    private func dayIndicatorColor(completed: Int, total: Int, hasDoseChange: Bool) -> Color {
        if hasDoseChange {
            return Color(red: 0.56, green: 0.50, blue: 0.69).opacity(0.62)
        }
        guard total > 0 else {
            return Color.secondary.opacity(0.18)
        }
        if completed == total {
            return Color(red: 0.42, green: 0.60, blue: 0.51).opacity(0.68)
        }
        if completed > 0 {
            return tint.opacity(0.58)
        }
        return Color.secondary.opacity(0.28)
    }
}

