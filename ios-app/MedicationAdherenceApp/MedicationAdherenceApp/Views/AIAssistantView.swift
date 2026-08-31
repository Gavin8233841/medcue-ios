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
    @StateObject private var weatherMedicationService = WeatherMedicationService()
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
        AIAssistantScreen(
            configuration: configuration,
            onlineReadiness: configurationStore.readiness(for: configuration),
            localModelStatus: localModelStore.status,
            visibleMessages: visibleMessages,
            archivedMessages: archivedMessages,
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
            applyPendingQuestion: applyPendingQuestionIfNeeded,
            refreshEnvironment: refreshEnvironment,
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

    private func refreshEnvironment() async {
        guard activeAppTab == nil || activeAppTab == .assistant else {
            return
        }
        await weatherMedicationService.refresh(medications: medications)
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
    private func sendLocalModelRequest(
        request: MedicalAIRequest,
        sharedScopesSummary: String,
        modelURL: URL,
        executionID: UUID
    ) async {
        defer {
            finishAIRequestIfCurrent(executionID)
        }

        do {
            localStreamingResponse = LocalStreamingAIResponse()
            let client = LocalMedicalAIClient(modelURL: modelURL)
            var finalAnswer = ""
            var finalThinking = ""
            for try await event in client.streamResponse(to: request) {
                try Task.checkCancellation()
                guard activeAIRequestID == executionID else { return }
                switch event {
                case .generationStarted:
                    updateLocalStreamingStatus("正在思考")
                case .modelLoading:
                    updateLocalStreamingStatus("正在加载本地端模型")
                case .prefillStarted:
                    updateLocalStreamingStatus("深度思考中")
                case .thinkingStarted:
                    updateLocalStreamingStatus("深度思考中")
                    localStreamingResponse?.isThinkingExpanded = true
                case .thinkingDelta:
                    updateLocalStreamingStatus("深度思考中")
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
            guard activeAIRequestID == executionID else { return }
            let response = result.response
            let finalized = result.finalized
            logAIEvent("success provider=\(response.provider.providerName) rawLength=\(response.message.count) displayLength=\(finalized.displayMessage.count) appendedSafetyNote=\(finalized.appendedSafetyNote) blocked=\(finalized.boundaryBlockedAction) flags=\(finalized.boundaryFlags.joined(separator: ","))")
            guard case .committed = AIChatResponseCommand(modelContext: modelContext).commit(
                AIChatResponseDraft(
                    role: .assistant,
                    text: finalized.persistedMessage,
                    providerName: response.provider.providerName,
                    modelName: response.provider.modelName,
                    sharedScopesSummary: sharedScopesSummary
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
                    sharedScopesSummary: sharedScopesSummary
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
        let request = contextBuilder.makeRequest(
            userMessage: userMessage,
            consent: consent,
            environmentInsights: environmentInsightsForAI(userMessage: userMessage),
            localeIdentifier: Locale.current.identifier
        )
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
            weatherHints: weatherMedicationService.hints,
            medications: medications
        )
    }

    private func saveConsent(_ draft: AIConsentDraft) {
        _ = AIConversationPersistenceCommand(modelContext: modelContext).saveConsent(
            existing: storedConsent,
            draft: draft,
            grantedAt: Date()
        )
    }

    private func revokeConsent() {
        let command = AIConsentRevocationCommand(modelContext: modelContext)
        _ = command.execute()
    }
}
