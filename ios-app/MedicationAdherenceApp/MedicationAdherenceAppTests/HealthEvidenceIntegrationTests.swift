import Foundation
import MedicationAdherenceCore
import Testing
import SwiftData
@testable import MedicationAdherenceApp

@MainActor
struct HealthEvidenceIntegrationTests {
    @Test func independentHealthConsentDefaultsOffAndRevocationChangesRevision() {
        let suiteName = "health-evidence-test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        #expect(!HealthAISharingPolicy.allowsLocalSummary(defaults: defaults))
        let initial = HealthAISharingPolicy.revision(defaults: defaults)
        HealthAISharingPolicy.setAllowed(true, defaults: defaults)
        #expect(HealthAISharingPolicy.allowsLocalSummary(defaults: defaults))
        let granted = HealthAISharingPolicy.revision(defaults: defaults)
        #expect(granted != initial)
        HealthAISharingPolicy.revoke(defaults: defaults)
        #expect(!HealthAISharingPolicy.allowsLocalSummary(defaults: defaults))
        #expect(HealthAISharingPolicy.revision(defaults: defaults) != granted)
        #expect(!HealthAISharingPolicy.cloudHealthSharingEnabled)
    }

    @Test func oldMedicationConsentDoesNotOptIntoHealthSummary() {
        let builder = MedicalAIContextBuilder(medications: [], plans: [], tasks: [], riskCards: [], labels: [])
        let consent = StoredAIConsent()
        let bundle = emptyHealthBundle()
        let request = builder.makeRequest(userMessage: "睡眠", consent: consent, environmentInsights: [],
            localeIdentifier: "zh_CN", healthEvidence: bundle)
        #expect(request.healthEvidence == nil)
        #expect(!request.authorization.grantedScopes.contains(.healthSummary))
        let allowed = builder.makeRequest(userMessage: "睡眠", consent: consent, environmentInsights: [],
            localeIdentifier: "zh_CN", healthEvidence: bundle, healthSharingAllowed: true,
            healthConsentRevision: "explicit-grant")
        #expect(allowed.healthEvidence != nil)
        #expect(allowed.authorization.grantedScopes.contains(.healthSummary))
        consent.revokedAt = Date()
        let revoked = builder.makeRequest(userMessage: "睡眠", consent: consent, environmentInsights: [],
            localeIdentifier: "zh_CN", healthEvidence: bundle, healthSharingAllowed: true)
        #expect(revoked.healthEvidence == nil)
        #expect(consent.authorization.grantedScopes.isEmpty)
    }

    @Test func cloudAdapterBlocksHealthEvenWithScope() async {
        let recorder = HealthTransportRecorder()
        let client = HealthRestrictedCloudClient(underlying: recorder)
        let request = MedicalAIRequest(kind: .chat, userMessage: "睡眠",
            authorization: MedicalAIUserAuthorization(grantedScopes: [.healthSummary]),
            healthEvidence: emptyHealthBundle())
        do {
            _ = try await client.respond(to: request)
            Issue.record("Health data reached the cloud adapter")
        } catch {
            #expect(error is HealthCloudSharingError)
        }
        let calls = await recorder.calls
        #expect(calls == 0)
    }

    @Test func sharedConnectionRevisionRejectsOldReadAfterReconnect() {
        let suiteName = "health-connection-test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        HealthConnectionPolicy.setConnected(true, defaults: defaults)
        let instanceARead = HealthConnectionPolicy.revision(defaults: defaults)
        HealthConnectionPolicy.setConnected(false, defaults: defaults)
        let oldDisconnectNotification = HealthConnectionPolicy.revision(defaults: defaults)
        HealthConnectionPolicy.setConnected(true, defaults: defaults)
        #expect(!HealthConnectionPolicy.isCurrent(instanceARead, defaults: defaults))
        #expect(HealthConnectionPolicy.revision(defaults: defaults) != oldDisconnectNotification)
        let instanceARefreshed = HealthConnectionPolicy.revision(defaults: defaults)
        #expect(HealthConnectionPolicy.isCurrent(instanceARefreshed, defaults: defaults))
    }

    @Test func revokeDuringResponsePreventsActualSwiftDataCommit() async throws {
        let container = try MedicationAdherenceModelContainer.make(isStoredInMemoryOnly: true)
        let context = ModelContext(container)
        let consent = StoredAIConsent()
        context.insert(consent)
        try context.save()
        let request = MedicalAIRequest(kind: .chat, userMessage: "回顾记录", authorization: consent.authorization)
        // The request has captured its grant; emulate a suspension while awaiting its response.
        await Task.yield()
        let revoked = AIConsentRevocationCommand(modelContext: context).execute()
        #expect(revoked == .revoked)
        let result = AIConsentCheckedResponseCommand(modelContext: context).commit(
            AIChatResponseDraft(role: .assistant, text: "stale answer", providerName: "test", modelName: "none", sharedScopesSummary: "test"),
            request: request, consent: consent)
        if case .authorizationChanged = result {} else { Issue.record("Revoked response was accepted") }
        let messages = try context.fetch(FetchDescriptor<StoredAIChatMessage>())
        #expect(!messages.contains { $0.role == .assistant })
    }

