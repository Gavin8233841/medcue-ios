import Foundation

public enum RiskPrioritySeverity: String, Codable, Sendable, Equatable, CaseIterable {
    case critical
    case high
    case medium
    case low
    case info

    public var isActionable: Bool {
        switch self {
        case .critical, .high:
            true
        case .medium, .low, .info:
            false
        }
    }
}

public struct RiskPriorityInput: Sendable, Equatable {
    public var kindRaw: String
    public var displayPriority: Int
    public var title: String
    public var message: String
    public var sourceExcerpt: String
    public var requiresProfessionalReview: Bool

    public init(
        kindRaw: String,
        displayPriority: Int,
        title: String,
        message: String,
        sourceExcerpt: String = "",
        requiresProfessionalReview: Bool
    ) {
        self.kindRaw = kindRaw
        self.displayPriority = displayPriority
        self.title = title
        self.message = message
        self.sourceExcerpt = sourceExcerpt
        self.requiresProfessionalReview = requiresProfessionalReview
    }
}

public struct RiskPriorityDecision: Sendable, Equatable {
    public var severity: RiskPrioritySeverity
    public var countsForUnreadBadge: Bool
    public var shouldAnnounce: Bool

    public init(
        severity: RiskPrioritySeverity,
        countsForUnreadBadge: Bool,
        shouldAnnounce: Bool
    ) {
        self.severity = severity
        self.countsForUnreadBadge = countsForUnreadBadge
        self.shouldAnnounce = shouldAnnounce
    }
}

public struct RiskPriorityPolicy: Sendable {
    public init() {}

    public func evaluate(_ input: RiskPriorityInput) -> RiskPriorityDecision {
        let severity = inferredSeverity(for: input)
        let shouldNotify = input.requiresProfessionalReview && severity.isActionable
        return RiskPriorityDecision(
            severity: severity,
            countsForUnreadBadge: shouldNotify,
            shouldAnnounce: shouldNotify
        )
    }

    public func inferredSeverity(for input: RiskPriorityInput) -> RiskPrioritySeverity {
        let text = normalizedRiskText(input)
        if input.requiresProfessionalReview
            && input.displayPriority <= 6
            && (text.contains("禁用") || text.contains("不得使用") || text.contains("contraindicated")) {
            return .critical
        }
        if input.requiresProfessionalReview
            && input.kindRaw == RiskAssessmentCardKind.healthConditionReview.rawValue
            && input.displayPriority <= 6 {
            return .critical
        }
        if input.requiresProfessionalReview
            && (
                input.displayPriority <= 10
                    || text.contains("禁忌")
                    || text.contains("contraindication")
            ) {
            return .high
        }
        if input.requiresProfessionalReview && input.displayPriority <= 18 {
            return .medium
        }
        if input.kindRaw == RiskAssessmentCardKind.drugClassContext.rawValue {
            return .info
        }
        return .low
    }

    private func normalizedRiskText(_ input: RiskPriorityInput) -> String {
        "\(input.title) \(input.message) \(input.sourceExcerpt)"
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
            .lowercased()
    }
}
