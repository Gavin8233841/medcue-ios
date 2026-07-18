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
        .onChange(of: activeAppTab) { _, _ in
            prepareAssistantSessionIfVisible()
        }
        .onChange(of: selectedChatImageItem) { _, newItem in
            Task {
                await prepareImageQuestion(newItem)
            }
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
        modelContext.insert(StoredAIChatMessage(
            role: .system,
            text: "云端智能体尚未开启。开启云端能力后，在线模式才会连接外部服务；未开启时不会发送任何用药数据。",
            providerName: configuration.providerName,
            modelName: configuration.modelName,
            sharedScopesSummary: activeConsent?.scopeSummary ?? "未授权"
        ))
        try? modelContext.save()
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
            modelContext.insert(StoredAIChatMessage(
                role: .system,
                text: readiness.userFacingMessage ?? "云端智能体尚未开启。快捷问题没有发送到外部服务；开启云端能力后即可使用在线智能体。",
                providerName: configuration.providerName,
                modelName: configuration.modelName,
                sharedScopesSummary: consent?.scopeSummary ?? "未授权"
            ))
            try? modelContext.save()
            return
        }

        withAnimation(.snappy(duration: 0.22, extraBounce: 0.02)) {
            showingRuntimePicker = false
        }
        modelContext.insert(StoredAIChatMessage(
            role: .user,
            text: displayText,
            providerName: providerName,
            modelName: modelName,
            sharedScopesSummary: consent?.scopeSummary ?? "未授权"
        ))
        draftMessage = ""

        guard let consent else {
            modelContext.insert(StoredAIChatMessage(
                role: .system,
                text: "尚未获得共享授权，因此没有读取任何用药数据。请先在授权页选择共享范围。",
                providerName: configuration.providerName,
                modelName: configuration.modelName,
                sharedScopesSummary: "未授权"
            ))
            try? modelContext.save()
            showingConsentSheet = true
            return
        }

        let request = buildRequest(userMessage: requestText, consent: consent)
        let missingScopes = MedicalAIRequestValidator().missingRequiredScopes(for: request)
        if !missingScopes.isEmpty {
            modelContext.insert(StoredAIChatMessage(
                role: .system,
                text: "当前授权范围不足，未发送请求。缺少：\(missingScopes.map(scopeDisplayName).sorted().joined(separator: "、"))。",
                providerName: configuration.providerName,
                modelName: configuration.modelName,
                sharedScopesSummary: consent.scopeSummary
            ))
            try? modelContext.save()
            return
        }

        if prefersLocalMedicalModel {
            guard localModelStore.status.canUseForResponses, let modelURL = localModelStore.readyModelURL else {
                prefersLocalMedicalModel = false
                modelContext.insert(StoredAIChatMessage(
                    role: .system,
                    text: "离线智能体暂时不可用，已切换为在线智能体。请重新发送这条消息。",
                    providerName: "离线智能体",
                    modelName: LocalMedicalModelStore.modelDisplayName,
                    sharedScopesSummary: consent.scopeSummary
                ))
                try? modelContext.save()
                return
            }
            try? modelContext.save()
            sendConfirmedLocalModelRequest(PendingLocalAIRequest(
                request: request,
                sharedScopesSummary: consent.scopeSummary,
                modelURL: modelURL
            ))
            return
        }

        guard readiness.canSend else {
            logAIEvent("not-ready \(readiness.diagnosticSummary)")
            modelContext.insert(StoredAIChatMessage(
                role: .system,
                text: readiness.userFacingMessage ?? "医疗智能体暂时无法连接，未发送任何用药数据。请稍后重试。",
                providerName: configuration.providerName,
                modelName: configuration.modelName,
                sharedScopesSummary: consent.scopeSummary
            ))
            try? modelContext.save()
            return
        }

        guard configurationStore.apiKey(for: configuration)?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            logAIEvent("not-ready missing-key-after-readiness provider=\(configuration.providerName) kind=\(configuration.providerKind.rawValue)")
            modelContext.insert(StoredAIChatMessage(
                role: .system,
                text: "医疗智能体暂时无法连接，未发送任何用药数据。请稍后重试。",
                providerName: configuration.providerName,
                modelName: configuration.modelName,
                sharedScopesSummary: consent.scopeSummary
            ))
            try? modelContext.save()
            return
        }

        try? modelContext.save()
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

    private func prepareImageQuestion(_ item: PhotosPickerItem?) async {
        guard let item else {
            return
        }
        await MainActor.run {
            isReadingImage = true
        }
        defer {
            Task { @MainActor in
                isReadingImage = false
                selectedChatImageItem = nil
            }
        }
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                await MainActor.run {
                    draftMessage = "我上传了一张药品相关图片，但没有读取到图片数据。请告诉我该如何在 App 内手动补全药品信息。"
                }
                return
            }
            let result = try await VisionImportService().recognizePrescriptionText(from: data)
            let excerpt = String(result.text.prefix(700))
            await MainActor.run {
                draftMessage = """
                我上传了一张药品相关图片，图片中的文字如下：
                \(excerpt)

                我想了解这些信息如何用于药品录入、说明书核对或复诊沟通。
                """
            }
        } catch {
            await MainActor.run {
                draftMessage = "我上传了一张药品相关图片，但没有读出清晰文字。请告诉我如何在 App 内手动补全药名、规格、剂型和提醒。"
            }
        }
    }

    private func sendConfirmedDirectAPIRequest(_ pendingRequest: PendingDirectAIRequest) {
        let configuration = configurationStore.refreshInjectedSecretsIfAvailable()
        guard let apiKey = configurationStore.apiKey(for: configuration), !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            logAIEvent("missing-key provider=\(configuration.providerName) kind=\(configuration.providerKind.rawValue)")
            modelContext.insert(StoredAIChatMessage(
                role: .system,
                text: "医疗智能体暂时无法连接，未发送任何用药数据。请稍后重试。",
                providerName: configuration.providerName,
                modelName: configuration.modelName,
                sharedScopesSummary: pendingRequest.sharedScopesSummary
            ))
            try? modelContext.save()
            return
        }

        isSending = true
        logAIEvent("sending provider=\(configuration.providerName) kind=\(configuration.providerKind.rawValue) keySource=\(configurationStore.apiKeySourceDescription(for: configuration)) scopes=\(pendingRequest.sharedScopesSummary)")
        Task {
            await sendDirectAPIRequest(
                request: pendingRequest.request,
                sharedScopesSummary: pendingRequest.sharedScopesSummary,
                configuration: configuration,
                apiKey: apiKey
            )
        }
    }

    private func sendConfirmedLocalModelRequest(_ pendingRequest: PendingLocalAIRequest) {
        isSending = true
        logAIEvent("sending provider=local requestID=\(pendingRequest.request.id.uuidString) model=\(LocalMedicalModelStore.modelDisplayName) scopes=\(pendingRequest.sharedScopesSummary)")
        Task {
            await sendLocalModelRequest(
                request: pendingRequest.request,
                sharedScopesSummary: pendingRequest.sharedScopesSummary,
                modelURL: pendingRequest.modelURL
            )
        }
    }

    @MainActor
    private func sendLocalModelRequest(
        request: MedicalAIRequest,
        sharedScopesSummary: String,
        modelURL: URL
    ) async {
        defer {
            isSending = false
            if localStreamingResponse?.isCompleted == true {
                localStreamingResponse = nil
            }
        }

        do {
            localStreamingResponse = LocalStreamingAIResponse()
            let client = LocalMedicalAIClient(modelURL: modelURL)
            var finalAnswer = ""
            var finalThinking = ""
            for try await event in client.streamResponse(to: request) {
                switch event {
                case .generationStarted:
                    localStreamingResponse?.statusText = "正在思考"
                case .modelLoading:
                    localStreamingResponse?.statusText = "正在加载本地端模型"
                case .prefillStarted:
                    localStreamingResponse?.statusText = "深度思考中"
                case .thinkingStarted:
                    localStreamingResponse?.statusText = "深度思考中"
                    localStreamingResponse?.isThinkingExpanded = true
                case .thinkingDelta:
                    localStreamingResponse?.statusText = "深度思考中"
                case .answerStarted:
                    localStreamingResponse?.statusText = "正在整理正式回答"
                case .answerDelta:
                    localStreamingResponse?.statusText = "正在整理正式回答"
                case let .generationCompleted(answer, thinking):
                    finalAnswer = answer
                    finalThinking = thinking
                    localStreamingResponse?.statusText = "正在进行安全检查"
                case let .generationFailed(message):
                    localStreamingResponse?.statusText = message
                }
            }
            let rawAnswer = finalAnswer.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !rawAnswer.isEmpty else {
                throw LocalMedicalAIError.emptyResponse
            }

            let boundaryGuard = MedicalAIResponseBoundaryGuard()
            let boundaryReview = boundaryGuard.review(rawAnswer)
            let displayMessage = boundaryReview.displayMessage.trimmingCharacters(in: .whitespacesAndNewlines)
            let rawThinking = finalThinking.trimmingCharacters(in: .whitespacesAndNewlines)
            let thinkingReview = rawThinking.isEmpty ? nil : boundaryGuard.review(rawThinking)
            let persistedThinking = boundaryReview.blockedActionableInstruction || thinkingReview?.blockedActionableInstruction == true
                ? ""
                : rawThinking
            let persistedMessage = persistedThinking.isEmpty
                ? displayMessage
                : "\(displayMessage)\(LocalMedicalAIClient.localReasoningSeparator)\(persistedThinking)"
            let boundaryFlags = boundaryReview.flags.joined(separator: ",")
            localStreamingResponse?.answerText = displayMessage
            localStreamingResponse?.thinkingText = persistedThinking
            localStreamingResponse?.statusText = "已完成安全检查"
            localStreamingResponse?.completedAt = Date()
            localStreamingResponse?.isThinkingExpanded = false
            logAIEvent("success provider=local requestID=\(request.id.uuidString) rawLength=\(finalAnswer.count) displayLength=\(displayMessage.count) thinkingLength=\(persistedThinking.count) appendedSafetyNote=\(boundaryReview.appendedSafetyNote) blocked=\(boundaryReview.blockedActionableInstruction) thinkingBlocked=\(thinkingReview?.blockedActionableInstruction == true) flags=\(boundaryFlags)")
            localStreamingResponse = nil
            modelContext.insert(StoredAIChatMessage(
                role: .assistant,
                text: persistedMessage,
                providerName: "离线智能体",
                modelName: LocalMedicalModelStore.modelDisplayName,
                sharedScopesSummary: sharedScopesSummary
            ))
            archiveOlderVisibleConversationIfNeeded()
        } catch {
            localStreamingResponse = nil
            let message = classifyAITransportError(error)
            logAIEvent("error provider=local requestID=\(request.id.uuidString) \(transportDiagnosticSummary(error))")
            modelContext.insert(StoredAIChatMessage(
                role: .system,
                text: message,
                providerName: "离线智能体",
                modelName: LocalMedicalModelStore.modelDisplayName,
                sharedScopesSummary: sharedScopesSummary
            ))
            archiveOlderVisibleConversationIfNeeded()
        }
        try? modelContext.save()
    }

    @MainActor
    private func sendDirectAPIRequest(
        request: MedicalAIRequest,
        sharedScopesSummary: String,
        configuration: MedicalAIConfiguration,
        apiKey: String
    ) async {
        defer {
            isSending = false
        }

        do {
            let response = try await performMedicalAIRequest(
                request: request,
                configuration: configuration,
                apiKey: apiKey
            )
            let boundaryReview = MedicalAIResponseBoundaryGuard().review(response.message)
            let displayMessage = boundaryReview.displayMessage.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !displayMessage.isEmpty else {
                throw DoubaoMedicalAIError.emptyMessage
            }
            let boundaryFlags = boundaryReview.flags.joined(separator: ",")
            logAIEvent("success provider=\(response.provider.providerName) rawLength=\(response.message.count) displayLength=\(displayMessage.count) appendedSafetyNote=\(boundaryReview.appendedSafetyNote) flags=\(boundaryFlags)")
            modelContext.insert(StoredAIChatMessage(
                role: .assistant,
                text: displayMessage,
                providerName: response.provider.providerName,
                modelName: response.provider.modelName,
                sharedScopesSummary: sharedScopesSummary
            ))
            archiveOlderVisibleConversationIfNeeded()
            configurationStore.promoteCurrentAPIKeyIfNeeded(for: configuration)
        } catch {
            let message = classifyAITransportError(error)
            logAIEvent("error provider=\(configuration.providerName) kind=\(configuration.providerKind.rawValue) \(transportDiagnosticSummary(error))")
            modelContext.insert(StoredAIChatMessage(
                role: .system,
                text: message,
                providerName: configuration.providerName,
                modelName: configuration.modelName,
                sharedScopesSummary: sharedScopesSummary
            ))
            archiveOlderVisibleConversationIfNeeded()
        }
        try? modelContext.save()
    }

    private func performMedicalAIRequest(
        request: MedicalAIRequest,
        configuration: MedicalAIConfiguration,
        apiKey: String
    ) async throws -> MedicalAIResponse {
        let client = medicalAIClient(configuration: configuration, apiKey: apiKey)
        return try await withThrowingTaskGroup(of: MedicalAIResponse.self) { group in
            group.addTask {
                try await client.respond(to: request)
            }
            group.addTask {
                try await Task.sleep(for: .seconds(20))
                throw MedicalAIRequestTimeoutError()
            }
            guard let response = try await group.next() else {
                throw MedicalAIRequestTimeoutError()
            }
            group.cancelAll()
            return response
        }
    }

    private func performLocalMedicalAIRequest(request: MedicalAIRequest, modelURL: URL) async throws -> MedicalAIResponse {
        let client = LocalMedicalAIClient(modelURL: modelURL)
        return try await withThrowingTaskGroup(of: MedicalAIResponse.self) { group in
            group.addTask {
                try await client.respond(to: request)
            }
            group.addTask {
                try await Task.sleep(for: .seconds(90))
                throw MedicalAIRequestTimeoutError()
            }
            guard let response = try await group.next() else {
                throw MedicalAIRequestTimeoutError()
            }
            group.cancelAll()
            return response
        }
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
        if let error = error as? MedicalAIRequestTimeoutError, let description = error.errorDescription {
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
        if error is MedicalAIRequestTimeoutError {
            return "request-timeout"
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

    private func purgePreProviderDemoMessagesIfNeeded() {
        guard !hasPurgedPreProviderDemoMessages else {
            return
        }
        for message in messages {
            modelContext.delete(message)
        }
        try? modelContext.save()
        hasPurgedPreProviderDemoMessages = true
    }

    private func migrateLegacyMedicalAIStatusMessagesIfNeeded() {
        var didUpdate = false
        for message in messages where message.role == .assistant && isMedicalAIStatusMessage(message.text) {
            message.roleRaw = StoredAIChatRole.system.rawValue
            message.providerName = ""
            message.modelName = ""
            didUpdate = true
        }
        if didUpdate {
            try? modelContext.save()
        }
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

        for message in messages where messageIDsToDelete.contains(message.id) {
            modelContext.delete(message)
        }
        if !messageIDsToDelete.isEmpty {
            try? modelContext.save()
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
        for message in messages where message.role == .user {
            if promptFragments.contains(where: { message.text.contains($0) }) {
                modelContext.delete(message)
            }
        }
        try? modelContext.save()
        hasPurgedVisibleQuickPromptMessages = true
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
        var insertedRepairMessage = false
        for (index, message) in orderedMessages.enumerated() where message.role == .user && message.createdAt < staleCutoff {
            let nextMessage = orderedMessages.dropFirst(index + 1).first
            if let nextMessage, nextMessage.role != .user {
                continue
            }

            let repairCreatedAt = repairMessageDate(after: message, before: nextMessage)
            modelContext.insert(StoredAIChatMessage(
                role: .system,
                text: "上一次医疗智能体请求未完成，请重新发送。",
                createdAt: repairCreatedAt,
                providerName: message.providerName.isEmpty ? configurationStore.configuration.providerName : message.providerName,
                modelName: message.modelName.isEmpty ? configurationStore.configuration.modelName : message.modelName,
                sharedScopesSummary: message.sharedScopesSummary
            ))
            insertedRepairMessage = true
        }

        if insertedRepairMessage {
            try? modelContext.save()
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
        var archivedIDs = manuallyArchivedMessageIDs
        for message in messagesToDelete {
            archivedIDs.remove(message.id)
            modelContext.delete(message)
        }
        archivedMessageIDStorage = archivedIDs
            .map(\.uuidString)
            .sorted()
            .joined(separator: "|")
        try? modelContext.save()
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
        let consent = storedConsent ?? StoredAIConsent()
        consent.sharesMedicationProfile = draft.sharesMedicationProfile
        consent.sharesMedicationPlans = draft.sharesMedicationPlans
        consent.sharesDoseEvents = draft.sharesDoseEvents
        consent.sharesRiskCards = draft.sharesRiskCards
        consent.sharesDrugLabels = draft.sharesDrugLabels
        consent.sharesImportDraft = draft.sharesImportDraft
        consent.grantedAt = Date()
        consent.revokedAt = nil
        consent.note = "用户授权医疗智能体读取选定范围的数据。"
        if storedConsent == nil {
            modelContext.insert(consent)
        }
        try? modelContext.save()
    }

    private func revokeConsent() {
        guard let consent = storedConsent else {
            return
        }
        consent.revokedAt = Date()
        modelContext.insert(StoredAIChatMessage(
            role: .system,
            text: "医疗智能体数据共享授权已撤销。",
            sharedScopesSummary: "已撤销"
        ))
        try? modelContext.save()
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

private struct MedicalAIRequestTimeoutError: LocalizedError {
    var errorDescription: String? {
        "医疗智能体响应超时，请稍后重试。"
    }
}

private struct PendingDirectAIRequest: Identifiable {
    let id = UUID()
    let request: MedicalAIRequest
    let sharedScopesSummary: String
    let configuration: MedicalAIConfiguration
}

private struct PendingLocalAIRequest: Identifiable {
    let id = UUID()
    let request: MedicalAIRequest
    let sharedScopesSummary: String
    let modelURL: URL
}

private struct LocalStreamingAIResponse {
    var thinkingText = ""
    var answerText = ""
    var statusText = "正在思考"
    var startedAt = Date()
    var completedAt: Date?
    var isThinkingExpanded = true

    var elapsedSeconds: Int {
        max(0, Int((completedAt ?? Date()).timeIntervalSince(startedAt).rounded()))
    }

    var isCompleted: Bool {
        completedAt != nil
    }
}

private struct AIOutgoingMessage {
    let displayText: String
    let requestText: String
}

private struct AgentRuntimeSelectorBar: View {
    let onlineConfiguration: MedicalAIConfiguration
    let onlineReadiness: MedicalAITransportReadiness
    let status: LocalMedicalModelStatus
    let prefersLocalResponses: Bool
    let hasUserSelectedRuntime: Bool
    let isExpanded: Bool
    let toggleExpanded: () -> Void
    let selectOnline: () -> Void
    let selectLocal: () -> Void
    let requestLocalDownload: () -> Void

    private var onlineStatusText: String {
        onlineReadiness.canSend ? "已可用" : "未开启"
    }

    private var offlineButtonTitle: String {
        switch status.availability {
        case .notDownloaded:
            return "下载离线模型"
        case .downloading:
            return "正在下载"
        case .ready:
            return "使用离线模型"
        case .failed:
            return "重新下载"
        }
    }

    private var offlineStatusText: String {
        switch status.availability {
        case .notDownloaded:
            return "未安装模型"
        case .downloading:
            return "下载中"
        case .ready:
            return status.canUseForResponses ? "模型已安装" : "模型已下载"
        case .failed:
            return "模型不可用"
        }
    }

    private var activeTitle: String {
        prefersLocalResponses ? "设备端模型 Beta" : "云端智能体"
    }

    private var activeSubtitle: String {
        prefersLocalResponses ? "在 iPhone 上本地推理" : "连接云端能力，适合复杂任务"
    }

    private var activeTint: Color {
        prefersLocalResponses ? Color(red: 0.28, green: 0.56, blue: 0.48) : Color(red: 0.28, green: 0.48, blue: 0.62)
    }

    private var shouldUseCompactChip: Bool {
        hasUserSelectedRuntime && !isExpanded
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Button(action: toggleExpanded) {
                    HStack(spacing: 8) {
                        Image(systemName: prefersLocalResponses ? "iphone.gen3.radiowaves.left.and.right" : "network")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(activeTint)
                            .frame(width: shouldUseCompactChip ? 24 : 28, height: shouldUseCompactChip ? 24 : 28)
                            .background(activeTint.opacity(0.10), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        if shouldUseCompactChip {
                            Text(prefersLocalResponses ? "端侧" : "云端")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                        } else {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(activeTitle)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.primary)
                                Text(activeSubtitle)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                        Image(systemName: "chevron.down")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.secondary)
                            .rotationEffect(.degrees(isExpanded ? 180 : 0))
                    }
                    .padding(.horizontal, shouldUseCompactChip ? 9 : 10)
                    .padding(.vertical, shouldUseCompactChip ? 7 : 8)
                    .background(.ultraThinMaterial, in: Capsule())
                    .overlay(
                        Capsule()
                            .stroke(Color.secondary.opacity(0.12), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("切换智能体模式")

                Spacer(minLength: 8)

                if !shouldUseCompactChip {
                    Text(prefersLocalResponses ? "Beta" : onlineStatusText)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(prefersLocalResponses ? Color.secondary : activeTint)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color(.secondarySystemGroupedBackground), in: Capsule())
                }
            }

            if isExpanded {
                VStack(spacing: 8) {
                    RuntimeChoiceRow(
                        title: "云端智能体",
                        subtitle: "连接云端能力，适合复杂问题和更长文本",
                        status: onlineStatusText,
                        progress: nil,
                        progressText: nil,
                        iconName: "network",
                        tint: .blue,
                        isSelected: !prefersLocalResponses,
                        isEnabled: true,
                        actionTitle: onlineReadiness.canSend ? "使用" : "开启",
                        action: selectOnline
                    )

                    RuntimeChoiceRow(
                        title: "设备端模型 Beta",
                        subtitle: status.canUseForResponses
                            ? "模型在这台 iPhone 上运行，数据留在设备上"
                            : "下载约 265MB 后启用本地推理，当前为 Beta 版本",
                        status: offlineStatusText,
                        progress: status.availability == .downloading ? (status.downloadProgress ?? 0.01) : status.downloadProgress,
                        progressText: status.fileSizeText ?? (status.availability == .downloading ? "正在连接下载源" : nil),
                        iconName: "iphone.gen3.radiowaves.left.and.right",
                        tint: .green,
                        isSelected: prefersLocalResponses,
                        isEnabled: status.canUseForResponses,
                        actionTitle: status.canUseForResponses ? "使用" : offlineButtonTitle,
                        action: {
                            if status.canUseForResponses {
                                selectLocal()
                            } else if status.canStartDownload {
                                requestLocalDownload()
                            }
                        }
                    )

                    Text("设备端模型会在这台 iPhone 上运行，本次输入默认留在设备上；Beta 版本回答可能不如云端智能体稳定。云端模式只有在你主动选择并开启后才会调用外部服务。")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.horizontal, 2)
    }
}

private struct RuntimeChoiceRow: View {
    let title: String
    let subtitle: String
    let status: String
    let progress: Double?
    let progressText: String?
    let iconName: String
    let tint: Color
    let isSelected: Bool
    let isEnabled: Bool
    let actionTitle: String
    let action: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: iconName)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(isEnabled ? tint : .secondary)
                .frame(width: 32, height: 32)
                .background((isEnabled ? tint : Color.secondary).opacity(0.12), in: RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(isEnabled ? .primary : .secondary)
                    Text(status)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(isEnabled ? tint : .secondary)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background((isEnabled ? tint : Color.secondary).opacity(0.12), in: Capsule())
                }
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                if let progress {
                    VStack(alignment: .leading, spacing: 4) {
                        ProgressView(value: progress)
                            .tint(tint)
                        if let progressText {
                            Text("\(Int((progress * 100).rounded()))% · \(progressText)")
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }
                    .padding(.top, 2)
                } else if let progressText {
                    Text(progressText)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }

            Spacer(minLength: 8)

            if isSelected {
                Button(actionTitle, action: action)
                    .font(.caption.weight(.semibold))
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            } else {
                Button(actionTitle, action: action)
                    .font(.caption.weight(.semibold))
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
        .padding(10)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isSelected ? tint.opacity(0.45) : Color.clear, lineWidth: 1)
        )
        .opacity(isEnabled || !isSelected ? 1 : 0.62)
    }
}

private struct FlowBadges: View {
    let items: [String]
    let tint: Color

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 86), spacing: 6)], alignment: .leading, spacing: 6) {
            ForEach(items, id: \.self) { item in
                Text(item)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(tint)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(tint.opacity(0.1), in: Capsule())
            }
        }
    }
}

private struct LocalMedicalModelStatusView: View {
    let status: LocalMedicalModelStatus
    let prefersLocalResponses: Bool
    let download: () -> Void
    let toggleLocalResponses: () -> Void

    private var isReady: Bool {
        status.availability == .ready
    }

    private var isDownloading: Bool {
        status.availability == .downloading
    }

    private var iconName: String {
        switch status.availability {
        case .notDownloaded:
            return "arrow.down.circle"
        case .downloading:
            return "arrow.down.circle.fill"
        case .ready:
            return "iphone.gen3.radiowaves.left.and.right"
        case .failed:
            return "exclamationmark.arrow.triangle.2.circlepath"
        }
    }

    private var tint: Color {
        switch status.availability {
        case .notDownloaded, .downloading:
            return .blue
        case .ready:
            return .green
        case .failed:
            return .orange
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: iconName)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 30, height: 30)
                .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Text(status.displayName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    if let fileSizeText = status.fileSizeText {
                        Text(fileSizeText)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                }
                Text(status.detailText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if let progress = status.downloadProgress {
                    ProgressView(value: progress)
                        .tint(tint)
                    if let fileSizeText = status.fileSizeText {
                        Text("\(Int((progress * 100).rounded()))% · \(fileSizeText)")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }

                if let actionTitle = status.actionTitle {
                    Button(actionTitle, action: download)
                        .font(.caption.weight(.semibold))
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .disabled(!status.canStartDownload || isDownloading)
                }

                if status.canUseForResponses {
                    Button(prefersLocalResponses ? "使用在线智能体" : "使用离线模型", action: toggleLocalResponses)
                        .font(.caption.weight(.semibold))
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .combine)
    }
}

private struct AIQuickActionsSection: View {
    let isDisabled: Bool
    let prefersLocalResponses: Bool
    let send: (AIOutgoingMessage?) -> Void
    @AppStorage("isAIQuickActionsExpandedV3") private var isExpanded = false

    private static let actions: [AIQuickAction] = [
        AIQuickAction(
            title: "忽略与稍后趋势",
            subtitle: "近期服药节奏",
            iconName: "chart.xyaxis.line",
            tint: .indigo,
            displayText: "看看近期忽略或稍后趋势",
            requestText: "请只基于 App 内授权共享的服药记录，说明近期忽略或稍后趋势，并给出提醒建议。"
        ),
        AIQuickAction(
            title: "天气与不适",
            subtitle: "环境、症状、提醒",
            iconName: "cloud.sun",
            tint: .teal,
            displayText: "看看今天环境变化需要注意什么",
            requestText: "请只基于 App 内授权共享的今日天气或环境提示，以及今天服药记录，用两三句说明环境变化下记录用药时应留意什么。若没有天气或环境事实，请直接说明本地记录不足。"
        ),
        AIQuickAction(
            title: "药盒与库存",
            subtitle: "编号、余量、提醒",
            iconName: "shippingbox.fill",
            tint: .brown,
            displayText: "帮我检查药盒和库存有什么要注意",
            requestText: "请只基于 App 内授权共享的药品信息、药盒编号、库存和提醒计划，说明药盒与库存管理上需要注意的事项。"
        ),
        AIQuickAction(
            title: "复诊沟通重点",
            subtitle: "便于和医生说明",
            iconName: "stethoscope",
            tint: .green,
            displayText: "帮我整理复诊时要说明的重点",
            requestText: "请只基于 App 内授权共享的服药记录、剂量变化、风险提醒和药品信息，整理复诊时可以说明的重点。"
        ),
        AIQuickAction(
            title: "今日重点核对",
            subtitle: "提醒、风险、记录",
            iconName: "exclamationmark.triangle",
            tint: .orange,
            displayText: "帮我核对今日用药注意事项",
            requestText: "请只基于 App 内授权共享的今日提醒药品、今日记录状态和风险提醒，用两三句说明今天应该先核对什么。不要诊断，不要建议停药、暂停使用、换药或调整剂量。"
        ),
        AIQuickAction(
            title: "说明书重点",
            subtitle: "把复杂内容说清楚",
            iconName: "doc.text.magnifyingglass",
            tint: .blue,
            displayText: "解释今天最需要注意的说明书内容",
            requestText: "请只基于 App 内授权共享的说明书摘要卡片，用两三句整理今天需要复核的说明书栏目。不要推断最终风险结论，不要建议停药、暂停使用、换药或调整剂量。"
        ),
        AIQuickAction(
            title: "风险复核",
            subtitle: "按药物整理",
            iconName: "shield.lefthalf.filled",
            tint: .purple,
            displayText: "整理目前最需要复核的用药风险",
            requestText: "请只基于 App 内授权共享的风险提醒、药品信息和说明书摘要，整理目前最需要复核的用药风险。"
        ),
        AIQuickAction(
            title: "服药记录摘要",
            subtitle: "近期执行情况",
            iconName: "doc.text",
            tint: .mint,
            displayText: "生成一段近期服药记录摘要",
            requestText: "请只基于 App 内授权共享的药品、服药记录和风险提醒，生成一段适合复诊沟通的简短服药记录摘要。"
        ),
        AIQuickAction(
            title: "剂量变化回顾",
            subtitle: "时间段与记录",
            iconName: "arrow.triangle.2.circlepath",
            tint: .cyan,
            displayText: "回顾近期剂量变化和服药记录",
            requestText: "请只基于 App 内授权共享的剂量变化和服药记录，回顾近期剂量调整前后的记录变化。"
        ),
        AIQuickAction(
            title: "图片录入建议",
            subtitle: "药盒、药品、说明书",
            iconName: "photo.on.rectangle",
            tint: .pink,
            displayText: "告诉我如何整理药品图片信息",
            requestText: "我准备上传药盒、药品或说明书图片。请只回答如何在本 App 内识别、录入、核对或整理这些信息。"
        )
    ]

    private var compactActions: [AIQuickAction] {
        ["忽略与稍后趋势", "天气与不适", "药盒与库存", "复诊沟通重点"].compactMap { title in
            Self.actions.first { $0.title == title }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation(.snappy(duration: 0.24, extraBounce: 0.02)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("快捷咨询")
                            .font(.headline)
                            .foregroundStyle(.primary)
                        Text(isExpanded ? "向左滑动查看更多" : "常用问题")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 8)

                    Text(isExpanded ? "收起" : "全部")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isExpanded ? 0 : -90))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(Self.actions) { action in
                            AIQuickActionButton(action: action) {
                                send(AIOutgoingMessage(
                                    displayText: action.displayText,
                                    requestText: action.requestText
                                ))
                            }
                            .disabled(isDisabled)
                            .opacity(isDisabled ? 0.55 : 1)
                        }
                    }
                    .padding(.vertical, 2)
                    .padding(.trailing, 2)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
                .accessibilityLabel("快捷咨询问题")
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(compactActions) { action in
                            AIQuickActionChip(action: action) {
                                send(AIOutgoingMessage(
                                    displayText: action.displayText,
                                    requestText: action.requestText
                                ))
                            }
                            .disabled(isDisabled)
                            .opacity(isDisabled ? 0.55 : 1)
                        }

                        Button {
                            withAnimation(.snappy(duration: 0.24, extraBounce: 0.02)) {
                                isExpanded = true
                            }
                        } label: {
                            Label("更多", systemImage: "ellipsis")
                                .font(.subheadline.weight(.semibold))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 9)
                                .background(Color(.secondarySystemGroupedBackground), in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.vertical, 2)
                    .padding(.trailing, 2)
                }
                .transition(.opacity)
            }
        }
    }
}

