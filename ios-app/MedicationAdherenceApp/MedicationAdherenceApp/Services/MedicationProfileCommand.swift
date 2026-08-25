import Foundation
import MedicationAdherenceCore
import SwiftData

struct MedicationProfileUpdate: Equatable, Sendable {
    let medicationID: UUID
    let displayName: String
    let genericName: String
    let strength: String
    let form: String
    let kind: MedicationKind
    let photoData: Data?
    let photoSymbolName: String
    let colorTagRaw: String
    let boxNumber: String
    let notes: String
}

struct MedicationPhotoUpdate: Equatable, Sendable {
    let medicationID: UUID
    let photoData: Data?
}

enum MedicationProfileRejection: Equatable {
    case invalidDisplayName
    case medicationNotFound
    case readFailed
}

enum MedicationProfileCommandOutcome: Equatable {
    case committed(medicationID: UUID)
    case rejected(MedicationProfileRejection)
    case saveFailed
}

@MainActor
struct MedicationProfileCommand {
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

    func update(_ update: MedicationProfileUpdate) -> MedicationProfileCommandOutcome {
        guard let normalizedDisplayName = MedicationNamePolicy.normalizedDisplayName(update.displayName) else {
            return .rejected(.invalidDisplayName)
        }

        let medication: StoredMedication
        do {
            guard let storedMedication = try fetchMedication(id: update.medicationID) else {
                return .rejected(.medicationNotFound)
            }
            medication = storedMedication
        } catch {
            return .rejected(.readFailed)
        }

        let snapshot = MedicationProfileSnapshot(medication)
        medication.displayName = normalizedDisplayName
        medication.genericName = update.genericName.trimmingCharacters(in: .whitespacesAndNewlines)
        medication.strength = update.strength
        medication.form = update.form
        medication.kindRaw = update.kind.rawValue
        medication.photoData = update.photoData
        medication.photoSymbolName = update.photoSymbolName
        medication.colorTagRaw = update.colorTagRaw
        medication.boxNumber = update.boxNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        medication.notes = update.notes

        do {
            try ModelContextPerformanceMetrics.measureSave(operation: "profile-update-medication") {
                try saveOperation(modelContext)
            }
            return .committed(medicationID: medication.id)
        } catch {
            snapshot.restore()
            modelContext.rollback()
            AppPersistenceCommitter.reportFailure(operation: "medication-profile-update")
            return .saveFailed
        }
    }

    func updatePhoto(_ update: MedicationPhotoUpdate) -> MedicationProfileCommandOutcome {
        let medication: StoredMedication
        do {
            guard let storedMedication = try fetchMedication(id: update.medicationID) else {
                return .rejected(.medicationNotFound)
            }
            medication = storedMedication
        } catch {
            return .rejected(.readFailed)
        }

        let previousPhotoData = medication.photoData
        medication.photoData = update.photoData
        do {
            try ModelContextPerformanceMetrics.measureSave(operation: "profile-update-photo") {
                try saveOperation(modelContext)
            }
            return .committed(medicationID: medication.id)
        } catch {
            medication.photoData = previousPhotoData
            modelContext.rollback()
            AppPersistenceCommitter.reportFailure(operation: "medication-photo-update")
            return .saveFailed
        }
    }

    private func fetchMedication(id: UUID) throws -> StoredMedication? {
        try ModelContextPerformanceMetrics.measureFetch(operation: "profile-fetch-medication-by-id") {
            var descriptor = FetchDescriptor<StoredMedication>(
                predicate: #Predicate<StoredMedication> { medication in
                    medication.id == id
                }
            )
            descriptor.fetchLimit = 1
            return try modelContext.fetch(descriptor).first
        }
    }
}

private struct MedicationProfileSnapshot {
    let medication: StoredMedication
    let displayName: String
    let genericName: String
    let strength: String
    let form: String
    let kindRaw: String
    let photoData: Data?
    let photoSymbolName: String
    let colorTagRaw: String
    let boxNumber: String
    let notes: String

    init(_ medication: StoredMedication) {
        self.medication = medication
        displayName = medication.displayName
        genericName = medication.genericName
        strength = medication.strength
        form = medication.form
        kindRaw = medication.kindRaw
        photoData = medication.photoData
        photoSymbolName = medication.photoSymbolName
        colorTagRaw = medication.colorTagRaw
        boxNumber = medication.boxNumber
        notes = medication.notes
    }

    func restore() {
        medication.displayName = displayName
        medication.genericName = genericName
        medication.strength = strength
        medication.form = form
        medication.kindRaw = kindRaw
        medication.photoData = photoData
        medication.photoSymbolName = photoSymbolName
        medication.colorTagRaw = colorTagRaw
        medication.boxNumber = boxNumber
        medication.notes = notes
    }
}
