import Foundation
import SwiftUI
import UserNotifications
import WatchConnectivity
import WidgetKit

@main
struct MedicationAdherenceWatchApp: App {
    @StateObject private var snapshotCenter = MedicationWatchSnapshotCenter()

    var body: some Scene {
        WindowGroup {
            WatchTodayView()
                .environmentObject(snapshotCenter)
        }
    }
}

@MainActor
final class MedicationWatchSnapshotCenter: NSObject, ObservableObject, WCSessionDelegate {
    @Published private(set) var snapshot: MedicationWatchSnapshot = MedicationWatchSnapshotCenter.initialSnapshot()
    @Published private(set) var reminderSummary: MedicationWatchReminderSummary = .idle
    @Published private(set) var isReminderAuthorizationRequestInFlight = false

    private let reminderScheduler = MedicationWatchReminderScheduler()
    private var lastReminderRefreshKey: String?
    private var reminderRefreshTask: Task<Void, Never>?
    private var reminderRefreshID: UUID?

    override init() {
        super.init()
        activateSession()
        refreshReminders(for: snapshot)
    }

    func reloadLocalSnapshot() {
        let localSnapshot = Self.initialSnapshot()
        snapshot = localSnapshot
        refreshReminders(for: localSnapshot)
    }

    func enableReminders() {
        guard !isReminderAuthorizationRequestInFlight else {
            return
        }
        let now = Date()
        isReminderAuthorizationRequestInFlight = true
        lastReminderRefreshKey = Self.reminderRefreshKey(for: snapshot, now: now)
        beginReminderRefresh { [self, snapshot] in
            await self.reminderScheduler.enableReminders(for: snapshot, now: now)
        } completion: { [self] summary in
            self.reminderSummary = summary
            self.isReminderAuthorizationRequestInFlight = false
        }
    }

    func reminderTimelineRefreshKey(now: Date) -> String {
        Self.reminderRefreshKey(for: snapshot, now: now)
    }

    func refreshRemindersIfNeeded(now: Date) {
        let refreshKey = Self.reminderRefreshKey(for: snapshot, now: now)
        guard refreshKey != lastReminderRefreshKey else {
            return
        }
        refreshReminders(for: snapshot, now: now)
    }

    private static func initialSnapshot() -> MedicationWatchSnapshot {
        if usesFirstSyncPreviewSnapshot {
            return .empty
        }
        if usesEmptyPlanPreviewSnapshot {
            return .previewEmptyPlan
        }
        if usesStalePlanPreviewSnapshot {
            return .previewStalePlan
        }
        if usesPrivacyPreviewSnapshot {
            return .previewPrivacy
        }
        if usesLongDayPreviewSnapshot {
            return .previewLongDay
        }
        if usesOverdueOnlyPreviewSnapshot {
            return .previewOverdueOnly
        }
        if usesStandardPreviewSnapshot {
            return .preview
        }
        return MedicationWatchSnapshotStore.load()
    }

    private static var usesStandardPreviewSnapshot: Bool {
        #if DEBUG
        return ProcessInfo.processInfo.arguments.contains("--watch-preview-snapshot")
        #else
        return false
        #endif
    }

    private static var usesFirstSyncPreviewSnapshot: Bool {
        #if DEBUG
        return ProcessInfo.processInfo.arguments.contains("--watch-preview-first-sync")
        #else
        return false
        #endif
    }

    private static var usesEmptyPlanPreviewSnapshot: Bool {
        #if DEBUG
        return ProcessInfo.processInfo.arguments.contains("--watch-preview-empty-plan")
        #else
        return false
        #endif
    }

    private static var usesStalePlanPreviewSnapshot: Bool {
        #if DEBUG
        return ProcessInfo.processInfo.arguments.contains("--watch-preview-stale-plan")
        #else
        return false
        #endif
    }

    private static var usesPrivacyPreviewSnapshot: Bool {
        #if DEBUG
        return ProcessInfo.processInfo.arguments.contains("--watch-preview-privacy")
        #else
        return false
        #endif
    }

    private static var usesOverdueOnlyPreviewSnapshot: Bool {
        #if DEBUG
        return ProcessInfo.processInfo.arguments.contains("--watch-preview-overdue-only")
        #else
        return false
        #endif
    }