private struct AIQuickAction: Identifiable {
    let title: String
    let subtitle: String
    let iconName: String
    let tint: Color
    let displayText: String
    let requestText: String

    var id: String { title }
}

private struct AIQuickActionChip: View {
    let action: AIQuickAction
    let send: () -> Void

    var body: some View {
        Button(action: send) {
            Label(action.title, systemImage: action.iconName)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(action.tint)
                .lineLimit(1)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(action.tint.opacity(0.10), in: Capsule())
                .overlay(
                    Capsule()
                        .stroke(action.tint.opacity(0.14), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(action.title)
    }
}

private struct AIQuickActionButton: View {
    let action: AIQuickAction
    let send: () -> Void

    var body: some View {
        Button(action: send) {
            VStack(alignment: .leading, spacing: 9) {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: action.iconName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(action.tint)
                        .frame(width: 28, height: 28)
                        .background(action.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                    Spacer(minLength: 8)

                    Image(systemName: "arrow.up.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(action.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                    Text(action.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            .frame(width: 168, alignment: .topLeading)
            .frame(minHeight: 112, alignment: .topLeading)
            .padding(12)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.secondary.opacity(0.12), lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(action.title)
        .accessibilityHint(action.subtitle)
    }
}

private struct AIEmptyConversationView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("开始一次用药咨询", systemImage: "bubble.left.and.bubble.right")
                .font(.headline)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background, in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct LocalStreamingResponseView: View {
    let response: LocalStreamingAIResponse
    @State private var isExpanded = true
    @State private var now = Date()

    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var thinkingText: String {
        let text = response.thinkingText.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? "本地端模型正在整理上下文。" : text
    }

    private var elapsedSeconds: Int {
        let end = response.completedAt ?? now
        return max(0, Int(end.timeIntervalSince(response.startedAt).rounded()))
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            VStack(alignment: .leading, spacing: 8) {
                LocalModelReasoningDisclosure(
                    reasoningText: thinkingText,
                    statusText: response.isCompleted ? "已完成思考" : response.statusText,
                    elapsedSeconds: elapsedSeconds,
                    defaultExpanded: !response.isCompleted
                )

                let answer = response.answerText.trimmingCharacters(in: .whitespacesAndNewlines)
                if !answer.isEmpty {
                    Text(answer)
                        .font(.body)
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8))
                }
            }
            Spacer(minLength: 42)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onChange(of: response.isCompleted) { _, isCompleted in
            if isCompleted {
                withAnimation(.snappy(duration: 0.2, extraBounce: 0.02)) {
                    isExpanded = false
                }
            }
        }
        .onReceive(timer) { date in
            guard !response.isCompleted else {
                return
            }
            now = date
        }
    }
}

private struct AIMessageBubble: View {
    let message: StoredAIChatMessage
    let archive: () -> Void

    private var tint: Color {
        switch message.role {
        case .user:
            .blue
        case .assistant:
            .green
        case .system:
            .orange
        }
    }

    private var accessibilityLabelText: String {
        [
            messageDisplayName(for: message),
            AppFormatters.time.string(from: message.createdAt),
            messageDisplayText(for: message)
        ]
        .joined(separator: "，")
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if message.role == .user {
                Spacer()
            }

            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 5) {
                HStack(spacing: 6) {
                    if message.role != .user {
                        Image(systemName: iconName)
                    }
                Text(messageDisplayName(for: message))
                Text(AppFormatters.time.string(from: message.createdAt))
                    .foregroundStyle(.secondary)
                }
                .font(.footnote.weight(.semibold))
                .foregroundStyle(tint)
                .accessibilityHidden(true)

                if let reasoningText = messageReasoningText(for: message) {
                    LocalModelReasoningDisclosure(reasoningText: reasoningText)
                }

                Text(messageDisplayText(for: message))
                    .font(.body)
                    .foregroundStyle(message.role == .user ? .white : .primary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(bubbleBackground, in: RoundedRectangle(cornerRadius: 8))
                    .accessibilityHidden(true)

                if message.role == .assistant {
                    Text("模型可能出现遗漏、误解或幻觉；请结合自身情况甄别，重要用药决定以医生或药师意见为准。")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 4)
                        .accessibilityHidden(true)
                }
            }

            if message.role != .user {
                Spacer(minLength: 42)
            }
        }
        .frame(maxWidth: .infinity, alignment: message.role == .user ? .trailing : .leading)
        .contentShape(Rectangle())
        .contextMenu {
            Button {
                UIPasteboard.general.string = messageDisplayText(for: message)
            } label: {
                Label("复制消息", systemImage: "doc.on.doc")
            }
            Button {
                archive()
            } label: {
                Label("归档此前对话", systemImage: "archivebox")
            }
        }
        .accessibilityRepresentation {
            Text(accessibilityLabelText)
        }
        .accessibilityHint("长按可归档此前对话")
        .accessibilityAction(named: "复制消息") {
            UIPasteboard.general.string = messageDisplayText(for: message)
        }
        .accessibilityAction(named: "归档此前对话", archive)
    }

    private var iconName: String {
        switch message.role {
        case .user:
            "person.fill"
        case .assistant:
            "stethoscope"
        case .system:
            "checkmark.seal"
        }
    }

    private var bubbleBackground: Color {
        switch message.role {
        case .user:
            .blue
        case .assistant:
            Color(.secondarySystemGroupedBackground)
        case .system:
            .orange.opacity(0.14)
        }
    }
}

private func messageDisplayName(for message: StoredAIChatMessage) -> String {
    if message.role == .assistant {
        let providerName = message.providerName.trimmingCharacters(in: .whitespacesAndNewlines)
        if providerName.contains("离线") || providerName.contains("端侧") || providerName.contains("设备端") {
            return "设备端智能体"
        }
        if !providerName.isEmpty {
            return "云端智能体"
        }
        return "医疗智能体"
    }
    return message.role.displayName
}

private func messageDisplayText(for message: StoredAIChatMessage) -> String {
    let text = message.text.trimmingCharacters(in: .whitespacesAndNewlines)
    if message.role == .assistant {
        return removingRepeatedMedicalAISafetyTail(from: formalMessageText(from: text))
    }
    guard message.role == .system else {
        return text
    }
    if let normalizedText = normalizedLegacyMedicalAIStatusText(text) {
        return normalizedText
    }
    return removingRepeatedMedicalAISafetyTail(from: text)
}

private func messageReasoningText(for message: StoredAIChatMessage) -> String? {
    guard message.role == .assistant else {
        return nil
    }
    let components = message.text.components(separatedBy: LocalMedicalAIClient.localReasoningSeparator)
    guard components.count > 1 else {
        return nil
    }
    let reasoningText = components.dropFirst().joined(separator: LocalMedicalAIClient.localReasoningSeparator)
        .trimmingCharacters(in: .whitespacesAndNewlines)
    return reasoningText.isEmpty ? nil : reasoningText
}

private func formalMessageText(from text: String) -> String {
    text.components(separatedBy: LocalMedicalAIClient.localReasoningSeparator)
        .first?
        .trimmingCharacters(in: .whitespacesAndNewlines) ?? text
}

private func normalizedLegacyMedicalAIStatusText(_ text: String) -> String? {
    let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
    let incompleteFragments = [
        "医疗 AI 暂不可用",
        "医疗 AI 暂时没有返回结果",
        "医疗智能体暂时没有返回结果",
        "医疗 AI 请求失败",
        "医疗 AI 返回内容暂时无法读取",
        "上一次医疗 AI 请求未完成",
        "未记录原始响应",
        "医疗 AI 请求超时",
        "医疗 AI 网络连接暂时不可用",
        "iPhone 当前网络无法连接医疗 AI"
    ]
    guard incompleteFragments.contains(where: { trimmedText.contains($0) }) else {
        return nil
    }
    return "上一次医疗智能体请求未完成，请重新发送。"
}

private func removingRepeatedMedicalAISafetyTail(from text: String) -> String {
    var cleanedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
    let repeatedTails = [
        MedicalAIResponseBoundaryGuard.safetyNote,
        "以上内容仅用于风险提示和复诊沟通，不能替代医生或药师判断。",
        "以上内容仅用于用药风险提示和复诊沟通，不能替代医生或药师判断"
    ]
    for tail in repeatedTails {
        let normalizedTail = tail.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleanedText.hasSuffix(normalizedTail) {
            cleanedText = String(cleanedText.dropLast(normalizedTail.count))
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "。；;，,\n "))
        }
    }
    return cleanedText.isEmpty ? text.trimmingCharacters(in: .whitespacesAndNewlines) : cleanedText
}

private struct LocalModelReasoningDisclosure: View {
    let reasoningText: String
    let statusText: String
    let elapsedSeconds: Int?
    @State private var isExpanded: Bool

