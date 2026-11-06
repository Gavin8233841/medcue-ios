import MedicationAdherenceCore
import PhotosUI
import SwiftData
import SwiftUI
import UIKit

struct AIAssistantView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.activeAppTab) private var activeAppTab
    @Query(sort: \StoredAIChatMessage.createdAt) private var messages: [StoredAIChatMessage]
    @Query(sort: \StoredAIConsent.grantedAt, order: .reverse) private var consents: [StoredAIConsent]
    @Query(sort: \StoredMedication.displayName) private var medications: [StoredMedication]
    @Query(sort: \StoredMedicationPlan.createdAt) private var plans: [StoredMedicationPlan]
    @Query(sort: \StoredDoseTask.dueAt, order: .reverse) private var tasks: [StoredDoseTask]
    @Query(sort: \StoredRiskCard.displayPriority) private var riskCards: [StoredRiskCard]
    @Query(sort: \StoredMedicationLabel.importedAt, order: .reverse) private var labels: [StoredMedicationLabel]
    @Environment(\.pendingMedicationAIQuestion) private var pendingMedicationAIQuestion
    @Environment(\.clearPendingMedicationAIQuestion) private var clearPendingMedicationAIQuestion
    @StateObject private var configurationStore = SecureAIConfigurationStore()
    @StateObject private var localModelStore = LocalMedicalModelStore()
    @AppStorage("hasAcceptedMedicalAIDisclaimer") private var hasAcceptedMedicalAIDisclaimer = false
    @AppStorage("hasAcknowledgedThirdPartyMedicalAgent") private var hasAcknowledgedThirdPartyMedicalAgent = false
    @AppStorage("hasPurgedPreProviderDemoMessagesV4") private var hasPurgedPreProviderDemoMessages = false
    @AppStorage("hasPurgedUnavailableMedicalAITransportMessagesV2") private var hasPurgedUnavailableMedicalAITransportMessages = false
    @AppStorage("hasPurgedVisibleQuickPromptMessagesV1") private var hasPurgedVisibleQuickPromptMessages = false
    @AppStorage("archivedMedicalAIMessageIDsV1") private var archivedMessageIDStorage = ""
    @AppStorage("prefersLocalMedicalModelV1") private var prefersLocalMedicalModel = false
    @AppStorage("hasUserSelectedMedicalAIRuntimeV1") private var hasUserSelectedMedicalAIRuntime = false
    @State private var draftMessage = ""
    @State private var showingConsentSheet = false
    @State private var showingThirdPartyAgentNotice = false
    @State private var showingArchivedMessages = false
    @State private var showingRuntimePicker = false
    @State private var showingLocalModelDownloadConfirmation = false
    @State private var isSending = false
    @State private var isReadingImage = false
    @State private var selectedChatImageItem: PhotosPickerItem?
    @State private var didPrepareVisibleSession = false
    @State private var localStreamingResponse: LocalStreamingAIResponse?
    @State private var activeAIRequestTask: Task<Void, Never>?
    @State private var activeAIRequestID: UUID?
    @State private var imageRecognitionTask: Task<Void, Never>?
    @State private var imageRecognitionGate = VisionImportGenerationGate()
    @FocusState private var isChatInputFocused: Bool

    init() {
        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: Date())
        let queryStart = calendar.date(byAdding: .day, value: -90, to: todayStart) ?? todayStart.addingTimeInterval(-7_776_000)
        let queryEnd = calendar.date(byAdding: .day, value: 8, to: todayStart) ?? todayStart.addingTimeInterval(691_200)
        _tasks = Query(
            filter: #Predicate<StoredDoseTask> { task in
                task.dueAt >= queryStart && task.dueAt < queryEnd
            },
            sort: \StoredDoseTask.dueAt,
            order: .reverse
        )
    }

    private var storedConsent: StoredAIConsent? {
        consents.first { $0.id == "medical-ai-consent" }
    }

    private var activeConsent: StoredAIConsent? {
        consents.first { $0.id == "medical-ai-consent" && $0.isActive }
    }

    private var conversationVisibility: AIConversationVisibilityProjection {
        AIConversationVisibilityProjection(
            messages: messages,
            manuallyArchivedMessageIDs: manuallyArchivedMessageIDs
        )
    }

    private var visibleMessages: [StoredAIChatMessage] {
        conversationVisibility.visibleMessages
    }

    private var archivedMessages: [StoredAIChatMessage] {
        conversationVisibility.archivedMessages
    }

    private var manuallyArchivedMessageIDs: Set<UUID> {
        Set(archivedMessageIDStorage.split(separator: "|").compactMap { UUID(uuidString: String($0)) })
    }

    private var environmentRefreshSignature: String {
        medications
            .filter { $0.lifecycleStatus == .active }
            .map { medication in
                [
                    medication.id.uuidString,
                    userFacingMedicationName(for: medication),
                    medication.genericName,
                    medication.form,
                    medication.notes
                ].joined(separator: "::")
            }
            .sorted()
            .joined(separator: "|")
    }

    var body: some View {
        let configuration = configurationStore.configuration
        let visible = conversationVisibility.visibleMessages
        let visibleIDs = Set(visible.map(\.id))
        let archived = messages.filter { !visibleIDs.contains($0.id) }
        AIAssistantScreen(
            configuration: configuration,
            onlineReadiness: configurationStore.readiness(for: configuration),
            localModelStatus: localModelStore.status,
            visibleMessages: visible,
            archivedMessages: archived,
            localStreamingResponse: localStreamingResponse,
            isSending: isSending,
            isReadingImage: isReadingImage,
            isInputEnabled: hasAcknowledgedThirdPartyMedicalAgent,
            prefersLocalResponses: prefersLocalMedicalModel,
            hasUserSelectedRuntime: hasUserSelectedMedicalAIRuntime,
            draftMessage: $draftMessage,
            selectedImageItem: $selectedChatImageItem,
            isChatInputFocused: $isChatInputFocused,
            showingThirdPartyAgentNotice: $showingThirdPartyAgentNotice,
            showingConsentSheet: $showingConsentSheet,
            showingArchivedMessages: $showingArchivedMessages,
            showingRuntimePicker: $showingRuntimePicker,
            showingLocalModelDownloadConfirmation: $showingLocalModelDownloadConfirmation,
            storedConsent: storedConsent,
            sendMessage: sendMessage,
            selectOnlineRuntime: selectOnlineRuntime,
            selectLocalRuntime: selectLocalRuntime,
            archiveVisibleConversation: archiveVisibleConversation,
            dismissChatKeyboard: dismissChatKeyboard,
            prepareSession: prepareAssistantSessionIfVisible,
            handleActiveTabChange: handleActiveTabChange,
            beginImageRecognition: beginImageRecognition,
            capturedImage: beginCameraImageRecognition,
            applyPendingQuestion: applyPendingQuestionIfNeeded,
            refreshEnvironment: {},
            acceptThirdPartyNotice: acceptThirdPartyNotice,
            saveConsent: saveConsent,
            revokeConsent: revokeConsent,
            deleteArchivedMessages: deleteArchivedMessages,
            deleteAllArchivedMessages: deleteAllArchivedMessages,
            requestLocalModelDownload: requestLocalModelDownload,
            environmentRefreshSignature: environmentRefreshSignature
        )
    }

    private func handleActiveTabChange(_ newTab: AppTab?) {
        if newTab != nil, newTab != .assistant {
            cancelActiveAIRequest()
            cancelImageRecognition()
        }
        prepareAssistantSessionIfVisible()
    }

    private func acceptThirdPartyNotice() {
        hasAcknowledgedThirdPartyMedicalAgent = true
        hasAcceptedMedicalAIDisclaimer = true
        showingThirdPartyAgentNotice = false
        if activeConsent == nil {
            showingConsentSheet = true
        }
    }

    private func requestLocalModelDownload() {
        Task {
            await localModelStore.downloadModel()
        }
    }

    private func prepareAssistantSessionIfVisible() {
        guard activeAppTab == nil || activeAppTab == .assistant else {
            return
        }
        purgePreProviderDemoMessagesIfNeeded()
        migrateLegacyMedicalAIStatusMessagesIfNeeded()
        purgeUnavailableMedicalAITransportMessagesIfNeeded()
        purgeVisibleQuickPromptMessagesIfNeeded()
        reconcileInterruptedMedicalAIRequestsIfNeeded()
        applyPendingQuestionIfNeeded()
        localModelStore.refresh()
        migrateSelectedRuntimePreferenceIfNeeded()
        guard !didPrepareVisibleSession else {
            return
        }
        didPrepareVisibleSession = true
        if !hasAcknowledgedThirdPartyMedicalAgent {
            showingThirdPartyAgentNotice = true
        } else if activeConsent == nil {
            showingConsentSheet = true
        }
    }

    private func migrateSelectedRuntimePreferenceIfNeeded() {
        guard prefersLocalMedicalModel, !hasUserSelectedMedicalAIRuntime else {
            return
        }
        hasUserSelectedMedicalAIRuntime = true
    }

    private func sendMessage() {
        sendOutgoingMessage(AIOutgoingMessage(displayText: draftMessage, requestText: draftMessage))
    }

    private func sendMessage(_ quickMessage: AIOutgoingMessage?) {
        guard let quickMessage else {
            sendMessage()
            return
        }
        sendOutgoingMessage(quickMessage)
    }

    private func selectOnlineRuntime() {
        prefersLocalMedicalModel = false
        hasUserSelectedMedicalAIRuntime = true
        withAnimation(.snappy(duration: 0.22, extraBounce: 0.02)) {
            showingRuntimePicker = false
        }
        let configuration = configurationStore.refreshInjectedSecretsIfAvailable()
        let readiness = configurationStore.readiness(for: configuration)
        guard !readiness.canSend else {
            return
        }
        _ = commitConversationMessages([AIChatResponseDraft(
            role: .system,
            text: "云端智能体尚未开启。开启云端能力后，在线模式才会连接外部服务；未开启时不会发送任何用药数据。",
            providerName: configuration.providerName,
            modelName: configuration.modelName,
            sharedScopesSummary: activeConsent?.scopeSummary ?? "未授权"
        )], operation: "ai-runtime-unavailable-message")
    }

    private func selectLocalRuntime() {
        guard localModelStore.status.canUseForResponses, localModelStore.readyModelURL != nil else {
            showingLocalModelDownloadConfirmation = true
            return
        }
        prefersLocalMedicalModel = true
        hasUserSelectedMedicalAIRuntime = true
        withAnimation(.snappy(duration: 0.22, extraBounce: 0.02)) {
            showingRuntimePicker = false
        }
    }

    private func sendOutgoingMessage(_ outgoingMessage: AIOutgoingMessage) {
        guard !isSending else {
            return
        }
        let configuration = configurationStore.refreshInjectedSecretsIfAvailable()
        let readiness = configurationStore.readiness(for: configuration)
        let localModelURL = localModelStore.status.canUseForResponses
            ? localModelStore.readyModelURL
            : nil
        let hasUsableCloudKey = configurationStore.apiKey(for: configuration)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty == false
        let displayText = outgoingMessage.displayText
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let todayOpenMedicationNames = hasAcknowledgedThirdPartyMedicalAgent
            && displayText == "帮我核对今日用药注意事项"
            ? todayOpenMedicationNamesForPrompt()
            : []
        logAIEvent("prepare \(configuration.sanitizedDebugSummary) consentActive=\(activeConsent != nil) transport=\(readiness.diagnosticSummary)")

        let directive = AIConversationSendPlanner().plan(
            input: AIConversationSendPlanningInput(
                outgoingMessage: outgoingMessage,
                hasAcknowledgedThirdPartyAgent: hasAcknowledgedThirdPartyMedicalAgent,
                consent: activeConsent,
                configuration: configuration,
                readiness: readiness,
                prefersLocalModel: prefersLocalMedicalModel,
                localModelURL: localModelURL,
                hasUsableCloudKey: hasUsableCloudKey,
                todayOpenMedicationNames: todayOpenMedicationNames
            ),
            makeRequest: buildRequest
        )
        executeSendDirective(directive)
    }

    private func executeSendDirective(_ directive: AIConversationSendDirective) {
        switch directive {
        case .ignored:
            return
        case .showThirdPartyAgentNotice:
            showingThirdPartyAgentNotice = true
            return
        case let .showRuntimePicker(drafts):
            logAIEvent("not-ready runtime-picker")
            withAnimation(.snappy(duration: 0.22, extraBounce: 0.02)) {
                showingRuntimePicker = true
            }
            _ = commitConversationMessages(drafts, operation: "ai-not-ready-message")
            return
        case let .showConsent(drafts):
            prepareComposerAfterAcceptedSend()
            _ = commitConversationMessages(drafts, operation: "ai-consent-required-message")
            showingConsentSheet = true
            return
        case let .reject(drafts):
            prepareComposerAfterAcceptedSend()
            _ = commitConversationMessages(drafts, operation: "ai-send-rejected-message")
            return
        case let .switchToOnline(drafts):
            prepareComposerAfterAcceptedSend()
            prefersLocalMedicalModel = false
            _ = commitConversationMessages(drafts, operation: "ai-local-unavailable-message")
            return
        case let .sendLocal(dispatch):
            prepareComposerAfterAcceptedSend()
            guard commitConversationMessages(
                [dispatch.userDraft],
                operation: "ai-user-message-before-local-request"
            ) else {
                return
            }
            sendConfirmedLocalModelRequest(PendingLocalAIRequest(
                request: dispatch.request,
                sharedScopesSummary: dispatch.sharedScopesSummary,
                modelURL: dispatch.modelURL
            ))
        case let .sendCloud(dispatch):
            prepareComposerAfterAcceptedSend()
            guard commitConversationMessages(
                [dispatch.userDraft],
                operation: "ai-user-message-before-cloud-request"
            ) else {
                return
            }
            sendConfirmedDirectAPIRequest(PendingDirectAIRequest(
                request: dispatch.request,
                sharedScopesSummary: dispatch.sharedScopesSummary,
                configuration: dispatch.configuration
            ))
        }
    }

    private func prepareComposerAfterAcceptedSend() {
        withAnimation(.snappy(duration: 0.22, extraBounce: 0.02)) {
            showingRuntimePicker = false
        }
        draftMessage = ""
    }

    private func dismissChatKeyboard() {
        isChatInputFocused = false
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil,
            from: nil,
            for: nil
        )
    }

    private func archiveVisibleConversation(through message: StoredAIChatMessage) {
        let orderedVisibleMessages = visibleMessages.sorted { $0.createdAt < $1.createdAt }
        guard let selectedIndex = orderedVisibleMessages.firstIndex(where: { $0.id == message.id }) else {
            return
        }

        var archivedIDs = manuallyArchivedMessageIDs
        for archivedMessage in orderedVisibleMessages[...selectedIndex] {
            archivedIDs.insert(archivedMessage.id)
        }
        archivedMessageIDStorage = archivedIDs
            .map(\.uuidString)
            .sorted()
            .joined(separator: "|")
        dismissChatKeyboard()
    }

    private func applyPendingQuestionIfNeeded() {
        let question = pendingMedicationAIQuestion.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty else {
            return
        }
        draftMessage = question
        clearPendingMedicationAIQuestion()
    }

    @MainActor
    private func beginImageRecognition(_ item: PhotosPickerItem?) {
        imageRecognitionTask?.cancel()
        imageRecognitionGate.cancel()
        guard let item else {
            isReadingImage = false
            return
        }
        isReadingImage = true
        let recognitionID = imageRecognitionGate.begin()
        imageRecognitionTask = Task { @MainActor in
            await prepareImageQuestion(item, recognitionID: recognitionID)
        }
    }

    @MainActor
    private func prepareImageQuestion(_ item: PhotosPickerItem, recognitionID: UUID) async {
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                guard imageRecognitionGate.finish(recognitionID) else { return }
                draftMessage = "我上传了一张药品相关图片，但没有读取到图片数据。请告诉我该如何在 App 内手动补全药品信息。"
                finishImageRecognition()
                return
            }
            await prepareImageQuestion(data: data, recognitionID: recognitionID)
        } catch {
            guard imageRecognitionGate.finish(recognitionID) else { return }
            finishImageRecognition()
        }
    }

    @MainActor
    private func beginCameraImageRecognition(_ image: UIImage) {
        guard let data = image.jpegData(compressionQuality: 0.85) else { return }
        cancelImageRecognition()
        dismissChatKeyboard()
        isReadingImage = true
        let recognitionID = imageRecognitionGate.begin()
        imageRecognitionTask = Task { @MainActor in
            await prepareImageQuestion(data: data, recognitionID: recognitionID)
        }
    }

    @MainActor
    private func prepareImageQuestion(data: Data, recognitionID: UUID) async {
        do {
            let output = try await VisionImportPipeline().analyze(data, purpose: .labelText)
            guard case let .labelText(result) = output else {
                return
            }
            let excerpt = String(result.text.prefix(700))
            try Task.checkCancellation()
            guard imageRecognitionGate.finish(recognitionID) else { return }
            draftMessage = """
            我上传了一张药品相关图片，图片中的文字如下：
            \(excerpt)

            我想了解这些信息如何用于药品录入、说明书核对或复诊沟通。
            """
            finishImageRecognition()
        } catch is CancellationError {
            return
        } catch {
            guard imageRecognitionGate.finish(recognitionID) else { return }
            draftMessage = "我上传了一张药品相关图片，但没有读出清晰文字。请告诉我如何在 App 内手动补全药名、规格、剂型和提醒。"
            finishImageRecognition()
        }
    }

    @MainActor
    private func finishImageRecognition() {
        isReadingImage = false
        selectedChatImageItem = nil
        imageRecognitionTask = nil
    }

    @MainActor
    private func cancelImageRecognition() {
        imageRecognitionTask?.cancel()
        imageRecognitionTask = nil
        imageRecognitionGate.cancel()
        isReadingImage = false
        selectedChatImageItem = nil
    }

    private func sendConfirmedDirectAPIRequest(_ pendingRequest: PendingDirectAIRequest) {
        let configuration = configurationStore.refreshInjectedSecretsIfAvailable()
        guard let apiKey = configurationStore.apiKey(for: configuration), !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            logAIEvent("missing-key provider=\(configuration.providerName) kind=\(configuration.providerKind.rawValue)")
            _ = commitConversationMessages([AIChatResponseDraft(
                role: .system,
                text: "医疗智能体暂时无法连接，未发送任何用药数据。请稍后重试。",
                providerName: configuration.providerName,
                modelName: configuration.modelName,
                sharedScopesSummary: pendingRequest.sharedScopesSummary
            )], operation: "ai-key-missing-message")
            return
        }

        cancelActiveAIRequest()
        let executionID = UUID()
        activeAIRequestID = executionID
        isSending = true
        logAIEvent("sending provider=\(configuration.providerName) kind=\(configuration.providerKind.rawValue) keySource=\(configurationStore.apiKeySourceDescription(for: configuration)) scopes=\(pendingRequest.sharedScopesSummary)")
        activeAIRequestTask = Task { @MainActor in
            await sendDirectAPIRequest(
                request: pendingRequest.request,
                sharedScopesSummary: pendingRequest.sharedScopesSummary,
                configuration: configuration,
                apiKey: apiKey,
                executionID: executionID
            )
        }
    }

    private func sendConfirmedLocalModelRequest(_ pendingRequest: PendingLocalAIRequest) {
        cancelActiveAIRequest()
        let executionID = UUID()
        activeAIRequestID = executionID
        isSending = true
        logAIEvent("sending provider=local requestID=\(pendingRequest.request.id.uuidString) model=\(LocalMedicalModelStore.modelDisplayName) scopes=\(pendingRequest.sharedScopesSummary)")
        activeAIRequestTask = Task { @MainActor in
            await sendLocalModelRequest(
                request: pendingRequest.request,
                sharedScopesSummary: pendingRequest.sharedScopesSummary,
                modelURL: pendingRequest.modelURL,
                executionID: executionID
            )
        }
    }

    @MainActor
    static func beginLocalStreamingResponse(
        executionID: UUID,
        activeRequestID: UUID?,
        response: inout LocalStreamingAIResponse?
    ) -> Bool {
        // A cancelled task can first reach the main actor after a retry has
        // started. Validate ownership before touching its shared UI state.
        guard !Task.isCancelled, activeRequestID == executionID else { return false }
        response = LocalStreamingAIResponse()
        return true
    }

    @MainActor
    private func sendLocalModelRequest(
        request: MedicalAIRequest,
        sharedScopesSummary: String,
        modelURL: URL,
        executionID: UUID
    ) async {
        defer {
            finishAIRequestIfCurrent(executionID)
        }

        guard Self.beginLocalStreamingResponse(
            executionID: executionID,
            activeRequestID: activeAIRequestID,
            response: &localStreamingResponse
        ) else { return }

        do {
            let client = LocalMedicalAIClient(modelURL: modelURL)
            var finalAnswer = ""
            var finalThinking = ""
            for try await event in client.streamResponse(to: request) {
                try Task.checkCancellation()
                guard activeAIRequestID == executionID else { return }
                switch event {
                case .generationStarted:
                    updateLocalStreamingStatus("准备本机回答")
                case .modelLoading:
                    updateLocalStreamingStatus("正在加载本地端模型")
                case .prefillStarted:
                    updateLocalStreamingStatus("正在生成回答 · 直接模式")
                case .thinkingStarted:
                    updateLocalStreamingStatus("正在思考")
                    localStreamingResponse?.isThinkingExpanded = true
                case .thinkingDelta:
                    updateLocalStreamingStatus("正在思考")
                case .answerStarted:
                    updateLocalStreamingStatus("正在整理正式回答")
                case .answerDelta:
                    updateLocalStreamingStatus("正在整理正式回答")
                case let .generationCompleted(answer, thinking):
                    finalAnswer = answer
                    finalThinking = thinking
                    updateLocalStreamingStatus("正在进行安全检查")
                case let .generationFailed(message):
                    updateLocalStreamingStatus(message)
                }
            }
            try Task.checkCancellation()
            guard activeAIRequestID == executionID else { return }
            let finalized = try MedicalAIResponseFinalizer().finalize(
                answer: finalAnswer,
                thinking: finalThinking
            )
            let outcome = AIChatResponseCommand(modelContext: modelContext).commit(
                AIChatResponseDraft(
                    role: .assistant,
                    text: finalized.persistedMessage,
                    providerName: "离线智能体",
                    modelName: LocalMedicalModelStore.modelDisplayName,
                    sharedScopesSummary: sharedScopesSummary
                )
            )
            guard case .committed = outcome else { return }
            localStreamingResponse?.answerText = finalized.displayMessage
            localStreamingResponse?.thinkingText = finalized.thinking
            localStreamingResponse?.statusText = "已完成安全检查"
            localStreamingResponse?.completedAt = Date()
            localStreamingResponse?.isThinkingExpanded = false
            logAIEvent("success provider=local requestID=\(request.id.uuidString) rawLength=\(finalAnswer.count) displayLength=\(finalized.displayMessage.count) thinkingLength=\(finalized.thinking.count) appendedSafetyNote=\(finalized.appendedSafetyNote) blocked=\(finalized.boundaryBlockedAction) flags=\(finalized.boundaryFlags.joined(separator: ","))")
            localStreamingResponse = nil
            archiveOlderVisibleConversationIfNeeded()
        } catch is CancellationError {
            guard activeAIRequestID == executionID else { return }
            localStreamingResponse = nil
            return
        } catch {
            guard !Task.isCancelled, activeAIRequestID == executionID else { return }
            localStreamingResponse = nil
            let message = classifyAITransportError(error)
            logAIEvent("error provider=local requestID=\(request.id.uuidString) \(transportDiagnosticSummary(error))")
            if case .committed = AIChatResponseCommand(modelContext: modelContext).commit(
                AIChatResponseDraft(
                    role: .system,
                    text: message,
                    providerName: "离线智能体",
                    modelName: LocalMedicalModelStore.modelDisplayName,
                    sharedScopesSummary: sharedScopesSummary
                )
            ) {
                archiveOlderVisibleConversationIfNeeded()
            }
        }
    }

    @MainActor
    private func updateLocalStreamingStatus(_ status: String) {
        guard localStreamingResponse?.statusText != status else {
            return
        }
        localStreamingResponse?.statusText = status
    }

    @MainActor
    private func sendDirectAPIRequest(
        request: MedicalAIRequest,
        sharedScopesSummary: String,
        configuration: MedicalAIConfiguration,
        apiKey: String,
        executionID: UUID
    ) async {
        let sentToolScopes = toolScopeSuffix
        defer {
            finishAIRequestIfCurrent(executionID)
        }

        do {
            let result = try await performMedicalAIRequest(
                request: request,
                configuration: configuration,
                apiKey: apiKey
            )
            try Task.checkCancellation()
            guard activeAIRequestID == executionID, sentToolScopes == toolScopeSuffix else { return }
            let response = result.response
            let finalized = result.finalized
            logAIEvent("success provider=\(response.provider.providerName) rawLength=\(response.message.count) displayLength=\(finalized.displayMessage.count) appendedSafetyNote=\(finalized.appendedSafetyNote) blocked=\(finalized.boundaryBlockedAction) flags=\(finalized.boundaryFlags.joined(separator: ","))")
            guard case .committed = AIChatResponseCommand(modelContext: modelContext).commit(
                AIChatResponseDraft(
                    role: .assistant,
                    text: finalized.persistedMessage,
                    providerName: response.provider.providerName,
                    modelName: response.provider.modelName,
                    sharedScopesSummary: sharedScopesSummary + sentToolScopes
                )
            ) else { return }
            archiveOlderVisibleConversationIfNeeded()
            configurationStore.promoteCurrentAPIKeyIfNeeded(for: configuration)
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled, activeAIRequestID == executionID else { return }
            let message = classifyAITransportError(error)
            logAIEvent("error provider=\(configuration.providerName) kind=\(configuration.providerKind.rawValue) \(transportDiagnosticSummary(error))")
            if case .committed = AIChatResponseCommand(modelContext: modelContext).commit(
                AIChatResponseDraft(
                    role: .system,
                    text: message,
                    providerName: configuration.providerName,
                    modelName: configuration.modelName,
                    sharedScopesSummary: sharedScopesSummary + sentToolScopes
                )
            ) {
                archiveOlderVisibleConversationIfNeeded()
            }
        }
    }

    private func performMedicalAIRequest(
        request: MedicalAIRequest,
        configuration: MedicalAIConfiguration,
        apiKey: String
    ) async throws -> MedicalAIExecutionResult {
        let client = MedicalAIClientFactory.make(
            configuration: configuration,
            credential: apiKey
        )
        return try await MedicalAIRequestOrchestrator(timeout: MedicalAIExecutionPolicy.default.cloudTimeout).execute(
            request: request,
            client: client
        )
    }

    private var toolScopeSuffix: String {
        "|health=\(UserDefaults.standard.bool(forKey: "aiSharesHealthSummary"))|inventory=\(UserDefaults.standard.bool(forKey: "aiSharesInventory"))"
    }

    @MainActor
    private func readAssistantTool(_ selection: MedicalAIReadOnlyToolSelection, request: MedicalAIRequest) async throws -> String {
        try Task.checkCancellation()
        guard let consent = activeConsent, consent.authorization == request.authorization else {
            return "本次授权已变更，请重新提问并确认共享范围。"
        }
        let calendar = Calendar.current
        let date = calendar.date(byAdding: .day, value: selection.period == "yesterday" ? -1 : 0, to: Date()) ?? Date()
        switch selection.tool {
        case "health_summary":
            guard UserDefaults.standard.bool(forKey: "aiSharesHealthSummary") else {
                return "尚未开启健康摘要共享。请在智能体授权中开启‘按需查询 Apple 健康摘要’，并在个人页完成 Apple 健康授权。"
            }
            let service = HealthKitService()
            await service.refreshRecentTrendSamples(days: selection.period == "recent" ? 14 : 2, useRecentCache: true)
            try Task.checkCancellation()
            guard activeConsent?.authorization == request.authorization,
                  UserDefaults.standard.bool(forKey: "aiSharesHealthSummary") else { return "健康摘要共享已关闭。" }
            let samples = service.recentTrendSamples.filter { selection.period == "recent" || calendar.isDate($0.measuredAt, inSameDayAs: date) }
            let summary = HealthKitRecentSummary(samples: samples, refreshedAt: service.lastSampleRefreshAt)
            guard !samples.isEmpty else { return "该时间段没有可读取的健康记录。\(service.statusMessage)" }
            return summary.metricSummaries.map {
                "\($0.kind.displayTitle)：最近值 \($0.latestValueText)，测量时间 \(AppFormatters.day.string(from: $0.latestMeasuredAt)) \(AppFormatters.time.string(from: $0.latestMeasuredAt))，\($0.sampleCount) 条记录"
            }.joined(separator: "\n")
        case "inventory":
            guard consent.sharesMedicationProfile, UserDefaults.standard.bool(forKey: "aiSharesInventory") else {
                return "尚未授权库存查询，请在智能体授权中开启药品资料和‘按需查询库存余量’。"
            }
            let stocks = try modelContext.fetch(FetchDescriptor<StoredMedicationStock>())
            let allowed = Dictionary(uniqueKeysWithValues: request.medicationSnapshots.map { ($0.medication.id, $0.medication.displayName) })
            let rows = stocks.compactMap { stock -> String? in
                guard let name = allowed[stock.medicationID] else { return nil }
                return "\(name)：登记余量 \(stock.remainingQuantity.formatted()) \(stock.unit)，低量阈值 \(stock.lowStockThreshold.formatted())，登记时间 \(AppFormatters.day.string(from: stock.lastUpdated))"
            }
            return rows.isEmpty ? "暂无已登记库存余量。" : rows.joined(separator: "\n")
        case "medication_records":
            guard consent.sharesMedicationProfile, consent.sharesDoseEvents else {
                return "尚未授权读取用药记录，请在智能体数据设置中开启药品资料和服药记录共享。"
            }
            let selectedTasks = tasks.filter {
                selection.period == "recent" ? $0.dueAt >= Date().addingTimeInterval(-14 * 86400) : calendar.isDate($0.dueAt, inSameDayAs: date)
            }
            let builder = MedicalAIContextBuilder(medications: medications, plans: plans, tasks: selectedTasks, riskCards: riskCards, labels: labels)
            let filtered = builder.makeRequest(userMessage: "查询指定时间段用药记录", consent: consent,
                environmentInsights: request.environmentInsights, localeIdentifier: request.localeIdentifier)
            let rows = filtered.medicationSnapshots.flatMap { snapshot in
                snapshot.scheduledDoses.map { dose in
                    let event = snapshot.doseEvents.last { $0.scheduledDoseID == dose.id }
                    let status = event?.status.rawValue ?? "未确认"
                    return "\(snapshot.medication.displayName) · 计划时间 \(AppFormatters.day.string(from: dose.dueAt)) \(AppFormatters.time.string(from: dose.dueAt)) · \(dose.dose.value.formatted()) \(dose.dose.unit) · 记录状态 \(status)"
                }
            }
            return rows.isEmpty ? "该时间段暂无已授权的用药记录。" : rows.joined(separator: "\n")
        default:
            return "未识别的查询。"
        }
    }

    @MainActor
    private func cancelActiveAIRequest() {
        activeAIRequestTask?.cancel()
        activeAIRequestTask = nil
        activeAIRequestID = nil
        isSending = false
        localStreamingResponse = nil
    }

    @MainActor
    private func finishAIRequestIfCurrent(_ executionID: UUID) {
        guard activeAIRequestID == executionID else { return }
        activeAIRequestTask = nil
        activeAIRequestID = nil
        isSending = false
        localStreamingResponse = nil
    }

    private func classifyAITransportError(_ error: Error) -> String {
        if let error = error as? LocalMedicalAIError, let description = error.errorDescription {
            return description
        }
        if let error = error as? BaichuanMedicalAIError, let description = error.errorDescription {
            return description
        }
        if let error = error as? DoubaoMedicalAIError, let description = error.errorDescription {
            return description
        }
        if let error = error as? MedicalAIOrchestrationError, let description = error.errorDescription {
            return description
        }
        if let error = error as? URLError {
            switch error.code {
            case .notConnectedToInternet, .networkConnectionLost, .cannotFindHost, .cannotConnectToHost:
                return "iPhone 当前网络无法连接医疗智能体，请确认联网后重试。"
            case .timedOut:
                return "医疗智能体响应超时，请稍后重试。"
            default:
                return "医疗智能体网络暂时无法连接，请稍后重试。"
            }
        }
        let fallback = "医疗智能体暂时没有返回结果，请稍后重试。"
        return fallback
    }

    private func transportDiagnosticSummary(_ error: Error) -> String {
        if let error = error as? LocalMedicalAIError {
            return "local=\(error.diagnosticSummary)"
        }
        if let error = error as? CloudBaseMedicalAIError {
            return "broker=\(error.diagnosticSummary)"
        }
        if let error = error as? BaichuanMedicalAIError {
            return "baichuan=\(error.diagnosticSummary)"
        }
        if let error = error as? DoubaoMedicalAIError {
            return "doubao=\(error.diagnosticSummary)"
        }
        if let error = error as? URLError {
            return "url-error code=\(error.code.rawValue)"
        }
        if let error = error as? MedicalAIOrchestrationError {
            return "orchestration=\(String(describing: error))"
        }
        if error is CancellationError {
            return "request-cancelled"
        }
        return "type=\(String(describing: Swift.type(of: error)))"
    }

    private func logAIEvent(_ message: String) {
        #if DEBUG
        print("[MedicalAI] \(message)")
        #endif
    }

    @discardableResult
    private func commitConversationMessages(
        _ drafts: [AIChatResponseDraft],
        operation: StaticString
    ) -> Bool {
        if case .committed = AIConversationPersistenceCommand(modelContext: modelContext)
            .commitMessages(drafts, operation: operation) {
            return true
        }
        return false
    }

    private func purgePreProviderDemoMessagesIfNeeded() {
        guard !hasPurgedPreProviderDemoMessages else {
            return
        }
        if case .deleted = AIConversationPersistenceCommand(modelContext: modelContext)
            .deleteMessages(messages, operation: "ai-purge-demo-messages") {
            hasPurgedPreProviderDemoMessages = true
        }
    }

    private func migrateLegacyMedicalAIStatusMessagesIfNeeded() {
        let messagesToMigrate = AIConversationMaintenancePolicy()
            .messagesForStatusMigration(in: messages)
        _ = AIConversationPersistenceCommand(modelContext: modelContext).migrateMessagesToSystem(
            messagesToMigrate,
            operation: "ai-migrate-status-messages"
        )
    }

    private func purgeUnavailableMedicalAITransportMessagesIfNeeded() {
        guard !hasPurgedUnavailableMedicalAITransportMessages else {
            return
        }

        let messagesToDelete = AIConversationMaintenancePolicy()
            .messagesForUnavailableTransportPurge(in: messages)
        if !messagesToDelete.isEmpty {
            _ = AIConversationPersistenceCommand(modelContext: modelContext).deleteMessages(
                messagesToDelete,
                operation: "ai-purge-unavailable-messages"
            )
        }
        hasPurgedUnavailableMedicalAITransportMessages = true
    }

    private func purgeVisibleQuickPromptMessagesIfNeeded() {
        guard !hasPurgedVisibleQuickPromptMessages else {
            return
        }
        let messagesToDelete = AIConversationMaintenancePolicy()
            .messagesForQuickPromptPurge(in: messages)
        if messagesToDelete.isEmpty {
            hasPurgedVisibleQuickPromptMessages = true
        } else if case .deleted = AIConversationPersistenceCommand(modelContext: modelContext)
            .deleteMessages(messagesToDelete, operation: "ai-purge-quick-prompts") {
            hasPurgedVisibleQuickPromptMessages = true
        }
    }

    private func reconcileInterruptedMedicalAIRequestsIfNeeded() {
        guard !isSending else {
            return
        }

        guard !messages.isEmpty else {
            return
        }

        let configuration = configurationStore.configuration
        let repairDrafts = AIConversationMaintenancePolicy()
            .interruptedRequestRepairDrafts(
                in: messages,
                now: Date(),
                defaultProviderName: configuration.providerName,
                defaultModelName: configuration.modelName
            )

        if !repairDrafts.isEmpty {
            _ = commitConversationMessages(
                repairDrafts,
                operation: "ai-reconcile-interrupted-request"
            )
        }
    }

    private func buildRequest(userMessage: String, consent: StoredAIConsent) -> MedicalAIRequest {
        let contextBuilder = MedicalAIContextBuilder(
            medications: medications,
            plans: plans,
            tasks: tasks,
            riskCards: riskCards,
            labels: labels
        )
        var request = contextBuilder.makeRequest(
            userMessage: userMessage,
            consent: consent,
            environmentInsights: environmentInsightsForAI(userMessage: userMessage),
            localeIdentifier: Locale.current.identifier
        )
        let provider = prefersLocalMedicalModel ? "离线智能体" : configurationStore.configuration.providerName
        request.conversation = visibleMessages.filter {
            ($0.role == .user || $0.role == .assistant)
                && $0.providerName == provider
                && ($0.sharedScopesSummary == consent.scopeSummary + (prefersLocalMedicalModel ? "" : toolScopeSuffix) || ($0.role == .user && $0.sharedScopesSummary == consent.scopeSummary))
        }.suffix(4).map {
            MedicalAIConversationTurn(role: $0.role == .user ? "user" : "assistant",
                text: String($0.text.components(separatedBy: LocalMedicalAIClient.localReasoningSeparator)[0].prefix(240)))
        }
        let scheduledDoseCount = request.medicationSnapshots.reduce(0) { $0 + $1.scheduledDoses.count }
        let doseEventCount = request.medicationSnapshots.reduce(0) { $0 + $1.doseEvents.count }
        logAIEvent("context requestID=\(request.id.uuidString) medications=\(request.medicationSnapshots.count) scheduledDoses=\(scheduledDoseCount) doseEvents=\(doseEventCount) todayMode=\(contextBuilder.isTodayQuestion(userMessage))")
        return request
    }

    private func todayOpenMedicationNamesForPrompt() -> [String] {
        let contextBuilder = MedicalAIContextBuilder(
            medications: medications,
            plans: plans,
            tasks: tasks,
            riskCards: riskCards,
            labels: labels
        )
        var names: [String] = []
        for task in contextBuilder.tasksForContext(userMessage: "今天") where task.status == .pending || task.status == .delayed {
            guard let medication = medications.first(where: { $0.id == task.medicationID }) else {
                continue
            }
            let name = userFacingMedicationName(for: medication)
            if !name.isEmpty, !names.contains(name) {
                names.append(name)
            }
        }
        return names
    }

    private func archiveOlderVisibleConversationIfNeeded() {
        let orderedMessages = messages
            .filter { !manuallyArchivedMessageIDs.contains($0.id) }
            .sorted { $0.createdAt < $1.createdAt }
        guard let startIndex = AIConversationVisibilityProjection.visibleConversationStartIndex(in: orderedMessages),
              startIndex > orderedMessages.startIndex else {
            return
        }
        var archivedIDs = manuallyArchivedMessageIDs
        for message in orderedMessages[..<startIndex] {
            archivedIDs.insert(message.id)
        }
        archivedMessageIDStorage = archivedIDs
            .map(\.uuidString)
            .sorted()
            .joined(separator: "|")
    }

    private func deleteArchivedMessages(_ messagesToDelete: [StoredAIChatMessage]) {
        guard !messagesToDelete.isEmpty else {
            return
        }
        guard case .deleted = AIConversationPersistenceCommand(modelContext: modelContext)
            .deleteMessages(messagesToDelete, operation: "ai-delete-archived-messages") else {
            return
        }
        var archivedIDs = manuallyArchivedMessageIDs
        for message in messagesToDelete {
            archivedIDs.remove(message.id)
        }
        archivedMessageIDStorage = archivedIDs
            .map(\.uuidString)
            .sorted()
            .joined(separator: "|")
    }

    private func deleteAllArchivedMessages() {
        deleteArchivedMessages(archivedMessages)
    }

    private func environmentInsightsForAI(userMessage: String) -> [MedicalAIEnvironmentInsight] {
        MedicalAIEnvironmentContextBuilder().insights(
            userMessage: userMessage,
            weatherHints: [],
            medications: medications
        )
    }

    private func saveConsent(_ draft: AIConsentDraft) -> Bool {
        cancelActiveAIRequest()
        let outcome = AIConversationPersistenceCommand(modelContext: modelContext).saveConsent(
            existing: storedConsent,
            draft: draft,
            grantedAt: Date()
        )
        guard outcome == .consentSaved else { return false }
        UserDefaults.standard.set(draft.sharesHealthSummary, forKey: "aiSharesHealthSummary")
        UserDefaults.standard.set(draft.sharesInventory, forKey: "aiSharesInventory")
        return true
    }

    private func revokeConsent() {
        cancelActiveAIRequest()
        UserDefaults.standard.set(false, forKey: "aiSharesHealthSummary")
        UserDefaults.standard.set(false, forKey: "aiSharesInventory")
        let command = AIConsentRevocationCommand(modelContext: modelContext)
        _ = command.execute()
    }
}
