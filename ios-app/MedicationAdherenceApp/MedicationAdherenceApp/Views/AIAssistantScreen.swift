import MedicationAdherenceCore
import PhotosUI
import SwiftUI
import UIKit

struct AIAssistantScreen: View {
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
        VStack(spacing: 0) {
            conversation
            Divider()
            AIChatInputBar(
                text: $draftMessage,
                selectedImageItem: $selectedImageItem,
                isFocused: isChatInputFocused,
                isSending: isSending,
                isReadingImage: isReadingImage,
                isEnabled: isInputEnabled,
                showDisclaimer: { showingThirdPartyAgentNotice = true },
                send: { sendMessage(nil) }
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
                .accessibilityIdentifier(AppAccessibilityID.assistantArchive)
            }
        }
        .onAppear(perform: prepareSession)
        .onChange(of: activeAppTab) { _, newTab in
            handleActiveTabChange(newTab)
        }
        .onChange(of: selectedImageItem) { _, newItem in
            beginImageRecognition(newItem)
        }
        .onChange(of: pendingMedicationAIQuestion) { _, _ in
            applyPendingQuestion()
        }
        .task(id: environmentRefreshSignature) {
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
            Button("开始下载约 265MB 模型", action: requestLocalModelDownload)
            Button("取消", role: .cancel) {}
        } message: {
            Text("离线端侧模型为 Beta 版本，会在本机运行，不上传用药记录。下载完成后可在智能体页切换使用。")
        }
    }

    private var conversation: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
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
                        send: sendMessage
                    )

                    if visibleMessages.isEmpty {
                        AIEmptyConversationView()
                    } else {
                        ForEach(visibleMessages) { message in
                            AIMessageBubble(
                                message: message,
                                archive: { archiveVisibleConversation(message) }
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
                }
                .padding(.horizontal, 16)
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
            .scrollDismissesKeyboard(.interactively)
            .contentShape(Rectangle())
            .simultaneousGesture(TapGesture().onEnded {
                dismissChatKeyboard()
            })
            .onChange(of: visibleMessages.count) { _, _ in
                scrollToLatest(using: proxy)
            }
            .onChange(of: isSending) { _, _ in
                scrollToLatest(using: proxy)
            }
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
