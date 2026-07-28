import Foundation
import MedicationAdherenceCore

struct AIConversationSendPlanningInput {
    let outgoingMessage: AIOutgoingMessage
    let hasAcknowledgedThirdPartyAgent: Bool
    let consent: StoredAIConsent?
    let configuration: MedicalAIConfiguration
    let readiness: MedicalAITransportReadiness
    let prefersLocalModel: Bool
    let localModelURL: URL?
    let hasUsableCloudKey: Bool
    let todayOpenMedicationNames: [String]
}

struct AIConversationCloudDispatch: Equatable {
    let userDraft: AIChatResponseDraft
    let request: MedicalAIRequest
    let sharedScopesSummary: String
    let configuration: MedicalAIConfiguration
}

struct AIConversationLocalDispatch: Equatable {
    let userDraft: AIChatResponseDraft
    let request: MedicalAIRequest
    let sharedScopesSummary: String
    let modelURL: URL
}

enum AIConversationSendDirective: Equatable {
    case ignored
    case showThirdPartyAgentNotice
    case showRuntimePicker([AIChatResponseDraft])
    case showConsent([AIChatResponseDraft])
    case reject([AIChatResponseDraft])
    case switchToOnline([AIChatResponseDraft])
    case sendCloud(AIConversationCloudDispatch)
    case sendLocal(AIConversationLocalDispatch)
}

struct AIConversationSendPlanner {
    func plan(
        input: AIConversationSendPlanningInput,
        makeRequest: (String, StoredAIConsent) -> MedicalAIRequest
    ) -> AIConversationSendDirective {
        guard input.hasAcknowledgedThirdPartyAgent else {
            return .showThirdPartyAgentNotice
        }
        let displayText = input.outgoingMessage.displayText
            .trimmingCharacters(in: .whitespacesAndNewlines)
        var requestText = input.outgoingMessage.requestText
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if displayText == "帮我核对今日用药注意事项",
           !input.todayOpenMedicationNames.isEmpty {
            requestText += "\n今日待处理药品：\(input.todayOpenMedicationNames.prefix(4).joined(separator: "、"))。"
        }
        guard !displayText.isEmpty, !requestText.isEmpty else {
            return .ignored
        }
        let canUseLocalModel = input.prefersLocalModel && input.localModelURL != nil
        guard canUseLocalModel || input.readiness.canSend else {
            return .showRuntimePicker([AIChatResponseDraft(
                role: .system,
                text: input.readiness.userFacingMessage
                    ?? "云端智能体尚未开启。快捷问题没有发送到外部服务；开启云端能力后即可使用在线智能体。",
                providerName: input.configuration.providerName,
                modelName: input.configuration.modelName,
                sharedScopesSummary: input.consent?.scopeSummary ?? "未授权"
            )])
        }
        let providerName = canUseLocalModel
            ? "离线智能体"
            : input.configuration.providerName
        let modelName = canUseLocalModel
            ? LocalMedicalModelStore.modelDisplayName
            : input.configuration.modelName
        let userDraft = AIChatResponseDraft(
            role: .user,
            text: displayText,
            providerName: providerName,
            modelName: modelName,
            sharedScopesSummary: input.consent?.scopeSummary ?? "未授权"
        )
        guard let consent = input.consent else {
            return .showConsent([userDraft, AIChatResponseDraft(
                role: .system,
                text: "尚未获得共享授权，因此没有读取任何用药数据。请先在授权页选择共享范围。",
                providerName: input.configuration.providerName,
                modelName: input.configuration.modelName,
                sharedScopesSummary: "未授权"
            )])
        }
        let request = makeRequest(requestText, consent)
        let missingScopes = MedicalAIRequestValidator().missingRequiredScopes(for: request)
        guard missingScopes.isEmpty else {
            let names = missingScopes.map(scopeDisplayName).sorted().joined(separator: "、")
            return .reject([userDraft, AIChatResponseDraft(
                role: .system,
                text: "当前授权范围不足，未发送请求。缺少：\(names)。",
                providerName: input.configuration.providerName,
                modelName: input.configuration.modelName,
                sharedScopesSummary: consent.scopeSummary
            )])
        }
        if input.prefersLocalModel, input.localModelURL == nil {
            return .switchToOnline([userDraft, AIChatResponseDraft(
                role: .system,
                text: "离线智能体暂时不可用，已切换为在线智能体。请重新发送这条消息。",
                providerName: "离线智能体",
                modelName: LocalMedicalModelStore.modelDisplayName,
                sharedScopesSummary: consent.scopeSummary
            )])
        }
        if input.prefersLocalModel, let modelURL = input.localModelURL {
            return .sendLocal(AIConversationLocalDispatch(
                userDraft: userDraft,
                request: request,
                sharedScopesSummary: consent.scopeSummary,
                modelURL: modelURL
            ))
        }
        if !input.hasUsableCloudKey {
            return .reject([userDraft, AIChatResponseDraft(
                role: .system,
                text: "医疗智能体暂时无法连接，未发送任何用药数据。请稍后重试。",
                providerName: input.configuration.providerName,
                modelName: input.configuration.modelName,
                sharedScopesSummary: consent.scopeSummary
            )])
        }
        if !input.prefersLocalModel {
            return .sendCloud(AIConversationCloudDispatch(
                userDraft: userDraft,
                request: request,
                sharedScopesSummary: consent.scopeSummary,
                configuration: input.configuration
            ))
        }
        return .ignored
    }

    private func scopeDisplayName(_ scope: MedicalAIDataScope) -> String {
        switch scope {
        case .medicationProfile:
            "药品信息"
        case .medicationPlans:
            "提醒计划"
        case .doseEvents:
            "服药记录"
        case .riskCards:
            "风险提醒"
        case .drugLabels:
            "说明书摘要"
        case .importDraft:
            "导入识别内容"
        }
    }
}
