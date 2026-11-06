import Foundation
import HealthKit
import MedicationAdherenceCore

struct HealthContextPolicy: Equatable, Sendable {
    let trendLookbackDays: Int

    static let `default` = HealthContextPolicy(trendLookbackDays: 56)
}

@MainActor
final class HealthKitService: ObservableObject {
    @Published private(set) var statusMessage: String
    @Published private(set) var hasCompletedAuthorizationRequest: Bool
    @Published private(set) var recentTrendSamples: [HealthSignalSample] = []
    @Published private(set) var lastSampleRefreshAt: Date?
    @Published private(set) var supportedReadTypesSummary = "心率、静息心率、血压、血氧、体温、血糖、睡眠、步数、活动能量与运动时间"

    private static var recentCache: (days: Int, samples: [HealthSignalSample], refreshedAt: Date)?
    private static let completionKey = "hasCompletedHealthKitAuthorizationRequest"
    private let healthStore = HKHealthStore()
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let hasCompleted = defaults.bool(forKey: Self.completionKey)
        hasCompletedAuthorizationRequest = hasCompleted
        statusMessage = hasCompleted
            ? "已完成 Apple 健康授权请求。仅在用户授权范围内读取健康、睡眠和活动数据。"
            : "尚未完成 Apple 健康授权请求"
    }

    @discardableResult
    func requestAuthorizationEntry() async -> Bool {
        guard HKHealthStore.isHealthDataAvailable() else {
            statusMessage = "当前设备不支持 Apple 健康数据读取"
            return false
        }

        let readTypes = Self.readTypes()
        guard !readTypes.isEmpty else {
            statusMessage = "当前系统没有可读取的 Apple 健康指标类型"
            return false
        }

        do {
            try await requestAuthorization(readTypes: readTypes)
            markAuthorizationRequestCompleted()
            statusMessage = "已完成 Apple 健康授权请求。仅在用户授权范围内读取健康、睡眠和活动数据，用于趋势和复诊资料。"
            await refreshRecentTrendSamples()
            return true
        } catch {
            statusMessage = "Apple 健康授权暂时无法完成，请稍后重试或前往系统隐私设置检查。"
            return false
        }
    }

    func refreshRecentTrendSamples() async {
        await refreshRecentTrendSamples(days: HealthContextPolicy.default.trendLookbackDays)
    }

    func refreshRecentTrendSamples(days: Int, useRecentCache: Bool = false) async {
        guard HKHealthStore.isHealthDataAvailable() else {
            recentTrendSamples = []
            statusMessage = "当前设备不支持 Apple 健康数据读取"
            return
        }

        guard hasCompletedAuthorizationRequest else {
            recentTrendSamples = []
            statusMessage = "尚未完成 Apple 健康授权请求"
            return
        }

        if useRecentCache, let cache = Self.recentCache,
           cache.days >= days, Date().timeIntervalSince(cache.refreshedAt) < 60 {
            recentTrendSamples = cache.samples
            lastSampleRefreshAt = cache.refreshedAt
            statusMessage = cache.samples.isEmpty ? "当前没有可读取的近期健康数据。" : "已读取近期健康数据。"
            return
        }
        let samples = await fetchTrendSamples(days: days)
        recentTrendSamples = samples
        let refreshedAt = Date()
        lastSampleRefreshAt = refreshedAt
        Self.recentCache = (days, samples, refreshedAt)
        statusMessage = samples.isEmpty
            ? "已完成授权请求；当前没有可读取的近期健康数据。"
            : "已读取 \(samples.count) 条近期健康数据。"
    }

    var recentSummary: HealthKitRecentSummary {
        HealthKitRecentSummary(samples: recentTrendSamples, refreshedAt: lastSampleRefreshAt)
    }

    private func markAuthorizationRequestCompleted() {
        hasCompletedAuthorizationRequest = true
        defaults.set(true, forKey: Self.completionKey)
    }

    private func requestAuthorization(readTypes: Set<HKObjectType>) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            healthStore.requestAuthorization(toShare: [], read: readTypes) { success, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: HealthKitAuthorizationError.requestNotCompleted)
                }
            }
        }
    }

    private func fetchTrendSamples(days: Int) async -> [HealthSignalSample] {
        let calendar = Calendar.current
        let endDate = Date()
        let startDate = calendar.date(
            byAdding: .day,
            value: -max(1, days),
            to: endDate
        ) ?? endDate
        let predicate = HKQuery.predicateForSamples(
            withStart: startDate,
            end: endDate,
            options: [.strictStartDate]
        )
        var samples: [HealthSignalSample] = []

        for descriptor in Self.trendSignalDescriptors() {
            guard let quantityType = HKQuantityType.quantityType(forIdentifier: descriptor.identifier) else {
                continue
            }
            do {
                let quantitySamples = try await queryQuantitySamples(
                    type: quantityType,
                    predicate: predicate,
                    limit: 250
                )
                samples.append(
                    contentsOf: quantitySamples.map { sample in
                        let rawValue = sample.quantity.doubleValue(for: descriptor.unit)
                        return HealthSignalSample(
                            kind: descriptor.kind,
                            measuredAt: sample.endDate,
                            value: descriptor.displayValue(from: rawValue),
                            unit: descriptor.displayUnit
                        )
                    }
                )
            } catch {
                continue
            }
        }

        for descriptor in Self.dailyActivityDescriptors {
            if let daily = try? await queryDailyTotals(descriptor, start: startDate, end: endDate) {
                samples.append(contentsOf: daily)
            }
        }
        if let sleep = try? await querySleep(start: startDate, end: endDate) {
            samples.append(contentsOf: sleep)
        }
        return samples.sorted { $0.measuredAt < $1.measuredAt }
    }

    private func queryQuantitySamples(
        type: HKQuantityType,
        predicate: NSPredicate,
        limit: Int
    ) async throws -> [HKQuantitySample] {
        try await withCheckedThrowingContinuation { continuation in
            let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
            let query = HKSampleQuery(
                sampleType: type,
                predicate: predicate,
                limit: limit,
                sortDescriptors: [sortDescriptor]
            ) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                continuation.resume(returning: samples?.compactMap { $0 as? HKQuantitySample } ?? [])
            }
            healthStore.execute(query)
        }
    }

    private static var dailyActivityDescriptors: [HealthKitSignalDescriptor] {
        [
            .init(identifier: .stepCount, kind: .stepCount, unit: .count(), displayUnit: "步"),
            .init(identifier: .activeEnergyBurned, kind: .activeEnergy, unit: .kilocalorie(), displayUnit: "千卡"),
            .init(identifier: .appleExerciseTime, kind: .exerciseMinutes, unit: .minute(), displayUnit: "分钟")
        ]
    }

    private func queryDailyTotals(_ descriptor: HealthKitSignalDescriptor, start: Date, end: Date) async throws -> [HealthSignalSample] {
        guard let type = HKQuantityType.quantityType(forIdentifier: descriptor.identifier) else { return [] }
        let calendar = Calendar.current
        let anchor = calendar.startOfDay(for: start)
        let predicate = HKQuery.predicateForSamples(withStart: anchor, end: end, options: [])
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsCollectionQuery(quantityType: type, quantitySamplePredicate: predicate,
                options: .cumulativeSum, anchorDate: anchor, intervalComponents: DateComponents(day: 1))
            query.initialResultsHandler = { _, collection, error in
                if let error { continuation.resume(throwing: error); return }
                var values: [HealthSignalSample] = []
                collection?.enumerateStatistics(from: anchor, to: end) { statistic, _ in
                    if let quantity = statistic.sumQuantity() {
                        values.append(.init(kind: descriptor.kind,
                            measuredAt: min(statistic.endDate.addingTimeInterval(-1), end),
                            value: quantity.doubleValue(for: descriptor.unit), unit: descriptor.displayUnit))
                    }
                }
                continuation.resume(returning: values)
            }
            healthStore.execute(query)
        }
    }

    private func querySleep(start: Date, end: Date) async throws -> [HealthSignalSample] {
        guard let type = HKCategoryType.categoryType(forIdentifier: .sleepAnalysis) else { return [] }
        let queryStart = Calendar.current.date(byAdding: .day, value: -1, to: start) ?? start
        let predicate = HKQuery.predicateForSamples(withStart: queryStart, end: end, options: [])
        let records: [HealthKitSleepRecord] = try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: HKObjectQueryNoLimit,
                sortDescriptors: nil) { _, values, error in
                if let error { continuation.resume(throwing: error); return }
                let records = (values as? [HKCategorySample] ?? []).map {
                    HealthKitSleepRecord(start: $0.startDate, end: $0.endDate, stage: $0.value,
                        source: $0.sourceRevision.source.bundleIdentifier)
                }
                continuation.resume(returning: records)
            }
            healthStore.execute(query)
        }
        return HealthKitSleepSummary.samples(from: records, start: start, end: end)
    }

    private static func readTypes() -> Set<HKObjectType> {
        [
            HKQuantityType.quantityType(forIdentifier: .heartRate),
            HKQuantityType.quantityType(forIdentifier: .bloodPressureSystolic),
            HKQuantityType.quantityType(forIdentifier: .bloodPressureDiastolic),
            HKQuantityType.quantityType(forIdentifier: .oxygenSaturation),
            HKQuantityType.quantityType(forIdentifier: .bodyTemperature),
            HKQuantityType.quantityType(forIdentifier: .bloodGlucose),
            HKQuantityType.quantityType(forIdentifier: .restingHeartRate),
            HKQuantityType.quantityType(forIdentifier: .stepCount),
            HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned),
            HKQuantityType.quantityType(forIdentifier: .appleExerciseTime),
            HKCategoryType.categoryType(forIdentifier: .sleepAnalysis)
        ]
        .compactMap { $0 }
        .reduce(into: Set<HKObjectType>()) { result, type in
            result.insert(type)
        }
    }

    private static func trendSignalDescriptors() -> [HealthKitSignalDescriptor] {
        [
            HealthKitSignalDescriptor(
                identifier: .heartRate,
                kind: .heartRate,
                unit: HKUnit.count().unitDivided(by: .minute()),
                displayUnit: "次/分"
            ),
            HealthKitSignalDescriptor(identifier: .restingHeartRate, kind: .restingHeartRate,
                unit: HKUnit.count().unitDivided(by: .minute()), displayUnit: "次/分钟"),
            HealthKitSignalDescriptor(
                identifier: .bloodPressureSystolic,
                kind: .bloodPressureSystolic,
                unit: .millimeterOfMercury(),
                displayUnit: "mmHg"
            ),
            HealthKitSignalDescriptor(
                identifier: .bloodPressureDiastolic,
                kind: .bloodPressureDiastolic,
                unit: .millimeterOfMercury(),
                displayUnit: "mmHg"
            ),
            HealthKitSignalDescriptor(
                identifier: .oxygenSaturation,
                kind: .bloodOxygen,
                unit: .percent(),
                displayUnit: "%",
                displayScale: 100
            ),
            HealthKitSignalDescriptor(
                identifier: .bodyTemperature,
                kind: .bodyTemperature,
                unit: .degreeCelsius(),
                displayUnit: "摄氏度"
            ),
            HealthKitSignalDescriptor(
                identifier: .bloodGlucose,
                kind: .bloodGlucose,
                unit: HKUnit.gramUnit(with: .milli).unitDivided(by: HKUnit.literUnit(with: .deci)),
                displayUnit: "mg/dL"
            )
        ]
    }
}

