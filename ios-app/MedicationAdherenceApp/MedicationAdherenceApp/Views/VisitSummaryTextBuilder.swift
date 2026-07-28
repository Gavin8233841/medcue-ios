import Foundation
import MedicationAdherenceCore
import SwiftData

struct VisitSummaryTextBuilder {
    func build(
        medications: [StoredMedication],
        tasks: [StoredDoseTask],
        riskCards: [StoredRiskCard],
        startDate: Date,
        endDate: Date,
        generatedAt: Date
    ) -> String {
        var lines: [String] = []
        let medicationsByID = Dictionary(uniqueKeysWithValues: medications.map { ($0.id, $0) })
        let tasksByMedicationID = Dictionary(grouping: tasks, by: \.medicationID)
        var takenTotal = 0
        var skippedTotal = 0
        var delayedTotal = 0
        for task in tasks {
            switch task.status {
            case .taken, .corrected:
                takenTotal += 1
            case .skipped:
                skippedTotal += 1
            case .delayed:
                delayedTotal += 1
            case .pending:
                break
            }
        }
        lines.append("复诊沟通摘要")
        lines.append("")
        lines.append("日期范围：\(VisitSummaryDateRange.displayText(startDate: startDate, endDate: endDate))")
        lines.append("生成时间：\(AppFormatters.day.string(from: generatedAt)) \(AppFormatters.time.string(from: generatedAt))")
        lines.append("")

        let medicationCount = Set(tasks.map(\.medicationID)).count
        let completionRate = tasks.isEmpty ? 0 : Int((Double(takenTotal) / Double(tasks.count) * 100).rounded())
        lines.append("摘要：期间记录 \(medicationCount) 种药物，应服 \(tasks.count) 次，已服用 \(takenTotal) 次，忽略 \(skippedTotal) 次，稍后 \(delayedTotal) 次，记录服用率 \(completionRate)%。")
        lines.append("")

        if medications.isEmpty {
            lines.append("用药记录")
            lines.append("暂无药品记录。")
        } else {
            lines.append("用药记录")
            for medication in medications {
                let relatedTasks = tasksByMedicationID[medication.id] ?? []
                guard !relatedTasks.isEmpty else { continue }
                let takenCount = relatedTasks.filter { $0.status == .taken || $0.status == .corrected }.count
                let skippedCount = relatedTasks.filter { $0.status == .skipped }.count
                let delayedCount = relatedTasks.filter { $0.status == .delayed }.count
                let rate = Int((Double(takenCount) / Double(max(relatedTasks.count, 1)) * 100).rounded())
                lines.append("\(userFacingMedicationName(for: medication))：计划 \(relatedTasks.count) 次，完成 \(takenCount) 次，完成率 \(rate)%，忽略 \(skippedCount) 次，稍后 \(delayedCount) 次。")
                let exceptionNotes = relatedTasks
                    .filter { $0.status == .skipped || $0.status == .delayed }
                    .prefix(3)
                    .map { task in
                        "\(AppFormatters.day.string(from: task.effectiveAdherenceDate)) \(task.status == .skipped ? "忽略" : "稍后")"
                    }
                if !exceptionNotes.isEmpty {
                    lines.append("需沟通节点：\(exceptionNotes.joined(separator: "；"))。")
                }
            }
        }

        lines.append("")
        lines.append("所选时间段记录")
        let calendar = Calendar.current
        let recentTasks = tasks
            .filter { $0.effectiveAdherenceDate >= startDate && $0.effectiveAdherenceDate <= endDate }
            .sorted { $0.effectiveAdherenceDate < $1.effectiveAdherenceDate }
        let groupedByWeek = Dictionary(grouping: recentTasks) { task -> Date in
            let interval = calendar.dateInterval(of: .weekOfYear, for: task.effectiveAdherenceDate)
            return interval?.start ?? calendar.startOfDay(for: task.effectiveAdherenceDate)
        }
        for weekStart in groupedByWeek.keys.sorted() {
            let weekTasks = groupedByWeek[weekStart] ?? []
            let takenCount = weekTasks.filter { $0.status == .taken || $0.status == .corrected }.count
            let delayedCount = weekTasks.filter { $0.status == .delayed }.count
            let skipped = weekTasks.filter { $0.status == .skipped }
            lines.append("\(AppFormatters.day.string(from: weekStart)) 周：计划 \(weekTasks.count) 次，完成 \(takenCount) 次，稍后 \(delayedCount) 次，忽略 \(skipped.count) 次。")
            let exceptions = weekTasks
                .filter { $0.status == .skipped || $0.status == .delayed }
                .prefix(8)
            for task in exceptions {
                let medicationName = medicationsByID[task.medicationID].map(userFacingMedicationName(for:)) ?? "未知药品"
                let action = task.status == .skipped ? "忽略" : "稍后"
                let displayDate = task.effectiveAdherenceDate
                lines.append("- \(AppFormatters.day.string(from: displayDate)) \(AppFormatters.time.string(from: displayDate))：\(medicationName) \(action)。")
            }
        }

        lines.append("")
        lines.append("风险提示")
        let importantRiskCards = riskCards.filter { $0.requiresProfessionalReview && $0.isActive }.prefix(6)
        if importantRiskCards.isEmpty {
            lines.append("暂无需要优先沟通的风险提醒。")
        } else {
            for card in importantRiskCards {
                let medicationName = medicationsByID[card.medicationID].map(userFacingMedicationName(for:)) ?? "未知药品"
                lines.append("\(medicationName)：\(summaryRiskDisplayTitle(for: card, limit: 48))。\(summaryRiskFocusText(for: card))")
            }
        }

        return lines.joined(separator: "\n")
    }

