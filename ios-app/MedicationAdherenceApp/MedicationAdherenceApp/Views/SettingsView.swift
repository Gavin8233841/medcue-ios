import AuthenticationServices
import MedicationAdherenceCore
import QuickLook
import SwiftData
import SwiftUI
import UIKit

struct ProfileView: View {
    @Environment(\.activeAppTab) private var activeAppTab
    @Environment(\.isBackgroundTabPrewarm) private var isBackgroundTabPrewarm
    @Query(sort: \StoredAIConsent.grantedAt, order: .reverse) private var consents: [StoredAIConsent]
    @Query(sort: \StoredMedication.displayName) private var medications: [StoredMedication]
    @Query(sort: \StoredDoseTask.dueAt, order: .reverse) private var tasks: [StoredDoseTask]
    @Query(sort: \StoredMedicationDoseChange.effectiveFrom, order: .reverse) private var doseChanges: [StoredMedicationDoseChange]
    @Query(sort: \StoredMedicationPlan.createdAt) private var plans: [StoredMedicationPlan]
    @Query(sort: \StoredMedicationLifecycleEvent.occurredAt, order: .reverse) private var lifecycleEvents: [StoredMedicationLifecycleEvent]
    @StateObject private var healthKitService = HealthKitService()
    @State private var profileSnapshot = ProfileSnapshot.empty
    @State private var deferredTrendDashboard: MedicationTrendDashboard?
    @State private var lastProfileRefreshToken = ""
    @State private var lastProfileRefreshAt = Date(timeIntervalSinceReferenceDate: 0)
    @State private var lastHealthRefreshAt = Date(timeIntervalSinceReferenceDate: 0)

    init() {
        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: Date())
        let queryStart = calendar.date(byAdding: .day, value: -90, to: todayStart) ?? todayStart.addingTimeInterval(-7_776_000)
        let queryEnd = calendar.date(byAdding: .day, value: 8, to: todayStart) ?? todayStart.addingTimeInterval(691_200)
        _tasks = Query(
            filter: #Predicate<StoredDoseTask> { task in
                task.dueAt >= queryStart && task.dueAt < queryEnd
            },
            sort: \StoredDoseTask.dueAt,
            order: .reverse
        )
    }

    private var activeConsent: StoredAIConsent? {
        consents.first { $0.id == "medical-ai-consent" && $0.isActive }
    }

    private var isActiveTab: Bool {
        activeAppTab == nil || activeAppTab == .profile
    }

    private var refreshToken: String {
        ProfileSnapshot.refreshID(
            medications: medications,
            tasks: tasks,
            doseChanges: doseChanges,
            plans: plans,
            lifecycleEvents: lifecycleEvents,
            healthSignals: healthKitService.recentTrendSamples
        )
    }

    private var refreshTaskID: String {
        "\(isActiveTab ? "active" : "inactive")|\(refreshToken)"
    }

    private var shouldPrepareSnapshot: Bool {
        isActiveTab || profileSnapshot.isPlaceholder
    }

    var body: some View {
        List {
            Section {
                NavigationLink {
                    AccountBackupView()
                } label: {
                    AccountHeaderRow()
                }
                .background(alignment: .top) {
                    AppTopGradientScrollReader(tab: .profile, coordinateSpaceName: "ProfileTopGradientList")
                }
            }

            Section("复诊") {
                NavigationLink {
                    VisitSummaryView()
                } label: {
                    ProfileActionRow(
                        iconName: "doc.text.fill",
                        tint: .orange,
                        title: "复诊资料",
                        subtitle: "整理近期记录、风险和健康信号",
                        trailingText: nil
                    )
                }
            }

            Section("健康与智能体") {
                NavigationLink {
                    HealthDataSettingsView()
                } label: {
                    ProfileActionRow(
                        iconName: "heart.text.square.fill",
                        tint: .red,
                        title: "Apple 健康",
                        subtitle: healthKitService.hasCompletedAuthorizationRequest ? healthKitService.recentSummary.coverageText : "连接生命体征到趋势与复诊资料",
                        trailingText: healthKitService.recentSummary.hasSamples ? "\(healthKitService.recentSummary.coveredDayCount) 天" : nil
                    )
                }

                NavigationLink {
                    MedicalAIPrivacyView()
                } label: {
                    ProfileActionRow(
                        iconName: "stethoscope",
                        tint: .green,
                        title: "医疗智能体",
                        subtitle: activeConsent == nil ? "尚未共享用药数据" : "已授权读取所选用药数据",
                        trailingText: activeConsent == nil ? nil : "已授权"
                    )
                }
            }

            Section("偏好") {
                NavigationLink {
                    SettingsView()
                } label: {
                    ProfileActionRow(
                        iconName: "gearshape.fill",
                        tint: .gray,
                        title: "应用设置",
                        subtitle: "外观、提醒、触控和系统设置",
                        trailingText: nil
                    )
                }
            }

            Section("隐私") {
                Text("记录默认保存在本机；只有在你主动授权、生成或分享时，才会使用对应数据。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .coordinateSpace(name: "ProfileTopGradientList")
        .navigationTitle("个人")
        .onAppear {
            restoreProfileSnapshotFromCacheIfAvailable()
        }
        .task(id: refreshTaskID) {
            guard shouldPrepareSnapshot else {
                return
            }
            let delay: Duration = isActiveTab
                ? .milliseconds(profileSnapshot.isPlaceholder ? 40 : 120)
                : .milliseconds(220)
            await refreshProfileSnapshot(token: refreshToken, after: delay)
            if isActiveTab && !isBackgroundTabPrewarm {
                await refreshHealthSamplesIfNeeded(after: .milliseconds(260))
            }
        }
    }

    @MainActor
    private func refreshHealthSamplesIfNeeded(after delay: Duration = .zero) async {
        guard Date().timeIntervalSince(lastHealthRefreshAt) > 300 else {
            return
        }
        if delay != .zero {
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else {
                return
            }
        }
        await healthKitService.refreshRecentTrendSamples()
        lastHealthRefreshAt = Date()
    }

    @MainActor
    private func refreshProfileSnapshot(token: String, after delay: Duration) async {
        if restoreProfileSnapshotFromCacheIfAvailable(for: token),
           !profileSnapshot.isPlaceholder,
           isActiveTab,
           !isBackgroundTabPrewarm {
            return
        }
        if lastProfileRefreshToken == token,
           !profileSnapshot.isPlaceholder,
           Date().timeIntervalSince(lastProfileRefreshAt) < 15 {
            return
        }
        let medications = medications
        let tasks = tasks
        let doseChanges = doseChanges
        let plans = plans
        let lifecycleEvents = lifecycleEvents
        let healthSignals = healthKitService.recentTrendSamples
        try? await Task.sleep(for: delay)
        guard !Task.isCancelled else {
            return
        }
        let snapshot = ProfileSnapshot(
            tasks: tasks,
            now: Date()
        )
        profileSnapshot = snapshot
        lastProfileRefreshToken = token
        lastProfileRefreshAt = Date()
        ProfileSnapshotCache.store(snapshot: snapshot, token: token)

        try? await Task.sleep(for: .milliseconds(120))
        guard !Task.isCancelled else {
            return
        }
        let trendDashboard = medicationTrendDashboard(
            tasks: snapshot.measurableTasks,
            doseChanges: doseChanges,
            medications: medications,
            plans: plans,
            lifecycleEvents: lifecycleEvents,
            healthSignals: healthSignals
        )
        deferredTrendDashboard = trendDashboard
        ProfileSnapshotCache.store(trendDashboard: trendDashboard, token: token)
    }

    @MainActor
    @discardableResult
    private func restoreProfileSnapshotFromCacheIfAvailable(for token: String? = nil) -> Bool {
        let lookupToken = token ?? refreshToken
        guard let cachedEntry = ProfileSnapshotCache.entry(for: lookupToken) else {
            return false
        }
        profileSnapshot = cachedEntry.snapshot
        deferredTrendDashboard = cachedEntry.trendDashboard
        lastProfileRefreshToken = lookupToken
        lastProfileRefreshAt = Date()
        return true
    }
}

@MainActor
private enum ProfileSnapshotCache {
    struct Entry {
        let snapshot: ProfileSnapshot
        let trendDashboard: MedicationTrendDashboard?
    }

    private static var token = ""
    private static var storedAt = Date(timeIntervalSinceReferenceDate: 0)
    private static var entry = Entry(snapshot: .empty, trendDashboard: nil)
    private static let timeToLive: TimeInterval = 300

    static func store(snapshot: ProfileSnapshot, token: String) {
        self.token = token
        self.entry = Entry(snapshot: snapshot, trendDashboard: entry.trendDashboard)
        storedAt = Date()
    }

    static func store(trendDashboard: MedicationTrendDashboard?, token: String) {
        guard self.token == token else {
            return
        }
        self.entry = Entry(snapshot: entry.snapshot, trendDashboard: trendDashboard)
        storedAt = Date()
    }

    static func entry(for token: String) -> Entry? {
        guard self.token == token,
              !entry.snapshot.isPlaceholder,
              Date().timeIntervalSince(storedAt) <= timeToLive
        else {
            return nil
        }
        return entry
    }
}

private struct ProfileSnapshot {
    static let empty = ProfileSnapshot(tasks: [], now: Date(timeIntervalSinceReferenceDate: 0))

    let measurableTasks: [StoredDoseTask]
    let insight: AdherenceInsight
    let streakDisplay: AdherenceStreakDisplay
    let completionRate: Double
    let recordedDayCount: Int
    let isPlaceholder: Bool

    init(tasks: [StoredDoseTask], now: Date, calendar: Calendar = .current) {
        self.measurableTasks = tasks.adherenceMeasurableTasks
        self.insight = AdherenceInsightBuilder().build(
            scheduledDoses: measurableTasks.map(\.coreScheduledDose),
            events: measurableTasks.compactMap(\.coreDoseEventUsingEffectiveAdherenceDate),
            timeZone: TimeZone.current,
            now: now
        )
        self.streakDisplay = AdherenceStreakDisplay(insight: insight)
        self.completionRate = insight.completionRate
        self.recordedDayCount = Set(measurableTasks.map { calendar.startOfDay(for: $0.effectiveAdherenceDate) }).count
        self.isPlaceholder = tasks.isEmpty
    }

    static func refreshID(
        medications: [StoredMedication],
        tasks: [StoredDoseTask],
        doseChanges: [StoredMedicationDoseChange],
        plans: [StoredMedicationPlan],
        lifecycleEvents: [StoredMedicationLifecycleEvent],
        healthSignals: [HealthSignalSample]
    ) -> String {
        var parts: [String] = []
        parts.reserveCapacity(6)
        parts.append(String(stableMedicationSignature(medications)))
        parts.append(String(stableTaskSignature(tasks)))
        parts.append(String(stableDoseChangeSignature(doseChanges)))
        parts.append(String(stablePlanSignature(plans)))
        parts.append(String(stableLifecycleEventSignature(lifecycleEvents)))
        parts.append(String(stableHealthSignalSignature(healthSignals)))
        return parts.joined(separator: "|")
    }
}

private struct ProfileActionRow: View {
    let iconName: String
    let tint: Color
    let title: String
    let subtitle: String
    let trailingText: String?

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: iconName)
                .font(.headline)
                .foregroundStyle(tint)
                .frame(width: 34, height: 34)
                .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.body.weight(.medium))
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 8)
            if let trailingText {
                Text(trailingText)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(tint)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(tint.opacity(0.10), in: Capsule())
            }
        }
        .padding(.vertical, 5)
    }
}

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @AppStorage("appColorSchemePreference") private var appColorSchemePreference = AppColorSchemePreference.system.rawValue
    @AppStorage("prefersReducedAppMotion") private var prefersReducedAppMotion = false
    @AppStorage("showsMedicationPhotosInReminders") private var showsMedicationPhotosInReminders = true
    @AppStorage("usesLargeTouchTargets") private var usesLargeTouchTargets = true
    @AppStorage(NotificationService.reminderNotificationUnavailableMessageKey) private var reminderNotificationUnavailableMessage = ""
    @StateObject private var notificationService = NotificationService()
    @State private var pendingPermissionGate: AppPermissionGate?
    @State private var isUpdatingNotificationPermission = false

    var body: some View {
        List {
            Section("外观与交互") {
                Picker("显示模式", selection: $appColorSchemePreference) {
                    ForEach(AppColorSchemePreference.allCases) { preference in
                        Text(preference.displayName).tag(preference.rawValue)
                    }
                }
                .pickerStyle(.segmented)

                SettingsToggleRow(title: "减少动态效果", isOn: $prefersReducedAppMotion)
                HStack {
                    Text("语言")
                    Spacer()
                    Text("中文")
                        .foregroundStyle(.secondary)
                }
                SettingsToggleRow(title: "提醒时突出药品图片", isOn: $showsMedicationPhotosInReminders)
                SettingsToggleRow(title: "使用更大的触控区域", isOn: $usesLargeTouchTargets)
            }

            Section("用药提醒") {
                SettingsStatusRow(
                    iconName: "bell.badge.fill",
                    tint: .blue,
                    title: "提醒通知",
                    subtitle: notificationStatusText
                )
                Button {
                    startNotificationPermissionFlow()
                } label: {
                    Text(isUpdatingNotificationPermission ? "正在检查通知权限" : "开启或更新通知权限")
                }
                .disabled(isUpdatingNotificationPermission)
                Button {
                    openSystemSettings()
                } label: {
                    Text("打开系统通知设置")
                }
            }

            Section("隐私") {
                SettingsStatusRow(
                    iconName: "lock.shield.fill",
                    tint: .green,
                    title: "本机优先",
                    subtitle: "用药数据默认保存在本机"
                )
            }
        }
        .navigationTitle("应用设置")
        .appPermissionPrimer(pendingGate: $pendingPermissionGate) { gate in
            guard gate == .notifications else {
                return
            }
            Task {
                await requestNotificationPermissionAndRefresh()
            }
        }
        .task {
            await notificationService.refreshAuthorizationStatus()
            await notificationService.refreshPendingReminderCount()
        }
    }

    private var notificationStatusText: String {
        let baseText: String
        if notificationService.pendingReminderCount > 0 {
            baseText = "\(notificationService.authorizationMessage) · 已安排 \(notificationService.pendingReminderCount) 个提醒"
        } else {
            baseText = notificationService.authorizationMessage
        }

        guard let detailText = notificationUnavailableDetailText else {
            return baseText
        }
        return "\(baseText) · 普通提醒需检查：\(detailText)"
    }

    private var notificationUnavailableDetailText: String? {
        let trimmedMessage = reminderNotificationUnavailableMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedMessage.isEmpty else {
            return nil
        }
        return trimmedMessage.replacingOccurrences(of: "普通提醒不可用：", with: "")
    }

    private func startNotificationPermissionFlow() {
        Task {
            guard !isUpdatingNotificationPermission else {
                return
            }
            isUpdatingNotificationPermission = true
            defer {
                isUpdatingNotificationPermission = false
            }
            if await notificationService.hasUsableNotificationAuthorization() {
                AppPermissionGate.markAuthorizationCompleted(for: .notifications)
                await notificationService.refreshPendingReminderCount()
                return
            }
            if AppPermissionGate.hasCompletedAuthorization(for: .notifications) {
                await requestNotificationPermissionAndRefresh()
            } else {
                pendingPermissionGate = .notifications
            }
        }
    }

    private func requestNotificationPermissionAndRefresh() async {
        let granted = await notificationService.requestAuthorization()
        guard granted else {
            return
        }
        AppPermissionGate.markAuthorizationCompleted(for: .notifications)
        await notificationService.refreshPendingReminderCount()
    }

    private func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else {
            return
        }
        UIApplication.shared.open(url)
    }
}

