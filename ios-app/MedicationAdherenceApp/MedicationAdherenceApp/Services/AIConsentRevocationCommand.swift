import Foundation
import MedicationAdherenceCore
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

    /// Revokes future AI sharing; existing conversation history is retained.
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
            requestKind: .chat,
            sharedScopesSummary: "已撤销"
        )
        modelContext.insert(auditMessage)

        // 5. Save atomically
        do {
            try saveOperation(modelContext)
            HealthAISharingPolicy.revoke()
            NotificationCenter.default.post(name: .medcueAIConsentChanged, object: nil)
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


/// The authorization check and SwiftData commit execute without an intervening
/// suspension on the main actor; cancellation alone is not a consent boundary.
@MainActor
struct AIConsentCheckedResponseCommand {
    let modelContext: ModelContext

    enum Outcome { case committed, authorizationChanged, persistenceFailed }

    static func isCurrent(_ request: MedicalAIRequest, consent: StoredAIConsent?,
                          defaults: UserDefaults = .standard) -> Bool {
        guard let consent, consent.isActive,
              consent.grantedAt == request.authorization.grantedAt else { return false }
        let medicationScopes = request.authorization.grantedScopes.subtracting([.healthSummary])
        guard medicationScopes.isSubset(of: consent.authorization.grantedScopes) else { return false }
        guard request.healthEvidence != nil else { return true }
        return HealthAISharingPolicy.allowsLocalSummary(defaults: defaults)
            && request.healthConsentRevision == HealthAISharingPolicy.revision(defaults: defaults)
            && request.healthSnapshotRevision != nil
            && request.healthSnapshotRevision == HealthAISharingPolicy.snapshotRevision(defaults: defaults)
            && request.authorization.allows(.healthSummary)
    }

    func commit(_ draft: AIChatResponseDraft, request: MedicalAIRequest,
                consent: StoredAIConsent?, defaults: UserDefaults = .standard) -> Outcome {
        guard Self.isCurrent(request, consent: consent, defaults: defaults) else { return .authorizationChanged }
        let outcome = AIChatResponseCommand(modelContext: modelContext).commit(draft)
        if case .committed = outcome { return .committed }
        return .persistenceFailed
    }
}
