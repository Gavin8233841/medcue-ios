import Foundation
import MedicationAdherenceCore

struct LocalMedicalResponsePolicy: Sendable {
    func buildLocalPrompt(for request: MedicalAIRequest, answerPlan: LocalMedicalAnswerPlan) -> String {
        let facts: String
        if isEnglishSwitchOnly(request.userMessage) {
            facts = "本轮仅切换对话语言，不需要个人资料。"
        } else if isDiscomfortMessage(request.userMessage) {
            facts = "本次没有提供具体症状，不能从药品资料推断用户患病或出现某种反应。"
        } else if !needsPersonalRecords(for: request) {
            facts = "本题无需个人记录。助手可解释一般健康与用药知识、帮助理解说明书、整理用药记录和复诊沟通要点；不能代替医生诊断或开处方。"
        } else if isTakenTodayQuestion(request.userMessage) {
            let canRead = request.authorization.grantedScopes.contains(.doseEvents) && request.authorization.grantedScopes.contains(.medicationProfile)
            let rows = request.medicationSnapshots.compactMap { snapshot -> String? in
                let events = snapshot.doseEvents.filter { $0.status == .taken && Calendar.current.isDateInToday($0.recordedAt) }
                return events.isEmpty ? nil : "\(snapshot.medication.displayName)：今日已记录服用 \(events.count) 次"
            }
            facts = !canRead ? "本次未共享药品或服药记录，暂时看不到今天的服用情况" : (rows.isEmpty ? "今天没有已记录为服用的条目；不能把待服提醒或稍后记录当作已服用" : rows.joined(separator: "；"))
        } else if answerPlan.focus.contains("今日用药注意事项") {
            let names = explicitTodayMedicationText(in: request.userMessage)
                ?? todayPendingMedicationDisplayNames(for: request).prefix(4).joined(separator: "、")
            let summary = todayPendingDoseSummary(for: request)
            let risk = focusedTodayRiskLine(for: request)
            facts = [
                names.isEmpty ? "未提供今日待处理药品资料" : "今日待处理药品：\(names)",
                summary.isEmpty ? "未提供今日完成情况" : summary,
                risk.isEmpty ? "未提供风险卡片" : risk
            ].joined(separator: "；")
        } else if answerPlan.focus.contains("忽略或稍后趋势") {
            let trend = recentMissedDoseTrendSummary(for: request)
            facts = trend.isEmpty ? "未提供可用于判断趋势的忽略或稍后记录" : "过去14天：\(trend)"
        } else {
            facts = answerPlan.factSummary
        }
        return """
        你是 MedCue 健康助手。直接回应当前问题，根据问题提供足够信息，不强制只答一句。只有纯问候才回应问候；其他问题不要欢迎、自我介绍或邀请，也不要仿照历史中的寒暄。一般健康知识和日常交流可以直接回答，不需要个人资料。药名照抄原文，不翻译或改写英文药名。
        只有涉及用户本人的药品、数量、剂量、心率、库存和天气时，才依据已提供资料。缺少个人数据时，说明暂时看不到，并给出查看位置或一个有用的追问，不要只回答“资料不足”。不诊断、开处方或建议调整剂量。
        本轮要求：\(turnGuidance(for: request.userMessage))
        问题：\(localQuestionText(for: request.userMessage))
        \(MedicalAIRequestPromptBuilder.conversationContext(for: request))
        已提供资料：\(facts)
        只回答当前问题，回答完就结束。能力介绍只简述能提供的帮助；不要顺带列出用户药品、剂量或说明书警告。一般问答不必每次重新问候或追加邀请。
        直接回答所问内容，不要每次重复自我介绍和邀请。用户要求 Markdown 或表格时按要求排版，表格单元格简短，不附加无关风险；数量必须对应各自药品，不能把合计分配给某一种药。
        请直接回答，不输出思考过程或代码。
        """
    }

