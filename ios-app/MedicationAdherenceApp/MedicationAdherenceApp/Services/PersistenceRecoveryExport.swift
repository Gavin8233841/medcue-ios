import CryptoKit
import Foundation
import UIKit

enum PersistenceRecoveryExportError: Error {
    case originalMissing
    case unsafeOriginal
    case protectionUnavailable
    case copyChanged
}

/// Only handles files owned by this app. It never opens the original for writing.
struct PersistenceRecoveryExport {
    let storeURL: URL
    let exportRoot: URL
    var copyBytes: ((URL, URL) throws -> Void)?

    static func production() -> Self {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return Self(
            storeURL: MedicationAdherenceModelContainer.defaultStoreURL,
            exportRoot: support.appendingPathComponent("medcue-store-recovery", isDirectory: true)
        )
    }

    /// The fixed-key report deliberately never serializes a framework error.
    func makeDiagnostic(stage: String, at date: Date = Date()) throws -> URL {
        let directory = try makeProtectedDirectory()
        let output = directory.appendingPathComponent("diagnostic.json")
        let bundle = Bundle.main
        let system = ProcessInfo.processInfo.operatingSystemVersion
        let report: [String: String] = [
            "appVersion": bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown",
            "build": bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown",
            "systemVersion": "\(system.majorVersion).\(system.minorVersion).\(system.patchVersion)",
            "failureStage": stage == "retry" ? "retryStoreOpen" : "initialStoreOpen",
            "errorCategory": "persistentStoreOpenFailure",
            "generatedAt": ISO8601DateFormatter().string(from: date)
        ]
        do {
            let data = try JSONSerialization.data(withJSONObject: report, options: [.sortedKeys])
            try data.write(to: output, options: [.atomic, .completeFileProtection])
            try verifyProtection(of: output)
            return output
        } catch {
            try? FileManager.default.removeItem(at: directory)
            throw error
        }
    }

    /// A byte copy is evidence for later manual analysis, not a tested restore path.
    func makeSensitiveCopy() throws -> [URL] {
        let manager = FileManager.default
        let originals = ["", "-wal", "-shm", "-journal"]
            .map { URL(fileURLWithPath: storeURL.path + $0) }
            .filter { manager.fileExists(atPath: $0.path) }
        guard originals.first == storeURL else {
            throw PersistenceRecoveryExportError.originalMissing
        }
        for original in originals {
            let values = try original.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            guard values.isRegularFile == true, values.isSymbolicLink != true else {
                throw PersistenceRecoveryExportError.unsafeOriginal
            }
        }

        let directory = try makeProtectedDirectory()
        do {
            var outputs: [URL] = []
            var sourceSignatures: [(url: URL, count: Int, hash: SHA256.Digest)] = []
            for original in originals {
                let output = directory.appendingPathComponent(original.lastPathComponent)
                let before = try digest(original)
                sourceSignatures.append((original, before.0, before.1))
                if let copyBytes {
                    try copyBytes(original, output)
                } else {
                    try Self.copyReadOnly(from: original, to: output)
                }
                try verifyProtection(of: output)
                let after = try digest(original)
                let copied = try digest(output)
                guard before == after && before == copied else {
                    throw PersistenceRecoveryExportError.copyChanged
                }
                outputs.append(output)
            }
            let finalOriginals = ["", "-wal", "-shm", "-journal"]
                .map { URL(fileURLWithPath: storeURL.path + $0) }
                .filter { manager.fileExists(atPath: $0.path) }
            guard finalOriginals == originals else {
                throw PersistenceRecoveryExportError.copyChanged
            }
            for signature in sourceSignatures {
                let final = try digest(signature.url)
                guard final.0 == signature.count && final.1 == signature.hash else {
                    throw PersistenceRecoveryExportError.copyChanged
                }
            }
            return outputs
        } catch {
            // This directory has a fresh opaque name and contains only files
            // created by this operation; the original store is never touched.
            try? manager.removeItem(at: directory)
            throw error
        }
    }

    private func makeProtectedDirectory() throws -> URL {
        let manager = FileManager.default
        if manager.fileExists(atPath: exportRoot.path) {
            let values = try exportRoot.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            guard values.isDirectory == true, values.isSymbolicLink != true else {
                throw PersistenceRecoveryExportError.protectionUnavailable
            }
        }
        try manager.createDirectory(
            at: exportRoot,
            withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.complete]
        )
        try manager.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: exportRoot.path)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var root = exportRoot
        try root.setResourceValues(values)
        try verifyProtection(of: exportRoot)

        let directory = exportRoot.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try manager.createDirectory(
            at: directory,
            withIntermediateDirectories: false,
            attributes: [.protectionKey: FileProtectionType.complete]
        )
        try verifyProtection(of: directory)
        return directory
    }

    private func verifyProtection(of url: URL) throws {
        #if !targetEnvironment(simulator)
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        guard attributes[.protectionKey] as? FileProtectionType == .complete else {
            throw PersistenceRecoveryExportError.protectionUnavailable
        }
        #endif
    }

    private func digest(_ url: URL) throws -> (Int, SHA256.Digest) {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hash = SHA256()
        var count = 0
        while let chunk = try handle.read(upToCount: 64 * 1024), !chunk.isEmpty {
            count += chunk.count
            hash.update(data: chunk)
        }
        return (count, hash.finalize())
    }

    private static func copyReadOnly(from original: URL, to output: URL) throws {
        try Data().write(to: output, options: .completeFileProtection)
        let source = try FileHandle(forReadingFrom: original)
        defer { try? source.close() }
        let destination = try FileHandle(forWritingTo: output)
        defer { try? destination.close() }
        while let chunk = try source.read(upToCount: 64 * 1024), !chunk.isEmpty {
            try destination.write(contentsOf: chunk)
        }
        try destination.synchronize()
    }
}
