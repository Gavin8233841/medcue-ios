import AuthenticationServices
import Charts
import MedicationAdherenceCore
import OSLog
import QuickLook
import SwiftData
import SwiftUI
import UIKit

struct HealthDataSettingsView: View {
    @StateObject private var healthKitService = HealthKitService()
    @State private var pendingPermissionGate: AppPermissionGate?

    private var summary: HealthKitRecentSummary {
        healthKitService.recentSummary
    }

    var body: some View {
        List {
            Section {
                SettingsStatusRow(
                    iconName: "heart.text.square.fill",
                    tint: .red,
                    title: "Apple 健康",
                    subtitle: healthKitService.statusMessage
                )
                HealthKitSnapshotCard(
                    summary: summary,
                    supportedTypes: healthKitService.supportedReadTypesSummary,
                    hasCompletedAuthorizationRequest: healthKitService.hasCompletedAuthorizationRequest
                )
            }

            Section("近期健康信号") {
                if summary.metricSummaries.isEmpty {
                    SettingsStatusRow(
                        iconName: "waveform.path.ecg",
                        tint: .secondary,
                        title: "暂无近期样本",
                        subtitle: healthKitService.hasCompletedAuthorizationRequest ? "授权范围内还没有可读取的健康、睡眠和活动数据" : "完成授权请求后显示最近 56 天的健康、睡眠和活动数据"
                    )
                } else {
                    ForEach(summary.metricSummaries) { metric in
                        NavigationLink {
                            HealthMetricHistoryView(metric: metric, samples: healthKitService.recentTrendSamples)
                        } label: {
                            HealthKitMetricSummaryRow(metric: metric)
                        }
                    }
                }
            }

            Section("用药与睡眠") {
                NavigationLink {
                    MedicationSleepReviewView()
                } label: {
                    Label("对照睡眠与实际用药记录", systemImage: "bed.double.fill")
                }
            }

            Section("用于本 App") {
                NavigationLink {
                    MedicationTrendDetailView()
                } label: {
                    HealthKitContributionRow(
                        iconName: "chart.line.uptrend.xyaxis",
                        tint: .blue,
                        title: "用药趋势",
                        subtitle: "作为趋势背景信号",
                        trailingText: summary.hasSamples ? "\(summary.coveredDayCount) 天" : "待授权"
                    )
                }

                NavigationLink {
                    VisitSummaryView()
                } label: {
                    HealthKitContributionRow(
                        iconName: "doc.text.magnifyingglass",
                        tint: .orange,
                        title: "复诊资料",
                        subtitle: "随报告汇总近期观察",
                        trailingText: summary.hasSamples ? "\(summary.sampleCount) 条" : "待样本"
                    )
                }
            }

            Section(healthKitService.hasCompletedAuthorizationRequest ? "管理" : "授权") {
                if healthKitService.hasCompletedAuthorizationRequest {
                    SettingsStatusRow(
                        iconName: "checkmark.seal.fill",
                        tint: .green,
                        title: "已完成授权请求",
                        subtitle: "可在系统隐私设置管理具体指标"
                    )
                    Button {
                        Task {
                            await healthKitService.refreshRecentTrendSamples()
                        }
                    } label: {
                        Text("刷新近期健康数据")
                    }
                } else {
                    Button {
                        startHealthPermissionFlow()
                    } label: {
                        Text("请求读取健康数据授权")
                    }
                }
                if healthKitService.hasCompletedAuthorizationRequest {
                    Button("更新读取授权（含睡眠与活动）") {
                        Task { await healthKitService.requestAuthorizationEntry() }
                    }
                }
                Button {
                    openSystemSettings()
                } label: {
                    Text("打开系统隐私设置")
                }
            }
        }
        .navigationTitle("Apple 健康")
        .toolbar(.hidden, for: .tabBar)
        .appPermissionPrimer(pendingGate: $pendingPermissionGate) { gate in
            guard gate == .health else {
                return
            }
            Task {
                let requestCompleted = await healthKitService.requestAuthorizationEntry()
                if requestCompleted {
                    AppPermissionGate.markAuthorizationCompleted(for: .health)
                }
            }
        }
        .task {
            await healthKitService.refreshRecentTrendSamples()
        }
    }

