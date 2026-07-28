import Foundation

public enum AdherenceTrendState: String, Codable, Sendable, Equatable {
    case insufficientData
    case improving
    case stable
    case declining
}

public struct AdherenceTrendPoint: Codable, Sendable, Equatable {
    public var date: DateOnly
    public var completionRate: Double
    public var scheduledCount: Int
    public var takenCount: Int
    public var skippedCount: Int
    public var delayedCount: Int

    public init(
        date: DateOnly,
        completionRate: Double,
        scheduledCount: Int,
        takenCount: Int,
        skippedCount: Int,
        delayedCount: Int
    ) {
        self.date = date
        self.completionRate = AdherenceMath.clampedRate(completionRate)
        self.scheduledCount = scheduledCount
        self.takenCount = takenCount
        self.skippedCount = skippedCount
        self.delayedCount = delayedCount
    }
}

public struct AdherenceTrendInsight: Codable, Sendable, Equatable {
    public var state: AdherenceTrendState
    public var daysAnalyzed: Int
    public var minimumRequiredDays: Int
    public var recentWindowDays: Int
    public var previousWindowDays: Int
    public var recentAverageCompletionRate: Double
    public var previousAverageCompletionRate: Double?
    public var changeFromPrevious: Double?
    public var slopePerDay: Double
    public var skippedRate: Double
    public var delayedRate: Double
    public var consistencyScore: Double
    public var doseChangeCount: Int
    public var doseChangeSummary: String
    public var message: String
    public var supportingSummary: String
    public var safetyNote: String
    public var points: [AdherenceTrendPoint]

    public init(
        state: AdherenceTrendState,
        daysAnalyzed: Int,
        minimumRequiredDays: Int,
        recentWindowDays: Int,
        previousWindowDays: Int,
        recentAverageCompletionRate: Double,
        previousAverageCompletionRate: Double?,
        changeFromPrevious: Double?,
        slopePerDay: Double,
        skippedRate: Double,
        delayedRate: Double,
        consistencyScore: Double,
        doseChangeCount: Int = 0,
        doseChangeSummary: String = "",
        message: String,
        supportingSummary: String,
        safetyNote: String = AdherenceTrendBuilder.defaultSafetyNote,
        points: [AdherenceTrendPoint]
    ) {
        self.state = state
        self.daysAnalyzed = daysAnalyzed
        self.minimumRequiredDays = minimumRequiredDays
        self.recentWindowDays = recentWindowDays
        self.previousWindowDays = previousWindowDays
        self.recentAverageCompletionRate = recentAverageCompletionRate
        self.previousAverageCompletionRate = previousAverageCompletionRate
        self.changeFromPrevious = changeFromPrevious
        self.slopePerDay = slopePerDay
        self.skippedRate = skippedRate
        self.delayedRate = delayedRate
        self.consistencyScore = consistencyScore
        self.doseChangeCount = doseChangeCount
        self.doseChangeSummary = doseChangeSummary
        self.message = message
        self.supportingSummary = supportingSummary
        self.safetyNote = safetyNote
        self.points = points
    }
}

public struct AdherenceTrendBuilder: Sendable {
    public static let defaultMinimumRequiredDays = 7
    public static let defaultRecentWindowDays = 7
    public static let defaultMaximumAnalysisDays = 28
    public static let defaultMeaningfulChange = 0.08
    public static let defaultSafetyNote = "用药趋势只反映用户记录与提醒完成情况，不代表疗效、诊断或处方建议。"

    public init() {}

    public func build(
        scheduledDoses: [ScheduledDose],
        events: [DoseEvent],
        doseChanges: [MedicationDoseChange] = [],
        calendar baseCalendar: Calendar = Calendar(identifier: .gregorian),
        timeZone: TimeZone,
        now: Date = Date(),
        minimumRequiredDays: Int = Self.defaultMinimumRequiredDays,
        recentWindowDays: Int = Self.defaultRecentWindowDays,
        maximumAnalysisDays: Int = Self.defaultMaximumAnalysisDays
    ) -> AdherenceTrendInsight {
        let insight = AdherenceInsightBuilder().build(
            scheduledDoses: scheduledDoses,
            events: events,
            calendar: baseCalendar,
            timeZone: timeZone,
            now: now
        )
        return build(
            dayStatuses: insight.dayStatuses,
            doseChanges: doseChanges,
            minimumRequiredDays: minimumRequiredDays,
            recentWindowDays: recentWindowDays,
            maximumAnalysisDays: maximumAnalysisDays
        )
    }

