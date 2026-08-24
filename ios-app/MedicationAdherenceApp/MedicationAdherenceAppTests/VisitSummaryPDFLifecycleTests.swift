import Foundation
import Testing
@testable import MedicationAdherenceApp

@Suite("VisitSummaryPDFLifecycle")
struct VisitSummaryPDFLifecycleTests {
    let fileManager = FileManager.default

    func makeTestLifecycle(
        expiryInterval: TimeInterval = 3600,
        currentTime: Date = Date()
    ) throws -> (lifecycle: VisitSummaryPDFLifecycle, rootURL: URL) {
        let testRoot = fileManager.temporaryDirectory
            .appendingPathComponent("test-pdf-lifecycle-\(UUID().uuidString)", isDirectory: true)

        var fixedTime = currentTime
        let lifecycle = VisitSummaryPDFLifecycle(
            rootDirectory: testRoot,
            expiryInterval: expiryInterval,
            fileManager: fileManager,
            clock: { fixedTime }
        )

        return (lifecycle, testRoot)
    }

    func cleanup(_ url: URL) {
        try? fileManager.removeItem(at: url)
    }

    @Test("Creates root directory with file protection")
    func testEnsureRootDirectory() throws {
        let (lifecycle, rootURL) = try makeTestLifecycle()
        defer { cleanup(rootURL) }

        try lifecycle.ensureRootDirectory()

        var isDirectory: ObjCBool = false
        #expect(fileManager.fileExists(atPath: rootURL.path, isDirectory: &isDirectory))
        #expect(isDirectory.boolValue)

        let attributes = try fileManager.attributesOfItem(atPath: rootURL.path)
        #expect(attributes[.protectionKey] as? FileProtectionType == .complete)
    }

    @Test("Generates unique opaque filenames")
    func testUniqueFilenames() throws {
        let (lifecycle, rootURL) = try makeTestLifecycle()
        defer { cleanup(rootURL) }

        let name1 = lifecycle.makeUniqueFilename()
        let name2 = lifecycle.makeUniqueFilename()

        #expect(name1.hasSuffix(".pdf"))
        #expect(name2.hasSuffix(".pdf"))
        #expect(name1 != name2)
        #expect(!name1.contains("复诊") && !name1.contains("medication"))
    }

    @Test("Publishes PDF with complete file protection")
    func testPublishWithProtection() throws {
        let (lifecycle, rootURL) = try makeTestLifecycle()
        defer { cleanup(rootURL) }

        try lifecycle.ensureRootDirectory()

        let testData = Data("Test PDF content".utf8)
        let targetURL = rootURL.appendingPathComponent(lifecycle.makeUniqueFilename())

        let publishedURL = try lifecycle.publish(data: testData, to: targetURL)

        #expect(fileManager.fileExists(atPath: publishedURL.path))
        #expect(try Data(contentsOf: publishedURL) == testData)

        let attributes = try fileManager.attributesOfItem(atPath: publishedURL.path)
        #expect(attributes[.protectionKey] as? FileProtectionType == .complete)
    }

    @Test("Removes owned report file")
    func testRemoveOwnedFile() throws {
        let (lifecycle, rootURL) = try makeTestLifecycle()
        defer { cleanup(rootURL) }

        try lifecycle.ensureRootDirectory()

        let testData = Data("Test PDF".utf8)
        let targetURL = rootURL.appendingPathComponent(lifecycle.makeUniqueFilename())
        let publishedURL = try lifecycle.publish(data: testData, to: targetURL)

        #expect(fileManager.fileExists(atPath: publishedURL.path))

        let removed = lifecycle.remove(publishedURL)

        #expect(removed)
        #expect(!fileManager.fileExists(atPath: publishedURL.path))
    }

    @Test("Refuses to remove files outside owned root")
    func testRefusesRemovalOutsideRoot() throws {
        let (lifecycle, rootURL) = try makeTestLifecycle()
        defer { cleanup(rootURL) }

        let outsideURL = fileManager.temporaryDirectory
            .appendingPathComponent("unrelated-file.pdf")
        try Data("Outside".utf8).write(to: outsideURL)
        defer { try? fileManager.removeItem(at: outsideURL) }

        let removed = lifecycle.remove(outsideURL)

        #expect(!removed)
        #expect(fileManager.fileExists(atPath: outsideURL.path))
    }

