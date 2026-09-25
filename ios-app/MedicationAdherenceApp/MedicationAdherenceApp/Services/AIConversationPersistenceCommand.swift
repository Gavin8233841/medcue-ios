import Foundation
import SwiftData

struct AIConsentDraft: Equatable {
    var sharesMedicationProfile: Bool
    var sharesMedicationPlans: Bool
    var sharesDoseEvents: Bool
    var sharesRiskCards: Bool
    var sharesDrugLabels: Bool
    var sharesImportDraft: Bool
}

enum AIConversationPersistenceOutcome: Equatable {
    case committed(messageIDs: [UUID])
    case deleted(count: Int)
    case consentSaved
    case consentRevoked
    case updated(count: Int)
    case rejectedEmptyMessage
    case saveFailed
}

@MainActor
struct AIConversationPersistenceCommand {
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

    func commitMessages(
        _ drafts: [AIChatResponseDraft],
        operation: StaticString
    ) -> AIConversationPersistenceOutcome {
        let normalizedDrafts = drafts.map { draft in
            (draft, draft.text.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        guard normalizedDrafts.allSatisfy({ !$0.1.isEmpty }) else {
            return .rejectedEmptyMessage
        }

        let messages = normalizedDrafts.map { draft, text in
            StoredAIChatMessage(
                role: draft.role,
                text: text,
                createdAt: draft.createdAt,
                providerName: draft.providerName,
                modelName: draft.modelName,
                requestKind: draft.requestKind,
                sharedScopesSummary: draft.sharedScopesSummary
            )
        }
        messages.forEach(modelContext.insert)

        do {
            try saveOperation(modelContext)
            return .committed(messageIDs: messages.map(\.id))
        } catch {
            modelContext.rollback()
            AppPersistenceCommitter.reportFailure(operation: operation)
            return .saveFailed
        }
    }

    func deleteMessages(
        _ messages: [StoredAIChatMessage],
        operation: StaticString
    ) -> AIConversationPersistenceOutcome {
        messages.forEach(modelContext.delete)
        do {
            try saveOperation(modelContext)
            return .deleted(count: messages.count)
        } catch {
            modelContext.rollback()
            AppPersistenceCommitter.reportFailure(operation: operation)
            return .saveFailed
        }
    }

    func saveConsent(
        existing: StoredAIConsent?,
        draft: AIConsentDraft,
        grantedAt: Date
    ) -> AIConversationPersistenceOutcome {
        let consent = existing ?? StoredAIConsent()
        let snapshot = existing.map(AIConsentSnapshot.init)
        consent.sharesMedicationProfile = draft.sharesMedicationProfile
        consent.sharesMedicationPlans = draft.sharesMedicationPlans
        consent.sharesDoseEvents = draft.sharesDoseEvents
        consent.sharesRiskCards = draft.sharesRiskCards
        consent.sharesDrugLabels = draft.sharesDrugLabels
        consent.sharesImportDraft = draft.sharesImportDraft
        consent.grantedAt = grantedAt
        consent.revokedAt = nil
        consent.note = "用户授权医疗智能体读取选定范围的数据。"
        if existing == nil {
            modelContext.insert(consent)
        }

        do {
            try saveOperation(modelContext)
            return .consentSaved
        } catch {
            snapshot?.restore()
            modelContext.rollback()
            AppPersistenceCommitter.reportFailure(operation: "ai-save-consent")
            return .saveFailed
        }
    }

    @available(*, deprecated, message: "Use AIConsentRevocationCommand instead")
    func revokeConsent(
        _ consent: StoredAIConsent,
        revokedAt: Date
    ) -> AIConversationPersistenceOutcome {
        let command = AIConsentRevocationCommand(
            modelContext: modelContext,
            saveOperation: saveOperation,
            now: { revokedAt }
        )
        let outcome = command.execute()

        switch outcome {
        case .revoked:
            return .consentRevoked
        case .alreadyRevoked:
            return .consentRevoked
        case .saveFailed:
            return .saveFailed
        case .consentNotFound:
            return .saveFailed
        }
    }

    func migrateMessagesToSystem(
        _ messages: [StoredAIChatMessage],
        operation: StaticString
    ) -> AIConversationPersistenceOutcome {
        guard !messages.isEmpty else {
            return .updated(count: 0)
        }
        let snapshots = messages.map(AIChatMessageMetadataSnapshot.init)
        for message in messages {
            message.roleRaw = StoredAIChatRole.system.rawValue
            message.providerName = ""
            message.modelName = ""
        }
        do {
            try saveOperation(modelContext)
            return .updated(count: messages.count)
        } catch {
            snapshots.forEach { $0.restore() }
            modelContext.rollback()
            AppPersistenceCommitter.reportFailure(operation: operation)
            return .saveFailed
        }
    }
}

private struct AIChatMessageMetadataSnapshot {
    let message: StoredAIChatMessage
    let roleRaw: String
    let providerName: String
    let modelName: String

    init(_ message: StoredAIChatMessage) {
        self.message = message
        self.roleRaw = message.roleRaw
        self.providerName = message.providerName
        self.modelName = message.modelName
    }

    func restore() {
        message.roleRaw = roleRaw
        message.providerName = providerName
        message.modelName = modelName
    }
}

private struct AIConsentSnapshot {
    let consent: StoredAIConsent
    let sharesMedicationProfile: Bool
    let sharesMedicationPlans: Bool
    let sharesDoseEvents: Bool
    let sharesRiskCards: Bool
    let sharesDrugLabels: Bool
    let sharesImportDraft: Bool
    let grantedAt: Date
    let revokedAt: Date?
    let note: String

    init(_ consent: StoredAIConsent) {
        self.consent = consent
        self.sharesMedicationProfile = consent.sharesMedicationProfile
        self.sharesMedicationPlans = consent.sharesMedicationPlans
        self.sharesDoseEvents = consent.sharesDoseEvents
        self.sharesRiskCards = consent.sharesRiskCards
        self.sharesDrugLabels = consent.sharesDrugLabels
        self.sharesImportDraft = consent.sharesImportDraft
        self.grantedAt = consent.grantedAt
        self.revokedAt = consent.revokedAt
        self.note = consent.note
    }

    func restore() {
        consent.sharesMedicationProfile = sharesMedicationProfile
        consent.sharesMedicationPlans = sharesMedicationPlans
        consent.sharesDoseEvents = sharesDoseEvents
        consent.sharesRiskCards = sharesRiskCards
        consent.sharesDrugLabels = sharesDrugLabels
        consent.sharesImportDraft = sharesImportDraft
        consent.grantedAt = grantedAt
        consent.revokedAt = revokedAt
        consent.note = note
    }
}
