import Charts
import MedicationAdherenceCore
import SwiftUI
import UIKit

struct MedicationTrendLineChart: View {
    let metric: MedicationTrendMetric
    @Binding var selectedDate: Date?

    private var points: [MedicationTrendChartPoint] {
        metric.points.map {
            MedicationTrendChartPoint(
                date: trendDate(from: $0.date),
                score: $0.score,
                doseChangeCount: $0.doseChangeCount,
                archivedMedicationCount: $0.archivedMedicationCount,
                interruptedMedicationCount: $0.interruptedMedicationCount,
                healthSignalCount: $0.healthSignalCount,
                annotation: $0.annotation
            )
        }
    }

    private var sortedPoints: [MedicationTrendChartPoint] {
        points.sorted { $0.date < $1.date }
    }

    private var renderedPoints: [MedicationTrendRenderedPoint] {
        sortedPoints.enumerated().map { index, point in
            let startIndex = max(0, index - 2)
            let endIndex = min(sortedPoints.count - 1, index + 1)
            let window = sortedPoints[startIndex...endIndex]
            let smoothedScore = window.reduce(0) { partialResult, item in
                partialResult + item.chartScore
            } / Double(window.count)
            return MedicationTrendRenderedPoint(point: point, visualScore: smoothedScore)
        }
    }

    private var eventPoints: [MedicationTrendRenderedPoint] {
        renderedPoints.filter(\.point.hasEventMarker)
    }

    private var selectedPoint: MedicationTrendChartPoint? {
        guard let selectedDate else {
            return sortedPoints.last
        }
        return sortedPoints.min { lhs, rhs in
            abs(lhs.date.timeIntervalSince(selectedDate)) < abs(rhs.date.timeIntervalSince(selectedDate))
        }
    }

    private var selectedRenderedPoint: MedicationTrendRenderedPoint? {
        guard let selectedPoint else {
            return renderedPoints.last
        }
        return renderedPoints.first { $0.point.id == selectedPoint.id }
    }

    private var chartAxisValues: [Double] {
        [0, 0.5, 0.8, 1]
    }

