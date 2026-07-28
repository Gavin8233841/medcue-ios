import Foundation

public enum EnvironmentMedicationInsightSeverity: String, Codable, Sendable, Equatable {
    case info
    case attention
    case caution
    case priority

    public var displayName: String {
        switch self {
        case .info:
            "提示"
        case .attention:
            "关注"
        case .caution:
            "留意"
        case .priority:
            "优先复核"
        }
    }
}

public struct EnvironmentMedicationSnapshot: Codable, Sendable, Equatable {
    public var temperatureCelsius: Double
    public var humidity: Double
    public var precipitationChance: Double
    public var uvIndexCategory: String
    public var windSpeedKPH: Double
    public var conditionDescription: String
    public var observedAt: Date

    public init(
        temperatureCelsius: Double,
        humidity: Double,
        precipitationChance: Double,
        uvIndexCategory: String,
        windSpeedKPH: Double,
        conditionDescription: String,
        observedAt: Date = Date()
    ) {
        self.temperatureCelsius = temperatureCelsius
        self.humidity = humidity
        self.precipitationChance = precipitationChance
        self.uvIndexCategory = uvIndexCategory
        self.windSpeedKPH = windSpeedKPH
        self.conditionDescription = conditionDescription
        self.observedAt = observedAt
    }
}

public struct EnvironmentMedicationProfileItem: Codable, Identifiable, Sendable, Equatable {
    public var id: UUID
    public var displayName: String
    public var genericName: String
    public var form: String
    public var notes: String
    public var isActive: Bool

    public init(
        id: UUID = UUID(),
        displayName: String,
        genericName: String = "",
        form: String = "",
        notes: String = "",
        isActive: Bool = true
    ) {
        self.id = id
        self.displayName = displayName
        self.genericName = genericName
        self.form = form
        self.notes = notes
        self.isActive = isActive
    }
}

public struct EnvironmentMedicationInsight: Codable, Identifiable, Sendable, Equatable {
    public var id: String
    public var iconName: String
    public var title: String
    public var message: String
    public var sourceSummary: String
    public var tintName: String
    public var severity: EnvironmentMedicationInsightSeverity

    public init(
        id: String,
        iconName: String,
        title: String,
        message: String,
        sourceSummary: String,
        tintName: String,
        severity: EnvironmentMedicationInsightSeverity
    ) {
        self.id = id
        self.iconName = iconName
        self.title = title
        self.message = message
        self.sourceSummary = sourceSummary
        self.tintName = tintName
        self.severity = severity
    }
}

public struct EnvironmentMedicationRuleThresholds: Codable, Sendable, Equatable {
    public var dryHumidity: Double
    public var veryDryHumidity: Double
    public var carryMedicationRainChance: Double
    public var hotRoutineTemperature: Double
    public var hotStorageTemperature: Double
    public var coldRoutineTemperature: Double
    public var windDryEyeSpeed: Double
    public var extremeHotStorageTemperature: Double

    public init(
        dryHumidity: Double = 0.35,
        veryDryHumidity: Double = 0.30,
        carryMedicationRainChance: Double = 0.45,
        hotRoutineTemperature: Double = 30.0,
        hotStorageTemperature: Double = 32.0,
        coldRoutineTemperature: Double = 5.0,
        windDryEyeSpeed: Double = 35.0,
        extremeHotStorageTemperature: Double = 38.0
    ) {
        self.dryHumidity = dryHumidity
        self.veryDryHumidity = veryDryHumidity
        self.carryMedicationRainChance = carryMedicationRainChance
        self.hotRoutineTemperature = hotRoutineTemperature
        self.hotStorageTemperature = hotStorageTemperature
        self.coldRoutineTemperature = coldRoutineTemperature
        self.windDryEyeSpeed = windDryEyeSpeed
        self.extremeHotStorageTemperature = extremeHotStorageTemperature
    }
}

public struct EnvironmentMedicationInsightBuilder: Sendable {
    public var thresholds: EnvironmentMedicationRuleThresholds

    public init(thresholds: EnvironmentMedicationRuleThresholds = EnvironmentMedicationRuleThresholds()) {
        self.thresholds = thresholds
    }

