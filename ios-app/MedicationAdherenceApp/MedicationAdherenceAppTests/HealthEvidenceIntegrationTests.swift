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

@MainActor
struct HealthPartialAuthorizationPresentationTests {
    private let measuredAt = Date(timeIntervalSince1970: 1_800_000_000)

    private func review(_ metric: HealthEvidenceMetric) -> HealthEvidenceSample {
        HealthEvidenceSample(id: UUID(), metric: metric, start: measuredAt.addingTimeInterval(-3600),
            end: measuredAt, value: metric == .sleep ? 0 : 62, unit: metric.unit,
            sourceID: "synthetic-watch", sourceName: "Synthetic Watch",
            sleepState: metric == .sleep ? .asleep : nil)
    }
    private func vital() -> HealthSignalSample {
        HealthSignalSample(kind: .heartRate, measuredAt: measuredAt, value: 70, unit: "次/分")
    }

    @Test func sleepOnlyIsReadableWithoutClaimingVitalSignAuthorization() {
        let summary = HealthKitSettingsSummary(vitalSignSamples: [], reviewSamples: [review(.sleep)], refreshedAt: measuredAt)
        #expect(summary.hasSamples)
        #expect(summary.hasReviewSamples)
        #expect(summary.sampleCount == 1)
        #expect(summary.metricCount == 1)
        #expect(summary.coveredDayCount == 1)
        #expect(summary.headline == "已读取健康回顾记录")
        #expect(summary.vitalSigns.sampleCount == 0)
        #expect(summary.vitalSignDestinationText == "暂无生命体征")
        #expect(!summary.vitalSignDestinationText.contains("授权"))
    }

    @Test func restingHeartRateOnlyIsSeparateFromLegacyHeartRate() {
        let summary = HealthKitSettingsSummary(vitalSignSamples: [], reviewSamples: [review(.restingHeartRate)], refreshedAt: measuredAt)
        #expect(summary.reviewSampleCount == 1)
        #expect(summary.reviewMetricCount == 1)
        #expect(summary.vitalSigns.metricSummaries.isEmpty)
        #expect(summary.vitalSigns.latestSample == nil)
    }

    @Test func vitalSignsOnlyAndMixedDataKeepDestinationCountsSeparate() {
        let onlyVital = HealthKitSettingsSummary(vitalSignSamples: [vital()], reviewSamples: [], refreshedAt: measuredAt)
        #expect(onlyVital.sampleCount == 1)
        #expect(onlyVital.reviewSampleCount == 0)
        #expect(onlyVital.vitalSignDestinationText == "1 条生命体征")
        let mixed = HealthKitSettingsSummary(vitalSignSamples: [vital()], reviewSamples: [review(.sleep), review(.restingHeartRate)], refreshedAt: measuredAt)
        #expect(mixed.sampleCount == 3)
        #expect(mixed.metricCount == 3)
        #expect(mixed.coveredDayCount == 1)
        #expect(mixed.vitalSigns.sampleCount == 1)
        #expect(mixed.reviewSampleCount == 2)
        #expect(mixed.vitalSignDestinationText == "1 条生命体征")
    }

    @Test func emptyDataDoesNotAssertReadPermissionWasDenied() {
        let summary = HealthKitSettingsSummary(vitalSignSamples: [], reviewSamples: [], refreshedAt: measuredAt)
        #expect(!summary.hasSamples)
        #expect(summary.headline == "暂无可读取的健康记录")
        #expect(summary.reviewCoverageText == "暂无健康回顾记录")
        #expect(summary.vitalSignDestinationText == "暂无生命体征")
    }
}

@MainActor
struct HealthReviewMissingSnapshotTests {
    @Test func exactReviewWithoutSnapshotNeverCallsModel() async throws {
        let runtime = HealthReviewForbiddenRuntime()
        let client = LocalMedicalAIClient(modelURL: URL(fileURLWithPath: "/tmp/not-a-real-model.gguf"), runtime: runtime)
        let request = MedicalAIRequest(kind: .chat, userMessage: "近一周睡眠怎样",
            authorization: MedicalAIUserAuthorization(grantedScopes: []))
        let response = try await client.respond(to: request)
        #expect(response.message.contains("刷新"))
        #expect(response.provider.modelName == "deterministic-v1")
        #expect(await runtime.calls == 0)
    }

    @Test func streamReviewWithoutSnapshotNeverCallsModel() async throws {
        let runtime = HealthReviewForbiddenRuntime()
        let client = LocalMedicalAIClient(modelURL: URL(fileURLWithPath: "/tmp/not-a-real-model.gguf"), runtime: runtime)
        let request = MedicalAIRequest(kind: .chat, userMessage: "回顾静息心率记录",
            authorization: MedicalAIUserAuthorization(grantedScopes: []))
        var answer: String?
        for try await event in client.streamResponse(to: request) {
            if case let .generationCompleted(text, _) = event { answer = text }
        }
        #expect(answer?.contains("刷新") == true)
        #expect(await runtime.calls == 0)
    }

    @Test func symptomQuestionDoesNotTakeMissingSnapshotShortcut() async {
        let runtime = HealthReviewForbiddenRuntime()
        let client = LocalMedicalAIClient(modelURL: URL(fileURLWithPath: "/tmp/not-a-real-model.gguf"), runtime: runtime)
        let request = MedicalAIRequest(kind: .chat, userMessage: "最近呼吸困难怎么办",
            authorization: MedicalAIUserAuthorization(grantedScopes: []))
        do { _ = try await client.respond(to: request) } catch { }
        #expect(await runtime.calls == 1) // The existing medical-AI path, not a record-review template.
    }
}

private actor HealthReviewForbiddenRuntime: LocalMedicalGenerating {
    private(set) var calls = 0
    func generateResponse(prompt: String, modelURL: URL, maxTokens: Int) async throws -> String {
        calls += 1
        throw LocalMedicalAIError.runtimeUnavailable
    }
    nonisolated func generateResponseStream(prompt: String, modelURL: URL, maxTokens: Int) -> LocalMedicalGenerationStream {
        let (stream, continuation) = AsyncThrowingStream<String, Error>.makeStream()
        // Any unexpected stream invocation is a test failure independently of actor counter timing.
        Issue.record("A missing-snapshot review invoked the model stream")
        continuation.finish(throwing: LocalMedicalAIError.runtimeUnavailable)
        return LocalMedicalGenerationStream(stream: stream) {}
    }
}