private struct HealthKitSignalDescriptor {
    let identifier: HKQuantityTypeIdentifier
    let kind: HealthSignalKind
    let unit: HKUnit
    let displayUnit: String
    var displayScale: Double = 1

    func displayValue(from rawValue: Double) -> Double {
        rawValue * displayScale
    }
}

private enum HealthKitAuthorizationError: LocalizedError {
    case requestNotCompleted

    var errorDescription: String? {
        "用户未授权 Apple 健康数据读取。"
    }
}

struct HealthKitRecentSummary {
    let sampleCount: Int
    let coveredDayCount: Int
    let metricSummaries: [HealthKitMetricSummary]
    let latestSample: HealthSignalSample?
    let refreshedAt: Date?

    init(samples: [HealthSignalSample], refreshedAt: Date?) {
        let calendar = Calendar.current
        sampleCount = samples.count
        coveredDayCount = Set(samples.map { calendar.startOfDay(for: $0.measuredAt) }).count
        latestSample = samples.max { $0.measuredAt < $1.measuredAt }
        self.refreshedAt = refreshedAt
        metricSummaries = Dictionary(grouping: samples, by: \.kind)
            .map { kind, kindSamples in
                HealthKitMetricSummary(kind: kind, samples: kindSamples)
            }
            .sorted { lhs, rhs in
                if lhs.latestMeasuredAt != rhs.latestMeasuredAt {
                    return lhs.latestMeasuredAt > rhs.latestMeasuredAt
                }
                return lhs.title < rhs.title
            }
    }

