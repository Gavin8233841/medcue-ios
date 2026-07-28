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

        do {
            let report = try audit()
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
