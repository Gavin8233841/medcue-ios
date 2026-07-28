import Foundation
import SwiftData
import Testing
@testable import MedicationAdherenceApp

@Suite(.serialized)
struct AIConversationPersistenceCommandTests {
    @Test @MainActor
    func messageBatchSaveFailureLeavesNoPartialConversation() throws {
        let container = try MedicationAdherenceModelContainer.make(isStoredInMemoryOnly: true)
        let context = ModelContext(container)
        context.autosaveEnabled = false
        let command = AIConversationPersistenceCommand(modelContext: context) { _ in
            throw SyntheticAIConversationSaveError.unavailable
        }

        let outcome = command.commitMessages([
            AIChatResponseDraft(
                role: .user,
                text: "这条用户消息不能半保存",
                providerName: "测试服务",
                modelName: "test-model",
                sharedScopesSummary: "药品信息"
            ),
            AIChatResponseDraft(
                role: .system,
                text: "这条系统消息也不能半保存",
                providerName: "测试服务",
                modelName: "test-model",
                sharedScopesSummary: "药品信息"
            )
        ], operation: "ai-test-message-batch")

        #expect(outcome == .saveFailed)
        #expect(try context.fetch(FetchDescriptor<StoredAIChatMessage>()).isEmpty)
        #expect(!context.hasChanges)
    }

    @Test @MainActor
    func deleteSaveFailureRestoresEveryMessage() throws {
        let container = try MedicationAdherenceModelContainer.make(isStoredInMemoryOnly: true)
        let context = ModelContext(container)
        context.autosaveEnabled = false
        let first = StoredAIChatMessage(role: .user, text: "保留一")
        let second = StoredAIChatMessage(role: .system, text: "保留二")
        context.insert(first)
        context.insert(second)
        try context.save()
        let command = AIConversationPersistenceCommand(modelContext: context) { _ in
            throw SyntheticAIConversationSaveError.unavailable
        }

        let outcome = command.deleteMessages(
            [first, second],
            operation: "ai-test-delete"
        )

        #expect(outcome == .saveFailed)
        let stored = try context.fetch(FetchDescriptor<StoredAIChatMessage>())
        #expect(Set(stored.map(\.id)) == [first.id, second.id])
        #expect(!context.hasChanges)
    }

    @Test @MainActor
    func consentSaveFailureRestoresPreviousAuthorization() throws {
        let container = try MedicationAdherenceModelContainer.make(isStoredInMemoryOnly: true)
        let context = ModelContext(container)
        context.autosaveEnabled = false
        let grantedAt = Date(timeIntervalSince1970: 100)
        let consent = StoredAIConsent(
            sharesMedicationProfile: true,
            sharesMedicationPlans: false,
            sharesDoseEvents: false,
            sharesRiskCards: false,
            sharesDrugLabels: false,
            sharesImportDraft: false,
            grantedAt: grantedAt
        )
        context.insert(consent)
        try context.save()
        let command = AIConversationPersistenceCommand(modelContext: context) { _ in
            throw SyntheticAIConversationSaveError.unavailable
        }

        let outcome = command.saveConsent(
            existing: consent,
            draft: AIConsentDraft(
                sharesMedicationProfile: false,
                sharesMedicationPlans: true,
                sharesDoseEvents: true,
                sharesRiskCards: true,
                sharesDrugLabels: true,
                sharesImportDraft: true
            ),
            grantedAt: Date(timeIntervalSince1970: 200)
        )

        #expect(outcome == .saveFailed)
        #expect(consent.sharesMedicationProfile)
        #expect(!consent.sharesMedicationPlans)
        #expect(!consent.sharesDoseEvents)
        #expect(consent.grantedAt == grantedAt)
        #expect(consent.revokedAt == nil)
        #expect(!context.hasChanges)
    }

    @Test @MainActor
    func revokeSaveFailureKeepsConsentActiveAndLeavesNoMessage() throws {
        let container = try MedicationAdherenceModelContainer.make(isStoredInMemoryOnly: true)
        let context = ModelContext(container)
        context.autosaveEnabled = false
        let consent = StoredAIConsent()
        context.insert(consent)
        try context.save()
        let command = AIConversationPersistenceCommand(modelContext: context) { _ in
            throw SyntheticAIConversationSaveError.unavailable
        }

        let outcome = command.revokeConsent(
            consent,
            revokedAt: Date(timeIntervalSince1970: 300)
        )

        #expect(outcome == .saveFailed)
        #expect(consent.revokedAt == nil)
        #expect(try context.fetch(FetchDescriptor<StoredAIChatMessage>()).isEmpty)
        #expect(!context.hasChanges)
    }
}

private enum SyntheticAIConversationSaveError: Error {
    case unavailable
}