    private var chartXDomain: ClosedRange<Date> {
        guard let first = sortedPoints.first?.date, let last = sortedPoints.last?.date else {
            let today = Calendar.current.startOfDay(for: Date())
            return today...today
        }
        let calendar = Calendar.current
        let start = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: first)) ?? first
        let end = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: last)) ?? last
        return start...end
    }

    private var chartXAxisLabelDates: [Date] {
        guard let first = sortedPoints.first?.date, let last = sortedPoints.last?.date else {
            return []
        }
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: first)
        let end = calendar.startOfDay(for: last)
        let daySpan = max(1, calendar.dateComponents([.day], from: start, to: end).day ?? sortedPoints.count)
        let step = max(2, Int(ceil(Double(daySpan) / 4.0)))
        var dates: [Date] = []
        var current = start
        while current < end {
            dates.append(current)
            guard let next = calendar.date(byAdding: .day, value: step, to: current), next > current else {
                break
            }
            current = next
        }
        return dates
    }

    private var visibleDomainLength: Int {
        let visibleDays = min(14, max(7, sortedPoints.count))
        return visibleDays * 24 * 60 * 60
    }

    private var chartInitialScrollDate: Date {
        guard let last = sortedPoints.last?.date else {
            return Date()
        }
        let calendar = Calendar.current
        return calendar.date(byAdding: .day, value: -min(13, max(6, sortedPoints.count - 1)), to: last) ?? last
    }

    var body: some View {
        let tint = trendDirectionTint(metric.direction)
        VStack(alignment: .leading, spacing: 14) {
            if let selectedPoint {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(AppFormatters.day.string(from: selectedPoint.date))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(selectedPointValueText(selectedPoint))
                            .font(.title2.monospacedDigit().weight(.bold))
                            .foregroundStyle(tint)
                    }

                    Spacer(minLength: 8)

                    if selectedPoint.hasEventMarker {
                        Image(systemName: eventMarkerIconName(for: selectedPoint))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(eventMarkerTint(for: selectedPoint))
                            .frame(width: 30, height: 30)
                            .background(eventMarkerTint(for: selectedPoint).opacity(0.12), in: Circle())
                    }
                }
            }

            Chart {
                ForEach(renderedPoints) { renderedPoint in
                    AreaMark(
                        x: .value("日期", renderedPoint.date),
                        yStart: .value("下限", 0),
                        yEnd: .value("分数", renderedPoint.visualScore)
                    )
                    .interpolationMethod(.monotone)
                    .foregroundStyle(
                        LinearGradient(
                            colors: [tint.opacity(0.20), tint.opacity(0.04)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                    LineMark(
                        x: .value("日期", renderedPoint.date),
                        y: .value("分数", renderedPoint.visualScore)
                    )
                    .interpolationMethod(.monotone)
                    .foregroundStyle(tint)
                    .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                }

                ForEach(eventPoints) { renderedPoint in
                    PointMark(
                        x: .value("事件日期", renderedPoint.date),
                        y: .value("事件分数", renderedPoint.visualScore)
                    )
                    .symbolSize(selectedPoint?.id == renderedPoint.id ? 82 : 52)
                    .foregroundStyle(eventMarkerTint(for: renderedPoint.point))
                }

                RuleMark(y: .value("参考线", 0.8))
                    .foregroundStyle(Color.secondary.opacity(0.26))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))

                if let selectedPoint, let selectedRenderedPoint {
                    RuleMark(x: .value("选中日期", selectedPoint.date))
                        .foregroundStyle(tint.opacity(0.42))
                        .lineStyle(StrokeStyle(lineWidth: 1))

                    PointMark(
                        x: .value("选中日期", selectedPoint.date),
                        y: .value("选中趋势", selectedRenderedPoint.visualScore)
                    )
                    .symbolSize(64)
                    .foregroundStyle(tint)
                }
            }
            .chartXScale(domain: chartXDomain)
            .chartYScale(domain: 0...1)
            .chartScrollableAxes(.horizontal)
            .chartXVisibleDomain(length: visibleDomainLength)
            .chartScrollPosition(initialX: chartInitialScrollDate)
            .chartXSelection(value: $selectedDate)
            .chartYAxis {
                AxisMarks(position: .leading, values: chartAxisValues) { value in
                    AxisGridLine()
                        .foregroundStyle(Color.secondary.opacity(0.16))
                    AxisValueLabel {
                        if let score = value.as(Double.self) {
                            Text("\(percentageText(score))%")
                                .font(.caption2.monospacedDigit())
                        }
                    }
                }
            }
            .chartXAxis {
                AxisMarks(values: chartXAxisLabelDates) {
                    AxisGridLine()
                        .foregroundStyle(Color.secondary.opacity(0.10))
                    AxisValueLabel(format: .dateTime.month(.defaultDigits).day())
                        .font(.caption2)
                }
            }
            .frame(height: 230)
        }
        .padding(14)
        .medicationGlassSurface(cornerRadius: 18, tint: tint, fallbackMaterial: .regularMaterial, isInteractive: true)
        .accessibilityLabel("\(metric.title)趋势曲线")
    }

    private func selectedPointValueText(_ point: MedicationTrendChartPoint) -> String {
        if metric.topic == .healthSignal && point.healthSignalCount == 0 {
            return "暂无数据"
        }
        return "\(percentageText(point.score))%"
    }

    private func eventMarkerTint(for point: MedicationTrendChartPoint) -> Color {
        if point.doseChangeCount > 0 {
            return .purple
        }
        if point.archivedMedicationCount > 0 || point.interruptedMedicationCount > 0 {
            return .orange
        }
        if point.healthSignalCount > 0 {
            return .teal
        }
        return trendDirectionTint(metric.direction)
    }

    private func eventMarkerIconName(for point: MedicationTrendChartPoint) -> String {
        if point.doseChangeCount > 0 {
            return "arrow.triangle.2.circlepath"
        }
        if point.archivedMedicationCount > 0 {
            return "archivebox.fill"
        }
        if point.interruptedMedicationCount > 0 {
            return "pause.circle.fill"
        }
        if point.healthSignalCount > 0 {
            return "heart.text.square.fill"
        }
        return "circle.fill"
    }
}