    var hasSamples: Bool {
        sampleCount > 0
    }

    var coverageText: String {
        guard hasSamples else {
            return "暂无近期样本"
        }
        return "\(coveredDayCount) 天 · \(sampleCount) 条"
    }

    var latestSampleText: String {
        guard let latestSample else {
            return "等待 Apple 健康样本"
        }
        return "\(latestSample.kind.displayTitle) \(HealthKitRecentSummary.valueText(for: latestSample))"
    }

    static func valueText(for sample: HealthSignalSample) -> String {
        let value = sample.value.formatted(.number.precision(.fractionLength(0...1)))
        return "\(value) \(sample.unit)"
    }
}

struct HealthKitMetricSummary: Identifiable {
    let id: String
    let kind: HealthSignalKind
    let sampleCount: Int
    let coveredDayCount: Int
    let latestValueText: String
    let unit: String
    let latestMeasuredAt: Date

    init(kind: HealthSignalKind, samples: [HealthSignalSample]) {
        let calendar = Calendar.current
        let latestSample = samples.max { $0.measuredAt < $1.measuredAt }
        self.kind = kind
        id = kind.rawValue
        sampleCount = samples.count
        coveredDayCount = Set(samples.map { calendar.startOfDay(for: $0.measuredAt) }).count
        latestValueText = latestSample.map(HealthKitRecentSummary.valueText(for:)) ?? "暂无"
        unit = latestSample?.unit ?? ""
        latestMeasuredAt = latestSample?.measuredAt ?? Date.distantPast
    }

