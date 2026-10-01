import Foundation

/// Health observations are separate from medication-management scores.
public enum HealthEvidenceMetric: String, Codable, CaseIterable, Sendable {
    case sleep, restingHeartRate, hrvSDNN, respiratoryRate

    public var title: String {
        switch self {
        case .sleep: "睡眠"
        case .restingHeartRate: "静息心率"
        case .hrvSDNN: "心率变异性（SDNN）"
        case .respiratoryRate: "呼吸频率"
        }
    }

    public var unit: String {
        switch self {
        case .sleep: "小时"
        case .restingHeartRate, .respiratoryRate: "次/分"
        case .hrvSDNN: "毫秒"
        }
    }
}

public enum HealthSleepState: String, Codable, Sendable {
    case inBed, awake, asleep, core, deep, rem
    public var isAsleep: Bool { self != .inBed && self != .awake }
}

/// The platform adapter must normalize compatible units before construction.
public struct HealthEvidenceSample: Codable, Identifiable, Equatable, Sendable {
    public let id: UUID
    public let metric: HealthEvidenceMetric
    public let start: Date
    public let end: Date
    public let value: Double
    public let unit: String
    public let sourceID: String
    public let sourceName: String
    public let sourceVersion: String?
    public let deviceModel: String?
    public let timeZoneIdentifier: String?
    public let sleepState: HealthSleepState?

    public init(id: UUID, metric: HealthEvidenceMetric, start: Date, end: Date,
                value: Double, unit: String, sourceID: String, sourceName: String,
                timeZoneIdentifier: String? = nil, sleepState: HealthSleepState? = nil,
                sourceVersion: String? = nil, deviceModel: String? = nil) {
        self.id = id; self.metric = metric; self.start = start; self.end = end
        self.value = value; self.unit = unit; self.sourceID = sourceID
        self.sourceName = sourceName; self.timeZoneIdentifier = timeZoneIdentifier
        self.sleepState = sleepState
        self.sourceVersion = sourceVersion; self.deviceModel = deviceModel
    }
}

public enum HealthEvidenceQuality: String, Codable, Hashable, Sendable {
    case noReadableData, multipleSources, conflictingIdentity, invalidSample
    case timeZoneMissing, sourceTimeZoneDiffers, overlappingSleepStages, partialPeriod
    case queryFailed, sampleBudgetExceeded

    public var explanation: String {
        switch self {
        case .noReadableData: "当前没有可读取的数据，可能尚未记录或未允许读取"
        case .multipleSources: "存在多个来源 App、版本或型号组；仅使用覆盖日期最多的一组"
        case .conflictingIdentity: "部分记录身份冲突，已排除"
        case .invalidSample: "部分记录的单位、数值或时间无法使用，已排除"
        case .timeZoneMissing: "部分记录没有时区信息；按本次回顾时区整理"
        case .sourceTimeZoneDiffers: "部分记录来自其他时区；日期按本次回顾时区整理"
        case .overlappingSleepStages: "睡眠阶段存在重叠；时长去重，不解释阶段占比"
        case .partialPeriod: "窗口边缘有不完整时段，未纳入日均比较"
        case .sampleBudgetExceeded: "记录数量超过本次读取预算，此指标未汇总，请缩短读取范围"
        case .queryFailed: "此指标读取未完成，请刷新后重试"
        }
    }
}

public struct HealthEvidenceDay: Codable, Identifiable, Equatable, Sendable {
    public var id: Date { start }
    public let start: Date
    public let end: Date
    public let value: Double
    public let sourceSampleIDs: [UUID]
}

public struct HealthEvidenceFact: Codable, Identifiable, Equatable, Sendable {
    public var id: String { metric.rawValue }
    public let metric: HealthEvidenceMetric
    public let sourceName: String?
    public let sourceID: String?
    public let days: [HealthEvidenceDay]
    public let expectedDays: Int
    public let quality: [HealthEvidenceQuality]
    public var observedDays: Int { days.count }
    public var median: Double? { HealthEvidenceBuilder.median(days.map(\.value)) }
    public var coverage: Double { expectedDays > 0 ? Double(observedDays) / Double(expectedDays) : 0 }
}

