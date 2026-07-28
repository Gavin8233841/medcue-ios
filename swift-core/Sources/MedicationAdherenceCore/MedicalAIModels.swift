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

public struct MedicalAIEnvironmentInsight: Codable, Sendable, Equatable {
    public var title: String
    public var message: String
    public var sourceSummary: String
    public var severityText: String

    public init(
        title: String,
        message: String,
        sourceSummary: String,
        severityText: String
    ) {
        self.title = title
        self.message = message
        self.sourceSummary = sourceSummary
        self.severityText = severityText
    }
}

public struct MedicalAIEnvironmentQuestionDetector: Sendable {
    public init() {}

    public func shouldAttachEnvironmentContext(to userMessage: String) -> Bool {
        let normalizedMessage = userMessage
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
            .lowercased()
            .filter { !$0.isWhitespace && !$0.isPunctuation }

        guard !normalizedMessage.isEmpty else {
            return false
        }

        let directKeywords = [
            "天气", "环境", "气温", "温度", "湿度", "降水", "下雨", "下雪", "雨天", "雪天",
            "紫外线", "日晒", "高温", "低温", "天热", "太热", "天冷", "太冷", "干燥", "潮湿",
            "气候", "空气", "空气质量", "空气不好", "污染", "沙尘", "雾霾", "花粉", "暴晒",
            "晒太阳", "日照", "闷热", "寒潮", "降温", "温差", "冷空气", "暴雨", "雷雨", "台风",
            "外出", "出门",
            "weather", "temperature", "humidity", "rain", "snow", "uv", "pollen", "airquality",
            "pollution", "smog", "dust", "storm", "typhoon", "sunlight", "heat", "cold", "dry", "humid"
        ]
        if directKeywords.contains(where: { normalizedMessage.contains($0) }) {
            return true
        }

        let windKeywords = ["大风", "风力", "刮风", "wind"]
        return windKeywords.contains { normalizedMessage.contains($0) }
    }
}

public struct MedicalAIRequest: Codable, Identifiable, Sendable, Equatable {
    public let id: UUID
    public var kind: MedicalAIRequestKind
    public var userMessage: String
    public var authorization: MedicalAIUserAuthorization
    public var medicationSnapshots: [MedicalAIMedicationSnapshot]
    public var environmentInsights: [MedicalAIEnvironmentInsight]
    public var importReview: MedicationImportReview?
    public var localeIdentifier: String
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        kind: MedicalAIRequestKind,
        userMessage: String,
        authorization: MedicalAIUserAuthorization,
        medicationSnapshots: [MedicalAIMedicationSnapshot] = [],
        environmentInsights: [MedicalAIEnvironmentInsight] = [],
        importReview: MedicationImportReview? = nil,
        localeIdentifier: String = "zh_CN",
        createdAt: Date = Date()
    ) {
        self.id = id
        self.kind = kind
        self.userMessage = userMessage
        self.authorization = authorization
        self.medicationSnapshots = medicationSnapshots
        self.environmentInsights = environmentInsights
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
        providerName: "医疗智能体",
        modelName: "unconfigured",
        serviceLicenseSummary: "医疗智能体连接暂未完成。"
    )) {
        self.provider = provider
    }

    public func respond(to request: MedicalAIRequest) async throws -> MedicalAIResponse {
        MedicalAIResponse(
            requestID: request.id,
            provider: provider,
            message: "医疗智能体暂时无法连接，未发送任何用药数据。请稍后重试。"
        )
    }
}
