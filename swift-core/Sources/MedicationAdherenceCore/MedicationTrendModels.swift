import Foundation

public enum MedicationTrendTopic: String, Codable, Sendable, Equatable, CaseIterable {
    case discipline
    case timing
    case doseChange
    case regimenLoad
    case healthSignal
}

public enum MedicationTrendDirection: String, Codable, Sendable, Equatable {
    case improving
    case stable
    case fluctuating
    case declining
    case needsData
}

public struct MedicationTrendPeriodComparison: Codable, Sendable, Equatable {
    public var recentPeriodTitle: String
    public var previousPeriodTitle: String
    public var recentScore: Double
    public var previousScore: Double?
    public var delta: Double?
    public var trendSlopePerDay: Double
    public var trendStrengthScore: Double
    public var confidenceScore: Double
    public var recentDayCount: Int
    public var previousDayCount: Int
    public var recentScheduledCount: Int
    public var previousScheduledCount: Int
    public var evidenceSummary: String

    public init(
        recentPeriodTitle: String = "近 7 天",
        previousPeriodTitle: String = "前 7 天",
        recentScore: Double,
        previousScore: Double? = nil,
        delta: Double? = nil,
        trendSlopePerDay: Double = 0,
        trendStrengthScore: Double = 0,
        confidenceScore: Double,
        recentDayCount: Int,
        previousDayCount: Int,
        recentScheduledCount: Int,
        previousScheduledCount: Int,
        evidenceSummary: String
    ) {
        self.recentPeriodTitle = recentPeriodTitle
        self.previousPeriodTitle = previousPeriodTitle
        self.recentScore = recentScore
        self.previousScore = previousScore
        self.delta = delta
        self.trendSlopePerDay = trendSlopePerDay
        self.trendStrengthScore = trendStrengthScore
        self.confidenceScore = confidenceScore
        self.recentDayCount = recentDayCount
        self.previousDayCount = previousDayCount
        self.recentScheduledCount = recentScheduledCount
        self.previousScheduledCount = previousScheduledCount
        self.evidenceSummary = evidenceSummary
    }
}

public struct MedicationTrendFormulaComponent: Codable, Identifiable, Sendable, Equatable {
    public var id: String
    public var title: String
    public var weight: Double
    public var score: Double
    public var source: String
    public var explanation: String

    public init(
        id: String,
        title: String,
        weight: Double,
        score: Double,
        source: String,
        explanation: String
    ) {
        self.id = id
        self.title = title
        self.weight = weight
        self.score = score
        self.source = source
        self.explanation = explanation
    }
}

public enum MedicationLifecycleState: String, Codable, Sendable, Equatable {
    case active
    case interrupted
    case archived
}

public enum HealthSignalKind: String, Codable, Sendable, Equatable {
    case heartRate
    case bloodPressureSystolic
    case bloodPressureDiastolic
    case bloodOxygen
    case bodyTemperature
    case bloodGlucose
    case unknown
}

public struct MedicationLifecycleEvent: Codable, Identifiable, Sendable, Equatable {
    public let id: UUID
    public var medicationID: UUID
    public var state: MedicationLifecycleState
    public var occurredAt: Date
    public var note: String

    public init(
        id: UUID = UUID(),
        medicationID: UUID,
        state: MedicationLifecycleState,
        occurredAt: Date,
        note: String = ""
    ) {
        self.id = id
        self.medicationID = medicationID
        self.state = state
        self.occurredAt = occurredAt
        self.note = note
    }
}

public struct MedicationTrendPlanContext: Codable, Identifiable, Sendable, Equatable {
    public var id: UUID { planID }
    public var planID: UUID
    public var medicationID: UUID
    public var medicationKind: MedicationKind
    public var inputSource: MedicationInputSource
    public var lifecycleState: MedicationLifecycleState

    public init(
        planID: UUID,
        medicationID: UUID,
        medicationKind: MedicationKind,
        inputSource: MedicationInputSource,
        lifecycleState: MedicationLifecycleState
    ) {
        self.planID = planID
        self.medicationID = medicationID
        self.medicationKind = medicationKind
        self.inputSource = inputSource
        self.lifecycleState = lifecycleState
    }
}

public struct HealthSignalSample: Codable, Identifiable, Sendable, Equatable {
    public let id: UUID
    public var kind: HealthSignalKind
    public var measuredAt: Date
    public var value: Double
    public var unit: String

    public init(
        id: UUID = UUID(),
        kind: HealthSignalKind,
        measuredAt: Date,
        value: Double,
        unit: String
    ) {
        self.id = id
        self.kind = kind
        self.measuredAt = measuredAt
        self.value = value
        self.unit = unit
    }
}

