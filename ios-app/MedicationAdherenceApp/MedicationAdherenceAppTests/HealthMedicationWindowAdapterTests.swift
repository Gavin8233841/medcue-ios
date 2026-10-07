import Foundation
import MedicationAdherenceCore
import SwiftData
import Testing
@testable import MedicationAdherenceApp

/// Synthetic models in a real in-memory SwiftData container, never a user store.
@Suite(.serialized)
@MainActor
struct HealthMedicationWindowAdapterTests {
    private let adapter = HealthMedicationWindowAdapter()
    private let start = Date(timeIntervalSince1970: 1_789_344_000)
    private var end: Date { start.addingTimeInterval(86_400) }

    private func id(_ value: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", value))!
    }

    private func request(start: Date? = nil, end: Date? = nil,
                         zone: String = "Asia/Shanghai") -> HealthMedicationWindowRequest {
        HealthMedicationWindowRequest(start: start ?? self.start, end: end ?? self.end,
            timeZoneIdentifier: zone, healthGeneratedAt: self.start.addingTimeInterval(-60),
            medicationSnapshotAt: self.end.addingTimeInterval(60))
    }

    private func container() throws -> ModelContainer {
        try ModelContainer(for: StoredDoseTask.self, StoredMedication.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    }

    private func task(_ number: Int, medication: Int = 100, due: Date? = nil,
                      raw: String = "pending", recorded: Date? = nil) -> StoredDoseTask {
        let model = StoredDoseTask(id: id(number), medicationID: id(medication), planID: id(900),
            dueAt: due ?? start, doseValue: 1, doseUnit: "片", recordedAt: recorded)
        model.statusRaw = raw
        return model
    }

    private func medication(_ number: Int = 100, name: String = "合成药品") -> StoredMedication {
        StoredMedication(id: id(number), displayName: name, kind: .unknown,
            inputSource: .manual, createdAt: start)
    }

    private func save(_ tasks: [StoredDoseTask], medications: [StoredMedication] = [],
                      into container: ModelContainer) throws {
        let context = ModelContext(container)
        context.autosaveEnabled = false
        for medication in medications { context.insert(medication) }
        for task in tasks { context.insert(task) }
        try context.save()
        #expect(!context.hasChanges)
    }

    @Test func persistedRawStatusesAndNilTimestampsStayExact() throws {
        let container = try container()
        let raw = ["taken", "pending", "delayed", "skipped", "corrected", "future-v3", "", " Taken "]
        let tasks = raw.enumerated().map { task($0.offset + 1, raw: $0.element) }
        try save(tasks, medications: [medication()], into: container)
        let result = adapter.read(from: container, request: request())
        #expect(result.availability == .recordsAvailable)
        #expect(result.rows.map { $0.record.statusRaw } == raw)
        #expect(result.rows.map { $0.record.status } ==
            [.taken, .pending, .delayed, .skipped, .corrected, .unknown, .unknown, .unknown])
        #expect(result.rows.allSatisfy { $0.record.recordedAt == nil })
        #expect(result.rows.allSatisfy { $0.record.medicationName == "合成药品" })
        #expect(result.medicationSnapshotAt == end.addingTimeInterval(60))
        #expect(result.healthGeneratedAt == start.addingTimeInterval(-60))
        #expect(result.timeZoneIdentifier == "Asia/Shanghai")
        let fresh = ModelContext(container)
        let persisted = try fresh.fetch(FetchDescriptor<StoredDoseTask>()).sorted { $0.id.uuidString < $1.id.uuidString }
        #expect(persisted.map(\.statusRaw) == raw)
        #expect(persisted.allSatisfy { $0.recordedAt == nil })
        #expect(!fresh.hasChanges)
    }

    @Test func persistedForeignKeysKeepMissingBlankAndSameNamesDistinct() throws {
        let container = try container()
        try save([task(1, medication: 101), task(2, medication: 102), task(3, medication: 103),
                  task(4, medication: 104), task(5, medication: 104)],
                 medications: [medication(102, name: " \n"), medication(103, name: "同名"),
                               medication(104, name: "同名")], into: container)
        let result = adapter.read(from: container, request: request())
        #expect(result.recordCount == 5)
        #expect(result.rows.map { $0.record.medicationID } == [101, 102, 103, 104, 104].map(id))
        #expect(result.rows.map { $0.record.medicationName } == [nil, " \n", "同名", "同名", "同名"])
        #expect(result.rows.map { $0.record.isMedicationInformationAvailable } == [false, false, true, true, true])
    }

    @Test func persistedDueBoundsDoNotFollowRecordedAt() throws {
        let container = try container()
        try save([task(1, due: start.addingTimeInterval(-1), raw: "taken", recorded: start),
                  task(2, due: start, raw: "taken", recorded: end),
                  task(3, due: end.addingTimeInterval(-1), raw: "delayed"),
                  task(4, due: end, raw: "corrected", recorded: start)], into: container)
        let result = adapter.read(from: container, request: request())
        #expect(result.rows.map { $0.record.taskID } == [id(2), id(3)])
        #expect(result.rows.map { $0.record.dueAt } == [start, end.addingTimeInterval(-1)])
        #expect(result.rows.map { $0.record.recordedAt } == [end, nil])
        #expect(result.rows.map(\.isRecordedAtOutsideWindow) == [true, false])
    }