    @Test("Sweeps expired files and preserves recent files")
    func testSweepExpiredFiles() throws {
        let now = Date()
        let (lifecycle, rootURL) = try makeTestLifecycle(
            expiryInterval: 3600,
            currentTime: now
        )
        defer { cleanup(rootURL) }

        try lifecycle.ensureRootDirectory()

        // Create an expired file (2 hours old)
        let expiredURL = rootURL.appendingPathComponent("expired.pdf")
        try Data("Expired".utf8).write(to: expiredURL)
        let expiredDate = now.addingTimeInterval(-7200)
        try fileManager.setAttributes(
            [.creationDate: expiredDate, .modificationDate: expiredDate],
            ofItemAtPath: expiredURL.path
        )

        // Create a recent file (30 minutes old)
        let recentURL = rootURL.appendingPathComponent("recent.pdf")
        try Data("Recent".utf8).write(to: recentURL)
        let recentDate = now.addingTimeInterval(-1800)
        try fileManager.setAttributes(
            [.creationDate: recentDate, .modificationDate: recentDate],
            ofItemAtPath: recentURL.path
        )

        // Create a non-PDF file that should be preserved
        let otherURL = rootURL.appendingPathComponent("other.txt")
        try Data("Other".utf8).write(to: otherURL)

        let removedCount = lifecycle.sweepExpiredFiles()

        #expect(removedCount == 1)
        #expect(!fileManager.fileExists(atPath: expiredURL.path))
        #expect(fileManager.fileExists(atPath: recentURL.path))
        #expect(fileManager.fileExists(atPath: otherURL.path))
    }

    @Test("Sweep handles boundary case: exactly at expiry threshold")
    func testSweepExactBoundary() throws {
        let now = Date()
        let (lifecycle, rootURL) = try makeTestLifecycle(
            expiryInterval: 3600,
            currentTime: now
        )
        defer { cleanup(rootURL) }

        try lifecycle.ensureRootDirectory()

        // Create a file exactly at the 1-hour boundary
        let boundaryURL = rootURL.appendingPathComponent("boundary.pdf")
        try Data("Boundary".utf8).write(to: boundaryURL)
        let boundaryDate = now.addingTimeInterval(-3600)
        try fileManager.setAttributes(
            [.creationDate: boundaryDate, .modificationDate: boundaryDate],
            ofItemAtPath: boundaryURL.path
        )

        let removedCount = lifecycle.sweepExpiredFiles()

        // At or beyond the boundary should be removed
        #expect(removedCount == 1)
        #expect(!fileManager.fileExists(atPath: boundaryURL.path))
    }

    @Test("Sweep returns zero when directory is empty")
    func testSweepEmptyDirectory() throws {
        let (lifecycle, rootURL) = try makeTestLifecycle()
        defer { cleanup(rootURL) }

        try lifecycle.ensureRootDirectory()

        let removedCount = lifecycle.sweepExpiredFiles()

        #expect(removedCount == 0)
    }

    @Test("Sweep returns zero when directory does not exist")
    func testSweepNonexistentDirectory() throws {
        let (lifecycle, rootURL) = try makeTestLifecycle()
        defer { cleanup(rootURL) }

        let removedCount = lifecycle.sweepExpiredFiles()

        #expect(removedCount == 0)
    }

    @Test("Cancellation cleanup removes artifact")
    func testCancellationCleanup() throws {
        let (lifecycle, rootURL) = try makeTestLifecycle()
        defer { cleanup(rootURL) }

        try lifecycle.ensureRootDirectory()

        let testData = Data("Cancelled PDF".utf8)
        let targetURL = rootURL.appendingPathComponent(lifecycle.makeUniqueFilename())
        let publishedURL = try lifecycle.publish(data: testData, to: targetURL)

        #expect(fileManager.fileExists(atPath: publishedURL.path))

        // Simulate cancellation cleanup
        lifecycle.remove(publishedURL)

        #expect(!fileManager.fileExists(atPath: publishedURL.path))
    }
}
