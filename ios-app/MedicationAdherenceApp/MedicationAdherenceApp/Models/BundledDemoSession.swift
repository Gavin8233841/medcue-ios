import Foundation
import SwiftData

#if (DEBUG || MEDCUE_DEMO) && targetEnvironment(simulator)
/// An explicit synthetic session. No primary store, standard preferences or services.
@MainActor
final class BundledDemoSession {
    static let argument = "--bundled-demo-session"
    static let sourceVersion = 1

    enum Failure: Error, Equatable {
        case invalidArguments, unsafeDirectory, incompleteSession, incompatibleSession
        case nonemptyStore, notFresh, invalidSeed, injectedFailure
    }

    enum TestFailure: Equatable {
        case none, beforeSeed, seedSave, beforeReady
    }

    struct Manifest: Codable, Equatable {
        let sessionID: UUID
        let sourceVersion: Int
        let referenceDate: Date
        let timeZoneID: String
        let calendarIdentifier: String
        var isReady: Bool
    }

    let sessionID: UUID
    let modelContainer: ModelContainer
    let preferences: UserDefaults
    let referenceDate: Date
    let calendar: Calendar
    let storeURL: URL
    let isNewlyCreated: Bool
    private let manifestURL: URL
    private let testFailure: TestFailure
    var failsSeedSave: Bool { testFailure == .seedSave }

    static func isRequested(in arguments: [String]) -> Bool {
        // Even malformed requests must prevent the caller's primary-store fallback.
        arguments.contains { $0 == argument || $0.hasPrefix(argument + "=") }
    }

    static func requestedSessionID(in arguments: [String]) throws -> UUID? {
        guard isRequested(in: arguments) else { return nil }
        let occurrences = arguments.indices.filter { arguments[$0] == argument }
        let incompatible = ["--elder-ui-fixture", "--elder-ui-session", "--seed-demo-data",
                            "--reminder-live-activity-smoke-test", "--medical-ai-smoke-test",
                            "--local-medical-model-smoke", "--medcue-recovery-isolated-test-store",
                            "--medcue-simulate-initial-store-open-failure", "--medcue-simulate-retry-store-open-failure"]
        guard occurrences.count == 1,
              !arguments.contains(where: { $0.hasPrefix(argument + "=") }),
              !arguments.contains(where: { value in
                  incompatible.contains { value == $0 || value.hasPrefix($0 + "=") }
              }),
              let index = occurrences.first, arguments.indices.contains(index + 1),
              let sessionID = UUID(uuidString: arguments[index + 1])
        else { throw Failure.invalidArguments }
        return sessionID
    }

    /// testRoot is confined to a named, UUID-owned temporary test directory.
    /// A ready session ignores a new reference date: its clock and user actions persist.
    static func open(
        sessionID: UUID, referenceDate: Date = Date(), calendar: Calendar = .current,
        testRoot: URL? = nil, testFailure: TestFailure = .none
    ) throws -> BundledDemoSession {
        let files = FileManager.default
        let root: URL
        if let testRoot {
            let temporary = files.temporaryDirectory.resolvingSymlinksInPath().standardizedFileURL
            let proposedParent = testRoot.deletingLastPathComponent().standardizedFileURL
            let prefix = "MedCueBundledDemoTests-"
            guard testRoot.lastPathComponent == "BundledDemoStores",
                  proposedParent.deletingLastPathComponent().resolvingSymlinksInPath() == temporary,
                  proposedParent.lastPathComponent.hasPrefix(prefix),
                  UUID(uuidString: String(proposedParent.lastPathComponent.dropFirst(prefix.count))) != nil
            else { throw Failure.unsafeDirectory }
            let parent = temporary.appendingPathComponent(proposedParent.lastPathComponent, isDirectory: true)
            if files.fileExists(atPath: parent.path) { try assertDirectory(parent) }
            root = parent.appendingPathComponent("BundledDemoStores", isDirectory: true)
        } else {
            guard let support = files.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            else { throw Failure.unsafeDirectory }
            root = support.resolvingSymlinksInPath().appendingPathComponent("BundledDemoStores", isDirectory: true)
        }
        if files.fileExists(atPath: root.path) { try assertDirectory(root) }
        try files.createDirectory(at: root, withIntermediateDirectories: true)
        try assertDirectory(root)
        let directory = root.appendingPathComponent(sessionID.uuidString, isDirectory: true)
        let storeURL = directory.appendingPathComponent("demo.store")
        let manifestURL = directory.appendingPathComponent("session.json")
        let isNew = !files.fileExists(atPath: directory.path)
        var manifest: Manifest
        if isNew {
            // No replacement of a racing creator, unknown or partial directory.
            try files.createDirectory(at: directory, withIntermediateDirectories: false)
            manifest = Manifest(sessionID: sessionID, sourceVersion: sourceVersion,
                                referenceDate: referenceDate, timeZoneID: calendar.timeZone.identifier,
                                calendarIdentifier: String(describing: calendar.identifier), isReady: false)
            try JSONEncoder().encode(manifest).write(to: manifestURL, options: .atomic)
        } else {
            try assertDirectory(directory)
            try assertRegularFile(manifestURL)
            manifest = try JSONDecoder().decode(Manifest.self, from: Data(contentsOf: manifestURL))
            guard manifest.isReady else { throw Failure.incompleteSession }
            guard manifest.sessionID == sessionID, manifest.sourceVersion == sourceVersion,
                  manifest.calendarIdentifier == String(describing: calendar.identifier),
                  manifest.timeZoneID == calendar.timeZone.identifier,
                  TimeZone(identifier: manifest.timeZoneID) != nil
            else { throw Failure.incompatibleSession }
            try assertRegularFile(storeURL)
        }
        try assertOwnedContents(directory)
        guard let timeZone = TimeZone(identifier: manifest.timeZoneID) else { throw Failure.incompatibleSession }
        var storedCalendar = calendar
        storedCalendar.timeZone = timeZone
        let container = try MedicationAdherenceModelContainer.make(storeURL: storeURL)
        container.mainContext.autosaveEnabled = false
        guard let preferences = UserDefaults(suiteName: "medcue.bundled-demo.\(sessionID.uuidString)")
        else { throw Failure.invalidArguments }
        let session = BundledDemoSession(sessionID: sessionID, modelContainer: container, preferences: preferences,
                                         manifest: manifest, calendar: storedCalendar, storeURL: storeURL,
                                         manifestURL: manifestURL, isNewlyCreated: isNew, testFailure: testFailure)
        if isNew {
            if testFailure == .beforeSeed { throw Failure.injectedFailure }
            try DemoDataSeeder.seedFreshBundledSession(session)
            if testFailure == .beforeReady { throw Failure.injectedFailure }
            manifest.isReady = true
            try JSONEncoder().encode(manifest).write(to: manifestURL, options: .atomic)
        } else {
            try session.assertOwnedMedicationIdentity()
        }
        return session
    }

