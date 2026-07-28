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
    @Published private(set) var supportedReadTypesSummary = "心率、血压、血氧、体温、血糖"

    private static let completionKey = "hasCompletedHealthKitAuthorizationRequest"
    private let healthStore = HKHealthStore()
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let hasCompleted = defaults.bool(forKey: Self.completionKey)
        hasCompletedAuthorizationRequest = hasCompleted
        statusMessage = hasCompleted
            ? "已完成 Apple 健康授权请求。仅在用户授权范围内读取生命体征。"
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
            statusMessage = "已完成 Apple 健康授权请求。仅在用户授权范围内读取生命体征，用于趋势和复诊资料。"
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

    func refreshRecentTrendSamples(days: Int) async {
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

        let samples = await fetchTrendSamples(days: days)
        recentTrendSamples = samples
        lastSampleRefreshAt = Date()
        statusMessage = samples.isEmpty
            ? "已完成授权请求；当前没有可读取的近期生命体征数据。"
            : "已读取 \(samples.count) 条近期生命体征数据。"
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

    private static func readTypes() -> Set<HKObjectType> {
        [
            HKQuantityType.quantityType(forIdentifier: .heartRate),
            HKQuantityType.quantityType(forIdentifier: .bloodPressureSystolic),
            HKQuantityType.quantityType(forIdentifier: .bloodPressureDiastolic),
            HKQuantityType.quantityType(forIdentifier: .oxygenSaturation),
            HKQuantityType.quantityType(forIdentifier: .bodyTemperature),
            HKQuantityType.quantityType(forIdentifier: .bloodGlucose)
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
    let latestMeasuredAt: Date

    init(kind: HealthSignalKind, samples: [HealthSignalSample]) {
        let calendar = Calendar.current
        let latestSample = samples.max { $0.measuredAt < $1.measuredAt }
        self.kind = kind
        id = kind.rawValue
        sampleCount = samples.count
        coveredDayCount = Set(samples.map { calendar.startOfDay(for: $0.measuredAt) }).count
        latestValueText = latestSample.map(HealthKitRecentSummary.valueText(for:)) ?? "暂无"
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
        case .heartRate:
            "heart.fill"
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
