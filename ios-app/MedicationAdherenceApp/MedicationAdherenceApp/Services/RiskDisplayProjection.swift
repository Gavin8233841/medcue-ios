import Foundation
import MedicationAdherenceCore

struct RiskDisplayProjection {
    let activeCards: [StoredRiskCard]
    let archivedCards: [StoredRiskCard]
    let cardsByGroup: [RiskReviewGroup: [StoredRiskCard]]
    let medicationNamesByID: [UUID: String]

    init(
        riskCards: [StoredRiskCard],
        medications: [StoredMedication],
        grouper: RiskReviewGrouper = RiskReviewGrouper()
    ) {
        medicationNamesByID = Dictionary(
            uniqueKeysWithValues: medications.map {
                ($0.id, userFacingMedicationName(for: $0))
            }
        )
        activeCards = Self.deduplicatedCards(
            from: riskCards.filter(\.isActive)
        )
        archivedCards = Self.deduplicatedCards(
            from: riskCards.filter { $0.isArchived || $0.isResolved }
        )
        var groupedCards: [RiskReviewGroup: [StoredRiskCard]] = [:]
        for group in RiskReviewGroup.allCases {
            groupedCards[group] = activeCards.filter {
                grouper.mappedGroup(for: $0.coreRiskCard) == group
            }
        }
        cardsByGroup = groupedCards
    }

    static func refreshID(
        riskCards: [StoredRiskCard],
        medications: [StoredMedication]
    ) -> String {
        [
            String(stableRiskCardSignature(riskCards)),
            String(stableMedicationSignature(medications))
        ].joined(separator: "|")
    }

    func medicationName(for card: StoredRiskCard) -> String {
        medicationNamesByID[card.medicationID] ?? "未知药品"
    }

    private static func deduplicatedCards(
        from cards: [StoredRiskCard]
    ) -> [StoredRiskCard] {
        var chosenCards: [String: StoredRiskCard] = [:]
        for card in cards {
            let key = duplicateKey(for: card)
            if let existingCard = chosenCards[key] {
                chosenCards[key] = preferredCard(existingCard, card)
            } else {
                chosenCards[key] = card
            }
        }
        return chosenCards.values.sorted(by: riskCardSort)
    }

    private static func duplicateKey(for card: StoredRiskCard) -> String {
        let medicationKey = card.medicationID.uuidString
        let detectionSignature = normalized(card.detectionSignature)
        if !detectionSignature.isEmpty {
            return "\(medicationKey)|detection|\(detectionSignature)"
        }
        return [
            medicationKey,
            "content",
            normalized(card.kindRaw),
            normalized(card.title),
            normalized(card.message)
        ].joined(separator: "|")
    }

    private static func preferredCard(
        _ lhs: StoredRiskCard,
        _ rhs: StoredRiskCard
    ) -> StoredRiskCard {
        if lhs.isArchived != rhs.isArchived {
            return lhs.isArchived ? rhs : lhs
        }
        if lhs.isResolved != rhs.isResolved {
            return lhs.isResolved ? rhs : lhs
        }
        if lhs.requiresProfessionalReview != rhs.requiresProfessionalReview {
            return lhs.requiresProfessionalReview ? lhs : rhs
        }
        if lhs.displayPriority != rhs.displayPriority {
            return lhs.displayPriority < rhs.displayPriority ? lhs : rhs
        }
        let lhsSpecificity = specificityScore(for: lhs)
        let rhsSpecificity = specificityScore(for: rhs)
        if lhsSpecificity != rhsSpecificity {
            return lhsSpecificity > rhsSpecificity ? lhs : rhs
        }
        return lhs.id <= rhs.id ? lhs : rhs
    }

    private static func specificityScore(for card: StoredRiskCard) -> Int {
        var score = 0
        if !card.sourceTitle.isEmpty {
            score += 1
        }
        if !card.sourceExcerpt.isEmpty {
            score += 2
        }
        if card.title.contains("相关复核") {
            score += 1
        }
        if card.title == "警示信息" || card.title == "注意事项" {
            score -= 1
        }
        return score
    }

    private static func normalized(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: " ", with: "")
    }
}

func riskCardSort(_ lhs: StoredRiskCard, _ rhs: StoredRiskCard) -> Bool {
    if lhs.displayPriority != rhs.displayPriority {
        return lhs.displayPriority < rhs.displayPriority
    }
    if lhs.requiresProfessionalReview != rhs.requiresProfessionalReview {
        return lhs.requiresProfessionalReview
    }
    let titleOrder = lhs.title.localizedStandardCompare(rhs.title)
    if titleOrder != .orderedSame {
        return titleOrder == .orderedAscending
    }
    return lhs.id < rhs.id
}
