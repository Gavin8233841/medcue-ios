import Foundation

public enum MedicalAIRequestKind: String, Codable, Sendable, Equatable {
    case chat
    case riskOptimization
    case prescriptionOCRReview
    case barcodeImportReview
}

public enum MedicalAIDataScope: String, Codable, Sendable, Hashable {
    case medicationProfile
    case medicationPlans
    case doseEvents
    case riskCards
    case drugLabels
    case importDraft
}

public struct MedicalAIProviderProfile: Codable, Sendable, Equatable {
    public var providerName: String
    public var modelName: String
    public var serviceLicenseSummary: String

    public init(providerName: String, modelName: String, serviceLicenseSummary: String) {
        self.providerName = providerName
        self.modelName = modelName
        self.serviceLicenseSummary = serviceLicenseSummary
    }
}

public struct MedicalAIUserAuthorization: Codable, Sendable, Equatable {
    public var grantedScopes: Set<MedicalAIDataScope>
    public var grantedAt: Date
    public var expiresAt: Date?
    public var note: String

    public init(
        grantedScopes: Set<MedicalAIDataScope>,
        grantedAt: Date = Date(),
        expiresAt: Date? = nil,
        note: String = ""
    ) {
        self.grantedScopes = grantedScopes
        self.grantedAt = grantedAt
        self.expiresAt = expiresAt
        self.note = note
    }

    public func allows(_ scope: MedicalAIDataScope, at date: Date = Date()) -> Bool {
        guard grantedScopes.contains(scope) else {
            return false
        }
        if let expiresAt {
            return date <= expiresAt
        }
        return true
    }
}

public struct MedicalAIMedicationSnapshot: Codable, Sendable, Equatable {
    public var medication: Medication
    public var plans: [MedicationPlan]
    public var scheduledDoses: [ScheduledDose]
    public var doseEvents: [DoseEvent]
    public var riskCards: [RiskAssessmentCard]
    public var labelSummary: ReadableLabelSummary?

    public init(
        medication: Medication,
        plans: [MedicationPlan] = [],
        scheduledDoses: [ScheduledDose] = [],
        doseEvents: [DoseEvent] = [],
        riskCards: [RiskAssessmentCard] = [],
        labelSummary: ReadableLabelSummary? = nil
    ) {
        self.medication = medication
        self.plans = plans
        self.scheduledDoses = scheduledDoses
        self.doseEvents = doseEvents
        self.riskCards = riskCards
        self.labelSummary = labelSummary
    }
}

public struct MedicalAIRequest: Codable, Identifiable, Sendable, Equatable {
    public let id: UUID
    public var kind: MedicalAIRequestKind
    public var userMessage: String
    public var authorization: MedicalAIUserAuthorization
    public var medicationSnapshots: [MedicalAIMedicationSnapshot]
    public var importReview: MedicationImportReview?
    public var localeIdentifier: String
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        kind: MedicalAIRequestKind,
        userMessage: String,
        authorization: MedicalAIUserAuthorization,
        medicationSnapshots: [MedicalAIMedicationSnapshot] = [],
        importReview: MedicationImportReview? = nil,
        localeIdentifier: String = "zh_CN",
        createdAt: Date = Date()
    ) {
        self.id = id
        self.kind = kind
        self.userMessage = userMessage
        self.authorization = authorization
        self.medicationSnapshots = medicationSnapshots
        self.importReview = importReview
        self.localeIdentifier = localeIdentifier
        self.createdAt = createdAt
    }
}

public struct MedicalAIResponse: Codable, Identifiable, Sendable, Equatable {
    public let id: UUID
    public var requestID: UUID
    public var provider: MedicalAIProviderProfile
    public var message: String
    public var optimizedRiskCards: [RiskAssessmentCard]
    public var suggestedImportReview: MedicationImportReview?
    public var receivedAt: Date

    public init(
        id: UUID = UUID(),
        requestID: UUID,
        provider: MedicalAIProviderProfile,
        message: String,
        optimizedRiskCards: [RiskAssessmentCard] = [],
        suggestedImportReview: MedicationImportReview? = nil,
        receivedAt: Date = Date()
    ) {
        self.id = id
        self.requestID = requestID
        self.provider = provider
        self.message = message
        self.optimizedRiskCards = optimizedRiskCards
        self.suggestedImportReview = suggestedImportReview
        self.receivedAt = receivedAt
    }
}

public protocol MedicalAIClient: Sendable {
    func respond(to request: MedicalAIRequest) async throws -> MedicalAIResponse
}

public struct MedicalAIRequestValidator: Sendable {
    public init() {}

    public func missingRequiredScopes(for request: MedicalAIRequest) -> Set<MedicalAIDataScope> {
        var requiredScopes: Set<MedicalAIDataScope> = []

        if !request.medicationSnapshots.isEmpty {
            requiredScopes.insert(.medicationProfile)
        }
        if request.medicationSnapshots.contains(where: { !$0.plans.isEmpty }) {
            requiredScopes.insert(.medicationPlans)
        }
        if request.medicationSnapshots.contains(where: { !$0.doseEvents.isEmpty || !$0.scheduledDoses.isEmpty }) {
            requiredScopes.insert(.doseEvents)
        }
        if request.medicationSnapshots.contains(where: { !$0.riskCards.isEmpty }) {
            requiredScopes.insert(.riskCards)
        }
        if request.medicationSnapshots.contains(where: { $0.labelSummary != nil }) {
            requiredScopes.insert(.drugLabels)
        }
        if request.importReview != nil {
            requiredScopes.insert(.importDraft)
        }

        return requiredScopes.filter { !request.authorization.allows($0, at: request.createdAt) }
    }

    public func canSend(_ request: MedicalAIRequest) -> Bool {
        missingRequiredScopes(for: request).isEmpty
    }
}

public struct UnconfiguredMedicalAIClient: MedicalAIClient {
    public var provider: MedicalAIProviderProfile

    public init(provider: MedicalAIProviderProfile = MedicalAIProviderProfile(
        providerName: "未配置医疗 AI 服务",
        modelName: "unconfigured",
        serviceLicenseSummary: "等待供应商 API 文档和鉴权信息。"
    )) {
        self.provider = provider
    }

    public func respond(to request: MedicalAIRequest) async throws -> MedicalAIResponse {
        MedicalAIResponse(
            requestID: request.id,
            provider: provider,
            message: "医疗 AI 服务尚未配置。请在 App 层接入已确认的供应商适配器后重试。"
        )
    }
}
