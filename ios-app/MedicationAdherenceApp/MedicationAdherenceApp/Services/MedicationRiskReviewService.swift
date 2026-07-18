import Foundation
import MedicationAdherenceCore
import SwiftData

enum MedicationRiskReviewService {
    static let userLabelRiskIDPrefix = "user-label"

    @MainActor
    @discardableResult
    static func rebuildUserLabelRisks(
        medication: StoredMedication,
        label: StoredMedicationLabel,
        in modelContext: ModelContext
    ) -> RiskLifecycleSyncResult {
        let now = Date()
        var result = RiskLifecycleSyncResult()
        let existing = (try? modelContext.fetch(FetchDescriptor<StoredRiskCard>())) ?? []
        archiveDemoLabelRisks(for: medication, cards: existing)

        guard let coreLabel = label.coreLabel else {
            resolveUserLabelRisks(for: medication, existing: existing, now: now, note: "说明书内容为空，相关风险已自动解除。", result: &result)
            label.lastRiskReviewAt = now
            try? modelContext.save()
            return result
        }

        archiveLegacyUserProvidedSourceReviews(for: medication, cards: existing)

        let context = MedicationRiskReviewContextProvider.context(for: medication, label: label)
        let input = RiskAssessmentInput(
            medication: medication.coreMedication,
            label: coreLabel,
            drugClasses: context.drugClasses,
            healthConditionEntries: context.healthConditionEntries,
            dietaryConcernEntries: context.dietaryConcernEntries
        )
        let assessedCards = RiskAssessmentEngine().assess(input)
        var activeStoredIDs: Set<String> = []
        for card in assessedCards {
            let storedID = "\(medication.id.uuidString)-\(userLabelRiskIDPrefix)-\(stableRiskCardID(from: card.id))"
            activeStoredIDs.insert(storedID)
            let sourceTitle = card.evidence?.sourceTitle ?? label.sourceTitle
            let sourceExcerpt = card.evidence?.excerpt ?? ""
            let detectionSignature = StoredRiskCard.makeDetectionSignature(
                medicationID: medication.id,
                kindRaw: card.kind.rawValue,
                title: card.title,
                message: card.message,
                sourceExcerpt: sourceExcerpt
            )
            let severityRaw = StoredRiskCard.inferredSeverityRaw(
                kindRaw: card.kind.rawValue,
                displayPriority: card.displayPriority,
                title: card.title,
                message: card.message,
                sourceExcerpt: sourceExcerpt,
                requiresProfessionalReview: card.requiresProfessionalReview
            )

            if let existingCard = existing.first(where: { $0.id == storedID }) {
                let wasResolved = existingCard.isResolved || existingCard.isArchived
                let shouldMarkUnread = existingCard.detectionSignature != detectionSignature
                    || existingCard.severityRaw != severityRaw
                    || existingCard.displayPriority != card.displayPriority
                    || existingCard.requiresProfessionalReview != card.requiresProfessionalReview
                let wasPriorityReminder = existingCard.shouldAnnounceAsPriorityReminder || existingCard.countsForRiskBadge
                existingCard.kindRaw = card.kind.rawValue
                existingCard.severityRaw = severityRaw
                existingCard.sourceKindRaw = StoredRiskSourceKind.drugLabel.rawValue
                existingCard.displayPriority = card.displayPriority
                existingCard.title = card.title
                existingCard.message = card.message
                existingCard.sourceTitle = sourceTitle
                existingCard.sourceExcerpt = sourceExcerpt
                existingCard.detectionSignature = detectionSignature
                existingCard.requiresProfessionalReview = card.requiresProfessionalReview
                existingCard.safetyNote = card.safetyNote
                existingCard.lastDetectedAt = now
                existingCard.resolvedAt = nil
                existingCard.resolutionNote = ""
                existingCard.archivedAt = nil
                existingCard.reviewNote = ""
                if shouldMarkUnread || wasResolved {
                    existingCard.readAt = nil
                }
                if wasResolved {
                    result.reactivatedIDs.append(storedID)
                } else if shouldMarkUnread {
                    result.updatedIDs.append(storedID)
                }
                if shouldMarkUnread || wasResolved || !wasPriorityReminder {
                    result.appendPriorityReminderIDIfNeeded(storedID, card: existingCard)
                }
            } else {
                let storedCard = StoredRiskCard(
                    id: storedID,
                    medicationID: medication.id,
                    kindRaw: card.kind.rawValue,
                    severityRaw: severityRaw,
                    sourceKindRaw: StoredRiskSourceKind.drugLabel.rawValue,
                    displayPriority: card.displayPriority,
                    title: card.title,
                    message: card.message,
                    sourceTitle: sourceTitle,
                    sourceExcerpt: sourceExcerpt,
                    detectionSignature: detectionSignature,
                    requiresProfessionalReview: card.requiresProfessionalReview,
                    safetyNote: card.safetyNote,
                    firstDetectedAt: now,
                    lastDetectedAt: now
                )
                modelContext.insert(storedCard)
                result.createdIDs.append(storedID)
                result.appendPriorityReminderIDIfNeeded(storedID, card: storedCard)
            }
        }

        for card in existing where card.medicationID == medication.id && card.id.contains("-\(userLabelRiskIDPrefix)-") && !activeStoredIDs.contains(card.id) && !card.isResolved {
            let wasPriorityReminder = card.shouldAnnounceAsPriorityReminder || card.countsForRiskBadge
            card.resolvedAt = now
            card.resolutionNote = "重新导入说明书后未再检测到该风险。"
            card.archivedAt = now
            card.reviewedAt = card.reviewedAt ?? now
            card.reviewNote = "风险已自动解除。"
            result.resolvedIDs.append(card.id)
            result.appendResolvedPriorityReminderIDIfNeeded(card.id, wasPriorityReminder: wasPriorityReminder)
        }

        label.lastRiskReviewAt = now
        try? modelContext.save()
        return result
    }

