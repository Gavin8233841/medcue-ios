import Foundation
import MedicationAdherenceCore
import SwiftData
import Testing
@testable import MedicationAdherenceApp

#if (DEBUG || MEDCUE_DEMO) && targetEnvironment(simulator)
@Suite(.serialized)
@MainActor
struct BundledDemoIsolationTests {
    @Test
    func onlyAnExplicitValidUniqueSessionRequestsTheDemo() throws {
        let id = UUID()
        let ordinary = try BundledDemoSession.requestedSessionID(in: ["MedCue"])
        #expect(ordinary == nil)
        let explicit = try BundledDemoSession.requestedSessionID(in: ["MedCue", "--bundled-demo-session", id.uuidString])
        #expect(explicit == id)
        for arguments in [
            ["--bundled-demo-session"], ["--bundled-demo-session", "invalid"],
            ["--bundled-demo-session=" + id.uuidString],
            ["--bundled-demo-session", id.uuidString, "--bundled-demo-session", id.uuidString],
            ["--bundled-demo-session", id.uuidString, "--elder-ui-fixture", "due"],
            ["--bundled-demo-session", id.uuidString, "--seed-demo-data"],
            ["--bundled-demo-session", id.uuidString, "--medical-ai-smoke-test"],
            ["--bundled-demo-session", id.uuidString, "--reminder-live-activity-smoke-test"],
            ["--bundled-demo-session", id.uuidString, "--local-medical-model-smoke"]
        ] {
            #expect(BundledDemoSession.isRequested(in: arguments))
            expectFailure(.invalidArguments) { _ = try BundledDemoSession.requestedSessionID(in: arguments) }
        }
    }

    @Test
    func historicalFiveDrugSourceHasTodayTasksAndCorrectAssociations() throws {
        let directory = try TestDirectory()
        defer { directory.removeOwnedFiles() }
        let calendar = calendar(in: "Asia/Shanghai")
        let date = try date(year: 2026, month: 10, day: 10, hour: 12, calendar: calendar)
        let session = try BundledDemoSession.open(sessionID: UUID(), referenceDate: date, calendar: calendar,
                                                  testRoot: directory.root)
        defer { clearPreferences(session.sessionID) }
        let context = session.modelContainer.mainContext
        let medications = try context.fetch(FetchDescriptor<StoredMedication>())
        #expect(Set(medications.map(\.displayName)) == ["布洛芬", "对乙酰氨基酚", "人工泪液", "氯雷他定", "维生素 D3"])
        let expectedIDs = Set((1...5).compactMap { UUID(uuidString: "44454D4F-4D45-4443-5545-00000000000\($0)") })
        #expect(Set(medications.map(\.id)) == expectedIDs)
        #expect(medications.allSatisfy { $0.isDemoContent && $0.photoData == nil && $0.coreMedication.inputSource == .demoData })
        let plans = try context.fetch(FetchDescriptor<StoredMedicationPlan>())
        let tasks = try context.fetch(FetchDescriptor<StoredDoseTask>())
        let today = tasks.filter { calendar.isDate($0.dueAt, inSameDayAs: date) }
        #expect(tasks.count == 305)
        #expect(today.count == 5 && today.allSatisfy { $0.status == .pending && $0.recordedAt == nil })
        #expect(Set(today.map(\.medicationID)) == expectedIDs)
        let projection = TodayDoseProjectionStore().projection(for: TodayDoseProjectionInput(
            tasks: tasks, medications: medications, now: date, calendar: calendar
        ))
        #expect(Set(projection.eligibleTodayTasks.map(\.id)) == Set(today.map(\.id)))
        #expect(projection.visibleOpenTimelineTasks.count == 5)
        for medication in medications {
            let plan = try #require(plans.first { $0.medicationID == medication.id })
            let associated = tasks.filter { $0.medicationID == medication.id }
            #expect(associated.count == 61 && associated.allSatisfy { $0.planID == plan.id && $0.doseUnit == plan.doseUnit })
        }
        let stocks = try context.fetch(FetchDescriptor<StoredMedicationStock>())
        let labels = try context.fetch(FetchDescriptor<StoredMedicationLabel>())
        let risks = try context.fetch(FetchDescriptor<StoredRiskCard>())
        #expect(stocks.count == 5 && stocks.allSatisfy { $0.remainingQuantity == 90 })
        #expect(labels.count == 5 && labels.allSatisfy { $0.source == .demo && $0.coreLabel != nil })
        #expect(!risks.isEmpty && risks.allSatisfy { expectedIDs.contains($0.medicationID) })
        let change = try #require(try context.fetch(FetchDescriptor<StoredMedicationDoseChange>()).first)
        let vitamin = try #require(medications.first { $0.displayName == "维生素 D3" })
        #expect(change.medicationID == vitamin.id && change.previousDoseValue == 1 && change.newDoseValue == 2)
        #expect(tasks.filter { $0.medicationID == vitamin.id && $0.dueAt >= change.effectiveFrom }.allSatisfy { $0.doseValue == 2 })
        #expect(tasks.filter { $0.medicationID == vitamin.id && $0.dueAt < change.effectiveFrom }.allSatisfy { $0.doseValue == 1 })
    }