public struct HealthEvidenceBundle: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let generatedAt: Date
    public let start: Date
    public let end: Date
    public let timeZoneIdentifier: String
    public let facts: [HealthEvidenceFact]

    public init(generatedAt: Date, start: Date, end: Date, timeZoneIdentifier: String,
                facts: [HealthEvidenceFact]) {
        schemaVersion = 1; self.generatedAt = generatedAt; self.start = start; self.end = end
        self.timeZoneIdentifier = timeZoneIdentifier; self.facts = facts
    }
}

public struct HealthEvidenceBuilder: Sendable {
    public init() {}

    /// Quantity days are midnight-to-midnight. Sleep days are noon-to-noon,
    /// including naps. Only complete periods inside the requested window count.
    public func build(samples: [HealthEvidenceSample], start: Date, end: Date,
                      timeZone: TimeZone, generatedAt: Date,
                      failedMetrics: Set<HealthEvidenceMetric> = [],
                      budgetExceededMetrics: Set<HealthEvidenceMetric> = []) -> HealthEvidenceBundle {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let facts = HealthEvidenceMetric.allCases.map { metric in
            makeFact(metric: metric, samples: samples.filter { $0.metric == metric },
                     start: start, end: end, calendar: calendar, failed: failedMetrics.contains(metric),
                     budgetExceeded: budgetExceededMetrics.contains(metric))
        }
        return HealthEvidenceBundle(generatedAt: generatedAt, start: start, end: end,
                                    timeZoneIdentifier: timeZone.identifier, facts: facts)
    }

    private func makeFact(metric: HealthEvidenceMetric, samples: [HealthEvidenceSample],
                          start: Date, end: Date, calendar: Calendar, failed: Bool, budgetExceeded: Bool) -> HealthEvidenceFact {
        var flags = Set<HealthEvidenceQuality>()
        if failed { flags.insert(.queryFailed) }
        if budgetExceeded { flags.insert(.sampleBudgetExceeded) }
        let grouped = Dictionary(grouping: samples, by: \.id)
        var unique: [HealthEvidenceSample] = []
        for duplicates in grouped.values {
            guard let first = duplicates.first else { continue }
            guard duplicates.allSatisfy({ $0 == first }) else {
                flags.insert(.conflictingIdentity); continue
            }
            guard first.start <= first.end, first.value.isFinite, first.value >= 0,
                  first.unit == metric.unit, !first.sourceID.isEmpty,
                  metric != .sleep || (first.sleepState != nil && first.end > first.start)
            else { flags.insert(.invalidSample); continue }
            if first.timeZoneIdentifier == nil { flags.insert(.timeZoneMissing) }
            else if first.timeZoneIdentifier != calendar.timeZone.identifier { flags.insert(.sourceTimeZoneDiffers) }
            unique.append(first)
        }
        let periods = completePeriods(start: start, end: end, metric: metric, calendar: calendar)
        if periods.first?.start != start || periods.last?.end != end { flags.insert(.partialPeriod) }
        let sources = Dictionary(grouping: unique, by: \.sourceID)
        if sources.count > 1 { flags.insert(.multipleSources) }
        // Date coverage, never sample density, determines one primary source.
        let sourceID = sources.keys.sorted { lhs, rhs in
            let l = coveredPeriods(sources[lhs] ?? [], periods: periods, metric: metric)
            let r = coveredPeriods(sources[rhs] ?? [], periods: periods, metric: metric)
            return l == r ? lhs < rhs : l > r
        }.first
        let selected = sourceID.flatMap { sources[$0] } ?? []
        var days: [HealthEvidenceDay] = []
        if !failed && !budgetExceeded {
            for period in periods {
                let rows = matching(selected, period: period, metric: metric)
                guard !rows.isEmpty else { continue }
                let value: Double
                if metric == .sleep {
                    if hasStageConflict(rows) { flags.insert(.overlappingSleepStages) }
                    value = Self.unionDuration(rows.map {
                        DateInterval(start: max($0.start, period.start), end: min($0.end, period.end))
                    }) / 3600
                } else {
                    guard let central = Self.median(rows.map(\.value)) else { continue }
                    value = central
                }
                days.append(HealthEvidenceDay(start: period.start, end: period.end, value: value,
                                              sourceSampleIDs: rows.map(\.id).sorted { $0.uuidString < $1.uuidString }))
            }
        }
        if days.isEmpty && !failed && !budgetExceeded { flags.insert(.noReadableData) }
        return HealthEvidenceFact(metric: metric,
            sourceName: selected.sorted { $0.sourceName < $1.sourceName }.first?.sourceName,
            sourceID: sourceID, days: days, expectedDays: periods.count,
            quality: flags.sorted { $0.rawValue < $1.rawValue })
    }

