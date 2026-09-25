import Foundation
import Testing
@testable import MedicationAdherenceApp

@Suite("VisitSummaryPDFLifecycle")
struct VisitSummaryPDFLifecycleTests {
    enum InjectedFailure: Error { case expected }
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

        let sameNamedRoot = fileManager.temporaryDirectory
            .appendingPathComponent("another-location-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent(rootURL.lastPathComponent, isDirectory: true)
        try fileManager.createDirectory(at: sameNamedRoot, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: sameNamedRoot.deletingLastPathComponent()) }
        let sameNamedFile = sameNamedRoot.appendingPathComponent(lifecycle.makeUniqueFilename())
        try Data("Outside".utf8).write(to: sameNamedFile)
        #expect(!lifecycle.remove(sameNamedFile))
        #expect(fileManager.fileExists(atPath: sameNamedFile.path))
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
        let expiredURL = rootURL.appendingPathComponent(lifecycle.makeUniqueFilename())
        try Data("Expired".utf8).write(to: expiredURL)
        let expiredDate = now.addingTimeInterval(-7200)
        try fileManager.setAttributes(
            [.creationDate: expiredDate, .modificationDate: expiredDate],
            ofItemAtPath: expiredURL.path
        )

        // Create a recent file (30 minutes old)
        let recentURL = rootURL.appendingPathComponent(lifecycle.makeUniqueFilename())
        try Data("Recent".utf8).write(to: recentURL)
        let recentDate = now.addingTimeInterval(-1800)
        try fileManager.setAttributes(
            [.creationDate: recentDate, .modificationDate: recentDate],
            ofItemAtPath: recentURL.path
        )

        // Create a non-PDF file that should be preserved
        let otherURL = rootURL.appendingPathComponent("other.txt")
        try Data("Other".utf8).write(to: otherURL)
        let unrelatedPDF = rootURL.appendingPathComponent("unrelated.pdf")
        try Data("Unrelated".utf8).write(to: unrelatedPDF)

        let removedCount = lifecycle.sweepExpiredFiles()

        #expect(removedCount == 1)
        #expect(!fileManager.fileExists(atPath: expiredURL.path))
        #expect(fileManager.fileExists(atPath: recentURL.path))
        #expect(fileManager.fileExists(atPath: otherURL.path))
        #expect(fileManager.fileExists(atPath: unrelatedPDF.path))
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
        let boundaryURL = rootURL.appendingPathComponent(lifecycle.makeUniqueFilename())
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

        do {
            _ = try await VisitSummaryPDFExporter.export(
                payload: payload,
                lifecycle: lifecycle,
                afterPublication: { _ in throw CancellationError() }
            )
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

        let testData = Data("Test".utf8)
        let targetURL = rootURL.appendingPathComponent(lifecycle.makeUniqueFilename())

        do {
            _ = try lifecycle.publish(data: testData, to: targetURL, writeData: { _, url in
                try Data("partial".utf8).write(to: url)
                throw InjectedFailure.expected
            })
            #expect(Bool(false), "Expected injected write failure")
        } catch InjectedFailure.expected {
            // The partial artifact must be removed by publish.
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

        do {
            _ = try lifecycle.publish(data: testData, to: targetURL, inspectProtection: { _ in
                throw InjectedFailure.expected
            })
            #expect(Bool(false), "Expected injected inspection failure")
        } catch InjectedFailure.expected {
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

        var leases = VisitSummaryPDFLeaseStore()
        let token = leases.beginUse(publishedURL)
        leases.requestRemoval(publishedURL, lifecycle: lifecycle)
        #expect(fileManager.fileExists(atPath: publishedURL.path))
        leases.finishUse(token, lifecycle: lifecycle)
        #expect(!fileManager.fileExists(atPath: publishedURL.path))
    }

    @Test("Share ownership keeps the PDF until the completion callback releases it")
    func testShareOwnership() throws {
        let (lifecycle, rootURL) = try makeTestLifecycle()
        defer { cleanup(rootURL) }
        try lifecycle.ensureRootDirectory()
        let url = rootURL.appendingPathComponent(lifecycle.makeUniqueFilename())
        try lifecycle.publish(data: Data("PDF".utf8), to: url)
        var leases = VisitSummaryPDFLeaseStore()
        let token = leases.beginUse(url)
        leases.requestRemoval(url, lifecycle: lifecycle)
        #expect(fileManager.fileExists(atPath: url.path))
        leases.finishUse(token, lifecycle: lifecycle)
        leases.finishUse(token, lifecycle: lifecycle)
        #expect(!fileManager.fileExists(atPath: url.path))
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

        var leases = VisitSummaryPDFLeaseStore()
        let oldConsumer = leases.beginUse(published1)
        leases.requestRemoval(published1, lifecycle: lifecycle)

        let data2 = Data("Second PDF".utf8)
        let url2 = rootURL.appendingPathComponent(lifecycle.makeUniqueFilename())
        let published2 = try lifecycle.publish(data: data2, to: url2)

        // Verify old is gone and new exists
        #expect(fileManager.fileExists(atPath: published1.path))
        #expect(fileManager.fileExists(atPath: published2.path))
        leases.finishUse(oldConsumer, lifecycle: lifecycle)
        #expect(!fileManager.fileExists(atPath: published1.path))

        // Clean up second file
        lifecycle.remove(published2)
    }
}