    private func startHealthPermissionFlow() {
        if healthKitService.hasCompletedAuthorizationRequest {
            AppPermissionGate.markAuthorizationCompleted(for: .health)
            Task {
                await healthKitService.refreshRecentTrendSamples()
            }
            return
        }
        if AppPermissionGate.hasCompletedAuthorization(for: .health) {
            Task {
                let requestCompleted = await healthKitService.requestAuthorizationEntry()
                if requestCompleted {
                    AppPermissionGate.markAuthorizationCompleted(for: .health)
                }
            }
        } else {
            pendingPermissionGate = .health
        }
    }

    private func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else {
            return
        }
        UIApplication.shared.open(url)
    }
}

struct HealthKitSnapshotCard: View {
    let summary: HealthKitRecentSummary
    let supportedTypes: String
    let hasCompletedAuthorizationRequest: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(summary.hasSamples ? summary.latestSampleText : "等待健康数据")
                    .font(.headline)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
                Spacer(minLength: 12)
                Text(summary.coverageText)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(summary.hasSamples ? .teal : .secondary)
            }

            HStack(spacing: 10) {
                HealthKitSnapshotTile(title: "覆盖", value: summary.hasSamples ? "\(summary.coveredDayCount) 天" : "0 天", tint: .teal)
                HealthKitSnapshotTile(title: "样本", value: "\(summary.sampleCount)", tint: .blue)
                HealthKitSnapshotTile(title: "指标", value: "\(summary.metricSummaries.count)", tint: .indigo)
            }

            HStack(spacing: 6) {
                Image(systemName: hasCompletedAuthorizationRequest ? "checkmark.shield.fill" : "shield")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(hasCompletedAuthorizationRequest ? .blue : .secondary)
                Text(supportedTypes)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
            }
        }
        .padding(.vertical, 4)
    }
}

struct HealthKitSnapshotTile: View {
    let title: String
    let value: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(tint)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: 54, alignment: .leading)
        .medicationGlassSurface(cornerRadius: 8, tint: tint, fallbackMaterial: .thinMaterial)
    }
}

struct HealthKitMetricSummaryRow: View {
    let metric: HealthKitMetricSummary

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(healthMetricTint(metric.kind).opacity(0.12))
                Image(systemName: metric.symbolName)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(healthMetricTint(metric.kind))
            }
            .frame(width: 38, height: 38)

            VStack(alignment: .leading, spacing: 3) {
                Text(metric.title)
                    .font(.body.weight(.medium))
                Text("\(metric.coveredDayCount) 天 · \(metric.sampleCount) 条")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 12)

            VStack(alignment: .trailing, spacing: 3) {
                Text(metric.latestValueText)
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                Text(AppFormatters.day.string(from: metric.latestMeasuredAt))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
    }
}


// Reuses the daily bar/line presentation from HealthMetricReviewCard in the
// visit-prep integration, adapted to the current health-signal model.
private struct HealthMetricHistoryView: View {
    let metric: HealthKitMetricSummary
    let samples: [HealthSignalSample]
    @State private var selectedDate: Date?
    @State private var lookbackDays = 7

    private struct DailyPoint: Identifiable {
        var id: Date { date }
        let date: Date
        let value: Double
        let segment: Date
    }

    private var points: [DailyPoint] {
        let calendar = Calendar.current
        let start = calendar.date(byAdding: .day, value: 1 - lookbackDays,
                                  to: calendar.startOfDay(for: Date())) ?? Date()
        let groups = Dictionary(grouping: samples.filter {
            $0.kind == metric.kind && $0.measuredAt >= start
        }, by: { calendar.startOfDay(for: $0.measuredAt) })
        var result: [DailyPoint] = []
        var segment = start
        for date in groups.keys.sorted() {
            let values = (groups[date] ?? []).map(\.value).sorted()
            guard !values.isEmpty else { continue }
            if let previous = result.last,
               calendar.date(byAdding: .day, value: 1, to: previous.date) != date {
                segment = date
            }
            let middle = values.count / 2
            let median = values.count.isMultiple(of: 2)
                ? (values[middle - 1] + values[middle]) / 2 : values[middle]
            result.append(DailyPoint(date: date, value: median, segment: segment))
        }
        return result
    }

