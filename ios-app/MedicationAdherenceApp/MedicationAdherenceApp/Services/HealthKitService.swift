import Foundation
import HealthKit

@MainActor
final class HealthKitService: ObservableObject {
    @Published private(set) var statusMessage: String
    @Published private(set) var hasCompletedAuthorizationRequest: Bool
    @Published private(set) var supportedReadTypesSummary = "心率、血压、血氧、体温、血糖"

    private static let completionKey = "hasCompletedHealthKitAuthorizationRequest"
    private let healthStore = HKHealthStore()
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let hasCompleted = defaults.bool(forKey: Self.completionKey)
        hasCompletedAuthorizationRequest = hasCompleted
        statusMessage = hasCompleted
            ? "已完成 HealthKit 授权请求。仅在用户授权范围内读取生命体征。"
            : "HealthKit 尚未授权"
    }

    func requestAuthorizationEntry() async {
        guard HKHealthStore.isHealthDataAvailable() else {
            statusMessage = "当前设备不支持 HealthKit 数据读取"
            return
        }

        let readTypes = Self.readTypes()
        guard !readTypes.isEmpty else {
            statusMessage = "当前系统没有可读取的 HealthKit 指标类型"
            return
        }

        do {
            try await requestAuthorization(readTypes: readTypes)
            markAuthorizationRequestCompleted()
            statusMessage = "已完成 HealthKit 授权请求。仅在用户授权范围内读取生命体征，并用于用药相关风险提示。"
        } catch {
            statusMessage = "HealthKit 授权失败：\(error.localizedDescription)"
        }
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
                    continuation.resume(throwing: HealthKitAuthorizationError.requestDenied)
                }
            }
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
}

private enum HealthKitAuthorizationError: LocalizedError {
    case requestDenied

    var errorDescription: String? {
        "用户未授权 HealthKit 数据读取。"
    }
}
