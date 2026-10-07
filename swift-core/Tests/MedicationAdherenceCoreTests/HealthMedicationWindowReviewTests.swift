import Foundation
import Testing
@testable import MedicationAdherenceCore

private enum MedicationWindowFixture {
    static func date(_ text: String) -> Date {
        ISO8601DateFormatter().date(from: text)!
    }

    static func id(_ number: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", number))!
    }

    static let start = date("2026-09-14T00:00:00Z")
    static let end = date("2026-09-15T00:00:00Z")
    static let snapshot = date("2026-09-16T09:00:00Z")

    static func record(_ number: Int, medication: Int = 100,
                       name: String? = "合成药品", due: Date = MedicationWindowFixture.start,
                       status: String = "pending", recorded: Date? = nil) -> HealthMedicationWindowRecord {
        HealthMedicationWindowRecord(taskID: id(number), medicationID: id(medication),
            medicationName: name, dueAt: due, statusRaw: status, recordedAt: recorded)
    }

    static func input(_ records: [HealthMedicationWindowRecord] = [],
                      start: Date = MedicationWindowFixture.start,
                      end: Date = MedicationWindowFixture.end, zone: String = "GMT",
                      healthAt: Date? = nil, medicationAt: Date = MedicationWindowFixture.snapshot,
                      status: HealthMedicationWindowReadStatus = .success) -> HealthMedicationWindowReviewInput {
        HealthMedicationWindowReviewInput(start: start, end: end, timeZoneIdentifier: zone,
            healthGeneratedAt: healthAt, medicationSnapshotAt: medicationAt,
            readStatus: status, records: records)
    }

    static func build(_ input: HealthMedicationWindowReviewInput) -> HealthMedicationWindowReviewResult {
        HealthMedicationWindowReview().build(input)
    }
}

@Test func healthMedicationWindowPreservesEveryRawStatusAndMissingTimestamp() {
    let raw = ["taken", "pending", "delayed", "skipped", "corrected", "unexpected-v2", "Taken", "", " taken "]
    let expected: [HealthMedicationWindowRecordStatus] = [
        .taken, .pending, .delayed, .skipped, .corrected, .unknown, .unknown, .unknown, .unknown
    ]
    let rows = raw.enumerated().map { MedicationWindowFixture.record($0.offset + 1, status: $0.element) }
    let input = MedicationWindowFixture.input(rows)
    let result = MedicationWindowFixture.build(input)
    #expect(result.availability == .recordsAvailable)
    #expect(result.rows.map(\.record) == rows)
    #expect(result.rows.map { $0.record.status } == expected)
    #expect(result.rows.map { $0.record.statusRaw } == raw)
    #expect(result.rows.allSatisfy { $0.record.recordedAt == nil && !$0.isRecordedAtOutsideWindow })
    #expect(result.rows.map { $0.record.status.displayName } == [
        "记录为已服", "尚未确认", "稍后提醒", "已忽略", "已修正", "未知状态", "未知状态", "未知状态", "未知状态"
    ])
    #expect(result.recordCount == 9)
    #expect(input.records == rows)
}

@Test func healthMedicationWindowKeepsMissingNamesAndDistinctSameNameRecords() {
    let records = [
        MedicationWindowFixture.record(1, medication: 101, name: nil),
        MedicationWindowFixture.record(2, medication: 102, name: " \n\t"),
        MedicationWindowFixture.record(3, medication: 103, name: "合成同名药品"),
        MedicationWindowFixture.record(4, medication: 104, name: "合成同名药品"),
        MedicationWindowFixture.record(5, medication: 104, name: "合成同名药品")
    ]
    let result = MedicationWindowFixture.build(MedicationWindowFixture.input(records))
    #expect(result.rows.map(\.record) == records)
    #expect(result.rows.map { $0.record.isMedicationInformationAvailable } == [false, false, true, true, true])
    #expect(result.recordCount == 5)
}

@Test func healthMedicationWindowUsesHalfOpenDueTimeAndStableTaskIDOrder() {
    let start = MedicationWindowFixture.start, end = MedicationWindowFixture.end
    let records = [
        MedicationWindowFixture.record(4, due: end),
        MedicationWindowFixture.record(3, due: start.addingTimeInterval(60)),
        MedicationWindowFixture.record(2, due: start),
        MedicationWindowFixture.record(5, due: start.addingTimeInterval(-1)),
        MedicationWindowFixture.record(1, due: start)
    ]
    let result = MedicationWindowFixture.build(MedicationWindowFixture.input(records))
    let reversed = MedicationWindowFixture.build(MedicationWindowFixture.input(Array(records.reversed())))
    #expect(result == reversed)
    #expect(result.rows.map { $0.record.taskID } == [1, 2, 3].map(MedicationWindowFixture.id))
    #expect(result.recordCount == 3)
}