    init(
        reasoningText: String,
        statusText: String = "已完成思考",
        elapsedSeconds: Int? = nil,
        defaultExpanded: Bool = false
    ) {
        self.reasoningText = reasoningText
        self.statusText = statusText
        self.elapsedSeconds = elapsedSeconds
        _isExpanded = State(initialValue: defaultExpanded)
    }

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            Text(reasoningText)
                .font(.caption)
                .foregroundStyle(Color(.secondaryLabel))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 6)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "sparkles.rectangle.stack")
                Text(statusText)
                if let elapsedSeconds {
                    Text("\(elapsedSeconds) 秒")
                        .foregroundStyle(.secondary)
                }
                Text(isExpanded ? "收起" : "展开")
                    .foregroundStyle(.secondary)
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(Color(red: 0.28, green: 0.48, blue: 0.62))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(Color(red: 0.91, green: 0.96, blue: 0.98).opacity(0.72), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color(red: 0.66, green: 0.78, blue: 0.86).opacity(0.42), lineWidth: 1)
        )
        .frame(maxWidth: 316, alignment: .leading)
        .accessibilityLabel("端侧模型已完成思考")
    }
}

private struct AIThinkingBubble: View {
    let isLocalRuntime: Bool

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text(isLocalRuntime ? "端侧模型正在推理" : "在线智能体正在生成")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                Text(isLocalRuntime ? "正在整理本机记录，稍后给出正式回答。" : "正在等待服务返回正式回答。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.secondary.opacity(0.12), lineWidth: 1)
            )
            Spacer(minLength: 42)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(isLocalRuntime ? "端侧模型正在推理" : "在线智能体正在生成")
    }
}