    private var usesBars: Bool {
        switch metric.kind {
        case .stepCount, .activeEnergy, .exerciseMinutes, .sleepDuration, .sleepCore, .sleepDeep, .sleepREM: true
        default: false
        }
    }

    var body: some View {
        let daily = points
        List {
            Section {
                Picker("回顾范围", selection: $lookbackDays) {
                    Text("近 7 天").tag(7)
                    Text("近 30 天").tag(30)
                    Text("近 56 天").tag(56)
                }
                .pickerStyle(.segmented)
                HealthKitMetricSummaryRow(metric: metric)
                if daily.isEmpty {
                    Text("这段时间暂无可读取的记录").foregroundStyle(.secondary)
                } else {
                    Chart(daily) { point in
                        if usesBars {
                            BarMark(x: .value("日期", point.date, unit: .day),
                                    y: .value(metric.title, point.value), width: .ratio(0.65))
                                .cornerRadius(3)
                                .foregroundStyle(healthMetricTint(metric.kind))
                        } else {
                            LineMark(x: .value("日期", point.date), y: .value(metric.title, point.value),
                                     series: .value("连续记录", point.segment))
                                .interpolationMethod(.linear)
                                .lineStyle(StrokeStyle(lineWidth: 2, lineJoin: .round))
                                .foregroundStyle(healthMetricTint(metric.kind))
                            PointMark(x: .value("日期", point.date), y: .value(metric.title, point.value))
                                .foregroundStyle(healthMetricTint(metric.kind))
                        }
                    }
                    .chartYScale(domain: .automatic(includesZero: usesBars))
                    .chartXSelection(value: $selectedDate)
                    .chartGesture { proxy in
                        SpatialTapGesture(coordinateSpace: .local).onEnded { event in
                            proxy.selectXValue(at: event.location.x)
                        }
                    }
                    .chartXAxis { AxisMarks(values: .automatic(desiredCount: 4)) }
                    .chartLegend(.hidden)
                    .frame(height: 220)
                    if let selectedDate,
                       let point = daily.first(where: { Calendar.current.isDate($0.date, inSameDayAs: selectedDate) }) {
                        Text("\(point.date.formatted(date: .abbreviated, time: .omitted)) · \(point.value.formatted(.number.precision(.fractionLength(0...1)))) \(metric.unit)")
                            .monospacedDigit()
                    }
                }
            }
            Section {
                Text(usesBars ? "按日汇总已记录的数据。睡眠归到结束日，重叠时段去重；缺失日期不补值。"
                              : "曲线显示每日记录中位数，缺失日期不连线。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .navigationTitle(metric.title)
    }
}

struct HealthKitContributionRow: View {
    let iconName: String
    let tint: Color
    let title: String
    let subtitle: String
    let trailingText: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: iconName)
                .font(.headline)
                .foregroundStyle(tint)
                .frame(width: 30, height: 30)
                .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.body.weight(.medium))
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 12)

            Text(trailingText)
                .font(.caption.weight(.semibold))
                .foregroundStyle(tint)
        }
        .padding(.vertical, 4)
    }
}

private func healthMetricTint(_ kind: HealthSignalKind) -> Color {
    switch kind {
    case .heartRate, .restingHeartRate:
        .red
    case .stepCount, .exerciseMinutes: .green
    case .activeEnergy: .orange
    case .sleepDuration, .sleepCore, .sleepDeep, .sleepREM: .indigo
    case .bloodPressureSystolic, .bloodPressureDiastolic:
        .indigo
    case .bloodOxygen:
        .teal
    case .bodyTemperature:
        .orange
    case .bloodGlucose:
        .purple
    case .unknown:
        .gray
    }
}

