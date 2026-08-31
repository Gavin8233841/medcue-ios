import Foundation
import SwiftData
import Testing
@testable import MedicationAdherenceApp

@Suite(.serialized)
struct AIConsentRevocationCommandTests {
    @Test @MainActor
    func successfulRevocationSetsRevokedAtAndCreatesAuditMessage() throws {
        let container = try MedicationAdherenceModelContainer.make(isStoredInMemoryOnly: true)
        let context = ModelContext(container)
        context.autosaveEnabled = false
        let consent = StoredAIConsent(
            sharesMedicationProfile: true,
            sharesMedicationPlans: true,
            sharesDoseEvents: true,
            sharesRiskCards: true,
            sharesDrugLabels: true,
            sharesImportDraft: false,
            grantedAt: Date(timeIntervalSince1970: 100)
        )
        context.insert(consent)
        try context.save()
        let now = Date(timeIntervalSince1970: 200)
        let command = AIConsentRevocationCommand(modelContext: context, now: { now })

        let outcome = command.execute()

        #expect(outcome == .revoked)
        #expect(consent.revokedAt == now)
        let messages = try context.fetch(FetchDescriptor<StoredAIChatMessage>())
        #expect(messages.count == 1)
        #expect(messages[0].role == .system)
        #expect(messages[0].text == "医疗智能体数据共享授权已撤销。")
        #expect(messages[0].createdAt == now)
        #expect(messages[0].sharedScopesSummary == "已撤销")
    }

    @Test @MainActor
    func alreadyRevokedConsentReturnsAlreadyRevokedWithoutDuplicateAuditMessage() throws {
        let container = try MedicationAdherenceModelContainer.make(isStoredInMemoryOnly: true)
        let context = ModelContext(container)
        context.autosaveEnabled = false
        let firstRevocationTime = Date(timeIntervalSince1970: 100)
        let consent = StoredAIConsent(
            sharesMedicationProfile: true,
            sharesMedicationPlans: true,
            sharesDoseEvents: true,
            sharesRiskCards: true,
            sharesDrugLabels: true,
            sharesImportDraft: false,
            grantedAt: Date(timeIntervalSince1970: 50)
        )
        consent.revokedAt = firstRevocationTime
        context.insert(consent)
        try context.save()
        let command = AIConsentRevocationCommand(
            modelContext: context,
            now: { Date(timeIntervalSince1970: 200) }
        )

        let outcome = command.execute()

        #expect(outcome == .alreadyRevoked)
        #expect(consent.revokedAt == firstRevocationTime)
        let messages = try context.fetch(FetchDescriptor<StoredAIChatMessage>())
        #expect(messages.isEmpty)
    }

    @Test @MainActor
    func consentNotFoundReturnsConsentNotFound() throws {
        let container = try MedicationAdherenceModelContainer.make(isStoredInMemoryOnly: true)
        let context = ModelContext(container)
        context.autosaveEnabled = false
        let command = AIConsentRevocationCommand(modelContext: context)

        let outcome = command.execute()

        #expect(outcome == .consentNotFound)
        #expect(try context.fetch(FetchDescriptor<StoredAIChatMessage>()).isEmpty)
    }

    @Test @MainActor
    func saveFailureRestoresConsentAndDeletesAuditMessage() throws {
        let container = try MedicationAdherenceModelContainer.make(isStoredInMemoryOnly: true)
        let context = ModelContext(container)
        context.autosaveEnabled = false
        let consent = StoredAIConsent(
            sharesMedicationProfile: true,
            sharesMedicationPlans: false,
            sharesDoseEvents: true,
            sharesRiskCards: false,
            sharesDrugLabels: true,
            sharesImportDraft: true,
            grantedAt: Date(timeIntervalSince1970: 100)
        )
        context.insert(consent)
        try context.save()

        let failingSaveOperation: (ModelContext) throws -> Void = { _ in
            throw SyntheticRevocationSaveError.unavailable
        }

        let command = AIConsentRevocationCommand(
            modelContext: context,
            saveOperation: failingSaveOperation,
            now: { Date(timeIntervalSince1970: 200) }
        )

        let outcome = command.execute()

        #expect(outcome == .saveFailed)
        #expect(consent.revokedAt == nil)
        #expect(consent.sharesMedicationProfile)
        #expect(!consent.sharesMedicationPlans)
        #expect(consent.sharesDoseEvents)
        #expect(!consent.sharesRiskCards)
        #expect(consent.sharesDrugLabels)
        #expect(consent.sharesImportDraft)
        #expect(consent.grantedAt == Date(timeIntervalSince1970: 100))
        #expect(try context.fetch(FetchDescriptor<StoredAIChatMessage>()).isEmpty)
        #expect(!context.hasChanges)
    }

    @Test @MainActor
    func multipleSuccessiveRevocationAttemptsAreIdempotent() throws {
        let container = try MedicationAdherenceModelContainer.make(isStoredInMemoryOnly: true)
        let context = ModelContext(container)
        context.autosaveEnabled = false
        let consent = StoredAIConsent()
        context.insert(consent)
        try context.save()

        let command1 = AIConsentRevocationCommand(
            modelContext: context,
            now: { Date(timeIntervalSince1970: 100) }
        )
        let outcome1 = command1.execute()

        let command2 = AIConsentRevocationCommand(
            modelContext: context,
            now: { Date(timeIntervalSince1970: 200) }
        )
        let outcome2 = command2.execute()

        let command3 = AIConsentRevocationCommand(
            modelContext: context,
            now: { Date(timeIntervalSince1970: 300) }
        )
        let outcome3 = command3.execute()

        #expect(outcome1 == .revoked)
        #expect(outcome2 == .alreadyRevoked)
        #expect(outcome3 == .alreadyRevoked)
        #expect(consent.revokedAt == Date(timeIntervalSince1970: 100))
        let messages = try context.fetch(FetchDescriptor<StoredAIChatMessage>())
        #expect(messages.count == 1)
    }
}

private enum SyntheticRevocationSaveError: Error {
    case unavailable
}
