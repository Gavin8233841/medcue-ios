#if DEBUG && targetEnvironment(simulator)
import Foundation
import MedicationAdherenceCore
import Testing
@testable import MedicationAdherenceApp

@MainActor
struct HealthReviewFixtureBoundaryTests {
    @Test func missingFlagLeavesExplicitDefaultsAndStandardPreferencesAlone() throws {
        try withPreferences { preferences in
            #expect(HealthReviewUITestFixture.resolve(arguments: [], isolatedPreferences: preferences) == nil)
            #expect(preferences.object(forKey: HealthReviewUITestFixture.seedKey) == nil)
            let standardGrant = UserDefaults.standard.object(forKey: HealthAISharingPolicy.allowedKey) as? Bool
            let standardRevision = UserDefaults.standard.string(forKey: HealthAISharingPolicy.revisionKey)
            let service = HealthKitService(defaults: preferences)
            service.setLocalSummaryAllowed(true)
            #expect(HealthAISharingPolicy.allowsLocalSummary(defaults: preferences))
            #expect((UserDefaults.standard.object(forKey: HealthAISharingPolicy.allowedKey) as? Bool) == standardGrant)
            #expect(UserDefaults.standard.string(forKey: HealthAISharingPolicy.revisionKey) == standardRevision)
        }
    }

    @Test func explicitInvalidRequestsAreBlockedWithoutSeedingCallerPreferences() throws {
        try withPreferences { preferences in
            let flag = HealthReviewUITestFixture.flag
            let invalidArguments = [[flag], [flag, "unknown"], [flag, "populated", flag, "empty"],
                                    [flag + "=populated"], [flag, "--another-flag"]]
            for arguments in invalidArguments {
                let fixture = try #require(HealthReviewUITestFixture.resolve(
                    arguments: arguments, isolatedPreferences: preferences))
                #expect(!fixture.isValid)
                #expect(fixture.preferences !== preferences)
                #expect(fixture.preferences !== UserDefaults.standard)
                #expect(fixture.samples(start: .distantPast, end: .distantFuture).isEmpty)
                #expect(preferences.object(forKey: HealthReviewUITestFixture.seedKey) == nil)
                #expect(preferences.object(forKey: HealthConnectionPolicy.completionKey) == nil)
            }
            let noSession = try #require(HealthReviewUITestFixture.resolve(
                arguments: [flag, "populated"], isolatedPreferences: nil))
            let standard = try #require(HealthReviewUITestFixture.resolve(
                arguments: [flag, "populated"], isolatedPreferences: .standard))
            #expect(!noSession.isValid)
            #expect(!standard.isValid)
        }
    }

    @Test func seedIsOncePerSessionAndCannotReconnectAfterRealDisconnect() throws {
        try withPreferences { preferences in
            let arguments = [HealthReviewUITestFixture.flag, "populated"]
            let fixture = try #require(HealthReviewUITestFixture.resolve(
                arguments: arguments, isolatedPreferences: preferences))
            #expect(fixture.isValid)
            #expect(preferences.bool(forKey: HealthConnectionPolicy.completionKey))
            #expect(!HealthAISharingPolicy.allowsLocalSummary(defaults: preferences))
            let service = HealthKitService(defaults: preferences)
            service.setLocalSummaryAllowed(true)
            let grantedRevision = HealthAISharingPolicy.revision(defaults: preferences)
            _ = HealthReviewUITestFixture.resolve(arguments: arguments, isolatedPreferences: preferences)
            #expect(HealthAISharingPolicy.allowsLocalSummary(defaults: preferences))
            #expect(HealthAISharingPolicy.revision(defaults: preferences) == grantedRevision)

            service.disconnectAndClear()
            let disconnectedRevision = HealthConnectionPolicy.revision(defaults: preferences)
            let snapshotRevision = HealthAISharingPolicy.snapshotRevision(defaults: preferences)
            _ = HealthReviewUITestFixture.resolve(arguments: arguments, isolatedPreferences: preferences)
            let newService = HealthKitService(defaults: preferences)
            #expect(!newService.hasCompletedAuthorizationRequest)
            #expect(!preferences.bool(forKey: HealthConnectionPolicy.completionKey))
            #expect(!HealthAISharingPolicy.allowsLocalSummary(defaults: preferences))
            #expect(HealthConnectionPolicy.revision(defaults: preferences) == disconnectedRevision)
            #expect(HealthAISharingPolicy.snapshotRevision(defaults: preferences) == snapshotRevision)

            let changedScenario = try #require(HealthReviewUITestFixture.resolve(
                arguments: [HealthReviewUITestFixture.flag, "empty"], isolatedPreferences: preferences))
            #expect(!changedScenario.isValid)
            #expect(preferences.string(forKey: HealthReviewUITestFixture.seedKey) == "populated")
            #expect(HealthConnectionPolicy.revision(defaults: preferences) == disconnectedRevision)
        }
    }

    @Test func populatedFixtureHasIndependentWindowExpectations() throws {
        try withPreferences { preferences in
            let fixture = try #require(HealthReviewUITestFixture.resolve(
                arguments: [HealthReviewUITestFixture.flag, "populated"], isolatedPreferences: preferences))
            // Independently specified from the arithmetic series 41...47,
            // 41...70 and 41...96; these are also the UI's expected medians.
            for (days, median) in [(7, 44.0), (30, 55.5), (56, 68.5)] {
                let start = try #require(fixture.calendar.date(byAdding: .day, value: -days,
                    to: fixture.calendar.startOfDay(for: fixture.now)))
                let bundle = HealthEvidenceBuilder().build(samples: fixture.samples(start: start, end: fixture.now),
                    start: start, end: fixture.now, timeZone: fixture.calendar.timeZone, generatedAt: fixture.now)
                let fact = try #require(bundle.facts.first { $0.metric == .restingHeartRate })
                #expect(fact.median == median)
                #expect(fact.observedDays == days)
                #expect(fact.expectedDays == days)
                #expect(fact.sourceName == "UI Fixture")
                #expect(bundle.timeZoneIdentifier == "Etc/UTC")
            }
        }
    }

    @Test func partialAndEmptyFixtureContractsDoNotInventMissingValues() throws {
        for scenario in ["sleep-only", "empty"] {
            try withPreferences { preferences in
                let fixture = try #require(HealthReviewUITestFixture.resolve(
                    arguments: [HealthReviewUITestFixture.flag, scenario], isolatedPreferences: preferences))
                let start = try #require(fixture.calendar.date(byAdding: .day, value: -7,
                    to: fixture.calendar.startOfDay(for: fixture.now)))
                let bundle = HealthEvidenceBuilder().build(samples: fixture.samples(start: start, end: fixture.now),
                    start: start, end: fixture.now, timeZone: fixture.calendar.timeZone, generatedAt: fixture.now)
                let sleep = try #require(bundle.facts.first { $0.metric == .sleep })
                #expect(sleep.median == (scenario == "sleep-only" ? 8 : nil))
                #expect(sleep.observedDays == (scenario == "sleep-only" ? 3 : 0))
                #expect(sleep.expectedDays == 7)
                for fact in bundle.facts where scenario == "empty" || fact.metric != .sleep {
                    #expect(fact.median == nil)
                    #expect(fact.quality.contains(.noReadableData))
                }
            }
        }
    }

    private func withPreferences(_ body: (UserDefaults) throws -> Void) throws {
        let name = "health-review-fixture-boundary-\(UUID().uuidString)"
        let preferences = try #require(UserDefaults(suiteName: name))
        defer { preferences.removePersistentDomain(forName: name) }
        try body(preferences)
    }
}
#endif
