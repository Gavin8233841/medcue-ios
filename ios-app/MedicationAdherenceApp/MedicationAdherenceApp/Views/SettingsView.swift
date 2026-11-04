import AuthenticationServices
import MedicationAdherenceCore
import OSLog
import QuickLook
import SwiftData
import SwiftUI
import UIKit
import UserNotifications

struct ProfileView: View {
    @Environment(\.activeAppTab) private var activeAppTab
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
                    WeatherMedicationSettingsView()
                } label: {
                    ProfileActionRow(iconName: "cloud.sun.fill", tint: .cyan,
                        title: "天气与用药关注", subtitle: "结合环境查看日常关注", trailingText: nil)
                }
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
            if isActiveTab {
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
           isActiveTab {
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
    static var empty: ProfileSnapshot {
        ProfileSnapshot(tasks: [], now: Date(timeIntervalSinceReferenceDate: 0))
    }

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

private struct WeatherMedicationSettingsView: View {
    @Query(sort: \StoredMedication.displayName) private var medications: [StoredMedication]
    @StateObject private var service = WeatherMedicationService()
    @State private var pendingPermissionGate: AppPermissionGate?

    var body: some View {
        List {
            Section {
                if service.isLoading && service.hints.isEmpty {
                    ProgressView("正在读取环境关注")
                }
                ForEach(service.hints.filter(\.isActionableForToday)) { hint in
                    WeatherMedicationHintCard(hint: hint)
                }
                if !service.statusText.isEmpty {
                    Text(service.statusText).font(.footnote).foregroundStyle(.secondary)
                }
                if service.shouldShowAuthorizationButton {
                    Button("允许天气提醒") { pendingPermissionGate = .location }
                        .disabled(service.isLoading)
                }
            }
        }
        .navigationTitle("天气与用药关注")
        .task { _ = await service.refresh(medications: medications) }
        .appPermissionPrimer(pendingGate: $pendingPermissionGate) { gate in
            guard gate == .location else { return }
            Task {
                if await service.refresh(medications: medications, requestAuthorization: true) {
                    AppPermissionGate.markAuthorizationCompleted(for: .location)
                }
            }
        }
    }
}

struct SettingsView: View {
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(AppExperienceMode.storageKey) private var experienceMode = AppExperienceMode.complete.rawValue
    @Environment(\.modelContext) private var modelContext
    @AppStorage("appColorSchemePreference") private var appColorSchemePreference = AppColorSchemePreference.system.rawValue
    @AppStorage("prefersReducedAppMotion") private var prefersReducedAppMotion = false
    @AppStorage("showsMedicationPhotosInReminders") private var showsMedicationPhotosInReminders = true
    @AppStorage("usesLargeTouchTargets") private var usesLargeTouchTargets = true
    @AppStorage(NotificationService.reminderNotificationUnavailableMessageKey) private var reminderNotificationUnavailableMessage = ""
    @StateObject private var notificationService = NotificationService()
    @State private var pendingPermissionGate: AppPermissionGate?
    @State private var isUpdatingNotificationPermission = false
    @State private var notificationPermissionIsUndetermined = false
    @State private var pendingExperienceMode: AppExperienceMode?

    var body: some View {
        List {
            Section("使用模式") {
                Picker("使用模式", selection: Binding(
                    get: { experienceMode },
                    set: { if $0 != experienceMode { pendingExperienceMode = AppExperienceMode(rawValue: $0) } }
                )) {
                    ForEach(AppExperienceMode.allCases) { mode in
                        Text(mode.displayName).tag(mode.rawValue)
                    }
                }.accessibilityIdentifier("settings.experience-mode")
            }

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
                    if notificationPermissionIsUndetermined {
                        startNotificationPermissionFlow()
                    } else {
                        openSystemSettings()
                    }
                } label: {
                    Text(notificationPermissionIsUndetermined ? "开启通知" : "管理通知设置")
                }
                .disabled(isUpdatingNotificationPermission)
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
        .alert("切换使用模式？", isPresented: Binding(
            get: { pendingExperienceMode != nil },
            set: { if !$0 { pendingExperienceMode = nil } }
        )) {
            Button("取消", role: .cancel) { pendingExperienceMode = nil }
            Button("确认切换") {
                if let mode = pendingExperienceMode { experienceMode = mode.rawValue }
                pendingExperienceMode = nil
            }
        } message: {
            Text(pendingExperienceMode == .elder ? "进入适老模式，一次处理一项用药任务。" : "返回完整模式，查看全部功能。")
        }
        .appPermissionPrimer(pendingGate: $pendingPermissionGate) { gate in
            guard gate == .notifications else {
                return
            }
            Task {
                await requestNotificationPermissionAndRefresh()
            }
        }
        .task {
            await refreshNotificationSettings()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await refreshNotificationSettings() } }
        }
    }

    private func refreshNotificationSettings() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        notificationPermissionIsUndetermined = settings.authorizationStatus == .notDetermined
        await notificationService.refreshAuthorizationStatus()
        await notificationService.refreshPendingReminderCount()
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
        await refreshNotificationSettings()
        guard granted else {
            return
        }
        AppPermissionGate.markAuthorizationCompleted(for: .notifications)
        await notificationService.refreshPendingReminderCount()
    }

    private func openSystemSettings() {
        guard let url = URL(string: UIApplication.openNotificationSettingsURLString) else {
            return
        }
        UIApplication.shared.open(url)
    }
}