public struct MedicationTrendPoint: Codable, Identifiable, Sendable, Equatable {
    public var id: DateOnly { date }
    public var date: DateOnly
    public var score: Double
    public var scheduledCount: Int
    public var completedCount: Int
    public var delayedCount: Int
    public var skippedCount: Int
    public var doseChangeCount: Int
    public var activeMedicationCount: Int
    public var archivedMedicationCount: Int
    public var interruptedMedicationCount: Int
    public var prescriptionMedicationCount: Int
    public var nonPrescriptionMedicationCount: Int
    public var importedMedicationCount: Int
    public var healthSignalCount: Int
    public var formulaComponents: [MedicationTrendFormulaComponent]
    public var annotation: String

    public init(
        date: DateOnly,
        score: Double,
        scheduledCount: Int,
        completedCount: Int,
        delayedCount: Int,
        skippedCount: Int,
        doseChangeCount: Int = 0,
        activeMedicationCount: Int = 0,
        archivedMedicationCount: Int = 0,
        interruptedMedicationCount: Int = 0,
        prescriptionMedicationCount: Int = 0,
        nonPrescriptionMedicationCount: Int = 0,
        importedMedicationCount: Int = 0,
        healthSignalCount: Int = 0,
        formulaComponents: [MedicationTrendFormulaComponent] = [],
        annotation: String = ""
    ) {
        self.date = date
        self.score = score
        self.scheduledCount = scheduledCount
        self.completedCount = completedCount
        self.delayedCount = delayedCount
        self.skippedCount = skippedCount
        self.doseChangeCount = doseChangeCount
        self.activeMedicationCount = activeMedicationCount
        self.archivedMedicationCount = archivedMedicationCount
        self.interruptedMedicationCount = interruptedMedicationCount
        self.prescriptionMedicationCount = prescriptionMedicationCount
        self.nonPrescriptionMedicationCount = nonPrescriptionMedicationCount
        self.importedMedicationCount = importedMedicationCount
        self.healthSignalCount = healthSignalCount
        self.formulaComponents = formulaComponents
        self.annotation = annotation
    }
}

public struct MedicationTrendMetric: Codable, Identifiable, Sendable, Equatable {
    public var id: MedicationTrendTopic { topic }
    public var topic: MedicationTrendTopic
    public var title: String
    public var score: Double
    public var direction: MedicationTrendDirection
    public var summary: String
    public var dataSourceSummary: String
    public var formulaSummary: String
    public var comparison: MedicationTrendPeriodComparison
    public var contributorSummary: [String]
    public var formulaComponents: [MedicationTrendFormulaComponent]
    public var points: [MedicationTrendPoint]

    public init(
        topic: MedicationTrendTopic,
        title: String,
        score: Double,
        direction: MedicationTrendDirection,
        summary: String,
        dataSourceSummary: String,
        formulaSummary: String,
        comparison: MedicationTrendPeriodComparison,
        contributorSummary: [String] = [],
        formulaComponents: [MedicationTrendFormulaComponent] = [],
        points: [MedicationTrendPoint]
    ) {
        self.topic = topic
        self.title = title
        self.score = score
        self.direction = direction
        self.summary = summary
        self.dataSourceSummary = dataSourceSummary
        self.formulaSummary = formulaSummary
        self.comparison = comparison
        self.contributorSummary = contributorSummary
        self.formulaComponents = formulaComponents
        self.points = points
    }
}

public struct MedicationTrendDashboard: Codable, Sendable, Equatable {
    public var overallScore: Double
    public var direction: MedicationTrendDirection
    public var title: String
    public var summary: String
    public var disciplineSummary: String
    public var confidenceScore: Double
    public var dataQualitySummary: String
    public var safetyNote: String
    public var metrics: [MedicationTrendMetric]

    public init(
        overallScore: Double,
        direction: MedicationTrendDirection,
        title: String,
        summary: String,
        disciplineSummary: String,
        confidenceScore: Double = 0,
        dataQualitySummary: String = "继续记录后提高趋势可信度。",
        safetyNote: String = MedicationTrendDashboardBuilder.defaultSafetyNote,
        metrics: [MedicationTrendMetric]
    ) {
        self.overallScore = overallScore
        self.direction = direction
        self.title = title
        self.summary = summary
        self.disciplineSummary = disciplineSummary
        self.confidenceScore = confidenceScore
        self.dataQualitySummary = dataQualitySummary
        self.safetyNote = safetyNote
        self.metrics = metrics
    }
}