    @Test
    func readyRestartPreservesEditsIdentityPreferencesAndClockWithoutReseeding() throws {
        let directory = try TestDirectory()
        defer { directory.removeOwnedFiles() }
        let id = UUID()
        defer { clearPreferences(id) }
        let calendar = calendar(in: "UTC")
        let originalDate = try date(year: 2025, month: 12, day: 31, hour: 23, calendar: calendar)
        let captured: (UUID, Set<UUID>, Data) = try {
            let session = try BundledDemoSession.open(sessionID: id, referenceDate: originalDate,
                                                       calendar: calendar, testRoot: directory.root)
            let context = session.modelContainer.mainContext
            let tasks = try context.fetch(FetchDescriptor<StoredDoseTask>())
            let task = try #require(tasks.first { calendar.isDate($0.dueAt, inSameDayAs: originalDate) })
            task.status = .skipped
            task.reason = "保留用户在隔离演示中的修改"
            let stock = try #require(try context.fetch(FetchDescriptor<StoredMedicationStock>()).first)
            stock.remainingQuantity = 42
            try context.save()
            session.preferences.set("persistent demo preference", forKey: "sentinel")
            let manifest = try Data(contentsOf: directory.manifest(id))
            return (task.id, Set(tasks.map(\.id)), manifest)
        }()
        // Today's owner defaults to the device calendar: do not silently reopen
        // a seed in another time zone and present an incomplete demo day.
        expectFailure(.incompatibleSession) {
            _ = try BundledDemoSession.open(sessionID: id, calendar: self.calendar(in: "Asia/Tokyo"),
                                             testRoot: directory.root)
        }
        let reopened = try BundledDemoSession.open(sessionID: id, referenceDate: originalDate.addingTimeInterval(86_400),
                                                    calendar: calendar, testRoot: directory.root)
        let tasks = try reopened.modelContainer.mainContext.fetch(FetchDescriptor<StoredDoseTask>())
        let changed = try #require(tasks.first { $0.id == captured.0 })
        #expect(changed.status == .skipped && changed.reason == "保留用户在隔离演示中的修改")
        #expect(Set(tasks.map(\.id)) == captured.1 && tasks.count == 305)
        let stocks = try reopened.modelContainer.mainContext.fetch(FetchDescriptor<StoredMedicationStock>())
        #expect(stocks.contains { $0.remainingQuantity == 42 })
        #expect(reopened.referenceDate == originalDate && reopened.calendar.timeZone == calendar.timeZone)
        #expect(reopened.preferences.string(forKey: "sentinel") == "persistent demo preference")
        let currentManifest = try Data(contentsOf: directory.manifest(id))
        #expect(currentManifest == captured.2)
        expectFailure(.notFresh) { try DemoDataSeeder.seedFreshBundledSession(reopened) }
    }