    private static func resolveUserLabelRisks(
        for medication: StoredMedication,
        existing: [StoredRiskCard],
        now: Date,
        note: String,
        result: inout RiskLifecycleSyncResult
    ) {
        for card in existing where card.medicationID == medication.id && card.id.contains("-\(userLabelRiskIDPrefix)-") && !card.isResolved {
            let wasPriorityReminder = card.shouldAnnounceAsPriorityReminder || card.countsForRiskBadge
            card.resolvedAt = now
            card.resolutionNote = note
            card.archivedAt = now
            card.reviewedAt = card.reviewedAt ?? now
            card.reviewNote = "风险已自动解除。"
            result.resolvedIDs.append(card.id)
            result.appendResolvedPriorityReminderIDIfNeeded(card.id, wasPriorityReminder: wasPriorityReminder)
        }
    }

    private static func archiveDemoLabelRisks(for medication: StoredMedication, cards: [StoredRiskCard]) {
        let now = Date()
        for card in cards where shouldArchiveSeededLabelRisk(card, for: medication) {
            card.archivedAt = now
            card.resolvedAt = card.resolvedAt ?? now
            card.resolutionNote = "用户已导入说明书，旧说明书风险已自动解除。"
            card.reviewedAt = card.reviewedAt ?? now
            card.reviewNote = "用户已导入说明书，旧说明书风险已自动归档隐藏。"
        }
    }

    private static func shouldArchiveSeededLabelRisk(_ card: StoredRiskCard, for medication: StoredMedication) -> Bool {
        guard card.medicationID == medication.id,
              card.id.hasPrefix("\(medication.id.uuidString)-"),
              !card.id.contains("-\(userLabelRiskIDPrefix)-"),
              !card.isArchived else {
            return false
        }

        switch RiskAssessmentCardKind(rawValue: card.kindRaw) {
        case .labelRisk, .healthConditionReview, .foodReview:
            return card.sourceKind == .drugLabel && (!card.sourceTitle.isEmpty || !card.sourceExcerpt.isEmpty)
        case .drugClassContext, .medicationSourceReview, nil:
            return false
        }
    }

    private static func archiveLegacyUserProvidedSourceReviews(for medication: StoredMedication, cards: [StoredRiskCard]) {
        let now = Date()
        for card in cards where card.medicationID == medication.id && !card.id.contains("-\(userLabelRiskIDPrefix)-") && !card.isArchived && isLegacyUserProvidedSourceReview(card) {
            card.archivedAt = now
            card.resolvedAt = card.resolvedAt ?? now
            card.resolutionNote = "用户已确认说明书，旧来源复核提醒已自动解除。"
            card.reviewedAt = card.reviewedAt ?? now
            card.reviewNote = "用户已确认说明书，旧来源复核提醒已自动归档隐藏。"
        }
    }

