import MedicationAdherenceCore
import PhotosUI
import SwiftUI
import UIKit

struct AIAssistantScreen: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .body) private var auxiliaryMinimum: CGFloat = AssistantReadingLayout.auxiliaryMinimum
    @ScaledMetric(relativeTo: .body) private var conversationMinimum: CGFloat = AssistantReadingLayout.conversationMinimum
    @Environment(\.activeAppTab) private var activeAppTab
    @Environment(\.pendingMedicationAIQuestion) private var pendingMedicationAIQuestion
    let configuration: MedicalAIConfiguration
    let onlineReadiness: MedicalAITransportReadiness
    let localModelStatus: LocalMedicalModelStatus
    let visibleMessages: [StoredAIChatMessage]
    let archivedMessages: [StoredAIChatMessage]
    let localStreamingResponse: LocalStreamingAIResponse?
    let isSending: Bool
    let isReadingImage: Bool
    let isInputEnabled: Bool
    let prefersLocalResponses: Bool
    let hasUserSelectedRuntime: Bool
    @Binding var draftMessage: String
    @Binding var selectedImageItem: PhotosPickerItem?
    var isChatInputFocused: FocusState<Bool>.Binding
    @Binding var showingThirdPartyAgentNotice: Bool
    @Binding var showingConsentSheet: Bool
    @Binding var showingArchivedMessages: Bool
    @Binding var showingRuntimePicker: Bool
    @Binding var showingLocalModelDownloadConfirmation: Bool
    let storedConsent: StoredAIConsent?
    let sendMessage: (AIOutgoingMessage?) -> Void
    let selectOnlineRuntime: () -> Void
    let selectLocalRuntime: () -> Void
    let archiveVisibleConversation: (StoredAIChatMessage) -> Void
    let dismissChatKeyboard: () -> Void
    let prepareSession: () -> Void
    let handleActiveTabChange: (AppTab?) -> Void
    let beginImageRecognition: (PhotosPickerItem?) -> Void
    let capturedImage: (UIImage) -> Void
    @State private var isReadingHistory = false
    @State private var isDraggingConversation = false
    let applyPendingQuestion: () -> Void
    let refreshEnvironment: () async -> Void
    let acceptThirdPartyNotice: () -> Void
    let saveConsent: (AIConsentDraft) -> Void
    let revokeConsent: () -> Void
    let deleteArchivedMessages: ([StoredAIChatMessage]) -> Void
    let deleteAllArchivedMessages: () -> Void
    let requestLocalModelDownload: () -> Void
    let environmentRefreshSignature: String

    var body: some View {
        GeometryReader { geometry in
            let layout = AssistantReadingLayout.resolve(
                width: geometry.size.width, regular: horizontalSizeClass == .regular,
                accessibility: dynamicTypeSize.isAccessibilitySize,
                auxiliaryMinimum: auxiliaryMinimum, conversationMinimum: conversationMinimum
            )
            HStack(alignment: .top, spacing: AssistantReadingLayout.gap) {
                if layout.showsAuxiliary {
                    ScrollView {
                        taskControls(usesVerticalLayout: true).padding(16)
                    }
                    .frame(width: layout.auxiliaryWidth)
                    .frame(maxHeight: .infinity)
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20))
                    .accessibilityIdentifier("assistant.reading.tools")
                }
                chatPane(showsInlineControls: !layout.showsAuxiliary)
                    .frame(width: layout.conversationWidth)
                    .accessibilityIdentifier("assistant.reading.chat")
            }
            .padding(.horizontal, layout.outerInset)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityIdentifier("assistant.reading.viewport")
        }
        .animation(.easeInOut(duration: 0.22), value: isReadingHistory)
        .background(Color(.systemBackground))
        .navigationTitle("医疗智能体")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(isChatInputFocused.wrappedValue ? .hidden : .automatic, for: .tabBar)
        .toolbar {
            ToolbarItem(placement: .principal) {
                VStack(spacing: 2) {
                    Text("医疗智能体").font(.headline)
                    Text("AI 可能出错，重要用药决定请咨询医生或药师")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                }
                .accessibilityElement(children: .combine)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingArchivedMessages = true
                } label: {
                    Image(systemName: "clock.arrow.circlepath")
                        .accessibilityLabel("归档历史")
                }
                .disabled(archivedMessages.isEmpty)
                .accessibilityIdentifier(AppAccessibilityID.assistantArchive)
            }
        }
        .task {
            // Yield before legacy-message maintenance; device timing is measured separately.
            await Task.yield()
            guard !Task.isCancelled else { return }
            prepareSession()
        }
        .onChange(of: activeAppTab) { _, newTab in
            handleActiveTabChange(newTab)
        }
        .onChange(of: draftMessage) { _, newValue in
            if !newValue.isEmpty { isReadingHistory = false }
        }
        .onChange(of: selectedImageItem) { _, newItem in
            beginImageRecognition(newItem)
        }
        .onChange(of: pendingMedicationAIQuestion) { _, _ in
            applyPendingQuestion()
        }
        .task(id: environmentRefreshSignature) {
            do { try await Task.sleep(for: .milliseconds(300)) } catch { return }
            await refreshEnvironment()
        }
        .sheet(isPresented: $showingThirdPartyAgentNotice) {
            ThirdPartyMedicalAgentNoticeSheet(accept: acceptThirdPartyNotice)
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
            Button("开始下载约 \(LocalMedicalModelStore.manifest.estimatedSizeMB)MB 模型", action: requestLocalModelDownload)
            Button("取消", role: .cancel) {}
        } message: {
            Text("离线端侧模型为 Beta 版本，会在本机运行，不上传用药记录。下载完成后可在智能体页切换使用。")
        }
    }

    private func chatPane(showsInlineControls: Bool) -> some View {
        conversation(showsInlineControls: showsInlineControls)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !isReadingHistory {
            AIChatInputBar(
                text: $draftMessage,
                selectedImageItem: $selectedImageItem,
                isFocused: isChatInputFocused,
                isSending: isSending,
                isReadingImage: isReadingImage,
                isEnabled: isInputEnabled,
                showDisclaimer: { showingThirdPartyAgentNotice = true },
                send: { sendMessage(nil) },
                capturedImage: capturedImage
            )
            .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }

    private func taskControls(usesVerticalLayout: Bool) -> some View {
        VStack(alignment: .leading, spacing: 20) {
                    AgentRuntimeSelectorBar(
                        onlineConfiguration: configuration,
                        onlineReadiness: onlineReadiness,
                        status: localModelStatus,
                        prefersLocalResponses: prefersLocalResponses,
                        hasUserSelectedRuntime: hasUserSelectedRuntime,
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
                        isDisabled: isSending || !isInputEnabled,
                        prefersLocalResponses: prefersLocalResponses,
                        send: sendMessage,
                        usesVerticalLayout: usesVerticalLayout
                    )
        }
        .accessibilityIdentifier("assistant.task-controls")
    }

    private func conversation(showsInlineControls: Bool) -> some View {
        ScrollViewReader { proxy in
            GeometryReader { viewport in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 24) {
                    if showsInlineControls {
                        taskControls(usesVerticalLayout: false)
                    }

                    if visibleMessages.isEmpty {
                        AIEmptyConversationView()
                    } else {
                        ForEach(visibleMessages) { message in
                            AIMessageBubble(
                                message: message,
                                archive: { archiveVisibleConversation(message) },
                                quote: { text in
                                    draftMessage = text + draftMessage
                                    isReadingHistory = false
                                    isChatInputFocused.wrappedValue = true
                                }
                            )
                            .id(message.id)
                        }
                    }

                    if let localStreamingResponse {
                        LocalStreamingResponseView(response: localStreamingResponse)
                            .id("local-streaming-response")
                    } else if isSending {
                        AIThinkingBubble(isLocalRuntime: prefersLocalResponses)
                            .id("thinking")
                    }
                    Color.clear
                        .frame(height: 1)
                        .id("conversation-bottom")
                        .background {
                            GeometryReader { anchor in
                                Color.clear.preference(
                                    key: AIConversationBottomKey.self,
                                    value: anchor.frame(in: .named("AIAssistantTopGradientScroll")).maxY
                                )
                            }
                        }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .background(alignment: .top) {
                    AppTopGradientScrollReader(
                        tab: .assistant,
                        coordinateSpaceName: "AIAssistantTopGradientScroll"
                    )
                }
            }
            .coordinateSpace(name: "AIAssistantTopGradientScroll")
            .accessibilityIdentifier("assistant.conversation")
            .scrollDismissesKeyboard(.interactively)
            .contentShape(Rectangle())
            .modifier(AIConversationScrollActivity(
                isScrolling: $isDraggingConversation,
                dismissKeyboard: dismissChatKeyboard,
                distanceChanged: updateDistanceToBottom
            ))
            .onPreferenceChange(AIConversationBottomKey.self) { bottom in
                if #unavailable(iOS 18.0) {
                    updateDistanceToBottom(bottom - viewport.size.height)
                }
            }
            .simultaneousGesture(TapGesture().onEnded {
                dismissChatKeyboard()
            })
            .onAppear { scrollToLatest(using: proxy, animated: false) }
            .onChange(of: visibleMessages.last?.id) { _, _ in
                if !isReadingHistory || visibleMessages.last?.role == .user {
                    isReadingHistory = false
                    scrollToLatest(using: proxy)
                }
            }
            .onChange(of: isSending) { _, sending in
                if sending || !isReadingHistory {
                    if sending { isReadingHistory = false }
                    scrollToLatest(using: proxy)
                }
            }
            .onChange(of: isReadingHistory) { wasReading, reading in
                if wasReading && !reading { scrollToLatest(using: proxy) }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardDidShowNotification)) { _ in
                if isChatInputFocused.wrappedValue { scrollToLatest(using: proxy) }
            }
            }

        }
    }

    private func updateDistanceToBottom(_ distance: CGFloat) {
        if distance <= 24 {
            isReadingHistory = false
        } else if isDraggingConversation && distance > 160 && !visibleMessages.isEmpty {
            isReadingHistory = true
        }
    }

    private func scrollToLatest(using proxy: ScrollViewProxy, animated: Bool = true) {
        withAnimation(animated ? .easeOut(duration: 0.22) : nil) {
            proxy.scrollTo("conversation-bottom", anchor: .bottom)
        }
    }
}