private struct HealthDataSettingsView: View {
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
                        subtitle: healthKitService.hasCompletedAuthorizationRequest ? "授权范围内还没有可读取的生命体征" : "完成授权请求后显示最近 56 天的生命体征"
                    )
                } else {
                    ForEach(summary.metricSummaries) { metric in
                        HealthKitMetricSummaryRow(metric: metric)
                    }
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

private struct HealthKitSnapshotCard: View {
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

private struct HealthKitSnapshotTile: View {
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

private struct HealthKitMetricSummaryRow: View {
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

private struct HealthKitContributionRow: View {
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
    case .heartRate:
        .red
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

private struct MedicalAIPrivacyView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \StoredAIConsent.grantedAt, order: .reverse) private var consents: [StoredAIConsent]

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
                    Text("设备端模型会在本机整理授权数据；云端智能体只有在你主动选择并确认授权后才会连接外部服务。")
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
    }

    private func revokeAIConsent() {
        activeConsent?.revokedAt = Date()
        try? modelContext.save()
    }
}

private struct ConsentScopeRow: View {
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

private struct AccountHeaderRow: View {
    @AppStorage("wantsICloudBackup") private var wantsICloudBackup = false

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: wantsICloudBackup ? "externaldrive.badge.checkmark" : "externaldrive.fill")
                .font(.largeTitle)
                .foregroundStyle(.blue)
                .frame(width: 48, height: 48)
            VStack(alignment: .leading, spacing: 4) {
                Text("本机数据")
                    .font(.headline)
                Text(statusText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 8)
    }

    private var statusText: String {
        if wantsICloudBackup {
            return "已记录备份偏好，数据仍由你主动管理"
        }
        return "提醒、记录和药品资料保存在这台 iPhone"
    }
}

private struct SettingsStatusRow: View {
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

private struct SettingsToggleRow: View {
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

private struct SettingsSwitchVisual: View {
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

private struct AccountBackupView: View {
    @AppStorage("appleAccountLocalUserID") private var appleAccountLocalUserID = ""
    @AppStorage("wantsICloudBackup") private var wantsICloudBackup = false
    @State private var statusMessage = ""

    private var hasAppleAccountMark: Bool {
        !appleAccountLocalUserID.isEmpty
    }

    private var hasICloudAccount: Bool {
        FileManager.default.ubiquityIdentityToken != nil
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    Label("账号与备份", systemImage: "person.crop.circle")
                        .font(.headline)
                    Text("用药数据默认保存在本机。")
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 6)
            }

            Section("Apple 账号") {
                if hasAppleAccountMark {
                    SettingsStatusRow(
                        iconName: "checkmark.circle.fill",
                        tint: .green,
                        title: "已连接 Apple 账号",
                        subtitle: "账号标识仅保存在本机"
                    )
                    Button(role: .destructive) {
                        appleAccountLocalUserID = ""
                        statusMessage = "已断开本机 Apple 账号连接。"
                    } label: {
                        Text("断开 Apple 账号")
                    }
                } else {
                    SignInWithAppleButton(.continue) { request in
                        request.requestedScopes = []
                    } onCompletion: { result in
                        handleSignIn(result)
                    }
                    .signInWithAppleButtonStyle(.black)
                    .frame(height: 48)
                }

            }

            Section("备份") {
                SettingsStatusRow(
                    iconName: hasICloudAccount ? "icloud.fill" : "icloud.slash",
                    tint: hasICloudAccount ? .blue : .gray,
                    title: hasICloudAccount ? "已检测到 iCloud" : "未检测到 iCloud",
                    subtitle: hasICloudAccount ? "可用于 iCloud 备份准备" : "请先在系统设置中登录 iCloud"
                )
                SettingsToggleRow(title: "自动备份到 iCloud", isOn: $wantsICloudBackup)
            }

            Section("系统设置") {
                Button {
                    openSystemSettings()
                } label: {
                    Text("打开 App 系统设置")
                }
            }

            if !statusMessage.isEmpty {
                Section {
                    Text(statusMessage)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("账号")
        .toolbar(.hidden, for: .tabBar)
    }

    private func handleSignIn(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case let .success(authorization):
            if let credential = authorization.credential as? ASAuthorizationAppleIDCredential {
                appleAccountLocalUserID = credential.user
                statusMessage = "Apple 账号已连接。"
            } else {
                statusMessage = "未能读取 Apple 账号状态。"
            }
        case .failure:
            statusMessage = "Apple 账号连接未完成，请稍后重试或前往系统设置检查。"
        }
    }

    private func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else {
            return
        }
        UIApplication.shared.open(url)
    }
}

private struct VisitSummaryView: View {
    @Query(sort: \StoredMedication.displayName) private var medications: [StoredMedication]
    @Query(sort: \StoredDoseTask.dueAt, order: .reverse) private var tasks: [StoredDoseTask]
    @Query(sort: \StoredMedicationDoseChange.effectiveFrom, order: .reverse) private var doseChanges: [StoredMedicationDoseChange]
    @Query(sort: \StoredMedicationPlan.createdAt) private var plans: [StoredMedicationPlan]
    @Query(sort: \StoredMedicationLifecycleEvent.occurredAt, order: .reverse) private var lifecycleEvents: [StoredMedicationLifecycleEvent]
    @Query(sort: \StoredRiskCard.displayPriority) private var riskCards: [StoredRiskCard]
    @StateObject private var healthKitService = HealthKitService()
    @State private var rangeStartDate = Calendar.current.date(byAdding: .day, value: -60, to: Date()) ?? Date()
    @State private var rangeEndDate = Date()
    @State private var pdfURL: URL?
    @State private var generatedPDFSignature = ""
    @State private var previewPDFItem: PDFPreviewItem?
    @State private var exportMessage = ""
    @State private var isSummaryPreviewExpanded = false

    private var measurableTasks: [StoredDoseTask] {
        tasks.adherenceMeasurableTasks
    }

    private var reportTasks: [StoredDoseTask] {
        VisitSummaryTaskFilter.historicalTasks(
            from: measurableTasks,
            startDate: normalizedRange.start,
            endDate: normalizedRange.end
        )
    }

    private var reportDoseChanges: [StoredMedicationDoseChange] {
        doseChanges.filter {
            $0.effectiveFrom >= normalizedRange.start && $0.effectiveFrom <= normalizedRange.end
        }
    }

    private var reportHealthSignals: [HealthSignalSample] {
        healthKitService.recentTrendSamples.filter {
            $0.measuredAt >= normalizedRange.start && $0.measuredAt <= normalizedRange.end
        }
    }

    private var reportHealthSummary: HealthKitRecentSummary {
        HealthKitRecentSummary(samples: reportHealthSignals, refreshedAt: healthKitService.lastSampleRefreshAt)
    }

    private var rangeRiskCards: [StoredRiskCard] {
        riskCards.filter { card in
            card.lastDetectedAt >= normalizedRange.start && card.lastDetectedAt <= normalizedRange.end
        }
    }

    private var reportMedicationIDs: Set<UUID> {
        Set(reportTasks.map(\.medicationID))
            .union(reportDoseChanges.map(\.medicationID))
            .union(rangeRiskCards.filter(\.isActive).map(\.medicationID))
    }

    private var reportMedications: [StoredMedication] {
        medications.filter { reportMedicationIDs.contains($0.id) }
    }

    private var reportRiskCards: [StoredRiskCard] {
        rangeRiskCards.filter { reportMedicationIDs.contains($0.medicationID) && $0.isActive }
    }

    private var trendDashboard: MedicationTrendDashboard {
        medicationTrendDashboard(
            tasks: reportTasks,
            doseChanges: reportDoseChanges,
            medications: medications,
            plans: plans,
            lifecycleEvents: lifecycleEvents,
            healthSignals: reportHealthSignals
        )
    }

    private var normalizedRange: (start: Date, end: Date) {
        VisitSummaryDateRange.normalized(startDate: rangeStartDate, endDate: rangeEndDate)
    }

    private var rangeText: String {
        VisitSummaryDateRange.displayText(startDate: normalizedRange.start, endDate: normalizedRange.end)
    }

    private var completedCount: Int {
        reportTasks.filter { $0.status == .taken || $0.status == .corrected }.count
    }

    private var skippedCount: Int {
        reportTasks.filter { $0.status == .skipped }.count
    }

    private var delayedCount: Int {
        reportTasks.filter { $0.status == .delayed }.count
    }

    private var activeProfessionalRiskCards: [StoredRiskCard] {
        reportRiskCards.filter { $0.requiresProfessionalReview && $0.isActive }
    }

    private var completionRate: Double {
        reportTasks.isEmpty ? 0 : Double(completedCount) / Double(reportTasks.count)
    }

    private var summaryText: String {
        VisitSummaryTextBuilder().build(
            medications: reportMedications,
            tasks: reportTasks,
            riskCards: reportRiskCards,
            startDate: normalizedRange.start,
            endDate: normalizedRange.end,
            generatedAt: Date()
        )
    }

    private var exportSignature: String {
        [
            "\(normalizedRange.start.timeIntervalSinceReferenceDate.rounded())",
            "\(normalizedRange.end.timeIntervalSinceReferenceDate.rounded())",
            "\(stableMedicationSignature(reportMedications))",
            "\(stableTaskSignature(reportTasks))",
            "\(stableDoseChangeSignature(reportDoseChanges))",
            "\(stableRiskCardSignature(reportRiskCards))",
            "\(stableHealthSignalSignature(reportHealthSignals))",
            "\(stablePlanSignature(plans))",
            "\(stableLifecycleEventSignature(lifecycleEvents))",
            "\(Int((trendDashboard.overallScore * 1_000).rounded()))",
            "\(trendDashboard.direction.rawValue)"
        ].joined(separator: "|")
    }

    private var currentPDFURL: URL? {
        generatedPDFSignature == exportSignature ? pdfURL : nil
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    Label("复诊沟通摘要", systemImage: "doc.text")
                        .font(.headline)
                }
                .padding(.vertical, 6)
            }

            Section("导出") {
                VisitSummaryExportPanel(
                    pdfURL: currentPDFURL,
                    exportMessage: exportMessage,
                    rangeText: rangeText,
                    medicationCount: reportMedicationIDs.count,
                    completionRate: completionRate,
                    communicationCount: skippedCount + delayedCount + activeProfessionalRiskCards.count,
                    onGeneratePDF: generatePDF,
                    onPreviewPDF: { url in
                        previewPDFItem = PDFPreviewItem(url: url)
                    }
                )
            }

            Section("日期范围") {
                DatePicker("开始日期", selection: $rangeStartDate, in: ...Date(), displayedComponents: .date)
                DatePicker("结束日期", selection: $rangeEndDate, in: ...Date(), displayedComponents: .date)
                Text("当前范围：\(rangeText)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .onChange(of: rangeStartDate) { _, newValue in
                if newValue > rangeEndDate {
                    rangeEndDate = newValue
                }
                resetGeneratedPDFState()
            }
            .onChange(of: rangeEndDate) { _, newValue in
                if newValue < rangeStartDate {
                    rangeStartDate = newValue
                }
                resetGeneratedPDFState()
            }

            Section("关键指标") {
                VisitSummaryMetricGrid(
                    medicationCount: reportMedicationIDs.count,
                    completionRate: completionRate,
                    takenCount: completedCount,
                    communicationCount: skippedCount + delayedCount + activeProfessionalRiskCards.count
                )
            }

            Section("健康信号") {
                VisitSummaryHealthSignalCard(
                    summary: reportHealthSummary,
                    hasCompletedAuthorizationRequest: healthKitService.hasCompletedAuthorizationRequest,
                    statusMessage: healthKitService.statusMessage
                )
                NavigationLink {
                    HealthDataSettingsView()
                } label: {
                    Label("查看 Apple 健康接入", systemImage: "heart.text.square")
                }
            }

            Section {
                DisclosureGroup(isExpanded: $isSummaryPreviewExpanded) {
                    Text(summaryText)
                        .font(.body.monospaced())
                        .textSelection(.enabled)
                        .padding(.top, 8)
                } label: {
                    Label("摘要预览", systemImage: "text.alignleft")
                        .font(.headline)
                }
            }
        }
        .navigationTitle("复诊资料")
        .toolbar(.hidden, for: .tabBar)
        .safeAreaInset(edge: .bottom) {
            Color.clear.frame(height: 28)
        }
        .task {
            await healthKitService.refreshRecentTrendSamples()
        }
        .sheet(item: $previewPDFItem) { item in
            PDFPreviewSheet(url: item.url)
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                ShareLink(item: summaryText) {
                    Image(systemName: "square.and.arrow.up")
                        .accessibilityLabel("分享文本")
                }
            }
        }
    }

    private func generatePDF() {
        let pageBounds = CGRect(x: 0, y: 0, width: 595, height: 842)
        let renderer = UIGraphicsPDFRenderer(bounds: pageBounds)
        let report = VisitSummaryPDFReport(
            medications: reportMedications,
            tasks: reportTasks,
            doseChanges: reportDoseChanges,
            riskCards: reportRiskCards,
            trendDashboard: trendDashboard,
            healthSignals: reportHealthSignals,
            startDate: normalizedRange.start,
            endDate: normalizedRange.end,
            generatedAt: Date()
        )
        let targetURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("复诊资料-\(Int(Date().timeIntervalSince1970)).pdf")
        let data = renderer.pdfData { context in
            report.draw(in: context, pageBounds: pageBounds)
        }
        do {
            try data.write(to: targetURL, options: .atomic)
            pdfURL = targetURL
            generatedPDFSignature = exportSignature
            exportMessage = ""
        } catch {
            exportMessage = "PDF 生成失败，请稍后重试。"
        }
    }

    private func resetGeneratedPDFState() {
        pdfURL = nil
        generatedPDFSignature = ""
        previewPDFItem = nil
        exportMessage = ""
    }
}