    private static var usesLongDayPreviewSnapshot: Bool {
        #if DEBUG
        return ProcessInfo.processInfo.arguments.contains("--watch-preview-long-day")
        #else
        return false
        #endif
    }

    private func activateSession() {
        guard WCSession.isSupported() else {
            return
        }
        let session = WCSession.default
        session.delegate = self
        session.activate()
    }

    private func applySnapshot(_ nextSnapshot: MedicationWatchSnapshot) {
        MedicationWatchSnapshotStore.save(nextSnapshot)
        WidgetCenter.shared.reloadAllTimelines()
        snapshot = nextSnapshot
        refreshReminders(for: nextSnapshot)
    }

    private func refreshReminders(for snapshot: MedicationWatchSnapshot, now: Date = Date()) {
        lastReminderRefreshKey = Self.reminderRefreshKey(for: snapshot, now: now)
        beginReminderRefresh { [self, snapshot] in
            await self.reminderScheduler.refresh(for: snapshot, now: now)
        } completion: { [self] summary in
            self.reminderSummary = summary
        }
    }

    private func beginReminderRefresh(
        operation: @escaping @MainActor () async -> MedicationWatchReminderSummary,
        completion: @escaping @MainActor (MedicationWatchReminderSummary) -> Void
    ) {
        reminderRefreshTask?.cancel()
        let refreshID = UUID()
        reminderRefreshID = refreshID
        reminderRefreshTask = Task { @MainActor [weak self] in
            let summary = await operation()
            guard !Task.isCancelled, self?.reminderRefreshID == refreshID else { return }
            completion(summary)
            self?.reminderRefreshID = nil
            self?.reminderRefreshTask = nil
        }
    }

    private static func reminderRefreshKey(
        for snapshot: MedicationWatchSnapshot,
        now: Date,
        calendar: Calendar = .current
    ) -> String {
        let dayKey = String(Int(calendar.startOfDay(for: now).timeIntervalSince1970))
        let generatedAtKey = String(Int(snapshot.generatedAt.timeIntervalSince1970))

        if snapshot.requiresRefresh(now: now, calendar: calendar) {
            return ["stale", dayKey, generatedAtKey].joined(separator: "|")
        }

        if snapshot.isAwaitingFirstSync {
            return ["first-sync", dayKey].joined(separator: "|")
        }

        let openItems = snapshot.displayOpenItems(now: now, calendar: calendar)
        let futureItemsKey = openItems
            .filter { $0.dueAt > now }
            .prefix(12)
            .map { item in
                [
                    item.id.uuidString,
                    String(Int(item.dueAt.timeIntervalSince1970)),
                    item.status.rawValue
                ].joined(separator: ":")
            }
            .joined(separator: ",")

        return [
            "fresh",
            dayKey,
            generatedAtKey,
            snapshot.privacyMode ? "private" : "visible",
            "open:\(openItems.count)",
            "future:\(futureItemsKey)"
        ].joined(separator: "|")
    }

    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        Task { @MainActor [weak self] in
            self?.reloadLocalSnapshot()
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        applyPayloadData(applicationContext["snapshot"] as? Data)
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        applyPayloadData(message["snapshot"] as? Data)
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        applyPayloadData(userInfo["snapshot"] as? Data)
    }

    nonisolated private func applyPayloadData(_ data: Data?) {
        guard let data,
              let nextSnapshot = try? JSONDecoder().decode(MedicationWatchSnapshot.self, from: data) else {
            return
        }
        Task { @MainActor [weak self] in
            self?.applySnapshot(nextSnapshot)
        }
    }

    #if os(iOS)
    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        Task { @MainActor in
            WCSession.default.activate()
        }
    }
    #endif
}

struct MedicationWatchReminderSummary: Equatable {
    var title: String
    var detail: String
    var scheduledCount: Int
    var symbolName: String
    var isAttentionNeeded: Bool
    var canRequestAuthorization: Bool
    var relativeDate: Date? = nil
    var relativeDateSuffix: String? = nil

    func detailText(now: Date) -> String {
        guard let relativeDate, let relativeDateSuffix else {
            return detail
        }
        return "\(MedicationWatchSnapshotFormatters.relativeDateString(for: relativeDate, relativeTo: now))\(relativeDateSuffix)"
    }

    static let idle = MedicationWatchReminderSummary(
        title: "提醒待同步",
        detail: "手机刷新",
        scheduledCount: 0,
        symbolName: "bell",
        isAttentionNeeded: false,
        canRequestAuthorization: false
    )

