import Foundation
import Testing
@testable import MedicationAdherenceCore

private func healthDate(_ text: String) -> Date {
    ISO8601DateFormatter().date(from: text)!
}
private func healthSample(_ value: Double = 60, id: UUID = UUID(), metric: HealthEvidenceMetric = .restingHeartRate,
                          start: String = "2026-09-01T08:00:00Z", end: String = "2026-09-01T08:00:00Z",
                          source: String = "watch", state: HealthSleepState? = nil,
                          unit: String? = nil) -> HealthEvidenceSample {
    HealthEvidenceSample(id: id, metric: metric, start: healthDate(start), end: healthDate(end),
        value: value, unit: unit ?? metric.unit, sourceID: source, sourceName: source,
        timeZoneIdentifier: "GMT", sleepState: state)
}
private func healthBundle(_ samples: [HealthEvidenceSample], start: String = "2026-09-01T00:00:00Z",
                          end: String = "2026-09-04T00:00:00Z", zone: String = "GMT",
                          failed: Set<HealthEvidenceMetric> = []) -> HealthEvidenceBundle {
    HealthEvidenceBuilder().build(samples: samples, start: healthDate(start), end: healthDate(end),
        timeZone: TimeZone(identifier: zone)!, generatedAt: healthDate(end), failedMetrics: failed)
}

@Test func healthEvidenceDeduplicatesUUIDAndCountsUniqueDays() {
    let one = healthSample(60)
    let bundle = healthBundle([one, one, healthSample(62), healthSample(70,
        start: "2026-09-03T08:00:00Z", end: "2026-09-03T08:00:00Z")])
    let fact = bundle.facts.first { $0.metric == .restingHeartRate }!
    #expect(fact.observedDays == 2)
    #expect(fact.expectedDays == 3)
    #expect(fact.median == 65.5) // median of daily medians (61, 70), not sample median.
    #expect(fact.coverage == 2.0 / 3.0)
    #expect(fact.days[0].sourceSampleIDs.count == 2)
}

@Test func healthEvidenceMissingIsNotZeroAndBadUnitsAreExcluded() {
    let missing = healthBundle([]).facts.first { $0.metric == .hrvSDNN }!
    #expect(missing.median == nil)
    #expect(missing.observedDays == 0)
    let zero = healthBundle([healthSample(0, metric: .hrvSDNN)]).facts.first { $0.metric == .hrvSDNN }!
    #expect(zero.median == 0)
    let bad = healthBundle([healthSample(60, unit: "mg/dL")]).facts.first { $0.metric == .restingHeartRate }!
    #expect(bad.median == nil)
    #expect(bad.quality.contains(.invalidSample))
    let invalidWindow = healthBundle([], start: "2026-09-04T00:00:00Z")
    #expect(invalidWindow.facts.allSatisfy { $0.expectedDays == 0 && $0.coverage == 0 })
}

@Test func healthEvidenceRejectsConflictingIdentityRatherThanLastWriteWins() {
    let id = UUID()
    let fact = healthBundle([healthSample(60, id: id), healthSample(70, id: id)])
        .facts.first { $0.metric == .restingHeartRate }!
    #expect(fact.median == nil)
    #expect(fact.quality.contains(.conflictingIdentity))
}

@Test func healthEvidenceSourceSelectionUsesDayCoverageNotSampleDensity() {
    var rows = (0..<100).map { _ in healthSample(90, source: "dense") }
    rows += [healthSample(60, source: "coverage"), healthSample(64,
        start: "2026-09-03T08:00:00Z", end: "2026-09-03T08:00:00Z", source: "coverage")]
    let fact = healthBundle(rows).facts.first { $0.metric == .restingHeartRate }!
    #expect(fact.sourceID == "coverage")
    #expect(fact.median == 62)
    #expect(fact.quality.contains(.multipleSources))
}

@Test func healthEvidenceSleepUnionsStagesAndExcludesInBed() {
    let rows = [
        healthSample(0, metric: .sleep, start: "2026-09-01T22:00:00Z", end: "2026-09-02T08:00:00Z", state: .inBed),
        healthSample(0, metric: .sleep, start: "2026-09-01T23:00:00Z", end: "2026-09-02T07:00:00Z", state: .asleep),
        healthSample(0, metric: .sleep, start: "2026-09-02T00:00:00Z", end: "2026-09-02T03:00:00Z", state: .core),
        healthSample(0, metric: .sleep, start: "2026-09-02T02:00:00Z", end: "2026-09-02T04:00:00Z", state: .rem)
    ]
    let fact = healthBundle(rows).facts.first { $0.metric == .sleep }!
    #expect(fact.median == 8)
    #expect(fact.observedDays == 1)
    #expect(fact.days[0].start == healthDate("2026-09-01T12:00:00Z"))
    #expect(fact.quality.contains(.overlappingSleepStages))
}

@Test func healthEvidenceSleepClipsToCompleteNoonPeriodsAndIncludesNap() {
    let rows = [healthSample(0, metric: .sleep, start: "2026-09-01T11:00:00Z",
                            end: "2026-09-01T14:00:00Z", state: .asleep),
                healthSample(0, metric: .sleep, start: "2026-09-01T23:00:00Z",
                             end: "2026-09-02T07:00:00Z", state: .asleep)]
    let fact = healthBundle(rows, start: "2026-09-01T12:00:00Z", end: "2026-09-02T12:00:00Z")
        .facts.first { $0.metric == .sleep }!
    #expect(fact.expectedDays == 1)
    #expect(fact.median == 10)
    #expect(!fact.quality.contains(.partialPeriod))
}

