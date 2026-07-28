import Foundation
import MedicationAdherenceCore
import SwiftData
import SwiftUI

struct RiskCardDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openMedicationAIQuestion) private var openMedicationAIQuestion
    let card: StoredRiskCard
    let medicationName: String
    @Query(sort: \StoredMedication.displayName) private var medications: [StoredMedication]

    init(card: StoredRiskCard, medicationName: String) {
        self.card = card
        self.medicationName = medicationName
        let medicationID = card.medicationID
        _medications = Query(
            filter: #Predicate<StoredMedication> { medication in
                medication.id == medicationID
            },
            sort: \StoredMedication.displayName
        )
    }

    private var medication: StoredMedication? {
        medications.first { $0.id == card.medicationID }
    }

    private var shareText: String {
        [
            "用药风险沟通摘要",
            "药品：\(medicationName)",
            "警示：\(riskDisplayTitle(for: card))",
            "提示：\(riskActionableSummaryText(for: card))",
            riskConcreteFocusText(for: card).map { "核对对象：\(riskShareFocusText($0))" },
            card.sourceTitle.isEmpty ? nil : "来源：\(card.sourceTitle)",
            card.sourceExcerpt.isEmpty ? nil : "依据片段：\(card.sourceExcerpt)",
            card.safetyNote.isEmpty ? "说明：以上内容仅用于风险提示和复诊沟通，不能替代医生或药师判断。" : "说明：\(card.safetyNote)"
        ]
        .compactMap { $0 }
        .joined(separator: "\n")
    }

    private var communicationText: String {
        let summary = riskCommunicationSummaryText(for: card)
        return [
            "药品：\(medicationName)",
            "警示：\(riskDisplayTitle(for: card))",
            summary.isEmpty ? nil : "提示：\(summary)",
            riskCommunicationFocusLine(for: card, summary: summary),
            card.sourceTitle.isEmpty ? nil : "来源：\(card.sourceTitle)",
            riskCommunicationEvidenceLine(for: card, summary: summary)
        ]
        .compactMap { $0 }
        .joined(separator: "\n")
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    Label(
                        isContraindicationRisk(card) ? "禁忌/慎用提醒" : riskCategoryText(for: card),
                        systemImage: riskCategoryIconName(for: card)
                    )
                    .font(.headline)
                    .foregroundStyle(riskCategoryTint(for: card))
                    Text(riskDisplayTitle(for: card))
                        .font(.title3.weight(.semibold))
                    Text(medicationName)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 8)
            }

            Section("提示内容") {
                Text(riskActionableSummaryText(for: card))
            }

            if let concreteFocus = riskConcreteFocusText(for: card) {
                Section("需要核对") {
                    Label(concreteFocus, systemImage: "scope")
                        .foregroundStyle(riskCategoryTint(for: card))
                }
            }

            Section("关联操作") {
                if let medication {
                    NavigationLink {
                        MedicationDetailView(medication: medication)
                    } label: {
                        Label("查看相关药品", systemImage: "pills.fill")
                    }
                }
                Button {
                    openMedicationAIQuestion(aiQuestion)
                } label: {
                    Label("让智能体解释这条警示", systemImage: "stethoscope")
                }
            }

            Section("复诊沟通") {
                Text(communicationText)
                    .font(.body)
                    .textSelection(.enabled)
                ShareLink(item: shareText) {
                    Label("分享给医生或药师", systemImage: "square.and.arrow.up")
                }
            }

            Section("处理") {
                if card.isArchived || card.isResolved {
                    Label {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(card.isResolved ? "已解除归档" : "已复核归档")
                                .font(.headline)
                            Text(card.reviewedAt.map { "复核时间：\(AppFormatters.day.string(from: $0)) \(AppFormatters.time.string(from: $0))" } ?? (card.isResolved ? "该警示已解除。" : "该警示已归档。"))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "archivebox.fill")
                            .foregroundStyle(.green)
                    }
                    Button {
                        _ = RiskReviewCommand(modelContext: modelContext).perform(
                            .reopen(riskCardID: card.id)
                        )
                    } label: {
                        Label("重新打开警示", systemImage: "arrow.uturn.backward")
                    }
                } else {
                    Button {
                        _ = RiskReviewCommand(modelContext: modelContext).perform(
                            .archive(riskCardID: card.id, reviewedAt: Date())
                        )
                    } label: {
                        Label("标记已复核并归档", systemImage: "checkmark.circle")
                    }
                }
            }

            if !card.sourceExcerpt.isEmpty || !card.sourceTitle.isEmpty {
                Section("依据片段") {
                    HStack {
                        Text("来源")
                            .foregroundStyle(.secondary)
                        Spacer()
                        StatusBadge(text: riskSourceText(for: card), color: sourceTint(for: card))
                    }
                    if !card.sourceTitle.isEmpty {
                        Text(card.sourceTitle)
                            .font(.headline)
                    }
                    if !card.sourceExcerpt.isEmpty {
                        Text(card.sourceExcerpt)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("使用边界") {
                Text(card.safetyNote.isEmpty ? "以上内容仅用于风险提示，不能替代医生或药师判断。" : card.safetyNote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("警示详情")
    }

    private var aiQuestion: String {
        [
            "请帮我解释这条用药风险，并给出适合复诊沟通的提醒。",
            "药品：\(medicationName)",
            "警示：\(riskDisplayTitle(for: card))",
            "内容：\(riskActionableSummaryText(for: card))",
            riskConcreteFocusText(for: card).map { "核对对象：\(riskShareFocusText($0))" },
            card.sourceExcerpt.isEmpty ? nil : "依据：\(card.sourceExcerpt)"
        ]
        .compactMap { $0 }
        .joined(separator: "\n")
    }
}

struct RiskVisualStyle: Equatable {
    let symbolName: String
    let tint: Color

    static let neutral = RiskVisualStyle(symbolName: "pills.fill", tint: RiskPalette.slate)
}

enum RiskPalette {
    static let slate = Color(red: 0.42, green: 0.48, blue: 0.56)
    static let blue = Color(red: 0.31, green: 0.47, blue: 0.62)
    static let teal = Color(red: 0.27, green: 0.50, blue: 0.48)
    static let indigo = Color(red: 0.43, green: 0.43, blue: 0.59)
    static let amber = Color(red: 0.62, green: 0.51, blue: 0.32)
    static let green = Color(red: 0.36, green: 0.53, blue: 0.40)
    static let rose = Color(red: 0.58, green: 0.38, blue: 0.40)
    static let grape = Color(red: 0.49, green: 0.43, blue: 0.58)
    static let softRed = rose
}

func riskGroupVisual(for group: RiskReviewGroup) -> RiskVisualStyle {
    switch group {
    case .drugInteraction:
        RiskVisualStyle(symbolName: "pills.fill", tint: RiskPalette.indigo)
    case .foodAndLifestyleInteraction:
        RiskVisualStyle(symbolName: "fork.knife", tint: RiskPalette.teal)
    case .conditionAndSymptomAttention:
        RiskVisualStyle(symbolName: "heart.text.square", tint: RiskPalette.softRed)
    }
}

func medicationRiskVisual(
    for medication: StoredMedication?,
    cards: [StoredRiskCard],
    medicationName fallbackName: String? = nil
) -> RiskVisualStyle {
    let primaryText = normalized([
        medication?.displayName,
        medication?.genericName,
        medication?.form,
        medication?.strength,
        fallbackName
    ]
    .compactMap { $0 }
    .joined(separator: " "))
    let fallbackText = primaryText.isEmpty ? normalized(medication?.notes ?? "") : ""
    let symbolName = medicationRiskSymbolName(
        for: medication,
        normalizedText: primaryText,
        fallbackText: fallbackText
    )
    let tint = medicationRiskTint(
        for: medication,
        normalizedText: primaryText,
        fallbackText: fallbackText
    )
    return RiskVisualStyle(symbolName: symbolName, tint: tint)
}

func medicationRiskSymbolName(
    for medication: StoredMedication?,
    normalizedText text: String,
    fallbackText: String
) -> String {
    if let symbolName = medication?.photoSymbolName,
       isMedicationTypeSymbol(symbolName),
       symbolName != "pills.fill" {
        return symbolName
    }
    if text.contains("滴眼") || text.contains("人工泪液") || text.contains("眼") {
        return "eye.fill"
    }
    if text.contains("喷") || text.contains("吸入") || text.contains("鼻") || text.contains("氯雷他定") || text.contains("loratadine") {
        return "wind"
    }
    if text.contains("维生素") || text.contains("vitamin") || text.contains("d3") {
        return "sun.max.fill"
    }
    if text.contains("布洛芬") || text.contains("对乙酰氨基酚") || text.contains("止痛") || text.contains("退热") || text.contains("ibuprofen") || text.contains("acetaminophen") {
        return "cross.case.fill"
    }
    if text.contains("胶囊") || text.contains("软胶囊") || text.contains("capsule") {
        return "capsule.fill"
    }
    if text.contains("贴") || text.contains("膏") || text.contains("外用") {
        return "bandage.fill"
    }
    if text.contains("注射") || text.contains("针") {
        return "syringe.fill"
    }
    if text.contains("颗粒") || text.contains("冲剂") || text.contains("粉") {
        return "shippingbox.fill"
    }
    if fallbackText.contains("滴眼") || fallbackText.contains("眼") {
        return "eye.fill"
    }
    if fallbackText.contains("吸入") || fallbackText.contains("鼻") {
        return "wind"
    }
    if let symbolName = medication?.photoSymbolName,
       isMedicationTypeSymbol(symbolName) {
        return symbolName
    }
    return "pills.fill"
}

func medicationRiskTint(
    for medication: StoredMedication?,
    normalizedText text: String,
    fallbackText: String
) -> Color {
    if let symbolName = medication?.photoSymbolName,
       isMedicationTypeSymbol(symbolName),
       symbolName != "pills.fill" {
        return medicationTintForSymbol(symbolName)
    }
    if text.contains("滴眼") || text.contains("人工泪液") || text.contains("眼") {
        return RiskPalette.teal
    }
    if text.contains("氯雷他定") || text.contains("loratadine") || text.contains("鼻") {
        return RiskPalette.blue
    }
    if text.contains("维生素") || text.contains("vitamin") || text.contains("d3") {
        return RiskPalette.amber
    }
    if text.contains("布洛芬") || text.contains("对乙酰氨基酚") || text.contains("止痛") || text.contains("退热") || text.contains("ibuprofen") || text.contains("acetaminophen") {
        return RiskPalette.indigo
    }
    if fallbackText.contains("滴眼") || fallbackText.contains("眼") {
        return RiskPalette.teal
    }
    if fallbackText.contains("吸入") || fallbackText.contains("鼻") {
        return RiskPalette.blue
    }
    if let symbolName = medication?.photoSymbolName {
        return medicationTintForSymbol(symbolName)
    }
    return RiskPalette.slate
}

func isMedicationTypeSymbol(_ symbolName: String) -> Bool {
    switch symbolName {
    case "pills.fill",
        "capsule.fill",
        "eye.fill",
        "wind",
        "sun.max.fill",
        "syringe.fill",
        "bandage.fill",
        "drop.fill",
        "shippingbox.fill",
        "cross.case.fill":
        return true
    default:
        return false
    }
}

func medicationTintForSymbol(_ symbolName: String) -> Color {
    switch symbolName {
    case "eye.fill", "drop.fill":
        return RiskPalette.teal
    case "wind":
        return RiskPalette.blue
    case "sun.max.fill":
        return RiskPalette.amber
    case "capsule.fill":
        return RiskPalette.grape
    case "syringe.fill", "bandage.fill":
        return RiskPalette.green
    case "cross.case.fill":
        return RiskPalette.indigo
    default:
        return RiskPalette.slate
    }
}

func normalized(_ value: String) -> String {
    value
        .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
        .lowercased()
        .components(separatedBy: .whitespacesAndNewlines)
        .filter { !$0.isEmpty }
        .joined(separator: " ")
        .trimmingCharacters(in: .punctuationCharacters)
}

func isContraindicationRisk(_ card: StoredRiskCard) -> Bool {
    let text = normalized("\(card.title) \(card.message) \(card.sourceTitle) \(card.sourceExcerpt)")
    return text.contains("禁忌")
        || text.contains("禁用")
        || text.contains("contraindication")
        || text.contains("contraindicated")
        || text.contains("avoid")
}

func riskCategoryText(for card: StoredRiskCard) -> String {
    switch RiskAssessmentCardKind(rawValue: card.kindRaw) ?? .labelRisk {
    case .foodReview:
        return "饮食注意"
    case .healthConditionReview:
        return "病症注意"
    case .medicationSourceReview:
        return "来源核对"
    case .drugClassContext:
        return "类别信息"
    case .labelRisk:
        let grouped = RiskReviewGrouper().mappedGroup(for: card.coreRiskCard)
        switch grouped {
        case .drugInteraction:
            return "相互作用"
        case .foodAndLifestyleInteraction:
            return "饮食注意"
        case .conditionAndSymptomAttention:
            return "病症注意"
        }
    }
}

func riskConcreteFocusText(for card: StoredRiskCard) -> String? {
    let focus = extractedRiskFocus(from: card)
    switch RiskAssessmentCardKind(rawValue: card.kindRaw) ?? .labelRisk {
    case .foodReview:
        guard !focus.isEmpty else {
            return "当前资料未写明具体饮食或生活方式，请补充说明书或向医生或药师确认。"
        }
        return "需核对饮食或生活方式：\(focus)"
    case .healthConditionReview:
        guard !focus.isEmpty else {
            return "当前资料未写明具体病症或症状，请补充病史信息或向医生或药师确认。"
        }
        return "需核对病症或症状：\(focus)"
    case .medicationSourceReview:
        guard !focus.isEmpty else {
            return "当前资料未写明药品来源细节，请按药盒、说明书或医嘱核对。"
        }
        return "需核对来源：\(focus)"
    case .drugClassContext:
        guard !focus.isEmpty else {
            return nil
        }
        return "药品类别：\(focus)"
    case .labelRisk:
        let grouped = RiskReviewGrouper().mappedGroup(for: card.coreRiskCard)
        if isContraindicationRisk(card) {
            guard !focus.isEmpty else {
                return "当前说明书未写明具体禁忌对象，请补充完整说明书或向医生或药师确认。"
            }
            return "需核对禁忌条件：\(focus)"
        }
        switch grouped {
        case .drugInteraction:
            guard !focus.isEmpty else {
                return "当前资料未写明合用药品名称，请补充说明书或向医生或药师确认。"
            }
            return "需核对合用药品：\(focus)"
        case .foodAndLifestyleInteraction:
            guard !focus.isEmpty else {
                return "当前资料未写明具体饮食或生活方式，请补充说明书或向医生或药师确认。"
            }
            return "需核对饮食或生活方式：\(focus)"
        case .conditionAndSymptomAttention:
            guard !focus.isEmpty else {
                return "当前资料未写明具体病症或症状，请补充病史信息或向医生或药师确认。"
            }
            return "需核对病症或症状：\(focus)"
        }
    }
}

func riskShareFocusText(_ text: String) -> String {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard trimmed.hasPrefix("需核对") else {
        return trimmed
    }
    return String(trimmed.dropFirst("需核对".count))
        .trimmingCharacters(in: .whitespacesAndNewlines)
}

func isMissingRiskFocusText(_ text: String) -> Bool {
    let normalizedText = normalized(text)
    return normalizedText.contains("未写明")
        || normalizedText.contains("请补充")
        || normalizedText.contains("待补充")
}

func missingRiskFocusTitle(for card: StoredRiskCard) -> String {
    switch RiskAssessmentCardKind(rawValue: card.kindRaw) ?? .labelRisk {
    case .foodReview:
        return "待补充饮食或生活方式"
    case .healthConditionReview:
        return "待补充病症或症状"
    case .medicationSourceReview:
        return "待补充来源细节"
    case .drugClassContext:
        return "待补充类别来源"
    case .labelRisk:
        let grouped = RiskReviewGrouper().mappedGroup(for: card.coreRiskCard)
        if isContraindicationRisk(card) {
            return "待补充禁忌对象"
        }
        switch grouped {
        case .drugInteraction:
            return "待补充合用药品"
        case .foodAndLifestyleInteraction:
            return "待补充饮食或生活方式"
        case .conditionAndSymptomAttention:
            return "待补充病症或症状"
        }
    }
}

func missingRiskFocusSummary(for card: StoredRiskCard) -> String {
    switch RiskAssessmentCardKind(rawValue: card.kindRaw) ?? .labelRisk {
    case .foodReview:
        return "当前资料没有具体饮食或生活方式，请补充说明书或向医生或药师确认。"
    case .healthConditionReview:
        return "当前资料没有具体病症或症状，请补充病史信息或向医生或药师确认。"
    case .medicationSourceReview:
        return "当前资料没有药品来源细节，请按药盒、说明书或医嘱核对。"
    case .drugClassContext:
        return "当前资料没有完整药品类别来源，请补充药品资料后再复核。"
    case .labelRisk:
        let grouped = RiskReviewGrouper().mappedGroup(for: card.coreRiskCard)
        if isContraindicationRisk(card) {
            return "当前说明书没有具体禁忌对象，请补充完整说明书或向医生或药师确认。"
        }
        switch grouped {
        case .drugInteraction:
            return "当前资料没有具体合用药品名称，请补充说明书或向医生或药师确认。"
        case .foodAndLifestyleInteraction:
            return "当前资料没有具体饮食或生活方式，请补充说明书或向医生或药师确认。"
        case .conditionAndSymptomAttention:
            return "当前资料没有具体病症或症状，请补充病史信息或向医生或药师确认。"
        }
    }
}

func riskDisplayTitle(for card: StoredRiskCard) -> String {
    let rawTitle = card.title.trimmingCharacters(in: .whitespacesAndNewlines)
    guard shouldExpandRiskDisplayTitle(rawTitle) else {
        return rawTitle.isEmpty ? riskCategoryText(for: card) : rawTitle
    }
    let category = isContraindicationRisk(card) ? "禁忌或慎用" : riskCategoryText(for: card)
    guard let focus = riskConcreteFocusText(for: card).map(riskShareFocusText),
          !focus.isEmpty
    else {
        return category
    }
    if isMissingRiskFocusText(focus) {
        return "\(category)：\(missingRiskFocusTitle(for: card))"
    }
    return "\(category)：\(riskCompactTitleFocusText(focus))"
}

func shouldExpandRiskDisplayTitle(_ title: String) -> Bool {
    let normalizedTitle = normalized(title)
    return isGenericRiskFocus(title)
        || normalizedTitle == "警示信息"
        || normalizedTitle == "注意事项"
        || normalizedTitle == "禁忌"
        || normalizedTitle == "禁忌或不得使用"
        || normalizedTitle == "相互作用"
        || normalizedTitle == "相互作用或需咨询药师"
        || normalizedTitle == "饮食注意"
        || normalizedTitle == "不良反应"
}

func riskCompactTitleFocusText(_ text: String) -> String {
    var value = text.trimmingCharacters(in: .whitespacesAndNewlines)
    let prefixes = [
        "禁忌条件：",
        "合用药品：",
        "饮食或生活方式：",
        "病症或症状：",
        "来源：",
        "药品类别："
    ]
    for prefix in prefixes where value.hasPrefix(prefix) {
        value = String(value.dropFirst(prefix.count))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        break
    }
    return value
}

func riskActionableSummaryText(for card: StoredRiskCard) -> String {
    let message = cleanedRiskFocusText(card.message, limit: 96)
    let focus = riskConcreteFocusText(for: card).map(riskShareFocusText)
    let sourceExcerpt = riskSourceExcerptPreview(for: card)
    let category = isContraindicationRisk(card) ? "禁忌或慎用" : riskCategoryText(for: card)
    let baseMessage: String
    if message.isEmpty || isGenericRiskFocus(message) {
        baseMessage = "\(category)提醒，需要结合药品资料复核。"
    } else {
        baseMessage = message
    }
    let focusText: String?
    if let focus, !focus.isEmpty, focus != baseMessage {
        focusText = isMissingRiskFocusText(focus)
            ? missingRiskFocusSummary(for: card)
            : "重点核对\(focus)"
    } else {
        focusText = nil
    }
    let evidenceText: String?
    if let sourceExcerpt, !sourceExcerpt.isEmpty, sourceExcerpt != focus, sourceExcerpt != baseMessage {
        evidenceText = "依据片段：\(sourceExcerpt)"
    } else {
        evidenceText = nil
    }
    return [baseMessage, focusText, evidenceText]
        .compactMap { $0 }
        .joined(separator: "\n")
}

func riskCommunicationSummaryText(for card: StoredRiskCard) -> String {
    let message = cleanedRiskFocusText(card.message, limit: 140)
    if !message.isEmpty && !isGenericRiskFocus(message) {
        return message
    }
    if let focus = riskConcreteFocusText(for: card).map(riskShareFocusText),
       !focus.isEmpty {
        return isMissingRiskFocusText(focus) ? missingRiskFocusSummary(for: card) : "请核对\(focus)"
    }
    if let sourceExcerpt = riskSourceExcerptPreview(for: card) {
        return sourceExcerpt
    }
    return riskActionableSummaryText(for: card)
}

func riskCommunicationFocusLine(for card: StoredRiskCard, summary: String) -> String? {
    guard let focus = riskConcreteFocusText(for: card).map(riskShareFocusText),
          !focus.isEmpty,
          !isMissingRiskFocusText(focus),
          !riskText(summary, containsRiskFragment: focus)
    else {
        return nil
    }
    return "需要核对：\(focus)"
}

func riskCommunicationEvidenceLine(for card: StoredRiskCard, summary: String) -> String? {
    guard let sourceExcerpt = riskSourceExcerptPreview(for: card),
          !riskText(summary, containsRiskFragment: sourceExcerpt)
    else {
        return nil
    }
    if let focus = riskConcreteFocusText(for: card).map(riskShareFocusText),
       riskText(focus, containsRiskFragment: sourceExcerpt) {
        return nil
    }
    return "依据片段：\(sourceExcerpt)"
}

func riskText(_ text: String, containsRiskFragment fragment: String) -> Bool {
    let normalizedText = normalized(text)
    let fragments = [
        fragment,
        riskCompactTitleFocusText(fragment)
    ]
    return fragments.contains { value in
        let normalizedFragment = normalized(value)
        return !normalizedFragment.isEmpty && normalizedText.contains(normalizedFragment)
    }
}

func extractedRiskFocus(from card: StoredRiskCard) -> String {
    let titleFocus = riskFocusFromReviewTitle(card.title)
    if !titleFocus.isEmpty {
        return titleFocus
    }
    if let sourceExcerpt = riskSourceExcerptPreview(for: card) {
        return sourceExcerpt
    }
    let message = cleanedRiskFocusText(card.message, limit: 72)
    if isGenericRiskFocus(message) {
        return ""
    }
    return message
}

func riskFocusFromReviewTitle(_ title: String) -> String {
    guard let separatorIndex = title.firstIndex(of: "：") ?? title.firstIndex(of: ":") else {
        return ""
    }
    return cleanedRiskFocusText(String(title[title.index(after: separatorIndex)...]), limit: 48)
}

func riskSourceExcerptPreview(for card: StoredRiskCard) -> String? {
    let excerpt = cleanedRiskFocusText(card.sourceExcerpt, limit: 96)
    return excerpt.isEmpty ? nil : excerpt
}

func cleanedRiskFocusText(_ text: String, limit: Int) -> String {
    let collapsed = text
        .split(whereSeparator: \.isNewline)
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
        .joined(separator: " ")
        .replacingOccurrences(of: "说明书“", with: "")
        .replacingOccurrences(of: "”指出：", with: "：")
        .replacingOccurrences(of: "请咨询医生或药师", with: "")
        .trimmingCharacters(in: .whitespacesAndNewlines)
    guard !collapsed.isEmpty else {
        return ""
    }
    guard collapsed.count > limit else {
        return collapsed
    }
    let endIndex = collapsed.index(collapsed.startIndex, offsetBy: limit)
    return String(collapsed[..<endIndex]).trimmingCharacters(in: .whitespacesAndNewlines) + "…"
}

func isGenericRiskFocus(_ text: String) -> Bool {
    let normalizedText = normalized(text)
    return normalizedText.isEmpty
        || normalizedText == "相关风险"
        || normalizedText == "相关警示"
        || normalizedText == "相关提醒"
        || normalizedText.contains("已根据药品资料和用户记录生成用药风险提醒")
}

func riskCategoryIconName(for card: StoredRiskCard) -> String {
    switch RiskAssessmentCardKind(rawValue: card.kindRaw) ?? .labelRisk {
    case .foodReview:
        return "fork.knife"
    case .healthConditionReview:
        return "heart.text.square"
    case .medicationSourceReview:
        return "doc.badge.exclamationmark"
    case .drugClassContext:
        return "tag.fill"
    case .labelRisk:
        let grouped = RiskReviewGrouper().mappedGroup(for: card.coreRiskCard)
        switch grouped {
        case .drugInteraction:
            return "pills.fill"
        case .foodAndLifestyleInteraction:
            return "fork.knife"
        case .conditionAndSymptomAttention:
            return "heart.text.square"
        }
    }
}

func riskCategoryTint(for card: StoredRiskCard) -> Color {
    switch RiskAssessmentCardKind(rawValue: card.kindRaw) ?? .labelRisk {
    case .foodReview:
        return RiskPalette.teal
    case .healthConditionReview:
        return RiskPalette.rose
    case .medicationSourceReview:
        return RiskPalette.amber
    case .drugClassContext:
        return RiskPalette.indigo
    case .labelRisk:
        let grouped = RiskReviewGrouper().mappedGroup(for: card.coreRiskCard)
        switch grouped {
        case .drugInteraction:
            return RiskPalette.indigo
        case .foodAndLifestyleInteraction:
            return RiskPalette.teal
        case .conditionAndSymptomAttention:
            return RiskPalette.rose
        }
    }
}

func riskSourceText(for card: StoredRiskCard) -> String {
    if card.id.contains("-\(MedicationRiskReviewService.userLabelRiskIDPrefix)-") {
        return "用户导入说明书"
    }
    if card.kindRaw == RiskAssessmentCardKind.medicationSourceReview.rawValue {
        return "药品来源复核"
    }
    if card.kindRaw == RiskAssessmentCardKind.drugClassContext.rawValue {
        return "药品类别信息"
    }
    if !card.sourceTitle.isEmpty || !card.sourceExcerpt.isEmpty {
        return "说明书资料"
    }
    return "本地规则"
}

func sourceTint(for card: StoredRiskCard) -> Color {
    if card.id.contains("-\(MedicationRiskReviewService.userLabelRiskIDPrefix)-") {
        return RiskPalette.green
    }
    if card.kindRaw == RiskAssessmentCardKind.medicationSourceReview.rawValue {
        return RiskPalette.amber
    }
    if card.kindRaw == RiskAssessmentCardKind.drugClassContext.rawValue {
        return RiskPalette.indigo
    }
    return .secondary
}