private struct VisitSummaryExportPanel: View {
    let pdfURL: URL?
    let exportMessage: String
    let rangeText: String
    let medicationCount: Int
    let completionRate: Double
    let communicationCount: Int
    let onGeneratePDF: () -> Void
    let onPreviewPDF: (URL) -> Void

    private var isPDFReady: Bool {
        pdfURL != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("复诊沟通 PDF")
                        .font(.headline)
                    Text(rangeText)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer(minLength: 10)

                Label(isPDFReady ? "已生成" : "待生成", systemImage: isPDFReady ? "checkmark.circle.fill" : "doc.badge.plus")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(statusTint)
                    .lineLimit(1)
            }

            HStack(spacing: 10) {
                VisitSummaryExportMetric(title: "药品", value: "\(medicationCount)", tint: .blue)
                VisitSummaryExportMetric(title: "服用率", value: "\(Int((completionRate * 100).rounded()))%", tint: .teal)
                VisitSummaryExportMetric(title: "需沟通", value: "\(communicationCount)", tint: .orange)
            }

            HStack(spacing: 10) {
                Button(action: onGeneratePDF) {
                    VisitSummaryExportActionLabel(
                        title: isPDFReady ? "重新生成" : "生成 PDF",
                        systemImage: isPDFReady ? "arrow.clockwise" : "doc.badge.plus",
                        tint: .blue,
                        isProminent: true
                    )
                }
                .buttonStyle(.plain)

                if let pdfURL {
                    Button {
                        onPreviewPDF(pdfURL)
                    } label: {
                        VisitSummaryExportActionLabel(title: "预览", systemImage: "eye", tint: .indigo)
                    }
                    .buttonStyle(.plain)

                    ShareLink(item: pdfURL) {
                        VisitSummaryExportActionLabel(title: "分享", systemImage: "square.and.arrow.up", tint: .teal)
                    }
                }
            }

            if !exportMessage.isEmpty {
                Text(exportMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .padding(.top, -2)
            }
        }
        .padding(.vertical, 6)
    }

    private var statusTint: Color {
        isPDFReady ? .green : .blue
    }
}

private struct VisitSummaryExportMetric: View {
    let title: String
    let value: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value)
                .font(.subheadline.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct VisitSummaryExportActionLabel: View {
    let title: String
    let systemImage: String
    let tint: Color
    var isProminent = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.subheadline.weight(.semibold))
            Text(title)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.82)
            Spacer(minLength: 10)
        }
        .foregroundStyle(isProminent ? .white : tint)
        .padding(.horizontal, isProminent ? 14 : 12)
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .background(isProminent ? tint : tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            if !isProminent {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(tint.opacity(0.16), lineWidth: 1)
            }
        }
    }
}

private struct VisitSummaryMetricGrid: View {
    let medicationCount: Int
    let completionRate: Double
    let takenCount: Int
    let communicationCount: Int

    var body: some View {
        HStack(spacing: 10) {
            VisitSummaryMetricTile(title: "药品", value: "\(medicationCount)", tint: .blue)
            VisitSummaryMetricTile(title: "服用率", value: "\(Int((completionRate * 100).rounded()))%", tint: .green)
            VisitSummaryMetricTile(title: "需沟通", value: "\(communicationCount)", tint: .orange)
        }
        .padding(.vertical, 4)
    }
}

