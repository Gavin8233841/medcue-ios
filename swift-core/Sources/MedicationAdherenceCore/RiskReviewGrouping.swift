import Foundation

public enum RiskReviewGroup: String, Codable, Sendable, CaseIterable, Equatable {
    case drugInteraction
    case foodAndLifestyleInteraction
    case conditionAndSymptomAttention

    public var title: String {
        switch self {
        case .drugInteraction:
            "药物相互作用"
        case .foodAndLifestyleInteraction:
            "药物与饮食/生活方式相互作用"
        case .conditionAndSymptomAttention:
            "药物与病症/症状相关注意"
        }
    }

    public var description: String {
        switch self {
        case .drugInteraction:
            "查看同时使用多种药品时需要留意的说明书提示。"
        case .foodAndLifestyleInteraction:
            "查看饮酒、食物和生活方式可能影响用药体验的提醒。"
        case .conditionAndSymptomAttention:
            "查看与既往病症、症状或处方来源有关的注意事项。"
        }
    }
}

public struct RiskReviewSection: Codable, Sendable, Equatable {
    public var group: RiskReviewGroup
    public var cards: [RiskAssessmentCard]

    public init(group: RiskReviewGroup, cards: [RiskAssessmentCard]) {
        self.group = group
        self.cards = cards
    }
}

public struct RiskReviewGrouper: Sendable {
    public init() {}

    public func groupedSections(from cards: [RiskAssessmentCard]) -> [RiskReviewSection] {
        RiskReviewGroup.allCases.map { group in
            RiskReviewSection(
                group: group,
                cards: cards.filter { mappedGroup(for: $0) == group }
            )
        }
    }

    public func mappedGroup(for card: RiskAssessmentCard) -> RiskReviewGroup {
        switch card.kind {
        case .foodReview:
            return .foodAndLifestyleInteraction
        case .healthConditionReview:
            return .conditionAndSymptomAttention
        case .medicationSourceReview:
            return .conditionAndSymptomAttention
        case .drugClassContext:
            return .drugInteraction
        case .labelRisk:
            return labelRiskGroup(for: card)
        }
    }

    private func labelRiskGroup(for card: RiskAssessmentCard) -> RiskReviewGroup {
        let text = "\(card.title) \(card.message) \(card.evidence?.sourceTitle ?? "") \(card.evidence?.excerpt ?? "")".lowercased()
        if text.contains("food") || text.contains("alcohol") || text.contains("grapefruit") || text.contains("饮食") || text.contains("饮酒") || text.contains("葡萄柚") {
            return .foodAndLifestyleInteraction
        }
        if text.contains("condition")
            || text.contains("symptom")
            || text.contains("disease")
            || text.contains("adverse")
            || text.contains("contraindication")
            || text.contains("warning")
            || text.contains("病症")
            || text.contains("症状")
            || text.contains("处方")
            || text.contains("不良反应")
            || text.contains("副作用")
            || text.contains("禁忌")
            || text.contains("警示")
            || text.contains("注意事项")
            || text.contains("禁用")
            || text.contains("过敏") {
            return .conditionAndSymptomAttention
        }
        return .drugInteraction
    }
}
