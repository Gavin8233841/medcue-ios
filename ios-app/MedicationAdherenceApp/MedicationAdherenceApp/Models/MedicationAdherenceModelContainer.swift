import Foundation
import SwiftData

enum MedicationAdherenceModelContainer {
    static var schema: Schema {
        Schema(versionedSchema: MedicationAdherenceSchemaV2.self)
    }

    static func make(isStoredInMemoryOnly: Bool = false) throws -> ModelContainer {
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: isStoredInMemoryOnly
        )
        return try make(configuration: configuration)
    }

    static func make(storeURL: URL) throws -> ModelContainer {
        let configuration = ModelConfiguration(
            "MedicationAdherence",
            schema: schema,
            url: storeURL,
            cloudKitDatabase: .none
        )
        return try make(configuration: configuration)
    }

    private static func make(configuration: ModelConfiguration) throws -> ModelContainer {
        try ModelContainer(
            for: schema,
            migrationPlan: MedicationAdherenceSchemaMigrationPlan.self,
            configurations: [configuration]
        )
    }
}

enum MedicationAdherenceSchemaV1: VersionedSchema {
    static var versionIdentifier = Schema.Version(1, 0, 0)

    static var models: [any PersistentModel.Type] {
        [
            StoredMedication.self,
            StoredMedicationLifecycleEvent.self,
            StoredMedicationPlan.self,
            StoredMedicationDoseChange.self,
            StoredDoseTask.self,
            StoredRiskCard.self,
            StoredMedicationLabel.self,
            StoredMedicationStock.self,
            StoredDoseActionLog.self,
            StoredAIConsent.self,
            StoredAIChatMessage.self
        ]
    }

    @Model
    final class StoredMedication {
        @Attribute(.unique) var id: UUID
        var displayName: String
        var genericName: String
        var kindRaw: String
        var form: String
        var strength: String
        var inputSourceRaw: String
        var photoSymbolName: String
        var photoData: Data?
        var boxNumber: String = ""
        var notes: String
        var lifecycleStatusRaw: String = StoredMedicationLifecycleStatus.active.rawValue
        var isDemoContent: Bool = false
        var createdAt: Date

        init(
            id: UUID = UUID(),
            displayName: String,
            genericName: String = "",
            kindRaw: String,
            form: String = "",
            strength: String = "",
            inputSourceRaw: String,
            photoSymbolName: String = "pills.fill",
            photoData: Data? = nil,
            boxNumber: String = "",
            notes: String = "",
            lifecycleStatusRaw: String = StoredMedicationLifecycleStatus.active.rawValue,
            isDemoContent: Bool = false,
            createdAt: Date = Date()
        ) {
            self.id = id
            self.displayName = displayName
            self.genericName = genericName
            self.kindRaw = kindRaw
            self.form = form
            self.strength = strength
            self.inputSourceRaw = inputSourceRaw
            self.photoSymbolName = photoSymbolName
            self.photoData = photoData
            self.boxNumber = boxNumber
            self.notes = notes
            self.lifecycleStatusRaw = lifecycleStatusRaw
            self.isDemoContent = isDemoContent
            self.createdAt = createdAt
        }
    }

    @Model
    final class StoredMedicationPlan {
        @Attribute(.unique) var id: UUID
        var medicationID: UUID
        var doseValue: Double
        var doseUnit: String
        var timingSummary: String
        var timeZonePolicyRaw: String
        var sourceNote: String
        var requiresUserConfirmation: Bool
        var courseStartAt: Date?
        var courseEndAt: Date?
        var reminderTimesRaw: String?
        var reminderDeliveryRaw: String?
        var createdAt: Date

        init(
            id: UUID = UUID(),
            medicationID: UUID,
            doseValue: Double,
            doseUnit: String,
            timingSummary: String,
            timeZonePolicyRaw: String,
            sourceNote: String,
            requiresUserConfirmation: Bool = true,
            courseStartAt: Date? = nil,
            courseEndAt: Date? = nil,
            reminderTimesRaw: String? = nil,
            reminderDeliveryRaw: String? = StoredReminderDeliveryMethod.notification.rawValue,
            createdAt: Date = Date()
        ) {
            self.id = id
            self.medicationID = medicationID
            self.doseValue = doseValue
            self.doseUnit = doseUnit
            self.timingSummary = timingSummary
            self.timeZonePolicyRaw = timeZonePolicyRaw
            self.sourceNote = sourceNote
            self.requiresUserConfirmation = requiresUserConfirmation
            self.courseStartAt = courseStartAt
            self.courseEndAt = courseEndAt
            self.reminderTimesRaw = reminderTimesRaw
            self.reminderDeliveryRaw = reminderDeliveryRaw
            self.createdAt = createdAt
        }
    }
}

enum MedicationAdherenceSchemaV2: VersionedSchema {
    static var versionIdentifier = Schema.Version(2, 0, 0)

    static var models: [any PersistentModel.Type] {
        [
            StoredMedication.self,
            StoredMedicationLifecycleEvent.self,
            StoredMedicationPlan.self,
            StoredMedicationDoseChange.self,
            StoredDoseTask.self,
            StoredRiskCard.self,
            StoredMedicationLabel.self,
            StoredMedicationStock.self,
            StoredDoseActionLog.self,
            StoredAIConsent.self,
            StoredAIChatMessage.self
        ]
    }
}

enum MedicationAdherenceSchemaMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [
            MedicationAdherenceSchemaV1.self,
            MedicationAdherenceSchemaV2.self
        ]
    }

    static var stages: [MigrationStage] {
        [
            .lightweight(
                fromVersion: MedicationAdherenceSchemaV1.self,
                toVersion: MedicationAdherenceSchemaV2.self
            )
        ]
    }
}