    @Test func persistedPostponementUsesCurrentSavedDueAt() throws {
        let container = try container()
        try save([task(1)], into: container)
        let context = ModelContext(container)
        context.autosaveEnabled = false
        let saved = try #require(context.fetch(FetchDescriptor<StoredDoseTask>()).first)
        saved.dueAt = end
        saved.statusRaw = "delayed"
        saved.recordedAt = start
        try context.save()
        let oldWindow = adapter.read(from: container, request: request())
        #expect(oldWindow.availability == .empty)
        let nextWindow = adapter.read(from: container, request: request(start: end, end: end.addingTimeInterval(86_400)))
        #expect(nextWindow.rows.first?.record.dueAt == end)
        #expect(nextWindow.rows.first?.record.statusRaw == "delayed")
        #expect(nextWindow.rows.first?.record.recordedAt == start)
    }

    @Test func unsavedChangesAreNeitherExposedNorCommittedByRead() throws {
        let container = try container()
        try save([task(1)], into: container)
        let editing = ModelContext(container)
        editing.autosaveEnabled = false
        let saved = try #require(editing.fetch(FetchDescriptor<StoredDoseTask>()).first)
        saved.statusRaw = "taken"
        saved.recordedAt = end
        editing.insert(task(2))
        let result = adapter.read(from: container, request: request())
        #expect(result.recordCount == 1)
        #expect(result.rows.first?.record.statusRaw == "pending")
        #expect(result.rows.first?.record.recordedAt == nil)
        #expect(editing.hasChanges)
        editing.rollback()
    }

    @Test func realFetchBudgetOverflowDoesNotPublishPartialRows() throws {
        let container = try container()
        try save([task(1), task(2)], into: container)
        let overflow = adapter.read(from: container, request: request(), taskBudget: 1)
        #expect(overflow.availability == .budgetExceeded)
        #expect(overflow.recordCount == nil && overflow.rows.isEmpty)
        let exact = adapter.read(from: container, request: request(), taskBudget: 2)
        #expect(exact.recordCount == 2)
    }

    @Test func medicationLookupBudgetIsBoundedIncludingMissingRelationships() throws {
        let container = try container()
        try save([task(1, medication: 101), task(2, medication: 102)], into: container)
        let result = adapter.read(from: container, request: request(), medicationBudget: 1)
        #expect(result.availability == .budgetExceeded)
        #expect(result.rows.isEmpty && result.recordCount == nil)
        #expect(adapter.read(from: container, request: request(), medicationBudget: 2).recordCount == 2)
    }

    @Test func emptyFailureAndBudgetAreDifferent() throws {
        let empty = adapter.read(from: try container(), request: request())
        let failed = adapter.project(.failed, request: request())
        let budget = adapter.project(.budgetExceeded, request: request())
        #expect(empty.availability == .empty && empty.recordCount == 0)
        #expect(failed.availability == .readFailed && failed.recordCount == nil)
        #expect(budget.availability == .budgetExceeded && budget.recordCount == nil)
        #expect(failed.rows.isEmpty && budget.rows.isEmpty)
    }

    @Test func invalidRequestsAndBudgetsNeverBecomeSuccessfulEmptyReads() throws {
        let container = try container()
        for input in [request(end: start), request(zone: "not/a/time-zone"),
                      request(start: Date(timeIntervalSince1970: .infinity))] {
            let result = adapter.read(from: container, request: input)
            #expect(result.availability == .invalidInput && result.recordCount == nil)
        }
        for budget in [0, -1, Int.max] {
            #expect(adapter.read(from: container, request: request(), taskBudget: budget).availability == .budgetExceeded)
        }
    }

    @Test func suppliedDuplicatesAreNotArbitrarilyCollapsed() {
        let duplicateTasks = adapter.project(.complete(tasks: [task(1), task(1, raw: "taken")], medications: []), request: request())
        #expect(duplicateTasks.availability == .invalidInput)
        #expect(duplicateTasks.invalidReasons == [.duplicateTaskID])
        let duplicateNames = adapter.project(.complete(tasks: [task(1)],
            medications: [medication(name: "合成甲"), medication(name: "合成乙")]), request: request())
        #expect(duplicateNames.availability == .readFailed && duplicateNames.recordCount == nil)
    }

    @Test func explicitSevenThirtyAndFiftySixDayWindowsAreUnchanged() throws {
        let container = try container()
        try save([task(1)], into: container)
        for days in [7, 30, 56] {
            let suppliedEnd = start.addingTimeInterval(Double(days) * 86_400)
            let result = adapter.read(from: container, request: request(end: suppliedEnd))
            #expect(result.start == start && result.end == suppliedEnd && result.recordCount == 1)
        }
    }

    @Test func persistedDSTAndNoonBoundsAreNotRecalculated() throws {
        let formatter = ISO8601DateFormatter()
        let start = try #require(formatter.date(from: "2026-03-07T17:00:00Z"))
        let end = try #require(formatter.date(from: "2026-03-08T16:00:00Z"))
        let container = try container()
        try save([task(1, due: start), task(2, due: end)], into: container)
        let result = adapter.read(from: container, request: request(start: start, end: end, zone: "America/New_York"))
        #expect(result.rows.map { $0.record.taskID } == [id(1)])
        #expect(result.start == start && result.end == end)
        #expect(result.end.timeIntervalSince(result.start) == 23 * 3_600)
    }
}