    private init(
        sessionID: UUID, modelContainer: ModelContainer, preferences: UserDefaults,
        manifest: Manifest, calendar: Calendar, storeURL: URL, manifestURL: URL,
        isNewlyCreated: Bool, testFailure: TestFailure
    ) {
        self.sessionID = sessionID
        self.modelContainer = modelContainer
        self.preferences = preferences
        referenceDate = manifest.referenceDate
        self.calendar = calendar
        self.storeURL = storeURL
        self.manifestURL = manifestURL
        self.isNewlyCreated = isNewlyCreated
        self.testFailure = testFailure
    }

    func assertEmptyStore() throws {
        let context = modelContainer.mainContext
        func empty<T: PersistentModel>(_ type: T.Type) throws {
            guard try context.fetchCount(FetchDescriptor<T>()) == 0 else { throw Failure.nonemptyStore }
        }
        try empty(StoredMedication.self)
        try empty(StoredMedicationLifecycleEvent.self)
        try empty(StoredMedicationPlan.self)
        try empty(StoredMedicationDoseChange.self)
        try empty(StoredDoseTask.self)
        try empty(StoredRiskCard.self)
        try empty(StoredMedicationLabel.self)
        try empty(StoredMedicationStock.self)
        try empty(StoredDoseActionLog.self)
        try empty(StoredAIConsent.self)
        try empty(StoredAIChatMessage.self)
    }

    private func assertOwnedMedicationIdentity() throws {
        let medications = try modelContainer.mainContext.fetch(FetchDescriptor<StoredMedication>())
        // Archive/name edits are user actions; never normalize them on reopen.
        guard Set(medications.map(\.id)) == DemoDataSeeder.bundledMedicationIDs,
              medications.count == 5,
              medications.allSatisfy({ $0.isDemoContent && $0.coreMedication.inputSource == .demoData })
        else { throw Failure.incompatibleSession }
    }

    private static func assertDirectory(_ url: URL) throws {
        let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard values.isDirectory == true, values.isSymbolicLink != true,
              url.standardizedFileURL == url.resolvingSymlinksInPath().standardizedFileURL
        else { throw Failure.unsafeDirectory }
    }

    private static func assertRegularFile(_ url: URL) throws {
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true else { throw Failure.unsafeDirectory }
    }

    private static func assertOwnedContents(_ directory: URL) throws {
        let files = FileManager.default
        // Reject injected links, export paths, unfamiliar stores and unsupported sidecars.
        let allowed = Set(["session.json", "demo.store", "demo.store-shm", "demo.store-wal"])
        let supportDirectories = Set(["demo.store_SUPPORT", ".demo.store_SUPPORT"])
        for url in try files.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isSymbolicLinkKey]) {
            if supportDirectories.contains(url.lastPathComponent) {
                try assertSupportDirectory(url)
                continue
            }
            guard allowed.contains(url.lastPathComponent) else { throw Failure.unsafeDirectory }
            try assertRegularFile(url)
        }
    }

    private static func assertSupportDirectory(_ directory: URL) throws {
        try assertDirectory(directory)
        for url in try FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey]
        ) {
            let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            guard values.isSymbolicLink != true else { throw Failure.unsafeDirectory }
            if values.isDirectory == true { try assertSupportDirectory(url) }
            else { try assertRegularFile(url) }
        }
    }
}
#endif