    var title: String {
        kind.displayTitle
    }

    var symbolName: String {
        kind.displaySymbolName
    }
}

extension HealthSignalKind {
    var displayTitle: String {
        switch self {
        case .heartRate:
            "心率"
        case .restingHeartRate: "静息心率"
        case .stepCount: "每日步数"
        case .activeEnergy: "每日活动能量"
        case .exerciseMinutes: "每日运动时间"
        case .sleepDuration: "睡眠总时长"
        case .sleepCore: "核心睡眠"
        case .sleepDeep: "深度睡眠"
        case .sleepREM: "REM 睡眠"
        case .bloodPressureSystolic:
            "收缩压"
        case .bloodPressureDiastolic:
            "舒张压"
        case .bloodOxygen:
            "血氧"
        case .bodyTemperature:
            "体温"
        case .bloodGlucose:
            "血糖"
        case .unknown:
            "健康数据"
        }
    }

    var displaySymbolName: String {
        switch self {
        case .heartRate, .restingHeartRate:
            "heart.fill"
        case .stepCount: "figure.walk"
        case .activeEnergy: "flame.fill"
        case .exerciseMinutes: "figure.run"
        case .sleepDuration, .sleepCore, .sleepDeep, .sleepREM: "bed.double.fill"
        case .bloodPressureSystolic, .bloodPressureDiastolic:
            "waveform.path.ecg"
        case .bloodOxygen:
            "lungs.fill"
        case .bodyTemperature:
            "thermometer.medium"
        case .bloodGlucose:
            "drop.fill"
        case .unknown:
            "heart.text.square.fill"
        }
    }

}

struct HealthKitSleepRecord: Sendable {
    let start: Date
    let end: Date
    let stage: Int
    let source: String
}