private struct AIConversationScrollActivity: ViewModifier {
    @Binding var isScrolling: Bool
    let dismissKeyboard: () -> Void
    let distanceChanged: (CGFloat) -> Void

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content
                .onScrollPhaseChange { _, phase in
                    isScrolling = phase == .tracking || phase == .interacting || phase == .decelerating
                    if phase == .interacting { dismissKeyboard() }
                }
                .onScrollGeometryChange(for: CGFloat.self) { geometry in
                    max(0, geometry.contentSize.height - geometry.visibleRect.maxY)
                } action: { _, distance in
                    distanceChanged(distance)
                }
        } else {
            content.simultaneousGesture(
                DragGesture(minimumDistance: 12).onChanged { value in
                    guard abs(value.translation.height) > abs(value.translation.width) else { return }
                    if !isScrolling { dismissKeyboard() }
                    isScrolling = true
                }.onEnded { _ in isScrolling = false }
            )
        }
    }
}

private struct AIConversationBottomKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

#if DEBUG
// Explicit, memory-only UI fixture: no inference, network, ordinary DB or seeded
// health data. Never used by the normal chat path or as an answer fallback.
struct AssistantUIFixture: View {
    private var isWaitingPreview: Bool { ProcessInfo.processInfo.arguments.contains("--assistant-waiting-preview") }
    @State private var draft = ""
    @State private var image: PhotosPickerItem?
    @FocusState private var focused: Bool
    @State private var notice = false
    @State private var consent = false
    @State private var archive = false
    @State private var runtime = false
    @State private var download = false
    @State private var messages: [StoredAIChatMessage] = (0..<6).flatMap { index in
        [StoredAIChatMessage(role: .user, text: "界面测试第 \(index + 1) 问：如何整理日常记录？"),
         StoredAIChatMessage(role: .assistant, text: index == 5 ? "## 合成记录示例\n\n| 药品 | 已记录服用 |\n| --- | --- |\n| ibuprofen | 1 次 |\n| loratadine | 0 次 |\n\n- **仅用于界面验证**，不是真实健康数据。" : "这是一段仅用于界面验证的合成文本。可以按日期整理记录，保留时间与备注，方便回看。\n\n" + String(repeating: "长消息用于检查滚动、键盘避让和文字选择。", count: 4), providerName: "离线智能体")]
    }

