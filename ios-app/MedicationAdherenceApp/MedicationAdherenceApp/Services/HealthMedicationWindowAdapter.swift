import Foundation
import MedicationAdherenceCore
import SwiftData

/// A caller-supplied health-review window, never recomputed from today or a day count.
struct HealthMedicationWindowRequest {
    let start: Date
    let end: Date
    let timeZoneIdentifier: String
    let healthGeneratedAt: Date?
    /// Time of this medication read attempt, independent of the health snapshot.
    let medicationSnapshotAt: Date
}

/// Only complete, bounded reads may use `complete`. Never pass a truncated prefix.
/// Model instances stay on the main actor; only the Core value result leaves it.
@MainActor
enum HealthMedicationWindowFetchResult {
    case complete(tasks: [StoredDoseTask], medications: [StoredMedication])
    case failed
    case budgetExceeded
}

/// Read-only App boundary. No HealthKit, consent, AI, status mutation, or event conversion.
@MainActor
struct HealthMedicationWindowAdapter {
    static let maximumTaskCount = 2_048
    static let maximumMedicationCount = 256

    /// A fresh context avoids presenting another context's uncommitted edits as saved facts.
    /// Both queries are bounded; any overflow or thrown fetch discards all partial rows.
    /// This is a synchronous read, not a cross-store/HealthKit atomic snapshot guarantee.
    func read(
        from container: ModelContainer,
        request: HealthMedicationWindowRequest,
        taskBudget: Int = HealthMedicationWindowAdapter.maximumTaskCount,
        medicationBudget: Int = HealthMedicationWindowAdapter.maximumMedicationCount
    ) -> HealthMedicationWindowReviewResult {
        let validation = project(.complete(tasks: [], medications: []), request: request)
        guard validation.availability != .invalidInput else { return validation }
        guard (1...Self.maximumTaskCount).contains(taskBudget),
              (1...Self.maximumMedicationCount).contains(medicationBudget) else {
            return project(.budgetExceeded, request: request)
        }
        let context = ModelContext(container)
        context.autosaveEnabled = false
        let start = request.start
        let end = request.end
        var tasksQuery = FetchDescriptor<StoredDoseTask>(
            predicate: #Predicate { $0.dueAt >= start && $0.dueAt < end }
        )
        tasksQuery.fetchLimit = taskBudget + 1
        tasksQuery.includePendingChanges = false
        do {
            let tasks = try context.fetch(tasksQuery)
            guard tasks.count <= taskBudget else {
                return project(.budgetExceeded, request: request)
            }
            // UUID foreign key join. There is no SwiftData @Relationship on these models.
            let medicationIDs = Array(Set(tasks.map(\.medicationID)))
            guard medicationIDs.count <= medicationBudget else {
                return project(.budgetExceeded, request: request)
            }
            guard !tasks.isEmpty else { return validation }
            var medicationsQuery = FetchDescriptor<StoredMedication>(
                predicate: #Predicate { medicationIDs.contains($0.id) }
            )
            medicationsQuery.fetchLimit = medicationBudget + 1
            medicationsQuery.includePendingChanges = false
            let medications = try context.fetch(medicationsQuery)
            guard medications.count <= medicationBudget else {
                return project(.budgetExceeded, request: request)
            }
            return project(.complete(tasks: tasks, medications: medications), request: request)
        } catch {
            // Do not log localized errors or identifiers that could disclose health content.
            return project(.failed, request: request)
        }
    }

    /// Also accepts a caller-owned bounded fetch result. Missing medication rows yield nil
    /// names, not invented facts; a failed medication query must be `.failed`, not an empty join.
    func project(
        _ fetched: HealthMedicationWindowFetchResult,
        request: HealthMedicationWindowRequest
    ) -> HealthMedicationWindowReviewResult {
        func build(_ status: HealthMedicationWindowReadStatus,
                   records: [HealthMedicationWindowRecord] = []) -> HealthMedicationWindowReviewResult {
            HealthMedicationWindowReview().build(HealthMedicationWindowReviewInput(
                start: request.start, end: request.end,
                timeZoneIdentifier: request.timeZoneIdentifier,
                healthGeneratedAt: request.healthGeneratedAt,
                medicationSnapshotAt: request.medicationSnapshotAt,
                readStatus: status, records: records
            ))
        }
        switch fetched {
        case .failed:
            return build(.failure)
        case .budgetExceeded:
            return build(.budgetExceeded)
        case let .complete(tasks, medications):
            guard tasks.count <= HealthMedicationWindowAdapter.maximumTaskCount,
                  medications.count <= HealthMedicationWindowAdapter.maximumMedicationCount else {
                return build(.budgetExceeded)
            }
            var names: [UUID: String] = [:]
            for medication in medications {
                // Never choose arbitrarily if a caller supplies conflicting foreign-key rows.
                guard names[medication.id] == nil else { return build(.failure) }
                names[medication.id] = medication.displayName
            }
            return build(.success, records: tasks.map { task in
                HealthMedicationWindowRecord(
                    taskID: task.id, medicationID: task.medicationID,
                    medicationName: names[task.medicationID], dueAt: task.dueAt,
                    statusRaw: task.statusRaw, recordedAt: task.recordedAt
                )
            })
        }
    }
}