    public func build(
        dayStatuses: [AdherenceDayStatus],
        doseChanges: [MedicationDoseChange] = [],
        minimumRequiredDays: Int = Self.defaultMinimumRequiredDays,
        recentWindowDays: Int = Self.defaultRecentWindowDays,
        maximumAnalysisDays: Int = Self.defaultMaximumAnalysisDays
    ) -> AdherenceTrendInsight {
        let requiredDays = max(1, minimumRequiredDays)
        let windowDays = max(1, recentWindowDays)
        let analysisDays = max(requiredDays, maximumAnalysisDays)
        let validStatuses = dayStatuses
            .filter { $0.scheduledCount > 0 }
            .sorted { $0.date < $1.date }
            .suffix(analysisDays)
        let points = validStatuses.map { status in
            AdherenceTrendPoint(
                date: status.date,
                completionRate: clampedRate(status.completionRate),
                scheduledCount: status.scheduledCount,
                takenCount: status.takenCount,
                skippedCount: status.skippedCount,
                delayedCount: status.delayedCount
            )
        }

        guard points.count >= requiredDays else {
            return insufficientInsight(
                points: points,
                doseChanges: doseChanges,
                requiredDays: requiredDays,
                windowDays: windowDays
            )
        }

        let recentPoints = Array(points.suffix(windowDays))
        let previousPoints = Array(points.dropLast(recentPoints.count).suffix(windowDays))
        let recentAverage = averageCompletionRate(in: recentPoints)
        let previousAverage = previousPoints.count == windowDays ? averageCompletionRate(in: previousPoints) : nil
        let change = previousAverage.map { recentAverage - $0 }
        let slope = slopePerDay(in: points)
        let scheduledCount = points.reduce(0) { $0 + $1.scheduledCount }
        let skippedRate = scheduledCount == 0 ? 0 : Double(points.reduce(0) { $0 + $1.skippedCount }) / Double(scheduledCount)
        let delayedRate = scheduledCount == 0 ? 0 : Double(points.reduce(0) { $0 + $1.delayedCount }) / Double(scheduledCount)
        let consistency = consistencyScore(in: points)
        let doseChangeContext = doseChangeContext(for: doseChanges)
        let state = trendState(
            changeFromPrevious: change,
            slopePerDay: slope,
            windowDays: recentPoints.count
        )

        return AdherenceTrendInsight(
            state: state,
            daysAnalyzed: points.count,
            minimumRequiredDays: requiredDays,
            recentWindowDays: recentPoints.count,
            previousWindowDays: previousPoints.count,
            recentAverageCompletionRate: recentAverage,
            previousAverageCompletionRate: previousAverage,
            changeFromPrevious: change,
            slopePerDay: slope,
            skippedRate: skippedRate,
            delayedRate: delayedRate,
            consistencyScore: consistency,
            doseChangeCount: doseChangeContext.count,
            doseChangeSummary: doseChangeContext.summary,
            message: message(
                state: state,
                recentAverage: recentAverage,
                changeFromPrevious: change,
                recentWindowDays: recentPoints.count
            ),
            supportingSummary: supportingSummary(
                daysAnalyzed: points.count,
                previousWindowDays: previousPoints.count,
                skippedRate: skippedRate,
                delayedRate: delayedRate,
                consistencyScore: consistency,
                doseChangeSummary: doseChangeContext.summary
            ),
            points: points
        )
    }

    private func insufficientInsight(
        points: [AdherenceTrendPoint],
        doseChanges: [MedicationDoseChange],
        requiredDays: Int,
        windowDays: Int
    ) -> AdherenceTrendInsight {
        let doseChangeContext = doseChangeContext(for: doseChanges)
        return AdherenceTrendInsight(
            state: .insufficientData,
            daysAnalyzed: points.count,
            minimumRequiredDays: requiredDays,
            recentWindowDays: min(points.count, windowDays),
            previousWindowDays: 0,
            recentAverageCompletionRate: averageCompletionRate(in: points),
            previousAverageCompletionRate: nil,
            changeFromPrevious: nil,
            slopePerDay: 0,
            skippedRate: 0,
            delayedRate: 0,
            consistencyScore: points.isEmpty ? 0 : consistencyScore(in: points),
            doseChangeCount: doseChangeContext.count,
            doseChangeSummary: doseChangeContext.summary,
            message: "至少记录 \(requiredDays) 个有提醒的日期后，才生成用药趋势。当前已有 \(points.count) 天。",
            supportingSummary: "趋势需要真实服药记录支撑；数据不足时不生成改善或下降判断。\(doseChangeContext.summary)",
            points: points
        )
    }

    private func trendState(changeFromPrevious: Double?, slopePerDay: Double, windowDays: Int) -> AdherenceTrendState {
        let windowSlope = slopePerDay * Double(max(1, windowDays))
        if let changeFromPrevious {
            if changeFromPrevious >= Self.defaultMeaningfulChange {
                return .improving
            }
            if changeFromPrevious <= -Self.defaultMeaningfulChange {
                return .declining
            }
        } else {
            if windowSlope >= Self.defaultMeaningfulChange {
                return .improving
            }
            if windowSlope <= -Self.defaultMeaningfulChange {
                return .declining
            }
        }
        return .stable
    }