@Test func healthMedicationWindowDoesNotMoveRecordsToTheirRecordedTimestamp() {
    let start = MedicationWindowFixture.start, end = MedicationWindowFixture.end
    let outsideBefore = start.addingTimeInterval(-60)
    let outsideAfter = end.addingTimeInterval(60)
    let records = [
        MedicationWindowFixture.record(1, status: "taken", recorded: outsideBefore),
        MedicationWindowFixture.record(2, status: "corrected", recorded: end),
        MedicationWindowFixture.record(3, status: "delayed", recorded: outsideAfter),
        MedicationWindowFixture.record(4, status: "skipped", recorded: start),
        MedicationWindowFixture.record(5, due: outsideBefore, status: "taken", recorded: start),
        MedicationWindowFixture.record(6, due: end, status: "taken", recorded: start)
    ]
    let result = MedicationWindowFixture.build(MedicationWindowFixture.input(records))
    #expect(result.rows.map { $0.record.recordedAt } == [outsideBefore, end, outsideAfter, start])
    #expect(result.rows.map(\.isRecordedAtOutsideWindow) == [true, true, true, false])
    #expect(result.recordCount == 4)
    #expect(result.windowMembershipExplanation == "按当前保存的提醒时间归入此时段；记录时间可能在时段外")
}

@Test func healthMedicationWindowDoesNotRewritePendingOrDelayedAfterTimePasses() {
    let end = MedicationWindowFixture.end
    let records = [MedicationWindowFixture.record(1), MedicationWindowFixture.record(2, status: "delayed")]
    let early = MedicationWindowFixture.build(MedicationWindowFixture.input(records, medicationAt: end))
    let late = MedicationWindowFixture.build(MedicationWindowFixture.input(records,
        medicationAt: end.addingTimeInterval(86_400 * 100)))
    #expect(early.rows == late.rows)
    #expect(late.rows.map { $0.record.status } == [.pending, .delayed])
    #expect(early.medicationSnapshotAt != late.medicationSnapshotAt)
}

@Test func healthMedicationWindowSeparatesNoHealthAndDifferentSnapshotTimes() {
    let records = [MedicationWindowFixture.record(1, status: "taken")]
    let withoutHealth = MedicationWindowFixture.build(MedicationWindowFixture.input(records))
    let olderHealthTime = MedicationWindowFixture.date("2026-09-10T09:00:00Z")
    let withHealth = MedicationWindowFixture.build(MedicationWindowFixture.input(records, healthAt: olderHealthTime))
    #expect(withoutHealth.healthGeneratedAt == nil)
    #expect(withoutHealth.rows == withHealth.rows)
    #expect(withHealth.healthGeneratedAt == olderHealthTime)
    #expect(withHealth.medicationSnapshotAt == MedicationWindowFixture.snapshot)
    #expect(withHealth.healthGeneratedAt != withHealth.medicationSnapshotAt)
    #expect(withoutHealth.recordCount == 1)
}

@Test func healthMedicationWindowDistinguishesEmptyFailureAndBudgetWithoutPartialCounts() {
    let empty = MedicationWindowFixture.build(MedicationWindowFixture.input())
    let outside = MedicationWindowFixture.record(1, due: MedicationWindowFixture.end)
    let noMatchingRows = MedicationWindowFixture.build(MedicationWindowFixture.input([outside]))
    #expect(empty.availability == .empty && empty.recordCount == 0)
    #expect(noMatchingRows.availability == .empty && noMatchingRows.recordCount == 0)
    for records in [[], [MedicationWindowFixture.record(1)]] {
        let failed = MedicationWindowFixture.build(MedicationWindowFixture.input(records, status: .failure))
        let budget = MedicationWindowFixture.build(MedicationWindowFixture.input(records, status: .budgetExceeded))
        #expect(failed.availability == .readFailed && failed.readStatus == .failure)
        #expect(budget.availability == .budgetExceeded && budget.readStatus == .budgetExceeded)
        #expect(failed.recordCount == nil && budget.recordCount == nil)
        #expect(failed.rows.isEmpty && budget.rows.isEmpty)
        #expect(failed.invalidReasons.isEmpty && budget.invalidReasons.isEmpty)
    }
}

