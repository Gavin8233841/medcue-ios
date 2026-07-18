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
            .split(whereSeparator: { "。！？；;\n".contains($0) })
            .flatMap { rawStatement -> [(text: String, isRiskDescription: Bool)] in
                let statement = String(rawStatement)
                let statementIsConditionalRiskDescription = isConditionalRiskDescription(statement)
                return statement
                    .split(whereSeparator: { "，,".contains($0) })
                    .map { rawClause in
                        let clause = String(rawClause)
                        let isRiskDescription = containsSourceAttribution(clause)
                            || statementIsConditionalRiskDescription
                        return (clause, isRiskDescription)
                    }
            }
            .filter { !isNonActionableContext($0.text, isRiskDescription: $0.isRiskDescription) }
        let checks: [(String, [String])] = [
            ("diagnosis", ["可以诊断为", "可诊断为", "诊断为", "确诊为", "你患有", "你得了", "就是患有"]),
            ("prescription", [
                "建议开始服用", "可以开始服用", "应开始服用", "建议服用", "可以服用", "应服用",
                "应该服用", "开具处方", "给你开药", "续方即可"
            ]),
            ("stop-medication", ["可以停药", "应停药", "建议停药", "立即停药", "马上停药", "停止服用", "停止使用", "暂停使用"]),
            ("switch-medication", ["换成", "改用"]),
            ("frequency-change", [
                "调整频次", "调整频率", "服药频次从", "服药频率从", "每天改为", "每日改为",
                "增加服药次数", "减少服药次数"
            ]),
            ("dose-change", [
                "调整剂量为", "调整剂量", "剂量改为", "剂量增加到", "剂量减少到",
                "增加剂量", "减少剂量", "加大剂量", "降低剂量", "加量至", "减量至", "每次改为"
            ])
        ]

        return checks.compactMap { flag, phrases in
            treatmentDecisionStatements.contains { statement in
                phrases.contains { statement.text.contains($0) }
            } ? flag : nil
        }
    }

    private func containsSourceAttribution(_ statement: String) -> Bool {
        let markers = [
            "说明书提示", "说明书写明", "说明书原文",
            "标签提示", "标签写明", "原文提示", "原文写明"
        ]
        return markers.contains { statement.contains($0) }
    }

    private func isConditionalRiskDescription(_ statement: String) -> Bool {
        let conditions = ["如已有", "如出现"]
        let riskLimits = ["应避免使用", "不应超过", "应停止使用"]
        return conditions.contains { statement.contains($0) }
            && riskLimits.contains { statement.contains($0) }
    }

    private func isNonActionableContext(
        _ statement: String,
        isRiskDescription: Bool
    ) -> Bool {
        if isRiskDescription {
            return true
        }
        let markers = [
            "不要自行", "不应自行", "请勿自行", "不得擅自",
            "你问", "用户问", "问题是", "是否", "能否"
        ]
        return markers.contains { statement.contains($0) }
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