private struct AIArchivedMessagesSheet: View {
    @Environment(\.dismiss) private var dismiss
    let messages: [StoredAIChatMessage]
    let deleteMessages: ([StoredAIChatMessage]) -> Void
    let deleteAllMessages: () -> Void
    @State private var selection = Set<UUID>()
    @State private var editMode: EditMode = .inactive

    private var selectedMessages: [StoredAIChatMessage] {
        messages.filter { selection.contains($0.id) }
    }

    var body: some View {
        NavigationStack {
            List {
                if messages.isEmpty {
                    ContentUnavailableView("暂无归档", systemImage: "archivebox")
                } else {
                    Section("归档历史") {
                        ForEach(messages) { message in
                            HStack(alignment: .top, spacing: 10) {
                                if editMode.isEditing {
                                    Image(systemName: selection.contains(message.id) ? "checkmark.circle.fill" : "circle")
                                        .font(.title3)
                                        .foregroundStyle(selection.contains(message.id) ? .red : .secondary)
                                        .padding(.top, 2)
                                }

                                VStack(alignment: .leading, spacing: 6) {
                                    HStack {
                                        Text(messageDisplayName(for: message))
                                            .font(.subheadline.weight(.semibold))
                                        Spacer()
                                        Text(AppFormatters.time.string(from: message.createdAt))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Text(messageDisplayText(for: message))
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(4)
                                }
                            }
                            .padding(.vertical, 4)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                guard editMode.isEditing else {
                                    return
                                }
                                if selection.contains(message.id) {
                                    selection.remove(message.id)
                                } else {
                                    selection.insert(message.id)
                                }
                            }
                        }
                    }
                }
            }
            .environment(\.editMode, $editMode)
            .navigationTitle("归档历史")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if !messages.isEmpty {
                        Button(editMode.isEditing ? "取消选择" : "选择") {
                            withAnimation(.snappy(duration: 0.2, extraBounce: 0.02)) {
                                if editMode.isEditing {
                                    editMode = .inactive
                                    selection.removeAll()
                                } else {
                                    editMode = .active
                                }
                            }
                        }
                    }
                }
                ToolbarItem(placement: .bottomBar) {
                    if editMode.isEditing {
                        HStack {
                            Button("全选") {
                                selection = Set(messages.map(\.id))
                            }
                            Spacer()
                            Button(role: .destructive) {
                                deleteMessages(selectedMessages)
                                selection.removeAll()
                                editMode = .inactive
                            } label: {
                                Text("删除所选")
                            }
                            .disabled(selection.isEmpty)
                            Spacer()
                            Button(role: .destructive) {
                                deleteAllMessages()
                                selection.removeAll()
                                editMode = .inactive
                            } label: {
                                Text("全部删除")
                            }
                        }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") {
                        dismiss()
                    }
                }
            }
        }
    }
}