    @Test func healthRegrantCannotAcceptPreviousRequestRevision() throws {
        let suiteName = "health-epoch-test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let consent = StoredAIConsent()
        HealthAISharingPolicy.setAllowed(true, defaults: defaults)
        var authorization = consent.authorization
        authorization.grantedScopes.insert(.healthSummary)
        let request = MedicalAIRequest(kind: .chat, userMessage: "回顾睡眠记录", authorization: authorization,
            healthEvidence: emptyHealthBundle(), healthConsentRevision: HealthAISharingPolicy.revision(defaults: defaults),
            healthSnapshotRevision: HealthAISharingPolicy.snapshotRevision(defaults: defaults))
        #expect(AIConsentCheckedResponseCommand.isCurrent(request, consent: consent, defaults: defaults))
        HealthAISharingPolicy.revoke(defaults: defaults)
        HealthAISharingPolicy.setAllowed(true, defaults: defaults)
        #expect(!AIConsentCheckedResponseCommand.isCurrent(request, consent: consent, defaults: defaults))
    }

    @Test func refreshedDeletedSamplesInvalidateInFlightHealthAnswer() throws {
        let suiteName = "health-snapshot-test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let container = try MedicationAdherenceModelContainer.make(isStoredInMemoryOnly: true)
        let context = ModelContext(container)
        let consent = StoredAIConsent()
        context.insert(consent); try context.save()
        HealthAISharingPolicy.setAllowed(true, defaults: defaults)
        var authorization = consent.authorization
        authorization.grantedScopes.insert(.healthSummary)
        let request = MedicalAIRequest(kind: .chat, userMessage: "回顾睡眠记录", authorization: authorization,
            healthEvidence: emptyHealthBundle(), healthConsentRevision: HealthAISharingPolicy.revision(defaults: defaults),
            healthSnapshotRevision: HealthAISharingPolicy.snapshotRevision(defaults: defaults))
        _ = HealthAISharingPolicy.invalidateSnapshot(defaults: defaults) // refresh may remove deleted samples
        let result = AIConsentCheckedResponseCommand(modelContext: context).commit(
            AIChatResponseDraft(role: .assistant, text: "old snapshot", providerName: "test", modelName: "none", sharedScopesSummary: "health"),
            request: request, consent: consent, defaults: defaults)
        if case .authorizationChanged = result {} else { Issue.record("Stale snapshot accepted") }
        #expect(try context.fetchCount(FetchDescriptor<StoredAIChatMessage>()) == 0)
    }

    @Test func cancelledBeforeStartCannotInvalidateNewerSnapshotOrRequestPermission() async {
        let suiteName = "health-cancel-before-start-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        HealthConnectionPolicy.setConnected(true, defaults: defaults)
        let revision = HealthAISharingPolicy.invalidateSnapshot(defaults: defaults)
        let connectionRevision = HealthConnectionPolicy.revision(defaults: defaults)
        let service = HealthKitService(defaults: defaults)
        let read = Task { @MainActor in await service.refreshRecentTrendSamples() }
        read.cancel() // actor remains owned by this test until the await below
        await read.value
        #expect(HealthAISharingPolicy.snapshotRevision(defaults: defaults) == revision)
        let authorization = Task { @MainActor in await service.requestAuthorizationEntry() }
        authorization.cancel()
        let completed = await authorization.value
        #expect(!completed)
        #expect(HealthConnectionPolicy.revision(defaults: defaults) == connectionRevision)
    }

    private func emptyHealthBundle() -> HealthEvidenceBundle {
        HealthEvidenceBuilder().build(samples: [], start: Date(timeIntervalSince1970: 0),
            end: Date(timeIntervalSince1970: 86400), timeZone: TimeZone(secondsFromGMT: 0)!, generatedAt: Date())
    }
}

private actor HealthTransportRecorder: MedicalAIClient {
    private(set) var calls = 0
    func respond(to request: MedicalAIRequest) async throws -> MedicalAIResponse {
        calls += 1
        return MedicalAIResponse(requestID: request.id,
            provider: MedicalAIProviderProfile(providerName: "test", modelName: "none", serviceLicenseSummary: "test"),
            message: "test")
    }
}
