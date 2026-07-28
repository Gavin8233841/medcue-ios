import SwiftUI
#if os(watchOS)
import WatchKit
#endif

struct WatchTodayView: View {
    @EnvironmentObject private var snapshotCenter: MedicationWatchSnapshotCenter
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var snapshot: MedicationWatchSnapshot {
        snapshotCenter.snapshot
    }

    var body: some View {
        NavigationStack {
            TimelineView(.periodic(from: Date(), by: 60)) { context in
                let now = context.date
                todayList(now: now)
                    .task(id: snapshotCenter.reminderTimelineRefreshKey(now: now)) {
                        snapshotCenter.refreshRemindersIfNeeded(now: now)
                    }
            }
            .navigationTitle(dynamicTypeSize.isAccessibilitySize ? "" : "今日用药")
            .navigationBarTitleDisplayMode(.inline)
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                snapshotCenter.reloadLocalSnapshot()
            }
        }
    }

    private func todayList(now: Date) -> some View {
        let openItems = snapshot.displayOpenItems(now: now)
        let handledItems = snapshot.displayHandledItems(now: now)

        return List {
            Section {
                WatchNextDoseCard(snapshot: snapshot, now: now)
                    .listRowInsets(EdgeInsets(top: 4, leading: 6, bottom: 6, trailing: 6))
                    .listRowBackground(Color.clear)
            }

            Section {
                WatchSyncReminderCard(
                    snapshot: snapshot,
                    reminderSummary: snapshotCenter.reminderSummary,
                    isRequestingAuthorization: snapshotCenter.isReminderAuthorizationRequestInFlight,
                    now: now,
                    onEnableReminders: snapshotCenter.enableReminders
                )
                    .listRowInsets(EdgeInsets(top: 0, leading: 6, bottom: 6, trailing: 6))
                    .listRowBackground(Color.clear)
            }

            if openItems.isEmpty {
                Section {
                    WatchEmptyStateCard(snapshot: snapshot, now: now)
                        .listRowInsets(EdgeInsets(top: 4, leading: 6, bottom: 4, trailing: 6))
                        .listRowBackground(Color.clear)
                }
            } else {
                Section("待处理 \(openItems.count)") {
                    ForEach(openItems.prefix(6)) { item in
                        WatchDoseRow(item: item, privacyMode: snapshot.privacyMode, now: now)
                    }
                    if openItems.count > 6 {
                        WatchMoreItemsRow(
                            hiddenCount: openItems.count - 6,
                            sectionTitle: "待处理",
                            symbolName: "ellipsis.circle",
                            tint: .blue
                        )
                    }
                }
            }

            if !handledItems.isEmpty {
                Section("已处理 \(handledItems.count)") {
                    ForEach(handledItems.prefix(4)) { item in
                        WatchDoseRow(item: item, privacyMode: snapshot.privacyMode, now: now)
                    }
                    if handledItems.count > 4 {
                        WatchMoreItemsRow(
                            hiddenCount: handledItems.count - 4,
                            sectionTitle: "已处理",
                            symbolName: "checklist",
                            tint: .secondary
                        )
                    }
                }
            }
        }
        .listStyle(.carousel)
        .refreshable {
            snapshotCenter.reloadLocalSnapshot()
        }
    }
}

private struct WatchNextDoseCard: View {
    let snapshot: MedicationWatchSnapshot
    let now: Date
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var progress: Double {
        snapshot.displayCompletionProgress(now: now)
    }

    private var progressText: String {
        if snapshot.requiresRefresh(now: now) {
            return "刷新"
        }
        guard !snapshot.displayItems(now: now).isEmpty else {
            return snapshot.isAwaitingFirstSync ? "同步" : "无计划"
        }
        return "\(Int((progress * 100).rounded()))%"
    }

    private var nextDoseText: String {
        guard let item = snapshot.displayNextOpenItem(now: now) else {
            if snapshot.requiresRefresh(now: now) {
                return "需刷新"
            }
            if snapshot.isAwaitingFirstSync {
                return "待同步"
            }
            return snapshot.displayItems(now: now).isEmpty ? "无计划" : "完成"
        }
        return item.timeText
    }

