import SwiftData
import SwiftUI

@main
struct MedicationAdherenceApp: App {
    private let modelContainer: ModelContainer

    init() {
        do {
            let schema = Schema([
                StoredMedication.self,
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
            let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
            modelContainer = try ModelContainer(for: schema, configurations: [configuration])
            MedicationNotificationDelegate.shared.install(modelContainer: modelContainer)
        } catch {
            fatalError("Unable to create SwiftData container: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            AppRootView()
        }
        .modelContainer(modelContainer)
    }
}
