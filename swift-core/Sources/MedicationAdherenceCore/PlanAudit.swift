import Foundation

public enum PlanChangeField: String, Codable, Sendable, Equatable {
    case dose
    case timing
    case dateRange
    case medication
    case source
}

public enum PlanChangeSource: String, Codable, Sendable, Equatable {
    case doctor
    case pharmacist
    case label
    case userCustom
    case unknown
}

public struct PlanChangeAudit: Codable, Identifiable, Sendable, Equatable {
    public let id: UUID
    public var planID: UUID
    public var changedAt: Date
    public var field: PlanChangeField
    public var source: PlanChangeSource
    public var note: String
    public var requiresConfirmation: Bool

    public init(
        id: UUID = UUID(),
        planID: UUID,
        changedAt: Date,
        field: PlanChangeField,
        source: PlanChangeSource,
        note: String,
        requiresConfirmation: Bool
    ) {
        self.id = id
        self.planID = planID
        self.changedAt = changedAt
        self.field = field
        self.source = source
        self.note = note
        self.requiresConfirmation = requiresConfirmation
    }
}

public struct PlanAuditEngine: Sendable {
    public init() {}

    public func audit(
        planID: UUID,
        field: PlanChangeField,
        source: PlanChangeSource,
        note: String,
        changedAt: Date = Date()
    ) -> PlanChangeAudit {
        let highRiskField = field == .dose || field == .timing || field == .dateRange
        let weakSource = source == .userCustom || source == .unknown
        return PlanChangeAudit(
            planID: planID,
            changedAt: changedAt,
            field: field,
            source: source,
            note: note,
            requiresConfirmation: highRiskField || weakSource
        )
    }
}
