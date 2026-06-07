import CoreLocation
import Foundation
import WeatherKit

struct WeatherMedicationHint: Identifiable, Equatable {
    let id: String
    let iconName: String
    let title: String
    let message: String
    let sourceSummary: String
    let tintName: String
}

@MainActor
final class WeatherMedicationService: NSObject, ObservableObject {
    @Published private(set) var hints: [WeatherMedicationHint] = []
    @Published private(set) var statusText = "正在准备今日环境关注。"
    @Published private(set) var isLoading = false
    @Published private(set) var shouldShowAuthorizationButton = false

    private let locationManager = CLLocationManager()
    private var locationContinuation: CheckedContinuation<CLLocation?, Never>?

    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyThreeKilometers
    }

    func refresh(medications: [StoredMedication], requestAuthorization: Bool = false) async {
        isLoading = true
        defer { isLoading = false }

        let location = await currentLocation(requestAuthorization: requestAuthorization)
        guard let location else {
            hints = Self.fallbackHints(for: medications)
            shouldShowAuthorizationButton = locationManager.authorizationStatus == .notDetermined
            statusText = shouldShowAuthorizationButton
                ? "允许后可结合当前位置天气生成今日提醒；当前显示本地通用提醒。"
                : "未获取位置或天气授权，已显示本地通用提醒。"
            return
        }

        do {
            let weather = try await WeatherService.shared.weather(for: location)
            let context = WeatherMedicationContext(
                temperatureCelsius: weather.currentWeather.temperature.converted(to: .celsius).value,
                humidity: weather.currentWeather.humidity,
                precipitationChance: weather.dailyForecast.forecast.first?.precipitationChance ?? 0,
                uvIndexCategory: weather.currentWeather.uvIndex.category.rawValue
            )
            hints = Self.hints(for: medications, context: context)
            statusText = "已结合今日天气和本机药品记录生成提醒。"
            shouldShowAuthorizationButton = false
        } catch {
            hints = Self.fallbackHints(for: medications)
            statusText = "天气数据暂不可用，已显示本地通用提醒。"
            shouldShowAuthorizationButton = false
        }
    }

    private func currentLocation(requestAuthorization: Bool) async -> CLLocation? {
        switch locationManager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            return await requestSingleLocation()
        case .notDetermined:
            return requestAuthorization ? await requestLocationAfterAuthorization() : nil
        case .denied, .restricted:
            return nil
        @unknown default:
            return nil
        }
    }

    private func requestSingleLocation() async -> CLLocation? {
        if let location = locationManager.location {
            return location
        }
        return await withCheckedContinuation { continuation in
            locationContinuation = continuation
            locationManager.requestLocation()
        }
    }

    private func requestLocationAfterAuthorization() async -> CLLocation? {
        await withCheckedContinuation { continuation in
            locationContinuation = continuation
            locationManager.requestWhenInUseAuthorization()
        }
    }

    private func resumeLocation(_ location: CLLocation?) {
        locationContinuation?.resume(returning: location)
        locationContinuation = nil
    }
}

extension WeatherMedicationService: CLLocationManagerDelegate {
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor in
            resumeLocation(locations.last)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            resumeLocation(nil)
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            switch manager.authorizationStatus {
            case .authorizedAlways, .authorizedWhenInUse:
                manager.requestLocation()
            case .denied, .restricted:
                resumeLocation(nil)
            case .notDetermined:
                break
            @unknown default:
                resumeLocation(nil)
            }
        }
    }
}

private struct WeatherMedicationContext {
    let temperatureCelsius: Double
    let humidity: Double
    let precipitationChance: Double
    let uvIndexCategory: String
}

