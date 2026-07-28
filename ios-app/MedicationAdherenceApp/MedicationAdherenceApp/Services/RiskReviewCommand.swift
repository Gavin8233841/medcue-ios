import Foundation
import SwiftData

enum RiskReviewAction: Equatable, Sendable {
    case archive(riskCardID: String, reviewedAt: Date)
    case reopen(riskCardID: String)

    var riskCardID: String {
        switch self {
        case let .archive(riskCardID, _), let .reopen(riskCardID):
            return riskCardID
        }
    }

    var operation: StaticString {
        switch self {
        case .archive:
            return "risk-resolution"
        case .reopen:
            return "risk-review"
        }
    }
}

enum RiskReviewRejection: Equatable {
    case riskCardNotFound
    case readFailed
}

enum RiskReviewCommandOutcome: Equatable {
    case committed(riskCardID: String)
    case rejected(RiskReviewRejection)
    case saveFailed
}

@MainActor
struct RiskReviewCommand {
    typealias SaveOperation = (ModelContext) throws -> Void

    private let modelContext: ModelContext
    private let saveOperation: SaveOperation

    init(
        modelContext: ModelContext,
        saveOperation: @escaping SaveOperation = { try $0.save() }
    ) {
        self.modelContext = modelContext
        self.saveOperation = saveOperation
    }

    func perform(_ action: RiskReviewAction) -> RiskReviewCommandOutcome {
        let riskCardID = action.riskCardID
        var descriptor = FetchDescriptor<StoredRiskCard>(
            predicate: #Predicate<StoredRiskCard> { card in
                card.id == riskCardID
            }
        )
        descriptor.fetchLimit = 1

        let card: StoredRiskCard
        do {
            guard let storedCard = try modelContext.fetch(descriptor).first else {
                return .rejected(.riskCardNotFound)
            }
            card = storedCard
        } catch {
            return .rejected(.readFailed)
        }

        let snapshot = RiskReviewMutationSnapshot(card)
        switch action {
        case let .archive(_, reviewedAt):
            card.reviewedAt = reviewedAt
            card.archivedAt = reviewedAt
            card.reviewNote = "用户已复核并归档。"
        case .reopen:
            card.archivedAt = nil
            card.resolvedAt = nil
            card.resolutionNote = ""
            card.reviewNote = ""
            card.readAt = nil
        }

        do {
            try saveOperation(modelContext)
            return .committed(riskCardID: card.id)
        } catch {
            snapshot.restore()
            modelContext.rollback()
            AppPersistenceCommitter.reportFailure(operation: action.operation)
            return .saveFailed
        }
    }
}

private struct RiskReviewMutationSnapshot {
    let card: StoredRiskCard
    let readAt: Date?
    let resolvedAt: Date?
    let resolutionNote: String
    let reviewedAt: Date?
    let archivedAt: Date?
    let reviewNote: String

    init(_ card: StoredRiskCard) {
        self.card = card
        readAt = card.readAt
        resolvedAt = card.resolvedAt
        resolutionNote = card.resolutionNote
        reviewedAt = card.reviewedAt
        archivedAt = card.archivedAt
        reviewNote = card.reviewNote
    }

    func restore() {
        card.readAt = readAt
        card.resolvedAt = resolvedAt
        card.resolutionNote = resolutionNote
        card.reviewedAt = reviewedAt
        card.archivedAt = archivedAt
        card.reviewNote = reviewNote
    }
}
