import Foundation
import MedicationAdherenceCore
import Testing
@testable import MedicationAdherenceApp

struct AIConversationSendPlannerTests {
    @Test @MainActor
    func unacknowledgedAgentNoticeStopsBeforeContextBuild() {
        var didBuildRequest = false

        let directive = AIConversationSendPlanner().plan(
            input: AIConversationSendPlanningInput(
                outgoingMessage: AIOutgoingMessage(
                    displayText: "核对今日用药",
                    requestText: "请核对今日用药"
                ),
                hasAcknowledgedThirdPartyAgent: false,
                consent: nil,
                configuration: MedicalAIConfiguration(
                    providerName: "测试智能体",
                    modelName: "test-model",
                    endpointURLString: "https://example.com/v1/respond",
                    hasAPIKey: true
                ),
                readiness: MedicalAITransportReadiness(
                    canSend: true,
                    userFacingMessage: nil,
                    diagnosticSummary: "ready"
                ),
                prefersLocalModel: false,
                localModelURL: nil,
                hasUsableCloudKey: true,
                todayOpenMedicationNames: []
            ),
            makeRequest: { _, _ in
                didBuildRequest = true
                Issue.record("未确认声明时不应构建医疗上下文")
                fatalError("request builder must not run")
            }
        )

        #expect(directive == .showThirdPartyAgentNotice)
        #expect(!didBuildRequest)
    }

    @Test @MainActor
    func unavailableRuntimeStopsBeforeContextBuild() throws {
        var didBuildRequest = false

        let directive = AIConversationSendPlanner().plan(
            input: AIConversationSendPlanningInput(
                outgoingMessage: AIOutgoingMessage(
                    displayText: "核对今日用药",
                    requestText: "请核对今日用药"
                ),
                hasAcknowledgedThirdPartyAgent: true,
                consent: nil,
                configuration: MedicalAIConfiguration(
                    providerName: "测试智能体",
                    modelName: "test-model",
                    endpointURLString: "https://example.com/v1/respond",
                    hasAPIKey: false
                ),
                readiness: MedicalAITransportReadiness(
                    canSend: false,
                    userFacingMessage: "测试智能体尚未开启。",
                    diagnosticSummary: "unavailable"
                ),
                prefersLocalModel: false,
                localModelURL: nil,
                hasUsableCloudKey: false,
                todayOpenMedicationNames: []
            ),
            makeRequest: { _, _ in
                didBuildRequest = true
                Issue.record("运行时不可用时不应构建医疗上下文")
                fatalError("request builder must not run")
            }
        )

        guard case let .showRuntimePicker(drafts) = directive else {
            Issue.record("应要求用户选择或配置运行时")
            return
        }
        let draft = try #require(drafts.first)
        #expect(drafts.count == 1)
        #expect(draft.role == .system)
        #expect(draft.text == "测试智能体尚未开启。")
        #expect(!didBuildRequest)
    }

    @Test @MainActor
    func missingConsentCreatesLocalExplanationWithoutContextBuild() throws {
        var didBuildRequest = false

        let directive = AIConversationSendPlanner().plan(
            input: AIConversationSendPlanningInput(
                outgoingMessage: AIOutgoingMessage(
                    displayText: "  核对今日用药  ",
                    requestText: "  请核对今日用药  "
                ),
                hasAcknowledgedThirdPartyAgent: true,
                consent: nil,
                configuration: MedicalAIConfiguration(
                    providerName: "测试智能体",
                    modelName: "test-model",
                    endpointURLString: "https://example.com/v1/respond",
                    hasAPIKey: true
                ),
                readiness: MedicalAITransportReadiness(
                    canSend: true,
                    userFacingMessage: nil,
                    diagnosticSummary: "ready"
                ),
                prefersLocalModel: false,
                localModelURL: nil,
                hasUsableCloudKey: true,
                todayOpenMedicationNames: []
            ),
            makeRequest: { _, _ in
                didBuildRequest = true
                Issue.record("缺少授权时不应构建医疗上下文")
                fatalError("request builder must not run")
            }
        )

        guard case let .showConsent(drafts) = directive else {
            Issue.record("应要求用户确认共享范围")
            return
        }
        #expect(drafts.count == 2)
        #expect(drafts.first?.role == .user)
        #expect(drafts.first?.text == "核对今日用药")
        #expect(drafts.last?.role == .system)
        #expect(!didBuildRequest)
    }

