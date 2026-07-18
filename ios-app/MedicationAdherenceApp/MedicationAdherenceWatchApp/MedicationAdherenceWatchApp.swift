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

final class MedicationWatchSnapshotCenter: NSObject, ObservableObject, WCSessionDelegate {
    @Published private(set) var snapshot: MedicationWatchSnapshot = MedicationWatchSnapshotCenter.initialSnapshot()
    @Published private(set) var reminderSummary: MedicationWatchReminderSummary = .idle
    @Published private(set) var isReminderAuthorizationRequestInFlight = false

    private let reminderScheduler = MedicationWatchReminderScheduler()
    private var lastReminderRefreshKey: String?

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
        reminderScheduler.enableReminders(for: snapshot, now: now) { [weak self] summary in
            DispatchQueue.main.async {
                self?.reminderSummary = summary
                self?.isReminderAuthorizationRequestInFlight = false
            }
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

    private func applyPayload(_ payload: [String: Any]) {
        guard let data = payload["snapshot"] as? Data,
              let nextSnapshot = try? JSONDecoder().decode(MedicationWatchSnapshot.self, from: data)
        else {
            return
        }
        MedicationWatchSnapshotStore.save(nextSnapshot)
        WidgetCenter.shared.reloadAllTimelines()
        refreshReminders(for: nextSnapshot)
        DispatchQueue.main.async {
            self.snapshot = nextSnapshot
        }
    }

    private func refreshReminders(for snapshot: MedicationWatchSnapshot, now: Date = Date()) {
        lastReminderRefreshKey = Self.reminderRefreshKey(for: snapshot, now: now)
        reminderScheduler.refresh(for: snapshot, now: now) { [weak self] summary in
            DispatchQueue.main.async {
                self?.reminderSummary = summary
            }
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

    func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        DispatchQueue.main.async {
            self.reloadLocalSnapshot()
        }
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        applyPayload(applicationContext)
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        applyPayload(message)
    }

    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        applyPayload(userInfo)
    }

    #if os(iOS)
    func sessionDidBecomeInactive(_ session: WCSession) {}

    func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
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
        return "\(MedicationWatchSnapshotFormatters.relativeDate.localizedString(for: relativeDate, relativeTo: now))\(relativeDateSuffix)"
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

private final class MedicationWatchReminderScheduler {
    private let notificationCenter = UNUserNotificationCenter.current()
    private let identifierPrefix = "MedicationWatchDoseReminder."
    private var lastScheduleKey: String?

    func refresh(
        for snapshot: MedicationWatchSnapshot,
        now: Date = Date(),
        completion: @escaping (MedicationWatchReminderSummary) -> Void
    ) {
        refresh(for: snapshot, now: now, shouldRequestAuthorization: false, completion: completion)
    }

    func enableReminders(
        for snapshot: MedicationWatchSnapshot,
        now: Date = Date(),
        completion: @escaping (MedicationWatchReminderSummary) -> Void
    ) {
        refresh(for: snapshot, now: now, shouldRequestAuthorization: true, completion: completion)
    }

    private func refresh(
        for snapshot: MedicationWatchSnapshot,
        now: Date,
        shouldRequestAuthorization: Bool,
        completion: @escaping (MedicationWatchReminderSummary) -> Void
    ) {
        if snapshot.requiresRefresh(now: now) {
            lastScheduleKey = nil
            removeScheduledReminders()
            completion(.refreshRequired)
            return
        }

        let upcomingItems = futureReminderItems(in: snapshot, now: now)
        let displayOpenItems = snapshot.displayOpenItems(now: now)
        guard !upcomingItems.isEmpty else {
            lastScheduleKey = nil
            removeScheduledReminders()
            if snapshot.isAwaitingFirstSync {
                completion(.idle)
            } else if displayOpenItems.isEmpty {
                completion(.noUpcoming)
            } else {
                completion(.overdueOnly(count: displayOpenItems.count))
            }
            return
        }

        #if DEBUG
        if Self.usesReminderFailurePreview {
            lastScheduleKey = nil
            removeScheduledReminders()
            completion(.schedulingFailed(count: min(upcomingItems.count, 1)))
            return
        }
        #endif

        notificationCenter.getNotificationSettings { [weak self] settings in
            guard let self else {
                return
            }

            switch settings.authorizationStatus {
            case .notDetermined:
                guard shouldRequestAuthorization else {
                    completion(.authorizationRequired(count: upcomingItems.count, nextDate: upcomingItems.first?.dueAt))
                    return
                }
                self.requestAuthorizationAndSchedule(
                    upcomingItems,
                    privacyMode: snapshot.privacyMode,
                    completion: completion
                )
            case .authorized, .provisional:
                self.replaceScheduledReminders(
                    with: upcomingItems,
                    privacyMode: snapshot.privacyMode,
                    completion: completion
                )
            case .denied:
                self.lastScheduleKey = nil
                self.removeScheduledReminders()
                completion(.denied)
            @unknown default:
                self.lastScheduleKey = nil
                self.removeScheduledReminders()
                completion(.denied)
            }
        }
    }

    private func requestAuthorizationAndSchedule(
        _ upcomingItems: [MedicationWatchDoseItem],
        privacyMode: Bool,
        completion: @escaping (MedicationWatchReminderSummary) -> Void
    ) {
        notificationCenter.requestAuthorization(options: [.alert, .sound]) { [weak self] granted, _ in
            guard let self else {
                return
            }
            if granted {
                self.replaceScheduledReminders(
                    with: upcomingItems,
                    privacyMode: privacyMode,
                    completion: completion
                )
            } else {
                self.lastScheduleKey = nil
                self.removeScheduledReminders()
                completion(.denied)
            }
        }
    }

    private func replaceScheduledReminders(
        with upcomingItems: [MedicationWatchDoseItem],
        privacyMode: Bool,
        completion: @escaping (MedicationWatchReminderSummary) -> Void
    ) {
        let scheduleKey = makeScheduleKey(for: upcomingItems, privacyMode: privacyMode)
        if scheduleKey == lastScheduleKey {
            completion(.scheduled(count: upcomingItems.count, nextDate: upcomingItems.first?.dueAt))
            return
        }

        notificationCenter.getPendingNotificationRequests { [weak self] requests in
            guard let self else {
                return
            }

            let existingReminderIDs = requests
                .map(\.identifier)
                .filter { $0.hasPrefix(self.identifierPrefix) }
            if !existingReminderIDs.isEmpty {
                self.notificationCenter.removePendingNotificationRequests(withIdentifiers: existingReminderIDs)
            }

            let schedulingGroup = DispatchGroup()
            let failureCounter = MedicationWatchSchedulingFailureCounter()

            for item in upcomingItems {
                schedulingGroup.enter()
                self.notificationCenter.add(
                    self.makeRequest(for: item, privacyMode: privacyMode)
                ) { error in
                    if error != nil {
                        failureCounter.increment()
                    }
                    schedulingGroup.leave()
                }
            }

            schedulingGroup.notify(queue: .main) {
                let failedCount = failureCounter.count
                if failedCount > 0 {
                    self.lastScheduleKey = nil
                    completion(.schedulingFailed(count: failedCount))
                    return
                }

                self.lastScheduleKey = scheduleKey
                completion(.scheduled(count: upcomingItems.count, nextDate: upcomingItems.first?.dueAt))
            }
        }
    }

    private func removeScheduledReminders() {
        notificationCenter.getPendingNotificationRequests { [weak self] requests in
            guard let self else {
                return
            }

            let reminderIDs = requests
                .map(\.identifier)
                .filter { $0.hasPrefix(self.identifierPrefix) }
            if !reminderIDs.isEmpty {
                self.notificationCenter.removePendingNotificationRequests(withIdentifiers: reminderIDs)
            }
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

        let dateComponents = Calendar.current.dateComponents(
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

    private func futureReminderItems(in snapshot: MedicationWatchSnapshot, now: Date) -> [MedicationWatchDoseItem] {
        return Array(snapshot.displayOpenItems(now: now).filter { $0.dueAt > now }.prefix(12))
    }

    private func makeScheduleKey(for items: [MedicationWatchDoseItem], privacyMode: Bool) -> String {
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

private final class MedicationWatchSchedulingFailureCounter {
    private let lock = NSLock()
    private var value = 0

    func increment() {
        lock.lock()
        value += 1
        lock.unlock()
    }

    var count: Int {
        lock.lock()
        let currentValue = value
        lock.unlock()
        return currentValue
    }
}
