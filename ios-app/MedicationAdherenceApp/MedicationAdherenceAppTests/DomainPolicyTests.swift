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
    func notificationPolicyCapsActualRequestsAtSixty() {
        let policy = MedicationNotificationPolicy.default
        let candidates = (0..<75).map { index in
            MedicationReminderRequestCandidate(
                taskID: UUID(),
                dueAt: Date(timeIntervalSince1970: Double(2_000 + index)),
                wantsAlarm: false,
                wantsEscalation: false
            )
        }
        let plan = policy.requestPlan(
            candidates: candidates,
            occupiedRequestCount: 0,
            notificationAvailable: true,
            alarmAvailable: false
        )

        #expect(policy.maximumScheduledRequests == 60)
        #expect(plan.assignments.count == 60)
        #expect(plan.deferredTaskIDs.count == 15)
    }

    @Test
    func healthContextDefaultsPreserveLookbackWindow() {
        #expect(HealthContextPolicy.default.trendLookbackDays == 56)
    }
}
