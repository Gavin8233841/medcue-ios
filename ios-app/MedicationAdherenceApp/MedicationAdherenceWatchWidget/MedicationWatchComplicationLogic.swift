import Foundation

enum MedicationWatchComplicationTint: Equatable {
    case blue
    case orange
    case purple
    case green
}

enum MedicationWatchComplicationTimelinePolicy {
    static func nextRefreshDate(
        for snapshot: MedicationWatchSnapshot,
        now: Date,
        calendar: Calendar = .current
    ) -> Date {
        let fallbackDate = now.addingTimeInterval(900)
        let dayBoundaryDate = nextStartOfDay(after: now, calendar: calendar).addingTimeInterval(5)
        let fallbackOrDayBoundaryDate = min(fallbackDate, dayBoundaryDate)
        guard !snapshot.requiresRefresh(now: now, calendar: calendar),
              let item = snapshot.displayNextOpenItem(now: now, calendar: calendar)
        else {
            return fallbackOrDayBoundaryDate
        }

        let dueSoonDate = item.dueAt.addingTimeInterval(-1_800)
        let statusBoundaryDate: Date?
        if now < dueSoonDate {
            statusBoundaryDate = dueSoonDate
        } else if now < item.dueAt {
            statusBoundaryDate = item.dueAt
        } else {
            statusBoundaryDate = nil
        }

        guard let statusBoundaryDate else {
            return fallbackOrDayBoundaryDate
        }
        let earliestUsefulRefresh = now.addingTimeInterval(60)
        return min(max(statusBoundaryDate, earliestUsefulRefresh), fallbackOrDayBoundaryDate)
    }

    private static func nextStartOfDay(after date: Date, calendar: Calendar) -> Date {
        let startOfDay = calendar.startOfDay(for: date)
        return calendar.date(byAdding: .day, value: 1, to: startOfDay) ?? date.addingTimeInterval(86_400)
    }
}

struct MedicationWatchComplicationStatus: Equatable {
    let primaryText: String
    let detailText: String
    let inlineText: String
    let symbolName: String
    let tint: MedicationWatchComplicationTint
    let accessibilityText: String

    init(
        snapshot: MedicationWatchSnapshot,
        now: Date = Date(),
        calendar: Calendar = .current
    ) {
        let presentationState = snapshot.presentationState(now: now, calendar: calendar)
        if presentationState == .awaitingFirstSync {
            primaryText = "同步"
            detailText = "手机同步"
            inlineText = "手机同步今日用药"
            symbolName = "iphone"
            tint = .blue
            accessibilityText = "今日用药尚未同步，请打开手机刷新"
            return
        }

        if presentationState == .stale {
            primaryText = "刷新"
            detailText = "手机更新"
            inlineText = "手机更新今日用药"
            symbolName = "clock.badge.exclamationmark"
            tint = .orange
            accessibilityText = "今日用药计划需刷新，请打开手机更新计划"
            return
        }

        if let item = snapshot.displayNextOpenItem(now: now, calendar: calendar) {
            let itemText = snapshot.privacyMode ? "用药" : item.medicationName
            let accessibilityItemText = snapshot.privacyMode ? "用药提醒" : "\(item.medicationName)，\(item.doseText)"
            primaryText = item.timeText

            switch snapshot.timing(for: item, now: now) {
            case .overdue:
                detailText = "\(itemText) · 已到点"
                inlineText = "\(item.timeText) 已到点"
                symbolName = "clock.badge.exclamationmark"
                tint = .orange
                accessibilityText = "\(item.timeText)，\(accessibilityItemText)，已到点"
            case .dueSoon:
                detailText = "\(itemText) · 即将提醒"
                inlineText = "\(item.timeText) 即将提醒"
                symbolName = "bell.badge"
                tint = .purple
                accessibilityText = "\(item.timeText)，\(accessibilityItemText)，即将提醒"
            case .upcoming:
                detailText = "\(itemText) · \(snapshot.displayCompletionText(now: now, calendar: calendar))"
                inlineText = snapshot.privacyMode ? "\(item.timeText) 用药" : "\(item.timeText) \(item.medicationName)"
                symbolName = "pills.fill"
                tint = .blue
                accessibilityText = "\(item.timeText)，\(accessibilityItemText)，\(snapshot.displayCompletionText(now: now, calendar: calendar))"
            }
            return
        }

        if presentationState == .empty {
            primaryText = "无计划"
            detailText = "今日暂无用药"
            inlineText = "今日暂无用药"
            symbolName = "calendar.badge.checkmark"
            tint = .green
            accessibilityText = "今日暂无用药计划"
            return
        }

        primaryText = "完成"
        detailText = snapshot.displayCompletionText(now: now, calendar: calendar)
        inlineText = "今日用药已完成"
        symbolName = "checkmark.circle.fill"
        tint = .green
        accessibilityText = "今日用药已完成，\(snapshot.displayCompletionText(now: now, calendar: calendar))"
    }
}