struct MedicationTrendRenderedPoint: Identifiable {
    let point: MedicationTrendChartPoint
    let visualScore: Double

    var id: Date { point.id }
    var date: Date { point.date }
}

struct MedicationTrendEventLegend: View {
    let metric: MedicationTrendMetric

    private var items: [TrendEventLegendItem] {
        var result: [TrendEventLegendItem] = []
        if metric.points.contains(where: { $0.doseChangeCount > 0 }) {
            result.append(TrendEventLegendItem(title: "剂量变化", color: .purple, iconName: "arrow.triangle.2.circlepath"))
        }
        if metric.points.contains(where: { $0.interruptedMedicationCount > 0 || $0.archivedMedicationCount > 0 }) {
            result.append(TrendEventLegendItem(title: "状态变化", color: .orange, iconName: "pause.circle.fill"))
        }
        if metric.points.contains(where: { $0.healthSignalCount > 0 }) {
            result.append(TrendEventLegendItem(title: "健康数据", color: .teal, iconName: "heart.text.square.fill"))
        }
        return result
    }

    var body: some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("事件标记")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    ForEach(items) { item in
                        Label {
                            Text(item.title)
                                .font(.caption.weight(.semibold))
                                .lineLimit(1)
                                .minimumScaleFactor(0.82)
                        } icon: {
                            Image(systemName: item.iconName)
                                .font(.caption.weight(.bold))
                        }
                        .foregroundStyle(item.color)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 6)
                        .background(item.color.opacity(0.12), in: Capsule())
                    }
                }
            }
            .padding(.bottom, 4)
            .accessibilityElement(children: .combine)
        }
    }
}

struct TrendEventLegendItem: Identifiable {
    let title: String
    let color: Color
    let iconName: String

    var id: String { title }
}

struct MedicationTrendPointDetail: View {
    let point: MedicationTrendPoint
    let topic: MedicationTrendTopic

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(AppFormatters.day.string(from: trendDate(from: point.date)))
                    .font(.headline)
                Spacer()
                Text(pointValueText)
                    .font(.headline.monospacedDigit())
            }

            TrendPointStatGrid(point: point)

            if !detailText.isEmpty {
                Text(detailText)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            if !eventBadges.isEmpty {
                VStack(alignment: .leading, spacing: 7) {
                    Text("当日事件")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    StatusBadgeFlow {
                        ForEach(eventBadges, id: \.text) { badge in
                            StatusBadge(text: badge.text, color: badge.color)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8))
    }

    private var pointValueText: String {
        if topic == .healthSignal && point.healthSignalCount == 0 {
            return "暂无数据"
        }
        return "\(percentageText(point.score))%"
    }

    private var detailText: String {
        if !point.annotation.isEmpty {
            return point.annotation
        }
        switch topic {
        case .discipline:
            return ""
        case .timing:
            return ""
        case .doseChange:
            return point.doseChangeCount == 0 ? "" : "当天记录 \(point.doseChangeCount) 次剂量变化。"
        case .regimenLoad:
            var parts: [String] = []
            if point.prescriptionMedicationCount > 0 {
                parts.append("\(point.prescriptionMedicationCount) 个处方药计划")
            }
            if point.nonPrescriptionMedicationCount > 0 {
                parts.append("\(point.nonPrescriptionMedicationCount) 个非处方药计划")
            }
            if point.interruptedMedicationCount > 0 {
                parts.append("\(point.interruptedMedicationCount) 个中断状态")
            }
            if point.archivedMedicationCount > 0 {
                parts.append("\(point.archivedMedicationCount) 个归档状态或操作")
            }
            if point.importedMedicationCount > 0 {
                parts.append("\(point.importedMedicationCount) 个导入来源计划")
            }
            return parts.joined(separator: "，")
        case .healthSignal:
            return point.healthSignalCount == 0 ? "" : "当天有 \(point.healthSignalCount) 条授权健康数据。"
        }
    }

    private var eventBadges: [TrendEventBadge] {
        var badges: [TrendEventBadge] = []
        if point.doseChangeCount > 0 {
            badges.append(TrendEventBadge(text: "\(point.doseChangeCount) 次剂量变化", color: .purple))
        }
        if point.interruptedMedicationCount > 0 {
            badges.append(TrendEventBadge(text: "\(point.interruptedMedicationCount) 个中断状态", color: .orange))
        }
        if point.archivedMedicationCount > 0 {
            badges.append(TrendEventBadge(text: "\(point.archivedMedicationCount) 个归档状态", color: .gray))
        }
        if point.healthSignalCount > 0 {
            badges.append(TrendEventBadge(text: "\(point.healthSignalCount) 条健康数据", color: .teal))
        }
        return badges
    }
}

struct TrendPointStatGrid: View {
    let point: MedicationTrendPoint

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
            TrendPointMiniStat(title: "计划", value: "\(point.scheduledCount)", tint: .blue)
            TrendPointMiniStat(title: "完成", value: "\(point.completedCount)", tint: .green)
            TrendPointMiniStat(title: "稍后", value: "\(point.delayedCount)", tint: .orange)
            TrendPointMiniStat(title: "忽略", value: "\(point.skippedCount)", tint: .red)
        }
    }
}

