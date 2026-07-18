import Foundation
import SwiftData
import Testing
@testable import MedicationAdherenceApp

struct MedicationAdherenceAppTests {
    @Test
    func inMemoryContainerPersistsAcrossModelContexts() throws {
        let container = try MedicationAdherenceModelContainer.make(isStoredInMemoryOnly: true)
        let messageID = UUID()
        let writeContext = ModelContext(container)
        writeContext.insert(StoredAIChatMessage(
            id: messageID,
            role: .user,
            text: "SwiftData round-trip",
            providerName: "test-provider",
            modelName: "test-model"
        ))

        try writeContext.save()

        let readContext = ModelContext(container)
        let messages = try readContext.fetch(FetchDescriptor<StoredAIChatMessage>())
        let reloadedMessage = try #require(messages.first { $0.id == messageID })

        #expect(reloadedMessage.text == "SwiftData round-trip")
        #expect(reloadedMessage.role == .user)
        #expect(reloadedMessage.providerName == "test-provider")
        #expect(reloadedMessage.modelName == "test-model")
    }

    @Test
    func schemaSupportsEveryStoredModel() throws {
        let container = try MedicationAdherenceModelContainer.make(isStoredInMemoryOnly: true)
        let context = ModelContext(container)

        #expect(try context.fetch(FetchDescriptor<StoredMedication>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<StoredMedicationLifecycleEvent>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<StoredMedicationPlan>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<StoredMedicationDoseChange>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<StoredDoseTask>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<StoredRiskCard>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<StoredMedicationLabel>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<StoredMedicationStock>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<StoredDoseActionLog>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<StoredAIConsent>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<StoredAIChatMessage>()).isEmpty)
    }
}