    @Test
    func fixedClockAtMidnightAndDSTStillSeedsExactlyOneDemoDay() throws {
        for (zone, month, day, hour) in [("UTC", 1, 1, 0), ("America/Los_Angeles", 3, 10, 12),
                                       ("America/Los_Angeles", 11, 3, 23)] {
            let directory = try TestDirectory()
            defer { directory.removeOwnedFiles() }
            let calendar = calendar(in: zone)
            let date = try date(year: 2024, month: month, day: day, hour: hour, calendar: calendar)
            let session = try BundledDemoSession.open(sessionID: UUID(), referenceDate: date,
                                                      calendar: calendar, testRoot: directory.root)
            defer { clearPreferences(session.sessionID) }
            let tasks = try session.modelContainer.mainContext.fetch(FetchDescriptor<StoredDoseTask>())
            let today = tasks.filter { calendar.isDate($0.dueAt, inSameDayAs: date) }
            #expect(today.count == 5 && today.allSatisfy { $0.status == .pending })
            #expect(tasks.filter { $0.dueAt < calendar.startOfDay(for: date) }.count == 300)
            let dayStarts = Set(tasks.map { calendar.startOfDay(for: $0.dueAt) })
            #expect(dayStarts.count == 61)
            let medications = try session.modelContainer.mainContext.fetch(FetchDescriptor<StoredMedication>())
            let projection = TodayDoseProjectionStore().projection(for: TodayDoseProjectionInput(
                tasks: tasks, medications: medications, now: date, calendar: calendar
            ))
            #expect(Set(projection.eligibleTodayTasks.map(\.id)) == Set(today.map(\.id)))
            #expect(projection.visibleOpenTimelineTasks.count == 5)
        }
    }

    @Test
    func primarySentinelAndStandardPreferenceDomainRemainUntouched() throws {
        let directory = try TestDirectory()
        defer { directory.removeOwnedFiles() }
        let primaryURL = directory.parent.appendingPathComponent("primary-sentinel.store")
        let primary = try MedicationAdherenceModelContainer.make(storeURL: primaryURL)
        primary.mainContext.autosaveEnabled = false
        let sentinel = StoredMedication(displayName: "非演示哨兵", kind: .unknown, inputSource: .manual)
        primary.mainContext.insert(sentinel)
        try primary.mainContext.save()
        let originalPreferences = NSDictionary(dictionary: UserDefaults.standard.dictionaryRepresentation())
        let session = try BundledDemoSession.open(sessionID: UUID(), testRoot: directory.root)
        defer { clearPreferences(session.sessionID) }
        session.preferences.set("owned", forKey: "bundled-demo-test-sentinel")
        let primaryRecords = try primary.mainContext.fetch(FetchDescriptor<StoredMedication>())
        #expect(primaryRecords.count == 1 && primaryRecords.first?.id == sentinel.id)
        #expect(primaryRecords.first?.displayName == "非演示哨兵" && primaryRecords.first?.isDemoContent == false)
        #expect(session.storeURL != primaryURL)
        #expect(NSDictionary(dictionary: UserDefaults.standard.dictionaryRepresentation()) == originalPreferences)
    }

    @Test
    func failedSeedOrSaveCannotBecomeReadyOrBeAutomaticallyRetried() throws {
        for failure in [BundledDemoSession.TestFailure.beforeSeed, .seedSave, .beforeReady] {
            let directory = try TestDirectory()
            defer { directory.removeOwnedFiles() }
            let id = UUID()
            defer { clearPreferences(id) }
            expectFailure(.injectedFailure) {
                _ = try BundledDemoSession.open(sessionID: id, testRoot: directory.root, testFailure: failure)
            }
            let data = try Data(contentsOf: directory.manifest(id))
            let manifest = try JSONDecoder().decode(BundledDemoSession.Manifest.self, from: data)
            #expect(!manifest.isReady)
            expectFailure(.incompleteSession) { _ = try BundledDemoSession.open(sessionID: id, testRoot: directory.root) }
            let unchanged = try Data(contentsOf: directory.manifest(id))
            #expect(unchanged == data)
            if failure == .beforeReady {
                // Save succeeded but publication failed: retain its owned records.
                let preserved = try MedicationAdherenceModelContainer.make(storeURL: directory.store(id))
                let count = try preserved.mainContext.fetchCount(FetchDescriptor<StoredDoseTask>())
                #expect(count == 305)
            }
        }
    }

    @Test
    func aFreshSessionObjectCannotImportTwiceIntoItsNowNonemptyStore() throws {
        let directory = try TestDirectory()
        defer { directory.removeOwnedFiles() }
        let session = try BundledDemoSession.open(sessionID: UUID(), testRoot: directory.root)
        defer { clearPreferences(session.sessionID) }
        expectFailure(.nonemptyStore) { try DemoDataSeeder.seedFreshBundledSession(session) }
        let count = try session.modelContainer.mainContext.fetchCount(FetchDescriptor<StoredDoseTask>())
        #expect(count == 305)
    }

