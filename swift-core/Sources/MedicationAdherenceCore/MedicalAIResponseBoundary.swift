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
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return MedicalAIResponseBoundaryReview(
                originalMessage: message,
                displayMessage: messageWithSafetyNote("医疗 AI 暂无可读回复，请稍后重试。"),
                flags: ["empty-response"],
                appendedSafetyNote: true
            )
        }

        let flags = actionableInstructionFlags(in: trimmed)
        let alreadyHasExactSafetyNote = trimmed.hasSuffix(Self.safetyNote)

        return MedicalAIResponseBoundaryReview(
            originalMessage: message,
            displayMessage: messageWithSafetyNote(trimmed),
            flags: alreadyHasExactSafetyNote ? flags : flags + ["missing-safety-boundary"],
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

    private func actionableInstructionFlags(in message: String) -> [String] {
        let normalized = message.lowercased()
        let checks: [(String, [String])] = [
            ("stop-medication", ["可以停药", "应停药", "立即停药", "马上停药", "自行停药", "停止服用", "应避免使用", "避免使用或在医生指导下调整"]),
            ("dose-change", ["调整剂量为", "调整剂量", "剂量改为", "加量至", "减量至", "每天改为", "每次改为", "不应超过", "每日不超过", "单日剂量", "最大剂量"]),
            ("diagnosis", ["可诊断为", "诊断为", "确诊为", "就是患有"]),
            ("prescription", ["开具处方", "续方即可", "改用处方药", "换成处方药"]),
            ("avoid-professional-review", ["不用咨询医生", "无需咨询医生", "不用咨询药师", "无需咨询药师"])
        ]

        return checks.compactMap { flag, phrases in
            phrases.contains { normalized.contains($0) } ? flag : nil
        }
    }
}
