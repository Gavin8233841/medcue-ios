import MedicationAdherenceCore
import PhotosUI
import SwiftData
import SwiftUI
import UIKit

struct AIConversationVisibilityProjection {
    let messages: [StoredAIChatMessage]
    let manuallyArchivedMessageIDs: Set<UUID>

    var visibleMessages: [StoredAIChatMessage] {
        let orderedMessages = messages
            .filter { !manuallyArchivedMessageIDs.contains($0.id) }
            .sorted { $0.createdAt < $1.createdAt }
        guard let startIndex = Self.visibleConversationStartIndex(in: orderedMessages) else {
            return orderedMessages
        }
        return Array(orderedMessages[startIndex...])
    }

    var archivedMessages: [StoredAIChatMessage] {
        let visibleIDs = Set(visibleMessages.map(\.id))
        return messages
            .filter { !visibleIDs.contains($0.id) }
            .sorted { $0.createdAt < $1.createdAt }
    }

    static func visibleConversationStartIndex(
        in orderedMessages: [StoredAIChatMessage]
    ) -> Int? {
        let userMessageIndexes = orderedMessages.indices.filter {
            orderedMessages[$0].role == .user
        }
        guard userMessageIndexes.count > 3 else {
            return orderedMessages.isEmpty ? nil : orderedMessages.startIndex
        }
        return userMessageIndexes[userMessageIndexes.count - 3]
    }
}

struct AIQuickActionsSection: View {
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

struct AIQuickAction: Identifiable {
    let title: String
    let subtitle: String
    let iconName: String
    let tint: Color
    let displayText: String
    let requestText: String

    var id: String { title }
}

struct AIQuickActionChip: View {
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

struct AIQuickActionButton: View {
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

struct AIEmptyConversationView: View {
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

struct LocalStreamingResponseView: View {
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

struct AIMessageBubble: View {
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

func normalizedLegacyMedicalAIStatusText(_ text: String) -> String? {
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

struct LocalModelReasoningDisclosure: View {
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

struct AIThinkingBubble: View {
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

struct AIArchivedMessagesSheet: View {
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