struct TrendEventBadge {
    let text: String
    let color: Color
}

struct TrendPointMiniStat: View {
    let title: String
    let value: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.headline.monospacedDigit().weight(.bold))
                .foregroundStyle(tint)
                .contentTransition(.numericText())
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(tint.opacity(0.12), lineWidth: 1)
        )
    }
}

struct MedicationTrendChartPoint: Identifiable {
    let date: Date
    let score: Double
    let doseChangeCount: Int
    let archivedMedicationCount: Int
    let interruptedMedicationCount: Int
    let healthSignalCount: Int
    let annotation: String

    var id: Date { date }

    var hasEventMarker: Bool {
        doseChangeCount > 0
            || archivedMedicationCount > 0
            || interruptedMedicationCount > 0
            || healthSignalCount > 0
    }

    var chartScore: Double {
        min(1, max(0, score))
    }
}

func emptyTrendMetric(topic: MedicationTrendTopic) -> MedicationTrendMetric {
    MedicationTrendMetric(
        topic: topic,
        title: trendTopicTitle(topic),
        score: 0,
        direction: .needsData,
        summary: "继续记录后生成趋势。",
        dataSourceSummary: "",
        formulaSummary: "继续记录后生成透明的权重说明。",
        comparison: MedicationTrendPeriodComparison(
            recentScore: 0,
            confidenceScore: 0,
            recentDayCount: 0,
            previousDayCount: 0,
            recentScheduledCount: 0,
            previousScheduledCount: 0,
            evidenceSummary: "继续记录后生成数据质量说明。"
        ),
        contributorSummary: [],
        formulaComponents: [],
        points: []
    )
}

func trendTopicTitle(_ topic: MedicationTrendTopic) -> String {
    switch topic {
    case .discipline:
        "用药纪律"
    case .timing:
        "时间稳定"
    case .doseChange:
        "剂量变化"
    case .regimenLoad:
        "用药负担"
    case .healthSignal:
        "健康信号"
    }
}

func trendTopicIconName(_ topic: MedicationTrendTopic) -> String {
    switch topic {
    case .discipline:
        "checklist.checked"
    case .timing:
        "clock.badge.checkmark"
    case .doseChange:
        "arrow.triangle.2.circlepath"
    case .regimenLoad:
        "pills.fill"
    case .healthSignal:
        "heart.text.square.fill"
    }
}

