import MedicationAdherenceCore
import PhotosUI
import SwiftData
import SwiftUI
import UIKit

struct AIChatInputBar: View {
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
        AIAssistantPalette.accent
    }

    private var isExpanded: Bool {
        isFocused.wrappedValue || !text.isEmpty || !isEnabled
    }

    var body: some View {
        let inputTint = accentTint

        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 8) {
                if !isExpanded {
                    imagePicker(tint: inputTint)
                }

                // Keep one TextField at the same place in the tree as the composer grows.
                TextField(isEnabled ? "询问用药记录、风险提示或说明书摘要" : "确认使用说明后开启咨询", text: $text, axis: .vertical)
                    .lineLimit(1...5)
                    .textInputAutocapitalization(.never)
                    .focused(isFocused)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .frame(minHeight: 44)
                    .disabled(!isEnabled || isSending)
                    .accessibilityIdentifier(AppAccessibilityID.assistantInput)
                    .toolbar {
                        ToolbarItemGroup(placement: .keyboard) {
                            Spacer()
                            Button("收起") {
                                dismissKeyboard()
                            }
                            .disabled(!isFocused.wrappedValue)
                        }
                    }

                if !isExpanded {
                    sendButton(tint: inputTint)
                }
            }
            .padding(.horizontal, 6)
            .frame(minHeight: 56)

            if isExpanded {
                HStack(spacing: 10) {
                    imagePicker(tint: inputTint)

                    Text(isEnabled ? "原图本机识别；文字填入输入框，云端发送时会随提问提交" : "请先查看使用说明")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Spacer(minLength: 4)
                    sendButton(tint: inputTint)
                }
                .padding(.leading, 6)
                .padding(.trailing, 6)
                .padding(.bottom, 5)
            }
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: isExpanded ? 22 : 28, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: isExpanded ? 22 : 28, style: .continuous)
                .stroke(accentTint.opacity(isFocused.wrappedValue ? 0.30 : 0.14), lineWidth: 1)
        )
        .shadow(color: accentTint.opacity(0.09), radius: 12, x: 0, y: 5)
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 10)
        .animation(.easeOut(duration: 0.18), value: isExpanded)
    }

    private func imagePicker(tint: Color) -> some View {
        PhotosPicker(selection: $selectedImageItem, matching: .images) {
            AIChatAccessoryIcon(
                systemName: isReadingImage ? "hourglass" : "photo.badge.plus",
                accessibilityLabel: "识别药品图片文字",
                tint: tint,
                isEnabled: isEnabled && !isSending && !isReadingImage
            )
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled || isSending || isReadingImage)
        .accessibilityHint("原图仅在本机识别。识别文字会填入输入框；选择云端并发送时，文字会作为提问内容提交")
    }

    private func sendButton(tint: Color) -> some View {
        Button {
            isEnabled ? send() : showDisclaimer()
        } label: {
            AIChatAccessoryIcon(
                systemName: isSending ? "hourglass" : "arrow.up",
                accessibilityLabel: isEnabled ? "发送" : "查看使用说明",
                tint: tint,
                isEnabled: isEnabled ? canSend : true,
                isProminent: true
            )
        }
        .buttonStyle(.plain)
        .disabled(isSending || isReadingImage || (isEnabled && trimmedText.isEmpty))
        .accessibilityIdentifier(AppAccessibilityID.assistantSend)
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

struct AIChatAccessoryIcon: View {
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

struct ThirdPartyMedicalAgentNoticeSheet: View {
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
                        .accessibilityIdentifier("assistant.thirdPartyNotice.accept")
                }
            }
        }
    }
}

struct AIConsentSheet: View {
    @Environment(\.dismiss) private var dismiss
    let consent: StoredAIConsent?
    let save: (AIConsentDraft) -> Void
    let revoke: () -> Void
    @State private var sharesMedicationProfile: Bool
    @State private var sharesMedicationPlans: Bool
    @State private var sharesDoseEvents: Bool
    @State private var sharesRiskCards: Bool
    @State private var sharesDrugLabels: Bool

    init(consent: StoredAIConsent?, save: @escaping (AIConsentDraft) -> Void, revoke: @escaping () -> Void) {
        self.consent = consent
        self.save = save
        self.revoke = revoke
        _sharesMedicationProfile = State(initialValue: consent?.sharesMedicationProfile ?? true)
        _sharesMedicationPlans = State(initialValue: consent?.sharesMedicationPlans ?? true)
        _sharesDoseEvents = State(initialValue: consent?.sharesDoseEvents ?? true)
        _sharesRiskCards = State(initialValue: consent?.sharesRiskCards ?? true)
        _sharesDrugLabels = State(initialValue: consent?.sharesDrugLabels ?? true)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("自动附加的 App 资料") {
                    Toggle("药品名称、规格和来源", isOn: $sharesMedicationProfile)
                    Toggle("提醒计划", isOn: $sharesMedicationPlans)
                    Toggle("服药记录", isOn: $sharesDoseEvents)
                    Toggle("风险提醒", isOn: $sharesRiskCards)
                    Toggle("说明书摘要", isOn: $sharesDrugLabels)
                }

                Section("授权说明") {
                    Text("勾选项只控制自动附加的 App 资料。你编辑并发送的提问文字，包括从图片识别后填入的文字，会提交给所选运行方式；关闭上方选项不会过滤提问文字。撤销后不会继续自动共享 App 资料。")
                        .foregroundStyle(.secondary)
                    if consent?.isActive == true && consent?.sharesImportDraft == true {
                        Text("此前开启的导入识别草稿授权仍保留；当前聊天不会自动附加该草稿。")
                            .foregroundStyle(.secondary)
                    }
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
                    .accessibilityIdentifier("assistant.consent.cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        save(AIConsentDraft(
                            sharesMedicationProfile: sharesMedicationProfile,
                            sharesMedicationPlans: sharesMedicationPlans,
                            sharesDoseEvents: sharesDoseEvents,
                            sharesRiskCards: sharesRiskCards,
                            sharesDrugLabels: sharesDrugLabels,
                            sharesImportDraft: consent?.isActive == true && consent?.sharesImportDraft == true
                        ))
                        dismiss()
                    }
                }
            }
        }
    }
}
