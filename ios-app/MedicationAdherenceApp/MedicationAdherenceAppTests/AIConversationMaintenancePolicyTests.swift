import Foundation
import Testing
@testable import MedicationAdherenceApp

struct AIConversationMaintenancePolicyTests {
    @Test
    func unavailableTransportPurgeIncludesOnlyNearbyUserRequest() {
        let policy = AIConversationMaintenancePolicy()
        let nearbyUser = message(
            role: .user,
            text: "附近请求",
            createdAt: Date(timeIntervalSince1970: 100)
        )
        let unavailable = message(
            role: .system,
            text: "医疗 AI 暂不可用",
            createdAt: Date(timeIntervalSince1970: 180)
        )
        let oldUser = message(
            role: .user,
            text: "较早请求",
            createdAt: Date(timeIntervalSince1970: 300)
        )
        let secondUnavailable = message(
            role: .assistant,
            text: "医疗 AI 网络连接暂时不可用",
            createdAt: Date(timeIntervalSince1970: 500)
        )

        let selected = policy.messagesForUnavailableTransportPurge(
            in: [secondUnavailable, oldUser, unavailable, nearbyUser]
        )

        #expect(Set(selected.map(\.id)) == [nearbyUser.id, unavailable.id, secondUnavailable.id])
    }

    @Test
    func interruptedRequestRepairUsesStablePlacementAndProviderFallback() {
        let policy = AIConversationMaintenancePolicy()
        let interrupted = message(
            role: .user,
            text: "未完成请求",
            createdAt: Date(timeIntervalSince1970: 100),
            sharedScopesSummary: "药品信息"
        )
        let nextUser = message(
            role: .user,
            text: "下一条请求",
            createdAt: Date(timeIntervalSince1970: 101)
        )

        let drafts = policy.interruptedRequestRepairDrafts(
            in: [nextUser, interrupted],
            now: Date(timeIntervalSince1970: 1_000),
            defaultProviderName: "默认服务",
            defaultModelName: "default-model"
        )

        #expect(drafts.count == 2)
        #expect(drafts[0].createdAt == Date(timeIntervalSince1970: 100.5))
        #expect(drafts[0].providerName == "默认服务")
        #expect(drafts[0].modelName == "default-model")
        #expect(drafts[0].sharedScopesSummary == "药品信息")
        #expect(drafts[1].createdAt == Date(timeIntervalSince1970: 102))
    }

    @Test
    func statusMigrationSelectsOnlyAssistantStatusMessages() {
        let policy = AIConversationMaintenancePolicy()
        let assistantStatus = message(
            role: .assistant,
            text: "当前授权范围不足",
            createdAt: .distantPast
        )
        let userStatusText = message(
            role: .user,
            text: "当前授权范围不足",
            createdAt: .distantPast
        )
        let normalAssistant = message(
            role: .assistant,
            text: "已整理授权范围内的信息。",
            createdAt: .distantPast
        )

        let selected = policy.messagesForStatusMigration(
            in: [assistantStatus, userStatusText, normalAssistant]
        )

        #expect(selected.map(\.id) == [assistantStatus.id])
    }

    @Test
    func quickPromptPurgeDoesNotDeleteAssistantExplanation() {
        let policy = AIConversationMaintenancePolicy()
        let promptText = "请只基于 App 内授权共享的今日提醒，整理待办。"
        let userPrompt = message(role: .user, text: promptText, createdAt: .distantPast)
        let assistantExplanation = message(
            role: .assistant,
            text: promptText,
            createdAt: .distantPast
        )

        let selected = policy.messagesForQuickPromptPurge(
            in: [assistantExplanation, userPrompt]
        )

        #expect(selected.map(\.id) == [userPrompt.id])
    }

    private func message(
        role: StoredAIChatRole,
        text: String,
        createdAt: Date,
        providerName: String = "",
        modelName: String = "",
        sharedScopesSummary: String = ""
    ) -> StoredAIChatMessage {
        StoredAIChatMessage(
            role: role,
            text: text,
            createdAt: createdAt,
            providerName: providerName,
            modelName: modelName,
            sharedScopesSummary: sharedScopesSummary
        )
    }
}