    private static func isLegacyUserProvidedSourceReview(_ card: StoredRiskCard) -> Bool {
        guard card.kindRaw == RiskAssessmentCardKind.medicationSourceReview.rawValue else {
            return false
        }
        return card.id.contains("source-user-provided-label") || card.title == "说明书来源待核对"
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

private struct MedicationRiskReviewContext {
    var drugClasses: [DrugClass] = []
    var healthConditionEntries: [UserRiskContextEntry] = []
    var dietaryConcernEntries: [UserRiskContextEntry] = []
}

private enum MedicationRiskReviewContextProvider {
    static func context(for medication: StoredMedication, label: StoredMedicationLabel) -> MedicationRiskReviewContext {
        let medicationAndLabelText = normalizedSearchText([
            medication.displayName,
            medication.genericName,
            medication.form,
            medication.strength,
            medication.notes,
            label.medicationName,
            label.sourceTitle,
            label.rawText
        ])
        let explicitUserContextText = explicitUserContextText(from: medication.notes)

        var context = MedicationRiskReviewContext()
        context.drugClasses = drugClasses(from: medicationAndLabelText)
        context.healthConditionEntries = healthConditionEntries(from: explicitUserContextText)
        context.dietaryConcernEntries = dietaryConcernEntries(from: explicitUserContextText)
        return context
    }

    private static func normalizedSearchText(_ parts: [String]) -> String {
        parts
            .joined(separator: "\n")
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
            .lowercased()
    }

    private static func explicitUserContextText(from notes: String) -> String {
        let normalizedNotes = normalizedSearchText([notes])
        let explicitMarkers = [
            "用户记录",
            "健康记录",
            "饮食记录",
            "病史",
            "既往",
            "本人",
            "我有",
            "我正在",
            "医生诊断",
            "医生说"
        ]
        guard containsAny(normalizedNotes, explicitMarkers) else {
            return ""
        }
        return normalizedNotes
    }

    private static func drugClasses(from text: String) -> [DrugClass] {
        var classes: [DrugClass] = []
        if containsAny(text, ["布洛芬", "ibuprofen", "nsaid", "非甾体"]) {
            classes.append(DrugClass(classID: "local-nsaid-analgesic", name: "非甾体类止痛药", source: "本地药品资料"))
        }
        if containsAny(text, ["对乙酰氨基酚", "acetaminophen", "paracetamol"]) {
            classes.append(DrugClass(classID: "local-acetaminophen-analgesic", name: "解热镇痛药", source: "本地药品资料"))
        }
        if containsAny(text, ["氯雷他定", "loratadine", "antihistamine", "抗组胺"]) {
            classes.append(DrugClass(classID: "local-antihistamine", name: "抗组胺药", source: "本地药品资料"))
        }
        return classes
    }

    private static func healthConditionEntries(from text: String) -> [UserRiskContextEntry] {
        var entries: [UserRiskContextEntry] = []
        appendEntryIfNeeded(
            name: "卒中",
            note: "用户记录中出现既往卒中相关表述，需要复核。",
            when: containsAny(text, ["卒中", "中风", "stroke"]),
            to: &entries
        )
        appendEntryIfNeeded(
            name: "肾病",
            note: "用户记录中出现肾病相关表述，需要复核。",
            when: containsAny(text, ["肾病", "kidney disease"]),
            to: &entries
        )
        appendEntryIfNeeded(
            name: "肾功能",
            note: "用户记录中出现肾功能相关表述，需要复核。",
            when: containsAny(text, ["肾功能", "renal"]),
            to: &entries
        )
        appendEntryIfNeeded(
            name: "肝功能",
            note: "用户记录中出现肝功能相关表述，需要复核。",
            when: containsAny(text, ["肝功能", "hepatic"]),
            to: &entries
        )
        appendEntryIfNeeded(
            name: "肝病",
            note: "用户记录中出现肝病相关表述，需要复核。",
            when: containsAny(text, ["肝病", "liver disease"]),
            to: &entries
        )
        appendEntryIfNeeded(
            name: "胃部不适",
            note: "用户记录中出现胃部不适或胃出血相关表述，需要复核。",
            when: containsAny(text, ["胃部不适", "胃痛", "stomach pain"]),
            to: &entries
        )
        appendEntryIfNeeded(
            name: "胃出血",
            note: "用户记录中出现胃出血相关表述，需要复核。",
            when: containsAny(text, ["胃出血", "stomach bleeding"]),
            to: &entries
        )
        appendEntryIfNeeded(
            name: "孕妇及哺乳期",
            note: "用户记录中出现孕妇或哺乳期相关表述，需要复核。",
            when: containsAny(text, ["孕妇", "妊娠", "哺乳", "pregnant", "pregnancy", "breastfeeding", "lactation"]),
            to: &entries
        )
        appendEntryIfNeeded(
            name: "儿童",
            note: "用户记录中出现儿童用药相关表述，需要复核。",
            when: containsAny(text, ["儿童", "小儿", "children", "pediatric"]),
            to: &entries
        )
        appendEntryIfNeeded(
            name: "老年",
            note: "用户记录中出现老年用药相关表述，需要复核。",
            when: containsAny(text, ["老年", "elderly", "geriatric"]),
            to: &entries
        )
        return entries
    }

    private static func dietaryConcernEntries(from text: String) -> [UserRiskContextEntry] {
        var entries: [UserRiskContextEntry] = []
        appendEntryIfNeeded(
            name: "饮酒",
            note: "用户记录中出现饮酒、酒精相关表述，需要复核。",
            when: containsAny(text, ["饮酒", "酒精", "alcohol"]),
            to: &entries
        )
        appendEntryIfNeeded(
            name: "葡萄柚",
            note: "用户记录中出现葡萄柚相关表述，需要复核。",
            when: containsAny(text, ["葡萄柚", "grapefruit"]),
            to: &entries
        )
        return entries
    }

    private static func appendEntryIfNeeded(
        name: String,
        note: String,
        when shouldAppend: Bool,
        to entries: inout [UserRiskContextEntry]
    ) {
        guard shouldAppend, !entries.contains(where: { $0.name == name }) else {
            return
        }
        entries.append(UserRiskContextEntry(name: name, note: note))
    }

    private static func containsAny(_ text: String, _ needles: [String]) -> Bool {
        needles.contains { text.contains($0.lowercased()) }
    }
}