    var body: some View {
        let metrics = WatchHeroMetrics.current

        VStack(alignment: .leading, spacing: metrics.verticalSpacing) {
            HStack(spacing: metrics.horizontalSpacing) {
                WatchProgressRing(
                    progress: progress,
                    label: progressText,
                    diameter: metrics.ringDiameter,
                    lineWidth: metrics.ringLineWidth
                )

                VStack(alignment: .leading, spacing: metrics.textSpacing) {
                    Text(nextDoseText)
                        .font(.system(size: metrics.timeFontSize, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.55)
                        .allowsTightening(true)

                    if let item = snapshot.displayNextOpenItem(now: now) {
                        Text(snapshot.privacyMode ? "下一次用药" : item.medicationName)
                            .font(.headline.weight(.semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                        HStack(spacing: 4) {
                            Image(systemName: nextDoseBadge.symbolName)
                                .font(.caption2.weight(.bold))
                            Text(
                                snapshot.privacyMode || (metrics.isCompact && dynamicTypeSize.isAccessibilitySize)
                                    ? nextDoseBadge.text
                                    : "\(item.doseText) · \(nextDoseBadge.text)"
                            )
                                .font(.caption2.weight(.semibold))
                                .lineLimit(1)
                                .minimumScaleFactor(0.62)
                                .allowsTightening(true)
                        }
                        .foregroundStyle(.white.opacity(0.82))
                    } else {
                        Text(emptyHeroTitle)
                            .font(.headline.weight(.semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.76)
                        Text(emptyHeroDetail)
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.78))
                            .lineLimit(1)
                    }
                }
            }

            HStack(spacing: metrics.chipSpacing) {
                WatchMetricChip(
                    title: primaryMetric.title,
                    value: primaryMetric.value,
                    symbolName: primaryMetric.symbolName,
                    tint: primaryMetric.tint,
                    metrics: metrics
                )
                WatchMetricChip(
                    title: secondaryMetric.title,
                    value: secondaryMetric.value,
                    symbolName: secondaryMetric.symbolName,
                    tint: secondaryMetric.tint,
                    metrics: metrics
                )
            }
        }
        .padding(metrics.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .foregroundStyle(.white)
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            nextDoseBadge.tint.opacity(0.9),
                            Color.cyan.opacity(0.5),
                            Color.green.opacity(0.3)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    private var nextDoseBadge: WatchDoseBadge {
        guard let item = snapshot.displayNextOpenItem(now: now) else {
            if snapshot.requiresRefresh(now: now) {
                return WatchDoseBadge(text: "需刷新", symbolName: "clock.badge.exclamationmark", tint: .orange)
            }
            if snapshot.isAwaitingFirstSync {
                return WatchDoseBadge(text: "尚未同步", symbolName: "iphone", tint: .blue)
            }
            if snapshot.displayItems(now: now).isEmpty {
                return WatchDoseBadge(text: "无计划", symbolName: "calendar.badge.checkmark", tint: .green)
            }
            return WatchDoseBadge(text: "今日完成", symbolName: "checkmark.circle.fill", tint: .green)
        }

        switch snapshot.timing(for: item, now: now) {
        case .overdue:
            return WatchDoseBadge(text: "已到点", symbolName: "clock.badge.exclamationmark", tint: .orange)
        case .dueSoon:
            return WatchDoseBadge(text: "即将提醒", symbolName: "bell.badge", tint: .purple)
        case .upcoming:
            return WatchDoseBadge(text: item.status.displayText, symbolName: "bell", tint: .blue)
        }
    }

    private var overdueOpenCount: Int {
        snapshot.overdueOpenCount(now: now)
    }

    private var primaryMetric: WatchMetricContent {
        if snapshot.requiresRefresh(now: now) {
            return WatchMetricContent(title: "今日", value: "需刷新", symbolName: "clock.badge.exclamationmark", tint: .orange)
        }
        if snapshot.isAwaitingFirstSync {
            return WatchMetricContent(title: "今日", value: "待同步", symbolName: "iphone", tint: .blue)
        }
        if snapshot.displayItems(now: now).isEmpty {
            return WatchMetricContent(title: "今日", value: "无计划", symbolName: "calendar.badge.checkmark", tint: .green)
        }
        return WatchMetricContent(
            title: "今日",
            value: snapshot.displayCompletionCountText(now: now),
            symbolName: "checkmark.circle.fill",
            tint: .green
        )
    }

    private var secondaryMetric: WatchMetricContent {
        if snapshot.requiresRefresh(now: now) {
            return WatchMetricContent(title: "刷新", value: "手机", symbolName: "arrow.triangle.2.circlepath", tint: .orange)
        }
        if snapshot.isAwaitingFirstSync {
            return WatchMetricContent(title: "同步", value: "打开", symbolName: "iphone", tint: .blue)
        }
        if snapshot.displayItems(now: now).isEmpty {
            return WatchMetricContent(title: "计划", value: "0 项", symbolName: "calendar.badge.checkmark", tint: .green)
        }
        if overdueOpenCount > 0 {
            return WatchMetricContent(
                title: "到点",
                value: "\(overdueOpenCount) 项",
                symbolName: "clock.badge.exclamationmark",
                tint: .orange
            )
        }
        return WatchMetricContent(
            title: "待处理",
            value: "\(snapshot.displayOpenItems(now: now).count) 项",
            symbolName: "clock.fill",
            tint: .cyan
        )
    }

    private var emptyHeroTitle: String {
        if snapshot.requiresRefresh(now: now) {
            return "计划需刷新"
        }
        if snapshot.isAwaitingFirstSync {
            return "等待 iPhone"
        }
        return snapshot.displayItems(now: now).isEmpty ? "今日暂无计划" : "今日暂无待处理"
    }

    private var emptyHeroDetail: String {
        if snapshot.requiresRefresh(now: now) {
            return "手机更新"
        }
        if snapshot.isAwaitingFirstSync {
            return "手机同步"
        }
        return snapshot.displayItems(now: now).isEmpty ? "无需处理" : "保持今日节奏"
    }

    private var accessibilityLabel: String {
        if let item = snapshot.displayNextOpenItem(now: now) {
            let itemText = snapshot.privacyMode ? "下一次用药" : "\(item.medicationName)，\(item.doseText)"
            return "今日用药，\(snapshot.displayCompletionText(now: now))。下一项，\(item.timeText)，\(itemText)，\(nextDoseBadge.text)"
        }
        if snapshot.requiresRefresh(now: now) {
            return "今日用药计划需刷新，请打开手机更新计划"
        }
        if snapshot.isAwaitingFirstSync {
            return "今日用药尚未同步，请打开手机同步"
        }
        if snapshot.displayItems(now: now).isEmpty {
            return "今日暂无用药计划"
        }
        return "今日用药已完成，\(snapshot.displayCompletionText(now: now))"
    }
}

private struct WatchDoseBadge {
    let text: String
    let symbolName: String
    let tint: Color
}

private struct WatchMetricContent {
    let title: String
    let value: String
    let symbolName: String
    let tint: Color
}

private struct WatchHeroMetrics {
    let isCompact: Bool

    static var current: WatchHeroMetrics {
        #if os(watchOS)
        let screenWidth = WKInterfaceDevice.current().screenBounds.width
        #else
        let screenWidth: CGFloat = 198
        #endif
        return WatchHeroMetrics(isCompact: screenWidth <= 180)
    }

    var cardPadding: CGFloat { isCompact ? 10 : 11 }
    var verticalSpacing: CGFloat { isCompact ? 8 : 10 }
    var horizontalSpacing: CGFloat { isCompact ? 7 : 8 }
    var textSpacing: CGFloat { isCompact ? 3 : 4 }
    var chipSpacing: CGFloat { isCompact ? 5 : 6 }
    var ringDiameter: CGFloat { isCompact ? 40 : 44 }
    var ringLineWidth: CGFloat { isCompact ? 4.5 : 5 }
    var timeFontSize: CGFloat { isCompact ? 32 : 36 }
    var chipHorizontalPadding: CGFloat { isCompact ? 5 : 6 }
    var chipVerticalPadding: CGFloat { isCompact ? 5 : 6 }
    var chipCornerRadius: CGFloat { isCompact ? 9 : 10 }
}

private struct WatchProgressRing: View {
    let progress: Double
    let label: String
    let diameter: CGFloat
    let lineWidth: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var clampedProgress: Double {
        min(max(progress, 0), 1)
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(.white.opacity(0.24), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(clampedProgress, clampedProgress == 0 ? 0 : 0.08))
                .stroke(.white, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text(label)
                .font(.caption2.weight(.bold))
                .minimumScaleFactor(0.7)
        }
        .frame(width: diameter, height: diameter)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.22), value: clampedProgress)
        .accessibilityHidden(true)
    }
}

private struct WatchMetricChip: View {
    let title: String
    let value: String
    let symbolName: String
    let tint: Color
    let metrics: WatchHeroMetrics

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: symbolName)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(tint)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.72))
                Text(value)
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.62)
                    .allowsTightening(true)
            }
        }
        .padding(.horizontal, metrics.chipHorizontalPadding)
        .padding(.vertical, metrics.chipVerticalPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.14), in: RoundedRectangle(cornerRadius: metrics.chipCornerRadius, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title)，\(value)")
    }
}

