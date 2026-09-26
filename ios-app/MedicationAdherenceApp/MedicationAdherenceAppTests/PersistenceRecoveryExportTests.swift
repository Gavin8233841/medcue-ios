import Foundation
import XCTest
@testable import MedicationAdherenceApp

final class PersistenceRecoveryExportTests: XCTestCase {
    func testCopiesStoreAndCompanionsWithoutChangingOriginals() throws {
        let root = try makeFixtureDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = root.appendingPathComponent("default.store")
        let wal = URL(fileURLWithPath: store.path + "-wal")
        let mainBytes = Data("synthetic-main".utf8)
        let walBytes = Data("synthetic-wal".utf8)
        try mainBytes.write(to: store)
        try walBytes.write(to: wal)

        let exporter = PersistenceRecoveryExport(
            storeURL: store,
            exportRoot: root.appendingPathComponent("exports")
        )
        let copies = try exporter.makeSensitiveCopy()

        XCTAssertEqual(copies.map(\.lastPathComponent), ["default.store", "default.store-wal"])
        XCTAssertEqual(try Data(contentsOf: copies[0]), mainBytes)
        XCTAssertEqual(try Data(contentsOf: copies[1]), walBytes)
        XCTAssertEqual(try Data(contentsOf: store), mainBytes)
        XCTAssertEqual(try Data(contentsOf: wal), walBytes)
    }

    func testFailedCopyDoesNotChangeOriginalAndDoesNotPublishPartialCopy() throws {
        let root = try makeFixtureDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = root.appendingPathComponent("default.store")
        let bytes = Data("only-original".utf8)
        try bytes.write(to: store)
        let exportRoot = root.appendingPathComponent("exports")
        let exporter = PersistenceRecoveryExport(
            storeURL: store,
            exportRoot: exportRoot,
            copyBytes: { _, output in
                try Data("partial".utf8).write(to: output, options: .completeFileProtection)
                throw SyntheticFailure.copyInterrupted
            }
        )

        XCTAssertThrowsError(try exporter.makeSensitiveCopy())
        XCTAssertEqual(try Data(contentsOf: store), bytes)
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: exportRoot.path).isEmpty)
    }

    func testDiagnosticHasOnlyAllowlistedFields() throws {
        let root = try makeFixtureDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let exporter = PersistenceRecoveryExport(
            storeURL: root.appendingPathComponent("private-name.store"),
            exportRoot: root.appendingPathComponent("exports")
        )

        let output = try exporter.makeDiagnostic(stage: "retry", at: Date(timeIntervalSince1970: 0))
        let report = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: output)) as? [String: String])
        XCTAssertEqual(
            Set(report.keys),
            Set(["appVersion", "build", "systemVersion", "failureStage", "errorCategory", "generatedAt"])
        )
        XCTAssertEqual(report["failureStage"], "retryStoreOpen")
        XCTAssertEqual(report["errorCategory"], "persistentStoreOpenFailure")
        XCTAssertFalse(String(data: try Data(contentsOf: output), encoding: .utf8)?.contains("private-name") ?? true)
    }

    func testDiagnosticExportFailureDoesNotTouchOriginal() throws {
        let root = try makeFixtureDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = root.appendingPathComponent("default.store")
        let bytes = Data("synthetic-medication".utf8)
        try bytes.write(to: store)
        let blockedRoot = root.appendingPathComponent("not-a-directory")
        try Data("blocked".utf8).write(to: blockedRoot)
        let exporter = PersistenceRecoveryExport(storeURL: store, exportRoot: blockedRoot)

        XCTAssertThrowsError(try exporter.makeDiagnostic(stage: "initial"))
        XCTAssertEqual(try Data(contentsOf: store), bytes)
    }

    private func makeFixtureDirectory() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("medcue-recovery-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        return root
    }
}

private enum SyntheticFailure: Error {
    case copyInterrupted
}
