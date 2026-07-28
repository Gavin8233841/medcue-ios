import Foundation
import MedicationAdherenceCore
import SwiftData
import Testing
@testable import MedicationAdherenceApp

@Suite(.serialized)
struct RiskReviewCommandTests {
    @Test @MainActor
    func archiveCommitsReviewMetadataTogether() throws {
        let fixture = try RiskReviewFixture()
        let reviewedAt = Date(timeIntervalSinceReferenceDate: 1_000)

        let outcome = RiskReviewCommand(modelContext: fixture.context).perform(
            .archive(riskCardID: fixture.card.id, reviewedAt: reviewedAt)
        )

        #expect(outcome == .committed(riskCardID: fixture.card.id))
        let persisted = try #require(try fixture.verificationCard())
        #expect(persisted.reviewedAt == reviewedAt)
        #expect(persisted.archivedAt == reviewedAt)
        #expect(persisted.reviewNote == "用户已复核并归档。")
    }

    @Test @MainActor
    func reopenClearsTheSameReviewFieldsAsTheExistingFlow() throws {
        let fixture = try RiskReviewFixture()
        fixture.card.readAt = Date(timeIntervalSinceReferenceDate: 700)
        fixture.card.reviewedAt = Date(timeIntervalSinceReferenceDate: 800)
        fixture.card.archivedAt = Date(timeIntervalSinceReferenceDate: 800)
        fixture.card.resolvedAt = Date(timeIntervalSinceReferenceDate: 850)
        fixture.card.resolutionNote = "已解除"
        fixture.card.reviewNote = "已归档"
        try fixture.context.save()

        let outcome = RiskReviewCommand(modelContext: fixture.context).perform(
            .reopen(riskCardID: fixture.card.id)
        )

        #expect(outcome == .committed(riskCardID: fixture.card.id))
        let persisted = try #require(try fixture.verificationCard())
        #expect(persisted.archivedAt == nil)
        #expect(persisted.resolvedAt == nil)
        #expect(persisted.resolutionNote.isEmpty)
        #expect(persisted.reviewNote.isEmpty)
        #expect(persisted.readAt == nil)
        #expect(persisted.reviewedAt == Date(timeIntervalSinceReferenceDate: 800))
    }

    @Test @MainActor
    func saveFailureRestoresEveryMutatedReviewField() throws {
        let fixture = try RiskReviewFixture()
        fixture.card.readAt = Date(timeIntervalSinceReferenceDate: 700)
        fixture.card.resolvedAt = Date(timeIntervalSinceReferenceDate: 750)
        fixture.card.resolutionNote = "原解除说明"
        fixture.card.reviewedAt = Date(timeIntervalSinceReferenceDate: 800)
        fixture.card.archivedAt = Date(timeIntervalSinceReferenceDate: 800)
        fixture.card.reviewNote = "原复核说明"
        try fixture.context.save()

        let outcome = RiskReviewCommand(
            modelContext: fixture.context,
            saveOperation: { _ in throw SyntheticRiskReviewSaveError.unavailable }
        ).perform(.reopen(riskCardID: fixture.card.id))

        #expect(outcome == .saveFailed)
        #expect(fixture.card.readAt == Date(timeIntervalSinceReferenceDate: 700))
        #expect(fixture.card.resolvedAt == Date(timeIntervalSinceReferenceDate: 750))
        #expect(fixture.card.resolutionNote == "原解除说明")
        #expect(fixture.card.reviewedAt == Date(timeIntervalSinceReferenceDate: 800))
        #expect(fixture.card.archivedAt == Date(timeIntervalSinceReferenceDate: 800))
        #expect(fixture.card.reviewNote == "原复核说明")
        #expect(!fixture.context.hasChanges)
    }
}

private enum SyntheticRiskReviewSaveError: Error {
    case unavailable
}

@MainActor
private struct RiskReviewFixture {
    let container: ModelContainer
    let context: ModelContext
    let card: StoredRiskCard

    init() throws {
        container = try ModelContainer(
            for: StoredRiskCard.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        context = ModelContext(container)
        card = StoredRiskCard(
            id: "risk-review-test",
            medicationID: UUID(),
            kindRaw: RiskAssessmentCardKind.labelRisk.rawValue,
            displayPriority: 1,
            title: "测试提醒",
            message: "测试内容",
            requiresProfessionalReview: true,
            safetyNote: ""
        )
        context.insert(card)
        try context.save()
    }

    func verificationCard() throws -> StoredRiskCard? {
        let verificationContext = ModelContext(container)
        return try verificationContext.fetch(FetchDescriptor<StoredRiskCard>()).first
    }
}
