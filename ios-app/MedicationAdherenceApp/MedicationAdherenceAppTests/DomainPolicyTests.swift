import Foundation
import Testing
@testable import MedicationAdherenceApp

struct DomainPolicyTests {
    @Test
    func medicalAIDefaultsPreserveTimeoutTrendAndTokenBudgets() {
        let policy = MedicalAIExecutionPolicy.default

        #expect(policy.cloudTimeout == .seconds(20))
        #expect(policy.trendLookbackDays == 14)
        #expect(policy.singleResponseTokenLimit == 220)
        #expect(policy.streamingResponseTokenLimit == 640)
        #expect(policy.repairTokenLimit == 360)
    }

    @Test
    func lifecycleDefaultsPreserveInterruptionWindow() {
        let policy = MedicationLifecyclePolicy.default

        #expect(policy.interruptionWindowDays == 14)
        #expect(policy.courseEndGraceDays == 1)
    }

    @Test
    func liveActivityDefaultsPreserveActivationAndStaleWindows() {
        let policy = MedicationLiveActivityPolicy.default

        #expect(policy.activationWindow == 5 * 60)
        #expect(policy.staleWindow == 10 * 60)
    }

    @Test
    func notificationPolicyCapsScheduledEntriesAtSixty() {
        let policy = MedicationNotificationPolicy.default
        let entries = Array(0..<75)

        #expect(policy.maximumScheduledEntries == 60)
        #expect(Array(policy.nearTermEntries(from: entries)) == Array(0..<60))
    }

    @Test
    func healthContextDefaultsPreserveLookbackWindow() {
        #expect(HealthContextPolicy.default.trendLookbackDays == 56)
    }
}
