import SwiftData
import Testing
@testable import MedicationAdherenceApp

@Suite(.serialized)
struct AIChatResponseCommandTests {
    @Test @MainActor
    func committedResponseIsTheOnlyVisibleAssistantMessage() throws {
        let container = try MedicationAdherenceModelContainer.make(isStoredInMemoryOnly: true)
        let context = ModelContext(container)
        context.autosaveEnabled = false

        let outcome = AIChatResponseCommand(modelContext: context).commit(
            AIChatResponseDraft(
                role: .assistant,
                text: "已完成安全检查。",
                providerName: "测试服务",
                modelName: "test-model",
                sharedScopesSummary: "药品信息"
            )
        )

        guard case .committed = outcome else {
            Issue.record("Expected committed response")
            return
        }
        let stored = try context.fetch(FetchDescriptor<StoredAIChatMessage>())
        #expect(stored.count == 1)
        #expect(stored.first?.text == "已完成安全检查。")
        #expect(stored.first?.role == .assistant)
    }

    @Test @MainActor
    func saveFailureLeavesNoHalfPersistedResponse() throws {
        let container = try MedicationAdherenceModelContainer.make(isStoredInMemoryOnly: true)
        let context = ModelContext(container)
        context.autosaveEnabled = false
        let command = AIChatResponseCommand(modelContext: context) { _ in
            throw SyntheticAIResponseSaveError.unavailable
        }

        let outcome = command.commit(
            AIChatResponseDraft(
                role: .assistant,
                text: "不应留下的半条消息",
                providerName: "测试服务",
                modelName: "test-model",
                sharedScopesSummary: "药品信息"
            )
        )

        #expect(outcome == .saveFailed)
        #expect(try context.fetch(FetchDescriptor<StoredAIChatMessage>()).isEmpty)
        #expect(!context.hasChanges)
    }

    @Test @MainActor
    func emptyResponseIsRejectedBeforeInsertion() throws {
        let container = try MedicationAdherenceModelContainer.make(isStoredInMemoryOnly: true)
        let context = ModelContext(container)

        let outcome = AIChatResponseCommand(modelContext: context).commit(
            AIChatResponseDraft(
                role: .assistant,
                text: " \n ",
                providerName: "测试服务",
                modelName: "test-model",
                sharedScopesSummary: "药品信息"
            )
        )

        #expect(outcome == .rejectedEmptyMessage)
        #expect(try context.fetch(FetchDescriptor<StoredAIChatMessage>()).isEmpty)
    }
}

private enum SyntheticAIResponseSaveError: Error {
    case unavailable
}