struct MedicalAIPrivacyView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \StoredAIConsent.grantedAt, order: .reverse) private var consents: [StoredAIConsent]
    @State private var revocationErrorMessage: String?

    private var activeConsent: StoredAIConsent? {
        consents.first { $0.id == "medical-ai-consent" && $0.isActive }
    }

    var body: some View {
        List {
            Section {
                SettingsStatusRow(
                    iconName: "lock.shield.fill",
                    tint: .green,
                    title: "医疗智能体",
                    subtitle: activeConsent == nil ? "设备端默认本机处理；云端需主动授权" : "已授权智能体读取所选用药数据"
                )
            }

            Section("共享范围") {
                if let activeConsent {
                    ConsentScopeRow(title: "药品名称、规格和来源", isEnabled: activeConsent.sharesMedicationProfile)
                    ConsentScopeRow(title: "提醒计划", isEnabled: activeConsent.sharesMedicationPlans)
                    ConsentScopeRow(title: "服药记录", isEnabled: activeConsent.sharesDoseEvents)
                    ConsentScopeRow(title: "风险提醒", isEnabled: activeConsent.sharesRiskCards)
                    ConsentScopeRow(title: "说明书摘要", isEnabled: activeConsent.sharesDrugLabels)
                    ConsentScopeRow(title: "导入识别内容", isEnabled: activeConsent.sharesImportDraft)
                } else {
                    Text("设备端模型会在本机整理授权数据；云端智能体仅在你确认授权并主动发送咨询后才会连接外部服务。")
                        .foregroundStyle(.secondary)
                }
            }

            if activeConsent != nil {
                Section {
                    Button(role: .destructive) {
                        revokeAIConsent()
                    } label: {
                        Text("停止共享用药数据")
                    }
                }
            }
        }
        .navigationTitle("医疗智能体")
        .toolbar(.hidden, for: .tabBar)
        .alert("撤销失败", isPresented: .constant(revocationErrorMessage != nil)) {
            Button("好") {
                revocationErrorMessage = nil
            }
        } message: {
            if let errorMessage = revocationErrorMessage {
                Text(errorMessage)
            }
        }
    }

    private func revokeAIConsent() {
        let command = AIConsentRevocationCommand(modelContext: modelContext)
        let outcome = command.execute()

        switch outcome {
        case .revoked:
            break
        case .alreadyRevoked:
            break
        case .saveFailed:
            revocationErrorMessage = "撤销未能保存，授权仍然有效。请重试。"
        case .consentNotFound:
            revocationErrorMessage = "未找到有效授权。"
        }
    }
}

struct ConsentScopeRow: View {
    let title: String
    let isEnabled: Bool

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            Text(isEnabled ? "已共享" : "未共享")
                .font(.caption.weight(.semibold))
                .foregroundStyle(isEnabled ? .green : .secondary)
        }
    }
}

struct AccountHeaderRow: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    private var isAccessibilitySize: Bool { dynamicTypeSize.isAccessibilitySize }

    var body: some View {
        (isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 14)) : AnyLayout(HStackLayout(spacing: 14))) {
            Image(systemName: "iphone")
                .font(.system(size: 28))
                .foregroundStyle(.blue)
                .frame(width: 48, height: 48)
            VStack(alignment: .leading, spacing: 4) {
                Text("本机数据")
                    .font(.headline)
                Text("提醒、记录和药品资料保存在这台 iPhone")
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("profile.local-data.summary")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            if !isAccessibilitySize { Spacer() }
        }
        .padding(.vertical, 8)
    }
}

struct SettingsStatusRow: View {
    let iconName: String
    let tint: Color
    let title: String
    let subtitle: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: iconName)
                .font(.headline)
                .foregroundStyle(tint)
                .frame(width: 30, height: 30)
                .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.body.weight(.medium))
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

struct SettingsToggleRow: View {
    let title: String
    @Binding var isOn: Bool

