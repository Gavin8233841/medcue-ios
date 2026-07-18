import Testing
@testable import MedicationAdherenceCore

@Test func environmentMedicationInsightsPrioritizeHotStorageBeforeRoutineHints() {
    let snapshot = EnvironmentMedicationSnapshot(
        temperatureCelsius: 34,
        humidity: 0.62,
        precipitationChance: 0.50,
        uvIndexCategory: "high",
        windSpeedKPH: 12,
        conditionDescription: "晴"
    )
    let medications = [
        EnvironmentMedicationProfileItem(displayName: "苯磺酸氨氯地平片", form: "片剂", isActive: true)
    ]

    let insights = EnvironmentMedicationInsightBuilder().build(medications: medications, snapshot: snapshot)

    #expect(insights.first?.id == "hot-storage")
    #expect(insights.first?.severity == .caution)
    #expect(insights.contains { $0.id == "hot-hydration" })
    #expect(insights.count == 3)
}

@Test func environmentMedicationInsightsEscalateOnlyExtremeHeatStorage() {
    let snapshot = EnvironmentMedicationSnapshot(
        temperatureCelsius: 39,
        humidity: 0.58,
        precipitationChance: 0.10,
        uvIndexCategory: "moderate",
        windSpeedKPH: 8,
        conditionDescription: "高温"
    )
    let medications = [
        EnvironmentMedicationProfileItem(displayName: "维生素 D3", form: "软胶囊", notes: "长期用药", isActive: true)
    ]

    let insights = EnvironmentMedicationInsightBuilder().build(medications: medications, snapshot: snapshot)
    let storageInsight = insights.first { $0.id == "hot-storage" }

    #expect(storageInsight?.severity == .priority)
    #expect(storageInsight?.title == "极端高温保存复核")
    #expect(storageInsight?.message.contains("咨询医生或药师") == true)
}

@Test func environmentMedicationInsightsUseMedicationProfileForDryEyeAndWind() {
    let snapshot = EnvironmentMedicationSnapshot(
        temperatureCelsius: 22,
        humidity: 0.24,
        precipitationChance: 0.10,
        uvIndexCategory: "low",
        windSpeedKPH: 38,
        conditionDescription: "多风"
    )
    let medications = [
        EnvironmentMedicationProfileItem(displayName: "玻璃酸钠滴眼液", form: "滴眼液", notes: "干眼", isActive: true)
    ]

    let insights = EnvironmentMedicationInsightBuilder().build(medications: medications, snapshot: snapshot)

    #expect(insights.map(\.id).contains("dry-eye"))
    #expect(insights.map(\.id).contains("wind-eye"))
    #expect(insights.allSatisfy { $0.message.contains("咨询医生或药师") || $0.message.contains("核对") })
}

@Test func environmentMedicationInsightsAddRespiratoryDrynessForAllergyMedication() {
    let snapshot = EnvironmentMedicationSnapshot(
        temperatureCelsius: 18,
        humidity: 0.22,
        precipitationChance: 0.05,
        uvIndexCategory: "moderate",
        windSpeedKPH: 6,
        conditionDescription: "干燥"
    )
    let medications = [
        EnvironmentMedicationProfileItem(displayName: "氯雷他定片", form: "片剂", notes: "过敏性鼻炎", isActive: true)
    ]

    let insights = EnvironmentMedicationInsightBuilder().build(medications: medications, snapshot: snapshot)

    #expect(insights.map(\.id).contains("dry-respiratory"))
}

@Test func environmentMedicationInsightsIgnoreInactiveMedicationProfiles() {
    let snapshot = EnvironmentMedicationSnapshot(
        temperatureCelsius: 22,
        humidity: 0.22,
        precipitationChance: 0.05,
        uvIndexCategory: "low",
        windSpeedKPH: 38,
        conditionDescription: "干燥多风"
    )
    let medications = [
        EnvironmentMedicationProfileItem(displayName: "玻璃酸钠滴眼液", form: "滴眼液", notes: "干眼", isActive: false),
        EnvironmentMedicationProfileItem(displayName: "氯雷他定片", form: "片剂", notes: "过敏性鼻炎", isActive: false)
    ]

    let insights = EnvironmentMedicationInsightBuilder().build(medications: medications, snapshot: snapshot)

    #expect(insights.map(\.id) == ["steady-routine"])
    #expect(insights.allSatisfy { !$0.message.contains("滴眼") && !$0.message.contains("鼻炎") })
}

@Test func environmentMedicationInsightsFallbackUseMedicationContextWithoutWeather() {
    let medications = [
        EnvironmentMedicationProfileItem(displayName: "玻璃酸钠滴眼液", form: "滴眼液", isActive: true),
        EnvironmentMedicationProfileItem(displayName: "苯磺酸氨氯地平片", form: "片剂", isActive: true)
    ]

    let insights = EnvironmentMedicationInsightBuilder().fallback(medications: medications)

    #expect(insights.map(\.id) == ["fallback-routine", "fallback-eye", "fallback-storage"])
    #expect(insights.first?.title == "今日计划核对")
    #expect(insights.first?.sourceSummary == "本机药品与提醒计划")
    #expect(insights.first?.message.contains("玻璃酸钠滴眼液") == true)
    #expect(insights[1].title == "滴眼药品关注")
    #expect(insights[2].title == "外出保存复核")
}