    @Test @MainActor
    func missingRequiredScopeRejectsBeforeDispatch() throws {
        let consent = StoredAIConsent(
            sharesMedicationProfile: false,
            sharesMedicationPlans: false,
            sharesDoseEvents: false,
            sharesRiskCards: false,
            sharesDrugLabels: false
        )
        let request = MedicalAIRequest(
            kind: .chat,
            userMessage: "介绍我的药品",
            authorization: consent.authorization,
            medicationSnapshots: [MedicalAIMedicationSnapshot(
                medication: Medication(
                    displayName: "测试药",
                    kind: .prescription,
                    inputSource: .manual
                )
            )]
        )

        let directive = AIConversationSendPlanner().plan(
            input: AIConversationSendPlanningInput(
                outgoingMessage: AIOutgoingMessage(
                    displayText: "介绍我的药品",
                    requestText: "介绍我的药品"
                ),
                hasAcknowledgedThirdPartyAgent: true,
                consent: consent,
                configuration: MedicalAIConfiguration(
                    providerName: "测试智能体",
                    modelName: "test-model",
                    endpointURLString: "https://example.com/v1/respond",
                    hasAPIKey: true
                ),
                readiness: MedicalAITransportReadiness(
                    canSend: true,
                    userFacingMessage: nil,
                    diagnosticSummary: "ready"
                ),
                prefersLocalModel: false,
                localModelURL: nil,
                hasUsableCloudKey: true,
                todayOpenMedicationNames: []
            ),
            makeRequest: { _, _ in request }
        )

        guard case let .reject(drafts) = directive else {
            Issue.record("缺少必要 scope 时应拒绝发送")
            return
        }
        #expect(drafts.count == 2)
        #expect(drafts.first?.role == .user)
        #expect(drafts.last?.text.contains("药品信息") == true)
    }

    @Test @MainActor
    func unavailablePreferredLocalRuntimeSwitchesToOnlineWithoutDispatch() {
        let consent = StoredAIConsent()
        let request = MedicalAIRequest(
            kind: .chat,
            userMessage: "测试",
            authorization: consent.authorization
        )

        let directive = AIConversationSendPlanner().plan(
            input: AIConversationSendPlanningInput(
                outgoingMessage: AIOutgoingMessage(displayText: "测试", requestText: "测试"),
                hasAcknowledgedThirdPartyAgent: true,
                consent: consent,
                configuration: MedicalAIConfiguration(
                    providerName: "测试智能体",
                    modelName: "test-model",
                    endpointURLString: "https://example.com/v1/respond",
                    hasAPIKey: true
                ),
                readiness: MedicalAITransportReadiness(
                    canSend: true,
                    userFacingMessage: nil,
                    diagnosticSummary: "ready"
                ),
                prefersLocalModel: true,
                localModelURL: nil,
                hasUsableCloudKey: true,
                todayOpenMedicationNames: []
            ),
            makeRequest: { _, _ in request }
        )

        guard case let .switchToOnline(drafts) = directive else {
            Issue.record("离线运行时不可用时应明确切换到在线模式")
            return
        }
        #expect(drafts.count == 2)
        #expect(drafts.last?.text.contains("已切换为在线智能体") == true)
    }

    @Test @MainActor
    func readyCloudRuntimeReturnsCommitBeforeDispatchPlan() {
        let consent = StoredAIConsent()
        let request = MedicalAIRequest(
            kind: .chat,
            userMessage: "测试云端请求",
            authorization: consent.authorization
        )
        let configuration = MedicalAIConfiguration(
            providerName: "测试智能体",
            modelName: "test-model",
            endpointURLString: "https://example.com/v1/respond",
            hasAPIKey: true
        )

        let directive = AIConversationSendPlanner().plan(
            input: AIConversationSendPlanningInput(
                outgoingMessage: AIOutgoingMessage(
                    displayText: "测试云端请求",
                    requestText: "测试云端请求"
                ),
                hasAcknowledgedThirdPartyAgent: true,
                consent: consent,
                configuration: configuration,
                readiness: MedicalAITransportReadiness(
                    canSend: true,
                    userFacingMessage: nil,
                    diagnosticSummary: "ready"
                ),
                prefersLocalModel: false,
                localModelURL: nil,
                hasUsableCloudKey: true,
                todayOpenMedicationNames: []
            ),
            makeRequest: { _, _ in request }
        )

        guard case let .sendCloud(dispatch) = directive else {
            Issue.record("全部云端门槛通过时应返回派发计划")
            return
        }
        #expect(dispatch.userDraft.text == "测试云端请求")
        #expect(dispatch.request == request)
        #expect(dispatch.configuration == configuration)
        #expect(dispatch.sharedScopesSummary == consent.scopeSummary)
    }

