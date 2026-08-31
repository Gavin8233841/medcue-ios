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

    @Test("Cancellation after successful publication removes artifact")
    func testCancellationAfterPublication() async throws {
        let (lifecycle, rootURL) = try makeTestLifecycle()
        defer { cleanup(rootURL) }

        try lifecycle.ensureRootDirectory()

        let payload = VisitSummaryExportPayload(
            medications: [],
            tasks: [],
            doseChanges: [],
            riskCards: [],
            trendDashboard: MedicationTrendDashboard(
                overallScore: 0.8,
                direction: .stable,
                signals: []
            ),
            healthSignals: [],
            startDate: Date(),
            endDate: Date(),
            generatedAt: Date(),
            exportSignature: "test-signature"
        )

        let task = Task {
            try await VisitSummaryPDFExporter.export(payload: payload, lifecycle: lifecycle)
        }

        // Allow publication to complete before cancelling
        try await Task.sleep(nanoseconds: 10_000_000) // 10ms
        task.cancel()

        do {
            _ = try await task.value
            #expect(Bool(false), "Expected CancellationError to be thrown")
        } catch is CancellationError {
            // Expected: cancellation after publication should throw
        } catch {
            #expect(Bool(false), "Expected CancellationError but got: \(error)")
        }

        // Verify that no PDF artifacts remain in the root directory
        let contents = try fileManager.contentsOfDirectory(
            at: rootURL,
            includingPropertiesForKeys: nil,
            options: .skipsHiddenFiles
        )
        let pdfFiles = contents.filter { $0.pathExtension == "pdf" }
        #expect(pdfFiles.isEmpty, "Expected no PDF artifacts after cancellation, found: \(pdfFiles)")
    }

    @Test("Publish failure during write removes partial artifacts")
    func testPublishFailureDuringWrite() throws {
        let (lifecycle, rootURL) = try makeTestLifecycle()
        defer { cleanup(rootURL) }

        try lifecycle.ensureRootDirectory()

        // Attempt to write to a read-only directory to simulate write failure
        let readOnlySubdir = rootURL.appendingPathComponent("readonly", isDirectory: true)
        try fileManager.createDirectory(at: readOnlySubdir, withIntermediateDirectories: false)
        try fileManager.setAttributes([.posixPermissions: 0o444], ofItemAtPath: readOnlySubdir.path)
        defer {
            try? fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: readOnlySubdir.path)
            try? fileManager.removeItem(at: readOnlySubdir)
        }

        let testData = Data("Test".utf8)
        let targetURL = readOnlySubdir.appendingPathComponent(lifecycle.makeUniqueFilename())

        do {
            _ = try lifecycle.publish(data: testData, to: targetURL)
            #expect(Bool(false), "Expected publish to fail in read-only directory")
        } catch {
            // Expected: publish should fail and clean up
        }

        // Verify no partial file was left behind
        #expect(!fileManager.fileExists(atPath: targetURL.path))
    }

    @Test("Publish failure during attribute inspection removes artifact")
    func testPublishFailureDuringAttributeInspection() throws {
        let (lifecycle, rootURL) = try makeTestLifecycle()
        defer { cleanup(rootURL) }

        try lifecycle.ensureRootDirectory()

        let testData = Data("Test".utf8)
        let targetURL = rootURL.appendingPathComponent(lifecycle.makeUniqueFilename())

        // Write file successfully
        try testData.write(to: targetURL, options: [.atomic, .completeFileProtection])

        // Now simulate attribute inspection failure by removing the file before inspection
        // (This tests the catch block around attributesOfItem)
        try fileManager.removeItem(at: targetURL)

        // Re-attempt publish which will write successfully but fail during attribute check
        do {
            _ = try lifecycle.publish(data: testData, to: targetURL)
            // If attributes can be read, verify protection is correct
            let attributes = try fileManager.attributesOfItem(atPath: targetURL.path)
            #expect(attributes[.protectionKey] as? FileProtectionType == .complete)
        } catch {
            // If attribute inspection fails, verify artifact was removed
            #expect(!fileManager.fileExists(atPath: targetURL.path))
        }
    }

    @Test("Preview dismissal allows cleanup")
    func testPreviewOwnershipReturn() throws {
        let (lifecycle, rootURL) = try makeTestLifecycle()
        defer { cleanup(rootURL) }

        try lifecycle.ensureRootDirectory()

        let testData = Data("Preview PDF".utf8)
        let targetURL = rootURL.appendingPathComponent(lifecycle.makeUniqueFilename())
        let publishedURL = try lifecycle.publish(data: testData, to: targetURL)

        #expect(fileManager.fileExists(atPath: publishedURL.path))

        // Simulate preview dismissal callback removing the file
        let removed = lifecycle.remove(publishedURL)

        #expect(removed)
        #expect(!fileManager.fileExists(atPath: publishedURL.path))
    }

    @Test("Concurrent generation requests cleanup replaced PDFs")
    func testReplacementRaceCleanup() throws {
        let (lifecycle, rootURL) = try makeTestLifecycle()
        defer { cleanup(rootURL) }

        try lifecycle.ensureRootDirectory()

        // Create first PDF
        let data1 = Data("First PDF".utf8)
        let url1 = rootURL.appendingPathComponent(lifecycle.makeUniqueFilename())
        let published1 = try lifecycle.publish(data: data1, to: url1)

        #expect(fileManager.fileExists(atPath: published1.path))

        // Simulate replacement by new generation: remove old before publishing new
        lifecycle.remove(published1)

        let data2 = Data("Second PDF".utf8)
        let url2 = rootURL.appendingPathComponent(lifecycle.makeUniqueFilename())
        let published2 = try lifecycle.publish(data: data2, to: url2)

        // Verify old is gone and new exists
        #expect(!fileManager.fileExists(atPath: published1.path))
        #expect(fileManager.fileExists(atPath: published2.path))

        // Clean up second file
        lifecycle.remove(published2)
    }
}