    @Test
    func unknownDirectoryIsRejectedWithoutOpeningOrReplacingItsFiles() throws {
        let directory = try TestDirectory()
        defer { directory.removeOwnedFiles() }
        let id = UUID()
        try FileManager.default.createDirectory(at: directory.session(id), withIntermediateDirectories: true)
        let sentinel = Data("unknown store must not be opened".utf8)
        try sentinel.write(to: directory.store(id))
        expectFailure { _ = try BundledDemoSession.open(sessionID: id, testRoot: directory.root) }
        let after = try Data(contentsOf: directory.store(id))
        #expect(after == sentinel && !FileManager.default.fileExists(atPath: directory.manifest(id).path))
    }

    @Test
    func symlinkedSessionCannotRedirectTheFactoryToAnotherStore() throws {
        let directory = try TestDirectory()
        defer { directory.removeOwnedFiles() }
        let target = directory.parent.appendingPathComponent("other-data", isDirectory: true)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: false)
        let sentinelURL = target.appendingPathComponent("demo.store")
        let sentinel = Data("other store unchanged".utf8)
        try sentinel.write(to: sentinelURL)
        try FileManager.default.createDirectory(at: directory.root, withIntermediateDirectories: false)
        let id = UUID()
        try FileManager.default.createSymbolicLink(at: directory.session(id), withDestinationURL: target)
        expectFailure(.unsafeDirectory) { _ = try BundledDemoSession.open(sessionID: id, testRoot: directory.root) }
        let after = try Data(contentsOf: sentinelURL)
        #expect(after == sentinel)
    }

    @Test
    func incompatibleReadyManifestDoesNotRewriteOrReseedTheStore() throws {
        let directory = try TestDirectory()
        defer { directory.removeOwnedFiles() }
        let id = UUID()
        defer { clearPreferences(id) }
        try {
            _ = try BundledDemoSession.open(sessionID: id, testRoot: directory.root)
        }()
        let original = try JSONDecoder().decode(BundledDemoSession.Manifest.self,
                                                from: Data(contentsOf: directory.manifest(id)))
        let incompatible = BundledDemoSession.Manifest(sessionID: id, sourceVersion: 999,
                                                       referenceDate: original.referenceDate,
                                                       timeZoneID: original.timeZoneID,
                                                       calendarIdentifier: original.calendarIdentifier, isReady: true)
        try JSONEncoder().encode(incompatible).write(to: directory.manifest(id), options: .atomic)
        let before = try Data(contentsOf: directory.store(id))
        expectFailure(.incompatibleSession) { _ = try BundledDemoSession.open(sessionID: id, testRoot: directory.root) }
        let after = try Data(contentsOf: directory.store(id))
        #expect(after == before)
    }

    private func expectFailure(_ expected: BundledDemoSession.Failure? = nil, _ operation: () throws -> Void) {
        do {
            try operation()
            Issue.record("Expected isolated operation to fail closed")
        } catch {
            if let expected { #expect((error as? BundledDemoSession.Failure) == expected) }
        }
    }

    private func calendar(in zone: String) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: zone)!
        return calendar
    }

    private func date(year: Int, month: Int, day: Int, hour: Int, calendar: Calendar) throws -> Date {
        try #require(calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour)))
    }

    private func clearPreferences(_ id: UUID) {
        let name = "medcue.bundled-demo.\(id.uuidString)"
        UserDefaults(suiteName: name)?.removePersistentDomain(forName: name)
    }

    private struct TestDirectory {
        let parent: URL
        var root: URL { parent.appendingPathComponent("BundledDemoStores", isDirectory: true) }
        init() throws {
            parent = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
                .appendingPathComponent("MedCueBundledDemoTests-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: false)
        }
        func session(_ id: UUID) -> URL { root.appendingPathComponent(id.uuidString, isDirectory: true) }
        func store(_ id: UUID) -> URL { session(id).appendingPathComponent("demo.store") }
        func manifest(_ id: UUID) -> URL { session(id).appendingPathComponent("session.json") }
        func removeOwnedFiles() { try? FileManager.default.removeItem(at: parent) }
    }
}
#endif