    @Test @MainActor
    func readyLocalRuntimeReturnsCommitBeforeDispatchPlan() {
        let consent = StoredAIConsent()
        let request = MedicalAIRequest(
            kind: .chat,
            userMessage: "测试离线请求",
            authorization: consent.authorization
        )
        let modelURL = URL(fileURLWithPath: "/tmp/test-model.gguf")

        let directive = AIConversationSendPlanner().plan(
            input: AIConversationSendPlanningInput(
                outgoingMessage: AIOutgoingMessage(
                    displayText: "测试离线请求",
                    requestText: "测试离线请求"
                ),
                hasAcknowledgedThirdPartyAgent: true,
                consent: consent,
                configuration: MedicalAIConfiguration(
                    providerName: "测试智能体",
                    modelName: "test-model",
                    endpointURLString: "https://example.com/v1/respond",
                    hasAPIKey: false
                ),
                readiness: MedicalAITransportReadiness(
                    canSend: false,
                    userFacingMessage: "在线运行时未开启",
                    diagnosticSummary: "not-ready"
                ),
                prefersLocalModel: true,
                localModelURL: modelURL,
                hasUsableCloudKey: false,
                todayOpenMedicationNames: []
            ),
            makeRequest: { _, _ in request }
        )

        guard case let .sendLocal(dispatch) = directive else {
            Issue.record("离线模型可用时应返回本地派发计划")
            return
        }
        #expect(dispatch.userDraft.text == "测试离线请求")
        #expect(dispatch.request == request)
        #expect(dispatch.modelURL == modelURL)
        #expect(dispatch.sharedScopesSummary == consent.scopeSummary)
    }

    @Test @MainActor
    func missingCloudKeyRejectsBeforeDispatch() {
        let consent = StoredAIConsent()
        let request = MedicalAIRequest(
            kind: .chat,
            userMessage: "测试云端密钥门槛",
            authorization: consent.authorization
        )

        let directive = AIConversationSendPlanner().plan(
            input: AIConversationSendPlanningInput(
                outgoingMessage: AIOutgoingMessage(
                    displayText: "测试云端密钥门槛",
                    requestText: "测试云端密钥门槛"
                ),
                hasAcknowledgedThirdPartyAgent: true,
                consent: consent,
                configuration: MedicalAIConfiguration(
                    providerName: "测试智能体",
                    modelName: "test-model",
                    endpointURLString: "https://example.com/v1/respond",
                    hasAPIKey: true
                ),
                readiness: MedicalAITransportReadiness(
                    canSend: true,
                    userFacingMessage: nil,
                    diagnosticSummary: "ready"
                ),
                prefersLocalModel: false,
                localModelURL: nil,
                hasUsableCloudKey: false,
                todayOpenMedicationNames: []
            ),
            makeRequest: { _, _ in request }
        )

        guard case let .reject(drafts) = directive else {
            Issue.record("缺少可用云端凭据时必须拒绝派发")
            return
        }
        #expect(drafts.count == 2)
        #expect(drafts.first?.role == .user)
        #expect(drafts.last?.text.contains("未发送任何用药数据") == true)
    }

    @Test @MainActor
    func todayReviewAddsAtMostFourMedicationNamesToRequestOnly() {
        let consent = StoredAIConsent()

        let directive = AIConversationSendPlanner().plan(
            input: AIConversationSendPlanningInput(
                outgoingMessage: AIOutgoingMessage(
                    displayText: "帮我核对今日用药注意事项",
                    requestText: "帮我核对今日用药注意事项"
                ),
                hasAcknowledgedThirdPartyAgent: true,
                consent: consent,
                configuration: MedicalAIConfiguration(
                    providerName: "测试智能体",
                    modelName: "test-model",
                    endpointURLString: "https://example.com/v1/respond",
                    hasAPIKey: true
                ),
                readiness: MedicalAITransportReadiness(
                    canSend: true,
                    userFacingMessage: nil,
                    diagnosticSummary: "ready"
                ),
                prefersLocalModel: false,
                localModelURL: nil,
                hasUsableCloudKey: true,
                todayOpenMedicationNames: ["药品一", "药品二", "药品三", "药品四", "药品五"]
            ),
            makeRequest: { text, consent in
                MedicalAIRequest(
                    kind: .chat,
                    userMessage: text,
                    authorization: consent.authorization
                )
            }
        )

        guard case let .sendCloud(dispatch) = directive else {
            Issue.record("今日重点核对通过门槛后应返回云端派发计划")
            return
        }
        #expect(dispatch.userDraft.text == "帮我核对今日用药注意事项")
        #expect(dispatch.request.userMessage.contains("药品一、药品二、药品三、药品四"))
        #expect(!dispatch.request.userMessage.contains("药品五"))
    }
}