    private func summaryRiskFocusText(for card: StoredRiskCard) -> String {
        if let focus = summaryRiskConcreteFocusText(for: card, limit: 96) {
            return focus
        }
        let message = summaryTrimmedText(card.message, limit: 96)
        return message.isEmpty ? "需补充说明书或向医生或药师确认具体对象。" : message
    }

    private func summaryRiskDisplayTitle(for card: StoredRiskCard, limit: Int) -> String {
        let rawTitle = summaryTrimmedText(card.title, limit: limit)
        guard summaryIsGenericRiskFocus(rawTitle) || rawTitle == "警示信息" || rawTitle == "注意事项" else {
            return rawTitle.isEmpty ? summaryRiskCategoryTitle(for: card) : rawTitle
        }
        let category = summaryIsContraindicationRisk(card) ? "禁忌或慎用" : summaryRiskCategoryTitle(for: card)
        guard let focus = summaryRiskConcreteFocusText(for: card, limit: limit),
              !focus.isEmpty
        else {
            return category
        }
        return summaryTrimmedText("\(category)：\(summaryRiskShareFocusText(focus))", limit: limit)
    }

    private func summaryRiskConcreteFocusText(for card: StoredRiskCard, limit: Int) -> String? {
        let focus = summaryExtractedRiskFocus(from: card, limit: limit)
        switch RiskAssessmentCardKind(rawValue: card.kindRaw) ?? .labelRisk {
        case .foodReview:
            return focus.isEmpty ? "需核对具体饮食或生活方式。" : "核对饮食或生活方式：\(focus)"
        case .healthConditionReview:
            return focus.isEmpty ? "需核对具体病症或症状。" : "核对病症或症状：\(focus)"
        case .medicationSourceReview:
            return focus.isEmpty ? "需按药盒、说明书或医嘱核对来源。" : "核对来源：\(focus)"
        case .drugClassContext:
            return focus.isEmpty ? nil : "药品类别：\(focus)"
        case .labelRisk:
            let group = RiskReviewGrouper().mappedGroup(for: card.coreRiskCard)
            if summaryIsContraindicationRisk(card) {
                return focus.isEmpty ? "需核对禁忌条件，当前资料未写明具体对象。" : "核对禁忌条件：\(focus)"
            }
            switch group {
            case .drugInteraction:
                return focus.isEmpty ? "需核对合用药品，当前资料未写明具体名称。" : "核对合用药品：\(focus)"
            case .foodAndLifestyleInteraction:
                return focus.isEmpty ? "需核对具体饮食或生活方式。" : "核对饮食或生活方式：\(focus)"
            case .conditionAndSymptomAttention:
                return focus.isEmpty ? "需核对具体病症或症状。" : "核对病症或症状：\(focus)"
            }
        }
    }

    private func summaryExtractedRiskFocus(from card: StoredRiskCard, limit: Int) -> String {
        let titleFocus = summaryRiskFocusFromReviewTitle(card.title, limit: limit)
        if !titleFocus.isEmpty {
            return titleFocus
        }
        let sourceExcerpt = summaryTrimmedText(card.sourceExcerpt, limit: limit)
        if !sourceExcerpt.isEmpty {
            return sourceExcerpt
        }
        let message = summaryTrimmedText(card.message, limit: limit)
        return summaryIsGenericRiskFocus(message) ? "" : message
    }

    private func summaryRiskFocusFromReviewTitle(_ title: String, limit: Int) -> String {
        guard let separatorIndex = title.firstIndex(of: "：") ?? title.firstIndex(of: ":") else {
            return ""
        }
        return summaryTrimmedText(String(title[title.index(after: separatorIndex)...]), limit: limit)
    }

    private func summaryRiskShareFocusText(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("需核对") else {
            return trimmed
        }
        return String(trimmed.dropFirst("需核对".count))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func summaryRiskCategoryTitle(for card: StoredRiskCard) -> String {
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
            switch RiskReviewGrouper().mappedGroup(for: card.coreRiskCard) {
            case .drugInteraction:
                return "相互作用"
            case .foodAndLifestyleInteraction:
                return "饮食注意"
            case .conditionAndSymptomAttention:
                return "病症注意"
            }
        }
    }

    private func summaryTrimmedText(_ text: String, limit: Int) -> String {
        let normalized = text
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "说明书“", with: "")
            .replacingOccurrences(of: "”指出：", with: "：")
            .replacingOccurrences(of: "请咨询医生或药师", with: "")
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalized.count > limit else {
            return normalized
        }
        let index = normalized.index(normalized.startIndex, offsetBy: limit)
        return String(normalized[..<index]) + "..."
    }

    private func summaryIsContraindicationRisk(_ card: StoredRiskCard) -> Bool {
        let text = summaryNormalizedRiskText("\(card.title) \(card.message) \(card.sourceTitle) \(card.sourceExcerpt)")
        return text.contains("禁忌")
            || text.contains("禁用")
            || text.contains("contraindication")
            || text.contains("contraindicated")
            || text.contains("avoid")
    }

    private func summaryIsGenericRiskFocus(_ text: String) -> Bool {
        let normalizedText = summaryNormalizedRiskText(text)
        return normalizedText.isEmpty
            || normalizedText == "相关风险"
            || normalizedText == "相关警示"
            || normalizedText == "相关提醒"
            || normalizedText.contains("已根据药品资料和用户记录生成用药风险提醒")
    }

    private func summaryNormalizedRiskText(_ value: String) -> String {
        value
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
            .lowercased()
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .trimmingCharacters(in: .punctuationCharacters)
    }
}
