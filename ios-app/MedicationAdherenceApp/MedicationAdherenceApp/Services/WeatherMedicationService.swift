import CoreLocation
import Foundation
import MedicationAdherenceCore
import WeatherKit

struct WeatherMedicationHint: Identifiable, Equatable {
    let id: String
    let iconName: String
    let title: String
    let message: String
    let sourceSummary: String
    let tintName: String
    let severity: EnvironmentMedicationInsightSeverity

    var isActionableForToday: Bool {
        id != "steady-routine" && id != "fallback-routine"
    }
}

@MainActor
final class WeatherMedicationService: NSObject, ObservableObject {
    @Published private(set) var hints: [WeatherMedicationHint] = []
    @Published private(set) var statusText = "正在准备今日环境关注。"
    @Published private(set) var isLoading = false
    @Published private(set) var shouldShowAuthorizationButton = false

    private let locationManager = CLLocationManager()
    private var locationContinuation: CheckedContinuation<CLLocation?, Never>?
    private let insightBuilder = EnvironmentMedicationInsightBuilder()

    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyThreeKilometers
    }

    var hasLocationAuthorization: Bool {
        switch locationManager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            return true
        case .notDetermined, .denied, .restricted:
            return false
        @unknown default:
            return false
        }
    }

    @discardableResult
    func refresh(medications: [StoredMedication], requestAuthorization: Bool = false) async -> Bool {
        isLoading = true
        defer { isLoading = false }

        let location = await currentLocation(requestAuthorization: requestAuthorization)
        guard let location else {
            hints = Self.fallbackHints(for: medications, builder: insightBuilder)
            shouldShowAuthorizationButton = locationManager.authorizationStatus == .notDetermined
            statusText = shouldShowAuthorizationButton
                ? "允许后可结合当前位置天气生成今日关注。"
                : ""
            return hasLocationAuthorization
        }

        do {
            let weather = try await WeatherService.shared.weather(for: location)
            let context = WeatherMedicationContext(
                temperatureCelsius: weather.currentWeather.temperature.converted(to: .celsius).value,
                humidity: weather.currentWeather.humidity,
                precipitationChance: weather.dailyForecast.forecast.first?.precipitationChance ?? 0,
                uvIndexCategory: weather.currentWeather.uvIndex.category.rawValue,
                windSpeedKPH: weather.currentWeather.wind.speed.converted(to: .kilometersPerHour).value,
                conditionDescription: weather.currentWeather.condition.description
            )
            hints = Self.hints(for: medications, context: context, builder: insightBuilder)
            statusText = "已结合今日天气和本机药品记录生成提醒。"
            shouldShowAuthorizationButton = false
            return true
        } catch {
            hints = Self.fallbackHints(for: medications, builder: insightBuilder)
            statusText = ""
            shouldShowAuthorizationButton = false
            return hasLocationAuthorization
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
    let windSpeedKPH: Double
    let conditionDescription: String
}

private extension WeatherMedicationService {
    static func hints(
        for medications: [StoredMedication],
        context: WeatherMedicationContext,
        builder: EnvironmentMedicationInsightBuilder
    ) -> [WeatherMedicationHint] {
        let snapshot = EnvironmentMedicationSnapshot(
            temperatureCelsius: context.temperatureCelsius,
            humidity: context.humidity,
            precipitationChance: context.precipitationChance,
            uvIndexCategory: context.uvIndexCategory,
            windSpeedKPH: context.windSpeedKPH,
            conditionDescription: context.conditionDescription
        )
        return builder
            .build(medications: medicationProfiles(from: medications), snapshot: snapshot, limit: 3)
            .map(WeatherMedicationHint.init)
    }

    static func fallbackHints(
        for medications: [StoredMedication],
        builder: EnvironmentMedicationInsightBuilder
    ) -> [WeatherMedicationHint] {
        builder
            .fallback(medications: medicationProfiles(from: medications), limit: 3)
            .map(WeatherMedicationHint.init)
    }

    static func medicationProfiles(from medications: [StoredMedication]) -> [EnvironmentMedicationProfileItem] {
        medications.map { medication in
            EnvironmentMedicationProfileItem(
                id: medication.id,
                displayName: userFacingMedicationName(for: medication),
                genericName: medication.genericName,
                form: medication.form,
                notes: medication.notes,
                isActive: medication.lifecycleStatus == .active
            )
        }
    }
}

private extension WeatherMedicationHint {
    init(_ insight: EnvironmentMedicationInsight) {
        self.init(
            id: insight.id,
            iconName: insight.iconName,
            title: insight.title,
            message: insight.message,
            sourceSummary: insight.sourceSummary,
            tintName: insight.tintName,
            severity: insight.severity
        )
    }
}
