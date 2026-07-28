import MedicationAdherenceCore
import PhotosUI
import SwiftData
import SwiftUI
import UIKit

struct AIAssistantView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.activeAppTab) private var activeAppTab
    @Environment(\.isBackgroundTabPrewarm) private var isBackgroundTabPrewarm
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

    private var visibleMessages: [StoredAIChatMessage] {
        let orderedMessages = messages
            .filter { !manuallyArchivedMessageIDs.contains($0.id) }
            .sorted { $0.createdAt < $1.createdAt }
        guard let startIndex = visibleConversationStartIndex(in: orderedMessages) else {
            return orderedMessages
        }
        return Array(orderedMessages[startIndex...])
    }

    private var archivedMessages: [StoredAIChatMessage] {
        let visibleIDs = Set(visibleMessages.map(\.id))
        return messages
            .filter { !visibleIDs.contains($0.id) }
            .sorted { $0.createdAt < $1.createdAt }
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

    private func visibleConversationStartIndex(in orderedMessages: [StoredAIChatMessage]) -> Int? {
        let userMessageIndexes = orderedMessages.indices.filter { orderedMessages[$0].role == .user }
        guard userMessageIndexes.count > 3 else {
            return orderedMessages.isEmpty ? nil : orderedMessages.startIndex
        }
        return userMessageIndexes[userMessageIndexes.count - 3]
    }

    var body: some View {
        let configuration = configurationStore.configuration
        let onlineReadiness = configurationStore.readiness(for: configuration)

        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        AgentRuntimeSelectorBar(
                            onlineConfiguration: configuration,
                            onlineReadiness: onlineReadiness,
                            status: localModelStore.status,
                            prefersLocalResponses: prefersLocalMedicalModel,
                            hasUserSelectedRuntime: hasUserSelectedMedicalAIRuntime,
                            isExpanded: showingRuntimePicker,
                            toggleExpanded: {
                                withAnimation(.snappy(duration: 0.22, extraBounce: 0.02)) {
                                    showingRuntimePicker.toggle()
                                }
                            },
                            selectOnline: selectOnlineRuntime,
                            selectLocal: selectLocalRuntime,
                            requestLocalDownload: { showingLocalModelDownloadConfirmation = true }
                        )

                        AIQuickActionsSection(
                            isDisabled: isSending || !hasAcknowledgedThirdPartyMedicalAgent,
                            prefersLocalResponses: prefersLocalMedicalModel,
                            send: sendMessage
                        )

                        if visibleMessages.isEmpty {
                            AIEmptyConversationView()
                        } else {
                            ForEach(visibleMessages) { message in
                                AIMessageBubble(
                                    message: message,
                                    archive: { archiveVisibleConversation(through: message) }
                                )
                                    .id(message.id)
                            }
                        }

                        if let localStreamingResponse {
                            LocalStreamingResponseView(response: localStreamingResponse)
                                .id("local-streaming-response")
                        } else if isSending {
                            AIThinkingBubble(isLocalRuntime: prefersLocalMedicalModel)
                                .id("thinking")
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .background(alignment: .top) {
                        AppTopGradientScrollReader(tab: .assistant, coordinateSpaceName: "AIAssistantTopGradientScroll")
                    }
                }
                .coordinateSpace(name: "AIAssistantTopGradientScroll")
                .scrollDismissesKeyboard(.interactively)
                .contentShape(Rectangle())
                .simultaneousGesture(TapGesture().onEnded {
                    dismissChatKeyboard()
                })
                .onChange(of: messages.count) { _, _ in
                    scrollToLatest(using: proxy)
                }
                .onChange(of: isSending) { _, _ in
                    scrollToLatest(using: proxy)
                }
            }

            Divider()

            AIChatInputBar(
                text: $draftMessage,
                selectedImageItem: $selectedChatImageItem,
                isFocused: $isChatInputFocused,
                isSending: isSending,
                isReadingImage: isReadingImage,
                isEnabled: hasAcknowledgedThirdPartyMedicalAgent,
                showDisclaimer: { showingThirdPartyAgentNotice = true },
                send: { sendMessage() }
            )
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("医疗智能体")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingArchivedMessages = true
                } label: {
                    Image(systemName: "clock.arrow.circlepath")
                        .accessibilityLabel("归档历史")
                }
                .disabled(archivedMessages.isEmpty)
            }
        }
        .onAppear {
            prepareAssistantSessionIfVisible()
        }
        .onChange(of: activeAppTab) { _, newTab in
            if newTab != nil, newTab != .assistant {
                cancelActiveAIRequest()
                cancelImageRecognition()
            }
            prepareAssistantSessionIfVisible()
        }
        .onChange(of: selectedChatImageItem) { _, newItem in
            beginImageRecognition(newItem)
        }
        .onChange(of: pendingMedicationAIQuestion) { _, _ in
            applyPendingQuestionIfNeeded()
        }
        .task(id: environmentRefreshSignature) {
            guard activeAppTab == nil || activeAppTab == .assistant else {
                return
            }
            await weatherMedicationService.refresh(medications: medications)
        }
        .sheet(isPresented: $showingThirdPartyAgentNotice) {
            ThirdPartyMedicalAgentNoticeSheet(
                accept: {
                    hasAcknowledgedThirdPartyMedicalAgent = true
                    hasAcceptedMedicalAIDisclaimer = true
                    showingThirdPartyAgentNotice = false
                    if activeConsent == nil {
                        showingConsentSheet = true
                    }
                }
            )
            .interactiveDismissDisabled(true)
        }
        .sheet(isPresented: $showingConsentSheet) {
            AIConsentSheet(
                consent: storedConsent,
                save: saveConsent,
                revoke: revokeConsent
            )
        }
        .sheet(isPresented: $showingArchivedMessages) {
            AIArchivedMessagesSheet(
                messages: archivedMessages,
                deleteMessages: deleteArchivedMessages,
                deleteAllMessages: deleteAllArchivedMessages
            )
        }
        .confirmationDialog(
            "下载离线端侧模型 Beta",
            isPresented: $showingLocalModelDownloadConfirmation,
            titleVisibility: .visible
        ) {
            Button("开始下载约 265MB 模型") {
                Task {
                    await localModelStore.downloadModel()
                }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("离线端侧模型为 Beta 版本，会在本机运行，不上传用药记录。下载完成后可在智能体页切换使用。")
        }
    }

    private func prepareAssistantSessionIfVisible() {
        guard !isBackgroundTabPrewarm else {
            return
        }
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
        guard hasAcknowledgedThirdPartyMedicalAgent else {
            showingThirdPartyAgentNotice = true
            return
        }

        let displayText = outgoingMessage.displayText.trimmingCharacters(in: .whitespacesAndNewlines)
        var requestText = outgoingMessage.requestText.trimmingCharacters(in: .whitespacesAndNewlines)
        if displayText == "帮我核对今日用药注意事项" {
            let names = todayOpenMedicationNamesForPrompt()
            if !names.isEmpty {
                requestText += "\n今日待处理药品：\(names.prefix(4).joined(separator: "、"))。"
            }
        }
        guard !displayText.isEmpty, !requestText.isEmpty else {
            return
        }
        let consent = activeConsent
        let configuration = configurationStore.refreshInjectedSecretsIfAvailable()
        let readiness = configurationStore.readiness(for: configuration)
        let canUseLocalModel = prefersLocalMedicalModel
            && localModelStore.status.canUseForResponses
            && localModelStore.readyModelURL != nil
        let providerName = canUseLocalModel ? "离线智能体" : configuration.providerName
        let modelName = canUseLocalModel ? LocalMedicalModelStore.modelDisplayName : configuration.modelName
        logAIEvent("prepare \(configuration.sanitizedDebugSummary) consentActive=\(consent != nil) transport=\(readiness.diagnosticSummary)")

        if !canUseLocalModel, !readiness.canSend {
            logAIEvent("not-ready \(readiness.diagnosticSummary)")
            withAnimation(.snappy(duration: 0.22, extraBounce: 0.02)) {
                showingRuntimePicker = true
            }
            _ = commitConversationMessages([AIChatResponseDraft(
                role: .system,
                text: readiness.userFacingMessage ?? "云端智能体尚未开启。快捷问题没有发送到外部服务；开启云端能力后即可使用在线智能体。",
                providerName: configuration.providerName,
                modelName: configuration.modelName,
                sharedScopesSummary: consent?.scopeSummary ?? "未授权"
            )], operation: "ai-not-ready-message")
            return
        }

        withAnimation(.snappy(duration: 0.22, extraBounce: 0.02)) {
            showingRuntimePicker = false
        }
        let userDraft = AIChatResponseDraft(
            role: .user,
            text: displayText,
            providerName: providerName,
            modelName: modelName,
            sharedScopesSummary: consent?.scopeSummary ?? "未授权"
        )
        draftMessage = ""

        guard let consent else {
            _ = commitConversationMessages([userDraft, AIChatResponseDraft(
                role: .system,
                text: "尚未获得共享授权，因此没有读取任何用药数据。请先在授权页选择共享范围。",
                providerName: configuration.providerName,
                modelName: configuration.modelName,
                sharedScopesSummary: "未授权"
            )], operation: "ai-consent-required-message")
            showingConsentSheet = true
            return
        }

        let request = buildRequest(userMessage: requestText, consent: consent)
        let missingScopes = MedicalAIRequestValidator().missingRequiredScopes(for: request)
        if !missingScopes.isEmpty {
            _ = commitConversationMessages([userDraft, AIChatResponseDraft(
                role: .system,
                text: "当前授权范围不足，未发送请求。缺少：\(missingScopes.map(scopeDisplayName).sorted().joined(separator: "、"))。",
                providerName: configuration.providerName,
                modelName: configuration.modelName,
                sharedScopesSummary: consent.scopeSummary
            )], operation: "ai-scope-required-message")
            return
        }

        if prefersLocalMedicalModel {
            guard localModelStore.status.canUseForResponses, let modelURL = localModelStore.readyModelURL else {
                prefersLocalMedicalModel = false
                _ = commitConversationMessages([userDraft, AIChatResponseDraft(
                    role: .system,
                    text: "离线智能体暂时不可用，已切换为在线智能体。请重新发送这条消息。",
                    providerName: "离线智能体",
                    modelName: LocalMedicalModelStore.modelDisplayName,
                    sharedScopesSummary: consent.scopeSummary
                )], operation: "ai-local-unavailable-message")
                return
            }
            guard commitConversationMessages(
                [userDraft],
                operation: "ai-user-message-before-local-request"
            ) else {
                return
            }
            sendConfirmedLocalModelRequest(PendingLocalAIRequest(
                request: request,
                sharedScopesSummary: consent.scopeSummary,
                modelURL: modelURL
            ))
            return
        }

        guard readiness.canSend else {
            logAIEvent("not-ready \(readiness.diagnosticSummary)")
            _ = commitConversationMessages([userDraft, AIChatResponseDraft(
                role: .system,
                text: readiness.userFacingMessage ?? "医疗智能体暂时无法连接，未发送任何用药数据。请稍后重试。",
                providerName: configuration.providerName,
                modelName: configuration.modelName,
                sharedScopesSummary: consent.scopeSummary
            )], operation: "ai-transport-unavailable-message")
            return
        }

        guard configurationStore.apiKey(for: configuration)?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            logAIEvent("not-ready missing-key-after-readiness provider=\(configuration.providerName) kind=\(configuration.providerKind.rawValue)")
            _ = commitConversationMessages([userDraft, AIChatResponseDraft(
                role: .system,
                text: "医疗智能体暂时无法连接，未发送任何用药数据。请稍后重试。",
                providerName: configuration.providerName,
                modelName: configuration.modelName,
                sharedScopesSummary: consent.scopeSummary
            )], operation: "ai-key-unavailable-message")
            return
        }

        guard commitConversationMessages(
            [userDraft],
            operation: "ai-user-message-before-cloud-request"
        ) else {
            return
        }
        sendConfirmedDirectAPIRequest(PendingDirectAIRequest(
            request: request,
            sharedScopesSummary: consent.scopeSummary,
            configuration: configuration
        ))
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
        let client = medicalAIClient(configuration: configuration, apiKey: apiKey)
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

    private func medicalAIClient(configuration: MedicalAIConfiguration, apiKey: String) -> any MedicalAIClient {
        if configuration.endpointURLString.contains("volces.com") || configuration.providerName.contains("豆包") {
            return DoubaoMedicalAIClient(configuration: configuration, apiKey: apiKey)
        }
        return BaichuanMedicalAIClient(configuration: configuration, apiKey: apiKey)
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
        let messagesToMigrate = messages.filter {
            $0.role == .assistant && isMedicalAIStatusMessage($0.text)
        }
        _ = AIConversationPersistenceCommand(modelContext: modelContext).migrateMessagesToSystem(
            messagesToMigrate,
            operation: "ai-migrate-status-messages"
        )
    }

    private func purgeUnavailableMedicalAITransportMessagesIfNeeded() {
        guard !hasPurgedUnavailableMedicalAITransportMessages else {
            return
        }

        let orderedMessages = messages.sorted { $0.createdAt < $1.createdAt }
        var messageIDsToDelete: Set<UUID> = []

        for (index, message) in orderedMessages.enumerated() {
            guard message.role != .user, isStaleUnavailableMedicalAIMessage(message.text) else {
                continue
            }

            messageIDsToDelete.insert(message.id)
            if index > 0 {
                let previousMessage = orderedMessages[index - 1]
                let gap = message.createdAt.timeIntervalSince(previousMessage.createdAt)
                if previousMessage.role == .user, gap >= 0, gap <= 120 {
                    messageIDsToDelete.insert(previousMessage.id)
                }
            }
        }

        let messagesToDelete = messages.filter { messageIDsToDelete.contains($0.id) }
        if !messagesToDelete.isEmpty {
            _ = AIConversationPersistenceCommand(modelContext: modelContext).deleteMessages(
                messagesToDelete,
                operation: "ai-purge-unavailable-messages"
            )
        }
        hasPurgedUnavailableMedicalAITransportMessages = true
    }

    private func isStaleUnavailableMedicalAIMessage(_ text: String) -> Bool {
        normalizedLegacyMedicalAIStatusText(text) != nil
    }

    private func isMedicalAIStatusMessage(_ text: String) -> Bool {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalizedLegacyMedicalAIStatusText(trimmedText) != nil
            || trimmedText.contains("医疗智能体暂时无法连接")
            || trimmedText.contains("医疗智能体响应超时")
            || trimmedText.contains("医疗智能体网络暂时无法连接")
            || trimmedText.contains("iPhone 当前网络无法连接医疗智能体")
            || trimmedText.contains("尚未获得共享授权")
            || trimmedText.contains("当前授权范围不足")
    }

    private func purgeVisibleQuickPromptMessagesIfNeeded() {
        guard !hasPurgedVisibleQuickPromptMessages else {
            return
        }
        let promptFragments = [
            "请只基于 App 内授权共享的今日提醒",
            "请只基于 App 内授权共享的药品信息和说明书摘要",
            "请只基于 App 内授权共享的服药记录",
            "请只基于 App 内授权共享的药品、服药记录",
            "请结合今日天气条件和 App 内授权共享的服药记录",
            "请结合今日环境提示和 App 内授权共享的服药记录",
            "请结合今日天气与环境提示和 App 内授权共享的服药记录",
            "请只回答如何在本 App 内识别、录入、核对或整理这些信息"
        ]
        let messagesToDelete = messages.filter { message in
            message.role == .user && promptFragments.contains(where: { message.text.contains($0) })
        }
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

        let orderedMessages = messages.sorted { $0.createdAt < $1.createdAt }
        guard !orderedMessages.isEmpty else {
            return
        }

        let staleCutoff = Date().addingTimeInterval(-90)
        var repairDrafts: [AIChatResponseDraft] = []
        for (index, message) in orderedMessages.enumerated() where message.role == .user && message.createdAt < staleCutoff {
            let nextMessage = orderedMessages.dropFirst(index + 1).first
            if let nextMessage, nextMessage.role != .user {
                continue
            }

            let repairCreatedAt = repairMessageDate(after: message, before: nextMessage)
            repairDrafts.append(AIChatResponseDraft(
                role: .system,
                text: "上一次医疗智能体请求未完成，请重新发送。",
                createdAt: repairCreatedAt,
                providerName: message.providerName.isEmpty ? configurationStore.configuration.providerName : message.providerName,
                modelName: message.modelName.isEmpty ? configurationStore.configuration.modelName : message.modelName,
                sharedScopesSummary: message.sharedScopesSummary
            ))
        }

        if !repairDrafts.isEmpty {
            _ = commitConversationMessages(
                repairDrafts,
                operation: "ai-reconcile-interrupted-request"
            )
        }
    }

    private func repairMessageDate(after message: StoredAIChatMessage, before nextMessage: StoredAIChatMessage?) -> Date {
        guard let nextMessage else {
            return message.createdAt.addingTimeInterval(1)
        }
        let gap = nextMessage.createdAt.timeIntervalSince(message.createdAt)
        guard gap > 0 else {
            return message.createdAt.addingTimeInterval(0.1)
        }
        return message.createdAt.addingTimeInterval(min(1, gap / 2))
    }

    private func buildRequest(userMessage: String, consent: StoredAIConsent) -> MedicalAIRequest {
        let snapshots: [MedicalAIMedicationSnapshot]
        if consent.sharesMedicationProfile {
            let measurableTasks = tasksForAIContext(userMessage: userMessage)
            snapshots = medications.filter { $0.lifecycleStatus == .active }.map { medication in
                let relatedTasks = measurableTasks.filter { $0.medicationID == medication.id }
                let relatedPlans = consent.sharesMedicationPlans
                    ? plans.filter { $0.medicationID == medication.id }.compactMap { $0.corePlan(using: relatedTasks) }
                    : []
                let relatedRiskCards = consent.sharesRiskCards
                    ? riskCards.filter { $0.medicationID == medication.id && $0.isActive }.map(\.coreRiskCard)
                    : []
                return MedicalAIMedicationSnapshot(
                    medication: medication.coreMedication,
                    plans: relatedPlans,
                    scheduledDoses: consent.sharesDoseEvents ? relatedTasks.map(\.coreScheduledDose) : [],
                    doseEvents: consent.sharesDoseEvents ? relatedTasks.compactMap(\.coreDoseEventUsingEffectiveAdherenceDate) : [],
                    riskCards: relatedRiskCards,
                    labelSummary: consent.sharesDrugLabels ? readableLabelSummary(for: medication) : nil
                )
            }
        } else {
            snapshots = []
        }

        let request = MedicalAIRequest(
            kind: .chat,
            userMessage: userMessage,
            authorization: consent.authorization,
            medicationSnapshots: snapshots,
            environmentInsights: environmentInsightsForAI(userMessage: userMessage),
            localeIdentifier: Locale.current.identifier
        )
        let scheduledDoseCount = snapshots.reduce(0) { $0 + $1.scheduledDoses.count }
        let doseEventCount = snapshots.reduce(0) { $0 + $1.doseEvents.count }
        logAIEvent("context requestID=\(request.id.uuidString) medications=\(snapshots.count) scheduledDoses=\(scheduledDoseCount) doseEvents=\(doseEventCount) todayMode=\(isTodayAIQuestion(userMessage))")
        return request
    }

    private func tasksForAIContext(userMessage: String) -> [StoredDoseTask] {
        if isTodayAIQuestion(userMessage) {
            return todayTasksForAIContext()
        }
        return tasks.adherenceMeasurableTasks
    }

    private func isTodayAIQuestion(_ userMessage: String) -> Bool {
        userMessage.contains("今日") || userMessage.contains("今天")
    }

    private func todayTasksForAIContext() -> [StoredDoseTask] {
        let calendar = Calendar.current
        let todayTasks = tasks.filter { task in
            guard task.isAdherenceMeasurable else {
                return false
            }
            guard medications.contains(where: { $0.id == task.medicationID && $0.lifecycleStatus == .active }) else {
                return false
            }
            if calendar.isDateInToday(task.dueAt) {
                return true
            }
            return task.status == .delayed
                && task.recordedAt.map(calendar.isDateInToday) == true
                && isOpenDoseStatusForAI(task.status)
        }
        var tasksByLogicalDose: [String: StoredDoseTask] = [:]
        for task in todayTasks {
            let key = DoseLogicalGroup.key(for: task)
            if let current = tasksByLogicalDose[key] {
                tasksByLogicalDose[key] = preferredTodayTaskForAI(current, task)
            } else {
                tasksByLogicalDose[key] = task
            }
        }
        return tasksByLogicalDose.values.sorted { lhs, rhs in
            if lhs.dueAt == rhs.dueAt {
                return lhs.id.uuidString < rhs.id.uuidString
            }
            return lhs.dueAt < rhs.dueAt
        }
    }

    private func preferredTodayTaskForAI(_ lhs: StoredDoseTask, _ rhs: StoredDoseTask) -> StoredDoseTask {
        let lhsScore = aiDisplayPriorityScore(for: lhs)
        let rhsScore = aiDisplayPriorityScore(for: rhs)
        if lhsScore != rhsScore {
            return lhsScore > rhsScore ? lhs : rhs
        }
        let lhsReferenceDate = lhs.effectiveAdherenceDate
        let rhsReferenceDate = rhs.effectiveAdherenceDate
        if lhsReferenceDate != rhsReferenceDate {
            return lhsReferenceDate > rhsReferenceDate ? lhs : rhs
        }
        return lhs.id.uuidString < rhs.id.uuidString ? lhs : rhs
    }

    private func aiDisplayPriorityScore(for task: StoredDoseTask) -> Int {
        var score = 0
        if task.recordedAt != nil {
            score += 120
        }
        switch task.status {
        case .taken, .corrected:
            score += 500
        case .skipped:
            score += 480
        case .delayed:
            score += 360
        case .pending:
            score += 300
        }
        return score
    }

    private func isOpenDoseStatusForAI(_ status: StoredDoseStatus) -> Bool {
        status == .pending || status == .delayed
    }

    private func todayOpenMedicationNamesForPrompt() -> [String] {
        var names: [String] = []
        for task in todayTasksForAIContext() where isOpenDoseStatusForAI(task.status) {
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
        guard let startIndex = visibleConversationStartIndex(in: orderedMessages), startIndex > orderedMessages.startIndex else {
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
        guard shouldAttachEnvironmentContext(to: userMessage) else {
            return []
        }

        if !weatherMedicationService.hints.isEmpty {
            return weatherMedicationService.hints.prefix(3).map { hint in
                MedicalAIEnvironmentInsight(
                    title: hint.title,
                    message: hint.message,
                    sourceSummary: hint.sourceSummary,
                    severityText: hint.severity.displayName
                )
            }
        }

        return EnvironmentMedicationInsightBuilder()
            .fallback(medications: activeMedicationEnvironmentProfiles(), limit: 3)
            .map { insight in
                MedicalAIEnvironmentInsight(
                    title: insight.title,
                    message: insight.message,
                    sourceSummary: insight.sourceSummary,
                    severityText: insight.severity.displayName
                )
            }
    }

    private func shouldAttachEnvironmentContext(to userMessage: String) -> Bool {
        MedicalAIEnvironmentQuestionDetector().shouldAttachEnvironmentContext(to: userMessage)
    }

    private func activeMedicationEnvironmentProfiles() -> [EnvironmentMedicationProfileItem] {
        medications
            .filter { $0.lifecycleStatus == .active }
            .map { medication in
                EnvironmentMedicationProfileItem(
                    id: medication.id,
                    displayName: userFacingMedicationName(for: medication),
                    genericName: medication.genericName,
                    form: medication.form,
                    notes: medication.notes,
                    isActive: true
                )
            }
    }

    private func readableLabelSummary(for medication: StoredMedication) -> ReadableLabelSummary? {
        let label = labels.first { $0.medicationID == medication.id }?.coreLabel
        guard let label else {
            return nil
        }
        return ReadableLabelSummaryBuilder().build(from: label)
    }

    private func saveConsent(_ draft: AIConsentDraft) {
        _ = AIConversationPersistenceCommand(modelContext: modelContext).saveConsent(
            existing: storedConsent,
            draft: draft,
            grantedAt: Date()
        )
    }

    private func revokeConsent() {
        guard let consent = storedConsent else {
            return
        }
        _ = AIConversationPersistenceCommand(modelContext: modelContext).revokeConsent(
            consent,
            revokedAt: Date()
        )
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

    private func scrollToLatest(using proxy: ScrollViewProxy) {
        withAnimation(.snappy(duration: 0.22, extraBounce: 0.02)) {
            if localStreamingResponse != nil {
                proxy.scrollTo("local-streaming-response", anchor: .bottom)
            } else if isSending {
                proxy.scrollTo("thinking", anchor: .bottom)
            } else if let lastMessage = visibleMessages.last {
                proxy.scrollTo(lastMessage.id, anchor: .bottom)
            }
        }
    }
}
