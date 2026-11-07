import Foundation

public struct MedicalAIRequestPromptBuilder: Sendable {
    public init() {}

    public func buildPrompt(for request: MedicalAIRequest) -> String {
        // Standalone social/capability turns do not need authorized medical
        // context. Keep generation real, but prevent unsolicited data recaps.
        let question = request.userMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        let conversational = [
            #"^(?:hi|hello|hey|你好|您好|嗨|早上好|晚上好)[！!。？?\s]*$"#,
            #"^(?:你|您)(?:能|可以)(?:帮我)?(?:做什么|干什么|干些什么|做些什么|提供什么帮助)[？?。！!\s]*$"#,
            #"^(?:请)?(?:介绍|说说)(?:一下)?(?:你自己|自己|你的功能|功能)[？?。！!\s]*$"#
        ]
        if request.kind == .chat, conversational.contains(where: {
            question.range(of: $0, options: [.regularExpression, .caseInsensitive]) != nil
        }) {
            return """
            你是 MedCue 健康助手，可以解释一般健康与用药知识、帮助理解说明书、整理用药记录和复诊沟通要点，不能代替医生诊断或开处方。
            只回应当前问题，简短自然。问候时友好问候并邀请交流；问功能时简述能提供的帮助。不要附带药品清单、数量、风险警告或个人情况摘要，也不要索要身份信息。无需个人资料，不要回答资料不足。
            用户问题：\(question)
            请直接给出中文回答。
            """
        }
        var lines: [String] = []
        lines.append("你是 MedCue 健康助手。请直接回答当前问题，不主动展开无关资料。一般健康知识可直接解释；涉及用户本人的情况只使用已授权共享的数据。可提供风险提示、依从性提醒、说明书可读化解释和复诊沟通建议。")
        lines.append("安全边界：不能替代医生或药师判断；如涉及治疗决策、症状加重或不确定风险，应建议咨询医生或药师。")
        lines.append("输出要求：使用用户要求的语言，按问题需要简明回答；查询用药情况时先总结已记录、待处理和已忽略状态；可以使用简洁 Markdown 标题和列表，用户要求表格时使用 Markdown 表格；不要使用 LaTeX 或表情符号；不要索要身份信息。")
        lines.append("")
        lines.append("请求类型：\(displayName(for: request.kind))")
        lines.append("用户问题：\(request.userMessage)")
        lines.append(Self.conversationContext(for: request))
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

        if !request.environmentInsights.isEmpty {
            lines.append("")
            lines.append("今日环境关注：")
            lines.append("回答天气、环境、气温、湿度、降水、风或紫外线相关问题时，必须优先结合这些环境关注和已授权用药数据，避免只给泛泛提醒。")
            for insight in request.environmentInsights.prefix(4) {
                lines.append("- \(limited(insight.title, maxLength: 80))（\(limited(insight.severityText, maxLength: 20))）：\(limited(insight.message, maxLength: 220))")
                if !insight.sourceSummary.isEmpty {
                    lines.append("  - 环境来源：\(limited(insight.sourceSummary, maxLength: 120))")
                }
            }
        }

        if let importReview = request.importReview {
            lines.append("")
            lines.append("导入识别内容核对：")
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

    public static func conversationContext(for request: MedicalAIRequest) -> String {
        let turns = (request.conversation ?? []).suffix(4)
            .filter { $0.role == "user" || $0.role == "assistant" }
        guard !turns.isEmpty else { return "" }
        return "近期对话（仅帮助理解指代，不是当前用药事实；事实以本次记录为准）：\n" + turns.map {
            "\($0.role == "user" ? "用户" : "助手")：\(String($0.text.prefix(240)))"
        }.joined(separator: "\n")
    }

    private func append(snapshot: MedicalAIMedicationSnapshot, index: Int, to lines: inout [String]) {
        let medication = snapshot.medication
        lines.append("")
        lines.append("\(index). \(MedicationNamePolicy.aiDisplayName(for: medication))")
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
                let sourceNote = plan.sourceNote.trimmingCharacters(in: .whitespacesAndNewlines)
                let sourceSuffix = sourceNote.isEmpty ? "" : "，备注：\(limited(sourceNote, maxLength: 180))"
                lines.append("  - \(plan.dose.value) \(plan.dose.unit)，\(String(describing: plan.timingRule))\(sourceSuffix)")
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
            lines.append("- 风险提醒：")
            snapshot.riskCards.prefix(8).forEach { card in
                lines.append("  - \(card.title)：\(limited(card.message, maxLength: 240))")
                if let evidence = card.evidence {
                    if !evidence.sourceTitle.isEmpty {
                        lines.append("    - 来源章节：\(limited(evidence.sourceTitle, maxLength: 80))")
                    }
                    if !evidence.excerpt.isEmpty {
                        lines.append("    - 依据片段：\(limited(evidence.excerpt, maxLength: 180))")
                    }
                }
                if card.requiresProfessionalReview {
                    lines.append("    - 建议咨询医生或药师")
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
            return "医嘱图片导入核对"
        case .barcodeImportReview:
            return "药盒条码导入核对"
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