    static let refreshRequired = MedicationWatchReminderSummary(
        title: "计划需刷新",
        detail: "手机更新",
        scheduledCount: 0,
        symbolName: "clock.badge.exclamationmark",
        isAttentionNeeded: true,
        canRequestAuthorization: false
    )

    static let noUpcoming = MedicationWatchReminderSummary(
        title: "无需提醒",
        detail: "没有未来待服",
        scheduledCount: 0,
        symbolName: "bell.slash",
        isAttentionNeeded: false,
        canRequestAuthorization: false
    )

    static func overdueOnly(count: Int) -> MedicationWatchReminderSummary {
        MedicationWatchReminderSummary(
            title: "先处理到点项",
            detail: "\(count) 项已到点",
            scheduledCount: 0,
            symbolName: "clock.badge.exclamationmark",
            isAttentionNeeded: true,
            canRequestAuthorization: false
        )
    }

    static func scheduled(count: Int, nextDate: Date?) -> MedicationWatchReminderSummary {
        let detail: String
        if nextDate != nil {
            detail = "下一项已安排"
        } else {
            detail = "已安排今日提醒"
        }
        return MedicationWatchReminderSummary(
            title: "\(count) 条提醒",
            detail: detail,
            scheduledCount: count,
            symbolName: "bell.badge",
            isAttentionNeeded: false,
            canRequestAuthorization: false,
            relativeDate: nextDate,
            relativeDateSuffix: nextDate == nil ? nil : "提醒"
        )
    }

    static func authorizationRequired(count: Int, nextDate: Date?) -> MedicationWatchReminderSummary {
        let detail: String
        if nextDate != nil {
            detail = "下一项可提醒"
        } else {
            detail = "\(count) 项待提醒"
        }
        return MedicationWatchReminderSummary(
            title: "开启手表提醒",
            detail: detail,
            scheduledCount: 0,
            symbolName: "bell.badge",
            isAttentionNeeded: false,
            canRequestAuthorization: true,
            relativeDate: nextDate,
            relativeDateSuffix: nextDate == nil ? nil : "可提醒"
        )
    }

    static let denied = MedicationWatchReminderSummary(
        title: "提醒未开启",
        detail: "在设置中允许通知",
        scheduledCount: 0,
        symbolName: "bell.badge.slash",
        isAttentionNeeded: true,
        canRequestAuthorization: false
    )

    static func schedulingFailed(count: Int) -> MedicationWatchReminderSummary {
        MedicationWatchReminderSummary(
            title: "提醒未安排",
            detail: "\(count) 项待重试",
            scheduledCount: 0,
            symbolName: "exclamationmark.triangle",
            isAttentionNeeded: true,
            canRequestAuthorization: false
        )
    }
}

@MainActor
private final class MedicationWatchReminderScheduler {
    private let notificationCenter = UNUserNotificationCenter.current()
    private let identifierPrefix = "MedicationWatchDoseReminder."
    private var lastScheduleKey: String?

    func refresh(
        for snapshot: MedicationWatchSnapshot,
        now: Date = Date()
    ) async -> MedicationWatchReminderSummary {
        await refresh(
            for: snapshot,
            now: now,
            shouldRequestAuthorization: false
        )
    }

    func enableReminders(
        for snapshot: MedicationWatchSnapshot,
        now: Date = Date()
    ) async -> MedicationWatchReminderSummary {
        await refresh(
            for: snapshot,
            now: now,
            shouldRequestAuthorization: true
        )
    }

