import Foundation
import MedicationAdherenceCore
import SwiftData

enum MedicationRiskReviewService {
    static let userLabelRiskIDPrefix = "user-label"

    @MainActor
    static func rebuildUserLabelRisks(
        medication: StoredMedication,
        label: StoredMedicationLabel,
        in modelContext: ModelContext
    ) {
        let existing = (try? modelContext.fetch(FetchDescriptor<StoredRiskCard>())) ?? []
        for card in existing where card.medicationID == medication.id && card.id.contains("-\(userLabelRiskIDPrefix)-") {
            modelContext.delete(card)
        }
        archiveDemoLabelRisks(for: medication, cards: existing)

        guard let coreLabel = label.coreLabel else {
            return
        }

        let input = RiskAssessmentInput(
            medication: medication.coreMedication,
            label: coreLabel
        )
        for card in RiskAssessmentEngine().assess(input) {
            let storedID = "\(medication.id.uuidString)-\(userLabelRiskIDPrefix)-\(stableRiskCardID(from: card.id))"
            modelContext.insert(StoredRiskCard(
                id: storedID,
                medicationID: medication.id,
                kindRaw: card.kind.rawValue,
                displayPriority: card.displayPriority,
                title: card.title,
                message: card.message,
                sourceTitle: card.evidence?.sourceTitle ?? label.sourceTitle,
                sourceExcerpt: card.evidence?.excerpt ?? "",
                requiresProfessionalReview: card.requiresProfessionalReview,
                safetyNote: card.safetyNote
            ))
        }
        label.lastRiskReviewAt = Date()
        try? modelContext.save()
    }

    private static func archiveDemoLabelRisks(for medication: StoredMedication, cards: [StoredRiskCard]) {
        let now = Date()
        for card in cards where card.medicationID == medication.id && !card.id.contains("-\(userLabelRiskIDPrefix)-") && !card.isArchived && isDemoLabelRisk(card) {
            card.archivedAt = now
            card.reviewedAt = card.reviewedAt ?? now
            card.reviewNote = "用户已导入说明书，演示说明书风险自动归档隐藏。"
        }
    }

    private static func isDemoLabelRisk(_ card: StoredRiskCard) -> Bool {
        if card.kindRaw == RiskAssessmentCardKind.medicationSourceReview.rawValue || card.kindRaw == RiskAssessmentCardKind.drugClassContext.rawValue {
            return false
        }
        return !card.sourceTitle.isEmpty || !card.sourceExcerpt.isEmpty
    }

    private static func stableRiskCardID(from value: String) -> String {
        value
            .lowercased()
            .map { character in
                character.isLetter || character.isNumber ? character : "-"
            }
            .reduce(into: "") { partialResult, character in
                if character == "-", partialResult.last == "-" {
                    return
                }
                partialResult.append(character)
            }
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }
}
