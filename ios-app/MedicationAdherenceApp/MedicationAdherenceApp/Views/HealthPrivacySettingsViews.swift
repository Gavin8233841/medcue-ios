import AuthenticationServices
import MedicationAdherenceCore
import OSLog
import QuickLook
import SwiftData
import SwiftUI
import UIKit

struct HealthDataSettingsView: View {
    @StateObject private var healthKitService = HealthKitService()
    @State private var pendingPermissionGate: AppPermissionGate?

    private var summary: HealthKitRecentSummary {
        healthKitService.recentSummary
    }

    var body: some View {
        List {
            Section {
                SettingsStatusRow(
                    iconName: "heart.text.square.fill",
                    tint: .red,
                    title: "Apple 健康",
                    subtitle: healthKitService.statusMessage
                )
                HealthKitSnapshotCard(
                    summary: summary,
                    supportedTypes: healthKitService.supportedReadTypesSummary,
                    hasCompletedAuthorizationRequest: healthKitService.hasCompletedAuthorizationRequest
                )
            }

            Section("近期健康信号") {
                if summary.metricSummaries.isEmpty {
                    SettingsStatusRow(
                        iconName: "waveform.path.ecg",
                        tint: .secondary,
                        title: "暂无近期样本",
                        subtitle: healthKitService.hasCompletedAuthorizationRequest ? "授权范围内还没有可读取的生命体征" : "完成授权请求后显示最近 56 天的生命体征"
                    )
                } else {
                    ForEach(summary.metricSummaries) { metric in
                        HealthKitMetricSummaryRow(metric: metric)
                    }
                }
            }

            Section("用于本 App") {
                NavigationLink {
                    MedicationTrendDetailView()
                } label: {
                    HealthKitContributionRow(
                        iconName: "chart.line.uptrend.xyaxis",
                        tint: .blue,
                        title: "用药趋势",
                        subtitle: "作为趋势背景信号",
                        trailingText: summary.hasSamples ? "\(summary.coveredDayCount) 天" : "待授权"
                    )
                }

                NavigationLink {
                    VisitSummaryView()
                } label: {
                    HealthKitContributionRow(
                        iconName: "doc.text.magnifyingglass",
                        tint: .orange,
                        title: "复诊资料",
                        subtitle: "随报告汇总近期观察",
                        trailingText: summary.hasSamples ? "\(summary.sampleCount) 条" : "待样本"
                    )
                }
            }

            Section(healthKitService.hasCompletedAuthorizationRequest ? "管理" : "授权") {
                if healthKitService.hasCompletedAuthorizationRequest {
                    SettingsStatusRow(
                        iconName: "checkmark.seal.fill",
                        tint: .green,
                        title: "已完成授权请求",
                        subtitle: "可在系统隐私设置管理具体指标"
                    )
                    Button {
                        Task {
                            await healthKitService.refreshRecentTrendSamples()
                        }
                    } label: {
                        Text("刷新近期健康数据")
                    }
                } else {
                    Button {
                        startHealthPermissionFlow()
                    } label: {
                        Text("请求读取健康数据授权")
                    }
                }
                Button {
                    openSystemSettings()
                } label: {
                    Text("打开系统隐私设置")
                }
            }
        }
        .navigationTitle("Apple 健康")
        .toolbar(.hidden, for: .tabBar)
        .appPermissionPrimer(pendingGate: $pendingPermissionGate) { gate in
            guard gate == .health else {
                return
            }
            Task {
                let requestCompleted = await healthKitService.requestAuthorizationEntry()
                if requestCompleted {
                    AppPermissionGate.markAuthorizationCompleted(for: .health)
                }
            }
        }
        .task {
            await healthKitService.refreshRecentTrendSamples()
        }
    }

    private func startHealthPermissionFlow() {
        if healthKitService.hasCompletedAuthorizationRequest {
            AppPermissionGate.markAuthorizationCompleted(for: .health)
            Task {
                await healthKitService.refreshRecentTrendSamples()
            }
            return
        }
        if AppPermissionGate.hasCompletedAuthorization(for: .health) {
            Task {
                let requestCompleted = await healthKitService.requestAuthorizationEntry()
                if requestCompleted {
                    AppPermissionGate.markAuthorizationCompleted(for: .health)
                }
            }
        } else {
            pendingPermissionGate = .health
        }
    }