@Test func healthMedicationWindowRejectsDuplicateIDsInsteadOfChoosingACopy() {
    let original = MedicationWindowFixture.record(1)
    let variants = [original,
        MedicationWindowFixture.record(1, status: "taken"),
        MedicationWindowFixture.record(1, medication: 999),
        MedicationWindowFixture.record(1, due: MedicationWindowFixture.end)]
    for duplicate in variants {
        let result = MedicationWindowFixture.build(MedicationWindowFixture.input([original, duplicate]))
        #expect(result.availability == .invalidInput)
        #expect(result.invalidReasons == [.duplicateTaskID])
        #expect(result.invalidTaskIDs == [original.taskID])
        #expect(result.rows.isEmpty && result.recordCount == nil)
    }
    let duplicates = [MedicationWindowFixture.record(3), original, original, MedicationWindowFixture.record(3)]
    let result = MedicationWindowFixture.build(MedicationWindowFixture.input(duplicates))
    #expect(result.invalidTaskIDs == [1, 3].map(MedicationWindowFixture.id))
    #expect(result == MedicationWindowFixture.build(MedicationWindowFixture.input(Array(duplicates.reversed()))))
}

@Test func healthMedicationWindowRejectsInvalidWindowAndTimezone() {
    let start = MedicationWindowFixture.start, end = MedicationWindowFixture.end
    for input in [MedicationWindowFixture.input(start: end, end: start),
                  MedicationWindowFixture.input(start: start, end: start)] {
        let result = MedicationWindowFixture.build(input)
        #expect(result.invalidReasons == [.emptyOrReversedWindow])
        #expect(result.availability == .invalidInput && result.recordCount == nil)
    }
    for zone in ["invalid-zone", "", " Asia/Shanghai "] {
        let result = MedicationWindowFixture.build(MedicationWindowFixture.input(zone: zone))
        #expect(result.invalidReasons == [.invalidTimeZone])
        #expect(result.availability == .invalidInput && result.rows.isEmpty)
    }
}

@Test func healthMedicationWindowRejectsNonFiniteDatesBeforeOrdering() {
    for value in [Double.nan, Double.infinity, -Double.infinity] {
        let invalid = Date(timeIntervalSince1970: value)
        for input in [MedicationWindowFixture.input(start: invalid), MedicationWindowFixture.input(end: invalid)] {
            let result = MedicationWindowFixture.build(input)
            #expect(result.invalidReasons == [.nonFiniteWindow])
            #expect(result.availability == .invalidInput && result.recordCount == nil)
        }
        for input in [MedicationWindowFixture.input(healthAt: invalid),
                      MedicationWindowFixture.input(medicationAt: invalid)] {
            let result = MedicationWindowFixture.build(input)
            #expect(result.invalidReasons == [.nonFiniteSnapshotTime])
            #expect(result.availability == .invalidInput && result.rows.isEmpty)
        }
        for record in [MedicationWindowFixture.record(1, due: invalid),
                       MedicationWindowFixture.record(1, recorded: invalid),
                       MedicationWindowFixture.record(1, due: MedicationWindowFixture.end, recorded: invalid)] {
            let result = MedicationWindowFixture.build(MedicationWindowFixture.input([record]))
            #expect(result.invalidReasons == [.nonFiniteRecordTime])
            #expect(result.invalidTaskIDs == [record.taskID])
            #expect(result.availability == .invalidInput && result.recordCount == nil)
        }
    }
}

@Test func healthMedicationWindowReportsInvalidInputEvenWhenReadFailed() {
    let result = MedicationWindowFixture.build(MedicationWindowFixture.input(
        [MedicationWindowFixture.record(1), MedicationWindowFixture.record(1)],
        zone: "invalid-zone", status: .failure))
    #expect(result.readStatus == .failure && result.availability == .invalidInput)
    #expect(result.invalidReasons == [.invalidTimeZone, .duplicateTaskID])
    #expect(result.recordCount == nil)
}

@Test func healthMedicationWindowUsesExplicitShanghaiAndDSTBounds() {
    let scenarios = [
        ("Asia/Shanghai", "2026-09-14T16:00:00Z", "2026-09-15T16:00:00Z", 24.0),
        ("America/New_York", "2026-03-08T05:00:00Z", "2026-03-09T04:00:00Z", 23.0),
        ("America/New_York", "2026-11-01T04:00:00Z", "2026-11-02T05:00:00Z", 25.0)
    ]
    for (zone, startText, endText, hours) in scenarios {
        let start = MedicationWindowFixture.date(startText), end = MedicationWindowFixture.date(endText)
        let records = [MedicationWindowFixture.record(1, due: start.addingTimeInterval(-1)),
                       MedicationWindowFixture.record(2, due: start),
                       MedicationWindowFixture.record(3, due: end.addingTimeInterval(-1)),
                       MedicationWindowFixture.record(4, due: end)]
        let input = MedicationWindowFixture.input(records, start: start, end: end, zone: zone)
        let result = MedicationWindowFixture.build(input)
        #expect(result.rows.map { $0.record.taskID } == [2, 3].map(MedicationWindowFixture.id))
        #expect(result.timeZoneIdentifier == zone)
        #expect(result.end.timeIntervalSince(result.start) == hours * 3600)
        let sameInstants = MedicationWindowFixture.build(MedicationWindowFixture.input(
            records, start: start, end: end, zone: "GMT"))
        #expect(result.rows == sameInstants.rows)
    }
}