private struct AIChatInputBar: View {
    @Binding var text: String
    @Binding var selectedImageItem: PhotosPickerItem?
    var isFocused: FocusState<Bool>.Binding
    let isSending: Bool
    let isReadingImage: Bool
    let isEnabled: Bool
    let showDisclaimer: () -> Void
    let send: () -> Void

    private var trimmedText: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSend: Bool {
        isEnabled && !isSending && !isReadingImage && !trimmedText.isEmpty
    }

    private var accentTint: Color {
        Color(red: 0.28, green: 0.48, blue: 0.62)
    }

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            PhotosPicker(selection: $selectedImageItem, matching: .images) {
                AIChatAccessoryIcon(
                    systemName: isReadingImage ? "hourglass" : "photo.badge.plus",
                    accessibilityLabel: "发送图片",
                    tint: accentTint,
                    isEnabled: isEnabled && !isSending && !isReadingImage
                )
            }
            .buttonStyle(.plain)
            .disabled(!isEnabled || isSending || isReadingImage)

            TextField(isEnabled ? "询问用药记录、风险提示或说明书摘要" : "确认使用说明后开启咨询", text: $text, axis: .vertical)
                .lineLimit(1...5)
                .textInputAutocapitalization(.never)
                .focused(isFocused)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .frame(minHeight: 44)
                .background(Color(.systemBackground).opacity(0.92), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(accentTint.opacity(isFocused.wrappedValue ? 0.28 : 0.10), lineWidth: 1)
                )
                .disabled(!isEnabled || isSending)
                .toolbar {
                    ToolbarItemGroup(placement: .keyboard) {
                        Spacer()
                        Button("收起") {
                            dismissKeyboard()
                        }
                        .disabled(!isFocused.wrappedValue)
                    }
                }

