import Foundation
import Testing
@testable import MedicationAdherenceApp

struct LocalMedicalModelIntegrityTests {
    private let verifiedBytes = Data("verified model bytes".utf8)
    private let verifiedSHA256 = "03cfa25d83f5eaa1faac98ed6ceaaf0e7afe3c273a1e1502c2714ebe10b8263e"

    @Test
    func installsOnlyAnExactChecksumMatchAndExcludesItFromBackup() throws {
        let fixture = try makeFixture(expectedSHA256: verifiedSHA256)
        try verifiedBytes.write(to: fixture.downloadURL, options: .atomic)

        let installedURL = try fixture.manager.installDownloadedModel(from: fixture.downloadURL)
        let installedBytes = try Data(contentsOf: installedURL)
        let resourceValues = try installedURL.resourceValues(forKeys: [.isExcludedFromBackupKey])

        #expect(installedBytes == verifiedBytes)
        #expect(resourceValues.isExcludedFromBackup == true)
        #expect(fixture.manager.installationStatus() == .installed)
    }

    @Test
    func checksumMismatchCannotReplaceAnInstalledModel() throws {
        let fixture = try makeFixture(expectedSHA256: verifiedSHA256)
        try verifiedBytes.write(to: fixture.downloadURL, options: .atomic)
        let installedURL = try fixture.manager.installDownloadedModel(from: fixture.downloadURL)

        let replacementURL = try makeDownloadURL(in: fixture.rootURL)
        let differentBytesWithSameLength = Data("untrusted model data".utf8)
        #expect(differentBytesWithSameLength.count == verifiedBytes.count)
        try differentBytesWithSameLength.write(to: replacementURL, options: .atomic)

        #expect(throws: LocalAIModelValidationError.checksumMismatch) {
            try fixture.manager.installDownloadedModel(from: replacementURL)
        }
        #expect(try Data(contentsOf: installedURL) == verifiedBytes)
    }

    @Test
    func exactByteCountIsCheckedBeforeInstallation() throws {
        let fixture = try makeFixture(expectedSHA256: verifiedSHA256)
        try Data("short".utf8).write(to: fixture.downloadURL, options: .atomic)

        #expect(throws: LocalAIModelValidationError.unexpectedByteCount(expected: 20, actual: 5)) {
            try fixture.manager.installDownloadedModel(from: fixture.downloadURL)
        }
        #expect(!FileManager.default.fileExists(atPath: try fixture.manager.modelURL().path))
    }

    private func makeFixture(expectedSHA256: String) throws -> (
        manager: LocalAIModelManager,
        rootURL: URL,
        downloadURL: URL
    ) {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("MedCue-ModelIntegrityTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        let downloadURL = try makeDownloadURL(in: rootURL)
        let manifest = LocalAIModelManifest(
            id: "integrity-test",
            displayName: "Integrity Test Model",
            fileName: "fixture.gguf",
            format: "gguf",
            estimatedSizeMB: 1,
            recommendedFreeSpaceMB: 1,
            runtime: "test",
            license: "test-only",
            downloadURL: URL(string: "https://example.invalid/fixture.gguf")!,
            subdirectoryName: "Fixture",
            minimumByteCount: 1,
            maximumByteCount: 100,
            exactByteCount: 20,
            expectedSHA256: expectedSHA256
        )
        return (
            LocalAIModelManager(manifest: manifest, applicationSupportOverrideURL: rootURL),
            rootURL,
            downloadURL
        )
    }

    private func makeDownloadURL(in rootURL: URL) throws -> URL {
        let directoryURL = rootURL
            .appendingPathComponent("Downloads-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        return directoryURL.appendingPathComponent("fixture.gguf")
    }
}