func trendDate(from date: DateOnly) -> Date {
    Calendar.current.date(from: DateComponents(year: date.year, month: date.month, day: date.day, hour: 12)) ?? Date()
}

func trendDirectionTitle(_ direction: MedicationTrendDirection) -> String {
    switch direction {
    case .improving:
        "正在改善"
    case .stable:
        "趋势平稳"
    case .fluctuating:
        "近期波动"
    case .declining:
        "需要关注"
    case .needsData:
        "继续记录"
    }
}

func trendDirectionTint(_ direction: MedicationTrendDirection) -> Color {
    switch direction {
    case .improving:
        .green
    case .stable:
        .blue
    case .fluctuating:
        .teal
    case .declining:
        .orange
    case .needsData:
        .gray
    }
}

func trendDirectionIconName(_ direction: MedicationTrendDirection) -> String {
    switch direction {
    case .improving:
        "chart.line.uptrend.xyaxis"
    case .stable:
        "equal.circle.fill"
    case .fluctuating:
        "waveform.path.ecg"
    case .declining:
        "chart.line.downtrend.xyaxis"
    case .needsData:
        "chart.xyaxis.line"
    }
}

func metricComparisonText(_ comparison: MedicationTrendPeriodComparison) -> String {
    let recent = "\(comparison.recentPeriodTitle) \(percentageText(comparison.recentScore))%"
    guard comparison.previousScore != nil, let delta = comparison.delta else {
        return "\(recent)，前一周期不足"
    }
    return "\(recent)，较\(comparison.previousPeriodTitle) \(trendDeltaText(delta))"
}

func trendMetricValueText(_ metric: MedicationTrendMetric) -> String {
    if metric.direction == .needsData {
        return "暂无数据"
    }
    return "\(percentageText(metric.comparison.recentScore))%"
}

func trendMetricPrimaryValueTitle(_ metric: MedicationTrendMetric) -> String {
    metric.direction == .needsData ? "当前状态" : "近 7 天"
}

func trendMetricRecordDaysText(_ metric: MedicationTrendMetric) -> String {
    if metric.topic == .healthSignal {
        let daysWithSamples = metric.points.filter { $0.healthSignalCount > 0 }.count
        return daysWithSamples == 0 ? "等待授权样本" : "\(daysWithSamples) 天有健康数据"
    }
    return "\(metric.points.count) 天"
}

func normalizedTrendScore(_ value: Double) -> Double {
    min(1, max(0, value))
}

func trendScoreTint(_ score: Double) -> Color {
    if score >= 0.86 {
        return .green
    }
    if score >= 0.68 {
        return .blue
    }
    if score >= 0.48 {
        return .orange
    }
    return .red
}

func trendSlopeShortText(_ comparison: MedicationTrendPeriodComparison) -> String {
    if comparison.trendStrengthScore < 0.04 {
        return "近 7 天内部平稳"
    }
    let direction = comparison.trendSlopePerDay > 0 ? "上行" : "下行"
    let dailyPoints = Int((abs(comparison.trendSlopePerDay) * 100).rounded())
    return "\(direction)约 \(dailyPoints) 点/天"
}

func trendSlopeSummaryText(_ comparison: MedicationTrendPeriodComparison) -> String {
    let strength = percentageText(comparison.trendStrengthScore)
    if comparison.trendStrengthScore < 0.04 {
        return "近 7 天内部走势平稳，方向强度 \(strength)%"
    }
    let direction = comparison.trendSlopePerDay > 0 ? "上行" : "下行"
    let dailyPoints = Int((abs(comparison.trendSlopePerDay) * 100).rounded())
    return "近 7 天呈\(direction)，约 \(dailyPoints) 个百分点/天，方向强度 \(strength)%"
}

func trendDeltaText(_ delta: Double) -> String {
    let points = Int((abs(delta) * 100).rounded())
    if points == 0 {
        return "持平"
    }
    return delta > 0 ? "上升 \(points) 个百分点" : "下降 \(points) 个百分点"
}