            Button {
                isEnabled ? send() : showDisclaimer()
            } label: {
                AIChatAccessoryIcon(
                    systemName: isSending ? "hourglass" : "arrow.up",
                    accessibilityLabel: isEnabled ? "发送" : "查看使用说明",
                    tint: accentTint,
                    isEnabled: isEnabled ? canSend : true,
                    isProminent: true
                )
            }
            .buttonStyle(.plain)
            .disabled(isSending || isReadingImage || (isEnabled && trimmedText.isEmpty))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(accentTint.opacity(0.14), lineWidth: 1)
        )
        .shadow(color: accentTint.opacity(0.06), radius: 10, x: 0, y: 4)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func dismissKeyboard() {
        isFocused.wrappedValue = false
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil,
            from: nil,
            for: nil
        )
    }
}

private struct AIChatAccessoryIcon: View {
    let systemName: String
    let accessibilityLabel: String
    let tint: Color
    let isEnabled: Bool
    var isProminent = false

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: isProminent ? 19 : 20, weight: .semibold))
            .foregroundStyle(foregroundStyle)
            .frame(width: 44, height: 44)
            .background(backgroundStyle, in: Circle())
            .overlay(
                Circle()
                    .stroke(tint.opacity(isEnabled ? 0.18 : 0.08), lineWidth: 1)
            )
            .contentShape(Circle())
            .accessibilityLabel(accessibilityLabel)
    }

    private var foregroundStyle: Color {
        if !isEnabled {
            return .secondary
        }
        return isProminent ? .white : tint
    }

    private var backgroundStyle: Color {
        if !isEnabled {
            return Color(.secondarySystemGroupedBackground).opacity(0.62)
        }
        return isProminent ? tint : Color(.systemBackground).opacity(0.90)
    }
}

