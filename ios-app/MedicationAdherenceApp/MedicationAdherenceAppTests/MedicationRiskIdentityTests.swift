import Foundation
import MedicationAdherenceCore
import SwiftData
import Testing
@testable import MedicationAdherenceApp

@Suite(.serialized)
struct MedicationRiskIdentityTests {
    @Test
    func evidenceNormalizationDoesNotDependOnDeviceLocale() throws {
        let medicationID = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000020"))
        let signature = StoredRiskCard.makeSemanticDetectionSignature(
            id: "synthetic-risk",
            medicationID: medicationID,
            kindRaw: RiskAssessmentCardKind.labelRisk.rawValue,
            sourceKindRaw: StoredRiskSourceKind.drugLabel.rawValue,
            sourceTitle: "SOURCE",
            sourceExcerpt: "I"
        )
        #expect(signature.hasSuffix("6:source1:i"))
    }

    @Test @MainActor
    func externalRiskPresentationChangeKeepsReadStateButEvidenceChangeReopens() throws {
        let container = try ModelContainer(
            for: StoredRiskCard.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        let medicationID = UUID()
        let original = ExternalRiskSignal(
            id: "risk-alpha",
            medicationID: medicationID,
            sourceKind: .drugLabel,
            severity: .high,
            kind: .labelRisk,
            displayPriority: 10,
            title: "合成风险提醒",
            message: "请核对原始说明书。",
            sourceTitle: "合成 来源",
            sourceExcerpt: "稳定的合成 来源证据",
            requiresProfessionalReview: true
        )
        let created = RiskLifecycleSyncService.sync(
            namespace: "synthetic", signals: [original], in: context
        )
        let riskID = try #require(created.createdIDs.first)
        let card = try #require(try context.fetch(FetchDescriptor<StoredRiskCard>()).first)
        let readAt = Date(timeIntervalSince1970: 1_800_000_000)
        let rollbackCompatibleSignature = card.detectionSignature
        #expect(rollbackCompatibleSignature == "\(medicationID.uuidString)|labelrisk|合成风险提醒|请核对原始说明书。|稳定的合成 来源证据")
        #expect(rollbackCompatibleSignature == StoredRiskCard.makeLegacyDetectionSignature(
            medicationID: medicationID,
            kindRaw: original.kind.rawValue,
            title: original.title,
            message: original.message,
            sourceExcerpt: original.sourceExcerpt
        ))
        card.readAt = readAt
        card.detectionSignature = card.semanticDetectionSignature
        try context.save()

        let candidateUpgrade = RiskLifecycleSyncService.sync(
            namespace: "synthetic", signals: [original], in: context
        )
        #expect(candidateUpgrade.updatedIDs.isEmpty)
        #expect(card.readAt == readAt)
        #expect(card.detectionSignature == rollbackCompatibleSignature)

        var translated = original
        translated.title = "Synthetic risk review"
        translated.message = "Check the original label."
        translated.sourceTitle = "合成\n 来源"
        translated.sourceExcerpt = "稳定的合成\n 来源证据"
        let presentationOnly = RiskLifecycleSyncService.sync(
            namespace: "synthetic", signals: [translated], in: context
        )
        #expect(presentationOnly.updatedIDs.isEmpty)
        #expect(card.readAt == readAt)
        #expect(card.title == translated.title)
        #expect(card.detectionSignature == rollbackCompatibleSignature)

        translated.sourceExcerpt = "不同的合成来源证据"
        let evidenceChanged = RiskLifecycleSyncService.sync(
            namespace: "synthetic", signals: [translated], in: context
        )
        #expect(evidenceChanged.updatedIDs == [riskID])
        #expect(card.readAt == nil)
        #expect(card.detectionSignature != rollbackCompatibleSignature)

        card.readAt = readAt
        translated.severity = .critical
        let severityChanged = RiskLifecycleSyncService.sync(
            namespace: "synthetic", signals: [translated], in: context
        )
        #expect(severityChanged.updatedIDs == [riskID])
        #expect(card.readAt == nil)

        card.readAt = readAt
        translated.sourceKind = .medicationProfile
        let sourceChanged = RiskLifecycleSyncService.sync(
            namespace: "synthetic", signals: [translated], in: context
        )
        #expect(sourceChanged.updatedIDs == [riskID])
        #expect(card.readAt == nil)
    }

    @Test @MainActor
    func userLabelRiskPresentationChangeKeepsReadStateButEvidenceChangeReopens() throws {
        let container = try ModelContainer(
            for: StoredMedication.self,
            StoredMedicationLabel.self,
            StoredRiskCard.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        let medication = StoredMedication(
            displayName: "合成药品",
            kind: .overTheCounter,
            inputSource: .manual
        )
        let label = StoredMedicationLabel(
            medicationID: medication.id,
            medicationName: medication.displayName,
            rawText: "【禁忌】对本品成分过敏者禁用。【药物相互作用】合用前应咨询医生或药师。",
            sourceTitle: "合成说明书"
        )
        context.insert(medication)
        context.insert(label)
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        _ = try MedicationRiskReviewService.applyUserLabelRisks(
            medication: medication, label: label, existing: [], reviewedAt: now, in: context
        )
        try context.save()
        let cards = try context.fetch(FetchDescriptor<StoredRiskCard>())
        let card = try #require(cards.first { !$0.sourceExcerpt.isEmpty })
        let rollbackCompatibleSignature = card.detectionSignature
        let readAt = now.addingTimeInterval(60)
        card.readAt = readAt
        card.title = "Synthetic warning"
        card.message = "Consult the original label."
        try context.save()

        let presentationOnly = try MedicationRiskReviewService.applyUserLabelRisks(
            medication: medication, label: label, existing: cards,
            reviewedAt: now.addingTimeInterval(120), in: context
        )
        #expect(!presentationOnly.updatedIDs.contains(card.id))
        #expect(card.readAt == readAt)
        #expect(card.detectionSignature == rollbackCompatibleSignature)
        try context.save()

        card.sourceExcerpt = "不同的合成禁忌原文"
        try context.save()
        let evidenceChanged = try MedicationRiskReviewService.applyUserLabelRisks(
            medication: medication, label: label, existing: cards,
            reviewedAt: now.addingTimeInterval(180), in: context
        )
        #expect(evidenceChanged.updatedIDs.contains(card.id))
        #expect(card.readAt == nil)
        #expect(card.detectionSignature == rollbackCompatibleSignature)
    }
}