    public func build(
        medications: [EnvironmentMedicationProfileItem],
        snapshot: EnvironmentMedicationSnapshot,
        limit: Int = 3
    ) -> [EnvironmentMedicationInsight] {
        var generated: [EnvironmentMedicationInsight] = []
        let source = sourceSummary(for: snapshot)
        let activeMedications = medications.filter(\.isActive)
        let profile = EnvironmentMedicationProfile(medications: activeMedications)

        if activeMedications.isEmpty {
            generated.append(steadyRoutineInsight(source: source))
            return Array(generated.prefix(max(1, limit)))
        }

        if snapshot.humidity < thresholds.dryHumidity, profile.hasEyeOrDrynessMedication {
            generated.append(EnvironmentMedicationInsight(
                id: "dry-eye",
                iconName: "humidity.fill",
                title: "干燥环境关注",
                message: "湿度偏低，滴眼类或干燥相关药品请按既定计划核对使用；持续不适请咨询医生或药师。",
                sourceSummary: source,
                tintName: "blue",
                severity: .attention
            ))
        }

        if snapshot.humidity < thresholds.veryDryHumidity, profile.hasRespiratoryOrAllergyMedication {
            generated.append(EnvironmentMedicationInsight(
                id: "dry-respiratory",
                iconName: "wind",
                title: "呼吸道环境关注",
                message: "空气偏干时，鼻炎、过敏或呼吸道相关用药更要按提醒记录；症状加重请咨询医生或药师。",
                sourceSummary: source,
                tintName: "teal",
                severity: .attention
            ))
        }

        if snapshot.precipitationChance >= thresholds.carryMedicationRainChance {
            generated.append(EnvironmentMedicationInsight(
                id: "rain-carry",
                iconName: "cloud.rain.fill",
                title: "外出携药关注",
                message: "今日降水概率较高，外出前可核对随身药品和提醒时间，避免因行程变化漏记。",
                sourceSummary: source,
                tintName: "teal",
                severity: .info
            ))
        }

        if snapshot.temperatureCelsius >= thresholds.hotStorageTemperature {
            let isExtremeHotStorage = snapshot.temperatureCelsius >= thresholds.extremeHotStorageTemperature
            generated.append(EnvironmentMedicationInsight(
                id: "hot-storage",
                iconName: "thermometer.sun.fill",
                title: isExtremeHotStorage ? "极端高温保存复核" : "高温保存关注",
                message: isExtremeHotStorage
                    ? "气温明显偏高，请优先核对随身药品、药盒和说明书保存要求；如药品曾长时间暴露在车内或阳光下，请咨询医生或药师后再确认是否继续使用。"
                    : "气温较高，请按药盒或说明书核对避光、密封、冷藏等保存要求，避免药品长时间留在车内或阳光下。",
                sourceSummary: source,
                tintName: "orange",
                severity: isExtremeHotStorage ? .priority : .caution
            ))
        } else if snapshot.temperatureCelsius <= thresholds.coldRoutineTemperature {
            generated.append(EnvironmentMedicationInsight(
                id: "cold-routine",
                iconName: "thermometer.snowflake",
                title: "低温出行关注",
                message: "气温较低，外出和晚间提醒可提前核对；慢病或长期用药用户如出现明显不适请咨询医生或药师。",
                sourceSummary: source,
                tintName: "indigo",
                severity: .attention
            ))
        }

        if snapshot.temperatureCelsius >= thresholds.hotRoutineTemperature, profile.hasLongTermMedication {
            generated.append(EnvironmentMedicationInsight(
                id: "hot-hydration",
                iconName: "drop.fill",
                title: "高温节奏关注",
                message: "高温天气容易打乱饮水、作息和外出节奏，请按提醒核对长期用药记录；不要自行调整剂量。",
                sourceSummary: source,
                tintName: "orange",
                severity: .attention
            ))
        }

        if isStrongUV(snapshot.uvIndexCategory) {
            generated.append(EnvironmentMedicationInsight(
                id: "uv-sun",
                iconName: "sun.max.fill",
                title: "日晒环境关注",
                message: "今日紫外线较强，如药品说明书提示光敏或避光保存，请按原文核对并做好防晒。",
                sourceSummary: source,
                tintName: "yellow",
                severity: .attention
            ))
        }

        if snapshot.windSpeedKPH >= thresholds.windDryEyeSpeed, profile.hasEyeOrDrynessMedication {
            generated.append(EnvironmentMedicationInsight(
                id: "wind-eye",
                iconName: "wind.circle.fill",
                title: "大风干眼关注",
                message: "风力较大时，滴眼类药品请按提醒核对使用间隔；外出后不适持续请咨询医生或药师。",
                sourceSummary: source,
                tintName: "blue",
                severity: .attention
            ))
        }

        if generated.isEmpty {
            generated.append(steadyRoutineInsight(source: source))
        }

        return Array(generated.sorted(by: insightSort).prefix(max(1, limit)))
    }

