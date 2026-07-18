import SwiftData

enum MedicationAdherenceModelContainer {
    static var schema: Schema {
        Schema([
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
        ])
    }

    static func make(isStoredInMemoryOnly: Bool = false) throws -> ModelContainer {
        let schema = schema
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: isStoredInMemoryOnly
        )
        return try ModelContainer(for: schema, configurations: [configuration])
    }
}