    private func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else {
            return
        }
        UIApplication.shared.open(url)
    }
}

struct HealthKitSnapshotCard: View {
    let summary: HealthKitRecentSummary
    let supportedTypes: String
    let hasCompletedAuthorizationRequest: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(summary.hasSamples ? summary.latestSampleText : "等待健康数据")
                    .font(.headline)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
                Spacer(minLength: 12)
                Text(summary.coverageText)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(summary.hasSamples ? .teal : .secondary)
            }

            HStack(spacing: 10) {
                HealthKitSnapshotTile(title: "覆盖", value: summary.hasSamples ? "\(summary.coveredDayCount) 天" : "0 天", tint: .teal)
                HealthKitSnapshotTile(title: "样本", value: "\(summary.sampleCount)", tint: .blue)
                HealthKitSnapshotTile(title: "指标", value: "\(summary.metricSummaries.count)", tint: .indigo)
            }

            HStack(spacing: 6) {
                Image(systemName: hasCompletedAuthorizationRequest ? "checkmark.shield.fill" : "shield")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(hasCompletedAuthorizationRequest ? .blue : .secondary)
                Text(supportedTypes)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
            }
        }
        .padding(.vertical, 4)
    }
}

struct HealthKitSnapshotTile: View {
    let title: String
    let value: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(tint)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: 54, alignment: .leading)
        .medicationGlassSurface(cornerRadius: 8, tint: tint, fallbackMaterial: .thinMaterial)
    }
}

struct HealthKitMetricSummaryRow: View {
    let metric: HealthKitMetricSummary

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(healthMetricTint(metric.kind).opacity(0.12))
                Image(systemName: metric.symbolName)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(healthMetricTint(metric.kind))
            }
            .frame(width: 38, height: 38)

            VStack(alignment: .leading, spacing: 3) {
                Text(metric.title)
                    .font(.body.weight(.medium))
                Text("\(metric.coveredDayCount) 天 · \(metric.sampleCount) 条")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 12)

            VStack(alignment: .trailing, spacing: 3) {
                Text(metric.latestValueText)
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                Text(AppFormatters.day.string(from: metric.latestMeasuredAt))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
    }
}

struct HealthKitContributionRow: View {
    let iconName: String
    let tint: Color
    let title: String
    let subtitle: String
    let trailingText: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: iconName)
                .font(.headline)
                .foregroundStyle(tint)
                .frame(width: 30, height: 30)
                .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.body.weight(.medium))
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 12)

            Text(trailingText)
                .font(.caption.weight(.semibold))
                .foregroundStyle(tint)
        }
        .padding(.vertical, 4)
    }
}

private func healthMetricTint(_ kind: HealthSignalKind) -> Color {
    switch kind {
    case .heartRate:
        .red
    case .bloodPressureSystolic, .bloodPressureDiastolic:
        .indigo
    case .bloodOxygen:
        .teal
    case .bodyTemperature:
        .orange
    case .bloodGlucose:
        .purple
    case .unknown:
        .gray
    }
}

