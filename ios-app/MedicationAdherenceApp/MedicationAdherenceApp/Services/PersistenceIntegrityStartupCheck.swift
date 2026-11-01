import Foundation
import OSLog
import SwiftData

enum PersistenceIntegrityStartupCheckOutcome: Equatable {
    case clean
    case issuesFound(totalCount: Int)
    case failed
    case alreadyRan
}

@MainActor
final class PersistenceIntegrityStartupCheck {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "MedicationAdherenceApp",
        category: "PersistenceIntegrity"
    )
    private var hasRun = false

    func runInBackground(modelContainer: ModelContainer) async -> PersistenceIntegrityStartupCheckOutcome {
        guard !hasRun else {
            return .alreadyRan
        }
        // Reserve this run before suspending so scene updates cannot duplicate it.
        hasRun = true
        let result = await Task.detached(priority: .utility) {
            // Create and use the context on this worker; never send main-context
            // models across executors. The audit reads committed data only.
            let context = ModelContext(modelContainer)
            context.autosaveEnabled = false
            return Result { try PersistenceIntegrityAuditor(modelContext: context).audit() }
        }.value
        return report(result: result) { message in
            Self.logger.notice("\(message, privacy: .public)")
        }
    }

    func run(modelContext: ModelContext) -> PersistenceIntegrityStartupCheckOutcome {
        run(
            audit: { try PersistenceIntegrityAuditor(modelContext: modelContext).audit() },
            log: { message in
                Self.logger.notice("\(message, privacy: .public)")
            }
        )
    }

    func run(
        audit: () throws -> PersistenceIntegrityReport,
        log: (String) -> Void
    ) -> PersistenceIntegrityStartupCheckOutcome {
        guard !hasRun else {
            return .alreadyRan
        }
        hasRun = true

        return report(result: Result { try audit() }, log: log)
    }

    private func report(
        result: Result<PersistenceIntegrityReport, Error>,
        log: (String) -> Void
    ) -> PersistenceIntegrityStartupCheckOutcome {
        do {
            let report = try result.get()
            guard !report.isClean else {
                log("persistence-integrity clean")
                return .clean
            }

            let counts = PersistenceIntegrityIssueKind.allCases
                .compactMap { kind -> String? in
                    let count = report.count(for: kind)
                    return count > 0 ? "\(kind.rawValue)=\(count)" : nil
                }
                .sorted()
                .joined(separator: " ")
            log("persistence-integrity issues total=\(report.issues.count) \(counts)")
            return .issuesFound(totalCount: report.issues.count)
        } catch {
            log("persistence-integrity audit-failed")
            return .failed
        }
    }
}