    private func completePeriods(start: Date, end: Date, metric: HealthEvidenceMetric,
                                 calendar: Calendar) -> [DateInterval] {
        guard start < end else { return [] }
        var cursor = calendar.startOfDay(for: start)
        if metric == .sleep { cursor = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: cursor) ?? cursor }
        if cursor < start { cursor = calendar.date(byAdding: .day, value: 1, to: cursor) ?? end }
        var result: [DateInterval] = []
        while cursor < end, result.count < 366 {
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor), next > cursor else { break }
            if next > end { break }
            result.append(DateInterval(start: cursor, end: next)); cursor = next
        }
        return result
    }

    private func matching(_ samples: [HealthEvidenceSample], period: DateInterval,
                          metric: HealthEvidenceMetric) -> [HealthEvidenceSample] {
        samples.filter {
            if metric == .sleep {
                return $0.sleepState?.isAsleep == true && $0.end > period.start && $0.start < period.end
            }
            return $0.end >= period.start && $0.end < period.end
        }
    }

    private func coveredPeriods(_ rows: [HealthEvidenceSample], periods: [DateInterval],
                                metric: HealthEvidenceMetric) -> Int {
        periods.filter { !matching(rows, period: $0, metric: metric).isEmpty }.count
    }

    private func hasStageConflict(_ rows: [HealthEvidenceSample]) -> Bool {
        var latestEnds: [HealthSleepState: Date] = [:]
        for row in rows.filter({ $0.sleepState != .asleep }).sorted(by: { $0.start < $1.start }) {
            guard let state = row.sleepState else { continue }
            if latestEnds.contains(where: { $0.key != state && $0.value > row.start }) { return true }
            latestEnds[state] = max(latestEnds[state] ?? row.end, row.end)
        }
        return false
    }

    public static func unionDuration(_ intervals: [DateInterval]) -> TimeInterval {
        let sorted = intervals.sorted { $0.start < $1.start }
        guard var current = sorted.first else { return 0 }
        var duration: TimeInterval = 0
        for next in sorted.dropFirst() {
            if next.start <= current.end {
                current = DateInterval(start: current.start, end: max(current.end, next.end))
            } else { duration += current.duration; current = next }
        }
        return duration + current.duration
    }

    public static func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted(); let middle = sorted.count / 2
        return sorted.count.isMultiple(of: 2) ? (sorted[middle - 1] + sorted[middle]) / 2 : sorted[middle]
    }
}

