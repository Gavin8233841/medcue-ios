import Testing
@testable import MedicationAdherenceCore

@Test func riskPriorityPolicyMarksContraindicatedReviewAsCriticalAndBadgeWorthy() {
    let decision = RiskPriorityPolicy().evaluate(RiskPriorityInput(
        kindRaw: RiskAssessmentCardKind.labelRisk.rawValue,
        displayPriority: 5,
        title: "禁忌或不得使用",
        message: "说明书提示相关人群不得使用。",
        sourceExcerpt: "对本品过敏者禁用。",
        requiresProfessionalReview: true
    ))

    #expect(decision.severity == .critical)
    #expect(decision.countsForUnreadBadge)
    #expect(decision.shouldAnnounce)
}

@Test func riskPriorityPolicyKeepsReviewMatchedContextAtMediumWithoutBadge() {
    let decision = RiskPriorityPolicy().evaluate(RiskPriorityInput(
        kindRaw: RiskAssessmentCardKind.healthConditionReview.rawValue,
        displayPriority: 15,
        title: "病症相关复核：肾病",
        message: "用户健康记录和说明书出现相同表述，需要复核。",
        sourceExcerpt: "肾病患者使用前请咨询医生。",
        requiresProfessionalReview: true
    ))

    #expect(decision.severity == .medium)
    #expect(!decision.countsForUnreadBadge)
    #expect(!decision.shouldAnnounce)
}

@Test func riskPriorityPolicyDoesNotBadgeInformationalDrugClassCards() {
    let decision = RiskPriorityPolicy().evaluate(RiskPriorityInput(
        kindRaw: RiskAssessmentCardKind.drugClassContext.rawValue,
        displayPriority: 80,
        title: "药品类别信息：Analgesics",
        message: "类别信息只帮助理解药品背景，不自动判断风险。",
        requiresProfessionalReview: false
    ))

    #expect(decision.severity == .info)
    #expect(!decision.countsForUnreadBadge)
    #expect(!decision.shouldAnnounce)
}

@Test func riskPriorityPolicyDoesNotBadgeLowPriorityGeneralNotes() {
    let decision = RiskPriorityPolicy().evaluate(RiskPriorityInput(
        kindRaw: RiskAssessmentCardKind.labelRisk.rawValue,
        displayPriority: 30,
        title: "说明书来源待核对",
        message: "用户提供文本需要核对来源。",
        requiresProfessionalReview: true
    ))

    #expect(decision.severity == .low)
    #expect(!decision.countsForUnreadBadge)
    #expect(!decision.shouldAnnounce)
}

@Test func riskPriorityPolicyAnnouncesOnlyHighPriorityExternalVitals() {
    let criticalVital = RiskPriorityPolicy().evaluate(RiskPriorityInput(
        kindRaw: RiskAssessmentCardKind.healthConditionReview.rawValue,
        displayPriority: 5,
        title: "血压读数需要优先复核",
        message: "最近一次授权血压读数较高，请先核对测量方式和原始记录。",
        sourceExcerpt: "收缩压 181 mmHg，舒张压 121 mmHg",
        requiresProfessionalReview: true
    ))

    let routineWeather = RiskPriorityPolicy().evaluate(RiskPriorityInput(
        kindRaw: RiskAssessmentCardKind.healthConditionReview.rawValue,
        displayPriority: 24,
        title: "高温天气关注",
        message: "天气变化下可核对饮水和随身药品。",
        sourceExcerpt: "天气与用药关注：高温",
        requiresProfessionalReview: true
    ))

    #expect(criticalVital.severity == .critical)
    #expect(criticalVital.countsForUnreadBadge)
    #expect(criticalVital.shouldAnnounce)
    #expect(routineWeather.severity == .low)
    #expect(!routineWeather.countsForUnreadBadge)
    #expect(!routineWeather.shouldAnnounce)
}
