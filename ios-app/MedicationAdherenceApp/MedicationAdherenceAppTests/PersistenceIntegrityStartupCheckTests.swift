import Foundation
import Testing
@testable import MedicationAdherenceApp

struct PersistenceIntegrityStartupCheckTests {
    @Test @MainActor
    func issueLogContainsOnlyCategoryCounts() {
        let recordID = "sensitive-record-id"
        let missingReferenceID = UUID()
        let report = PersistenceIntegrityReport(issues: [
            PersistenceIntegrityIssue(
                kind: .orphanDoseTaskPlan,
                recordID: recordID,
                missingReferenceID: missingReferenceID
            ),
            PersistenceIntegrityIssue(
                kind: .orphanDoseTaskPlan,
                recordID: "another-sensitive-id",
                missingReferenceID: UUID()
            ),
            PersistenceIntegrityIssue(
                kind: .orphanActionLogTask,
                recordID: "third-sensitive-id",
                missingReferenceID: UUID()
            )
        ])
        var logs: [String] = []

        let outcome = PersistenceIntegrityStartupCheck().run(
            audit: { report },
            log: { logs.append($0) }
        )

        #expect(outcome == .issuesFound(totalCount: 3))
        #expect(logs == [
            "persistence-integrity issues total=3 orphanActionLogTask=1 orphanDoseTaskPlan=2"
        ])
        #expect(!logs[0].contains(recordID))
        #expect(!logs[0].contains(missingReferenceID.uuidString))
    }

    @Test @MainActor
    func repeatedRunDoesNotAuditOrLogAgain() {
        let check = PersistenceIntegrityStartupCheck()
        var auditCount = 0
        var logs: [String] = []
        let audit = {
            auditCount += 1
            return PersistenceIntegrityReport(issues: [])
        }

        let firstOutcome = check.run(audit: audit, log: { logs.append($0) })
        let secondOutcome = check.run(audit: audit, log: { logs.append($0) })

        #expect(firstOutcome == .clean)
        #expect(secondOutcome == .alreadyRan)
        #expect(auditCount == 1)
        #expect(logs == ["persistence-integrity clean"])
    }
}
