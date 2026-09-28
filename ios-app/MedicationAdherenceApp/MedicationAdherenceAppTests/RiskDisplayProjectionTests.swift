import Foundation
import MedicationAdherenceCore
import Testing
@testable import MedicationAdherenceApp

struct RiskDisplayProjectionTests {
    @Test
    func projectionDeduplicatesActiveCardsAndKeepsHigherReviewPriority() {
        let medication = StoredMedication(
            displayName: "测试药品",
            kind: .prescription,
            inputSource: .manual
        )
        let lowerPriority = riskCard(
            id: "lower",
            medicationID: medication.id,
            kind: .drugClassContext,
            displayPriority: 20,
            sourceExcerpt: "同一来源",
            requiresProfessionalReview: false
        )
        let reviewCard = riskCard(
            id: "review",
            medicationID: medication.id,
            kind: .drugClassContext,
            displayPriority: 30,
            sourceExcerpt: "同一来源",
            requiresProfessionalReview: true
        )

        let projection = RiskDisplayProjection(
            riskCards: [lowerPriority, reviewCard],
            medications: [medication]
        )

        #expect(projection.activeCards.map(\.id) == ["review"])
        #expect(
            projection.cardsByGroup[.drugInteraction]?.map(\.id)
                == ["review"]
        )
        #expect(projection.medicationName(for: reviewCard) == "测试药品")
    }

    @Test
    func semanticSignatureKeepsDistinctContentSeparated() {
        let medication = StoredMedication(
            displayName: "测试药品",
            kind: .prescription,
            inputSource: .manual
        )
        let first = riskCard(
            id: "spaced",
            medicationID: medication.id,
            kind: .labelRisk,
            displayPriority: 10,
            sourceExcerpt: "同一来源",
            title: "警 示",
            requiresProfessionalReview: false
        )
        let second = riskCard(
            id: "joined",
            medicationID: medication.id,
            kind: .labelRisk,
            displayPriority: 20,
            sourceExcerpt: "同一来源",
            title: "警示",
            requiresProfessionalReview: false
        )

        let projection = RiskDisplayProjection(
            riskCards: [second, first],
            medications: [medication]
        )

        #expect(projection.activeCards.map(\.id) == ["spaced", "joined"])
    }

    @Test
    func projectionDeduplicatesMixedLegacyAndSemanticSignatures() {
        let medication = StoredMedication(
            displayName: "测试药品", kind: .prescription, inputSource: .manual
        )
        let semantic = riskCard(
            id: "semantic", medicationID: medication.id, kind: .labelRisk,
            displayPriority: 10, sourceExcerpt: "同一来源", requiresProfessionalReview: false
        )
        let legacy = riskCard(
            id: "legacy", medicationID: medication.id, kind: .labelRisk,
            displayPriority: 30, sourceExcerpt: "同一来源", requiresProfessionalReview: true
        )
        legacy.detectionSignature = "\(medication.id.uuidString)|\(legacy.kindRaw.lowercased())|风险标题|风险内容|同一来源"

        let projection = RiskDisplayProjection(
            riskCards: [semantic, legacy], medications: [medication]
        )
        #expect(projection.activeCards.map(\.id) == ["legacy"])
    }

    @Test
    func projectionKeepsDistinctProvenanceAndUnreadStateVisible() {
        let medication = StoredMedication(
            displayName: "测试药品", kind: .prescription, inputSource: .manual
        )
        let read = riskCard(
            id: "read", medicationID: medication.id, kind: .labelRisk,
            displayPriority: 10, sourceExcerpt: "同一来源", requiresProfessionalReview: false
        )
        read.readAt = Date(timeIntervalSince1970: 1_800_000_000)
        let unread = riskCard(
            id: "unread", medicationID: medication.id, kind: .labelRisk,
            displayPriority: 20, sourceExcerpt: "同一来源", requiresProfessionalReview: false
        )
        let otherSource = riskCard(
            id: "other-source", medicationID: medication.id, kind: .labelRisk,
            displayPriority: 30, sourceExcerpt: "同一来源", sourceTitle: "另一份说明书",
            requiresProfessionalReview: false
        )

        let projection = RiskDisplayProjection(
            riskCards: [otherSource, unread, read], medications: [medication]
        )
        #expect(projection.activeCards.map(\.id) == ["read", "unread", "other-source"])
    }

    @Test
    func projectionKeepsCardsWithDifferentDetectionSignatures() {
        let medication = StoredMedication(
            displayName: "测试药品",
            kind: .prescription,
            inputSource: .manual
        )
        let firstRisk = riskCard(
            id: "first-risk",
            medicationID: medication.id,
            kind: .foodReview,
            displayPriority: 10,
            sourceExcerpt: "同一说明书片段",
            detectionSignature: "food-review",
            requiresProfessionalReview: false
        )
        let secondRisk = riskCard(
            id: "second-risk",
            medicationID: medication.id,
            kind: .healthConditionReview,
            displayPriority: 20,
            sourceExcerpt: "同一说明书片段",
            detectionSignature: "condition-review",
            requiresProfessionalReview: false
        )

        let projection = RiskDisplayProjection(
            riskCards: [secondRisk, firstRisk],
            medications: [medication]
        )

        #expect(projection.activeCards.map(\.id) == ["first-risk", "second-risk"])
    }

    @Test
    func projectionKeepsDifferentRiskContentWhenDetectionSignatureIsMissing() {
        let medication = StoredMedication(
            displayName: "测试药品",
            kind: .prescription,
            inputSource: .manual
        )
        let foodRisk = riskCard(
            id: "food-risk",
            medicationID: medication.id,
            kind: .foodReview,
            displayPriority: 10,
            sourceExcerpt: "同一说明书片段",
            title: "饮食注意",
            message: "服药期间需要核对饮食。",
            requiresProfessionalReview: false
        )
        let conditionRisk = riskCard(
            id: "condition-risk",
            medicationID: medication.id,
            kind: .healthConditionReview,
            displayPriority: 20,
            sourceExcerpt: "同一说明书片段",
            title: "病症注意",
            message: "出现特定症状时需要复核。",
            requiresProfessionalReview: false
        )
        foodRisk.detectionSignature = ""
        conditionRisk.detectionSignature = ""

        let projection = RiskDisplayProjection(
            riskCards: [conditionRisk, foodRisk],
            medications: [medication]
        )

        #expect(projection.activeCards.map(\.id) == ["food-risk", "condition-risk"])
    }

    @Test
    func projectionSeparatesArchivedCardsAndRefreshIDTracksMutations() {
        let medication = StoredMedication(
            displayName: "测试药品",
            kind: .overTheCounter,
            inputSource: .manual
        )
        let active = riskCard(
            id: "active",
            medicationID: medication.id,
            kind: .foodReview,
            displayPriority: 10,
            sourceExcerpt: "饮食",
            requiresProfessionalReview: false
        )
        let archived = riskCard(
            id: "archived",
            medicationID: medication.id,
            kind: .healthConditionReview,
            displayPriority: 5,
            sourceExcerpt: "病症",
            requiresProfessionalReview: true,
            archivedAt: Date(timeIntervalSince1970: 100)
        )
        let firstRefreshID = RiskDisplayProjection.refreshID(
            riskCards: [active, archived],
            medications: [medication]
        )

        let projection = RiskDisplayProjection(
            riskCards: [active, archived],
            medications: [medication]
        )
        active.displayPriority = 1
        let secondRefreshID = RiskDisplayProjection.refreshID(
            riskCards: [active, archived],
            medications: [medication]
        )

        #expect(projection.activeCards.map(\.id) == ["active"])
        #expect(projection.archivedCards.map(\.id) == ["archived"])
        #expect(
            projection.cardsByGroup[.foodAndLifestyleInteraction]?.map(\.id)
                == ["active"]
        )
        #expect(firstRefreshID != secondRefreshID)
    }

    private func riskCard(
        id: String,
        medicationID: UUID,
        kind: RiskAssessmentCardKind,
        displayPriority: Int,
        sourceExcerpt: String,
        sourceTitle: String = "说明书",
        detectionSignature: String = "",
        title: String = "风险标题",
        message: String = "风险内容",
        requiresProfessionalReview: Bool,
        archivedAt: Date? = nil
    ) -> StoredRiskCard {
        StoredRiskCard(
            id: id,
            medicationID: medicationID,
            kindRaw: kind.rawValue,
            displayPriority: displayPriority,
            title: title,
            message: message,
            sourceTitle: sourceTitle,
            sourceExcerpt: sourceExcerpt,
            detectionSignature: detectionSignature,
            requiresProfessionalReview: requiresProfessionalReview,
            safetyNote: RiskAssessmentEngine.defaultSafetyNote,
            archivedAt: archivedAt
        )
    }
}