/// Complete snapshots replace, rather than append, so deleted HealthKit objects
/// disappear from all recomputed facts. Access epochs reject late read callbacks.
public struct HealthEvidenceSnapshot: Sendable {
    public private(set) var samples: [HealthEvidenceSample] = []
    public private(set) var epoch: UInt64 = 0
    public private(set) var isEnabled = true
    public init() {}
    public mutating func beginRefresh() -> UInt64 { epoch &+= 1; return epoch }
    @discardableResult public mutating func replace(_ values: [HealthEvidenceSample], epoch requestEpoch: UInt64) -> Bool {
        guard isEnabled, requestEpoch == epoch else { return false }
        samples = values; return true
    }
    public mutating func disconnect() { epoch &+= 1; isEnabled = false; samples = [] }
    public mutating func reconnect() { epoch &+= 1; isEnabled = true }
}

/// No model and no network: the numeric answer is generated from verified facts.
public struct HealthEvidenceLocalReview: Sendable {
    public init() {}
    public static func metric(in question: String) -> HealthEvidenceMetric? {
        // Deliberately exact, controlled review intents. Never intercept arbitrary
        // symptom, medication or causal questions using a health keyword alone.
        let normalized = question.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "？?。"))
        let intents: [String: HealthEvidenceMetric] = [
            "回顾睡眠记录": .sleep, "近一周睡眠怎样": .sleep, "近7天睡眠记录": .sleep,
            "近30天睡眠记录": .sleep, "回顾静息心率记录": .restingHeartRate,
            "近一周静息心率记录": .restingHeartRate, "近30天静息心率记录": .restingHeartRate,
            "回顾HRV记录": .hrvSDNN, "近一周HRV记录": .hrvSDNN,
            "回顾呼吸频率记录": .respiratoryRate, "最近呼吸频率记录怎样": .respiratoryRate,
            "近一周呼吸频率记录": .respiratoryRate
        ]
        return intents[normalized]
    }
    public static func lookbackDays(in question: String) -> Int {
        let text = question.lowercased()
        if ["近一周", "近7天", "最近7天", "本周", "这周", "last week"].contains(where: text.contains) { return 7 }
        if ["近一个月", "近30天", "最近30天", "last month"].contains(where: text.contains) { return 30 }
        return 56
    }
    public func answer(metric: HealthEvidenceMetric, bundle: HealthEvidenceBundle) -> String {
        guard let fact = bundle.facts.first(where: { $0.metric == metric }) else {
            return "本次回顾没有包含\(metric.title)记录。"
        }
        guard let value = fact.median else {
            let reason = fact.quality.contains(.sampleBudgetExceeded)
                ? HealthEvidenceQuality.sampleBudgetExceeded.explanation
                : fact.quality.contains(.queryFailed) ? HealthEvidenceQuality.queryFailed.explanation
                : "当前没有足够的可读取记录；请检查 Apple 健康中的记录和读取权限"
            return "\(metric.title)：\(reason)。"
        }
        let formatted = value.formatted(.number.precision(.fractionLength(0...1)))
        let period = metric == .sleep ? "睡眠日（中午至次日中午，含午睡）" : "日期"
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(identifier: bundle.timeZoneIdentifier)
        formatter.dateFormat = "yyyy-MM-dd"
        let window = "\(formatter.string(from: bundle.start))至\(formatter.string(from: bundle.end))"
        let limitations = fact.quality.map(\.explanation).joined(separator: "；")
        let limitationText = limitations.isEmpty ? "" : "数据限制：\(limitations)。"
        return "本次回顾范围为\(window)（时区：\(bundle.timeZoneIdentifier)），有\(fact.observedDays)/\(fact.expectedDays)个\(period)有记录，日汇总中位数为\(formatted)\(metric.unit)。来源 App：\(fact.sourceName ?? "未知")。\(limitationText)缺记录不代表数值为零。以上是记录回顾，不能据此判断病情或药效。"
    }
}


/// Query one extra object; an overflow invalidates the entire metric rather than
/// presenting an apparently complete summary from a truncated prefix.
public enum HealthReadBudget {
    public static let quantitySamples = 20_000
    public static let sleepSamples = 8_000
    public static func accepts(count: Int, limit: Int) -> Bool { count >= 0 && limit > 0 && count <= limit }
}
