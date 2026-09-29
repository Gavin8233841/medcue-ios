import Foundation

public struct MedicalAIResponseBoundaryReview: Sendable, Equatable {
    public var originalMessage: String
    public var displayMessage: String
    public var flags: [String]
    public var appendedSafetyNote: Bool
    public var blockedActionableInstruction: Bool

    public init(
        originalMessage: String,
        displayMessage: String,
        flags: [String] = [],
        appendedSafetyNote: Bool = false,
        blockedActionableInstruction: Bool = false
    ) {
        self.originalMessage = originalMessage
        self.displayMessage = displayMessage
        self.flags = flags
        self.appendedSafetyNote = appendedSafetyNote
        self.blockedActionableInstruction = blockedActionableInstruction
    }
}

public struct MedicalAIResponseBoundaryGuard: Sendable {
    public static let safetyNote = "以上内容仅用于用药风险提示和复诊沟通，不能替代医生或药师判断。"
    private static let doseMultiplierPhrases = [
        "剂量加倍", "用量翻一番", "剂量翻倍", "加倍服用",
        "用量翻倍", "用量加倍", "药量翻倍", "药量加倍"
    ]
    private static let nonActionableMultiplierMarkers = [
        "不要自行", "不应自行", "请勿自行", "不得擅自",
        "不要把", "不应把", "请勿把", "不得把",
        "别把", "切勿把", "不可把", "不能把", "不建议",
        "你问", "用户问", "问题是", "是否", "能否", "能不能"
    ]

    public init() {}

    public func review(_ message: String) -> MedicalAIResponseBoundaryReview {
        let normalized = plainText(from: message)
        let trimmed = normalized.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return MedicalAIResponseBoundaryReview(
                originalMessage: message,
                displayMessage: messageWithSafetyNote("医疗智能体暂无可读回复，请稍后重试。"),
                flags: ["empty-response"],
                appendedSafetyNote: true
            )
        }

        let actionableFlags = actionableInstructionFlags(in: trimmed)
        if !actionableFlags.isEmpty {
            let safeMessage = "这条回复涉及诊断、处方或用药调整等治疗决策，不能作为操作依据。请联系医生或药师核对。"
            return MedicalAIResponseBoundaryReview(
                originalMessage: message,
                displayMessage: messageWithSafetyNote(safeMessage),
                flags: actionableFlags,
                appendedSafetyNote: true,
                blockedActionableInstruction: true
            )
        }

        let alreadyHasExactSafetyNote = trimmed.hasSuffix(Self.safetyNote)

