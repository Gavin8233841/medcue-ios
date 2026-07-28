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
