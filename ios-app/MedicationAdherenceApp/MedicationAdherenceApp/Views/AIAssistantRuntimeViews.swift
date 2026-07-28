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

struct RuntimeChoiceRow: View {
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
