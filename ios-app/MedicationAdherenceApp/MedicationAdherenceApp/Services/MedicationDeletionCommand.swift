import Foundation
import SwiftData

struct MedicationDeletionCommit {
    let medicationID: UUID
    let taskIDs: [UUID]
}

enum MedicationDeletionRejection: Equatable {
    case medicationNotFound
    case medicationNotArchived
    case readFailed
}

enum MedicationDeletionCommandOutcome {
    case committed(MedicationDeletionCommit)
    case rejected(MedicationDeletionRejection)
    case saveFailed
}

@MainActor
struct MedicationDeletionCommand {
    typealias SaveOperation = (ModelContext) throws -> Void

    private let modelContext: ModelContext
    private let saveOperation: SaveOperation

    init(
        modelContext: ModelContext,
        saveOperation: @escaping SaveOperation = { try $0.save() }
    ) {
        self.modelContext = modelContext
        self.saveOperation = saveOperation
    }

    func delete(medicationID: UUID) -> MedicationDeletionCommandOutcome {
        let graph: MedicationDeletionGraph
        do {
            guard let medication = try fetchMedication(id: medicationID) else {
                return .rejected(.medicationNotFound)
            }
            guard medication.lifecycleStatus == .archived else {
                return .rejected(.medicationNotArchived)
            }
            graph = try fetchGraph(medication: medication)
        } catch {
            return .rejected(.readFailed)
        }

        graph.delete(from: modelContext)
        do {
            try saveOperation(modelContext)
            return .committed(
                MedicationDeletionCommit(
                    medicationID: medicationID,
                    taskIDs: graph.tasks.map(\.id).sorted { $0.uuidString < $1.uuidString }
                )
            )
        } catch {
            modelContext.rollback()
            AppPersistenceCommitter.reportFailure(operation: "medication-delete-archived")
            return .saveFailed
        }
    }

    private func fetchMedication(id medicationID: UUID) throws -> StoredMedication? {
        var descriptor = FetchDescriptor<StoredMedication>(
            predicate: #Predicate { medication in
                medication.id == medicationID
            }
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    private func fetchGraph(medication: StoredMedication) throws -> MedicationDeletionGraph {
        let medicationID = medication.id
        let tasks = try modelContext.fetch(
            FetchDescriptor<StoredDoseTask>(
                predicate: #Predicate { task in
                    task.medicationID == medicationID
                }
            )
        )
        let taskIDs = tasks.map(\.id)
        let actionLogs = try modelContext.fetch(
            FetchDescriptor<StoredDoseActionLog>(
                predicate: #Predicate { log in
                    taskIDs.contains(log.taskID)
                }
            )
        )
        return MedicationDeletionGraph(
            medication: medication,
            plans: try modelContext.fetch(FetchDescriptor<StoredMedicationPlan>(
                predicate: #Predicate { $0.medicationID == medicationID }
            )),
            doseChanges: try modelContext.fetch(FetchDescriptor<StoredMedicationDoseChange>(
                predicate: #Predicate { $0.medicationID == medicationID }
            )),
            tasks: tasks,
            actionLogs: actionLogs,
            riskCards: try modelContext.fetch(FetchDescriptor<StoredRiskCard>(
                predicate: #Predicate { $0.medicationID == medicationID }
            )),
            stocks: try modelContext.fetch(FetchDescriptor<StoredMedicationStock>(
                predicate: #Predicate { $0.medicationID == medicationID }
            )),
            labels: try modelContext.fetch(FetchDescriptor<StoredMedicationLabel>(
                predicate: #Predicate { $0.medicationID == medicationID }
            )),
            lifecycleEvents: try modelContext.fetch(FetchDescriptor<StoredMedicationLifecycleEvent>(
                predicate: #Predicate { $0.medicationID == medicationID }
            ))
        )
    }
}

private struct MedicationDeletionGraph {
    let medication: StoredMedication
    let plans: [StoredMedicationPlan]
    let doseChanges: [StoredMedicationDoseChange]
    let tasks: [StoredDoseTask]
    let actionLogs: [StoredDoseActionLog]
    let riskCards: [StoredRiskCard]
    let stocks: [StoredMedicationStock]
    let labels: [StoredMedicationLabel]
    let lifecycleEvents: [StoredMedicationLifecycleEvent]

    @MainActor
    func delete(from modelContext: ModelContext) {
        actionLogs.forEach(modelContext.delete)
        tasks.forEach(modelContext.delete)
        plans.forEach(modelContext.delete)
        doseChanges.forEach(modelContext.delete)
        riskCards.forEach(modelContext.delete)
        stocks.forEach(modelContext.delete)
        labels.forEach(modelContext.delete)
        lifecycleEvents.forEach(modelContext.delete)
        modelContext.delete(medication)
    }
}
