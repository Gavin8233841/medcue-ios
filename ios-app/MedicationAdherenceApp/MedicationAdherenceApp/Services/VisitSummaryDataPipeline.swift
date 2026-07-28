import Foundation
import MedicationAdherenceCore
import SwiftData

@MainActor
struct VisitSummaryStoredData {
    let medications: [StoredMedication]
    let tasks: [StoredDoseTask]
    let doseChanges: [StoredMedicationDoseChange]
    let plans: [StoredMedicationPlan]
    let lifecycleEvents: [StoredMedicationLifecycleEvent]
    let riskCards: [StoredRiskCard]
}

enum VisitSummaryDataLoadOutcome {
    case loaded(VisitSummaryStoredData)
    case rejected
    case failed(VisitSummaryDataLoadStage)
}

enum VisitSummaryDataLoadStage: String {
    case tasks
    case doseChanges
    case risks
    case medications
    case plans
    case lifecycleEvents
}

@MainActor
struct VisitSummaryDataCommand {
    let modelContext: ModelContext

    func load(startDate: Date, endDate: Date) -> VisitSummaryDataLoadOutcome {
        guard startDate <= endDate, !Task.isCancelled else {
            return .rejected
        }

        let tasks: [StoredDoseTask]
        do {
            let taskContextInterval: TimeInterval = 24 * 60 * 60
            let queryStartDate = startDate.addingTimeInterval(-taskContextInterval)
            let queryEndDate = endDate.addingTimeInterval(taskContextInterval)
            let dueTaskDescriptor = FetchDescriptor<StoredDoseTask>(
                predicate: #Predicate { task in
                    task.dueAt >= queryStartDate && task.dueAt <= queryEndDate
                },
                sortBy: [SortDescriptor(\StoredDoseTask.dueAt)]
            )
            tasks = try modelContext.fetch(dueTaskDescriptor).filter { task in
                let effectiveDate = task.effectiveAdherenceDate
                return effectiveDate >= startDate && effectiveDate <= endDate
            }
        } catch {
            return .failed(.tasks)
        }
        guard !Task.isCancelled else { return .rejected }

        let doseChanges: [StoredMedicationDoseChange]
        do {
            doseChanges = try modelContext.fetch(FetchDescriptor<StoredMedicationDoseChange>(
                predicate: #Predicate { change in
                    change.effectiveFrom >= startDate && change.effectiveFrom <= endDate
                },
                sortBy: [SortDescriptor(\StoredMedicationDoseChange.effectiveFrom, order: .reverse)]
            ))
        } catch {
            return .failed(.doseChanges)
        }
        guard !Task.isCancelled else { return .rejected }

        let riskCards: [StoredRiskCard]
        do {
            riskCards = try modelContext.fetch(FetchDescriptor<StoredRiskCard>(
                predicate: #Predicate { card in
                    card.lastDetectedAt >= startDate && card.lastDetectedAt <= endDate
                },
                sortBy: [
                    SortDescriptor(\StoredRiskCard.displayPriority),
                    SortDescriptor(\StoredRiskCard.lastDetectedAt, order: .reverse)
                ]
            ))
        } catch {
            return .failed(.risks)
        }

        let medicationIDs = Set(tasks.map(\.medicationID))
            .union(doseChanges.map(\.medicationID))
            .union(riskCards.map(\.medicationID))
        guard !medicationIDs.isEmpty else {
            return .loaded(VisitSummaryStoredData(
                medications: [],
                tasks: [],
                doseChanges: [],
                plans: [],
                lifecycleEvents: [],
                riskCards: []
            ))
        }
        guard !Task.isCancelled else { return .rejected }

        let medications: [StoredMedication]
        do {
            medications = try modelContext.fetch(FetchDescriptor<StoredMedication>(
                predicate: #Predicate { medication in
                    medicationIDs.contains(medication.id)
                },
                sortBy: [SortDescriptor(\StoredMedication.displayName)]
            ))
        } catch {
            return .failed(.medications)
        }
        let plans: [StoredMedicationPlan]
        do {
            plans = try modelContext.fetch(FetchDescriptor<StoredMedicationPlan>(
                predicate: #Predicate { plan in
                    medicationIDs.contains(plan.medicationID)
                },
                sortBy: [SortDescriptor(\StoredMedicationPlan.createdAt)]
            ))
        } catch {
            return .failed(.plans)
        }
        let lifecycleEvents: [StoredMedicationLifecycleEvent]
        do {
            lifecycleEvents = try modelContext.fetch(FetchDescriptor<StoredMedicationLifecycleEvent>(
                predicate: #Predicate { event in
                    medicationIDs.contains(event.medicationID) && event.occurredAt <= endDate
                },
                sortBy: [SortDescriptor(\StoredMedicationLifecycleEvent.occurredAt, order: .reverse)]
            ))
        } catch {
            return .failed(.lifecycleEvents)
        }
        guard !Task.isCancelled else { return .rejected }
        return .loaded(VisitSummaryStoredData(
            medications: medications,
            tasks: tasks,
            doseChanges: doseChanges,
            plans: plans,
            lifecycleEvents: lifecycleEvents,
            riskCards: riskCards
        ))
    }
}

