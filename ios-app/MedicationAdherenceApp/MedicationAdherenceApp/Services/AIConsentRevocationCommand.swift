import Foundation
import SwiftData

enum AIConsentRevocationOutcome: Equatable {
    case revoked
    case alreadyRevoked
    case consentNotFound
    case saveFailed
}

/// Application-level command for revoking AI consent and cleaning up related data
///
/// This command provides a single, transactional operation that:
/// 1. Marks consent as revoked with timestamp
/// 2. Creates an audit message for the revocation
///
/// Both UI entry points (HealthPrivacySettingsViews and AIAssistantInputViews)
/// should use this command to ensure consistent behavior.
@MainActor
struct AIConsentRevocationCommand {
    typealias SaveOperation = (ModelContext) throws -> Void
    typealias Clock = () -> Date

    private let modelContext: ModelContext
    private let saveOperation: SaveOperation
    private let now: Clock

    init(
        modelContext: ModelContext,
        saveOperation: @escaping SaveOperation = { try $0.save() },
        now: @escaping Clock = Date.init
    ) {
        self.modelContext = modelContext
        self.saveOperation = saveOperation
        self.now = now
    }

    /// Revokes AI consent and cleans up all AI-related data
    func execute() -> AIConsentRevocationOutcome {
        // 1. Find existing consent
        let consentDescriptor = FetchDescriptor<StoredAIConsent>()
        guard let consent = try? modelContext.fetch(consentDescriptor).first else {
            return .consentNotFound
        }

        // 2. Check if already revoked
        if consent.revokedAt != nil {
            return .alreadyRevoked
        }

        // 3. Mark as revoked
        let snapshot = AIConsentSnapshot(consent)
        let revocationTime = now()
        consent.revokedAt = revocationTime

        // 4. Create audit message
        let auditMessage = StoredAIChatMessage(
            role: .system,
            text: "医疗智能体数据共享授权已撤销。",
            createdAt: revocationTime,
            providerName: "",
            modelName: "",
            requestKind: "",
            sharedScopesSummary: "已撤销"
        )
        modelContext.insert(auditMessage)

        // 5. Save atomically
        do {
            try saveOperation(modelContext)
            return .revoked
        } catch {
            snapshot.restore()
            modelContext.delete(auditMessage)
            modelContext.rollback()
            AppPersistenceCommitter.reportFailure(operation: "ai-revoke-consent")
            return .saveFailed
        }
    }
}

private struct AIConsentSnapshot {
    let consent: StoredAIConsent
    let revokedAt: Date?

    init(_ consent: StoredAIConsent) {
        self.consent = consent
        self.revokedAt = consent.revokedAt
    }

    func restore() {
        consent.revokedAt = revokedAt
    }
}