    private func isDiscomfortMessage(_ message: String) -> Bool {
        message.range(of: #"^(?:我(?:现在|感觉|觉得)?(?:不舒服|不好|难受)|身体不适)[啊呀了]?[。！？!?，,\s]*$"#, options: .regularExpression) != nil
    }

    private func isEnglishSwitchOnly(_ message: String) -> Bool {
        message.range(of: #"^\s*(?:(?:(?:let'?s|can we|please)\s+)?(?:speak|talk(?: in)?|use)\s+english|(?:请)?(?:用|说|换成|切换到)\s*(?:英文|英语)(?:聊天|回答)?)[。！？!?\s]*$"#, options: [.regularExpression, .caseInsensitive]) != nil
    }

    private func requestsEnglish(_ message: String) -> Bool {
        message.range(of: #"(?:speak|talk|use).{0,20}english|(?:用|说|换成|切换到).{0,4}(?:英文|英语)"#, options: [.regularExpression, .caseInsensitive]) != nil
    }

    private func turnGuidance(for message: String) -> String {
        if requestsEnglish(message) {
            return "Answer in English. Speak directly to the user, without describing your instructions or plans."
        }
        if isDiscomfortMessage(message) {
            return "用户表达不适，需要具体帮助而非寒暄。先回应感受，再问哪里不舒服、何时开始；若‘不好’含义不清，询问是身体还是情绪。不要猜疾病或药物原因，不给治疗方案。只对用户已描述的明显紧急症状建议及时就医。"
        }
        return "直接给出与问题有关的信息；不用欢迎语开头，不重复‘欢迎随时交流’。用户只问候时可简短问候。通常用中文；若用户指定其他语言，服从其要求。"
    }

    private func isTakenTodayQuestion(_ question: String) -> Bool {
        (question.contains("今天") || question.contains("今日")) && ["吃了", "吃过", "服用了", "已服用", "用了什么"].contains(where: question.contains)
    }

    private func needsPersonalRecords(for request: MedicalAIRequest) -> Bool {
        let question = localQuestionText(for: request.userMessage)
        // Exclude only clear standalone conversation. All other questions keep
        // the existing context path, including natural personal-record requests.
        let conversationalQuestions = [
            #"^(?:hi|hello|hey|你好|您好|嗨|早上好|晚上好)[！!。？?\s]*$"#,
            #"^(?:你|您)(?:能|可以)(?:帮我)?(?:做什么|干什么|干些什么|做些什么|提供什么帮助)[？?。！!\s]*$"#,
            #"^(?:请)?(?:介绍|说说)(?:一下)?(?:你自己|自己|你的功能|功能)[？?。！!\s]*$"#
        ]
        return !conversationalQuestions.contains {
            question.range(of: $0, options: [.regularExpression, .caseInsensitive]) != nil
        }
    }

    func buildRepairPrompt(for request: MedicalAIRequest, answerPlan: LocalMedicalAnswerPlan) -> String {
        buildLocalPrompt(for: request, answerPlan: answerPlan)
            + "\n请重新写成完整可读的回答，不重复问题或上述指令。"
    }

    func postprocessLocalResponse(_ value: String, request: MedicalAIRequest) -> String {
        let stoppedValue = cutAtStopMarkers(value)
        let thinking = [
            taggedContent(named: "think", in: stoppedValue),
            taggedContent(named: "thought", in: stoppedValue)
        ]
        .compactMap { $0 }
        .map(cleanReasoningText)
        .filter { !$0.isEmpty }
        .joined(separator: "\n\n")
        let withoutThinking = removingTaggedBlock(named: "thought", from: removingTaggedBlock(named: "think", from: stoppedValue))
        let finalCandidate = taggedContent(named: "final", in: withoutThinking)
            ?? textAfterFinalMarker(in: withoutThinking)
            ?? withoutThinking
        let cleaned = cleanFinalAnswerText(finalCandidate, request: request)
        let combinedThinking = [thinking]
            .map(cleanReasoningText)
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
        guard !cleaned.isEmpty, !combinedThinking.isEmpty else {
            return cleaned
        }
        return "\(cleaned)\(LocalMedicalAIClient.localReasoningSeparator)\(combinedThinking)"
    }

    private func cleanFinalAnswerText(_ value: String, request: MedicalAIRequest) -> String {
        // Remove transport wrappers, not natural-language sentences. Headings and
        // later warnings are part of the answer and must survive intact.
        let wrappers = ["<|im_start|>", "<|im_end|>", "</s>", "<final>", "</final>",
                        "<answer>", "</answer>", "<thought>", "</thought>", "<think>", "</think>"]
        var cleaned = value
        for wrapper in wrappers {
            cleaned = cleaned.replacingOccurrences(of: wrapper, with: "")
        }
        return cleaned
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func cleanReasoningText(_ value: String) -> String {
        value
            .replacingOccurrences(of: "<|im_start|>", with: "")
            .replacingOccurrences(of: "<|im_end|>", with: "")
            .replacingOccurrences(of: "</s>", with: "")
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func formalAnswerText(from message: String) -> String {
        message
            .components(separatedBy: LocalMedicalAIClient.localReasoningSeparator)
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    func reasoningText(from message: String) -> String {
        let components = message.components(separatedBy: LocalMedicalAIClient.localReasoningSeparator)
        guard components.count > 1 else {
            return ""
        }
        return components.dropFirst()
            .joined(separator: LocalMedicalAIClient.localReasoningSeparator)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func isLowQualityLocalResponse(_ response: String, request: MedicalAIRequest) -> Bool {
        let trimmed = response.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }

        // Only obvious machine output or leaked instructions trigger a rewrite.
        // Drug names, headings, polite wording and topic synonyms are valid prose.
        let garbagePatterns = [
            #"(?:^|\n)\s*(?:func |let |var |import |struct |class |return )"#,
            #"[\{\[]\s*"[^"]+"\s*:"#,
            #"(?:^|\n)\s*(?:当前任务|用户问题|回答焦点|事实边界)\s*[:：]"#,
            #"```(?:swift|python|javascript|json)"#,
            #"<(?:think|thought)(?:>|\s)"#
        ]
        if garbagePatterns.contains(where: { trimmed.range(of: $0, options: .regularExpression) != nil }) {
            return true
        }
        if let reviewed = try? MedicalAIResponseFinalizer().finalize(answer: trimmed),
           reviewed.boundaryBlockedAction {
            return true
        }
        // Catch direct colloquial treatment commands too, independently of whether
        // the medicine happens to have a Chinese or English name.
        let treatmentCommand = #"(?:^|[。！？；;，,\n])\s*(?:[-*•]|\d+[.)、])?\s*(?:今天|现在|你|您)?\s*(?:(?:建议|应该|应当|请|立即|先)\s*(?:吃|服用|停药|停用|暂停使用|停止使用|换药|增加剂量|减少剂量|加量|减量)|请勿继续使用)"#
        return trimmed.range(of: treatmentCommand, options: .regularExpression) != nil
    }

    func isOffTopicLocalResponse(_ response: String, answerPlan: LocalMedicalAnswerPlan) -> Bool {
        // A keyword miss cannot establish that a natural-language answer is off topic.
        response.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func localIntentTitle(for userMessage: String) -> String {
        if userMessage.contains("图片") || userMessage.contains("上传") || userMessage.contains("拍照") {
            return "图片录入建议"
        }
        if userMessage.contains("天气") || userMessage.contains("环境") {
            return "天气与环境用药关注"
        }
        if userMessage.contains("复诊") {
            return "复诊沟通整理"
        }
        if userMessage.contains("库存") || userMessage.contains("药盒") {
            return "药盒与库存提醒"
        }
        if userMessage.contains("今日提醒药品") || userMessage.contains("今日待处理药品") {
            return "今日重点核对"
        }
        if userMessage.contains("风险") || userMessage.contains("说明书") {
            return "风险与说明书重点"
        }
        if userMessage.contains("趋势") || userMessage.contains("稍后") || userMessage.contains("忽略") {
            return "服药记录趋势"
        }
        if userMessage.contains("今日") || userMessage.contains("今天") {
            return "今日重点核对"
        }
        return "一般用药记录问题"
    }

    private func localQuestionText(for userMessage: String) -> String {
        let replacements = [
            "请只基于 App 内授权共享的": "",
            "App 内授权共享的": "",
            "请结合今日天气与环境提示和": "",
            "复核": "核对"
        ]
        var text = userMessage
        for (source, replacement) in replacements {
            text = text.replacingOccurrences(of: source, with: replacement)
        }
        return limited(text.trimmingCharacters(in: .whitespacesAndNewlines), maxLength: 72)
    }

    func localAnswerPlan(for request: MedicalAIRequest) -> LocalMedicalAnswerPlan {
        let intent = localIntentTitle(for: request.userMessage)
        let facts = compactLocalFactSummary(for: request)
        let medicationNames = medicationDisplayNames(for: request)
        let todayNames = todayMedicationDisplayNames(for: request)
        let risks = riskSummary(for: request)
        let recent = recentDoseEventSummary(for: request)

        if intent.contains("天气") || intent.contains("环境") {
            let environment = request.environmentInsights.first.map { insight in
                "\(limited(insight.title, maxLength: 18))：\(limited(insight.message, maxLength: 80))"
            }
            let answer = environment.map {
                "今天先留意环境变化：\($0)。按原提醒记录用药；如果出现不适、漏服或症状变化，把时间和情况补充到记录里，必要时咨询医生或药师。"
            } ?? "今天没有可用的天气或环境提示。你可以继续按提醒记录用药；如果出现不适、漏服或症状变化，把时间和情况补充到记录里。"
            return LocalMedicalAnswerPlan(
                focus: "回答今天环境变化与用药记录需要留意什么",
                factSummary: facts,
                factGuidance: answer,
                requiredFragments: ["环境", "天气"]
            )
        }

        if intent == "服药记录趋势" {
            let missedTrend = recentMissedDoseTrendSummary(for: request)
            let answer = missedTrend.isEmpty
                ? "近 14 天没有可用的服药记录趋势。建议先补全漏服、稍后和已服用记录，之后再查看节奏变化。"
                : "近 14 天忽略或稍后记录显示：\(missedTrend)。可以优先回看忽略或稍后的原因，把容易错过的时段调整成更容易完成的提醒。"
            return LocalMedicalAnswerPlan(
                focus: "回答近期忽略或稍后趋势",
                factSummary: missedTrend.isEmpty ? facts : "近14天记录显示，\(missedTrend)",
                factGuidance: answer,
                requiredFragments: ["趋势", "忽略", "稍后"]
            )
        }

        if intent.contains("风险") || intent.contains("说明书") {
            let labelText = labelSummaryText(for: request)
            let answer: String
            if !risks.isEmpty, !labelText.isEmpty {
                answer = "当前最需要复核的是：\(risks)。说明书重点可先看：\(labelText)。这些只用于整理线索，具体判断请咨询医生或药师。"
            } else if !risks.isEmpty {
                answer = "当前最需要复核的是：\(risks)。建议打开风险卡片逐条核对来源和相关药品，重要决定请咨询医生或药师。"
            } else if !labelText.isEmpty {
                answer = "说明书里可先看：\(labelText)。这些内容只帮助你理解来源文本，不能替代医生或药师判断。"
            } else {
                answer = "当前本地记录里没有可用的风险卡片或说明书摘要。可以先补充说明书或药品信息，再让智能体整理重点。"
            }
            return LocalMedicalAnswerPlan(
                focus: "回答风险或说明书重点",
                factSummary: facts,
                factGuidance: answer,
                requiredFragments: ["风险", "说明书", "复核", "药师"]
            )
        }

        if intent.contains("复诊") {
            let medicationText = medicationNames.isEmpty ? "当前药品" : medicationNames.prefix(4).joined(separator: "、")
            let recentText = recent.isEmpty ? "近期服药记录还不完整" : "近 14 天记录：\(recent)"
            let riskText = risks.isEmpty ? "暂无明确风险卡片需要单独说明" : "需要复核的风险：\(risks)"
            return LocalMedicalAnswerPlan(
                focus: "回答复诊沟通时可以说明什么",
                factSummary: facts,
                factGuidance: "复诊时可先说明正在记录的药品：\(medicationText)。\(recentText)；\(riskText)。如果有漏服、稍后或不适，把发生时间和原因一起带给医生或药师。",
                requiredFragments: ["复诊", "记录", "风险", "医生"]
            )
        }

        if intent.contains("库存") || intent.contains("药盒") {
            let medicationText = medicationNames.isEmpty ? "当前没有可用药品名称" : medicationNames.prefix(4).joined(separator: "、")
            return LocalMedicalAnswerPlan(
                focus: "回答药盒与库存管理注意事项",
                factSummary: facts,
                factGuidance: "当前可先核对这些药品的药盒和余量：\(medicationText)。如果本地没有明确库存或药盒编号，请按药盒实物补充；低量、过期或包装不清楚时，先标记并复核后再继续使用。",
                requiredFragments: ["药盒", "库存", "余量", "核对"]
            )
        }

        if request.userMessage.contains("图片") || request.userMessage.contains("上传") || request.userMessage.contains("拍照") {
            return LocalMedicalAnswerPlan(
                focus: "回答如何整理药品图片信息",
                factSummary: facts,
                factGuidance: "你可以上传药盒、药品或说明书图片，让 App 先识别文字，再在录入页核对药名、通用名、规格、剂量和说明书重点。保存前请按实物逐项确认，识别结果不要直接当作最终结论。",
                requiredFragments: ["图片", "识别", "核对", "录入"]
            )
        }

        if !intent.contains("今日") {
            return LocalMedicalAnswerPlan(
                focus: "回答用户的用药记录问题：\(localQuestionText(for: request.userMessage))",
                factSummary: facts,
                factGuidance: "直接解释问题涉及的记录或核对方法。涉及个人情况时只使用本次资料；资料不足就说明不足，不推断具体药品、数量或治疗方案。",
                requiredFragments: []
            )
        }

        let explicitTodayText = explicitTodayMedicationText(in: request.userMessage)
        let pendingTodayNames = explicitTodayText?.components(separatedBy: "、").filter { !$0.isEmpty }
            ?? todayPendingMedicationDisplayNames(for: request)
        let todayText = pendingTodayNames.isEmpty
            ? (todayNames.isEmpty ? "今天没有未处理提醒药品名称" : todayNames.prefix(5).joined(separator: "、"))
            : pendingTodayNames.prefix(4).joined(separator: "、")
        let todayStatus = todayPendingDoseSummary(for: request)
        let todayStatusText = todayStatus.isEmpty ? "今天还没有可用的完成、稍后或忽略记录" : "今日记录：\(todayStatus)"
        let concreteRisk = focusedTodayRiskLine(for: request)
        let riskText = concreteRisk.isEmpty ? "目前没有明确风险卡片需要单独提示" : concreteRisk
        return LocalMedicalAnswerPlan(
            focus: "回答今日用药注意事项",
            factSummary: "今日待处理药品：\(todayText)；\(todayStatusText)；风险线索：\(riskText)",
            factGuidance: "今天先核对待处理药品：\(todayText)。\(todayStatusText)。最需要留意：\(riskText)。完成、稍后、忽略或不适都及时记录。",
            requiredFragments: pendingTodayNames.isEmpty ? ["今天", "记录"] : Array(pendingTodayNames.prefix(2))
        )
    }

    private func labelSummaryText(for request: MedicalAIRequest) -> String {
        let cards = request.medicationSnapshots
            .compactMap(\.labelSummary)
            .flatMap(\.cards)
            .filter { card in
                card.kind == .warnings
                    || card.kind == .interactions
                    || card.kind == .directions
                    || card.kind == .adverseReactions
            }
            .prefix(3)
            .map { card in
                let source = limited(card.sourceTitle, maxLength: 12)
                let excerpt = limited(cleanRiskExcerpt(card.sourceExcerpt), maxLength: 52)
                return excerpt.isEmpty ? source : "\(source)：\(excerpt)"
            }
        return cards.joined(separator: "；")
    }

    private func medicationDisplayNames(for request: MedicalAIRequest) -> [String] {
        request.medicationSnapshots
            .prefix(6)
            .map { snapshot in
                let medication = snapshot.medication
                let generic = medication.genericName?.trimmingCharacters(in: .whitespacesAndNewlines)
                if let generic, !generic.isEmpty, generic != medication.displayName {
                    return "\(medication.displayName)(\(generic))"
                }
                return medication.displayName
            }
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    private func doseEventSummary(for request: MedicalAIRequest) -> String {
        recentDoseEventSummary(for: request)
    }

    private func recentDoseEventSummary(for request: MedicalAIRequest) -> String {
        let lookbackDays = MedicalAIExecutionPolicy.default.trendLookbackDays
        let cutoff = Calendar.current.date(byAdding: .day, value: -lookbackDays, to: Date())
            ?? Date().addingTimeInterval(TimeInterval(-lookbackDays * 24 * 60 * 60))
        let events = request.medicationSnapshots
            .flatMap(\.doseEvents)
            .filter { $0.recordedAt >= cutoff }
        let takenCount = events.filter { $0.status == .taken }.count
        let delayedCount = events.filter { $0.status == .delayed }.count
        let skippedCount = events.filter { $0.status == .skipped }.count
        var parts: [String] = []
        if takenCount > 0 {
            parts.append("已完成 \(takenCount) 次")
        }
        if delayedCount > 0 {
            parts.append("稍后 \(delayedCount) 次")
        }
        if skippedCount > 0 {
            parts.append("忽略 \(skippedCount) 次")
        }
        return parts.joined(separator: "，")
    }

    private func recentMissedDoseTrendSummary(for request: MedicalAIRequest) -> String {
        let lookbackDays = MedicalAIExecutionPolicy.default.trendLookbackDays
        let cutoff = Calendar.current.date(byAdding: .day, value: -lookbackDays, to: Date())
            ?? Date().addingTimeInterval(TimeInterval(-lookbackDays * 24 * 60 * 60))
        var delayedTotal = 0
        var skippedTotal = 0
        var medicationParts: [String] = []
        for snapshot in request.medicationSnapshots {
            let events = snapshot.doseEvents.filter { $0.recordedAt >= cutoff }
            let delayedCount = events.filter { $0.status == .delayed }.count
            let skippedCount = events.filter { $0.status == .skipped }.count
            delayedTotal += delayedCount
            skippedTotal += skippedCount
            var pieces: [String] = []
            if delayedCount > 0 {
                pieces.append("稍后\(delayedCount)次")
            }
            if skippedCount > 0 {
                pieces.append("忽略\(skippedCount)次")
            }
            if !pieces.isEmpty {
                medicationParts.append("\(snapshot.medication.displayName)\(pieces.joined(separator: "、"))")
            }
        }
        var summary: [String] = []
        if delayedTotal > 0 {
            summary.append("稍后 \(delayedTotal) 次")
        }
        if skippedTotal > 0 {
            summary.append("忽略 \(skippedTotal) 次")
        }
        if medicationParts.isEmpty {
            return summary.joined(separator: "，")
        }
        let details = medicationParts.prefix(4).joined(separator: "；")
        return summary.isEmpty ? details : "\(summary.joined(separator: "，"))，主要出现在 \(details)"
    }

    private func todayDoseSummary(for request: MedicalAIRequest) -> String {
        let calendar = Calendar.current
        let scheduledCount = request.medicationSnapshots
            .flatMap(\.scheduledDoses)
            .filter { calendar.isDateInToday($0.dueAt) }
            .count
        let events = request.medicationSnapshots
            .flatMap(\.doseEvents)
            .filter { calendar.isDateInToday($0.recordedAt) }
        let takenCount = events.filter { $0.status == .taken }.count
        let delayedCount = events.filter { $0.status == .delayed }.count
        let skippedCount = events.filter { $0.status == .skipped }.count

        var parts: [String] = []
        if scheduledCount > 0 {
            parts.append("\(scheduledCount) 项提醒")
        }
        if takenCount > 0 {
            parts.append("已完成 \(takenCount) 次")
        }
        if delayedCount > 0 {
            parts.append("稍后 \(delayedCount) 次")
        }
        if skippedCount > 0 {
            parts.append("忽略 \(skippedCount) 次")
        }
        return parts.joined(separator: "，")
    }

    private func todayPendingDoseSummary(for request: MedicalAIRequest) -> String {
        let pendingNames = todayPendingMedicationDisplayNames(for: request)
        guard !pendingNames.isEmpty else {
            return ""
        }
        return "待处理 \(pendingNames.count) 项"
    }

    private func riskSummary(for request: MedicalAIRequest) -> String {
        var summaries: [String] = []
        for snapshot in request.medicationSnapshots {
            let medicationName = snapshot.medication.displayName
            for card in snapshot.riskCards.prefix(2) {
                let title = isGenericRiskTitle(card.title) ? "" : card.title
                let source = cleanRiskExcerpt(card.evidence?.excerpt ?? "")
                let message = cleanRiskExcerpt(card.message)
                let detail = source.isEmpty ? message : source
                let compactDetail = limited(detail, maxLength: 62)
                guard !compactDetail.isEmpty else {
                    continue
                }
                let prefix = title.isEmpty ? medicationName : "\(medicationName) \(title)"
                let summary = "\(prefix)：\(compactDetail)"
                if !summaries.contains(summary) {
                    summaries.append(summary)
                }
                if summaries.count >= 3 {
                    return summaries.joined(separator: "；")
                }
            }
        }
        return summaries.joined(separator: "；")
    }

    private func focusedTodayRiskLine(for request: MedicalAIRequest) -> String {
        let todayNames = Set(todayPendingMedicationDisplayNames(for: request).map { $0.components(separatedBy: "(").first ?? $0 })
        for snapshot in request.medicationSnapshots {
            let medicationName = snapshot.medication.displayName
            if !todayNames.isEmpty, !todayNames.contains(medicationName) {
                continue
            }
            if let labelCard = snapshot.labelSummary?.cards.first(where: { card in
                card.kind == .warnings || card.kind == .directions || card.kind == .adverseReactions
            }) {
                let excerpt = limited(cleanRiskExcerpt(labelCard.sourceExcerpt), maxLength: 58)
                if !excerpt.isEmpty {
                    return "\(medicationName)：\(excerpt)"
                }
            }
            if let riskCard = snapshot.riskCards.first {
                let detail = cleanRiskExcerpt(riskCard.evidence?.excerpt ?? riskCard.message)
                if !detail.isEmpty {
                    return "\(medicationName)：\(limited(detail, maxLength: 58))"
                }
            }
        }
        return ""
    }

    private func cleanRiskExcerpt(_ value: String) -> String {
        value
            .replacingOccurrences(of: "说明书“", with: "")
            .replacingOccurrences(of: "”指出：", with: "：")
            .replacingOccurrences(of: "请核对你是否属于上述人群、成分过敏或用药条件，并向医生或药师确认。", with: "")
            .replacingOccurrences(of: "请带着当前正在使用的药品、保健品和外用药清单咨询医生或药师。", with: "")
            .replacingOccurrences(of: "若出现相似不适，请记录时间、症状和正在使用的药品，并咨询医生或药师。", with: "")
            .replacingOccurrences(of: "应停止使用并咨询医生或药师", with: "应记录不适并咨询医生或药师")
            .replacingOccurrences(of: "停止使用并咨询医生或药师", with: "记录不适并咨询医生或药师")
            .replacingOccurrences(of: "停止使用", with: "记录不适")
            .replacingOccurrences(of: "请按原文核对适用条件，并在不确定时咨询医生或药师。", with: "")
            .split(whereSeparator: { $0.isWhitespace || $0.isNewline })
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "。；;，,"))
    }

    private func compactLocalFactSummary(for request: MedicalAIRequest) -> String {
        var facts: [String] = []
        let intent = localIntentTitle(for: request.userMessage)
        let todaySummary = todayDoseSummary(for: request)
        let recentSummary = recentDoseEventSummary(for: request)
        if intent.contains("天气") || intent.contains("环境") {
            let environment = request.environmentInsights.prefix(2).map {
                "\($0.title)：\(limited($0.message, maxLength: 100))"
            }
            facts.append(environment.isEmpty ? "未提供天气或环境数据" : environment.joined(separator: "；"))
        }
        if intent.contains("药盒") || intent.contains("库存") {
            facts.append("本次资料未提供库存余量、药盒编号或有效期")
        }
        facts.append("本次资料未列出具体服用剂量")

        if intent == "服药记录趋势" {
            let missedTrend = recentMissedDoseTrendSummary(for: request)
            if !missedTrend.isEmpty {
                facts.append("近14天记录显示，\(missedTrend)")
            }
            return facts.isEmpty ? "本地记录不足" : facts.joined(separator: "；")
        }

        if intent.contains("今日重点") {
            if !todaySummary.isEmpty {
                facts.append("今日记录：\(todaySummary)")
            }
            let todayMedications = todayMedicationDisplayNames(for: request)
            if !todayMedications.isEmpty {
                facts.append("今日相关药品：\(todayMedications.prefix(4).joined(separator: "、"))")
            }
        } else {
            let medications = medicationDisplayNames(for: request)
            if !medications.isEmpty {
                let visibleNames = Array(medications.prefix(4))
                facts.append("已提供\(visibleNames.count)条药品资料，名称：\(visibleNames.joined(separator: "、"))")
            }
        }
        if !recentSummary.isEmpty, !intent.contains("今日重点") {
            let cutoff = Date().addingTimeInterval(-14 * 24 * 60 * 60)
            let rows = request.medicationSnapshots.map { snapshot in
                let events = snapshot.doseEvents.filter { $0.recordedAt >= cutoff }
                return "\(snapshot.medication.displayName)：已记录服用\(events.filter { $0.status == .taken }.count)次，稍后\(events.filter { $0.status == .delayed }.count)次，忽略\(events.filter { $0.status == .skipped }.count)次"
            }
            facts.append("近14天按药品统计：\(rows.joined(separator: "；"))")
        }
        let labels = labelSummaryText(for: request)
        if intent.contains("说明书"), !labels.isEmpty {
            facts.append("说明书原文摘要：\(labels)")
        }
        let risks = riskSummary(for: request)
        if !risks.isEmpty {
            if intent.contains("今日重点") {
                facts.append("今日风险线索：\(risks)")
            } else {
                facts.append("风险：\(risks)")
            }
        }
        return facts.isEmpty ? "本地记录不足" : facts.joined(separator: "；")
    }

    private func todayMedicationDisplayNames(for request: MedicalAIRequest) -> [String] {
        let calendar = Calendar.current
        var names: [String] = []
        for snapshot in request.medicationSnapshots {
            let hasDoseToday = snapshot.scheduledDoses.contains { calendar.isDateInToday($0.dueAt) }
            guard hasDoseToday else {
                continue
            }
            let medication = snapshot.medication
            let generic = medication.genericName?.trimmingCharacters(in: .whitespacesAndNewlines)
            let name: String
            if let generic, !generic.isEmpty, generic != medication.displayName {
                name = "\(medication.displayName)(\(generic))"
            } else {
                name = medication.displayName
            }
            if !names.contains(name) {
                names.append(name)
            }
        }
        return names
    }

    private func todayPendingMedicationDisplayNames(for request: MedicalAIRequest) -> [String] {
        let calendar = Calendar.current
        var names: [String] = []
        for snapshot in request.medicationSnapshots {
            let eventByDoseID = Dictionary(grouping: snapshot.doseEvents, by: \.scheduledDoseID)
                .compactMapValues { events in
                    events.sorted { $0.recordedAt < $1.recordedAt }.last
                }
            let hasOpenDoseToday = snapshot.scheduledDoses.contains { dose in
                guard calendar.isDateInToday(dose.dueAt) else {
                    return false
                }
                guard let event = eventByDoseID[dose.id] else {
                    return true
                }
                return event.status == .delayed
            }
            guard hasOpenDoseToday else {
                continue
            }
            let medication = snapshot.medication
            let generic = medication.genericName?.trimmingCharacters(in: .whitespacesAndNewlines)
            let name: String
            if let generic, !generic.isEmpty, generic != medication.displayName {
                name = "\(medication.displayName)(\(generic))"
            } else {
                name = medication.displayName
            }
            if !names.contains(name) {
                names.append(name)
            }
        }
        return names
    }

    private func explicitTodayMedicationText(in userMessage: String) -> String? {
        guard let range = userMessage.range(of: "今日待处理药品：") else {
            return nil
        }
        let tail = userMessage[range.upperBound...]
        let rawText = tail.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? String(tail)
        let text = rawText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "。.;；"))
        return text.isEmpty ? nil : text
    }

    private func removingTaggedBlock(named tagName: String, from text: String) -> String {
        let pattern = #"<\#(tagName)>[\s\S]*?</\#(tagName)>"#
        return text.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
    }

    private func cutAtStopMarkers(_ text: String) -> String {
        let markers = ["<|im_end|>", "<|im_start|>"]
        var earliestRange: Range<String.Index>?
        for marker in markers {
            guard let range = text.range(of: marker) else {
                continue
            }
            if let currentRange = earliestRange {
                if range.lowerBound < currentRange.lowerBound {
                    earliestRange = range
                }
            } else {
                earliestRange = range
            }
        }
        guard let earliestRange else {
            return text
        }
        return String(text[..<earliestRange.lowerBound])
    }

    private func taggedContent(named tagName: String, in text: String) -> String? {
        let pattern = #"<\#(tagName)>([\s\S]*?)</\#(tagName)>"#
        guard let range = text.range(of: pattern, options: .regularExpression) else {
            return nil
        }
        let taggedText = String(text[range])
        return taggedText
            .replacingOccurrences(of: "<\(tagName)>", with: "")
            .replacingOccurrences(of: "</\(tagName)>", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func textAfterFinalMarker(in text: String) -> String? {
        let markers = [
            "正式回答：",
            "最终回答：",
            "回答："
        ]
        for marker in markers {
            guard let range = text.range(of: marker) else {
                continue
            }
            return String(text[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return nil
    }

    private func isGenericRiskTitle(_ title: String) -> Bool {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return true
        }
        let genericFragments = [
            "警示信息",
            "药品类别信息",
            "风险提醒",
            "注意事项",
            "用药风险"
        ]
        return genericFragments.contains { trimmed == $0 || trimmed.contains("\($0)：") }
    }

    private func occurrences(of needle: String, in haystack: String) -> Int {
        guard !needle.isEmpty else {
            return 0
        }
        var count = 0
        var searchRange = haystack.startIndex..<haystack.endIndex
        while let range = haystack.range(of: needle, options: [], range: searchRange) {
            count += 1
            searchRange = range.upperBound..<haystack.endIndex
        }
        return count
    }

    private func limited(_ value: String, maxLength: Int) -> String {
        guard value.count > maxLength else {
            return value
        }
        let end = value.index(value.startIndex, offsetBy: maxLength)
        return String(value[..<end])
    }
}
