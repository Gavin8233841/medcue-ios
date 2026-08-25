import Foundation
import MedicationAdherenceCore

/// 药品搜索索引，用于快速匹配搜索查询
struct MedicationSearchIndex {
    let medication: StoredMedication
    let searchableText: String

    init(medication: StoredMedication) {
        self.medication = medication

        let fields = [
            medication.displayName,
            medication.genericName,
            medication.strength,
            medication.form,
            medication.kind.displayName,
            medication.notes
        ]
        .compactMap { $0.isEmpty ? nil : $0 }

        self.searchableText = SearchTextNormalizer.normalize(
            fields.joined(separator: " ")
        )
    }

    func matches(query: [String]) -> Bool {
        SearchTextNormalizer.matches(query: query, in: searchableText)
    }
}