private struct VisitSummaryMetricTile: View {
    let title: String
    let value: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(value)
                .font(.title3.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
        .background(tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct VisitSummaryHealthSignalCard: View {
    let summary: HealthKitRecentSummary
    let hasCompletedAuthorizationRequest: Bool
    let statusMessage: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: summary.hasSamples ? "heart.text.square.fill" : "heart.text.square")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(summary.hasSamples ? .teal : .secondary)
                    .frame(width: 38, height: 38)
                    .background((summary.hasSamples ? Color.teal : Color.secondary).opacity(0.12), in: RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 4) {
                    Text(summary.hasSamples ? "已纳入复诊资料" : healthSignalEmptyTitle)
                        .font(.headline)
                    Text(summary.hasSamples ? summary.latestSampleText : statusMessage)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            HStack(spacing: 10) {
                VisitSummaryMetricTile(title: "覆盖", value: summary.hasSamples ? "\(summary.coveredDayCount) 天" : "0 天", tint: .teal)
                VisitSummaryMetricTile(title: "样本", value: "\(summary.sampleCount)", tint: .blue)
                VisitSummaryMetricTile(title: "指标", value: "\(summary.metricSummaries.count)", tint: .indigo)
            }

            if summary.hasSamples {
                Text(summary.metricSummaries.prefix(3).map(\.title).joined(separator: "、"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 4)
    }

    private var healthSignalEmptyTitle: String {
        hasCompletedAuthorizationRequest ? "本范围暂无健康样本" : "等待完成 Apple 健康授权请求"
    }
}

private enum VisitSummaryDateRange {
    static func normalized(startDate: Date, endDate: Date) -> (start: Date, end: Date) {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: min(startDate, endDate))
        let endStart = calendar.startOfDay(for: max(startDate, endDate))
        let end = calendar.date(byAdding: DateComponents(day: 1, second: -1), to: endStart) ?? endStart
        return (start, end)
    }

    static func displayText(startDate: Date, endDate: Date) -> String {
        "\(AppFormatters.day.string(from: startDate)) - \(AppFormatters.day.string(from: endDate))"
    }
}

private enum VisitSummaryTaskFilter {
    static func historicalTasks(
        from tasks: [StoredDoseTask],
        startDate: Date,
        endDate: Date
    ) -> [StoredDoseTask] {
        return tasks
            .filter { task in
                let referenceDate = task.effectiveAdherenceDate
                guard referenceDate >= startDate && referenceDate <= endDate else {
                    return false
                }
                return task.dueAt <= endDate || task.effectiveAdherenceRecordedAt != nil
            }
            .sorted { $0.effectiveAdherenceDate < $1.effectiveAdherenceDate }
    }
}

private struct VisitSummaryPDFReport {
    let medications: [StoredMedication]
    let tasks: [StoredDoseTask]
    let doseChanges: [StoredMedicationDoseChange]
    let riskCards: [StoredRiskCard]
    let trendDashboard: MedicationTrendDashboard
    let healthSignals: [HealthSignalSample]
    let startDate: Date
    let endDate: Date
    let generatedAt: Date

    private static let primaryText = UIColor(red: 0.10, green: 0.12, blue: 0.16, alpha: 1)
    private static let secondaryText = UIColor(red: 0.42, green: 0.46, blue: 0.54, alpha: 1)
    private static let mutedText = UIColor(red: 0.62, green: 0.66, blue: 0.74, alpha: 1)
    private static let dividerColor = UIColor(red: 0.86, green: 0.89, blue: 0.94, alpha: 1)
    private static let neutralPanel = UIColor(red: 0.96, green: 0.975, blue: 0.995, alpha: 1)

    private var completedCount: Int {
        tasks.filter { $0.status == .taken || $0.status == .corrected }.count
    }

    private var skippedCount: Int {
        tasks.filter { $0.status == .skipped }.count
    }

    private var delayedCount: Int {
        tasks.filter { $0.status == .delayed }.count
    }

    private var completionRate: Double {
        tasks.isEmpty ? 0 : Double(completedCount) / Double(tasks.count)
    }

    private var adherenceInsight: AdherenceInsight {
        AdherenceInsightBuilder().build(
            scheduledDoses: tasks.map(\.coreScheduledDose),
            events: tasks.compactMap(\.coreDoseEventUsingEffectiveAdherenceDate),
            timeZone: TimeZone.current,
            now: generatedAt
        )
    }

    private var recentDoseChanges: [StoredMedicationDoseChange] {
        return doseChanges
            .sorted { $0.effectiveFrom > $1.effectiveFrom }
    }

    private var activeProfessionalRiskCards: [StoredRiskCard] {
        riskCards.filter { $0.requiresProfessionalReview && $0.isActive }
    }

    private var communicationCount: Int {
        skippedCount + delayedCount + activeProfessionalRiskCards.count
    }

    private var healthSignalDayCount: Int {
        let calendar = Calendar.current
        return Set(healthSignals.map { calendar.startOfDay(for: $0.measuredAt) }).count
    }

    private var healthSignalMetricCount: Int {
        Set(healthSignals.map(\.kind)).count
    }

    private var rangeText: String {
        VisitSummaryDateRange.displayText(startDate: startDate, endDate: endDate)
    }

    func draw(in context: UIGraphicsPDFRendererContext, pageBounds: CGRect) {
        context.beginPage()
        drawSummaryPage(in: pageBounds)
        context.beginPage()
        drawTimelinePage(in: pageBounds)
    }

    private func drawSummaryPage(in pageBounds: CGRect) {
        let margin: CGFloat = 36
        let contentWidth = pageBounds.width - margin * 2
        let accent = UIColor(red: 0.13, green: 0.38, blue: 0.92, alpha: 1)
        let green = UIColor(red: 0.12, green: 0.58, blue: 0.32, alpha: 1)
        let orange = UIColor(red: 0.92, green: 0.43, blue: 0.12, alpha: 1)
        let red = UIColor(red: 0.78, green: 0.18, blue: 0.16, alpha: 1)
        let softBackground = UIColor(red: 0.96, green: 0.975, blue: 0.995, alpha: 1)
        var y = margin

        drawHeader(x: margin, y: y, width: contentWidth, accent: accent)
        y += 82

        let metricWidth = (contentWidth - 24) / 4
        let metrics = [
            ("药品", "\(medications.count)", accent),
            ("完成率", "\(Int((completionRate * 100).rounded()))%", green),
            ("已服用", "\(completedCount)", green),
            ("需沟通", "\(communicationCount)", orange)
        ]
        for (index, metric) in metrics.enumerated() {
            let x = margin + CGFloat(index) * (metricWidth + 8)
            drawMetricCard(title: metric.0, value: metric.1, color: metric.2, rect: CGRect(x: x, y: y, width: metricWidth, height: 62))
        }
        y += 78

        drawSectionTitle("所选范围执行概览", x: margin, y: y)
        y += 26
        drawStackedAdherenceBar(
            rect: CGRect(x: margin, y: y, width: contentWidth, height: 12),
            completed: completedCount,
            delayed: delayedCount,
            skipped: skippedCount,
            total: tasks.count,
            completedColor: green,
            delayedColor: accent,
            skippedColor: orange
        )
        y += 20
        drawAdherenceLegend(x: margin, y: y, completedColor: green, delayedColor: accent, skippedColor: orange)
        y += 24
        drawMultilineText(
            "\(rangeText) 期间计划 \(tasks.count) 次，已服用 \(completedCount) 次，稍后 \(delayedCount) 次，已忽略 \(skippedCount) 次。",
            rect: CGRect(x: margin, y: y, width: contentWidth, height: 34),
            font: .systemFont(ofSize: 10),
            color: Self.secondaryText
        )
        y += 48

        let columnWidth = (contentWidth - 12) / 2
        drawTrendPanel(rect: CGRect(x: margin, y: y, width: columnWidth, height: 92), accent: accent)
        drawDoseChangePanel(rect: CGRect(x: margin + columnWidth + 12, y: y, width: columnWidth, height: 92), accent: UIColor.systemPurple)
        y += 110

        drawSectionTitle("当前药品", x: margin, y: y)
        y += 24
        let medicationRows = Array(medications.prefix(4))
        for medication in medicationRows {
            let relatedTasks = tasks.filter { $0.medicationID == medication.id }
            let taken = relatedTasks.filter { $0.status == .taken || $0.status == .corrected }.count
            drawRoundedPanel(rect: CGRect(x: margin, y: y, width: contentWidth, height: 34), fill: softBackground)
            drawText(userFacingMedicationName(for: medication), rect: CGRect(x: margin + 14, y: y + 7, width: 160, height: 18), font: .systemFont(ofSize: 11, weight: .semibold))
            drawText([medication.strength, medication.form].filter { !$0.isEmpty }.joined(separator: " · "), rect: CGRect(x: margin + 180, y: y + 8, width: 190, height: 16), font: .systemFont(ofSize: 9), color: Self.secondaryText)
            drawText("\(taken) / \(relatedTasks.count) 次", rect: CGRect(x: margin + contentWidth - 92, y: y + 8, width: 78, height: 16), font: .monospacedDigitSystemFont(ofSize: 10, weight: .semibold), color: green, alignment: .right)
            y += 39
        }
        if medications.count > medicationRows.count {
            drawBodyText("另有 \(medications.count - medicationRows.count) 个药品未在本页展开。", rect: CGRect(x: margin, y: y, width: contentWidth, height: 20))
            y += 28
        }

        drawSectionTitle("异常节点与风险复核", x: margin, y: y)
        y += 24
        let exceptions = tasks
            .filter { $0.status == .skipped || $0.status == .delayed }
            .sorted { $0.effectiveAdherenceDate > $1.effectiveAdherenceDate }
        let importantRiskCards = activeProfessionalRiskCards.prefix(2)
        drawExceptionPanel(rect: CGRect(x: margin, y: y, width: columnWidth, height: 112), exceptions: Array(exceptions.prefix(4)), accent: accent, orange: orange)
        drawRiskPanel(rect: CGRect(x: margin + columnWidth + 12, y: y, width: columnWidth, height: 112), risks: Array(importantRiskCards), red: red)

        drawFooter(x: margin, y: pageBounds.height - 54, width: contentWidth)
    }

    private func drawTimelinePage(in pageBounds: CGRect) {
        let margin: CGFloat = 36
        let contentWidth = pageBounds.width - margin * 2
        let accent = UIColor(red: 0.13, green: 0.38, blue: 0.92, alpha: 1)
        let green = UIColor(red: 0.12, green: 0.58, blue: 0.32, alpha: 1)
        let orange = UIColor(red: 0.92, green: 0.43, blue: 0.12, alpha: 1)
        let red = UIColor(red: 0.78, green: 0.18, blue: 0.16, alpha: 1)
        let purple = UIColor(red: 0.46, green: 0.26, blue: 0.82, alpha: 1)
        var y = margin

        drawHeader(x: margin, y: y, width: contentWidth, accent: accent)
        y += 82

        drawSectionTitle("连续达标与复诊沟通重点", x: margin, y: y)
        y += 24
        let insight = adherenceInsight
        let streakValue = insight.currentStreakDays > 0 ? "\(insight.currentStreakDays) 天" : "\(insight.longestStreakDays) 天"
        let streakTitle = insight.currentStreakDays > 0 ? "当前连续达标" : "历史最长达标"
        let columnWidth = (contentWidth - 12) / 2
        drawMetricCard(title: streakTitle, value: streakValue, color: green, rect: CGRect(x: margin, y: y, width: columnWidth, height: 62))
        drawMetricCard(title: "范围内需沟通", value: "\(communicationCount)", color: orange, rect: CGRect(x: margin + columnWidth + 12, y: y, width: columnWidth, height: 62))
        y += 78
        drawMultilineText(
            insight.message,
            rect: CGRect(x: margin, y: y, width: contentWidth, height: 36),
            font: .systemFont(ofSize: 10),
            color: Self.secondaryText
        )
        y += 54

        drawSectionTitle("时间线", x: margin, y: y)
        y += 26
        let events = timelineEvents(accent: accent, green: green, orange: orange, red: red, purple: purple)
        if events.isEmpty {
            drawRoundedPanel(rect: CGRect(x: margin, y: y, width: contentWidth, height: 54), fill: Self.neutralPanel)
            drawMultilineText(
                "所选日期范围内没有需要优先沟通的异常节点、剂量变化或风险复核记录。",
                rect: CGRect(x: margin + 14, y: y + 14, width: contentWidth - 28, height: 28),
                font: .systemFont(ofSize: 10),
                color: Self.secondaryText
            )
            y += 72
        } else {
            for event in events.prefix(9) {
                drawTimelineEvent(event, x: margin, y: y, width: contentWidth)
                y += 48
            }
            if events.count > 9 {
                drawBodyText("另有 \(events.count - 9) 条记录未在本页展开。", rect: CGRect(x: margin + 18, y: y, width: contentWidth - 36, height: 18))
                y += 26
            }
        }

        let lowerTop = min(y + 4, pageBounds.height - 190)
        drawSectionTitle("医生快速查看", x: margin, y: lowerTop)
        let quickTop = lowerTop + 24
        drawDoctorChecklist(rect: CGRect(x: margin, y: quickTop, width: columnWidth, height: 116), accent: accent, orange: orange, red: red)
        drawMedicationContextPanel(rect: CGRect(x: margin + columnWidth + 12, y: quickTop, width: columnWidth, height: 116), green: green, purple: purple)

        drawFooter(x: margin, y: pageBounds.height - 54, width: contentWidth)
    }

    private func drawStackedAdherenceBar(
        rect: CGRect,
        completed: Int,
        delayed: Int,
        skipped: Int,
        total: Int,
        completedColor: UIColor,
        delayedColor: UIColor,
        skippedColor: UIColor
    ) {
        let background = UIBezierPath(roundedRect: rect, cornerRadius: rect.height / 2)
        Self.dividerColor.setFill()
        background.fill()

        guard total > 0 else {
            return
        }

        guard let context = UIGraphicsGetCurrentContext() else {
            return
        }
        context.saveGState()
        background.addClip()
        defer { context.restoreGState() }

        let segments: [(Int, UIColor)] = [
            (completed, completedColor),
            (delayed, delayedColor),
            (skipped, skippedColor)
        ].filter { $0.0 > 0 }

        var currentX = rect.minX
        for (count, color) in segments {
            let width = rect.width * CGFloat(count) / CGFloat(total)
            let segmentRect = CGRect(x: currentX, y: rect.minY, width: width, height: rect.height)
            color.setFill()
            UIBezierPath(rect: segmentRect).fill()
            currentX += width
        }

        Self.dividerColor.setStroke()
        background.lineWidth = 1
        background.stroke()
    }

    private func drawAdherenceLegend(x: CGFloat, y: CGFloat, completedColor: UIColor, delayedColor: UIColor, skippedColor: UIColor) {
        drawLegendItem("已服用 \(completedCount)", x: x, y: y, color: completedColor)
        drawLegendItem("稍后 \(delayedCount)", x: x + 126, y: y, color: delayedColor)
        drawLegendItem("已忽略 \(skippedCount)", x: x + 238, y: y, color: skippedColor)
    }

    private func drawLegendItem(_ title: String, x: CGFloat, y: CGFloat, color: UIColor) {
        color.setFill()
        UIBezierPath(ovalIn: CGRect(x: x, y: y + 4, width: 7, height: 7)).fill()
        drawText(title, rect: CGRect(x: x + 12, y: y, width: 100, height: 16), font: .systemFont(ofSize: 9), color: Self.secondaryText)
    }

    private func drawTrendPanel(rect: CGRect, accent: UIColor) {
        let trendColor = trendReportColor(trendDashboard.direction, fallback: accent)
        drawRoundedPanel(rect: rect, fill: trendColor.withAlphaComponent(0.10))
        drawText("用药趋势", rect: CGRect(x: rect.minX + 12, y: rect.minY + 10, width: rect.width - 24, height: 16), font: .systemFont(ofSize: 11, weight: .semibold), color: trendColor)
        drawText("综合 \(pdfPercentage(trendDashboard.overallScore))% · \(trendReportTitle(trendDashboard.direction))", rect: CGRect(x: rect.minX + 12, y: rect.minY + 29, width: rect.width - 24, height: 18), font: .monospacedDigitSystemFont(ofSize: 13, weight: .bold))
        drawProgressBar(rect: CGRect(x: rect.minX + 12, y: rect.minY + 52, width: rect.width - 24, height: 7), progress: trendDashboard.overallScore, background: Self.dividerColor, fill: trendColor)

        let highlightedMetric = trendDashboard.metrics.first { $0.direction == .declining || $0.direction == .fluctuating }
            ?? trendDashboard.metrics.first
        let detail = highlightedMetric.map { "\($0.title) \(pdfPercentage($0.score))%：\($0.summary)" } ?? trendDashboard.summary
        drawMultilineText(detail, rect: CGRect(x: rect.minX + 12, y: rect.minY + 64, width: rect.width - 24, height: 24), font: .systemFont(ofSize: 8.5), color: Self.secondaryText)
    }

    private func drawDoseChangePanel(rect: CGRect, accent: UIColor) {
        drawRoundedPanel(rect: rect, fill: accent.withAlphaComponent(0.10))
        drawText("剂量变化", rect: CGRect(x: rect.minX + 12, y: rect.minY + 10, width: rect.width - 24, height: 16), font: .systemFont(ofSize: 11, weight: .semibold), color: accent)
        let changes = Array(recentDoseChanges.prefix(2))
        if changes.isEmpty {
            drawMultilineText("所选范围内没有记录剂量变化。", rect: CGRect(x: rect.minX + 12, y: rect.minY + 30, width: rect.width - 24, height: 50), font: .systemFont(ofSize: 9), color: Self.secondaryText)
            return
        }

        var rowY = rect.minY + 29
        for change in changes {
            let medicationName = medications.first { $0.id == change.medicationID }.map(userFacingMedicationName(for:)) ?? "待核对药品名称"
            let previous = change.previousDoseValue.map { doseAmountText(value: $0, unit: change.previousDoseUnit) } ?? "未记录"
            let current = doseAmountText(value: change.newDoseValue, unit: change.newDoseUnit)
            drawText(medicationName, rect: CGRect(x: rect.minX + 12, y: rowY, width: rect.width - 24, height: 13), font: .systemFont(ofSize: 9, weight: .semibold))
            drawText("\(previous) 调整为 \(current)", rect: CGRect(x: rect.minX + 12, y: rowY + 13, width: rect.width - 24, height: 13), font: .systemFont(ofSize: 8.5), color: Self.secondaryText)
            drawText(pdfDoseChangePeriodText(change: change), rect: CGRect(x: rect.minX + 12, y: rowY + 26, width: rect.width - 24, height: 13), font: .systemFont(ofSize: 8), color: Self.secondaryText)
            rowY += 39
        }
    }

    private func drawExceptionPanel(rect: CGRect, exceptions: [StoredDoseTask], accent: UIColor, orange: UIColor) {
        drawRoundedPanel(rect: rect, fill: Self.neutralPanel)
        drawText("异常节点", rect: CGRect(x: rect.minX + 12, y: rect.minY + 10, width: rect.width - 24, height: 16), font: .systemFont(ofSize: 11, weight: .semibold))
        guard !exceptions.isEmpty else {
            drawMultilineText("所选范围内没有需要优先沟通的忽略或稍后记录。", rect: CGRect(x: rect.minX + 12, y: rect.minY + 32, width: rect.width - 24, height: 32), font: .systemFont(ofSize: 9), color: Self.secondaryText)
            return
        }

        var rowY = rect.minY + 32
        for task in exceptions {
            let medicationName = medications.first { $0.id == task.medicationID }.map(userFacingMedicationName(for:)) ?? "待核对药品名称"
            let action = task.status == .skipped ? "已忽略" : "稍后提醒"
            let displayDate = task.effectiveAdherenceDate
            drawTimelineDot(x: rect.minX + 13, y: rowY + 6, color: task.status == .skipped ? orange : accent)
            drawText("\(AppFormatters.day.string(from: displayDate)) \(AppFormatters.time.string(from: displayDate))", rect: CGRect(x: rect.minX + 28, y: rowY, width: 92, height: 14), font: .monospacedDigitSystemFont(ofSize: 8, weight: .medium), color: Self.secondaryText)
            drawText("\(medicationName) · \(action)", rect: CGRect(x: rect.minX + 122, y: rowY, width: rect.width - 134, height: 14), font: .systemFont(ofSize: 8.5, weight: .semibold))
            rowY += 20
        }
    }

    private func drawRiskPanel(rect: CGRect, risks: [StoredRiskCard], red: UIColor) {
        drawRoundedPanel(rect: rect, fill: red.withAlphaComponent(0.08))
        drawText("风险复核", rect: CGRect(x: rect.minX + 12, y: rect.minY + 10, width: rect.width - 24, height: 16), font: .systemFont(ofSize: 11, weight: .semibold), color: red)
        guard !risks.isEmpty else {
            drawMultilineText("暂无需要优先沟通的风险提醒。", rect: CGRect(x: rect.minX + 12, y: rect.minY + 32, width: rect.width - 24, height: 32), font: .systemFont(ofSize: 9), color: Self.secondaryText)
            return
        }

        var rowY = rect.minY + 31
        for card in risks {
            let medicationName = medications.first { $0.id == card.medicationID }.map(userFacingMedicationName(for:)) ?? "待核对药品名称"
            let focus = pdfRiskFocusSummary(for: card)
            drawText(medicationName, rect: CGRect(x: rect.minX + 12, y: rowY, width: 88, height: 13), font: .systemFont(ofSize: 8.5, weight: .semibold), color: red)
            drawText(pdfRiskDisplayTitle(for: card, limit: 36), rect: CGRect(x: rect.minX + 104, y: rowY, width: rect.width - 116, height: 13), font: .systemFont(ofSize: 8.5, weight: .semibold))
            drawMultilineText(focus, rect: CGRect(x: rect.minX + 12, y: rowY + 14, width: rect.width - 24, height: 24), font: .systemFont(ofSize: 8), color: Self.secondaryText)
            rowY += 38
        }
    }

    private struct PDFTimelineEvent {
        let date: Date
        let title: String
        let detail: String
        let color: UIColor
    }

    private func timelineEvents(
        accent: UIColor,
        green: UIColor,
        orange: UIColor,
        red: UIColor,
        purple: UIColor
    ) -> [PDFTimelineEvent] {
        var events: [PDFTimelineEvent] = []

        let exceptionEvents = tasks
            .filter { $0.status == .skipped || $0.status == .delayed }
            .sorted { $0.effectiveAdherenceDate > $1.effectiveAdherenceDate }
            .prefix(8)
            .map { task -> PDFTimelineEvent in
                let medicationName = medications.first { $0.id == task.medicationID }.map(userFacingMedicationName(for:)) ?? "待核对药品名称"
                let action = task.status == .skipped ? "已忽略" : "稍后提醒"
                let doseText = "\(task.doseValue.formatted()) \(localizedMedicationUnit(task.doseUnit))"
                let reason = pdfRecordReason(from: task.reason).map { " · \($0)" } ?? ""
                return PDFTimelineEvent(
                    date: task.effectiveAdherenceDate,
                    title: "\(medicationName) · \(action)",
                    detail: "\(AppFormatters.day.string(from: task.effectiveAdherenceDate)) \(AppFormatters.time.string(from: task.effectiveAdherenceDate)) · \(doseText)\(reason)",
                    color: task.status == .skipped ? orange : accent
                )
            }
        events.append(contentsOf: exceptionEvents)

        let doseEvents = recentDoseChanges.prefix(4).map { change -> PDFTimelineEvent in
            let medicationName = medications.first { $0.id == change.medicationID }.map(userFacingMedicationName(for:)) ?? "待核对药品名称"
            let previous = change.previousDoseValue.map { doseAmountText(value: $0, unit: change.previousDoseUnit) } ?? "未记录"
            let current = doseAmountText(value: change.newDoseValue, unit: change.newDoseUnit)
            return PDFTimelineEvent(
                date: change.effectiveFrom,
                title: "\(medicationName) · 剂量变化",
                detail: "\(previous) 调整为 \(current)；\(pdfDoseChangePeriodText(change: change))",
                color: purple
            )
        }
        events.append(contentsOf: doseEvents)

        let riskEvents = riskCards
            .filter {
                $0.requiresProfessionalReview
                    && $0.isActive
                    && $0.lastDetectedAt >= startDate
                    && $0.lastDetectedAt <= endDate
            }
            .sorted {
                if $0.displayPriority != $1.displayPriority {
                    return $0.displayPriority < $1.displayPriority
                }
                return $0.lastDetectedAt > $1.lastDetectedAt
            }
            .prefix(5)
            .map { card -> PDFTimelineEvent in
                let medicationName = medications.first { $0.id == card.medicationID }.map(userFacingMedicationName(for:)) ?? "待核对药品名称"
                return PDFTimelineEvent(
                    date: card.lastDetectedAt,
                    title: "\(medicationName) · \(pdfRiskDisplayTitle(for: card, limit: 42))",
                    detail: pdfRiskFocusSummary(for: card, limit: 84),
                    color: card.severity == .high || card.severity == .critical ? red : orange
                )
            }
        events.append(contentsOf: riskEvents)

        return events.sorted { lhs, rhs in
            if lhs.date != rhs.date {
                return lhs.date > rhs.date
            }
            return lhs.title < rhs.title
        }
    }

    private func drawTimelineEvent(_ event: PDFTimelineEvent, x: CGFloat, y: CGFloat, width: CGFloat) {
        drawTimelineDot(x: x + 5, y: y + 13, color: event.color)
        drawText(
            AppFormatters.day.string(from: event.date),
            rect: CGRect(x: x + 24, y: y + 4, width: 78, height: 15),
            font: .monospacedDigitSystemFont(ofSize: 8.5, weight: .medium),
            color: Self.secondaryText
        )
        drawText(
            event.title,
            rect: CGRect(x: x + 106, y: y + 3, width: width - 118, height: 16),
            font: .systemFont(ofSize: 10, weight: .semibold)
        )
        drawMultilineText(
            event.detail,
            rect: CGRect(x: x + 106, y: y + 20, width: width - 118, height: 24),
            font: .systemFont(ofSize: 8.5),
            color: Self.secondaryText
        )
        Self.dividerColor.setStroke()
        let line = UIBezierPath()
        line.move(to: CGPoint(x: x + 9, y: y + 27))
        line.addLine(to: CGPoint(x: x + 9, y: y + 47))
        line.lineWidth = 1
        line.stroke()
    }

    private func drawDoctorChecklist(rect: CGRect, accent: UIColor, orange: UIColor, red: UIColor) {
        drawRoundedPanel(rect: rect, fill: Self.neutralPanel)
        drawText("需要沟通", rect: CGRect(x: rect.minX + 12, y: rect.minY + 10, width: rect.width - 24, height: 16), font: .systemFont(ofSize: 11, weight: .semibold), color: accent)

        let activeRiskCount = riskCards.filter { $0.requiresProfessionalReview && $0.isActive }.count
        let rows = [
            ("忽略记录", "\(skippedCount) 次", skippedCount > 0 ? orange : Self.secondaryText),
            ("稍后记录", "\(delayedCount) 次", delayedCount > 0 ? accent : Self.secondaryText),
            ("风险复核", "\(activeRiskCount) 条", activeRiskCount > 0 ? red : Self.secondaryText)
        ]
        var rowY = rect.minY + 32
        for row in rows {
            drawTimelineDot(x: rect.minX + 13, y: rowY + 4, color: row.2)
            drawText(row.0, rect: CGRect(x: rect.minX + 28, y: rowY, width: 88, height: 14), font: .systemFont(ofSize: 9), color: Self.secondaryText)
            drawText(row.1, rect: CGRect(x: rect.minX + rect.width - 82, y: rowY, width: 68, height: 14), font: .monospacedDigitSystemFont(ofSize: 9.5, weight: .semibold), color: row.2, alignment: .right)
            rowY += 22
        }
    }

    private func drawMedicationContextPanel(rect: CGRect, green: UIColor, purple: UIColor) {
        drawRoundedPanel(rect: rect, fill: purple.withAlphaComponent(0.09))
        drawText("方案与健康", rect: CGRect(x: rect.minX + 12, y: rect.minY + 10, width: rect.width - 24, height: 16), font: .systemFont(ofSize: 11, weight: .semibold), color: purple)

        let trackedMedicationCount = medications.filter { $0.lifecycleStatus != .archived }.count
        let rows: [(String, String, UIColor)] = [
            ("剂量变化", "\(recentDoseChanges.count) 次", purple),
            ("管理药品", "\(trackedMedicationCount) 个", green),
            ("健康信号", healthSignals.isEmpty ? "待样本" : "\(healthSignalDayCount) 天 · \(healthSignals.count) 条", UIColor.systemTeal)
        ]
        var rowY = rect.minY + 32
        for row in rows {
            drawTimelineDot(x: rect.minX + 13, y: rowY + 4, color: row.2)
            drawText(row.0, rect: CGRect(x: rect.minX + 28, y: rowY, width: 74, height: 14), font: .systemFont(ofSize: 9), color: Self.secondaryText)
            drawText(row.1, rect: CGRect(x: rect.minX + 104, y: rowY, width: rect.width - 116, height: 14), font: .monospacedDigitSystemFont(ofSize: 9.5, weight: .semibold), color: row.2, alignment: .right)
            rowY += 22
        }

        if healthSignalMetricCount > 0 {
            drawText("纳入 \(healthSignalMetricCount) 类指标", rect: CGRect(x: rect.minX + 28, y: rect.maxY - 20, width: rect.width - 40, height: 12), font: .systemFont(ofSize: 8), color: Self.secondaryText)
        }
    }

    private func doseAmountText(value: Double, unit: String) -> String {
        let number = value.formatted(.number.precision(.fractionLength(0...2)))
        return "\(number) \(localizedMedicationUnit(unit))"
    }

    private func trimmedPDFText(_ text: String, limit: Int) -> String {
        let normalized = text
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "说明书“", with: "")
            .replacingOccurrences(of: "”指出：", with: "：")
            .replacingOccurrences(of: "请咨询医生或药师", with: "")
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalized.count > limit else {
            return normalized
        }
        let index = normalized.index(normalized.startIndex, offsetBy: limit)
        return String(normalized[..<index]) + "..."
    }

    private func pdfRecordReason(from rawText: String) -> String? {
        let displayParts = rawText
            .components(separatedBy: "；")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { part in
                !part.isEmpty
                    && !part.contains("用户撤销后等待确认")
                    && !part.contains("同一剂量重复提醒已随")
                    && !part.contains("未来提醒已停用")
            }
        guard !displayParts.isEmpty else {
            return nil
        }
        return displayParts.joined(separator: "；")
    }

    private func pdfRiskFocusSummary(for card: StoredRiskCard, limit: Int = 72) -> String {
        if let focus = pdfRiskConcreteFocusText(for: card, limit: limit) {
            return focus
        }
        let message = trimmedPDFText(card.message, limit: limit)
        guard !message.isEmpty else {
            return "需补充说明书或向医生或药师确认具体对象。"
        }
        return message
    }

    private func pdfRiskDisplayTitle(for card: StoredRiskCard, limit: Int) -> String {
        let rawTitle = trimmedPDFText(card.title, limit: limit)
        guard pdfIsGenericRiskFocus(rawTitle) || rawTitle == "警示信息" || rawTitle == "注意事项" else {
            return rawTitle.isEmpty ? pdfRiskCategoryTitle(for: card) : rawTitle
        }
        let category = pdfIsContraindicationRisk(card) ? "禁忌或慎用" : pdfRiskCategoryTitle(for: card)
        guard let focus = pdfRiskConcreteFocusText(for: card, limit: limit),
              !focus.isEmpty
        else {
            return category
        }
        return trimmedPDFText("\(category)：\(pdfRiskShareFocusText(focus))", limit: limit)
    }

    private func pdfRiskConcreteFocusText(for card: StoredRiskCard, limit: Int) -> String? {
        let focus = pdfExtractedRiskFocus(from: card, limit: limit)
        switch RiskAssessmentCardKind(rawValue: card.kindRaw) ?? .labelRisk {
        case .foodReview:
            return focus.isEmpty ? "需核对具体饮食或生活方式。" : "核对饮食或生活方式：\(focus)"
        case .healthConditionReview:
            return focus.isEmpty ? "需核对具体病症或症状。" : "核对病症或症状：\(focus)"
        case .medicationSourceReview:
            return focus.isEmpty ? "需按药盒、说明书或医嘱核对来源。" : "核对来源：\(focus)"
        case .drugClassContext:
            return focus.isEmpty ? nil : "药品类别：\(focus)"
        case .labelRisk:
            let group = RiskReviewGrouper().mappedGroup(for: card.coreRiskCard)
            if pdfIsContraindicationRisk(card) {
                return focus.isEmpty ? "需核对禁忌条件，当前资料未写明具体对象。" : "核对禁忌条件：\(focus)"
            }
            switch group {
            case .drugInteraction:
                return focus.isEmpty ? "需核对合用药品，当前资料未写明具体名称。" : "核对合用药品：\(focus)"
            case .foodAndLifestyleInteraction:
                return focus.isEmpty ? "需核对具体饮食或生活方式。" : "核对饮食或生活方式：\(focus)"
            case .conditionAndSymptomAttention:
                return focus.isEmpty ? "需核对具体病症或症状。" : "核对病症或症状：\(focus)"
            }
        }
    }

    private func pdfExtractedRiskFocus(from card: StoredRiskCard, limit: Int) -> String {
        let titleFocus = pdfRiskFocusFromReviewTitle(card.title, limit: limit)
        if !titleFocus.isEmpty {
            return titleFocus
        }
        let sourceExcerpt = trimmedPDFText(card.sourceExcerpt, limit: limit)
        if !sourceExcerpt.isEmpty {
            return sourceExcerpt
        }
        let message = trimmedPDFText(card.message, limit: limit)
        return pdfIsGenericRiskFocus(message) ? "" : message
    }

    private func pdfRiskFocusFromReviewTitle(_ title: String, limit: Int) -> String {
        guard let separatorIndex = title.firstIndex(of: "：") ?? title.firstIndex(of: ":") else {
            return ""
        }
        return trimmedPDFText(String(title[title.index(after: separatorIndex)...]), limit: limit)
    }

    private func pdfRiskShareFocusText(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("需核对") else {
            return trimmed
        }
        return String(trimmed.dropFirst("需核对".count))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func pdfRiskCategoryTitle(for card: StoredRiskCard) -> String {
        switch RiskAssessmentCardKind(rawValue: card.kindRaw) ?? .labelRisk {
        case .foodReview:
            return "饮食注意"
        case .healthConditionReview:
            return "病症注意"
        case .medicationSourceReview:
            return "来源核对"
        case .drugClassContext:
            return "类别信息"
        case .labelRisk:
            switch RiskReviewGrouper().mappedGroup(for: card.coreRiskCard) {
            case .drugInteraction:
                return "相互作用"
            case .foodAndLifestyleInteraction:
                return "饮食注意"
            case .conditionAndSymptomAttention:
                return "病症注意"
            }
        }
    }

    private func pdfIsContraindicationRisk(_ card: StoredRiskCard) -> Bool {
        let text = pdfNormalizedRiskText("\(card.title) \(card.message) \(card.sourceTitle) \(card.sourceExcerpt)")
        return text.contains("禁忌")
            || text.contains("禁用")
            || text.contains("contraindication")
            || text.contains("contraindicated")
            || text.contains("avoid")
    }

    private func pdfIsGenericRiskFocus(_ text: String) -> Bool {
        let normalizedText = pdfNormalizedRiskText(text)
        return normalizedText.isEmpty
            || normalizedText == "相关风险"
            || normalizedText == "相关警示"
            || normalizedText == "相关提醒"
            || normalizedText.contains("已根据药品资料和用户记录生成用药风险提醒")
    }

    private func pdfNormalizedRiskText(_ value: String) -> String {
        value
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
            .lowercased()
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .trimmingCharacters(in: .punctuationCharacters)
    }

    private func pdfDoseChangePeriodText(change: StoredMedicationDoseChange) -> String {
        let startText = AppFormatters.day.string(from: change.effectiveFrom)
        guard let effectiveUntil = pdfDoseChangeEffectiveUntil(change) else {
            return "\(startText) 起生效"
        }
        if Calendar.current.isDate(effectiveUntil, inSameDayAs: change.effectiveFrom) {
            return "\(startText) 当天生效，之后有新记录"
        }
        return "\(startText) 至 \(AppFormatters.day.string(from: effectiveUntil))"
    }

    private func pdfDoseChangeEffectiveUntil(_ change: StoredMedicationDoseChange) -> Date? {
        let calendar = Calendar.current
        let currentStart = calendar.startOfDay(for: change.effectiveFrom)
        let nextChange = doseChanges
            .filter {
                $0.id != change.id
                    && $0.medicationID == change.medicationID
                    && pdfDoseChangePlanMatches($0, change)
                    && $0.effectiveFrom > change.effectiveFrom
            }
            .min { $0.effectiveFrom < $1.effectiveFrom }

        guard let nextStart = nextChange.map({ calendar.startOfDay(for: $0.effectiveFrom) }) else {
            return nil
        }
        guard nextStart > currentStart else {
            return currentStart
        }
        return calendar.date(byAdding: .day, value: -1, to: nextStart)
    }

    private func pdfDoseChangePlanMatches(_ first: StoredMedicationDoseChange, _ second: StoredMedicationDoseChange) -> Bool {
        guard let firstPlanID = first.planID, let secondPlanID = second.planID else {
            return true
        }
        return firstPlanID == secondPlanID
    }

    private func pdfPercentage(_ value: Double) -> String {
        "\(Int((value * 100).rounded()))"
    }

    private func trendReportTitle(_ direction: MedicationTrendDirection) -> String {
        switch direction {
        case .improving:
            return "趋势改善"
        case .stable:
            return "趋势平稳"
        case .fluctuating:
            return "需要关注"
        case .declining:
            return "趋势下降"
        case .needsData:
            return "继续记录"
        }
    }

    private func trendReportColor(_ direction: MedicationTrendDirection, fallback: UIColor) -> UIColor {
        switch direction {
        case .improving:
            return UIColor(red: 0.12, green: 0.58, blue: 0.32, alpha: 1)
        case .stable:
            return fallback
        case .fluctuating:
            return UIColor(red: 0.92, green: 0.43, blue: 0.12, alpha: 1)
        case .declining:
            return UIColor(red: 0.78, green: 0.18, blue: 0.16, alpha: 1)
        case .needsData:
            return Self.secondaryText
        }
    }

    private func drawHeader(x: CGFloat, y: CGFloat, width: CGFloat, accent: UIColor) {
        drawText("服药复诊沟通报告", rect: CGRect(x: x, y: y, width: width * 0.62, height: 28), font: .systemFont(ofSize: 22, weight: .bold))
        drawText("范围 \(rangeText) · 生成 \(AppFormatters.day.string(from: generatedAt)) \(AppFormatters.time.string(from: generatedAt))", rect: CGRect(x: x, y: y + 32, width: width * 0.74, height: 18), font: .systemFont(ofSize: 10), color: Self.secondaryText)
        drawText("供复诊沟通", rect: CGRect(x: x + width - 118, y: y + 6, width: 118, height: 22), font: .systemFont(ofSize: 11, weight: .semibold), color: accent, alignment: .right)
        drawProgressBar(rect: CGRect(x: x, y: y + 66, width: width, height: 3), progress: 1, background: accent.withAlphaComponent(0.18), fill: accent)
    }

    private func drawMetricCard(title: String, value: String, color: UIColor, rect: CGRect) {
        drawRoundedPanel(rect: rect, fill: color.withAlphaComponent(0.10))
        drawText(value, rect: CGRect(x: rect.minX + 12, y: rect.minY + 10, width: rect.width - 24, height: 24), font: .monospacedDigitSystemFont(ofSize: 19, weight: .bold), color: color)
        drawText(title, rect: CGRect(x: rect.minX + 12, y: rect.minY + 37, width: rect.width - 24, height: 16), font: .systemFont(ofSize: 10, weight: .medium), color: Self.secondaryText)
    }

    private func drawSectionTitle(_ title: String, x: CGFloat, y: CGFloat) {
        drawText(title, rect: CGRect(x: x, y: y, width: 260, height: 20), font: .systemFont(ofSize: 14, weight: .bold))
    }

    private func drawFooter(x: CGFloat, y: CGFloat, width: CGFloat) {
        drawProgressBar(rect: CGRect(x: x, y: y - 10, width: width, height: 1), progress: 1, background: Self.dividerColor, fill: Self.dividerColor)
    }

    private func drawProgressBar(rect: CGRect, progress: Double, background: UIColor, fill: UIColor) {
        let path = UIBezierPath(roundedRect: rect, cornerRadius: rect.height / 2)
        background.setFill()
        path.fill()
        let fillRect = CGRect(x: rect.minX, y: rect.minY, width: rect.width * CGFloat(max(0, min(progress, 1))), height: rect.height)
        guard let context = UIGraphicsGetCurrentContext() else {
            return
        }
        context.saveGState()
        UIBezierPath(roundedRect: fillRect, cornerRadius: rect.height / 2).addClip()
        fill.setFill()
        path.fill()
        context.restoreGState()
    }

    private func drawRoundedPanel(rect: CGRect, fill: UIColor) {
        fill.setFill()
        UIBezierPath(roundedRect: rect, cornerRadius: 8).fill()
    }

    private func drawTimelineDot(x: CGFloat, y: CGFloat, color: UIColor) {
        color.setFill()
        UIBezierPath(ovalIn: CGRect(x: x, y: y, width: 8, height: 8)).fill()
    }

    private func drawBodyText(_ text: String, rect: CGRect) {
        drawText(text, rect: rect, font: .systemFont(ofSize: 10), color: Self.secondaryText)
    }

    private func drawMultilineText(
        _ text: String,
        rect: CGRect,
        font: UIFont,
        color: UIColor = VisitSummaryPDFReport.primaryText,
        alignment: NSTextAlignment = .left
    ) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = alignment
        paragraph.lineBreakMode = .byWordWrapping
        (text as NSString).draw(
            with: rect,
            options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine],
            attributes: [
                .font: font,
                .foregroundColor: color,
                .paragraphStyle: paragraph
            ],
            context: nil
        )
    }

    private func drawText(
        _ text: String,
        rect: CGRect,
        font: UIFont,
        color: UIColor = VisitSummaryPDFReport.primaryText,
        alignment: NSTextAlignment = .left
    ) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = alignment
        paragraph.lineBreakMode = .byTruncatingTail
        (text as NSString).draw(in: rect, withAttributes: [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: paragraph
        ])
    }
}

