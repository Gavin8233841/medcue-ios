import MedicationAdherenceCore
import PhotosUI
import SwiftData
import SwiftUI
import UIKit

struct PendingDirectAIRequest: Identifiable {
    let id = UUID()
    let request: MedicalAIRequest
    let sharedScopesSummary: String
    let configuration: MedicalAIConfiguration
}

struct PendingLocalAIRequest: Identifiable {
    let id = UUID()
    let request: MedicalAIRequest
    let sharedScopesSummary: String
    let modelURL: URL
}

struct LocalStreamingAIResponse {
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

struct AIOutgoingMessage {
    let displayText: String
    let requestText: String
}

func medicalAIScopeDisplayName(_ scope: MedicalAIDataScope) -> String {
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

struct AgentRuntimeSelectorBar: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    private var isAccessibilitySize: Bool { dynamicTypeSize.isAccessibilitySize }

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
            return status.canUseForResponses ? "使用离线模型" : "暂不可用"
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

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button(action: toggleExpanded) {
                HStack(spacing: 8) {
                    Image(systemName: prefersLocalResponses ? "sparkles" : "cloud")
                        .foregroundStyle(AIAssistantPalette.accent)
                    Text(prefersLocalResponses ? "本机模型" : "云端模型")
                        .foregroundStyle(.primary)
                    Image(systemName: "chevron.down")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                }
                .font(.subheadline.weight(.medium))
                .padding(.horizontal, 16)
                .frame(minHeight: 44)
                .modifier(RuntimeGlassCapsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("切换智能体模式")
            .accessibilityIdentifier("assistant.runtime.toggle")

            if isExpanded {
                VStack(spacing: 6) {
                    RuntimeChoiceRow(
                        title: "云端模型",
                        subtitle: "联网回答 · 授权后使用",
                        status: onlineStatusText,
                        progress: nil,
                        progressText: nil,
                        iconName: "cloud",
                        tint: AIAssistantPalette.accent,
                        statusBackgroundTint: AIAssistantPalette.accent,
                        isSelected: !prefersLocalResponses,
                        isEnabled: true,
                        isActionAvailable: onlineReadiness.canSend,
                        actionTitle: onlineReadiness.canSend ? "选择" : "未开启",
                        action: selectOnline
                    )
                    RuntimeChoiceRow(
                        title: "本机模型",
                        subtitle: "离线回答 · 数据留在本机",
                        status: offlineStatusText,
                        progress: status.availability == .downloading ? (status.downloadProgress ?? 0.01) : nil,
                        progressText: status.availability == .downloading ? status.fileSizeText : nil,
                        iconName: "sparkles",
                        tint: AIAssistantPalette.accent,
                        statusBackgroundTint: AIAssistantPalette.accent,
                        isSelected: prefersLocalResponses,
                        isEnabled: status.canUseForResponses,
                        isActionAvailable: status.canUseForResponses || status.canStartDownload,
                        actionTitle: status.canUseForResponses ? "选择" : offlineButtonTitle,
                        action: {
                            if status.canUseForResponses { selectLocal() }
                            else if status.canStartDownload { requestLocalDownload() }
                        }
                    )
                }
                .padding(8)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.horizontal, 2)
    }
}

private struct RuntimeGlassCapsule: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.glassEffect(.regular.interactive(), in: .capsule)
        } else {
            content.background(.regularMaterial, in: Capsule())
        }
    }
}

struct RuntimeChoiceRow: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    private var isAccessibilitySize: Bool { dynamicTypeSize.isAccessibilitySize }

    let title: String
    let subtitle: String
    let status: String
    let progress: Double?
    let progressText: String?
    let iconName: String
    let tint: Color
    let statusBackgroundTint: Color
    let isSelected: Bool
    let isEnabled: Bool
    let isActionAvailable: Bool
    let actionTitle: String
    let action: () -> Void

    var body: some View {
        (isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12)) : AnyLayout(HStackLayout(spacing: 12))) {
            Image(systemName: iconName)
                .font(.system(size: 21, weight: .medium))
                .foregroundStyle(tint)
                .frame(width: 42, height: 42)
                .background(tint.opacity(0.09), in: RoundedRectangle(cornerRadius: 14))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if !isEnabled || progress != nil {
                    Text(status)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                }
                if let progress {
                    ProgressView(value: progress).tint(tint)
                    if let progressText {
                        Text(progressText)
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
            if !isAccessibilitySize { Spacer(minLength: 0) }
            Button(action: action) {
                Group {
                    if isSelected && isActionAvailable {
                        Image(systemName: "checkmark")
                            .font(.subheadline.weight(.semibold))
                    } else {
                        Text(actionTitle).font(.caption.weight(.semibold))
                    }
                }
                .foregroundStyle(isSelected ? tint : Color.primary)
                .padding(.horizontal, 14)
                .frame(minWidth: 44, minHeight: 44)
                .background(isSelected ? tint.opacity(0.10) : Color.primary.opacity(0.045), in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(!isActionAvailable)
            .accessibilityLabel(isSelected ? "已选择\(title)" : "\(actionTitle)\(title)")
        }
        .padding(12)
        .background(isSelected ? tint.opacity(0.055) : Color.clear, in: RoundedRectangle(cornerRadius: 20))
    }
}

struct FlowBadges: View {
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

struct LocalMedicalModelStatusView: View {
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
