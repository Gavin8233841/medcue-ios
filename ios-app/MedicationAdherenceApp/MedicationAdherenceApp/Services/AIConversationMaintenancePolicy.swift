import Foundation

struct AIConversationMaintenancePolicy {
    private let quickPromptFragments = [
        "请只基于 App 内授权共享的今日提醒",
        "请只基于 App 内授权共享的药品信息和说明书摘要",
        "请只基于 App 内授权共享的服药记录",
        "请只基于 App 内授权共享的药品、服药记录",
        "请结合今日天气条件和 App 内授权共享的服药记录",
        "请结合今日环境提示和 App 内授权共享的服药记录",
        "请结合今日天气与环境提示和 App 内授权共享的服药记录",
        "请只回答如何在本 App 内识别、录入、核对或整理这些信息"
    ]

    func messagesForStatusMigration(
        in messages: [StoredAIChatMessage]
    ) -> [StoredAIChatMessage] {
        messages.filter {
            $0.role == .assistant && isStatusMessage($0.text)
        }
    }

    func messagesForUnavailableTransportPurge(
        in messages: [StoredAIChatMessage]
    ) -> [StoredAIChatMessage] {
        let orderedMessages = messages.sorted { $0.createdAt < $1.createdAt }
        var messageIDsToDelete: Set<UUID> = []

        for (index, message) in orderedMessages.enumerated() {
            guard message.role != .user,
                  normalizedLegacyMedicalAIStatusText(message.text) != nil
            else {
                continue
            }

            messageIDsToDelete.insert(message.id)
            guard index > 0 else {
                continue
            }
            let previousMessage = orderedMessages[index - 1]
            let gap = message.createdAt.timeIntervalSince(previousMessage.createdAt)
            if previousMessage.role == .user, gap >= 0, gap <= 120 {
                messageIDsToDelete.insert(previousMessage.id)
            }
        }

        return messages.filter { messageIDsToDelete.contains($0.id) }
    }

    func messagesForQuickPromptPurge(
        in messages: [StoredAIChatMessage]
    ) -> [StoredAIChatMessage] {
        messages.filter { message in
            message.role == .user
                && quickPromptFragments.contains {
                    message.text.contains($0)
                }
        }
    }

    func interruptedRequestRepairDrafts(
        in messages: [StoredAIChatMessage],
        now: Date,
        defaultProviderName: String,
        defaultModelName: String
    ) -> [AIChatResponseDraft] {
        let orderedMessages = messages.sorted { $0.createdAt < $1.createdAt }
        let staleCutoff = now.addingTimeInterval(-90)
        var drafts: [AIChatResponseDraft] = []

        for (index, message) in orderedMessages.enumerated()
        where message.role == .user && message.createdAt < staleCutoff {
            let nextMessage = orderedMessages.dropFirst(index + 1).first
            if let nextMessage, nextMessage.role != .user {
                continue
            }
            drafts.append(AIChatResponseDraft(
                role: .system,
                text: "上一次医疗智能体请求未完成，请重新发送。",
                createdAt: repairDate(after: message, before: nextMessage),
                providerName: message.providerName.isEmpty
                    ? defaultProviderName
                    : message.providerName,
                modelName: message.modelName.isEmpty
                    ? defaultModelName
                    : message.modelName,
                sharedScopesSummary: message.sharedScopesSummary
            ))
        }

        return drafts
    }

    private func isStatusMessage(_ text: String) -> Bool {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalizedLegacyMedicalAIStatusText(trimmedText) != nil
            || trimmedText.contains("医疗智能体暂时无法连接")
            || trimmedText.contains("医疗智能体响应超时")
            || trimmedText.contains("医疗智能体网络暂时无法连接")
            || trimmedText.contains("iPhone 当前网络无法连接医疗智能体")
            || trimmedText.contains("尚未获得共享授权")
            || trimmedText.contains("当前授权范围不足")
    }

    private func repairDate(
        after message: StoredAIChatMessage,
        before nextMessage: StoredAIChatMessage?
    ) -> Date {
        guard let nextMessage else {
            return message.createdAt.addingTimeInterval(1)
        }
        let gap = nextMessage.createdAt.timeIntervalSince(message.createdAt)
        guard gap > 0 else {
            return message.createdAt.addingTimeInterval(0.1)
        }
        return message.createdAt.addingTimeInterval(min(1, gap / 2))
    }
}