private struct WatchSyncReminderCard: View {
    let snapshot: MedicationWatchSnapshot
    let reminderSummary: MedicationWatchReminderSummary
    let isRequestingAuthorization: Bool
    let now: Date
    let onEnableReminders: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 6) {
                    statusPills
                }

                VStack(spacing: 6) {
                    statusPills
                }
            }

            if reminderSummary.canRequestAuthorization {
                Button(action: onEnableReminders) {
                    Label(
                        isRequestingAuthorization ? "正在开启" : "开启提醒",
                        systemImage: isRequestingAuthorization ? "hourglass" : "bell.badge"
                    )
                    .font(.caption.weight(.bold))
                    .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .tint(.blue)
                .disabled(isRequestingAuthorization)
                .accessibilityHint("为未来待服用药安排手表本地提醒")
            }
        }
        .padding(8)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var statusPills: some View {
        WatchStatusPill(content: syncStatus)
        WatchStatusPill(content: reminderStatus)
    }

    private var syncStatus: WatchStatusContent {
        WatchStatusContent(
            symbolName: syncSymbolName,
            title: syncTitle,
            detail: syncDetail,
            tint: syncTint
        )
    }

    private var reminderStatus: WatchStatusContent {
        WatchStatusContent(
            symbolName: reminderSummary.symbolName,
            title: reminderSummary.title,
            detail: reminderSummary.detailText(now: now),
            tint: reminderTint
        )
    }

    private var syncTitle: String {
        if snapshot.generatedAt.timeIntervalSince1970 == 0 {
            return "尚未同步"
        }
        if isSnapshotFromAnotherDay {
            return "计划需刷新"
        }
        return "计划已同步"
    }

    private var syncDetail: String {
        guard snapshot.generatedAt.timeIntervalSince1970 > 0 else {
            return "手机刷新"
        }
        if isSnapshotFromAnotherDay {
            return "手机更新"
        }
        return MedicationWatchSnapshotFormatters.relativeDateString(
            for: snapshot.generatedAt,
            relativeTo: now
        )
    }

    private var syncSymbolName: String {
        if snapshot.generatedAt.timeIntervalSince1970 == 0 {
            return "iphone"
        }
        if isSnapshotFromAnotherDay {
            return "clock.badge.exclamationmark"
        }
        return "arrow.triangle.2.circlepath"
    }

    private var syncTint: Color {
        if snapshot.generatedAt.timeIntervalSince1970 == 0 {
            return .blue
        }
        if isSnapshotFromAnotherDay {
            return .orange
        }
        return .cyan
    }

    private var reminderTint: Color {
        if reminderSummary.isAttentionNeeded {
            return .orange
        }
        if reminderSummary.canRequestAuthorization {
            return .blue
        }
        return .green
    }

    private var isSnapshotFromAnotherDay: Bool {
        snapshot.generatedAt.timeIntervalSince1970 > 0
            && !Calendar.current.isDate(snapshot.generatedAt, inSameDayAs: now)
    }
}