struct MedicalAIPrivacyView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \StoredAIConsent.grantedAt, order: .reverse) private var consents: [StoredAIConsent]
    @State private var revocationErrorMessage: String?

    private var activeConsent: StoredAIConsent? {
        consents.first { $0.id == "medical-ai-consent" && $0.isActive }
    }

    var body: some View {
        List {
            Section {
                SettingsStatusRow(
                    iconName: "lock.shield.fill",
                    tint: .green,
                    title: "医疗智能体",
                    subtitle: activeConsent == nil ? "设备端默认本机处理；云端需主动授权" : "已授权智能体读取所选用药数据"
                )
            }

            Section("共享范围") {
                if let activeConsent {
                    ConsentScopeRow(title: "药品名称、规格和来源", isEnabled: activeConsent.sharesMedicationProfile)
                    ConsentScopeRow(title: "提醒计划", isEnabled: activeConsent.sharesMedicationPlans)
                    ConsentScopeRow(title: "服药记录", isEnabled: activeConsent.sharesDoseEvents)
                    ConsentScopeRow(title: "风险提醒", isEnabled: activeConsent.sharesRiskCards)
                    ConsentScopeRow(title: "说明书摘要", isEnabled: activeConsent.sharesDrugLabels)
                    ConsentScopeRow(title: "导入识别内容", isEnabled: activeConsent.sharesImportDraft)
                } else {
                    Text("设备端模型会在本机整理授权数据；云端智能体只有在你主动选择并确认授权后才会连接外部服务。")
                        .foregroundStyle(.secondary)
                }
            }

            if activeConsent != nil {
                Section {
                    Button(role: .destructive) {
                        revokeAIConsent()
                    } label: {
                        Text("停止共享用药数据")
                    }
                }
            }
        }
        .navigationTitle("医疗智能体")
        .toolbar(.hidden, for: .tabBar)
        .alert("撤销失败", isPresented: .constant(revocationErrorMessage != nil)) {
            Button("好") {
                revocationErrorMessage = nil
            }
        } message: {
            if let errorMessage = revocationErrorMessage {
                Text(errorMessage)
            }
        }
    }

    private func revokeAIConsent() {
        let command = AIConsentRevocationCommand(modelContext: modelContext)
        let outcome = command.execute()

        switch outcome {
        case .revoked:
            break
        case .alreadyRevoked:
            break
        case .saveFailed:
            revocationErrorMessage = "撤销未能保存，授权仍然有效。请重试。"
        case .consentNotFound:
            revocationErrorMessage = "未找到有效授权。"
        }
    }
}

struct ConsentScopeRow: View {
    let title: String
    let isEnabled: Bool

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            Text(isEnabled ? "已共享" : "未共享")
                .font(.caption.weight(.semibold))
                .foregroundStyle(isEnabled ? .green : .secondary)
        }
    }
}

struct AccountHeaderRow: View {
    @AppStorage("wantsICloudBackup") private var wantsICloudBackup = false

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: wantsICloudBackup ? "externaldrive.badge.checkmark" : "externaldrive.fill")
                .font(.largeTitle)
                .foregroundStyle(.blue)
                .frame(width: 48, height: 48)
            VStack(alignment: .leading, spacing: 4) {
                Text("本机数据")
                    .font(.headline)
                Text(statusText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 8)
    }

    private var statusText: String {
        if wantsICloudBackup {
            return "已记录备份偏好，数据仍由你主动管理"
        }
        return "提醒、记录和药品资料保存在这台 iPhone"
    }
}

struct SettingsStatusRow: View {
    let iconName: String
    let tint: Color
    let title: String
    let subtitle: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: iconName)
                .font(.headline)
                .foregroundStyle(tint)
                .frame(width: 30, height: 30)
                .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.body.weight(.medium))
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

struct SettingsToggleRow: View {
    let title: String
    @Binding var isOn: Bool

    var body: some View {
        Button {
            withAnimation(.snappy(duration: 0.18, extraBounce: 0)) {
                isOn.toggle()
            }
        } label: {
            HStack(spacing: 12) {
                Text(title)
                    .foregroundStyle(.primary)
                Spacer(minLength: 12)
                SettingsSwitchVisual(isOn: isOn)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityValue(isOn ? "已开启" : "已关闭")
    }
}

struct SettingsSwitchVisual: View {
    let isOn: Bool

    var body: some View {
        Capsule(style: .continuous)
            .fill(isOn ? Color.green : Color.secondary.opacity(0.26))
            .frame(width: 51, height: 31)
            .overlay(alignment: isOn ? .trailing : .leading) {
                Circle()
                    .fill(Color.white)
                    .frame(width: 27, height: 27)
                    .shadow(color: Color.black.opacity(0.12), radius: 2, x: 0, y: 1)
                    .padding(2)
            }
            .animation(.snappy(duration: 0.18, extraBounce: 0), value: isOn)
            .accessibilityHidden(true)
    }
}