    public func fallback(
        medications: [EnvironmentMedicationProfileItem],
        limit: Int = 3
    ) -> [EnvironmentMedicationInsight] {
        let activeMedications = medications.filter(\.isActive)
        let profile = EnvironmentMedicationProfile(medications: activeMedications)
        let medicationSummary = summarizedMedicationNames(activeMedications)
        var insights = [
            EnvironmentMedicationInsight(
                id: "fallback-routine",
                iconName: "clock.badge.checkmark",
                title: "今日计划核对",
                message: medicationSummary.isEmpty
                    ? "添加药品和提醒后，可按今日计划核对随身药品、服用时间和记录状态。"
                    : "已保存 \(medicationSummary)，外出前核对随身药品、服用时间和记录状态。",
                sourceSummary: "本机药品与提醒计划",
                tintName: "green",
                severity: .info
            )
        ]

        if profile.hasEyeOrDrynessMedication {
            insights.append(EnvironmentMedicationInsight(
                id: "fallback-eye",
                iconName: "eye.fill",
                title: "滴眼药品关注",
                message: "已保存滴眼或干燥相关药品。空气干燥、大风或长时间用眼时，请按医嘱核对使用间隔并记录。",
                sourceSummary: "本机药品类型",
                tintName: "blue",
                severity: .attention
            ))
        }

        if profile.hasRespiratoryOrAllergyMedication {
            insights.append(EnvironmentMedicationInsight(
                id: "fallback-allergy",
                iconName: "wind",
                title: "过敏与呼吸道关注",
                message: "已保存过敏、鼻炎或呼吸道相关药品。遇到干燥、花粉、雾霾或天气突变时，按提醒记录并留意症状变化。",
                sourceSummary: "本机药品类型",
                tintName: "teal",
                severity: .attention
            ))
        }

        if profile.hasLongTermMedication {
            insights.append(EnvironmentMedicationInsight(
                id: "fallback-storage",
                iconName: "shippingbox.fill",
                title: "外出保存复核",
                message: "长期用药外出携带时，优先核对药盒编号、余量和保存要求；不要把药品长时间留在车内或阳光下。",
                sourceSummary: "本机药品与药盒管理",
                tintName: "orange",
                severity: .info
            ))
        }
        return Array(insights.prefix(max(1, limit)))
    }

    public func sourceSummary(for snapshot: EnvironmentMedicationSnapshot) -> String {
        let temperature = Int(snapshot.temperatureCelsius.rounded())
        let humidity = Int((snapshot.humidity * 100).rounded())
        let rain = Int((snapshot.precipitationChance * 100).rounded())
        let wind = Int(snapshot.windSpeedKPH.rounded())
        return "\(temperature)°C · 湿度 \(humidity)% · 降水 \(rain)% · 风速 \(wind)km/h"
    }

    private func insightSort(_ lhs: EnvironmentMedicationInsight, _ rhs: EnvironmentMedicationInsight) -> Bool {
        if severityRank(lhs.severity) != severityRank(rhs.severity) {
            return severityRank(lhs.severity) > severityRank(rhs.severity)
        }
        return lhs.id < rhs.id
    }

    private func severityRank(_ severity: EnvironmentMedicationInsightSeverity) -> Int {
        switch severity {
        case .priority:
            4
        case .caution:
            3
        case .attention:
            2
        case .info:
            1
        }
    }

    private func isStrongUV(_ category: String) -> Bool {
        let normalizedCategory = category
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
            .replacingOccurrences(of: " ", with: "")
            .lowercased()
        return normalizedCategory == "high"
            || normalizedCategory == "veryhigh"
            || normalizedCategory == "extreme"
    }

    private func steadyRoutineInsight(source: String) -> EnvironmentMedicationInsight {
        EnvironmentMedicationInsight(
            id: "steady-routine",
            iconName: "cloud.sun.fill",
            title: "今日环境平稳",
            message: "今日天气暂未触发特别关注，继续按已确认计划记录用药；如有不适请咨询医生或药师。",
            sourceSummary: source,
            tintName: "green",
            severity: .info
        )
    }

    private func summarizedMedicationNames(_ medications: [EnvironmentMedicationProfileItem]) -> String {
        let names = medications
            .map { $0.displayName.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !names.isEmpty else {
            return ""
        }
        let visibleNames = names.prefix(2).joined(separator: "、")
        let remainingCount = names.count - 2
        if remainingCount > 0 {
            return "\(visibleNames) 等 \(names.count) 种正在服用药物"
        }
        return "\(visibleNames)"
    }
}

private struct EnvironmentMedicationProfile {
    let hasEyeOrDrynessMedication: Bool
    let hasRespiratoryOrAllergyMedication: Bool
    let hasLongTermMedication: Bool

    init(medications: [EnvironmentMedicationProfileItem]) {
        hasEyeOrDrynessMedication = medications.contains { medication in
            let text = Self.searchText(for: medication)
            return text.contains("滴眼") || text.contains("眼") || text.contains("tear") || text.contains("dry")
        }
        hasRespiratoryOrAllergyMedication = medications.contains { medication in
            let text = Self.searchText(for: medication)
            return text.contains("氯雷他定")
                || text.contains("鼻炎")
                || text.contains("过敏")
                || text.contains("呼吸")
                || text.contains("loratadine")
                || text.contains("allerg")
                || text.contains("rhinitis")
        }
        hasLongTermMedication = medications.contains(where: \.isActive)
    }

    private static func searchText(for medication: EnvironmentMedicationProfileItem) -> String {
        "\(medication.displayName) \(medication.genericName) \(medication.form) \(medication.notes)".lowercased()
    }
}