private struct PDFPreviewItem: Identifiable {
    let id = UUID()
    let url: URL
}

private struct PDFPreviewSheet: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> QLPreviewController {
        let controller = QLPreviewController()
        controller.dataSource = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: QLPreviewController, context: Context) {
        context.coordinator.url = url
        uiViewController.reloadData()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(url: url)
    }

    final class Coordinator: NSObject, QLPreviewControllerDataSource {
        var url: URL

        init(url: URL) {
            self.url = url
        }

        func numberOfPreviewItems(in controller: QLPreviewController) -> Int {
            1
        }

        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
            url as NSURL
        }
    }
}

private struct VisitSummaryTextBuilder {
    func build(
        medications: [StoredMedication],
        tasks: [StoredDoseTask],
        riskCards: [StoredRiskCard],
        startDate: Date,
        endDate: Date,
        generatedAt: Date
    ) -> String {
        var lines: [String] = []
        lines.append("复诊沟通摘要")
        lines.append("")
        lines.append("日期范围：\(VisitSummaryDateRange.displayText(startDate: startDate, endDate: endDate))")
        lines.append("生成时间：\(AppFormatters.day.string(from: generatedAt)) \(AppFormatters.time.string(from: generatedAt))")
        lines.append("")

        let takenTotal = tasks.filter { $0.status == .taken || $0.status == .corrected }.count
        let skippedTotal = tasks.filter { $0.status == .skipped }.count
        let delayedTotal = tasks.filter { $0.status == .delayed }.count
        let medicationCount = Set(tasks.map(\.medicationID)).count
        let completionRate = tasks.isEmpty ? 0 : Int((Double(takenTotal) / Double(tasks.count) * 100).rounded())
        lines.append("摘要：期间记录 \(medicationCount) 种药物，应服 \(tasks.count) 次，已服用 \(takenTotal) 次，忽略 \(skippedTotal) 次，稍后 \(delayedTotal) 次，记录服用率 \(completionRate)%。")
        lines.append("")

        if medications.isEmpty {
            lines.append("用药记录")
            lines.append("暂无药品记录。")
        } else {
            lines.append("用药记录")
            for medication in medications {
                let relatedTasks = tasks.filter { $0.medicationID == medication.id }
                guard !relatedTasks.isEmpty else { continue }
                let takenCount = relatedTasks.filter { $0.status == .taken || $0.status == .corrected }.count
                let skippedCount = relatedTasks.filter { $0.status == .skipped }.count
                let delayedCount = relatedTasks.filter { $0.status == .delayed }.count
                let rate = Int((Double(takenCount) / Double(max(relatedTasks.count, 1)) * 100).rounded())
                lines.append("\(userFacingMedicationName(for: medication))：计划 \(relatedTasks.count) 次，完成 \(takenCount) 次，完成率 \(rate)%，忽略 \(skippedCount) 次，稍后 \(delayedCount) 次。")
                let exceptionNotes = relatedTasks
                    .filter { $0.status == .skipped || $0.status == .delayed }
                    .prefix(3)
                    .map { task in
                        "\(AppFormatters.day.string(from: task.effectiveAdherenceDate)) \(task.status == .skipped ? "忽略" : "稍后")"
                    }
                if !exceptionNotes.isEmpty {
                    lines.append("需沟通节点：\(exceptionNotes.joined(separator: "；"))。")
                }
            }
        }

        lines.append("")
        lines.append("所选时间段记录")
        let calendar = Calendar.current
        let recentTasks = tasks
            .filter { $0.effectiveAdherenceDate >= startDate && $0.effectiveAdherenceDate <= endDate }
            .sorted { $0.effectiveAdherenceDate < $1.effectiveAdherenceDate }
        let groupedByWeek = Dictionary(grouping: recentTasks) { task -> Date in
            let interval = calendar.dateInterval(of: .weekOfYear, for: task.effectiveAdherenceDate)
            return interval?.start ?? calendar.startOfDay(for: task.effectiveAdherenceDate)
        }
        for weekStart in groupedByWeek.keys.sorted() {
            let weekTasks = groupedByWeek[weekStart] ?? []
            let takenCount = weekTasks.filter { $0.status == .taken || $0.status == .corrected }.count
            let delayedCount = weekTasks.filter { $0.status == .delayed }.count
            let skipped = weekTasks.filter { $0.status == .skipped }
            lines.append("\(AppFormatters.day.string(from: weekStart)) 周：计划 \(weekTasks.count) 次，完成 \(takenCount) 次，稍后 \(delayedCount) 次，忽略 \(skipped.count) 次。")
            let exceptions = weekTasks
                .filter { $0.status == .skipped || $0.status == .delayed }
                .prefix(8)
            for task in exceptions {
                let medicationName = medications.first { $0.id == task.medicationID }.map(userFacingMedicationName(for:)) ?? "未知药品"
                let action = task.status == .skipped ? "忽略" : "稍后"
                let displayDate = task.effectiveAdherenceDate
                lines.append("- \(AppFormatters.day.string(from: displayDate)) \(AppFormatters.time.string(from: displayDate))：\(medicationName) \(action)。")
            }
        }

        lines.append("")
        lines.append("风险提示")
        let importantRiskCards = riskCards.filter { $0.requiresProfessionalReview && $0.isActive }.prefix(6)
        if importantRiskCards.isEmpty {
            lines.append("暂无需要优先沟通的风险提醒。")
        } else {
            for card in importantRiskCards {
                let medicationName = medications.first { $0.id == card.medicationID }.map(userFacingMedicationName(for:)) ?? "未知药品"
                lines.append("\(medicationName)：\(summaryRiskDisplayTitle(for: card, limit: 48))。\(summaryRiskFocusText(for: card))")
            }
        }

        return lines.joined(separator: "\n")
    }

