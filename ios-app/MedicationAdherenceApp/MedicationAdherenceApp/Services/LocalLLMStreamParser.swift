import Foundation

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
    private var buffer = ""
    private var emittedThinkingCount = 0
    private var emittedAnswerCount = 0
    private var hasStartedThinking = false
    private var hasStartedAnswer = false

    static func parseComplete(_ text: String) -> (thinking: String, answer: String) {
        Self().parse(text, isFinal: true)
    }

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
        let normalized = stableRenderableText(text, isFinal: isFinal)
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
        return ("", trimmed)
    }

    private func stableRenderableText(_ text: String, isFinal: Bool) -> String {
        let sanitized = sanitizedRenderableText(text)
        guard !isFinal, let tagStart = sanitized.lastIndex(of: "<") else {
            return sanitized
        }
        let tail = String(sanitized[tagStart...]).lowercased()
        let controlTags = [
            "<think>", "</think>", "<thought>", "</thought>",
            "<answer>", "</answer>",
            "<final>", "</final>",
            "<|im_start|>", "<|im_end|>"
        ]
        guard controlTags.contains(where: { $0.hasPrefix(tail) && $0 != tail }) else {
            return sanitized
        }
        return String(sanitized[..<tagStart])
    }

    private func parseTagged(_ text: String, isFinal: Bool) -> (thinking: String, answer: String)? {
        let thinkingTags = [("<think>", "</think>"), ("<thought>", "</thought>")]
        let answerStartTags = ["<answer>", "<final>"]
        let answerEndTags = ["</answer>", "</final>"]

        let firstThinkingTag = thinkingTags.compactMap { startTag, endTag in
            rangeOfControlTag(startTag, in: text).map { (start: $0, endTag: endTag) }
        }.min { $0.start.lowerBound < $1.start.lowerBound }
        if let thinkStart = firstThinkingTag?.start,
           let thinkEndTag = firstThinkingTag?.endTag {
            let thinkingStartIndex = thinkStart.upperBound
            if let thinkEnd = rangeOfControlTag(thinkEndTag, in: text, range: thinkingStartIndex..<text.endIndex) {
                let thinking = cleanupVisibleText(String(text[thinkingStartIndex..<thinkEnd.lowerBound]))
                let afterThink = String(text[thinkEnd.upperBound...])
                let remainder = parseTagged(afterThink, isFinal: isFinal)
                let combinedThinking = [thinking, remainder?.thinking ?? ""]
                    .filter { !$0.isEmpty }
                    .joined(separator: "\n\n")
                return (combinedThinking, remainder?.answer ?? cleanupVisibleText(afterThink))
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
        for startTag in startTags {
            guard let start = rangeOfControlTag(startTag, in: text) else {
                continue
            }
            let answerStart = start.upperBound
            let matchingEndTags = endTags.filter { $0.contains(startTag.replacingOccurrences(of: "<", with: "</")) || endTags.count > 1 }
            let endRange = matchingEndTags.compactMap { tag in
                rangeOfControlTag(tag, in: text, range: answerStart..<text.endIndex)
            }.min { $0.lowerBound < $1.lowerBound }
            if let endRange {
                return cleanupVisibleText(String(text[answerStart..<endRange.lowerBound]))
            }
            return cleanupVisibleText(String(text[answerStart...]))
        }
        return nil
    }

    private func rangeOfControlTag(
        _ tag: String,
        in text: String,
        range: Range<String.Index>? = nil
    ) -> Range<String.Index>? {
        let searchRange = range ?? (text.startIndex..<text.endIndex)
        var searchStart = searchRange.lowerBound
        while searchStart < searchRange.upperBound,
              let match = text.range(
                of: tag,
                options: .caseInsensitive,
                range: searchStart..<searchRange.upperBound
              ) {
            // Keep indices in the original string: lowercasing may change its
            // UTF-8 length. Validate the small match to retain the existing tag
            // grammar rather than accepting extra folds such as long-s/ligatures.
            if text[match].lowercased() == tag {
                return match
            }
            searchStart = match.upperBound
        }
        return nil
    }

    private func parseWeakSeparators(_ text: String) -> (thinking: String, answer: String)? {
        let markers = ["正式回答：", "最终回答：", "答案：", "回答：", "Answer:"]
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
            .replacingOccurrences(of: "<thought>", with: "")
            .replacingOccurrences(of: "</thought>", with: "")
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
