import Foundation
import SwiftData

enum PersistenceIntegrityIssueKind: String, CaseIterable, Hashable, Sendable {
    case orphanPlanMedication
    case orphanDoseChangeMedication
    case orphanDoseChangePlan
    case doseChangePlanMedicationMismatch
    case orphanDoseTaskMedication
    case orphanDoseTaskPlan
    case doseTaskPlanMedicationMismatch
    case orphanRiskMedication
    case orphanLabelMedication
    case orphanStockMedication
    case orphanLifecycleMedication
    case orphanActionLogTask
}

struct PersistenceIntegrityIssue: Equatable, Hashable, Sendable {
    let kind: PersistenceIntegrityIssueKind
    let recordID: String
    let missingReferenceID: UUID?
}

struct PersistenceIntegrityReport: Equatable, Sendable {
    let issues: [PersistenceIntegrityIssue]

    var isClean: Bool { issues.isEmpty }

    func count(for kind: PersistenceIntegrityIssueKind) -> Int {
        issues.lazy.filter { $0.kind == kind }.count
    }
}

@MainActor
struct PersistenceIntegrityAuditor {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func audit() throws -> PersistenceIntegrityReport {
        let medications = try modelContext.fetch(FetchDescriptor<StoredMedication>())
        let plans = try modelContext.fetch(FetchDescriptor<StoredMedicationPlan>())
        let doseChanges = try modelContext.fetch(FetchDescriptor<StoredMedicationDoseChange>())
        let tasks = try modelContext.fetch(FetchDescriptor<StoredDoseTask>())
        let risks = try modelContext.fetch(FetchDescriptor<StoredRiskCard>())
        let labels = try modelContext.fetch(FetchDescriptor<StoredMedicationLabel>())
        let stocks = try modelContext.fetch(FetchDescriptor<StoredMedicationStock>())
        let lifecycleEvents = try modelContext.fetch(FetchDescriptor<StoredMedicationLifecycleEvent>())
        let actionLogs = try modelContext.fetch(FetchDescriptor<StoredDoseActionLog>())

        let medicationIDs = Set(medications.map(\.id))
        let planMedicationIDs = Dictionary(uniqueKeysWithValues: plans.map { ($0.id, $0.medicationID) })
        let taskIDs = Set(tasks.map(\.id))
        var issues: [PersistenceIntegrityIssue] = []

        for plan in plans where !medicationIDs.contains(plan.medicationID) {
            issues.append(issue(.orphanPlanMedication, recordID: plan.id, referenceID: plan.medicationID))
        }

        for change in doseChanges {
            if !medicationIDs.contains(change.medicationID) {
                issues.append(issue(.orphanDoseChangeMedication, recordID: change.id, referenceID: change.medicationID))
            }
            if let planID = change.planID {
                guard let planMedicationID = planMedicationIDs[planID] else {
                    issues.append(issue(.orphanDoseChangePlan, recordID: change.id, referenceID: planID))
                    continue
                }
                if planMedicationID != change.medicationID {
                    issues.append(issue(.doseChangePlanMedicationMismatch, recordID: change.id, referenceID: planID))
                }
            }
        }

        for task in tasks {
            if !medicationIDs.contains(task.medicationID) {
                issues.append(issue(.orphanDoseTaskMedication, recordID: task.id, referenceID: task.medicationID))
            }
            guard let planMedicationID = planMedicationIDs[task.planID] else {
                issues.append(issue(.orphanDoseTaskPlan, recordID: task.id, referenceID: task.planID))
                continue
            }
            if planMedicationID != task.medicationID {
                issues.append(issue(.doseTaskPlanMedicationMismatch, recordID: task.id, referenceID: task.planID))
            }
        }

        for risk in risks where !medicationIDs.contains(risk.medicationID) {
            issues.append(PersistenceIntegrityIssue(
                kind: .orphanRiskMedication,
                recordID: risk.id,
                missingReferenceID: risk.medicationID
            ))
        }
        for label in labels where !medicationIDs.contains(label.medicationID) {
            issues.append(issue(.orphanLabelMedication, recordID: label.id, referenceID: label.medicationID))
        }
        for stock in stocks where !medicationIDs.contains(stock.medicationID) {
            issues.append(issue(.orphanStockMedication, recordID: stock.id, referenceID: stock.medicationID))
        }
        for event in lifecycleEvents where !medicationIDs.contains(event.medicationID) {
            issues.append(issue(.orphanLifecycleMedication, recordID: event.id, referenceID: event.medicationID))
        }
        for log in actionLogs where !taskIDs.contains(log.taskID) {
            issues.append(issue(.orphanActionLogTask, recordID: log.id, referenceID: log.taskID))
        }

        return PersistenceIntegrityReport(issues: issues.sorted {
            ($0.kind.rawValue, $0.recordID) < ($1.kind.rawValue, $1.recordID)
        })
    }

    private func issue(
        _ kind: PersistenceIntegrityIssueKind,
        recordID: UUID,
        referenceID: UUID
    ) -> PersistenceIntegrityIssue {
        PersistenceIntegrityIssue(
            kind: kind,
            recordID: recordID.uuidString,
            missingReferenceID: referenceID
        )
    }
}
