import Foundation
import MedicationAdherenceCore

/// 风险搜索索引，用于快速匹配搜索查询
struct RiskSearchIndex {
    let card: StoredRiskCard
    let searchableText: String

    init(
        card: StoredRiskCard,
        medicationName: String,
        medicationGenericName: String = ""
    ) {
        self.card = card

        let fields = [
            medicationName,
            medicationGenericName,
            card.title,
            card.message,
            RiskReviewGrouper().mappedGroup(for: card.coreRiskCard).title,
            card.severity.displayName,
            card.sourceTitle,
            card.sourceExcerpt
        ]
        .compactMap { $0 }
        .filter { !$0.isEmpty }

        self.searchableText = SearchTextNormalizer.normalize(
            fields.joined(separator: " ")
        )
    }

    func matches(query: [String]) -> Bool {
        SearchTextNormalizer.matches(query: query, in: searchableText)
    }
}