@Test func healthMedicationWindowKeepsBothFallBackHourInstants() {
    let first = MedicationWindowFixture.date("2026-11-01T05:30:00Z")
    let second = MedicationWindowFixture.date("2026-11-01T06:30:00Z")
    let records = [MedicationWindowFixture.record(2, due: second), MedicationWindowFixture.record(1, due: first)]
    let result = MedicationWindowFixture.build(MedicationWindowFixture.input(records,
        start: MedicationWindowFixture.date("2026-11-01T04:00:00Z"),
        end: MedicationWindowFixture.date("2026-11-02T05:00:00Z"), zone: "America/New_York"))
    #expect(result.rows.map { $0.record.dueAt } == [first, second])
    #expect(result.recordCount == 2)
}

@Test func healthMedicationWindowDoesNotReplaceNoonBoundsWithMidnight() {
    let noon = MedicationWindowFixture.date("2026-09-14T12:00:00Z")
    let nextNoon = MedicationWindowFixture.date("2026-09-15T12:00:00Z")
    let records = [MedicationWindowFixture.record(1, due: MedicationWindowFixture.date("2026-09-14T11:00:00Z")),
                   MedicationWindowFixture.record(2, due: MedicationWindowFixture.date("2026-09-14T13:00:00Z")),
                   MedicationWindowFixture.record(3, due: MedicationWindowFixture.date("2026-09-15T08:00:00Z")),
                   MedicationWindowFixture.record(4, due: nextNoon)]
    let sleepWindow = MedicationWindowFixture.build(MedicationWindowFixture.input(records, start: noon, end: nextNoon))
    let midnightWindow = MedicationWindowFixture.build(MedicationWindowFixture.input(records))
    #expect(sleepWindow.rows.map { $0.record.taskID } == [2, 3].map(MedicationWindowFixture.id))
    #expect(midnightWindow.rows.map { $0.record.taskID } == [1, 2].map(MedicationWindowFixture.id))
}

@Test func healthMedicationWindowEightHourSleepDoesNotBecomeSleepAfterMedication() {
    // Synthetic facts: 22:00–06:00 sleep precedes an 08:00 reminder/record,
    // although both belong to the same noon-to-noon health review window.
    let sleepStart = MedicationWindowFixture.date("2026-09-14T22:00:00Z")
    let sleepEnd = MedicationWindowFixture.date("2026-09-15T06:00:00Z")
    let savedTime = MedicationWindowFixture.date("2026-09-15T08:00:00Z")
    let record = MedicationWindowFixture.record(1, due: savedTime, status: "taken", recorded: savedTime)
    let result = MedicationWindowFixture.build(MedicationWindowFixture.input([record],
        start: MedicationWindowFixture.date("2026-09-14T12:00:00Z"),
        end: MedicationWindowFixture.date("2026-09-15T12:00:00Z")))
    #expect(sleepEnd.timeIntervalSince(sleepStart) == 8 * 3600)
    #expect(sleepEnd < savedTime)
    #expect(result.rows.first?.record == record && result.recordCount == 1)
    #expect(result.rows.first?.record.status.displayName == "记录为已服")
}

@Test func healthMedicationWindowAcceptsSevenDaysWithoutRequestingFourteen() {
    let start = MedicationWindowFixture.start
    let end = MedicationWindowFixture.date("2026-09-21T00:00:00Z")
    let result = MedicationWindowFixture.build(MedicationWindowFixture.input(
        [MedicationWindowFixture.record(1)], start: start, end: end))
    #expect(result.start == start && result.end == end)
    #expect(result.availability == .recordsAvailable && result.recordCount == 1)
}

@Test func healthMedicationWindowIsDeterministicAndLeavesInputUnchanged() {
    let records = [MedicationWindowFixture.record(2, status: "corrected"),
                   MedicationWindowFixture.record(1, name: nil, status: "future-v3")]
    let input = MedicationWindowFixture.input(records, healthAt: MedicationWindowFixture.end)
    let original = input
    let first = MedicationWindowFixture.build(input)
    let second = MedicationWindowFixture.build(input)
    #expect(first == second && input == original)
    #expect(first.rows.map { $0.record.statusRaw } == ["future-v3", "corrected"])
    #expect(first.rows.allSatisfy { $0.record.recordedAt == nil })
}