private struct ThirdPartyMedicalAgentNoticeSheet: View {
    let accept: () -> Void

    private var responseSourceText: String {
        "设备端模型在本机运行；云端智能体只有在你主动选择并开启后才会连接外部服务。"
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        Image(systemName: "lock.shield.fill")
                            .font(.largeTitle)
                            .foregroundStyle(Color(red: 0.28, green: 0.48, blue: 0.62))
                        Text("选择智能体运行方式")
                            .font(.title2.weight(.semibold))
                        Text("模型可能出现遗漏、误解或幻觉，回答仅供参考。")
                            .foregroundStyle(.secondary)
                        Text(responseSourceText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 8)
                }

                Section("使用前确认") {
                    Label("回答仅用于风险提示、依从性提醒和说明书可读化", systemImage: "doc.text.magnifyingglass")
                    Label("设备端模型 Beta 可在 iPhone 上本地生成回答", systemImage: "iphone.gen3.radiowaves.left.and.right")
                    Label("不能替代医生或药师判断", systemImage: "person.text.rectangle")
                    Label("不会作为诊断、处方、续方、停药或调整剂量依据", systemImage: "cross.case")
                }

                Section("对话记录") {
                    Text("聊天页默认保留最近 3 轮对话，较早内容会自动进入归档历史，可在右上角查看和批量删除。")
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("开始前确认")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("我已知晓", action: accept)
                        .fontWeight(.semibold)
                }
            }
        }
    }
}

