import Foundation

/// Manages the complete lifecycle of visit-summary PDF temporary files with
/// protection, bounded retention, and cleanup guarantees.
///
/// Every report is created in an app-owned temporary export area with opaque
/// unique filenames, protected with `NSFileProtectionComplete`, and removed
/// when no longer needed: after share completion/cancellation, screen reset,
/// replacement by a new export, generation failure, or cancellation.
///
/// A startup or pre-export sweep removes MedCue-owned report files older than
/// one hour, covering process termination before normal cleanup.
struct VisitSummaryPDFLifecycle: Sendable {
    let rootDirectory: URL
    let expiryInterval: TimeInterval
    let fileManager: FileManager
    let clock: @Sendable () -> Date

    /// Default production lifecycle using the app's temporary directory.
    static func production() -> VisitSummaryPDFLifecycle {
        let appTempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("medcue-visit-summaries", isDirectory: true)
        return VisitSummaryPDFLifecycle(
            rootDirectory: appTempRoot,
            expiryInterval: 3600, // 1 hour
            fileManager: .default,
            clock: { Date() }
        )
    }

    /// Create the export root directory if it does not exist.
    func ensureRootDirectory() throws {
        guard !fileManager.fileExists(atPath: rootDirectory.path) else {
            return
        }
        try fileManager.createDirectory(
            at: rootDirectory,
            withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.complete]
        )
    }

    /// Generate a unique opaque filename for a new report.
    func makeUniqueFilename() -> String {
        "\(UUID().uuidString).pdf"
    }

    /// Publish a completed PDF at the target URL with required file protection.
    ///
    /// - Parameter targetURL: The destination URL inside the root directory.
    /// - Parameter data: The PDF data to write atomically.
    /// - Throws: If the atomic write fails or if applying the protection fails.
    /// - Returns: The successfully protected target URL.
    func publish(data: Data, to targetURL: URL) throws -> URL {
        // Atomic write with NSFileProtectionComplete
        try data.write(
            to: targetURL,
            options: [.atomic, .completeFileProtection]
        )

        // Verify that the protection was applied
        let attributes = try fileManager.attributesOfItem(atPath: targetURL.path)
        guard let protection = attributes[.protectionKey] as? FileProtectionType,
              protection == .complete
        else {
            // Protection verification failed; remove the file and report failure
            try? fileManager.removeItem(at: targetURL)
            throw VisitSummaryPDFLifecycleError.protectionVerificationFailed
        }

        return targetURL
    }

    /// Remove a single owned report file.
    ///
    /// - Parameter url: The URL of the file to remove.
    /// - Returns: `true` if the file was removed or did not exist; `false` on error.
    @discardableResult
    func remove(_ url: URL) -> Bool {
        guard url.pathComponents.contains(rootDirectory.lastPathComponent) else {
            // Refuse to remove a file outside the owned root
            return false
        }
        guard fileManager.fileExists(atPath: url.path) else {
            return true
        }
        do {
            try fileManager.removeItem(at: url)
            return true
        } catch {
            return false
        }
    }

    /// Sweep the root directory and remove MedCue-owned report files older than
    /// the expiry interval.
    ///
    /// - Returns: The count of expired files removed.
    @discardableResult
    func sweepExpiredFiles() -> Int {
        let now = clock()
        let expiryThreshold = now.addingTimeInterval(-expiryInterval)

        guard let contents = try? fileManager.contentsOfDirectory(
            at: rootDirectory,
            includingPropertiesForKeys: [.creationDateKey, .contentModificationDateKey],
            options: .skipsHiddenFiles
        ) else {
            return 0
        }

        var removedCount = 0
        for url in contents {
            guard url.pathExtension == "pdf" else {
                continue
            }

            // Use the later of creation or modification date
            let attributes = try? fileManager.attributesOfItem(atPath: url.path)
            let creationDate = attributes?[.creationDate] as? Date
            let modificationDate = attributes?[.modificationDate] as? Date
            let referenceDate = [creationDate, modificationDate]
                .compactMap { $0 }
                .max() ?? .distantPast

            if referenceDate <= expiryThreshold {
                if remove(url) {
                    removedCount += 1
                }
            }
        }

        return removedCount
    }
}

enum VisitSummaryPDFLifecycleError: Error {
    case protectionVerificationFailed
    case atomicWriteFailed
}