private struct WatchStatusContent {
    let symbolName: String
    let title: String
    let detail: String
    let tint: Color
}

private struct WatchStatusPill: View {
    let content: WatchStatusContent

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: content.symbolName)
                .font(.caption.weight(.bold))
                .foregroundStyle(content.tint)
                .frame(width: 22, height: 22)
                .background(content.tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 7, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(content.title)
                    .font(.caption.weight(.bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                Text(content.detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(content.title)，\(content.detail)")
    }
}

private struct WatchEmptyStateCard: View {
    let snapshot: MedicationWatchSnapshot
    let now: Date

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbolName)
                .font(.title3.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 34, height: 34)
                .background(tint.opacity(0.14), in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: String {
        if snapshot.requiresRefresh(now: now) {
            return "计划需刷新，请打开手机更新今日计划"
        }
        if snapshot.isAwaitingFirstSync {
            return "等待同步计划，打开手机后出现"
        }
        if snapshot.displayItems(now: now).isEmpty {
            return "今日暂无计划，今天无需处理"
        }
        return "今日待处理已清空，\(snapshot.displayCompletionText(now: now))"
    }

    private var title: String {
        if snapshot.requiresRefresh(now: now) {
            return "计划需刷新"
        }
        if snapshot.isAwaitingFirstSync {
            return "等待同步计划"
        }
        return snapshot.displayItems(now: now).isEmpty ? "今日暂无计划" : "今日待处理已清空"
    }

    private var detail: String {
        if snapshot.requiresRefresh(now: now) {
            return "手机更新"
        }
        if snapshot.isAwaitingFirstSync {
            return "手机同步后出现"
        }
        return snapshot.displayItems(now: now).isEmpty ? "无需处理" : snapshot.displayCompletionText(now: now)
    }

    private var symbolName: String {
        if snapshot.requiresRefresh(now: now) {
            return "clock.badge.exclamationmark"
        }
        if snapshot.isAwaitingFirstSync {
            return "iphone"
        }
        return snapshot.displayItems(now: now).isEmpty ? "calendar.badge.checkmark" : "checkmark.circle.fill"
    }

    private var tint: Color {
        if snapshot.requiresRefresh(now: now) {
            return .orange
        }
        if snapshot.isAwaitingFirstSync {
            return .blue
        }
        return .green
    }
}

private struct WatchDoseRow: View {
    let item: MedicationWatchDoseItem
    let privacyMode: Bool
    let now: Date

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: statusSymbolName)
                .font(.caption.weight(.bold))
                .foregroundStyle(statusTint)
                .frame(width: 24, height: 24)
                .background(statusTint.opacity(0.14), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(item.timeText)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(privacyMode ? "用药提醒" : item.medicationName)
                    .font(.body.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.68)
                    .allowsTightening(true)
                if let detailText {
                    Text(detailText)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.58)
                        .allowsTightening(true)
                }
            }
            Spacer(minLength: 4)
            Text(statusText)
                .font(.caption2.weight(.bold))
                .foregroundStyle(statusTint)
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .background(statusTint.opacity(0.16), in: Capsule())
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    private var statusSymbolName: String {
        if openTiming == .overdue {
            return "clock.badge.exclamationmark"
        }
        switch item.status {
        case .pending:
            return "pills.fill"
        case .delayed:
            return "clock.fill"
        case .taken, .corrected:
            return "checkmark.circle.fill"
        case .skipped:
            return "minus.circle.fill"
        }
    }

    private var statusTint: Color {
        if openTiming == .overdue {
            return .orange
        }
        if openTiming == .dueSoon {
            return .purple
        }
        switch item.status {
        case .pending:
            return .blue
        case .delayed:
            return .orange
        case .taken, .corrected:
            return .green
        case .skipped:
            return .secondary
        }
    }

    private var statusText: String {
        if openTiming == .overdue {
            return usesCompactDetail ? "到点" : "已到点"
        }
        if openTiming == .dueSoon {
            return "即将"
        }
        return item.status.displayText
    }

    private var detailText: String? {
        if privacyMode {
            return relativeTimingText
        }
        guard let relativeTimingText else {
            return item.doseText
        }
        if usesCompactDetail {
            return relativeTimingText
        }
        return "\(item.doseText) · \(relativeTimingText)"
    }

    private var usesCompactDetail: Bool {
        #if os(watchOS)
        return WKInterfaceDevice.current().screenBounds.width <= 180
        #else
        return false
        #endif
    }

    private var relativeTimingText: String? {
        guard item.status.isOpen else {
            return nil
        }
        let seconds = item.dueAt.timeIntervalSince(now)
        let minutes = max(1, Int((abs(seconds) / 60).rounded(.up)))
        if minutes < 60 {
            return seconds < 0 ? "已过 \(minutes) 分钟" : "\(minutes) 分钟后"
        }
        let hours = max(1, Int((Double(minutes) / 60).rounded(.up)))
        return seconds < 0 ? "已过约 \(hours) 小时" : "约 \(hours) 小时后"
    }

    private var openTiming: MedicationWatchDoseTiming? {
        guard item.status.isOpen else {
            return nil
        }
        if item.dueAt < now {
            return .overdue
        }
        if item.dueAt.timeIntervalSince(now) <= 1_800 {
            return .dueSoon
        }
        return .upcoming
    }

    private var accessibilityLabel: String {
        let itemText = privacyMode ? "用药提醒" : "\(item.medicationName)，\(item.doseText)"
        if let relativeTimingText {
            return "\(item.timeText)，\(itemText)，\(statusText)，\(relativeTimingText)"
        }
        return "\(item.timeText)，\(itemText)，\(statusText)"
    }
}

private struct WatchMoreItemsRow: View {
    let hiddenCount: Int
    let sectionTitle: String
    let symbolName: String
    let tint: Color

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: symbolName)
                .font(.caption.weight(.bold))
                .foregroundStyle(tint)
                .frame(width: 24, height: 24)
                .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text("还有 \(hiddenCount) 项")
                    .font(.body.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
                Text("iPhone 查看全部")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.76)
            }

            Spacer(minLength: 4)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("还有 \(hiddenCount) 项\(sectionTitle)，打开 iPhone 查看全部")
    }
}

#Preview {
    WatchTodayView()
        .environmentObject(MedicationWatchSnapshotCenter())
}