@Test func healthEvidenceSleepDSTUsesElapsedTimeAndDayCalendar() {
    let rows = [healthSample(0, metric: .sleep, start: "2026-11-01T04:00:00Z",
                            end: "2026-11-01T13:00:00Z", state: .asleep)]
    let fact = healthBundle(rows, start: "2026-10-31T16:00:00Z", end: "2026-11-01T17:00:00Z",
                           zone: "America/New_York").facts.first { $0.metric == .sleep }!
    #expect(fact.expectedDays == 1)
    #expect(fact.median == 9)
    #expect(fact.quality.contains(.sourceTimeZoneDiffers))
}

@Test func healthEvidenceQueryFailureNeverReusesOldValues() {
    let bundle = healthBundle([healthSample()], failed: [.restingHeartRate])
    let fact = bundle.facts.first { $0.metric == .restingHeartRate }!
    #expect(fact.median == nil)
    #expect(fact.quality.contains(.queryFailed))
}

@Test func healthEvidenceSnapshotDeletionAndLateCallbacks() {
    var snapshot = HealthEvidenceSnapshot()
    let first = healthSample()
    let epoch1 = snapshot.beginRefresh()
    let accepted1 = snapshot.replace([first], epoch: epoch1)
    #expect(accepted1)
    let epoch2 = snapshot.beginRefresh()
    let accepted2 = snapshot.replace([], epoch: epoch2)
    #expect(accepted2)
    let accepted3 = snapshot.replace([first], epoch: epoch1)
    #expect(!accepted3)
    snapshot.disconnect()
    let accepted4 = snapshot.replace([first], epoch: epoch2)
    #expect(!accepted4)
    snapshot.reconnect()
    let accepted5 = snapshot.replace([first], epoch: epoch2)
    #expect(!accepted5)
    let epoch3 = snapshot.beginRefresh()
    let accepted6 = snapshot.replace([first], epoch: epoch3)
    #expect(accepted6)
}

@Test func healthEvidenceScopeRequiredAndUnauthorizedPromptOmitsFacts() {
    let bundle = healthBundle([healthSample(73)])
    var request = MedicalAIRequest(kind: .chat, userMessage: "静息心率", authorization:
        MedicalAIUserAuthorization(grantedScopes: [.medicationProfile]), healthEvidence: bundle)
    #expect(MedicalAIRequestValidator().missingRequiredScopes(for: request) == [.healthSummary])
    #expect(!MedicalAIRequestPromptBuilder().buildPrompt(for: request).contains("事实ID"))
    request.authorization.grantedScopes.insert(.healthSummary)
    #expect(MedicalAIRequestValidator().canSend(request))
    #expect(MedicalAIRequestPromptBuilder().buildPrompt(for: request).contains("事实ID"))
}

@Test func healthEvidenceLocalAnswerNeedsNeitherNetworkNorModel() {
    let answer = HealthEvidenceLocalReview().answer(metric: .restingHeartRate, bundle: healthBundle([healthSample(73)]))
    #expect(answer.contains("73"))
    #expect(answer.contains("1/3"))
    #expect(answer.contains("不能据此判断病情或药效"))
    #expect(HealthEvidenceLocalReview.metric(in: "近一周睡眠怎样") == .sleep)
    #expect(HealthEvidenceLocalReview.metric(in: "今天漏药了吗") == nil)
}

@Test func healthEvidenceDoesNotSilentlyDropThe251stSample() {
    let rows = (0..<301).map { index in healthSample(Double(index), metric: .hrvSDNN) }
    let fact = healthBundle(rows).facts.first { $0.metric == .hrvSDNN }!
    #expect(fact.days.first?.sourceSampleIDs.count == 301)
    #expect(fact.median == 150)
}

@Test func healthEvidenceReviewNeverShortcutsSymptomsTreatmentOrCausality() {
    for question in ["吃药后呼吸困难怎么办", "睡眠时胸痛需要急救吗", "HRV下降是不是药物导致", "静息心率高要减药吗", "breathing difficulty after medication"] {
        #expect(HealthEvidenceLocalReview.metric(in: question) == nil)
    }
    #expect(HealthEvidenceLocalReview.metric(in: "最近呼吸频率记录怎样") == .respiratoryRate)
    #expect(HealthEvidenceLocalReview.lookbackDays(in: "近一周睡眠怎样") == 7)
    #expect(HealthEvidenceLocalReview.lookbackDays(in: "近30天静息心率记录") == 30)
}

@Test func healthEvidenceBudgetOverflowFailsClosedWithoutPartialFacts() {
    #expect(HealthReadBudget.accepts(count: 301, limit: HealthReadBudget.quantitySamples))
    #expect(!HealthReadBudget.accepts(count: HealthReadBudget.quantitySamples + 1, limit: HealthReadBudget.quantitySamples))
    let bundle = HealthEvidenceBuilder().build(samples: [healthSample(73)],
        start: healthDate("2026-09-01T00:00:00Z"), end: healthDate("2026-09-04T00:00:00Z"),
        timeZone: TimeZone(secondsFromGMT: 0)!, generatedAt: healthDate("2026-09-04T00:00:00Z"),
        budgetExceededMetrics: [.restingHeartRate])
    let fact = bundle.facts.first { $0.metric == .restingHeartRate }!
    #expect(fact.median == nil)
    #expect(fact.days.isEmpty)
    #expect(fact.quality.contains(.sampleBudgetExceeded))
    #expect(HealthEvidenceLocalReview().answer(metric: .restingHeartRate, bundle: bundle).contains("超过本次读取预算"))
}
