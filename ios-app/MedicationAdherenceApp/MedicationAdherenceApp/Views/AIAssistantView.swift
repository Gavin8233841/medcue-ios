import MedicationAdherenceCore
import PhotosUI
import SwiftData
import SwiftUI

struct AIAssistantView: View {
    @Environment(\.modelContext) private var modelContext
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
    @AppStorage("hasAcceptedMedicalAIDisclaimer") private var hasAcceptedMedicalAIDisclaimer = false
    @AppStorage("hasAcknowledgedThirdPartyMedicalAgent") private var hasAcknowledgedThirdPartyMedicalAgent = false
    @AppStorage("hasPurgedPreProviderDemoMessagesV4") private var hasPurgedPreProviderDemoMessages = false
    @AppStorage("hasPurgedUnavailableMedicalAITransportMessagesV1") private var hasPurgedUnavailableMedicalAITransportMessages = false
    @State private var draftMessage = ""
    @State private var showingConsentSheet = false
    @State private var showingThirdPartyAgentNotice = false
    @State private var showingArchivedMessages = false
    @State private var isSending = false
    @State private var isReadingImage = false
    @State private var selectedChatImageItem: PhotosPickerItem?

    private var storedConsent: StoredAIConsent? {
        consents.first { $0.id == "medical-ai-consent" }
    }

    private var activeConsent: StoredAIConsent? {
        consents.first { $0.id == "medical-ai-consent" && $0.isActive }
    }

    private var visibleMessages: [StoredAIChatMessage] {
        Array(messages.suffix(5))
    }

    private var archivedMessages: [StoredAIChatMessage] {
        let visibleIDs = Set(visibleMessages.map(\.id))
        return messages.filter { !visibleIDs.contains($0.id) }
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        AIQuickActionsSection(
                            isDisabled: isSending || !hasAcknowledgedThirdPartyMedicalAgent,
                            send: sendMessage
                        )

                        if visibleMessages.isEmpty {
                            AIEmptyConversationView()
                        } else {
                            ForEach(visibleMessages) { message in
                                AIMessageBubble(message: message)
                                    .id(message.id)
                            }
                        }

                        if isSending {
                            AIThinkingBubble()
                                .id("thinking")
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
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
                isSending: isSending,
                isReadingImage: isReadingImage,
                isEnabled: hasAcknowledgedThirdPartyMedicalAgent,
                showDisclaimer: { showingThirdPartyAgentNotice = true },
                send: { sendMessage() }
            )
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("医疗 AI")
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
            purgePreProviderDemoMessagesIfNeeded()
            purgeUnavailableMedicalAITransportMessagesIfNeeded()
            applyPendingQuestionIfNeeded()
            if !hasAcknowledgedThirdPartyMedicalAgent {
                showingThirdPartyAgentNotice = true
            } else if activeConsent == nil {
                showingConsentSheet = true
            }
        }
        .onChange(of: selectedChatImageItem) { _, newItem in
            Task {
                await prepareImageQuestion(newItem)
            }
        }
        .onChange(of: pendingMedicationAIQuestion) { _, _ in
            applyPendingQuestionIfNeeded()
        }
        .sheet(isPresented: $showingThirdPartyAgentNotice) {
            ThirdPartyMedicalAgentNoticeSheet(
                providerName: configurationStore.configuration.providerName,
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
            AIArchivedMessagesSheet(messages: archivedMessages)
        }
    }

    private func sendMessage(_ quickMessage: String? = nil) {
        guard hasAcknowledgedThirdPartyMedicalAgent else {
            showingThirdPartyAgentNotice = true
            return
        }

        let text = (quickMessage ?? draftMessage).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            return
        }
        let consent = activeConsent
        let configuration = configurationStore.configuration
        logAIEvent("prepare \(configuration.sanitizedDebugSummary) consentActive=\(consent != nil)")
        modelContext.insert(StoredAIChatMessage(
            role: .user,
            text: text,
            providerName: configuration.providerName,
            modelName: configuration.modelName,
            sharedScopesSummary: consent?.scopeSummary ?? "未授权"
        ))
        draftMessage = ""

        guard let consent else {
            modelContext.insert(StoredAIChatMessage(
                role: .assistant,
                text: "尚未获得共享授权，因此没有读取任何用药数据。请先在授权页选择共享范围。",
                providerName: configuration.providerName,
                modelName: configuration.modelName,
                sharedScopesSummary: "未授权"
            ))
            try? modelContext.save()
            showingConsentSheet = true
            return
        }