    private func refresh(
        for snapshot: MedicationWatchSnapshot,
        now: Date,
        shouldRequestAuthorization: Bool
    ) async -> MedicationWatchReminderSummary {
        if snapshot.requiresRefresh(now: now) {
            lastScheduleKey = nil
            await removeScheduledReminders()
            return .refreshRequired
        }

        let upcomingItems = futureReminderItems(in: snapshot, now: now)
        let displayOpenItems = snapshot.displayOpenItems(now: now)
        guard !upcomingItems.isEmpty else {
            lastScheduleKey = nil
            await removeScheduledReminders()
            if snapshot.isAwaitingFirstSync {
                return .idle
            }
            if displayOpenItems.isEmpty {
                return .noUpcoming
            }
            return .overdueOnly(count: displayOpenItems.count)
        }

        #if DEBUG
        if Self.usesReminderFailurePreview {
            lastScheduleKey = nil
            await removeScheduledReminders()
            return .schedulingFailed(count: min(upcomingItems.count, 1))
        }
        #endif

        let settings = await notificationCenter.notificationSettings()
        switch settings.authorizationStatus {
        case .notDetermined:
            guard shouldRequestAuthorization else {
                return .authorizationRequired(
                    count: upcomingItems.count,
                    nextDate: upcomingItems.first?.dueAt
                )
            }
            let granted = (try? await notificationCenter.requestAuthorization(options: [.alert, .sound])) == true
            guard granted else {
                lastScheduleKey = nil
                await removeScheduledReminders()
                return .denied
            }
            return await replaceScheduledReminders(
                with: upcomingItems,
                privacyMode: snapshot.privacyMode
            )
        case .authorized, .provisional:
            return await replaceScheduledReminders(
                with: upcomingItems,
                privacyMode: snapshot.privacyMode
            )
        case .denied:
            lastScheduleKey = nil
            await removeScheduledReminders()
            return .denied
        @unknown default:
            lastScheduleKey = nil
            await removeScheduledReminders()
            return .denied
        }
    }

    private func replaceScheduledReminders(
        with upcomingItems: [MedicationWatchDoseItem],
        privacyMode: Bool
    ) async -> MedicationWatchReminderSummary {
        let scheduleKey = makeScheduleKey(for: upcomingItems, privacyMode: privacyMode)
        if scheduleKey == lastScheduleKey {
            return .scheduled(count: upcomingItems.count, nextDate: upcomingItems.first?.dueAt)
        }

        let requests = await notificationCenter.pendingNotificationRequests()
        let existingReminderIDs = requests
            .map(\.identifier)
            .filter { $0.hasPrefix(identifierPrefix) }
        if !existingReminderIDs.isEmpty {
            notificationCenter.removePendingNotificationRequests(withIdentifiers: existingReminderIDs)
        }

        var failedCount = 0
        for item in upcomingItems {
            do {
                try await notificationCenter.add(makeRequest(for: item, privacyMode: privacyMode))
            } catch {
                failedCount += 1
            }
        }
        guard failedCount == 0 else {
            lastScheduleKey = nil
            return .schedulingFailed(count: failedCount)
        }

        lastScheduleKey = scheduleKey
        return .scheduled(count: upcomingItems.count, nextDate: upcomingItems.first?.dueAt)
    }

    private func removeScheduledReminders() async {
        let requests = await notificationCenter.pendingNotificationRequests()
        let reminderIDs = requests
            .map(\.identifier)
            .filter { $0.hasPrefix(identifierPrefix) }
        if !reminderIDs.isEmpty {
            notificationCenter.removePendingNotificationRequests(withIdentifiers: reminderIDs)
        }
    }

    private func makeRequest(
        for item: MedicationWatchDoseItem,
        privacyMode: Bool
    ) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = privacyMode ? "用药提醒" : item.medicationName
        content.body = privacyMode ? "现在该处理一项今日用药。" : "\(item.doseText) · \(item.status.displayText)"
        content.sound = .default

        let calendar = Calendar.current
        let dateComponents = calendar.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: item.dueAt
        )
        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: false)
        return UNNotificationRequest(
            identifier: "\(identifierPrefix)\(item.id.uuidString)",
            content: content,
            trigger: trigger
        )
    }

    private func futureReminderItems(
        in snapshot: MedicationWatchSnapshot,
        now: Date
    ) -> [MedicationWatchDoseItem] {
        Array(snapshot.displayOpenItems(now: now).filter { $0.dueAt > now }.prefix(12))
    }

    private func makeScheduleKey(
        for items: [MedicationWatchDoseItem],
        privacyMode: Bool
    ) -> String {
        items
            .map { item in
                [
                    item.id.uuidString,
                    String(item.dueAt.timeIntervalSince1970),
                    item.status.rawValue,
                    privacyMode ? "private" : "visible"
                ].joined(separator: "|")
            }
            .joined(separator: "#")
    }

    private static var usesReminderFailurePreview: Bool {
        #if DEBUG
        return ProcessInfo.processInfo.arguments.contains("--watch-preview-reminder-failure")
        #else
        return false
        #endif
    }
}