    private func summaryRiskFocusText(for card: StoredRiskCard) -> String {
        if let focus = summaryRiskConcreteFocusText(for: card, limit: 96) {
            return focus
        }
        let message = summaryTrimmedText(card.message, limit: 96)
        return message.isEmpty ? "需补充说明书或向医生或药师确认具体对象。" : message
    }

    private func summaryRiskDisplayTitle(for card: StoredRiskCard, limit: Int) -> String {
        let rawTitle = summaryTrimmedText(card.title, limit: limit)
        guard summaryIsGenericRiskFocus(rawTitle) || rawTitle == "警示信息" || rawTitle == "注意事项" else {
            return rawTitle.isEmpty ? summaryRiskCategoryTitle(for: card) : rawTitle
        }
        let category = summaryIsContraindicationRisk(card) ? "禁忌或慎用" : summaryRiskCategoryTitle(for: card)
        guard let focus = summaryRiskConcreteFocusText(for: card, limit: limit),
              !focus.isEmpty
        else {
            return category
        }
        return summaryTrimmedText("\(category)：\(summaryRiskShareFocusText(focus))", limit: limit)
    }

    private func summaryRiskConcreteFocusText(for card: StoredRiskCard, limit: Int) -> String? {
        let focus = summaryExtractedRiskFocus(from: card, limit: limit)
        switch RiskAssessmentCardKind(rawValue: card.kindRaw) ?? .labelRisk {
        case .foodReview:
            return focus.isEmpty ? "需核对具体饮食或生活方式。" : "核对饮食或生活方式：\(focus)"
        case .healthConditionReview:
            return focus.isEmpty ? "需核对具体病症或症状。" : "核对病症或症状：\(focus)"
        case .medicationSourceReview:
            return focus.isEmpty ? "需按药盒、说明书或医嘱核对来源。" : "核对来源：\(focus)"
        case .drugClassContext:
            return focus.isEmpty ? nil : "药品类别：\(focus)"
        case .labelRisk:
            let group = RiskReviewGrouper().mappedGroup(for: card.coreRiskCard)
            if summaryIsContraindicationRisk(card) {
                return focus.isEmpty ? "需核对禁忌条件，当前资料未写明具体对象。" : "核对禁忌条件：\(focus)"
            }
            switch group {
            case .drugInteraction:
                return focus.isEmpty ? "需核对合用药品，当前资料未写明具体名称。" : "核对合用药品：\(focus)"
            case .foodAndLifestyleInteraction:
                return focus.isEmpty ? "需核对具体饮食或生活方式。" : "核对饮食或生活方式：\(focus)"
            case .conditionAndSymptomAttention:
                return focus.isEmpty ? "需核对具体病症或症状。" : "核对病症或症状：\(focus)"
            }
        }
    }

