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
    let clock: @Sendable () -> Date
    private var fileManager: FileManager { .default }

    /// Default production lifecycle using the app's temporary directory.
    static func production() -> VisitSummaryPDFLifecycle {
        let appTempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("medcue-visit-summaries", isDirectory: true)
        return VisitSummaryPDFLifecycle(
            rootDirectory: appTempRoot,
            expiryInterval: 3600, // 1 hour
            clock: { Date() }
        )
    }

    /// Create the export root directory if it does not exist.
    func ensureRootDirectory() throws {
        if fileManager.fileExists(atPath: rootDirectory.path) {
            let values = try rootDirectory.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            guard values.isDirectory == true, values.isSymbolicLink != true else {
                throw VisitSummaryPDFLifecycleError.invalidRootDirectory
            }
        } else {
            try fileManager.createDirectory(
                at: rootDirectory,
                withIntermediateDirectories: true,
                attributes: [.protectionKey: FileProtectionType.complete]
            )
        }
        try fileManager.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: rootDirectory.path)
        #if !targetEnvironment(simulator)
        let attributes = try fileManager.attributesOfItem(atPath: rootDirectory.path)
        guard attributes[.protectionKey] as? FileProtectionType == .complete else {
            throw VisitSummaryPDFLifecycleError.protectionVerificationFailed
        }
        #endif
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
    func publish(
        data: Data,
        to targetURL: URL,
        writeData: ((Data, URL) throws -> Void)? = nil,
        inspectProtection: ((URL) throws -> Bool)? = nil
    ) throws -> URL {
        guard owns(targetURL) else {
            throw VisitSummaryPDFLifecycleError.unownedTarget
        }
        do {
            if let writeData {
                try writeData(data, targetURL)
            } else {
                try data.write(to: targetURL, options: [.atomic, .completeFileProtection])
            }
            let isProtected: Bool
            if let inspectProtection {
                isProtected = try inspectProtection(targetURL)
            } else {
                let attributes = try fileManager.attributesOfItem(atPath: targetURL.path)
                if let protection = attributes[.protectionKey] as? FileProtectionType {
                    isProtected = protection == .complete
                } else {
                    // Simulator does not expose the data-protection class. The
                    // write still requests complete protection; physical-device
                    // builds fail closed when the class cannot be verified.
                    #if targetEnvironment(simulator)
                    isProtected = true
                    #else
                    isProtected = false
                    #endif
                }
            }
            guard isProtected else {
                throw VisitSummaryPDFLifecycleError.protectionVerificationFailed
            }
            return targetURL
        } catch {
            // Every failure after creation removes the owned artifact.
            try? fileManager.removeItem(at: targetURL)
            throw error
        }
    }

    private func owns(_ url: URL) -> Bool {
        url.isFileURL
            && url.deletingLastPathComponent().standardizedFileURL == rootDirectory.standardizedFileURL
            && url.pathExtension == "pdf"
            && UUID(uuidString: url.deletingPathExtension().lastPathComponent) != nil
    }

    /// Remove a single owned report file.
    ///
    /// - Parameter url: The URL of the file to remove.
    /// - Returns: `true` if the file was removed or did not exist; `false` on error.
    @discardableResult
    func remove(_ url: URL) -> Bool {
        guard owns(url) else {
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
            guard owns(url) else {
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
    case invalidRootDirectory
    case unownedTarget
}

/// Defers deletion while a system preview or share controller owns the URL.
struct VisitSummaryPDFLeaseStore {
    private var active: [UUID: URL] = [:]
    private var pendingRemoval: Set<URL> = []

    mutating func beginUse(_ url: URL) -> UUID {
        let token = UUID()
        active[token] = url
        return token
    }

    mutating func requestRemoval(_ url: URL, lifecycle: VisitSummaryPDFLifecycle) {
        pendingRemoval.insert(url)
        flush(url, lifecycle: lifecycle)
    }

    mutating func finishUse(_ token: UUID, lifecycle: VisitSummaryPDFLifecycle) {
        guard let url = active.removeValue(forKey: token) else { return }
        flush(url, lifecycle: lifecycle)
    }

    private mutating func flush(_ url: URL, lifecycle: VisitSummaryPDFLifecycle) {
        guard pendingRemoval.contains(url), !active.values.contains(url) else { return }
        if lifecycle.remove(url) {
            pendingRemoval.remove(url)
        }
    }
}
