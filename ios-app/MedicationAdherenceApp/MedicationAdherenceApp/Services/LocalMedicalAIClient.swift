import Foundation
import MedicationAdherenceCore
#if canImport(llama)
import llama
#endif

struct LocalMedicalAIClient: MedicalAIClient {
    static let localReasoningSeparator = "\n[[LOCAL_MODEL_REASONING]]\n"

    let modelURL: URL
    var runtime: LocalMedicalModelRuntime = .shared

    private var provider: MedicalAIProviderProfile {
        MedicalAIProviderProfile(
            providerName: "离线智能体",
            modelName: LocalMedicalModelStore.modelDisplayName,
            serviceLicenseSummary: "在本机生成用药整理内容，不上传本次共享数据。"
        )
    }

    func respond(to request: MedicalAIRequest) async throws -> MedicalAIResponse {
        let answerPlan = localAnswerPlan(for: request)
        let prompt = buildLocalPrompt(for: request, answerPlan: answerPlan)
        let generatedMessage = try await runtime.generateResponse(
            prompt: prompt,
            modelURL: modelURL,
            maxTokens: 220
        )
        let processedMessage = postprocessLocalResponse(generatedMessage, request: request)
        let processedAnswer = formalAnswerText(from: processedMessage)
        let message: String
        let processedIsLowQuality = isLowQualityLocalResponse(processedAnswer, request: request)
        if processedIsLowQuality || isOffTopicLocalResponse(processedAnswer, answerPlan: answerPlan) {
            let repairedMessage = try await runtime.generateResponse(
                prompt: buildRepairPrompt(for: request, answerPlan: answerPlan),
                modelURL: modelURL,
                maxTokens: 220
            )
            let repairedProcessedMessage = postprocessLocalResponse(repairedMessage, request: request)
            let repairedAnswer = formalAnswerText(from: repairedProcessedMessage)
            if isLowQualityLocalResponse(repairedAnswer, request: request) {
                if processedIsLowQuality {
                    throw LocalMedicalAIError.unstableResponse
                }
                message = processedMessage
            } else {
                message = repairedProcessedMessage
            }
        } else {
            message = processedMessage
        }
        guard !formalAnswerText(from: message).isEmpty else {
            throw LocalMedicalAIError.emptyResponse
        }
        return MedicalAIResponse(
            requestID: request.id,
            provider: provider,
            message: message
        )
    }