        return MedicalAIResponseBoundaryReview(
            originalMessage: message,
            displayMessage: messageWithSafetyNote(trimmed),
            flags: displayFlags(
                normalizedFormatting: normalized.didNormalize,
                hasSafetyNote: alreadyHasExactSafetyNote
            ),
            appendedSafetyNote: !alreadyHasExactSafetyNote,
            blockedActionableInstruction: false
        )
    }

    private func messageWithSafetyNote(_ message: String) -> String {
        let baseMessage = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !baseMessage.hasSuffix(Self.safetyNote) else {
            return baseMessage
        }
        return [baseMessage, Self.safetyNote]
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }

    private func plainText(from message: String) -> (text: String, didNormalize: Bool) {
        var didNormalize = false
        let normalizedNewlines = message
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        if normalizedNewlines != message {
            didNormalize = true
        }

        let normalizedLines = normalizedNewlines
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { rawLine -> String in
                let original = String(rawLine)
                let line = normalizeMarkdownLine(original)
                if line != original {
                    didNormalize = true
                }
                return line
            }

        let text = normalizedLines
            .joined(separator: "\n")
            .replacingOccurrences(of: "\n\n\n", with: "\n\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (text, didNormalize)
    }

    private func normalizeMarkdownLine(_ line: String) -> String {
        var value = line.trimmingCharacters(in: .whitespaces)
        value = removeHeadingPrefix(from: value)
        value = removeListPrefix(from: value)

        let replacements: [(String, String)] = [
            ("```", ""),
            ("**", ""),
            ("__", ""),
            ("~~", ""),
            ("`", ""),
            ("|", "，"),
            ("$$", ""),
            ("$", ""),
            ("\\(", ""),
            ("\\)", ""),
            ("\\[", ""),
            ("\\]", "")
        ]
        for (target, replacement) in replacements {
            value = value.replacingOccurrences(of: target, with: replacement)
        }
        return value.trimmingCharacters(in: .whitespaces)
    }

    private func removeHeadingPrefix(from line: String) -> String {
        var value = line
        while value.first == "#" {
            value.removeFirst()
        }
        return value.trimmingCharacters(in: .whitespaces)
    }

    private func removeListPrefix(from line: String) -> String {
        let simplePrefixes = ["- ", "* ", "+ ", "• "]
        for prefix in simplePrefixes where line.hasPrefix(prefix) {
            return String(line.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
        }

        var digitCount = 0
        for character in line {
            if character.isNumber {
                digitCount += 1
            } else {
                break
            }
        }
        guard digitCount > 0,
              line.count > digitCount + 1
        else {
            return line
        }

        let markerIndex = line.index(line.startIndex, offsetBy: digitCount)
        let spaceIndex = line.index(after: markerIndex)
        if line[markerIndex] == ".", line[spaceIndex] == " " {
            return String(line[line.index(after: spaceIndex)...]).trimmingCharacters(in: .whitespaces)
        }
        return line
    }

    private func actionableInstructionFlags(in message: String) -> [String] {
        let treatmentDecisionStatements = message
            .split(whereSeparator: { "。！？?；;\n".contains($0) })
            .flatMap { rawStatement -> [(text: String, isRiskDescription: Bool)] in
                let statement = String(rawStatement)
                let clauses = statement.split(whereSeparator: { "，,".contains($0) })
                let hasConditionalRiskPrefix = clauses.first.map {
                    $0.contains("如已有") || $0.contains("如出现")
                } ?? false
                return clauses.enumerated().flatMap { index, rawClause in
                    let clause = String(rawClause)
                    return splitActionTransitions(clause).map { part in
                        let isRiskDescription = isConditionalRiskDescription(part)
                            || (index > 0 && hasConditionalRiskPrefix && isRiskLimitClause(part))
                        return (part, isRiskDescription)
                    }
                }
            }
            .filter {
                !isNonActionableContext($0.text, isRiskDescription: $0.isRiskDescription)
                    || hasUnnegatedMultiplier(in: $0.text)
            }
        let checks: [(String, [String])] = [
            ("diagnosis", ["可以诊断为", "可诊断为", "诊断为", "确诊为", "你患有", "你得了", "就是患有"]),
            ("prescription", [
                "建议开始服用", "可以开始服用", "应开始服用", "建议服用", "可以服用", "应服用",
                "应该服用", "开具处方", "给你开药", "续方即可"
            ]),
            ("stop-medication", [
                "可以停药", "应停药", "建议停药", "立即停药", "马上停药",
                "自行停药",
                "可以停用", "可停用", "应停用", "建议停用",
                "停止服用", "停止使用", "暂停使用"
            ]),
            ("switch-medication", ["换成", "改用"]),
            ("frequency-change", [
                "调整频次", "调整频率", "服药频次从", "服药频率从", "每天改为", "每日改为",
                "增加服药次数", "减少服药次数"
            ]),
            ("dose-change", [
                "调整剂量为", "调整剂量", "剂量改为", "剂量增加到", "剂量减少到",
                "增加剂量", "减少剂量", "加大剂量", "降低剂量", "加量至", "减量至",
                "逐渐减量", "逐步减量", "渐减剂量", "递减剂量", "每次改为"
            ] + Self.doseMultiplierPhrases)
        ]

        var flags = checks.compactMap { flag, phrases in
            treatmentDecisionStatements.contains { statement in
                phrases.contains { statement.text.contains($0) }
            } ? flag : nil
        }
        for statement in treatmentDecisionStatements.map(\.text) where !isCurrentDoseDescription(statement) {
            let lowercased = statement.lowercased()
            let hasDoseQuantity = lowercased.range(
                of: #"(?:[0-9]+(?:\.[0-9]+)?|[一二两三四五六七八九十半])\s*(?:片|粒|丸|毫克|mg|毫升|ml|tablets?|capsules?)"#,
                options: .regularExpression
            ) != nil
            let hasMedicationAction = [
                "服用", "吃", "每天", "每日", "每次", "一日", "一天", "剂量", "用量",
                "改为", "改成", "调到", "take", "tablet", "capsule"
            ].contains { lowercased.contains($0) }
            if hasDoseQuantity && hasMedicationAction && !flags.contains("dose-change") {
                flags.append("dose-change")
            }

            let hasFrequencyQuantity = lowercased.range(
                of: #"(?:[0-9]+|[一二两三四五六七八九十])\s*(?:次|times?)"#,
                options: .regularExpression
            ) != nil
            let hasFrequencyAction = ["每天", "每日", "一日", "服用", "用药", "daily", "per day"].contains {
                lowercased.contains($0)
            }
            if hasFrequencyQuantity && hasFrequencyAction && !flags.contains("frequency-change") {
                flags.append("frequency-change")
            }
        }
        return flags
    }

    private func isCurrentDoseDescription(_ statement: String) -> Bool {
        let trimmed = statement.trimmingCharacters(in: .whitespaces)
        let descriptionPrefixes = ["患者目前", "患者当前", "用户目前", "用户当前", "我目前", "我现在", "目前", "当前"]
        let actionMarkers = ["建议", "应", "可以", "必须", "改为", "改成", "调整", "增加", "减少", "加倍", "翻倍"]
        return descriptionPrefixes.contains { trimmed.hasPrefix($0) }
            && !actionMarkers.contains { trimmed.contains($0) }
    }

    private func splitActionTransitions(_ clause: String) -> [String] {
        let transitions = ["但是", "然后", "随后", "接着", "而是", "并且", "同时", "或者", "不过", "可是", "然而", "转而", "之后", "再", "但", "也", "却", "而", "还", "并", "后"]
        let answerFrames = ["我的建议是", "我的看法是", "我认为", "我建议", "我觉得", "我主张", "我答", "结论是", "答案是"]
        let actionPrefixes = ["把", "将", "建议", "应", "可以", "必须", "要", "不要", "不应", "请勿", "不得", "立即", "马上", "改为", "调整"]
        var parts: [String] = []
        var start = clause.startIndex
        var index = start
        var insideQuote = false

        while index < clause.endIndex {
            if clause[index] == "“" { insideQuote = true }
            if clause[index] == "”" { insideQuote = false }

            if !insideQuote, let frame = answerFrames.first(where: { clause[index...].hasPrefix($0) }) {
                let part = clause[start..<index].trimmingCharacters(in: .whitespaces)
                if !part.isEmpty { parts.append(part) }
                start = index
                index = clause.index(index, offsetBy: frame.count)
                continue
            }
            if !insideQuote, let transition = transitions.first(where: { clause[index...].hasPrefix($0) }) {
                let next = clause.index(index, offsetBy: transition.count)
                if actionPrefixes.contains(where: { clause[next...].hasPrefix($0) }) {
                    let part = clause[start..<index].trimmingCharacters(in: .whitespaces)
                    if !part.isEmpty { parts.append(part) }
                    start = next
                    index = next
                    continue
                }
            }
            index = clause.index(after: index)
        }

        let finalPart = clause[start...].trimmingCharacters(in: .whitespaces)
        if !finalPart.isEmpty { parts.append(finalPart) }
        return parts
    }

    private func hasUnnegatedMultiplier(in statement: String) -> Bool {
        var insideQuote = false
        var previousMatchEnd = statement.startIndex
        var index = statement.startIndex
        let isQuestion = isNonImperativeQuestion(statement)

        while index < statement.endIndex {
            if statement[index] == "“" { insideQuote = true }
            if statement[index] == "”" { insideQuote = false }

            if let phrase = Self.doseMultiplierPhrases.first(where: { statement[index...].hasPrefix($0) }) {
                let prefix = String(statement[previousMatchEnd..<index])
                let lastBoundaryEnd = Self.nonActionableMultiplierMarkers
                    .compactMap { prefix.range(of: $0, options: .backwards)?.upperBound }
                    .max()
                let interveningActions = ["停药", "停用", "换药", "加量", "减量", "然后", "随后", "之后", "并", "却", "而", "还", "我认为", "我建议", "我答"]
                let hasLocalBoundary = lastBoundaryEnd.map { boundaryEnd in
                    let trailing = prefix[boundaryEnd...]
                    return !interveningActions.contains { trailing.contains($0) }
                } ?? false
                if !insideQuote && !hasLocalBoundary && !isQuestion {
                    return true
                }
                index = statement.index(index, offsetBy: phrase.count)
                previousMatchEnd = index
                continue
            }
            index = statement.index(after: index)
        }
        return false
    }

    private func isNonImperativeQuestion(_ statement: String) -> Bool {
        let trimmed = statement.trimmingCharacters(in: .whitespaces)
        let questionPrefixes = [
            "是否", "能否", "能不能", "可否", "可以", "能", "需要", "要不要", "该不该",
            "我是否", "我能否", "我能不能", "我可以", "我能", "我该不该",
            "你问", "用户问", "请问", "药量可以", "用量可以", "剂量可以"
        ]
        return trimmed.hasSuffix("吗") && questionPrefixes.contains { trimmed.hasPrefix($0) }
    }

    private func isConditionalRiskDescription(_ statement: String) -> Bool {
        let conditions = ["如已有", "如出现"]
        return conditions.contains { statement.contains($0) }
            && isRiskLimitClause(statement)
    }

    private func isRiskLimitClause(_ clause: String) -> Bool {
        let riskLimits = ["应避免使用", "不应超过", "应停止使用"]
        let professionalReferral = ["咨询医生", "咨询药师", "联系医生", "联系药师"]
        let additionalDirections = [
            "建议", "可以", "改为", "加倍", "翻倍", "翻一番",
            "把", "每次", "每天", "每日", "换成", "改用", "换药"
        ]
        return riskLimits.contains { clause.contains($0) }
            && (!clause.contains("应停止使用") || professionalReferral.contains { clause.contains($0) })
            && !additionalDirections.contains { clause.contains($0) }
    }

    private func isNonActionableContext(
        _ statement: String,
        isRiskDescription: Bool
    ) -> Bool {
        if isRiskDescription {
            return true
        }
        if let closingQuote = statement.lastIndex(of: "”") {
            let followingText = statement[statement.index(after: closingQuote)...]
            if !actionableInstructionFlags(in: String(followingText)).isEmpty {
                return false
            }
            let safetyDescriptions = [
                "是错误建议", "不是正确建议", "请勿照做", "不要照做",
                "应由医生判断", "并不安全", "不安全", "不可取", "有风险"
            ]
            if safetyDescriptions.contains(where: { followingText.contains($0) }) {
                return true
            }
        }
        let laterAdvice = [
            "但建议", "但可以", "不过建议", "不过可以", "随后建议", "并建议",
            "然后建议", "接着建议", "我建议"
        ]
        if laterAdvice.contains(where: { statement.contains($0) }) {
            return false
        }
        let lowercased = statement.trimmingCharacters(in: .whitespaces).lowercased()
        if lowercased.hasPrefix("do not take ")
            && !lowercased.contains(" but take ")
            && !lowercased.contains(" then take ") {
            return true
        }
        return isNonImperativeQuestion(statement)
            || Self.nonActionableMultiplierMarkers.contains { statement.contains($0) }
    }

    private func displayFlags(normalizedFormatting: Bool, hasSafetyNote: Bool) -> [String] {
        var flags: [String] = []
        if normalizedFormatting {
            flags.append("plain-text-normalized")
        }
        if !hasSafetyNote {
            flags.append("missing-safety-boundary")
        }
        return flags
    }
}