    private func message(
        state: AdherenceTrendState,
        recentAverage: Double,
        changeFromPrevious: Double?,
        recentWindowDays: Int
    ) -> String {
        let recentText = "\(percentage(recentAverage))%"
        let changeText = changeFromPrevious.map { "，较前一周期\(signedPercentagePoint($0))" } ?? ""
        switch state {
        case .insufficientData:
            return ""
        case .improving:
            return "最近 \(recentWindowDays) 天完成率 \(recentText)\(changeText)，记录趋势正在改善。"
        case .stable:
            return "最近 \(recentWindowDays) 天完成率 \(recentText)\(changeText)，趋势总体平稳。"
        case .declining:
            return "最近 \(recentWindowDays) 天完成率 \(recentText)\(changeText)，建议复盘漏服或延后原因。"
        }
    }

    private func supportingSummary(
        daysAnalyzed: Int,
        previousWindowDays: Int,
        skippedRate: Double,
        delayedRate: Double,
        consistencyScore: Double,
        doseChangeSummary: String
    ) -> String {
        let comparison = previousWindowDays >= Self.defaultRecentWindowDays ? "已与前一周期比较" : "前一周期不足 7 天，先按斜率和波动观察"
        return "分析最近 \(daysAnalyzed) 个有提醒日期，\(comparison)；已忽略率 \(percentage(skippedRate))%，稍后率 \(percentage(delayedRate))%，稳定度 \(percentage(consistencyScore))%。\(doseChangeSummary)"
    }

    private func averageCompletionRate(in points: [AdherenceTrendPoint]) -> Double {
        guard !points.isEmpty else {
            return 0
        }
        return points.reduce(0) { $0 + $1.completionRate } / Double(points.count)
    }

    // This is a record-based trend model, not a clinical adherence or drug-supply measure.
    // PDC and MPR usually require pharmacy claims or refill supply data. This app instead
    // uses confirmed scheduled-dose records: 7-day completion average, previous-period
    // delta, least-squares slope, skipped/delayed rates and variance-derived consistency.
    // Dose changes are treated as explanatory context, not as proof of illness severity.
    // Keeping the math small and explicit makes the first version auditable, and leaves
    // room to add medication-specific weighting, refill data or before/after segmentation later.
    private func slopePerDay(in points: [AdherenceTrendPoint]) -> Double {
        guard points.count > 1 else {
            return 0
        }
        let xValues = points.indices.map(Double.init)
        let yValues = points.map(\.completionRate)
        let xAverage = xValues.reduce(0, +) / Double(xValues.count)
        let yAverage = yValues.reduce(0, +) / Double(yValues.count)
        let numerator = zip(xValues, yValues).reduce(0) { result, pair in
            result + (pair.0 - xAverage) * (pair.1 - yAverage)
        }
        let denominator = xValues.reduce(0) { result, x in
            result + pow(x - xAverage, 2)
        }
        guard denominator > 0 else {
            return 0
        }
        return numerator / denominator
    }

    private func consistencyScore(in points: [AdherenceTrendPoint]) -> Double {
        guard points.count > 1 else {
            return points.isEmpty ? 0 : 1
        }
        let average = averageCompletionRate(in: points)
        let variance = points.reduce(0) { result, point in
            result + pow(point.completionRate - average, 2)
        } / Double(points.count)
        let standardDeviation = sqrt(variance)
        return max(0, min(1, 1 - standardDeviation / 0.5))
    }

    private func clampedRate(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }

    private func percentage(_ value: Double) -> Int {
        Int((value * 100).rounded())
    }

    private func signedPercentagePoint(_ value: Double) -> String {
        let points = Int((abs(value) * 100).rounded())
        return value >= 0 ? "上升 \(points) 个百分点" : "下降 \(points) 个百分点"
    }

    private func doseChangeContext(for doseChanges: [MedicationDoseChange]) -> (count: Int, summary: String) {
        guard !doseChanges.isEmpty else {
            return (0, "")
        }
        let sortedChanges = doseChanges.sorted { $0.effectiveFrom < $1.effectiveFrom }
        let count = sortedChanges.count
        let latest = sortedChanges[sortedChanges.count - 1]
        let latestDose = doseText(latest.newDose)
        let prefix = count == 1 ? "记录到 1 次剂量变化" : "记录到 \(count) 次剂量变化"
        return (count, "\(prefix)，最近一次调整为 \(latestDose)；趋势解读应结合剂量变化前后分别观察。")
    }

    private func doseText(_ dose: DoseAmount) -> String {
        "\(dose.value) \(dose.unit)"
    }
}