    func streamResponse(to request: MedicalAIRequest) -> AsyncThrowingStream<LocalLLMGenerationEvent, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let answerPlan = localAnswerPlan(for: request)
                    let prompt = buildLocalPrompt(for: request, answerPlan: answerPlan)
                    var parser = LocalLLMStreamParser()
                    continuation.yield(.generationStarted)
                    continuation.yield(.modelLoading)
                    let stream = await runtime.generateResponseStream(
                        prompt: prompt,
                        modelURL: modelURL,
                        maxTokens: 640
                    )
                    continuation.yield(.prefillStarted)
                    for try await delta in stream {
                        for event in parser.consume(delta) {
                            continuation.yield(event)
                        }
                    }
                    let completed = parser.finish()
                    for event in completed.events {
                        continuation.yield(event)
                    }
                    let processedMessage = postprocessLocalResponse(completed.answer, request: request)
                    let answer = formalAnswerText(from: processedMessage)
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    let thinking = [completed.thinking, reasoningText(from: processedMessage)]
                        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                        .filter { !$0.isEmpty }
                        .joined(separator: "\n\n")
                    if answer.isEmpty {
                        throw LocalMedicalAIError.emptyResponse
                    }
                    if isLowQualityLocalResponse(answer, request: request)
                        || isOffTopicLocalResponse(answer, answerPlan: answerPlan) {
                        let repairedMessage = try await runtime.generateResponse(
                            prompt: buildRepairPrompt(for: request, answerPlan: answerPlan),
                            modelURL: modelURL,
                            maxTokens: 360
                        )
                        let repairedProcessedMessage = postprocessLocalResponse(repairedMessage, request: request)
                        let repairedAnswer = formalAnswerText(from: repairedProcessedMessage)
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                        let repairedThinking = reasoningText(from: repairedProcessedMessage)
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !repairedAnswer.isEmpty,
                              !isLowQualityLocalResponse(repairedAnswer, request: request),
                              !isOffTopicLocalResponse(repairedAnswer, answerPlan: answerPlan) else {
                            throw LocalMedicalAIError.unstableResponse
                        }
                        let combinedThinking = [thinking, repairedThinking]
                            .filter { !$0.isEmpty }
                            .joined(separator: "\n\n")
                        continuation.yield(.generationCompleted(
                            answer: repairedAnswer,
                            thinking: combinedThinking
                        ))
                        continuation.finish()
                        return
                    }
                    continuation.yield(.generationCompleted(
                        answer: answer,
                        thinking: thinking
                    ))
                    continuation.finish()
                } catch {
                    continuation.yield(.generationFailed(error.localizedDescription))
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    private func buildLocalPrompt(for request: MedicalAIRequest, answerPlan: LocalMedicalAnswerPlan) -> String {
        if answerPlan.focus.contains("今日用药注意事项") {
            return buildTodayFocusPrompt(for: request, answerPlan: answerPlan)
        }
        if answerPlan.focus.contains("忽略或稍后趋势") {
            return buildTrendPrompt(for: request, answerPlan: answerPlan)
        }
        let system = """
        你是用药记录助手。只根据本地记录回答，不复述提示词，不输出代码、JSON、编号、表格或 Markdown。
        不诊断，不开药，不建议停药、停止使用、暂停使用、换药或调整剂量。不要编造记录数量；没有事实时说明“本地记录不足”。
        可以使用 <think> 写简短思考，必须使用 <answer> 写给用户看的最终回答。
        <answer>里只能写自然中文回答，不得出现“当前任务、用户问题、回答焦点、本地事实、事实边界、本地药品资料”等字段名。
        """
        let facts = [
            "用户：\(localQuestionText(for: request.userMessage))",
            "重点：\(answerPlan.focus)",
            "资料：\(answerPlan.factSummary)",
            "边界：\(answerPlan.factGuidance)"
        ].joined(separator: "\n")
        return "\(system)\n\n\(facts)\n\n请输出：<answer>两到四句自然中文回答</answer>"
    }

    private func buildTodayFocusPrompt(for request: MedicalAIRequest, answerPlan: LocalMedicalAnswerPlan) -> String {
        let pendingMedicationText = explicitTodayMedicationText(in: request.userMessage)
            ?? todayPendingMedicationDisplayNames(for: request).prefix(4).joined(separator: "、")
        let todayText = pendingMedicationText.isEmpty ? "今天没有未处理提醒药品名称" : pendingMedicationText
        let summary = todayPendingDoseSummary(for: request)
        let recordText = summary.isEmpty ? "今天还没有可用的完成、稍后或忽略记录" : summary
        let riskText = focusedTodayRiskLine(for: request)
        let riskLine = riskText.isEmpty ? "没有明确风险卡片需要单独提示" : riskText
        return """
        你是用药记录助手。请把下面三条事实改写成给用户看的自然中文提醒，不要遗漏药品名。
        事实一：今日待处理药品是 \(todayText)。
        事实二：\(recordText)。
        事实三：最具体注意事项是 \(riskLine)。
        必须包含这些词：\(todayText)。
        回答要求：两到三句；第一句列出今日待处理药品；第二句说明注意事项和记录建议。不要复述“事实一、事实二、事实三”，不要输出代码、字段名、标题、Markdown 或 XML 标签。
        不诊断，不开药，不建议停药、停止使用、暂停使用、换药或调整剂量。
        输出格式：<answer>两到三句自然中文</answer>
        """
    }

    private func buildTrendPrompt(for request: MedicalAIRequest, answerPlan: LocalMedicalAnswerPlan) -> String {
        let medications = medicationDisplayNames(for: request).prefix(5).joined(separator: "、")
        let medicationText = medications.isEmpty ? "本地药品名称不足" : medications
        let trendText = recentMissedDoseTrendSummary(for: request)
        let usableTrend = trendText.isEmpty ? "过去14天没有稍后或忽略记录" : "过去14天，\(trendText)。"
        return """
        你是用药记录助手。用户想看近期“忽略或稍后”趋势。
        可参考的药品名称包括：\(medicationText)。
        可参考的记录事实是：\(usableTrend)
        只回答趋势和一个减少遗漏的建议。不要要求用户再提供资料，不要输出代码、字段名、标题、Markdown 或原始事实标签，不要用“趋势：”开头。
        不要提“已完成”次数。如果记录里有“忽略”或“稍后”，请先说出数量；如果没有，就说明近期没有明显忽略或稍后记录。
        输出格式：<answer>两到三句自然中文</answer>
        """
    }

    private func buildRepairPrompt(for request: MedicalAIRequest, answerPlan: LocalMedicalAnswerPlan) -> String {
        if answerPlan.focus.contains("今日用药注意事项") {
            return """
            你是用药记录助手。请把下面事实改写成自然中文回答，不要遗漏药品名。
            用户问：\(localQuestionText(for: request.userMessage))
            \(answerPlan.factSummary)
            必须包含这些词：\(answerPlan.requiredFragments.joined(separator: "、"))。
            请用两到三句回答；不要输出标题、代码、Markdown、XML 标签、用户原文或字段名；不要建议停药、停止使用、暂停使用、换药或调整剂量。
            """
        }
        return """
        你是用药记录助手。请直接回答用户，不要输出 XML 标签、思考过程、代码、JSON、编号、Markdown、标题、表格或用户原文。
        用户问：\(localQuestionText(for: request.userMessage))
        你要回答：\(answerPlan.focus)。
        只能使用这些本地事实：\(answerPlan.factSummary)。
        可参考的表达方向是：\(answerPlan.factGuidance)
        请用两到三句自然中文重新回答；不要用“趋势：”“回答：”这类标题开头，不要重复同一句话，不要照抄上面的句子，不要编造记录数量，不要建议停药、停止使用、暂停使用、换药或调整剂量。
        """
    }

    private func postprocessLocalResponse(_ value: String, request: MedicalAIRequest) -> String {
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
        let implicit = splitImplicitReasoning(from: finalCandidate)
        let cleaned = cleanFinalAnswerText(implicit.answer, request: request)
        let combinedThinking = [thinking, implicit.thinking]
            .map(cleanReasoningText)
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
        guard !cleaned.isEmpty, !combinedThinking.isEmpty else {
            return cleaned
        }
        return "\(cleaned)\(Self.localReasoningSeparator)\(combinedThinking)"
    }

    private func splitImplicitReasoning(from value: String) -> (thinking: String, answer: String) {
        let cleaned = value
            .replacingOccurrences(of: "\n", with: " ")
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let separators = CharacterSet(charactersIn: "。！？!?")
        var sentences: [String] = []
        var current = ""
        for scalar in cleaned.unicodeScalars {
            current.unicodeScalars.append(scalar)
            if separators.contains(scalar) {
                let sentence = current.trimmingCharacters(in: .whitespacesAndNewlines)
                if !sentence.isEmpty {
                    sentences.append(sentence)
                }
                current = ""
            }
        }
        let tail = current.trimmingCharacters(in: .whitespacesAndNewlines)
        if !tail.isEmpty {
            sentences.append(tail)
        }
        guard sentences.count > 1 else {
            return ("", cleaned)
        }
        var reasoningSentences: [String] = []
        var answerSentences: [String] = []
        var isStillReasoningPrefix = true
        for sentence in sentences {
            if isStillReasoningPrefix, isImplicitReasoningSentence(sentence) {
                reasoningSentences.append(sentence)
            } else {
                isStillReasoningPrefix = false
                answerSentences.append(sentence)
            }
        }
        guard !reasoningSentences.isEmpty, !answerSentences.isEmpty else {
            return ("", cleaned)
        }
        return (
            reasoningSentences.joined(separator: " "),
            answerSentences.joined(separator: " ")
        )
    }

    private func isImplicitReasoningSentence(_ sentence: String) -> Bool {
        let markers = [
            "用户的问题",
            "用户想要",
            "我需要",
            "我将",
            "我会",
            "我可以",
            "我要",
            "来回答用户",
            "回答用户的问题",
            "没有提供具体",
            "可以根据用户",
            "根据用户给出",
            "来推断"
        ]
        return markers.contains { sentence.contains($0) }
    }

    private func cleanFinalAnswerText(_ value: String, request: MedicalAIRequest) -> String {
        let cleaned = value
            .replacingOccurrences(of: "<|im_start|>", with: "")
            .replacingOccurrences(of: "<|im_end|>", with: "")
            .replacingOccurrences(of: "</s>", with: "")
            .replacingOccurrences(of: "<final>", with: "")
            .replacingOccurrences(of: "</final>", with: "")
            .replacingOccurrences(of: "<thought>", with: "")
            .replacingOccurrences(of: "</thought>", with: "")
            .replacingOccurrences(of: "<think>", with: "")
            .replacingOccurrences(of: "</think>", with: "")
            .replacingOccurrences(of: "最终回答：", with: "")
            .replacingOccurrences(of: "正式回答：", with: "")
            .replacingOccurrences(of: "根据用户提供的信息，", with: "")
            .replacingOccurrences(of: "根据用户提供的信息：", with: "")
            .replacingOccurrences(of: "根据您提供的信息，", with: "")
            .replacingOccurrences(of: "根据您提供的信息：", with: "")
            .replacingOccurrences(of: "近14天稍后/忽略：", with: "")
            .replacingOccurrences(of: "近 14 天稍后/忽略：", with: "")
            .replacingOccurrences(of: "首先，", with: "")
            .replacingOccurrences(of: "然后，", with: "")
            .replacingOccurrences(of: "assistant", with: "")
            .replacingOccurrences(of: "用户问题：\(request.userMessage)", with: "")
            .replacingOccurrences(of: request.userMessage, with: "")
            .components(separatedBy: .newlines)
            .filter { line in
                let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
                return !trimmedLine.hasPrefix("```")
                    && !trimmedLine.hasPrefix("#")
                    && !trimmedLine.hasPrefix("思考")
                    && !trimmedLine.hasPrefix("推理")
                    && !trimmedLine.hasPrefix("分析")
                    && !trimmedLine.hasPrefix("代码")
                    && !trimmedLine.hasPrefix("当前任务")
                    && !trimmedLine.hasPrefix("用户问题")
                    && !trimmedLine.hasPrefix("回答焦点")
                    && !trimmedLine.hasPrefix("事实边界")
                    && !trimmedLine.hasPrefix("本地事实")
                    && !trimmedLine.hasPrefix("本地药品")
                    && !trimmedLine.hasPrefix("本地记录")
                    && !trimmedLine.hasPrefix("本地药品资料")
                    && !trimmedLine.hasPrefix("资料：")
                    && !trimmedLine.hasPrefix("边界：")
            }
            .joined(separator: " ")
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let compacted = compactRepeatedSegments(in: cleaned)
        let normalizedCompacted = compacted
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "：:，,；;、"))
        guard normalizedCompacted.count > 220 else {
            return normalizedCompacted
        }
        let end = normalizedCompacted.index(normalizedCompacted.startIndex, offsetBy: 220)
        return String(normalizedCompacted[..<end])
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "：:，,；;、"))
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

    private func formalAnswerText(from message: String) -> String {
        message
            .components(separatedBy: Self.localReasoningSeparator)
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private func reasoningText(from message: String) -> String {
        let components = message.components(separatedBy: Self.localReasoningSeparator)
        guard components.count > 1 else {
            return ""
        }
        return components.dropFirst()
            .joined(separator: Self.localReasoningSeparator)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func isLowQualityLocalResponse(_ response: String, request: MedicalAIRequest) -> Bool {
        let trimmed = response.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count < 8 {
            return true
        }
        let badFragments = [
            "用户问题",
            "风险关注",
            "任务：",
            "本地事实",
            "本地信息",
            "本地药品：",
            "本地记录：",
            "用户想要",
            "可参考信息",
            "回答焦点",
            "答案要点",
            "当前任务",
            "事实边界",
            "近14天稍后/忽略",
            "近 14 天稍后/忽略",
            "近14天记录显示",
            "近 14 天记录显示",
            "近期忽略或稍后趋势。",
            "趋势：",
            "关注这些药物的减少遗漏",
            "本地药品资料",
            "这是一位用户的问题",
            "请直接回答用户",
            "请只基于",
            "App 内授权共享",
            "【提醒】",
            "【风险提醒】",
            "【服药记录】",
            "根据用户的问题",
            "用户的问题是",
            "我需要",
            "我将",
            "很抱歉",
            "无法根据",
            "不能根据",
            "请提供其他信息",
            "更准确的查询",
            "根据用户提供",
            "将检查",
            "基于这些信息",
            "暂停使用",
            "停止使用",
            "停用",
            "自行对照",
            "###",
            "警示信息",
            "今日用药提醒",
            "风险与用药信息",
            "```",
            "func ",
            "let ",
            "var ",
            "import ",
            "struct ",
            "class ",
            "return ",
            "<think",
            "</think",
            "<thought",
            "</thought",
            "推理过程",
            "思考过程",
            "分析：",
            "自然中文",
            "代码",
            "system.",
            "user.",
            "record.",
            "acetaminophen",
            "ibuprofen",
            "loratadine",
            "\"days\"",
            "\"completed\"",
            "\"",
            "{",
            "}",
            "**",
            "__"
        ]
        if badFragments.contains(where: { trimmed.contains($0) }) {
            return true
        }
        if trimmed.components(separatedBy: .newlines).contains(where: { $0.trimmingCharacters(in: .whitespaces).hasPrefix("- ") }) {
            return true
        }
        if trimmed.range(of: #"已完成\s*\d{3,}\s*次"#, options: .regularExpression) != nil {
            return true
        }
        if localIntentTitle(for: request.userMessage).contains("趋势"),
           trimmed.contains("没有明显"),
           (trimmed.contains("忽略") || trimmed.contains("稍后")),
           trimmed.range(of: #"\d+\s*次"#, options: .regularExpression) != nil {
            return true
        }
        if localIntentTitle(for: request.userMessage).contains("趋势"),
           hasInconsistentMedicationCountWord(in: trimmed, request: request) {
            return true
        }
        if localIntentTitle(for: request.userMessage).contains("趋势"),
           occurrences(of: "趋势", in: trimmed) > 1 {
            return true
        }
        if localIntentTitle(for: request.userMessage).contains("趋势"),
           !trimmed.contains("建议"),
           !trimmed.contains("可以"),
           !trimmed.contains("优先") {
            return true
        }
        if localIntentTitle(for: request.userMessage).contains("今日"),
           trimmed.range(of: #"已完成\s*\d{2,}\s*次|忽略\s*\d{2,}\s*次|稍后\s*\d{2,}\s*次"#, options: .regularExpression) != nil {
            return true
        }
        if localIntentTitle(for: request.userMessage).contains("今日") {
            let todayNames = explicitTodayMedicationText(in: request.userMessage)?
                .components(separatedBy: "、")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty } ?? todayPendingMedicationDisplayNames(for: request)
            let mentionedTodayNameCount = todayNames.reduce(0) { count, name in
                let shortName = name.components(separatedBy: "(").first ?? name
                return count + (trimmed.contains(name) || trimmed.contains(shortName) ? 1 : 0)
            }
            let requiredCount = min(2, todayNames.count)
            if requiredCount > 0, mentionedTodayNameCount < requiredCount {
                return true
            }
            let pendingNameSet = Set(todayNames.map { $0.components(separatedBy: "(").first ?? $0 })
            let mentionedUnrelatedMedication = medicationDisplayNames(for: request).contains { name in
                let shortName = name.components(separatedBy: "(").first ?? name
                return !pendingNameSet.contains(shortName) && trimmed.contains(shortName)
            }
            if mentionedUnrelatedMedication {
                return true
            }
        }
        let medicationNames = medicationDisplayNames(for: request)
        let repeatedMedicationNameCount = medicationNames.reduce(0) { count, name in
            count + occurrences(of: name, in: trimmed)
        }
        if repeatedMedicationNameCount > max(4, medicationNames.count) {
            return true
        }
        return false
    }

    private func hasInconsistentMedicationCountWord(in response: String, request: MedicalAIRequest) -> Bool {
        let mentionedMedicationCount = Set(
            medicationDisplayNames(for: request)
                .map { $0.components(separatedBy: "(").first ?? $0 }
                .filter { !$0.isEmpty && response.contains($0) }
        ).count
        let countWords: [(String, Int)] = [
            ("一种", 1),
            ("两种", 2),
            ("二种", 2),
            ("三种", 3),
            ("四种", 4),
            ("五种", 5),
            ("六种", 6)
        ]
        for (word, count) in countWords where response.contains(word) {
            return mentionedMedicationCount > 0 && mentionedMedicationCount != count
        }
        return false
    }

    private func isOffTopicLocalResponse(_ response: String, answerPlan: LocalMedicalAnswerPlan) -> Bool {
        let trimmed = response.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return true
        }
        guard !answerPlan.requiredFragments.isEmpty else {
            return false
        }
        let matchedCount = answerPlan.requiredFragments.reduce(0) { count, fragment in
            trimmed.contains(fragment) ? count + 1 : count
        }
        return matchedCount == 0
    }

    private func localIntentTitle(for userMessage: String) -> String {
        if userMessage.contains("图片") || userMessage.contains("上传") || userMessage.contains("拍照") {
            return "图片录入建议"
        }
        if userMessage.contains("天气") || userMessage.contains("环境") || userMessage.contains("不适") {
            return "天气与环境用药关注"
        }
        if userMessage.contains("趋势") || userMessage.contains("稍后") || userMessage.contains("忽略") {
            return "服药记录趋势"
        }
        if userMessage.contains("风险") || userMessage.contains("说明书") {
            return "风险与说明书重点"
        }
        if userMessage.contains("复诊") {
            return "复诊沟通整理"
        }
        if userMessage.contains("库存") || userMessage.contains("药盒") {
            return "药盒与库存提醒"
        }
        if userMessage.contains("今日") || userMessage.contains("今天") {
            return "今日重点核对"
        }
        return "今日重点核对"
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

    private func localAnswerPlan(for request: MedicalAIRequest) -> LocalMedicalAnswerPlan {
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

        if intent.contains("趋势") || intent.contains("记录") {
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
        let cutoff = Calendar.current.date(byAdding: .day, value: -14, to: Date()) ?? Date().addingTimeInterval(-1_209_600)
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
        let cutoff = Calendar.current.date(byAdding: .day, value: -14, to: Date()) ?? Date().addingTimeInterval(-1_209_600)
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

        if intent.contains("趋势") || intent.contains("记录") {
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
                facts.append("已授权药品：\(medications.prefix(4).joined(separator: "、"))")
            }
        }
        if !recentSummary.isEmpty, !intent.contains("今日重点") {
            facts.append("近14天：\(recentSummary)")
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
        let markers = [
            "<|im_end|>",
            "<|im_start|>user",
            "<|im_start|>system",
            "<|im_start|>",
            "当前任务：",
            "回答焦点：",
            "事实边界：",
            "本地事实：",
            "本地药品：",
            "本地记录：",
            "本地药品资料：",
            "这是一位用户的问题："
        ]
        var earliestRange: Range<String.Index>?
        for marker in markers {
            guard let range = text.range(of: marker) else {
                continue
            }
            if earliestRange == nil || range.lowerBound < earliestRange!.lowerBound {
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

    private func compactRepeatedSegments(in text: String) -> String {
        let separators = CharacterSet(charactersIn: "。；;！!？?")
        var result: [String] = []
        for segment in text.components(separatedBy: separators) {
            let trimmed = segment.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, !result.contains(trimmed) else {
                continue
            }
            result.append(trimmed)
            if result.count >= 3 {
                break
            }
        }
        if result.isEmpty {
            return text
        }
        return result.joined(separator: "。") + "。"
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

private struct LocalMedicalAnswerPlan {
    let focus: String
    let factSummary: String
    let factGuidance: String
    let requiredFragments: [String]
}

enum LocalLLMGenerationEvent {
    case generationStarted
    case modelLoading
    case prefillStarted
    case thinkingStarted
    case thinkingDelta(String)
    case answerStarted
    case answerDelta(String)
    case generationCompleted(answer: String, thinking: String)
    case generationFailed(String)
}

struct LocalLLMStreamParser {
    enum Section {
        case undecided
        case thinking
        case answer
    }

    private var buffer = ""
    private var emittedThinkingCount = 0
    private var emittedAnswerCount = 0
    private var hasStartedThinking = false
    private var hasStartedAnswer = false
    private var section: Section = .undecided

    mutating func consume(_ rawDelta: String) -> [LocalLLMGenerationEvent] {
        buffer += sanitizedRenderableText(rawDelta)
        return currentEvents()
    }

    mutating func finish() -> (events: [LocalLLMGenerationEvent], thinking: String, answer: String) {
        let parsed = parse(buffer, isFinal: true)
        var events = emitDeltas(thinking: parsed.thinking, answer: parsed.answer)
        if !hasStartedAnswer, !parsed.answer.isEmpty {
            events.insert(.answerStarted, at: 0)
            hasStartedAnswer = true
        }
        return (events, parsed.thinking, parsed.answer)
    }

    private mutating func currentEvents() -> [LocalLLMGenerationEvent] {
        let parsed = parse(buffer, isFinal: false)
        return emitDeltas(thinking: parsed.thinking, answer: parsed.answer)
    }

    private mutating func emitDeltas(thinking: String, answer: String) -> [LocalLLMGenerationEvent] {
        var events: [LocalLLMGenerationEvent] = []
        if !thinking.isEmpty, !hasStartedThinking {
            events.append(.thinkingStarted)
            hasStartedThinking = true
        }
        if thinking.count > emittedThinkingCount {
            let start = thinking.index(thinking.startIndex, offsetBy: emittedThinkingCount)
            events.append(.thinkingDelta(String(thinking[start...])))
            emittedThinkingCount = thinking.count
        }
        if !answer.isEmpty, !hasStartedAnswer {
            events.append(.answerStarted)
            hasStartedAnswer = true
        }
        if answer.count > emittedAnswerCount {
            let start = answer.index(answer.startIndex, offsetBy: emittedAnswerCount)
            events.append(.answerDelta(String(answer[start...])))
            emittedAnswerCount = answer.count
        }
        return events
    }

    private func parse(_ text: String, isFinal: Bool) -> (thinking: String, answer: String) {
        let normalized = sanitizedRenderableText(text)
        if let explicit = parseTagged(normalized, isFinal: isFinal) {
            return explicit
        }
        if let weak = parseWeakSeparators(normalized) {
            return weak
        }
        let trimmed = cleanupVisibleText(normalized)
        let implicit = splitImplicitReasoning(from: trimmed)
        if !implicit.thinking.isEmpty {
            return implicit
        }
        if isFinal {
            return ("", trimmed)
        }
        return ("", trimmed)
    }

    private func parseTagged(_ text: String, isFinal: Bool) -> (thinking: String, answer: String)? {
        let lowercased = text.lowercased()
        let thinkStartTag = "<think>"
        let thinkEndTag = "</think>"
        let answerStartTags = ["<answer>", "<final>"]
        let answerEndTags = ["</answer>", "</final>"]

        if let thinkStart = lowercased.range(of: thinkStartTag) {
            let thinkingStartIndex = thinkStart.upperBound
            if let thinkEnd = lowercased.range(of: thinkEndTag, range: thinkingStartIndex..<lowercased.endIndex) {
                let thinking = cleanupVisibleText(String(text[thinkingStartIndex..<thinkEnd.lowerBound]))
                let afterThink = String(text[thinkEnd.upperBound...])
                let answer = taggedAnswer(in: afterThink, startTags: answerStartTags, endTags: answerEndTags)
                    ?? cleanupVisibleText(afterThink)
                return (thinking, answer)
            }
            let thinking = cleanupVisibleText(String(text[thinkingStartIndex...]))
            return (thinking, isFinal ? "" : "")
        }

        if let answer = taggedAnswer(in: text, startTags: answerStartTags, endTags: answerEndTags) {
            return ("", answer)
        }
        return nil
    }

    private func taggedAnswer(in text: String, startTags: [String], endTags: [String]) -> String? {
        let lowercased = text.lowercased()
        for startTag in startTags {
            guard let start = lowercased.range(of: startTag) else {
                continue
            }
            let answerStart = start.upperBound
            let matchingEndTags = endTags.filter { $0.contains(startTag.replacingOccurrences(of: "<", with: "</")) || endTags.count > 1 }
            let endRange = matchingEndTags.compactMap { tag in
                lowercased.range(of: tag, range: answerStart..<lowercased.endIndex)
            }.min { $0.lowerBound < $1.lowerBound }
            if let endRange {
                return cleanupVisibleText(String(text[answerStart..<endRange.lowerBound]))
            }
            return cleanupVisibleText(String(text[answerStart...]))
        }
        return nil
    }

    private func parseWeakSeparators(_ text: String) -> (thinking: String, answer: String)? {
        let markers = ["答案：", "回答：", "最终回答：", "Answer:"]
        for marker in markers {
            guard let range = text.range(of: marker) else {
                continue
            }
            let before = cleanupVisibleText(String(text[..<range.lowerBound]))
            let after = cleanupVisibleText(String(text[range.upperBound...]))
            if before.contains("思考") || before.contains("分析") || before.contains("推理") {
                return (before, after)
            }
            return ("", after)
        }
        return nil
    }

    private func cleanupVisibleText(_ text: String) -> String {
        sanitizedRenderableText(text)
            .replacingOccurrences(of: "<think>", with: "")
            .replacingOccurrences(of: "</think>", with: "")
            .replacingOccurrences(of: "<answer>", with: "")
            .replacingOccurrences(of: "</answer>", with: "")
            .replacingOccurrences(of: "<final>", with: "")
            .replacingOccurrences(of: "</final>", with: "")
            .replacingOccurrences(of: "<|im_start|>", with: "")
            .replacingOccurrences(of: "<|im_end|>", with: "")
            .replacingOccurrences(of: "</s>", with: "")
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func splitImplicitReasoning(from value: String) -> (thinking: String, answer: String) {
        let cleaned = value
            .replacingOccurrences(of: "\n", with: " ")
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let separators = CharacterSet(charactersIn: "。！？!?")
        var sentences: [String] = []
        var current = ""
        for scalar in cleaned.unicodeScalars {
            current.unicodeScalars.append(scalar)
            if separators.contains(scalar) {
                let sentence = current.trimmingCharacters(in: .whitespacesAndNewlines)
                if !sentence.isEmpty {
                    sentences.append(sentence)
                }
                current = ""
            }
        }
        let tail = current.trimmingCharacters(in: .whitespacesAndNewlines)
        if !tail.isEmpty {
            sentences.append(tail)
        }
        guard sentences.count > 1 else {
            return ("", cleaned)
        }
        var reasoningSentences: [String] = []
        var answerSentences: [String] = []
        var isStillReasoningPrefix = true
        for sentence in sentences {
            if isStillReasoningPrefix, isImplicitReasoningSentence(sentence) {
                reasoningSentences.append(sentence)
            } else {
                isStillReasoningPrefix = false
                answerSentences.append(sentence)
            }
        }
        guard !reasoningSentences.isEmpty, !answerSentences.isEmpty else {
            return ("", cleaned)
        }
        return (
            reasoningSentences.joined(separator: " "),
            answerSentences.joined(separator: " ")
        )
    }

    private func isImplicitReasoningSentence(_ sentence: String) -> Bool {
        let markers = [
            "用户的问题",
            "用户想要",
            "我需要",
            "我将",
            "我会",
            "我可以",
            "我要",
            "来回答用户",
            "回答用户的问题",
            "没有提供具体",
            "可以根据用户",
            "根据用户给出",
            "来推断"
        ]
        return markers.contains { sentence.contains($0) }
    }

    private func sanitizedRenderableText(_ text: String) -> String {
        String(text.unicodeScalars.compactMap { scalar in
            if scalar == "\n" || scalar == "\t" {
                return Character(scalar)
            }
            if CharacterSet.controlCharacters.contains(scalar) {
                return nil
            }
            if scalar.value == 0xFFFD {
                return nil
            }
            return Character(scalar)
        })
    }
}

actor LocalMedicalModelRuntime {
    static let shared = LocalMedicalModelRuntime()

    static var isAvailable: Bool {
        #if canImport(llama)
        true
        #else
        false
        #endif
    }

    var isReady: Bool {
        Self.isAvailable
    }

    func generateResponse(prompt: String, modelURL: URL, maxTokens: Int) async throws -> String {
        #if canImport(llama)
        let context = try LlamaCppContext(modelURL: modelURL)
        let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPrompt.isEmpty else {
            throw LocalMedicalAIError.emptyResponse
        }
        let response = try context.generate(prompt: trimmedPrompt, maxTokens: maxTokens)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !response.isEmpty else {
            throw LocalMedicalAIError.emptyResponse
        }
        return response
        #else
        throw LocalMedicalAIError.runtimeUnavailable
        #endif
    }

    func generateResponseStream(prompt: String, modelURL: URL, maxTokens: Int) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    #if canImport(llama)
                    let context = try LlamaCppContext(modelURL: modelURL)
                    let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmedPrompt.isEmpty else {
                        throw LocalMedicalAIError.emptyResponse
                    }
                    _ = try context.generate(prompt: trimmedPrompt, maxTokens: maxTokens) { delta in
                        guard !delta.isEmpty else {
                            return
                        }
                        continuation.yield(delta)
                    }
                    continuation.finish()
                    #else
                    throw LocalMedicalAIError.runtimeUnavailable
                    #endif
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}

#if canImport(llama)
private final class LlamaCppContext {
    private var model: OpaquePointer
    private var context: OpaquePointer
    private var vocab: OpaquePointer
    private var sampler: UnsafeMutablePointer<llama_sampler>
    private var pendingUTF8Bytes: [CChar] = []
    private let contextLength = 2048

    init(modelURL: URL) throws {
        llama_backend_init()

        var modelParameters = llama_model_default_params()
        #if targetEnvironment(simulator)
        modelParameters.n_gpu_layers = 0
        #endif

        guard let loadedModel = llama_model_load_from_file(modelURL.path, modelParameters) else {
            throw LocalMedicalAIError.modelMissing
        }
        model = loadedModel

        let threadCount = max(1, min(8, ProcessInfo.processInfo.processorCount - 2))
        var contextParameters = llama_context_default_params()
        contextParameters.n_ctx = UInt32(contextLength)
        contextParameters.n_batch = UInt32(contextLength)
        contextParameters.n_ubatch = min(contextParameters.n_ubatch, 512)
        contextParameters.n_threads = Int32(threadCount)
        contextParameters.n_threads_batch = Int32(threadCount)

        guard let loadedContext = llama_init_from_model(loadedModel, contextParameters) else {
            llama_model_free(loadedModel)
            throw LocalMedicalAIError.runtimeUnavailable
        }
        context = loadedContext
        vocab = llama_model_get_vocab(loadedModel)

        let samplerParameters = llama_sampler_chain_default_params()
        sampler = llama_sampler_chain_init(samplerParameters)
        llama_sampler_chain_add(sampler, llama_sampler_init_top_k(40))
        llama_sampler_chain_add(sampler, llama_sampler_init_top_p(0.85, 1))
        llama_sampler_chain_add(sampler, llama_sampler_init_penalties(128, 1.10, 0.02, 0.0))
        llama_sampler_chain_add(sampler, llama_sampler_init_temp(0.40))
        llama_sampler_chain_add(sampler, llama_sampler_init_dist(42))
    }

    deinit {
        llama_sampler_free(sampler)
        llama_model_free(model)
        llama_free(context)
        llama_backend_free()
    }

    func generate(prompt: String, maxTokens: Int, onToken: ((String) -> Void)? = nil) throws -> String {
        pendingUTF8Bytes.removeAll()
        llama_memory_clear(llama_get_memory(context), true)
        llama_sampler_reset(sampler)

        let formattedPrompt = chatFormattedPrompt(for: prompt)
        let tokenLimit = max(1, min(maxTokens, 640))
        let promptTokens = truncatePromptTokens(
            tokenize(formattedPrompt, addBOS: true),
            maxPromptTokens: max(1, contextLength - tokenLimit - 32)
        )
        guard !promptTokens.isEmpty else {
            throw LocalMedicalAIError.emptyResponse
        }

        var promptTokensForDecode = promptTokens
        let promptDecodeStatus = promptTokensForDecode.withUnsafeMutableBufferPointer { tokens in
            let promptBatch = llama_batch_get_one(tokens.baseAddress, Int32(tokens.count))
            return llama_decode(context, promptBatch)
        }

        guard promptDecodeStatus == 0 else {
            throw LocalMedicalAIError.runtimeUnavailable
        }

        var output = ""
        for _ in 0..<tokenLimit {
            let newToken = llama_sampler_sample(sampler, context, -1)
            if llama_vocab_is_eog(vocab, newToken) {
                output += flushPendingUTF8Bytes()
                break
            }

            let piece = appendTokenPiece(newToken)
            output += piece
            onToken?(piece)
            llama_sampler_accept(sampler, newToken)
            var tokenForDecode = newToken
            let tokenBatch = llama_batch_get_one(&tokenForDecode, 1)

            guard llama_decode(context, tokenBatch) == 0 else {
                throw LocalMedicalAIError.runtimeUnavailable
            }
        }

        output += flushPendingUTF8Bytes()
        return output
    }

    private func chatFormattedPrompt(for prompt: String) -> String {
        guard let template = llama_model_chat_template(model, nil) else {
            return prompt
        }
        return "user".withCString { rolePointer in
            prompt.withCString { contentPointer in
                var message = llama_chat_message(role: rolePointer, content: contentPointer)
                let initialLength = max(4096, prompt.utf8.count * 3)
                var buffer = [CChar](repeating: 0, count: initialLength)
                let written = llama_chat_apply_template(template, &message, 1, true, &buffer, Int32(buffer.count))
                if written <= 0 {
                    return prompt
                }
                if written < buffer.count {
                    return String(cString: buffer)
                }
                var largerBuffer = [CChar](repeating: 0, count: Int(written) + 1)
                let largerWritten = llama_chat_apply_template(template, &message, 1, true, &largerBuffer, Int32(largerBuffer.count))
                guard largerWritten > 0, largerWritten < largerBuffer.count else {
                    return prompt
                }
                return String(cString: largerBuffer)
            }
        }
    }

    private func truncatePromptTokens(_ tokens: [llama_token], maxPromptTokens: Int) -> [llama_token] {
        guard tokens.count > maxPromptTokens else {
            return tokens
        }
        let headCount = min(256, maxPromptTokens / 3)
        let tailCount = maxPromptTokens - headCount
        return Array(tokens.prefix(headCount)) + Array(tokens.suffix(tailCount))
    }

    private func tokenize(_ text: String, addBOS: Bool) -> [llama_token] {
        let tokenCapacity = text.utf8.count + (addBOS ? 1 : 0) + 1
        let tokens = UnsafeMutablePointer<llama_token>.allocate(capacity: tokenCapacity)
        defer {
            tokens.deallocate()
        }

        let tokenCount = llama_tokenize(
            vocab,
            text,
            Int32(text.utf8.count),
            tokens,
            Int32(tokenCapacity),
            addBOS,
            false
        )
        guard tokenCount > 0 else {
            return []
        }
        return (0..<Int(tokenCount)).map { tokens[$0] }
    }

    private func appendTokenPiece(_ token: llama_token) -> String {
        pendingUTF8Bytes.append(contentsOf: tokenPiece(token))
        if let string = String(validatingUTF8: pendingUTF8Bytes + [0]) {
            pendingUTF8Bytes.removeAll()
            return string
        }
        return ""
    }

    private func flushPendingUTF8Bytes() -> String {
        guard !pendingUTF8Bytes.isEmpty else {
            return ""
        }
        let string = String(cString: pendingUTF8Bytes + [0])
        pendingUTF8Bytes.removeAll()
        return string
    }

    private func tokenPiece(_ token: llama_token) -> [CChar] {
        let initialCapacity: Int32 = 8
        let buffer = UnsafeMutablePointer<CChar>.allocate(capacity: Int(initialCapacity))
        defer {
            buffer.deallocate()
        }

        let count = llama_token_to_piece(vocab, token, buffer, initialCapacity, 0, false)
        if count >= 0 {
            return Array(UnsafeBufferPointer(start: buffer, count: Int(count)))
        }

        let requiredCapacity = Int(-count)
        let largerBuffer = UnsafeMutablePointer<CChar>.allocate(capacity: requiredCapacity)
        defer {
            largerBuffer.deallocate()
        }
        let largerCount = llama_token_to_piece(vocab, token, largerBuffer, Int32(requiredCapacity), 0, false)
        guard largerCount > 0 else {
            return []
        }
        return Array(UnsafeBufferPointer(start: largerBuffer, count: Int(largerCount)))
    }

}
#endif

enum LocalMedicalAIError: LocalizedError {
    case modelMissing
    case runtimeUnavailable
    case emptyResponse
    case unstableResponse

    var diagnosticSummary: String {
        switch self {
        case .modelMissing:
            "model-missing"
        case .runtimeUnavailable:
            "runtime-unavailable"
        case .emptyResponse:
            "empty-response"
        case .unstableResponse:
            "unstable-response"
        }
    }

    var errorDescription: String? {
        switch self {
        case .modelMissing:
            return "离线模型还未准备好，请先下载后再试。"
        case .runtimeUnavailable:
            return "离线智能体暂时不可用，请先使用在线智能体。"
        case .emptyResponse:
            return "离线智能体暂时没有返回结果，请稍后重试。"
        case .unstableResponse:
            return "端侧模型这次输出不稳定，没有作为正式回答展示。请换一种问法或稍后再试。"
        }
    }
}
