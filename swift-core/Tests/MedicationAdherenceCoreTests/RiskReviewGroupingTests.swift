import Testing
@testable import MedicationAdherenceCore

@Test func riskReviewGrouperSplitsCardsIntoThreeSections() {
    let cards = [
        RiskAssessmentCard(
            id: "interaction",
            kind: .labelRisk,
            displayPriority: 10,
            title: "相互作用或需咨询药师",
            message: "说明书提示药物相互作用。",
            requiresProfessionalReview: true
        ),
        RiskAssessmentCard(
            id: "food",
            kind: .foodReview,
            displayPriority: 12,
            title: "饮食相关复核",
            message: "说明书提到 alcohol。",
            requiresProfessionalReview: true
        ),
        RiskAssessmentCard(
            id: "condition",
            kind: .healthConditionReview,
            displayPriority: 15,
            title: "病症相关复核",
            message: "说明书提到 kidney disease。",
            requiresProfessionalReview: true
        )
    ]

    let sections = RiskReviewGrouper().groupedSections(from: cards)

    #expect(sections.count == 3)
    #expect(sections.first { $0.group == .drugInteraction }?.cards.map(\.id) == ["interaction"])
    #expect(sections.first { $0.group == .foodAndLifestyleInteraction }?.cards.map(\.id) == ["food"])
    #expect(sections.first { $0.group == .conditionAndSymptomAttention }?.cards.map(\.id) == ["condition"])
}

@Test func riskReviewGroupTitlesUseFormalWording() {
    #expect(RiskReviewGroup.drugInteraction.title == "药物相互作用")
    #expect(RiskReviewGroup.foodAndLifestyleInteraction.title.contains("饮食"))
    #expect(RiskReviewGroup.conditionAndSymptomAttention.title.contains("病症"))
}

@Test func riskReviewGrouperMapsContraindicationAndAdverseReactionToConditionSection() {
    let cards = [
        RiskAssessmentCard(
            id: "contraindication",
            kind: .labelRisk,
            displayPriority: 10,
            title: "禁忌或不得使用",
            message: "说明书提示过敏者禁用。",
            requiresProfessionalReview: true
        ),
        RiskAssessmentCard(
            id: "adverse",
            kind: .labelRisk,
            displayPriority: 20,
            title: "不良反应",
            message: "说明书提到可能出现头晕。",
            requiresProfessionalReview: true
        )
    ]

    let grouper = RiskReviewGrouper()

    #expect(cards.allSatisfy { grouper.mappedGroup(for: $0) == .conditionAndSymptomAttention })
}