enum HealthKitSleepSummary {
    // Noon-to-noon assigns an overnight sleep to the day it ends.
    static func samples(from records: [HealthKitSleepRecord], start: Date, end: Date,
                        calendar: Calendar = .current) -> [HealthSignalSample] {
        let asleep = Set([HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue,
                          HKCategoryValueSleepAnalysis.asleepCore.rawValue,
                          HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
                          HKCategoryValueSleepAnalysis.asleepREM.rawValue])
        let stages: [(HealthSignalKind, Int?)] = [
            (.sleepDuration, nil), (.sleepCore, HKCategoryValueSleepAnalysis.asleepCore.rawValue),
            (.sleepDeep, HKCategoryValueSleepAnalysis.asleepDeep.rawValue),
            (.sleepREM, HKCategoryValueSleepAnalysis.asleepREM.rawValue)
        ]
        var output: [HealthSignalSample] = []
        var day = calendar.startOfDay(for: start)
        while day <= end {
            guard let noon = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: day),
                  let previousNoon = calendar.date(byAdding: .day, value: -1, to: noon),
                  let nextDay = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            let windowEnd = min(noon, end)
            let matching = records.filter {
                asleep.contains($0.stage) && $0.end > $0.start && $0.end > previousNoon && $0.start < windowEnd
            }
            let bySource = Dictionary(grouping: matching, by: \.source)
            // Use one source per night, preferring stage-resolved data. Never add
            // overlapping records from different devices as separate sleep.
            let source = bySource.keys.sorted().max { left, right in
                func score(_ key: String) -> Double {
                    let values = bySource[key] ?? []
                    let detailed = values.filter { $0.stage != HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue }
                    return mergedSeconds(detailed.isEmpty ? values : detailed, start: previousNoon, end: windowEnd)
                        + (detailed.isEmpty ? 0 : 86400)
                }
                return score(left) < score(right)
            }
            if let source, let selected = bySource[source] {
                for (kind, stage) in stages {
                    let values = stage.map { value in selected.filter { $0.stage == value } } ?? selected
                    let seconds = mergedSeconds(values, start: previousNoon, end: windowEnd)
                    if seconds > 0 {
                        output.append(.init(kind: kind, measuredAt: windowEnd, value: seconds / 3600, unit: "小时"))
                    }
                }
            }
            day = nextDay
        }
        return output
    }

    private static func mergedSeconds(_ records: [HealthKitSleepRecord], start: Date, end: Date) -> Double {
        let intervals = records.compactMap { record -> DateInterval? in
            let lower = max(record.start, start), upper = min(record.end, end)
            return upper > lower ? DateInterval(start: lower, end: upper) : nil
        }.sorted { $0.start < $1.start }
        var current: DateInterval?
        var total: Double = 0
        for interval in intervals {
            if let previous = current {
                if interval.start <= previous.end {
                    current = DateInterval(start: previous.start, end: max(previous.end, interval.end))
                } else {
                    total += previous.duration
                    current = interval
                }
            } else { current = interval }
        }
        return total + (current?.duration ?? 0)
    }
}

/// One shared projection for the chart and AI. Each day ends a noon-to-noon window.
struct MedicationSleepDay: Identifiable, Sendable {
    var id: Date { date }
    let date: Date
    let sleepHours: Double?
    let medicationRecords: [String]
    let medicationContext: [String]
    let actualDoseCount: Int
}

struct MedicationSleepReview: Sendable {
    let days: [MedicationSleepDay]
    let timeZoneIdentifier: String

