import Foundation
import Testing
@testable import MedicationAdherenceApp

struct VisitSummarySnapshotRevisionTests {
    @Test
    func identicalInputsProduceStableIdentityIndependentOfGenerationTime() {
        let start = Date(timeIntervalSinceReferenceDate: 100)
        let end = Date(timeIntervalSinceReferenceDate: 200)

        let first = VisitSummarySnapshotRevision(
            startDate: start,
            endDate: end,
            medicationSignature: 1,
            taskSignature: 2,
            doseChangeSignature: 3,
            riskCardSignature: 4,
            healthSignalSignature: 5,
            planSignature: 6,
            lifecycleEventSignature: 7
        )
        let second = VisitSummarySnapshotRevision(
            startDate: start,
            endDate: end,
            medicationSignature: 1,
            taskSignature: 2,
            doseChangeSignature: 3,
            riskCardSignature: 4,
            healthSignalSignature: 5,
            planSignature: 6,
            lifecycleEventSignature: 7
        )

        #expect(first == second)
        #expect(first.id == second.id)
    }

    @Test
    func changedDataOrRangeInvalidatesIdentity() {
        let baseline = VisitSummarySnapshotRevision(
            startDate: Date(timeIntervalSinceReferenceDate: 100),
            endDate: Date(timeIntervalSinceReferenceDate: 200),
            medicationSignature: 1,
            taskSignature: 2,
            doseChangeSignature: 3,
            riskCardSignature: 4,
            healthSignalSignature: 5,
            planSignature: 6,
            lifecycleEventSignature: 7
        )
        let changedTask = VisitSummarySnapshotRevision(
            startDate: Date(timeIntervalSinceReferenceDate: 100),
            endDate: Date(timeIntervalSinceReferenceDate: 200),
            medicationSignature: 1,
            taskSignature: 20,
            doseChangeSignature: 3,
            riskCardSignature: 4,
            healthSignalSignature: 5,
            planSignature: 6,
            lifecycleEventSignature: 7
        )
        let changedRange = VisitSummarySnapshotRevision(
            startDate: Date(timeIntervalSinceReferenceDate: 101),
            endDate: Date(timeIntervalSinceReferenceDate: 200),
            medicationSignature: 1,
            taskSignature: 2,
            doseChangeSignature: 3,
            riskCardSignature: 4,
            healthSignalSignature: 5,
            planSignature: 6,
            lifecycleEventSignature: 7
        )

        #expect(baseline != changedTask)
        #expect(baseline.id != changedTask.id)
        #expect(baseline != changedRange)
        #expect(baseline.id != changedRange.id)
    }
}