struct VisitSummaryGenerationGate: Sendable {
    private var currentID: UUID?

    mutating func begin() -> UUID {
        let id = UUID()
        currentID = id
        return id
    }

    func accepts(_ id: UUID) -> Bool {
        currentID == id
    }

    mutating func cancel() {
        currentID = nil
    }
}

struct VisitSummaryMedicationValue: Sendable, Equatable {
    let id: UUID
    let displayName: String
    let form: String
    let strength: String
    let isArchived: Bool

    @MainActor
    init(_ medication: StoredMedication) {
        id = medication.id
        displayName = userFacingMedicationName(for: medication)
        form = medication.form
        strength = medication.strength
        isArchived = medication.lifecycleStatus == .archived
    }
}

struct VisitSummaryTaskValue: Sendable, Equatable {
    let id: UUID
    let medicationID: UUID
    let planID: UUID
    let dueAt: Date
    let doseValue: Double
    let doseUnit: String
    let statusRaw: String
    let effectiveRecordedAt: Date?
    let reason: String

    @MainActor
    init(_ task: StoredDoseTask) {
        id = task.id
        medicationID = task.medicationID
        planID = task.planID
        dueAt = task.dueAt
        doseValue = task.doseValue
        doseUnit = task.doseUnit
        statusRaw = task.statusRaw
        effectiveRecordedAt = task.effectiveAdherenceRecordedAt
        reason = task.reason
    }

    var effectiveAdherenceDate: Date { effectiveRecordedAt ?? dueAt }
    var isTaken: Bool { statusRaw == StoredDoseStatus.taken.rawValue || statusRaw == StoredDoseStatus.corrected.rawValue }
    var isSkipped: Bool { statusRaw == StoredDoseStatus.skipped.rawValue }
    var isDelayed: Bool { statusRaw == StoredDoseStatus.delayed.rawValue }

    var coreScheduledDose: ScheduledDose {
        ScheduledDose(
            id: id,
            planID: planID,
            dueAt: dueAt,
            dose: DoseAmount(value: Decimal(doseValue), unit: doseUnit)
        )
    }

    var coreDoseEvent: DoseEvent? {
        let status: DoseEventStatus?
        switch statusRaw {
        case StoredDoseStatus.taken.rawValue:
            status = .taken
        case StoredDoseStatus.skipped.rawValue:
            status = .skipped
        case StoredDoseStatus.delayed.rawValue:
            status = .delayed
        case StoredDoseStatus.corrected.rawValue:
            status = .corrected
        default:
            status = nil
        }
        guard let status else { return nil }
        return DoseEvent(
            scheduledDoseID: id,
            status: status,
            recordedAt: effectiveAdherenceDate,
            reason: reason.isEmpty ? nil : reason
        )
    }
}