private struct AIConsentDraft {
    var sharesMedicationProfile: Bool
    var sharesMedicationPlans: Bool
    var sharesDoseEvents: Bool
    var sharesRiskCards: Bool
    var sharesDrugLabels: Bool
    var sharesImportDraft: Bool
}

private struct AIConsentSheet: View {
    @Environment(\.dismiss) private var dismiss
    let consent: StoredAIConsent?
    let save: (AIConsentDraft) -> Void
    let revoke: () -> Void
    @State private var sharesMedicationProfile: Bool
    @State private var sharesMedicationPlans: Bool
    @State private var sharesDoseEvents: Bool
    @State private var sharesRiskCards: Bool
    @State private var sharesDrugLabels: Bool
    @State private var sharesImportDraft: Bool

    init(consent: StoredAIConsent?, save: @escaping (AIConsentDraft) -> Void, revoke: @escaping () -> Void) {
        self.consent = consent
        self.save = save
        self.revoke = revoke
        _sharesMedicationProfile = State(initialValue: consent?.sharesMedicationProfile ?? true)
        _sharesMedicationPlans = State(initialValue: consent?.sharesMedicationPlans ?? true)
        _sharesDoseEvents = State(initialValue: consent?.sharesDoseEvents ?? true)
        _sharesRiskCards = State(initialValue: consent?.sharesRiskCards ?? true)
        _sharesDrugLabels = State(initialValue: consent?.sharesDrugLabels ?? true)
        _sharesImportDraft = State(initialValue: consent?.sharesImportDraft ?? false)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("共享范围") {
                    Toggle("药品名称、规格和来源", isOn: $sharesMedicationProfile)
                    Toggle("提醒计划", isOn: $sharesMedicationPlans)
                    Toggle("服药记录", isOn: $sharesDoseEvents)
                    Toggle("风险提醒", isOn: $sharesRiskCards)
                    Toggle("说明书摘要", isOn: $sharesDrugLabels)
                    Toggle("拍照或条码识别内容", isOn: $sharesImportDraft)
                }

                Section("授权说明") {
                    Text("只有勾选的数据会用于本次咨询；撤销后不会继续共享。")
                        .foregroundStyle(.secondary)
                }

                if consent?.isActive == true {
                    Section {
                        Button(role: .destructive) {
                            revoke()
                            dismiss()
                        } label: {
                            Label("撤销授权", systemImage: "xmark.shield")
                        }
                    }
                }
            }
            .navigationTitle("智能体授权")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        save(AIConsentDraft(
                            sharesMedicationProfile: sharesMedicationProfile,
                            sharesMedicationPlans: sharesMedicationPlans,
                            sharesDoseEvents: sharesDoseEvents,
                            sharesRiskCards: sharesRiskCards,
                            sharesDrugLabels: sharesDrugLabels,
                            sharesImportDraft: sharesImportDraft
                        ))
                        dismiss()
                    }
                }
            }
        }
    }
}