    var body: some View {
        TabView {
            NavigationStack {
                AIAssistantScreen(
                    configuration: MedicalAIConfiguration(providerName: "UI 验证", modelName: "未连接模型", endpointURLString: "", hasAPIKey: false),
                    onlineReadiness: MedicalAITransportReadiness(canSend: false, diagnosticSummary: "ui-fixture"),
                    localModelStatus: LocalMedicalModelStatus(availability: .notDownloaded, displayName: "UI 验证", detailText: "合成文字，不运行模型", canUseForResponses: false),
                    visibleMessages: isWaitingPreview ? Array(messages.suffix(2)) : messages, archivedMessages: [],
                    localStreamingResponse: isWaitingPreview ? LocalStreamingAIResponse(statusText: "正在准备本机回答") : nil,
                    isSending: isWaitingPreview, isReadingImage: false, isInputEnabled: true,
                    prefersLocalResponses: true, hasUserSelectedRuntime: true,
                    draftMessage: $draft, selectedImageItem: $image, isChatInputFocused: $focused,
                    showingThirdPartyAgentNotice: $notice, showingConsentSheet: $consent,
                    showingArchivedMessages: $archive, showingRuntimePicker: $runtime,
                    showingLocalModelDownloadConfirmation: $download, storedConsent: nil,
                    sendMessage: { _ in
                        guard !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                        messages.append(StoredAIChatMessage(role: .user, text: draft))
                        draft = ""
                        focused = false
                    },
                    selectOnlineRuntime: {}, selectLocalRuntime: {}, archiveVisibleConversation: { _ in },
                    dismissChatKeyboard: { focused = false }, prepareSession: {}, handleActiveTabChange: { _ in },
                    beginImageRecognition: { _ in }, capturedImage: { _ in }, applyPendingQuestion: {},
                    refreshEnvironment: {}, acceptThirdPartyNotice: {}, saveConsent: { _ in }, revokeConsent: {},
                    deleteArchivedMessages: { _ in }, deleteAllArchivedMessages: {}, requestLocalModelDownload: {},
                    environmentRefreshSignature: "fixture"
                )
            }
            .tabItem { Label("UI 验证", systemImage: "bubble.left") }
            Text("隔离界面验证").tabItem { Label("其他", systemImage: "square") }
        }
    }
}
#endif