    @MainActor
    init(samples: [HealthSignalSample], tasks: [StoredDoseTask], medications: [StoredMedication],
         dayCount: Int, now: Date = Date(), calendar: Calendar = .current) {
        timeZoneIdentifier = calendar.timeZone.identifier
        let names = Dictionary(medications.map { ($0.id, $0.displayName) }, uniquingKeysWith: { first, _ in first })
        let logical = Dictionary(grouping: tasks.adherenceMeasurableTasks, by: DoseLogicalGroup.key(for:))
        let uniqueTasks = logical.values.compactMap { group in
            group.max { ($0.recordedAt ?? .distantPast) < ($1.recordedAt ?? .distantPast) }
        }
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "MM-dd HH:mm"
        let today = calendar.startOfDay(for: now)
        days = (0..<dayCount).compactMap { index in
            guard let date = calendar.date(byAdding: .day, value: index + 1 - dayCount, to: today),
                  let noon = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: date),
                  let start = calendar.date(byAdding: .day, value: -1, to: noon) else { return nil }
            let sleep = samples.filter { $0.kind == .sleepDuration && calendar.isDate($0.measuredAt, inSameDayAs: date) }
                .max { $0.measuredAt < $1.measuredAt }?.value
            let matching = uniqueTasks.filter { task in
                let time = task.status == .taken ? (task.recordedAt ?? task.dueAt) : task.dueAt
                return time >= start && time < min(noon, now)
            }.sorted { ($0.recordedAt ?? $0.dueAt) < ($1.recordedAt ?? $1.dueAt) }
            let records = matching.map { task in
                let name = names[task.medicationID] ?? "未命名药品"
                let planTime = task.dueAt.formatted(date: .abbreviated, time: .shortened)
                let actual = task.recordedAt.map { $0.formatted(date: .abbreviated, time: .shortened) } ?? "未记录时间"
                switch task.status {
                case .taken:
                    let recorded = task.recordedAt == nil ? "实际时间未知，按计划窗口展示" : actual
                    return "\(name) \(task.doseValue.formatted())\(task.doseUnit)，已记录服用 \(recorded)（计划 \(planTime)）"
                case .skipped: return "\(name)，已忽略（计划 \(planTime)）"
                case .delayed: return "\(name)，稍后/待确认（计划 \(planTime)）"
                default: return "\(name)，未确认（计划 \(planTime)）"
                }
            }
            let compact = matching.map { task in
                let name = names[task.medicationID] ?? "未命名药品"
                let referenceTime = task.status == .taken ? (task.recordedAt ?? task.dueAt) : task.dueAt
                let time = formatter.string(from: referenceTime)
                let state = task.status == .taken ? (task.recordedAt == nil ? "已服/实际时间未知/计划" : "已服/实际") : "\(task.status.rawValue)/计划"
                return "\(name)\(task.doseValue.formatted())\(task.doseUnit) \(state)\(time)"
            }
            return MedicationSleepDay(date: date, sleepHours: sleep, medicationRecords: records, medicationContext: compact,
                actualDoseCount: matching.filter { $0.status == .taken && $0.recordedAt != nil }.count)
        }
    }

    var sleepSummary: String {
        let middle = days.count / 2
        func median(_ values: [Double]) -> Double? {
            let sorted = values.sorted()
            guard !sorted.isEmpty else { return nil }
            let center = sorted.count / 2
            return sorted.count.isMultiple(of: 2) ? (sorted[center - 1] + sorted[center]) / 2 : sorted[center]
        }
        func label(_ value: Double?) -> String {
            value.map { $0.formatted(.number.precision(.fractionLength(1))) + "小时" } ?? "暂无记录"
        }
        let first = median(days.prefix(middle).compactMap(\.sleepHours))
        let second = median(days.dropFirst(middle).compactMap(\.sleepHours))
        var change = "两段记录不足，暂不能比较。"
        if let first, let second {
            let difference = second - first
            change = abs(difference) < 0.05 ? "两段中位数基本相同。"
                : "后半段较前半段\(difference > 0 ? "增加" : "减少") \(abs(difference).formatted(.number.precision(.fractionLength(1)))) 小时。"
        }
        return "睡眠有记录 \(days.compactMap(\.sleepHours).count)/\(days.count) 天；前半段中位数 \(label(first))，后半段中位数 \(label(second))。\(change)"
    }

    var localContext: String {
        let rows = days.map { day in
            let sleep = day.sleepHours.map { $0.formatted(.number.precision(.fractionLength(1))) + "h" } ?? "缺记录"
            return "\(day.date.formatted(.dateTime.month(.twoDigits).day(.twoDigits))) 睡眠\(sleep)，实际服用记录\(day.actualDoseCount)次"
        }
        return sleepSummary + "\n按睡眠结束日对齐的端侧汇总：\n" + rows.joined(separator: "\n")
            + "\n服用次数是所有已授权药品的合计，不能据此归因到某一种药；单药具体时序见用药与睡眠页。"
    }

    var context: String {
        let rows = days.map { day in
            let sleep = day.sleepHours.map { $0.formatted(.number.precision(.fractionLength(1))) + "小时" } ?? "未读取到睡眠记录"
            return "\(day.date.formatted(date: .numeric, time: .omitted))：睡眠 \(sleep)；同期用药：\(day.medicationContext.isEmpty ? "暂无已授权记录" : day.medicationContext.joined(separator: "；"))"
        }
        return "时区 \(timeZoneIdentifier)。按结束日归属，每个观察窗口为前日中午到当日中午。未确认/忽略不能视为已服药。\n\(sleepSummary)\n" + rows.joined(separator: "\n")
    }
}