    var body: some View {
        Button {
            withAnimation(.snappy(duration: 0.18, extraBounce: 0)) {
                isOn.toggle()
            }
        } label: {
            HStack(spacing: 12) {
                Text(title)
                    .foregroundStyle(.primary)
                Spacer(minLength: 12)
                SettingsSwitchVisual(isOn: isOn)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityValue(isOn ? "已开启" : "已关闭")
    }
}

struct SettingsSwitchVisual: View {
    let isOn: Bool

    var body: some View {
        Capsule(style: .continuous)
            .fill(isOn ? Color.green : Color.secondary.opacity(0.26))
            .frame(width: 51, height: 31)
            .overlay(alignment: isOn ? .trailing : .leading) {
                Circle()
                    .fill(Color.white)
                    .frame(width: 27, height: 27)
                    .shadow(color: Color.black.opacity(0.12), radius: 2, x: 0, y: 1)
                    .padding(2)
            }
            .animation(.snappy(duration: 0.18, extraBounce: 0), value: isOn)
            .accessibilityHidden(true)
    }
}


private struct MedicationSleepReviewView: View {
    @Query private var tasks: [StoredDoseTask]
    @Query private var medications: [StoredMedication]
    @StateObject private var service = HealthKitService()
    @State private var dayCount = 14
    @State private var selectedDate: Date?
    @Environment(\.openMedicationAIQuestion) private var openQuestion

    var body: some View {
        let review = MedicationSleepReview(samples: service.recentTrendSamples,
            tasks: tasks, medications: medications, dayCount: dayCount)
        let selected = review.days.first { Calendar.current.isDate($0.date, inSameDayAs: selectedDate ?? Date()) }
        List {
            Section {
                Picker("观察范围", selection: $dayCount) {
                    Text("近 14 天").tag(14)
                    Text("近 30 天").tag(30)
                }.pickerStyle(.segmented)
                Text(review.sleepSummary).font(.subheadline)
                Text("点击图表日期，对照同一观察窗口的记录。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("睡眠时长 · 小时") {
                if review.days.compactMap(\.sleepHours).isEmpty {
                    Text("暂无可读取的睡眠记录，请在 Apple 健康页更新读取授权。")
                        .foregroundStyle(.secondary)
                } else {
                    Chart(review.days) { day in
                        if let hours = day.sleepHours {
                            BarMark(x: .value("日期", day.date, unit: .day), y: .value("小时", hours))
                                .foregroundStyle(.indigo.gradient).cornerRadius(3)
                        }
                        if let selectedDate {
                            RuleMark(x: .value("所选日期", selectedDate)).foregroundStyle(.secondary.opacity(0.4))
                        }
                    }
                    .chartXScale(domain: (review.days.first?.date ?? Date())...Date())
                    .chartXSelection(value: $selectedDate)
                    .chartGesture { proxy in
                        SpatialTapGesture().onEnded { proxy.selectXValue(at: $0.location.x) }
                    }
                    .chartXAxis { AxisMarks(values: .automatic(desiredCount: 4)) }
                    .frame(height: 200)
                }
            }
            Section("同窗口实际服用记录 · 次") {
                Chart(review.days) { day in
                    BarMark(x: .value("日期", day.date, unit: .day), y: .value("已记录次数", day.actualDoseCount))
                        .foregroundStyle(.teal.gradient).cornerRadius(3)
                    if let selectedDate {
                        RuleMark(x: .value("所选日期", selectedDate)).foregroundStyle(.secondary.opacity(0.4))
                    }
                }
                .chartXScale(domain: (review.days.first?.date ?? Date())...Date())
                .chartXSelection(value: $selectedDate)
                .chartGesture { proxy in
                    SpatialTapGesture().onEnded { proxy.selectXValue(at: $0.location.x) }
                }
                .chartXAxis { AxisMarks(values: .automatic(desiredCount: 4)) }
                .frame(height: 120)
                Text("仅统计有实际时间的已服用记录，时间未知的记录见下方明细。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section(selected.map { $0.date.formatted(date: .abbreviated, time: .omitted) } ?? "所选日期") {
                if let selected {
                    Text(selected.sleepHours.map { "睡眠 \($0.formatted(.number.precision(.fractionLength(1)))) 小时" } ?? "缺少睡眠记录")
                        .font(.headline)
                    Text("前日中午至当日中午的用药记录")
                        .font(.caption).foregroundStyle(.secondary)
                    if selected.medicationRecords.isEmpty { Text("暂无同期用药记录").foregroundStyle(.secondary) }
                    ForEach(Array(selected.medicationRecords.enumerated()), id: \.offset) { _, record in
                        Text(record).font(.body)
                    }
                }
            }
            Section {
                Button("询问智能体，分析这 \(dayCount) 天的变化") {
                    openQuestion("请分析最近\(dayCount)天睡眠与实际用药记录的同期变化，引用日期和数值，并结合已提供的药品说明书给出值得继续观察的问题。")
                }
                Text("选择云端模式并开启健康摘要共享后，可结合当前数据分析。")
                    .font(.caption).foregroundStyle(.secondary)
                Text("睡眠按结束日归属。计划和未确认记录不能视为已服药；同期变化不代表药物导致变化。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("用药与睡眠")
        .task(id: dayCount) { await service.refreshRecentTrendSamples(days: dayCount, useRecentCache: true) }
    }
}
