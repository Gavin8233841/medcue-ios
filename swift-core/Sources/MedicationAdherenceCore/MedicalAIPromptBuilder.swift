import Foundation

public struct MedicalAIRequestPromptBuilder: Sendable {
    public init() {}

    public func buildPrompt(for request: MedicalAIRequest) -> String {
        var lines: [String] = []
        lines.append("你是依法提供医疗服务能力的医疗 AI 模型。请只基于用户已授权共享的数据，输出风险提示、依从性提醒、说明书可读化解释和复诊沟通建议。")
        lines.append("安全边界：不能替代医生或药师判断；如涉及治疗决策、症状加重或不确定风险，应建议咨询医生或药师。")
        lines.append("输出要求：中文，100字以内；只用纯文字和常规标点；不要使用 Markdown、LaTeX、表格、列表符号或表情符号；不要索要身份信息。")
        lines.append("")
        lines.append("请求类型：\(displayName(for: request.kind))")
        lines.append("用户问题：\(request.userMessage)")
        lines.append("授权说明：\(request.authorization.note.isEmpty ? "用户已授权本次请求所需范围。" : request.authorization.note)")
        lines.append("生成时间：\(iso8601.string(from: request.createdAt))")

        if request.medicationSnapshots.isEmpty {
            lines.append("")
            lines.append("授权数据：本次请求未包含药品快照。")
        } else {
            lines.append("")
            lines.append("已授权药品快照：")
            for (index, snapshot) in request.medicationSnapshots.enumerated() {
                append(snapshot: snapshot, index: index + 1, to: &lines)
            }
        }

        if let importReview = request.importReview {
            lines.append("")
            lines.append("导入草稿复核：")
            lines.append("- 来源：\(importReview.draft.source.rawValue)")
            if !importReview.draft.confidenceByField.isEmpty {
                let confidenceSummary = importReview.draft.confidenceByField
                    .map { "\($0.key.rawValue): \($0.value)" }
                    .sorted()
                    .joined(separator: "，")
                lines.append("- 字段置信度：\(confidenceSummary)")
            }
            lines.append("- 可创建药品：\(importReview.canCreateMedication ? "是" : "否")")
            importReview.issues.prefix(6).forEach { issue in
                lines.append("- \(issue.message)")
            }
        }

        lines.append("")
        lines.append("请在回答末尾保留一句边界提示：以上内容仅用于用药风险提示和复诊沟通，不能替代医生或药师判断。")
        return lines.joined(separator: "\n")
    }

    private func append(snapshot: MedicalAIMedicationSnapshot, index: Int, to lines: inout [String]) {
        let medication = snapshot.medication
        lines.append("")
        lines.append("\(index). \(medication.displayName)")
        if let genericName = medication.genericName, !genericName.isEmpty {
            lines.append("- 通用名：\(genericName)")
        }
        lines.append("- 类型：\(medication.kind.rawValue)")
        if let strength = medication.strength, !strength.isEmpty {
            lines.append("- 规格：\(strength)")
        }
        if let form = medication.form, !form.isEmpty {
            lines.append("- 剂型：\(form)")
        }
        if !medication.notes.isEmpty {
            lines.append("- 用户备注：\(limited(medication.notes, maxLength: 360))")
        }

        if !snapshot.plans.isEmpty {
            lines.append("- 提醒计划：")
            snapshot.plans.prefix(6).forEach { plan in
                lines.append("  - \(plan.dose.value) \(plan.dose.unit)，\(String(describing: plan.timingRule))，来源：\(limited(plan.sourceNote, maxLength: 180))")
            }
        }

        if !snapshot.scheduledDoses.isEmpty || !snapshot.doseEvents.isEmpty {
            lines.append("- 服药记录：")
            snapshot.scheduledDoses.prefix(12).forEach { dose in
                lines.append("  - 计划：\(iso8601.string(from: dose.dueAt))，\(dose.dose.value) \(dose.dose.unit)")
            }
            snapshot.doseEvents.prefix(12).forEach { event in
                let reason = event.reason.map { "，原因：\(limited($0, maxLength: 120))" } ?? ""
                lines.append("  - 结果：\(event.status.rawValue)，记录于 \(iso8601.string(from: event.recordedAt))\(reason)")
            }
        }

        if !snapshot.riskCards.isEmpty {
            lines.append("- 风险卡片：")
            snapshot.riskCards.prefix(8).forEach { card in
                lines.append("  - \(card.title)：\(limited(card.message, maxLength: 240))")
                if card.requiresProfessionalReview {
                    lines.append("    - 需要医生或药师复核")
                }
            }
        }

        if let labelSummary = snapshot.labelSummary {
            lines.append("- 说明书摘要：")
            labelSummary.cards.prefix(6).forEach { card in
                lines.append("  - \(card.heading)：\(limited(card.plainLanguageNote, maxLength: 240))")
            }
        }
    }

    private func displayName(for kind: MedicalAIRequestKind) -> String {
        switch kind {
        case .chat:
            return "对话"
        case .riskOptimization:
            return "风险提醒优化"
        case .prescriptionOCRReview:
            return "医嘱 OCR 导入复核"
        case .barcodeImportReview:
            return "药盒条码导入复核"
        }
    }

    private func limited(_ value: String, maxLength: Int) -> String {
        guard value.count > maxLength else {
            return value
        }
        let end = value.index(value.startIndex, offsetBy: maxLength)
        return String(value[..<end]) + "..."
    }

    private var iso8601: ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }
}