    private func summaryExtractedRiskFocus(from card: StoredRiskCard, limit: Int) -> String {
        let titleFocus = summaryRiskFocusFromReviewTitle(card.title, limit: limit)
        if !titleFocus.isEmpty {
            return titleFocus
        }
        let sourceExcerpt = summaryTrimmedText(card.sourceExcerpt, limit: limit)
        if !sourceExcerpt.isEmpty {
            return sourceExcerpt
        }
        let message = summaryTrimmedText(card.message, limit: limit)
        return summaryIsGenericRiskFocus(message) ? "" : message
    }

    private func summaryRiskFocusFromReviewTitle(_ title: String, limit: Int) -> String {
        guard let separatorIndex = title.firstIndex(of: "：") ?? title.firstIndex(of: ":") else {
            return ""
        }
        return summaryTrimmedText(String(title[title.index(after: separatorIndex)...]), limit: limit)
    }

    private func summaryRiskShareFocusText(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("需核对") else {
            return trimmed
        }
        return String(trimmed.dropFirst("需核对".count))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func summaryRiskCategoryTitle(for card: StoredRiskCard) -> String {
        switch RiskAssessmentCardKind(rawValue: card.kindRaw) ?? .labelRisk {
        case .foodReview:
            return "饮食注意"
        case .healthConditionReview:
            return "病症注意"
        case .medicationSourceReview:
            return "来源核对"
        case .drugClassContext:
            return "类别信息"
        case .labelRisk:
            switch RiskReviewGrouper().mappedGroup(for: card.coreRiskCard) {
            case .drugInteraction:
                return "相互作用"
            case .foodAndLifestyleInteraction:
                return "饮食注意"
            case .conditionAndSymptomAttention:
                return "病症注意"
            }
        }
    }

    private func summaryTrimmedText(_ text: String, limit: Int) -> String {
        let normalized = text
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "说明书“", with: "")
            .replacingOccurrences(of: "”指出：", with: "：")
            .replacingOccurrences(of: "请咨询医生或药师", with: "")
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalized.count > limit else {
            return normalized
        }
        let index = normalized.index(normalized.startIndex, offsetBy: limit)
        return String(normalized[..<index]) + "..."
    }

    private func summaryIsContraindicationRisk(_ card: StoredRiskCard) -> Bool {
        let text = summaryNormalizedRiskText("\(card.title) \(card.message) \(card.sourceTitle) \(card.sourceExcerpt)")
        return text.contains("禁忌")
            || text.contains("禁用")
            || text.contains("contraindication")
            || text.contains("contraindicated")
            || text.contains("avoid")
    }

    private func summaryIsGenericRiskFocus(_ text: String) -> Bool {
        let normalizedText = summaryNormalizedRiskText(text)
        return normalizedText.isEmpty
            || normalizedText == "相关风险"
            || normalizedText == "相关警示"
            || normalizedText == "相关提醒"
            || normalizedText.contains("已根据药品资料和用户记录生成用药风险提醒")
    }

    private func summaryNormalizedRiskText(_ value: String) -> String {
        value
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
            .lowercased()
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .trimmingCharacters(in: .punctuationCharacters)
    }
}
