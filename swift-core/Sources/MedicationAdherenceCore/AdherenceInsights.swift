import Foundation

public struct AdherenceDayStatus: Codable, Sendable, Equatable {
    public var date: DateOnly
    public var scheduledCount: Int
    public var takenCount: Int
    public var skippedCount: Int
    public var delayedCount: Int
    public var completionRate: Double
    public var isComplete: Bool

    public init(
        date: DateOnly,
        scheduledCount: Int,
        takenCount: Int,
        skippedCount: Int,
        delayedCount: Int
    ) {
        self.date = date
        self.scheduledCount = scheduledCount
        self.takenCount = takenCount
        self.skippedCount = skippedCount
        self.delayedCount = delayedCount
        self.completionRate = scheduledCount == 0 ? 0 : Double(takenCount) / Double(scheduledCount)
        self.isComplete = scheduledCount > 0 && takenCount == scheduledCount
    }
}

public struct AdherenceInsight: Codable, Sendable, Equatable {
    public var scheduledCount: Int
    public var takenCount: Int
    public var skippedCount: Int
    public var delayedCount: Int
    public var completionRate: Double
    public var currentStreakDays: Int
    public var longestStreakDays: Int
    public var dayStatuses: [AdherenceDayStatus]
    public var message: String
    public var safetyNote: String

    public init(
        scheduledCount: Int,
        takenCount: Int,
        skippedCount: Int,
        delayedCount: Int,
        currentStreakDays: Int,
        longestStreakDays: Int,
        dayStatuses: [AdherenceDayStatus],
        message: String,
        safetyNote: String = AdherenceInsightBuilder.defaultSafetyNote
    ) {
        self.scheduledCount = scheduledCount
        self.takenCount = takenCount
        self.skippedCount = skippedCount
        self.delayedCount = delayedCount
        self.completionRate = scheduledCount == 0 ? 0 : Double(takenCount) / Double(scheduledCount)
        self.currentStreakDays = currentStreakDays
        self.longestStreakDays = longestStreakDays
        self.dayStatuses = dayStatuses
        self.message = message
        self.safetyNote = safetyNote
    }
}

public struct AdherenceInsightBuilder: Sendable {
    public static let defaultSafetyNote = "依从性数据只用于自我管理和复诊沟通，不代表疗效判断。"
    public static let defaultStreakMinimumCompletionRate = 0.8

    public init() {}

    public func build(
        scheduledDoses: [ScheduledDose],
        events: [DoseEvent],
        calendar baseCalendar: Calendar = Calendar(identifier: .gregorian),
        timeZone: TimeZone,
        now: Date = Date(),
        streakMinimumCompletionRate: Double = Self.defaultStreakMinimumCompletionRate
    ) -> AdherenceInsight {
        var calendar = baseCalendar
        calendar.timeZone = timeZone
        let today = dateOnly(from: now, calendar: calendar)
        let streakThreshold = min(max(streakMinimumCompletionRate, 0), 1)

        let latestEventByDoseID = Dictionary(grouping: events, by: \.scheduledDoseID).compactMapValues { doseEvents in
            doseEvents.sorted { $0.recordedAt < $1.recordedAt }.last
        }

        let dosesByDate = Dictionary(grouping: scheduledDoses) { dose in
            dateOnly(from: dose.dueAt, calendar: calendar)
        }

        let dayStatuses = dosesByDate.keys.sorted().map { date in
            let doses = dosesByDate[date] ?? []
            let latestEvents = doses.compactMap { latestEventByDoseID[$0.id] }
            let takenCount = latestEvents.filter { $0.status == .taken || $0.status == .corrected }.count
            let skippedCount = latestEvents.filter { $0.status == .skipped }.count
            let delayedCount = latestEvents.filter { $0.status == .delayed }.count
            return AdherenceDayStatus(
                date: date,
                scheduledCount: doses.count,
                takenCount: takenCount,
                skippedCount: skippedCount,
                delayedCount: delayedCount
            )
        }

        let scheduledCount = dayStatuses.reduce(0) { $0 + $1.scheduledCount }
        let takenCount = dayStatuses.reduce(0) { $0 + $1.takenCount }
        let skippedCount = dayStatuses.reduce(0) { $0 + $1.skippedCount }
        let delayedCount = dayStatuses.reduce(0) { $0 + $1.delayedCount }
        let currentStreakDays = currentStreak(in: dayStatuses, today: today, minimumCompletionRate: streakThreshold)
        let longestStreakDays = longestStreak(in: dayStatuses, minimumCompletionRate: streakThreshold)

        return AdherenceInsight(
            scheduledCount: scheduledCount,
            takenCount: takenCount,
            skippedCount: skippedCount,
            delayedCount: delayedCount,
            currentStreakDays: currentStreakDays,
            longestStreakDays: longestStreakDays,
            dayStatuses: dayStatuses,
            message: message(
                currentStreakDays: currentStreakDays,
                skippedCount: skippedCount,
                minimumCompletionRate: streakThreshold
            )
        )
    }

    private func dateOnly(from date: Date, calendar: Calendar) -> DateOnly {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return DateOnly(
            year: components.year ?? 1970,
            month: components.month ?? 1,
            day: components.day ?? 1
        )
    }

    private func currentStreak(
        in dayStatuses: [AdherenceDayStatus],
        today: DateOnly,
        minimumCompletionRate: Double
    ) -> Int {
        var count = 0
        var hasStartedCounting = false
        for status in dayStatuses.reversed() {
            if !hasStartedCounting && status.shouldIgnoreForCurrentStreak(
                today: today,
                minimumCompletionRate: minimumCompletionRate
            ) {
                continue
            }
            guard status.meetsStreakGoal(minimumCompletionRate: minimumCompletionRate) else {
                break
            }
            hasStartedCounting = true
            count += 1
        }
        return count
    }

    private func longestStreak(in dayStatuses: [AdherenceDayStatus], minimumCompletionRate: Double) -> Int {
        var longest = 0
        var current = 0
        for status in dayStatuses {
            if status.meetsStreakGoal(minimumCompletionRate: minimumCompletionRate) {
                current += 1
                longest = max(longest, current)
            } else {
                current = 0
            }
        }
        return longest
    }

    private func message(currentStreakDays: Int, skippedCount: Int, minimumCompletionRate: Double) -> String {
        if currentStreakDays > 0 {
            return "已经连续 \(currentStreakDays) 天达到 \(Int((minimumCompletionRate * 100).rounded()))% 以上记录完成率，继续按已确认计划记录。"
        }
        if skippedCount > 0 {
            return "近期有 \(skippedCount) 次忽略记录，复诊时可带给医生或药师查看。"
        }
        return "继续按已确认计划记录用药情况。"
    }
}

private extension AdherenceDayStatus {
    func meetsStreakGoal(minimumCompletionRate: Double) -> Bool {
        scheduledCount > 0 && completionRate >= minimumCompletionRate
    }

    func shouldIgnoreForCurrentStreak(today: DateOnly, minimumCompletionRate: Double) -> Bool {
        date == today && scheduledCount > 0 && !meetsStreakGoal(minimumCompletionRate: minimumCompletionRate)
    }
}