private extension WeatherMedicationService {
    static func hints(for medications: [StoredMedication], context: WeatherMedicationContext) -> [WeatherMedicationHint] {
        var generated: [WeatherMedicationHint] = []
        let source = sourceSummary(for: context)

        if context.humidity < 0.35, medications.contains(where: isEyeOrDrynessRelated) {
            generated.append(WeatherMedicationHint(
                id: "dry-eye",
                iconName: "humidity.fill",
                title: "干燥环境关注",
                message: "今日湿度偏低，滴眼类或干燥相关用药可按既定计划核对使用，并留意不适时咨询医生或药师。",
                sourceSummary: source,
                tintName: "blue"
            ))
        }

        if context.precipitationChance >= 0.45 {
            generated.append(WeatherMedicationHint(
                id: "rain-carry",
                iconName: "cloud.rain.fill",
                title: "外出携药关注",
                message: "今日降水概率较高，外出前可核对随身药品和提醒时间，避免因行程变化漏记。",
                sourceSummary: source,
                tintName: "teal"
            ))
        }

        if context.temperatureCelsius >= 32 {
            generated.append(WeatherMedicationHint(
                id: "hot-storage",
                iconName: "thermometer.sun.fill",
                title: "高温保存关注",
                message: "今日气温较高，请按药盒或说明书核对避光、密封、冷藏等保存要求，异常情况咨询医生或药师。",
                sourceSummary: source,
                tintName: "orange"
            ))
        } else if context.temperatureCelsius <= 5 {
            generated.append(WeatherMedicationHint(
                id: "cold-routine",
                iconName: "thermometer.snowflake",
                title: "低温出行关注",
                message: "今日气温较低，外出和晚间提醒可提前核对，慢病或长期用药不适时请咨询医生或药师。",
                sourceSummary: source,
                tintName: "indigo"
            ))
        }

        if context.uvIndexCategory == "high" || context.uvIndexCategory == "veryHigh" || context.uvIndexCategory == "extreme" {
            generated.append(WeatherMedicationHint(
                id: "uv-sun",
                iconName: "sun.max.fill",
                title: "日晒环境关注",
                message: "今日紫外线较强，如药品说明书提示光敏或避光保存，请按原文核对并做好防晒。",
                sourceSummary: source,
                tintName: "yellow"
            ))
        }

        if generated.isEmpty {
            generated.append(WeatherMedicationHint(
                id: "steady-routine",
                iconName: "cloud.sun.fill",
                title: "今日环境平稳",
                message: "今日天气暂未触发特别关注，继续按已确认计划记录用药；如有不适请咨询医生或药师。",
                sourceSummary: source,
                tintName: "green"
            ))
        }

        return Array(generated.prefix(3))
    }

    static func fallbackHints(for medications: [StoredMedication]) -> [WeatherMedicationHint] {
        var hints = [
            WeatherMedicationHint(
                id: "fallback-routine",
                iconName: "clock.badge.checkmark",
                title: "固定节奏关注",
                message: "天气数据不可用时，仍可按今日提醒核对药品、剂量和实际记录。",
                sourceSummary: "本地通用规则",
                tintName: "blue"
            )
        ]
        if medications.contains(where: isEyeOrDrynessRelated) {
            hints.append(WeatherMedicationHint(
                id: "fallback-eye",
                iconName: "eye.fill",
                title: "滴眼类用药关注",
                message: "滴眼类药品请按说明书或医生、药师建议核对使用间隔，避免漏记。",
                sourceSummary: "本地药品信息",
                tintName: "teal"
            ))
        }
        return hints
    }

    static func isEyeOrDrynessRelated(_ medication: StoredMedication) -> Bool {
        let text = "\(medication.displayName) \(medication.genericName) \(medication.form) \(medication.notes)".lowercased()
        return text.contains("滴眼") || text.contains("眼") || text.contains("tear") || text.contains("dry")
    }

    static func sourceSummary(for context: WeatherMedicationContext) -> String {
        let temperature = Int(context.temperatureCelsius.rounded())
        let humidity = Int((context.humidity * 100).rounded())
        let rain = Int((context.precipitationChance * 100).rounded())
        return "\(temperature)°C · 湿度 \(humidity)% · 降水 \(rain)%"
    }
}
