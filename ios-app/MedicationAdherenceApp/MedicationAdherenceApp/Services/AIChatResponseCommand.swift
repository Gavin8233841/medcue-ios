import Foundation
import MedicationAdherenceCore
import SwiftData

struct AIChatResponseDraft: Equatable {
    let role: StoredAIChatRole
    let text: String
    let createdAt: Date
    let providerName: String
    let modelName: String
    let requestKind: MedicalAIRequestKind
    let sharedScopesSummary: String

    init(
        role: StoredAIChatRole,
        text: String,
        createdAt: Date = Date(),
        providerName: String,
        modelName: String,
        requestKind: MedicalAIRequestKind = .chat,
        sharedScopesSummary: String
    ) {
        self.role = role
        self.text = text
        self.createdAt = createdAt
        self.providerName = providerName
        self.modelName = modelName
        self.requestKind = requestKind
        self.sharedScopesSummary = sharedScopesSummary
    }
}

enum AIChatResponseCommandOutcome: Equatable {
    case committed(messageID: UUID)
    case rejectedEmptyMessage
    case saveFailed
}

@MainActor
struct AIChatResponseCommand {
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

    func commit(_ draft: AIChatResponseDraft) -> AIChatResponseCommandOutcome {
        switch AIConversationPersistenceCommand(
            modelContext: modelContext,
            saveOperation: saveOperation
        ).commitMessages([draft], operation: "ai-response-commit") {
        case let .committed(messageIDs):
            guard let messageID = messageIDs.first else {
                return .rejectedEmptyMessage
            }
            return .committed(messageID: messageID)
        case .rejectedEmptyMessage:
            return .rejectedEmptyMessage
        case .saveFailed:
            return .saveFailed
        case .deleted, .consentSaved, .consentRevoked, .updated:
            return .saveFailed
        }
    }
}
