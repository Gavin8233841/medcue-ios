import Foundation
import Combine
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
    @Published private(set) var evidenceBundle: HealthEvidenceBundle?
    private var evidenceSnapshot = HealthEvidenceSnapshot()
    private var evidenceConnectionRevision: String?
    private var evidenceWindows: [Int: HealthEvidenceBundle] = [:]
    private(set) var evidenceRevision: String?
    private var disconnectObserver: AnyCancellable?
    private var activeReads: [UUID: HealthKitReadOperation] = [:]
    @Published private(set) var lastSampleRefreshAt: Date?
    @Published private(set) var supportedReadTypesSummary = "睡眠、静息心率、心率变异性、呼吸频率、心率、血压、血氧、体温、血糖"

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
        disconnectObserver = NotificationCenter.default.publisher(for: .medcueHealthDisconnected)
            .sink { [weak self] notification in
                let revision = notification.object as? String
                Task { @MainActor in
                    guard let self, revision == HealthConnectionPolicy.revision(defaults: self.defaults),
                          !self.defaults.bool(forKey: Self.completionKey) else { return }
                    self.clearHealthSnapshot()
                }
            }
    }

    @discardableResult
    func requestAuthorizationEntry() async -> Bool {
        guard !Task.isCancelled else { return false }
        guard HKHealthStore.isHealthDataAvailable() else {
            statusMessage = "当前设备不支持 Apple 健康数据读取"
            return false
        }

        let readTypes = Self.readTypes()
        guard !readTypes.isEmpty else {
            statusMessage = "当前系统没有可读取的 Apple 健康指标类型"
            return false
        }

        evidenceSnapshot.reconnect()
        let authorizationEpoch = evidenceSnapshot.beginRefresh()
        let connectionRevision = HealthConnectionPolicy.revision(defaults: defaults)
        do {
            try await requestAuthorization(readTypes: readTypes)
            guard evidenceSnapshot.epoch == authorizationEpoch, evidenceSnapshot.isEnabled,
                  HealthConnectionPolicy.revision(defaults: defaults) == connectionRevision,
                  !Task.isCancelled else { return false }
            markAuthorizationRequestCompleted()
            statusMessage = "已完成 Apple 健康授权请求。仅在用户授权范围内读取生命体征，用于趋势和复诊资料。"
            await refreshRecentTrendSamples()
            return true
        } catch {
            guard !Task.isCancelled, evidenceSnapshot.epoch == authorizationEpoch,
                  HealthConnectionPolicy.revision(defaults: defaults) == connectionRevision else { return false }
            statusMessage = "Apple 健康授权暂时无法完成，请稍后重试或前往系统隐私设置检查。"
            return false
        }
    }

    func refreshRecentTrendSamples() async {
        await refreshRecentTrendSamples(days: HealthContextPolicy.default.trendLookbackDays)
    }

    func refreshRecentTrendSamples(days: Int) async {
        guard !Task.isCancelled else { return }
        guard HKHealthStore.isHealthDataAvailable() else {
            recentTrendSamples = []
            evidenceBundle = nil
            statusMessage = "当前设备不支持 Apple 健康数据读取"
            return
        }

        guard defaults.bool(forKey: Self.completionKey) else {
            recentTrendSamples = []
            evidenceBundle = nil
            statusMessage = "尚未完成 Apple 健康授权请求"
            return
        }

        if !evidenceSnapshot.isEnabled { evidenceSnapshot.reconnect() }
        hasCompletedAuthorizationRequest = true
        let epoch = evidenceSnapshot.beginRefresh()
        let snapshotRevision = HealthAISharingPolicy.invalidateSnapshot(defaults: defaults)
        let connectionRevision = HealthConnectionPolicy.revision(defaults: defaults)
        // Clear stale facts before suspending; failed/empty reads cannot reuse them.
        evidenceBundle = nil
        evidenceWindows = [:]
        evidenceRevision = nil
        recentTrendSamples = []
        statusMessage = "正在读取健康记录…"
        let end = Date()
        let calendar = Calendar.current
        let start = calendar.date(byAdding: .day, value: -min(56, max(1, days)),
                                  to: calendar.startOfDay(for: end)) ?? end
        let trend = await fetchTrendSamples(days: min(56, max(1, days)))
        let samples = trend.samples
        let evidence = await fetchEvidenceSamples(start: start, end: end)
        let windows = await Task.detached(priority: .utility) {
            var windows: [Int: HealthEvidenceBundle] = [:]
            for lookback in [7, 30, 56] {
                let windowStart = calendar.date(byAdding: .day, value: -lookback,
                                                to: calendar.startOfDay(for: end)) ?? start
                windows[lookback] = HealthEvidenceBuilder().build(samples: evidence.samples,
                    start: max(start, windowStart), end: end, timeZone: calendar.timeZone,
                    generatedAt: end, failedMetrics: evidence.failed, budgetExceededMetrics: evidence.overflow)
            }
            return windows
        }.value
        guard !Task.isCancelled,
              HealthConnectionPolicy.isCurrent(connectionRevision, defaults: defaults),
              HealthAISharingPolicy.snapshotRevision(defaults: defaults) == snapshotRevision,
              evidenceSnapshot.replace(evidence.samples, epoch: epoch) else {
            if evidenceSnapshot.epoch == epoch,
               HealthConnectionPolicy.isCurrent(connectionRevision, defaults: defaults) {
                statusMessage = "本次读取已取消或被其他页面更新，请刷新当前回顾。"
            }
            return
        }
        recentTrendSamples = samples
        evidenceConnectionRevision = connectionRevision
        evidenceRevision = snapshotRevision
        evidenceWindows = windows
        lastSampleRefreshAt = Date()
        evidenceBundle = windows[56]
        if trend.overflowCount > 0 || !evidence.overflow.isEmpty {
            statusMessage = "部分指标记录超过读取预算，已排除这些指标；可选择较短范围重试。"
        } else {
            statusMessage = samples.isEmpty && evidence.samples.isEmpty
                ? "已完成授权请求；当前没有可读取的近期健康数据。"
                : "已读取 \(samples.count + evidence.samples.count) 条近期健康记录。"
        }
    }

    var recentSummary: HealthKitRecentSummary {
        HealthKitRecentSummary(samples: recentTrendSamples, refreshedAt: lastSampleRefreshAt)
    }

    func evidence(for question: String) -> HealthEvidenceBundle? {
        guard let revision = evidenceConnectionRevision,
              HealthConnectionPolicy.isCurrent(revision, defaults: defaults),
              evidenceRevision == HealthAISharingPolicy.snapshotRevision(defaults: defaults) else { return nil }
        return evidenceWindows[HealthEvidenceLocalReview.lookbackDays(in: question)]
    }

    func disconnectAndClear() {
        HealthConnectionPolicy.setConnected(false, defaults: defaults)
        HealthAISharingPolicy.revoke(defaults: defaults)
        _ = HealthAISharingPolicy.invalidateSnapshot(defaults: defaults)
        clearHealthSnapshot()
        NotificationCenter.default.post(name: .medcueHealthDisconnected,
                                        object: HealthConnectionPolicy.revision(defaults: defaults))
    }

    private func clearHealthSnapshot() {
        for operation in activeReads.values { operation.cancel() }
        activeReads = [:]
        evidenceSnapshot.disconnect()
        evidenceConnectionRevision = nil
        evidenceRevision = nil
        evidenceWindows = [:]
        recentTrendSamples = []
        evidenceBundle = nil
        lastSampleRefreshAt = nil
        hasCompletedAuthorizationRequest = false
        statusMessage = "已停止读取并清除本次健康回顾；Apple 健康原始记录未更改。"
    }

    private func fetchEvidenceSamples(start: Date, end: Date) async
        -> (samples: [HealthEvidenceSample], failed: Set<HealthEvidenceMetric>, overflow: Set<HealthEvidenceMetric>) {
        let connectionRevision = HealthConnectionPolicy.revision(defaults: defaults)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: [])
        var result: [HealthEvidenceSample] = []
        var failed = Set<HealthEvidenceMetric>()
        var overflow = Set<HealthEvidenceMetric>()
        let descriptors: [(HealthEvidenceMetric, HKQuantityTypeIdentifier, HKUnit)] = [
            (.restingHeartRate, .restingHeartRate, HKUnit.count().unitDivided(by: .minute())),
            (.hrvSDNN, .heartRateVariabilitySDNN, HKUnit.secondUnit(with: .milli)),
            (.respiratoryRate, .respiratoryRate, HKUnit.count().unitDivided(by: .minute()))
        ]
        for (metric, identifier, unit) in descriptors {
            if Task.isCancelled || !HealthConnectionPolicy.isCurrent(connectionRevision, defaults: defaults) { return ([], Set(HealthEvidenceMetric.allCases), []) }
            guard let type = HKQuantityType.quantityType(forIdentifier: identifier) else {
                failed.insert(metric); continue
            }
            do {
                let samples = try await queryQuantitySamples(type: type, predicate: predicate, limit: HealthReadBudget.quantitySamples + 1)
                guard HealthReadBudget.accepts(count: samples.count, limit: HealthReadBudget.quantitySamples) else {
                    overflow.insert(metric); continue
                }
                result += samples.map { sample in
                    HealthEvidenceSample(id: sample.uuid, metric: metric, start: sample.startDate,
                        end: sample.endDate, value: sample.quantity.doubleValue(for: unit), unit: metric.unit,
                        sourceID: Self.evidenceSourceID(sample),
                        sourceName: sample.sourceRevision.source.name,
                        timeZoneIdentifier: sample.metadata?[HKMetadataKeyTimeZone] as? String,
                        sourceVersion: sample.sourceRevision.version, deviceModel: sample.device?.model)
                }
            } catch { failed.insert(metric) }
        }
        if Task.isCancelled || !HealthConnectionPolicy.isCurrent(connectionRevision, defaults: defaults) { return ([], Set(HealthEvidenceMetric.allCases), []) }
        if let type = HKCategoryType.categoryType(forIdentifier: .sleepAnalysis) {
            do {
                let samples = try await querySamples(type: type, predicate: predicate, limit: HealthReadBudget.sleepSamples + 1)
                    .compactMap { $0 as? HKCategorySample }
                if !HealthReadBudget.accepts(count: samples.count, limit: HealthReadBudget.sleepSamples) {
                    overflow.insert(.sleep)
                }
                for sample in overflow.contains(.sleep) ? [] : samples {
                    let state: HealthSleepState
                    switch sample.value {
                    case HKCategoryValueSleepAnalysis.inBed.rawValue: state = .inBed
                    case HKCategoryValueSleepAnalysis.awake.rawValue: state = .awake
                    case HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue: state = .asleep
                    case HKCategoryValueSleepAnalysis.asleepCore.rawValue: state = .core
                    case HKCategoryValueSleepAnalysis.asleepDeep.rawValue: state = .deep
                    case HKCategoryValueSleepAnalysis.asleepREM.rawValue: state = .rem
                    default: continue
                    }
                    result.append(HealthEvidenceSample(id: sample.uuid, metric: .sleep,
                        start: sample.startDate, end: sample.endDate, value: 0, unit: HealthEvidenceMetric.sleep.unit,
                        sourceID: Self.evidenceSourceID(sample),
                        sourceName: sample.sourceRevision.source.name,
                        timeZoneIdentifier: sample.metadata?[HKMetadataKeyTimeZone] as? String, sleepState: state,
                        sourceVersion: sample.sourceRevision.version, deviceModel: sample.device?.model))
                }
            } catch { failed.insert(.sleep) }
        } else { failed.insert(.sleep) }
        return (result, failed, overflow)
    }

    private static func evidenceSourceID(_ sample: HKSample) -> String {
        // Keep model/source versions distinct without collecting serial numbers.
        [sample.sourceRevision.source.bundleIdentifier, sample.sourceRevision.version ?? "unknown",
         sample.sourceRevision.productType ?? sample.device?.model ?? "unknown"].joined(separator: "|")
    }

    private func markAuthorizationRequestCompleted() {
        hasCompletedAuthorizationRequest = true
        HealthConnectionPolicy.setConnected(true, defaults: defaults)
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

    private func fetchTrendSamples(days: Int) async -> (samples: [HealthSignalSample], overflowCount: Int) {
        let connectionRevision = HealthConnectionPolicy.revision(defaults: defaults)
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
        var overflowCount = 0

        for descriptor in Self.trendSignalDescriptors() {
            if Task.isCancelled || !HealthConnectionPolicy.isCurrent(connectionRevision, defaults: defaults) { return ([], 0) }
            guard let quantityType = HKQuantityType.quantityType(forIdentifier: descriptor.identifier) else {
                continue
            }
            do {
                let quantitySamples = try await queryQuantitySamples(
                    type: quantityType,
                    predicate: predicate,
                    limit: HealthReadBudget.quantitySamples + 1
                )
                guard HealthReadBudget.accepts(count: quantitySamples.count, limit: HealthReadBudget.quantitySamples) else {
                    overflowCount += 1; continue
                }
                samples.append(
                    contentsOf: quantitySamples.map { sample in
                        let rawValue = sample.quantity.doubleValue(for: descriptor.unit)
                        return HealthSignalSample(
                            id: sample.uuid,
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

        return (samples.sorted { $0.measuredAt < $1.measuredAt }, overflowCount)
    }

    private func queryQuantitySamples(
        type: HKQuantityType,
        predicate: NSPredicate,
        limit: Int
    ) async throws -> [HKQuantitySample] {
        try await querySamples(type: type, predicate: predicate, limit: limit)
            .compactMap { $0 as? HKQuantitySample }
    }

    private func querySamples(type: HKSampleType, predicate: NSPredicate, limit: Int) async throws -> [HKSample] {
        try Task.checkCancellation()
        let id = UUID()
        let operation = HealthKitReadOperation(store: healthStore)
        activeReads[id] = operation
        defer { activeReads.removeValue(forKey: id) }
        return try await operation.read(type: type, predicate: predicate, limit: limit)
    }

    private static func readTypes() -> Set<HKObjectType> {
        [
            HKCategoryType.categoryType(forIdentifier: .sleepAnalysis),
            HKQuantityType.quantityType(forIdentifier: .restingHeartRate),
            HKQuantityType.quantityType(forIdentifier: .heartRateVariabilitySDNN),
            HKQuantityType.quantityType(forIdentifier: .respiratoryRate),
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

// Independent of the existing medication-sharing consent. No cloud rollout is enabled.
@MainActor
enum HealthAISharingPolicy {
    static let allowedKey = "healthAI.localSummaryAllowed.v1"
    static let revisionKey = "healthAI.consentRevision.v1"
    static let cloudHealthSharingEnabled = false
    static let snapshotRevisionKey = "healthAI.snapshotRevision.v1"
    static func snapshotRevision(defaults: UserDefaults = .standard) -> String {
        defaults.string(forKey: snapshotRevisionKey) ?? "unread"
    }
    static func invalidateSnapshot(defaults: UserDefaults = .standard) -> String {
        let revision = UUID().uuidString
        defaults.set(revision, forKey: snapshotRevisionKey)
        NotificationCenter.default.post(name: .medcueHealthEvidenceChanged, object: nil)
        return revision
    }

    static func allowsLocalSummary(defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: allowedKey)
    }
    static func revision(defaults: UserDefaults = .standard) -> String {
        defaults.string(forKey: revisionKey) ?? "not-granted"
    }
    static func setAllowed(_ allowed: Bool, defaults: UserDefaults = .standard) {
        defaults.set(allowed, forKey: allowedKey)
        defaults.set(UUID().uuidString, forKey: revisionKey)
        NotificationCenter.default.post(name: .medcueHealthAIConsentChanged, object: nil)
    }
    static func revoke(defaults: UserDefaults = .standard) { setAllowed(false, defaults: defaults) }
}

extension Notification.Name {
    static let medcueHealthEvidenceChanged = Notification.Name("medcue.health.evidenceChanged")
    static let medcueAIConsentChanged = Notification.Name("medcue.ai.consentChanged")
    static let medcueHealthDisconnected = Notification.Name("medcue.health.disconnected")
    static let medcueHealthAIConsentChanged = Notification.Name("medcue.health.aiConsentChanged")
}


/// Shared across service instances. A bool alone cannot reject a disconnect /
/// reconnect ABA race while an older HealthKit query is still in flight.
@MainActor
enum HealthConnectionPolicy {
    static let completionKey = "hasCompletedHealthKitAuthorizationRequest"
    static let revisionKey = "health.connectionRevision.v1"
    static func revision(defaults: UserDefaults = .standard) -> String {
        defaults.string(forKey: revisionKey) ?? "initial"
    }
    static func setConnected(_ connected: Bool, defaults: UserDefaults = .standard) {
        defaults.set(UUID().uuidString, forKey: revisionKey)
        defaults.set(connected, forKey: completionKey)
    }
    static func isCurrent(_ capturedRevision: String, defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: completionKey) && revision(defaults: defaults) == capturedRevision
    }
}


/// HealthKit callbacks and task cancellation may race. The lock owns exactly one
/// continuation completion; cancellation also stops the OS query, not just its UI.
private final class HealthKitReadOperation: @unchecked Sendable {
    private let store: HKHealthStore
    private let lock = NSLock()
    private var continuation: CheckedContinuation<[HKSample], Error>?
    private var query: HKQuery?
    private var finished = false
    private var cancelled = false

    init(store: HKHealthStore) { self.store = store }

    // Query construction stays on the caller's main actor. NSPredicate is not
    // Sendable; only HealthKit's callback and the locked completion state cross threads.
    @MainActor
    func read(type: HKSampleType, predicate: NSPredicate, limit: Int) async throws -> [HKSample] {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: limit,
                    sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)]) {
                        [weak self] _, samples, error in
                        if let error { self?.finish(.failure(error)) }
                        else { self?.finish(.success(samples ?? [])) }
                    }
                start(query, continuation: continuation)
            }
        } onCancel: {
            self.cancel()
        }
    }

    private func start(_ query: HKQuery, continuation: CheckedContinuation<[HKSample], Error>) {
        lock.lock()
        if finished {
            lock.unlock(); continuation.resume(throwing: CancellationError()); return
        }
        self.query = query; self.continuation = continuation
        lock.unlock()
        store.execute(query)
        lock.lock(); let shouldStop = cancelled; lock.unlock()
        if shouldStop { store.stop(query) }
    }

    private func finish(_ result: Result<[HKSample], Error>) {
        lock.lock()
        guard !finished else { lock.unlock(); return }
        finished = true
        let continuation = self.continuation
        self.continuation = nil; query = nil
        lock.unlock()
        continuation?.resume(with: result)
    }

    func cancel() {
        lock.lock()
        guard !finished else { lock.unlock(); return }
        finished = true; cancelled = true
        let query = self.query; let continuation = self.continuation
        self.query = nil; self.continuation = nil
        lock.unlock()
        if let query { store.stop(query) }
        continuation?.resume(throwing: CancellationError())
    }
}
