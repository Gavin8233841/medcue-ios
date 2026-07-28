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
            sourceTitle: "说明书",
            sourceExcerpt: sourceExcerpt,
            detectionSignature: detectionSignature,
            requiresProfessionalReview: requiresProfessionalReview,
            safetyNote: RiskAssessmentEngine.defaultSafetyNote,
            archivedAt: archivedAt
        )
    }
}