        let request = buildRequest(userMessage: text, consent: consent)
        let missingScopes = MedicalAIRequestValidator().missingRequiredScopes(for: request)
        if !missingScopes.isEmpty {
            modelContext.insert(StoredAIChatMessage(
                role: .assistant,
                text: "当前授权范围不足，未发送请求。缺少：\(missingScopes.map(scopeDisplayName).sorted().joined(separator: "、"))。",
                providerName: configuration.providerName,
                modelName: configuration.modelName,
                sharedScopesSummary: consent.scopeSummary
            ))
            try? modelContext.save()
            return
        }

        if configuration.isReadyForDirectAPI {
            guard configurationStore.apiKey()?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
                modelContext.insert(StoredAIChatMessage(
                    role: .assistant,
                    text: "医疗 AI 暂不可用，未发送任何用药数据。请稍后重试。",
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
            return
        } else if configuration.hasAPIKey {
            modelContext.insert(StoredAIChatMessage(
                role: .assistant,
                text: "医疗 AI 暂不可用，未发送任何用药数据。请稍后重试。",
                providerName: configuration.providerName,
                modelName: configuration.modelName,
                sharedScopesSummary: consent.scopeSummary
            ))
        } else {
            modelContext.insert(StoredAIChatMessage(
                role: .assistant,
                text: "医疗 AI 暂不可用，未发送任何用药数据。请稍后重试。",
                providerName: configuration.providerName,
                modelName: configuration.modelName,
                sharedScopesSummary: consent.scopeSummary
            ))
        }

        try? modelContext.save()
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
                我上传了一张药品相关图片，本机 OCR 识别文字如下：
                \(excerpt)

                请只围绕本 App 的药盒识别、药品录入、说明书可读化或复诊沟通回答。
                """
            }
        } catch {
            await MainActor.run {
                draftMessage = "我上传了一张药品相关图片，但本机 OCR 没有识别出清晰文字。请告诉我如何在 App 内手动补全药名、规格、剂型和提醒。"
            }
        }
    }

    private func sendConfirmedDirectAPIRequest(_ pendingRequest: PendingDirectAIRequest) {
        guard let apiKey = configurationStore.apiKey(), !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            logAIEvent("missing-key provider=\(pendingRequest.configuration.providerName)")
            modelContext.insert(StoredAIChatMessage(
                role: .assistant,
                text: "医疗 AI 暂不可用，未发送任何用药数据。请稍后重试。",
                providerName: pendingRequest.configuration.providerName,
                modelName: pendingRequest.configuration.modelName,
                sharedScopesSummary: pendingRequest.sharedScopesSummary
            ))
            try? modelContext.save()
            return
        }

        isSending = true
        logAIEvent("sending provider=\(pendingRequest.configuration.providerName) scopes=\(pendingRequest.sharedScopesSummary)")
        Task {
            await sendDirectAPIRequest(
                request: pendingRequest.request,
                sharedScopesSummary: pendingRequest.sharedScopesSummary,
                configuration: pendingRequest.configuration,
                apiKey: apiKey
            )
        }
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
            let response = try await medicalAIClient(configuration: configuration, apiKey: apiKey).respond(to: request)
            let displayMessage = response.message.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !displayMessage.isEmpty else {
                throw DoubaoMedicalAIError.emptyMessage
            }
            logAIEvent("success provider=\(response.provider.providerName) rawLength=\(response.message.count) displayLength=\(displayMessage.count)")
            modelContext.insert(StoredAIChatMessage(
                role: .assistant,
                text: displayMessage,
                providerName: response.provider.providerName,
                modelName: response.provider.modelName,
                sharedScopesSummary: sharedScopesSummary
            ))
        } catch {
            let message = classifyAITransportError(error)
            logAIEvent("error provider=\(configuration.providerName) type=\(String(describing: Swift.type(of: error)))")
            modelContext.insert(StoredAIChatMessage(
                role: .assistant,
                text: message,
                providerName: configuration.providerName,
                modelName: configuration.modelName,
                sharedScopesSummary: sharedScopesSummary
            ))
        }
        try? modelContext.save()
    }

    private func classifyAITransportError(_ error: Error) -> String {
        if let error = error as? BaichuanMedicalAIError, let description = error.errorDescription {
            return description
        }
        if let error = error as? DoubaoMedicalAIError, let description = error.errorDescription {
            return description
        }
        let fallback = "医疗 AI 暂时没有返回结果，请稍后重试。未记录原始响应。"
        return fallback
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

    private func purgeUnavailableMedicalAITransportMessagesIfNeeded() {
        guard !hasPurgedUnavailableMedicalAITransportMessages else {
            return
        }

        let orderedMessages = messages.sorted { $0.createdAt < $1.createdAt }
        var messageIDsToDelete: Set<UUID> = []

        for (index, message) in orderedMessages.enumerated() {
            guard message.role == .assistant, isStaleUnavailableMedicalAIMessage(message.text) else {
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
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedText.contains("医疗 AI 暂不可用")
            || trimmedText.contains("医疗 AI 暂时没有返回结果")
            || trimmedText.contains("医疗 AI 请求失败")
            || trimmedText.contains("医疗 AI 返回内容暂时无法读取")
    }

    private func buildRequest(userMessage: String, consent: StoredAIConsent) -> MedicalAIRequest {
        let snapshots: [MedicalAIMedicationSnapshot]
        if consent.sharesMedicationProfile {
            snapshots = medications.map { medication in
                let relatedTasks = tasks.filter { $0.medicationID == medication.id }
                let relatedPlans = consent.sharesMedicationPlans
                    ? plans.filter { $0.medicationID == medication.id }.compactMap { $0.corePlan(using: relatedTasks) }
                    : []
                let relatedRiskCards = consent.sharesRiskCards
                    ? riskCards.filter { $0.medicationID == medication.id }.map(\.coreRiskCard)
                    : []
                return MedicalAIMedicationSnapshot(
                    medication: medication.coreMedication,
                    plans: relatedPlans,
                    scheduledDoses: consent.sharesDoseEvents ? relatedTasks.map(\.coreScheduledDose) : [],
                    doseEvents: consent.sharesDoseEvents ? relatedTasks.compactMap(\.coreDoseEvent) : [],
                    riskCards: relatedRiskCards,
                    labelSummary: consent.sharesDrugLabels ? readableLabelSummary(for: medication) : nil
                )
            }
        } else {
            snapshots = []
        }

        return MedicalAIRequest(
            kind: .chat,
            userMessage: userMessage,
            authorization: consent.authorization,
            medicationSnapshots: snapshots,
            localeIdentifier: Locale.current.identifier
        )
    }

    private func readableLabelSummary(for medication: StoredMedication) -> ReadableLabelSummary? {
        let label = labels.first { $0.medicationID == medication.id }?.coreLabel
            ?? DemoDrugLabels.all.first { $0.name == medicationDemoLabelLookupName(for: medication) }
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
        consent.note = "用户授权医疗 AI 助手读取选定范围的数据。"
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
            text: "医疗 AI 数据共享授权已撤销。",
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
            "风险卡片"
        case .drugLabels:
            "说明书摘要"
        case .importDraft:
            "导入草稿"
        }
    }

    private func scrollToLatest(using proxy: ScrollViewProxy) {
        withAnimation(.snappy) {
            if isSending {
                proxy.scrollTo("thinking", anchor: .bottom)
            } else if let lastMessage = visibleMessages.last {
                proxy.scrollTo(lastMessage.id, anchor: .bottom)
            }
        }
    }
}

private struct PendingDirectAIRequest: Identifiable {
    let id = UUID()
    let request: MedicalAIRequest
    let sharedScopesSummary: String
    let configuration: MedicalAIConfiguration
}

private struct AIQuickActionsSection: View {
    let isDisabled: Bool
    let send: (String?) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("快捷咨询")
                .font(.headline)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                AIQuickActionButton(
                    title: "今日复核",
                    iconName: "exclamationmark.triangle",
                    action: {
                        send("请只基于 App 内授权共享的今日提醒、风险卡片和服药记录，复核今日用药风险。")
                    }
                )
                AIQuickActionButton(
                    title: "解释说明书",
                    iconName: "doc.text.magnifyingglass",
                    action: {
                        send("请只基于 App 内授权共享的药品信息和说明书摘要，解释今天最需要注意的用药事项。")
                    }
                )
                AIQuickActionButton(
                    title: "漏服趋势",
                    iconName: "chart.xyaxis.line",
                    action: {
                        send("请只基于 App 内授权共享的服药记录，说明近期漏服或延后趋势，并给出提醒建议。")
                    }
                )
                AIQuickActionButton(
                    title: "服药记录",
                    iconName: "doc.text",
                    action: {
                        send("请只基于 App 内授权共享的药品、服药记录和风险卡片，生成一段适合复诊沟通的简短服药记录。")
                    }
                )
                AIQuickActionButton(
                    title: "天气影响",
                    iconName: "cloud.sun",
                    action: {
                        send("请结合今日天气条件和 App 内授权共享的服药记录，提示可能需要留意的环境与用药相关事项。")
                    }
                )
                AIQuickActionButton(
                    title: "图片说明",
                    iconName: "photo.on.rectangle",
                    action: {
                        send("我准备上传药盒、药品或说明书图片。请只回答如何在本 App 内识别、录入、核对或整理这些信息。")
                    }
                )
            }
        }
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.55 : 1)
    }
}

private struct AIQuickActionButton: View {
    let title: String
    let iconName: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: iconName)
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(.background, in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }
}

private struct AIEmptyConversationView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("开始一次用药咨询", systemImage: "bubble.left.and.bubble.right")
                .font(.headline)
            Text("可询问说明书、今日复核和漏服趋势。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background, in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct AIMessageBubble: View {
    let message: StoredAIChatMessage

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

                Text(message.text)
                    .font(.body)
                    .foregroundStyle(message.role == .user ? .white : .primary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(bubbleBackground, in: RoundedRectangle(cornerRadius: 8))
                    .textSelection(.enabled)
            }

            if message.role != .user {
                Spacer(minLength: 42)
            }
        }
        .frame(maxWidth: .infinity, alignment: message.role == .user ? .trailing : .leading)
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
        return providerName.isEmpty ? "医疗 AI" : providerName
    }
    return message.role.displayName
}

private struct AIThinkingBubble: View {
    var body: some View {
        HStack {
            HStack(spacing: 10) {
                ProgressView()
                Text("正在请求医疗 AI")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8))
            Spacer(minLength: 42)
        }
    }
}

private struct AIArchivedMessagesSheet: View {
    @Environment(\.dismiss) private var dismiss
    let messages: [StoredAIChatMessage]

    var body: some View {
        NavigationStack {
            List {
                if messages.isEmpty {
                    ContentUnavailableView("暂无归档", systemImage: "archivebox")
                } else {
                    Section("归档历史") {
                        ForEach(messages) { message in
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text(messageDisplayName(for: message))
                                        .font(.subheadline.weight(.semibold))
                                    Spacer()
                                    Text(AppFormatters.time.string(from: message.createdAt))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Text(message.text)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(4)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
            }
            .navigationTitle("归档历史")
            .toolbar {
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
    let isSending: Bool
    let isReadingImage: Bool
    let isEnabled: Bool
    let showDisclaimer: () -> Void
    let send: () -> Void

    var body: some View {
        HStack(alignment: .bottom, spacing: 10) {
            PhotosPicker(selection: $selectedImageItem, matching: .images) {
                Image(systemName: isReadingImage ? "hourglass" : "photo.badge.plus")
                    .font(.title3)
                    .accessibilityLabel("发送图片")
            }
            .disabled(!isEnabled || isSending || isReadingImage)

            TextField(isEnabled ? "询问用药记录、风险提示或说明书摘要" : "确认免责说明后开启咨询", text: $text, axis: .vertical)
                .lineLimit(1...5)
                .textInputAutocapitalization(.never)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8))
                .disabled(!isEnabled || isSending)

            Button {
                isEnabled ? send() : showDisclaimer()
            } label: {
                Image(systemName: isSending ? "hourglass" : "arrow.up.circle.fill")
                    .font(.title2)
                    .accessibilityLabel(isEnabled ? "发送" : "查看免责说明")
            }
            .disabled(isSending || isReadingImage || (isEnabled && text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
    }
}

private struct ThirdPartyMedicalAgentNoticeSheet: View {
    let providerName: String
    let accept: () -> Void

    private var poweredByText: String {
        let trimmedProviderName = providerName.trimmingCharacters(in: .whitespacesAndNewlines)
        return "Powered by \(trimmedProviderName.isEmpty ? "医疗智能体" : trimmedProviderName)"
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        Image(systemName: "stethoscope.circle.fill")
                            .font(.largeTitle)
                            .foregroundStyle(.blue)
                        Text("你正在使用第三方医疗智能体")
                            .font(.title2.weight(.semibold))
                        Text("它可能会出错，回答仅供参考。")
                            .foregroundStyle(.secondary)
                        Text(poweredByText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 8)
                }

                Section("使用前确认") {
                    Label("回答仅用于风险提示、依从性提醒和说明书可读化", systemImage: "doc.text.magnifyingglass")
                    Label("不能替代医生或药师判断", systemImage: "person.text.rectangle")
                    Label("不会作为诊断、处方、续方、停药或调整剂量依据", systemImage: "cross.case")
                }

                Section("对话记录") {
                    Text("聊天页仅展示最近 5 条对话，较早内容会自动进入归档历史，可在右上角查看。")
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
                    Toggle("风险卡片", isOn: $sharesRiskCards)
                    Toggle("说明书摘要", isOn: $sharesDrugLabels)
                    Toggle("OCR 或条码导入草稿", isOn: $sharesImportDraft)
                }

                Section("授权说明") {
                    Text("只有勾选的数据会进入医疗 AI 请求快照；撤销后不会继续共享。模型返回内容只作为风险提示和可读化说明，不能替代医生或药师判断。")
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
            .navigationTitle("AI 授权")
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