enum AssistantReadingLayout {
    static let auxiliaryMinimum: CGFloat = 300
    static let conversationMinimum: CGFloat = 480
    static let readingMaximum: CGFloat = 680
    static let gap: CGFloat = 24
    static let outerInset: CGFloat = 16

    struct Plan {
        let conversationWidth: CGFloat
        let auxiliaryWidth: CGFloat
        let outerInset: CGFloat
        var showsAuxiliary: Bool { auxiliaryWidth > 0 }
    }

    static func resolve(
        width: CGFloat, regular: Bool, accessibility: Bool,
        auxiliaryMinimum: CGFloat, conversationMinimum: CGFloat
    ) -> Plan {
        guard width.isFinite, width > 0,
              auxiliaryMinimum.isFinite, auxiliaryMinimum > 0,
              conversationMinimum.isFinite, conversationMinimum > 0 else {
            return Plan(conversationWidth: width.isFinite ? max(0, width) : 0,
                        auxiliaryWidth: 0, outerInset: 0)
        }
        let tools = max(Self.auxiliaryMinimum, auxiliaryMinimum)
        let conversation = max(Self.conversationMinimum, conversationMinimum)
        let maximum = max(readingMaximum, conversation)
        let showsAuxiliary = regular && !accessibility
            && width >= tools + conversation + gap + 2 * outerInset
        let available = showsAuxiliary ? width - tools - gap - 2 * outerInset : width
        return Plan(
            conversationWidth: accessibility ? width : min(available, maximum),
            auxiliaryWidth: showsAuxiliary ? tools : 0,
            outerInset: showsAuxiliary ? outerInset : 0
        )
    }
}