struct VisitSummaryDoseChangeValue: Sendable, Equatable {
    let id: UUID
    let medicationID: UUID
    let planID: UUID?
    let previousDoseValue: Double?
    let previousDoseUnit: String
    let newDoseValue: Double
    let newDoseUnit: String
    let effectiveFrom: Date

    @MainActor
    init(_ change: StoredMedicationDoseChange) {
        id = change.id
        medicationID = change.medicationID
        planID = change.planID
        previousDoseValue = change.previousDoseValue
        previousDoseUnit = change.previousDoseUnit
        newDoseValue = change.newDoseValue
        newDoseUnit = change.newDoseUnit
        effectiveFrom = change.effectiveFrom
    }
}

struct VisitSummaryRiskValue: Sendable, Equatable {
    let id: String
    let medicationID: UUID
    let kindRaw: String
    let severityRaw: String
    let displayPriority: Int
    let title: String
    let message: String
    let sourceTitle: String
    let sourceExcerpt: String
    let requiresProfessionalReview: Bool
    let lastDetectedAt: Date
    let isActive: Bool
    let coreRiskCard: RiskAssessmentCard

    @MainActor
    init(_ card: StoredRiskCard) {
        id = card.id
        medicationID = card.medicationID
        kindRaw = card.kindRaw
        severityRaw = card.severityRaw
        displayPriority = card.displayPriority
        title = card.title
        message = card.message
        sourceTitle = card.sourceTitle
        sourceExcerpt = card.sourceExcerpt
        requiresProfessionalReview = card.requiresProfessionalReview
        lastDetectedAt = card.lastDetectedAt
        isActive = card.isActive
        coreRiskCard = card.coreRiskCard
    }

    var isHighSeverity: Bool {
        severityRaw == StoredRiskSeverity.high.rawValue || severityRaw == StoredRiskSeverity.critical.rawValue
    }
}

struct VisitSummaryExportPayload: Sendable, Equatable {
    let medications: [VisitSummaryMedicationValue]
    let tasks: [VisitSummaryTaskValue]
    let doseChanges: [VisitSummaryDoseChangeValue]
    let riskCards: [VisitSummaryRiskValue]
    let trendDashboard: MedicationTrendDashboard
    let healthSignals: [HealthSignalSample]
    let startDate: Date
    let endDate: Date
    let generatedAt: Date
    let exportSignature: String

    @MainActor
    init(
        data: VisitSummaryStoredData,
        trendDashboard: MedicationTrendDashboard,
        healthSignals: [HealthSignalSample],
        startDate: Date,
        endDate: Date,
        generatedAt: Date,
        exportSignature: String
    ) {
        self.init(
            medications: data.medications,
            tasks: data.tasks,
            doseChanges: data.doseChanges,
            riskCards: data.riskCards,
            trendDashboard: trendDashboard,
            healthSignals: healthSignals,
            startDate: startDate,
            endDate: endDate,
            generatedAt: generatedAt,
            exportSignature: exportSignature
        )
    }

    @MainActor
    init(
        medications: [StoredMedication],
        tasks: [StoredDoseTask],
        doseChanges: [StoredMedicationDoseChange],
        riskCards: [StoredRiskCard],
        trendDashboard: MedicationTrendDashboard,
        healthSignals: [HealthSignalSample],
        startDate: Date,
        endDate: Date,
        generatedAt: Date,
        exportSignature: String
    ) {
        self.medications = medications.map(VisitSummaryMedicationValue.init)
        self.tasks = tasks.map(VisitSummaryTaskValue.init)
        self.doseChanges = doseChanges.map(VisitSummaryDoseChangeValue.init)
        self.riskCards = riskCards.map(VisitSummaryRiskValue.init)
        self.trendDashboard = trendDashboard
        self.healthSignals = healthSignals
        self.startDate = startDate
        self.endDate = endDate
        self.generatedAt = generatedAt
        self.exportSignature = exportSignature
    }
}
