import AuthenticationServices
import MedicationAdherenceCore
import SwiftData
import SwiftUI
import UIKit

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \StoredAIConsent.grantedAt, order: .reverse) private var consents: [StoredAIConsent]
    @Query(sort: \StoredMedication.displayName) private var medications: [StoredMedication]
    @Query(sort: \StoredDoseTask.dueAt, order: .reverse) private var tasks: [StoredDoseTask]
    @AppStorage("appColorSchemePreference") private var appColorSchemePreference = AppColorSchemePreference.system.rawValue
    @AppStorage("prefersReducedAppMotion") private var prefersReducedAppMotion = false
    @AppStorage("showsMedicationPhotosInReminders") private var showsMedicationPhotosInReminders = true
    @AppStorage("usesLargeTouchTargets") private var usesLargeTouchTargets = true
    @StateObject private var notificationService = NotificationService()
    @StateObject private var healthKitService = HealthKitService()

    private var activeConsent: StoredAIConsent? {
        consents.first { $0.id == "medical-ai-consent" && $0.isActive }
    }

    var body: some View {
        List {
            Section {
                NavigationLink {
                    AccountBackupView()
                } label: {
                    AccountHeaderRow()
                }
            }

            Section("外观与交互") {
                Picker("显示模式", selection: $appColorSchemePreference) {
                    ForEach(AppColorSchemePreference.allCases) { preference in
                        Text(preference.displayName).tag(preference.rawValue)
                    }
                }
                .pickerStyle(.segmented)

                Toggle("减少动态效果", isOn: $prefersReducedAppMotion)
                HStack {
                    Text("语言")
                    Spacer()
                    Text("中文")
                        .foregroundStyle(.secondary)
                }
                Text("英文界面将在后续版本随本地化资源一起开放，当前不提供无效切换。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Toggle("提醒时突出药品图片", isOn: $showsMedicationPhotosInReminders)
                Toggle("使用更大的触控区域", isOn: $usesLargeTouchTargets)
                Text("默认跟随系统显示模式；这些偏好只影响本 App。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("用药提醒") {
                SettingsStatusRow(
                    iconName: "bell.badge.fill",
                    tint: .blue,
                    title: "提醒通知",
                    subtitle: notificationService.authorizationMessage
                )
                Button {
                    Task {
                        await notificationService.requestAuthorization()
                    }
                } label: {
                    Text("开启或更新通知权限")
                }
                Button {
                    openSystemSettings()
                } label: {
                    Text("打开系统通知设置")
                }
            }

            Section("健康数据") {
                SettingsStatusRow(
                    iconName: "heart.text.square.fill",
                    tint: .red,
                    title: "Apple 健康",
                    subtitle: healthKitService.statusMessage
                )
                Text("可读取：\(healthKitService.supportedReadTypesSummary)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Button {
                    Task {
                        await healthKitService.requestAuthorizationEntry()
                    }
                } label: {
                    Text(healthKitService.hasCompletedAuthorizationRequest ? "重新请求或更新授权" : "授权读取健康数据")
                }
                if healthKitService.hasCompletedAuthorizationRequest {
                    Text("如需关闭或调整具体健康指标，请前往系统隐私设置。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Button {
                    openSystemSettings()
                } label: {
                    Text("打开系统隐私设置")
                }
            }

            Section("医疗智能体") {
                SettingsStatusRow(
                    iconName: "stethoscope",
                    tint: .green,
                    title: "医疗 AI",
                    subtitle: activeConsent == nil ? "尚未共享用药数据" : "已授权读取所选用药数据"
                )
                if activeConsent != nil {
                    Button(role: .destructive) {
                        revokeAIConsent()
                    } label: {
                        Text("停止共享用药数据")
                    }
                }
            }

            Section("复诊资料") {
                NavigationLink {
                    VisitSummaryView()
                } label: {
                    SettingsStatusRow(
                        iconName: "doc.text.fill",
                        tint: .orange,
                        title: "生成服药记录",
                        subtitle: "按时间段生成纯文本摘要，并可导出 PDF"
                    )
                }
                Text("记录只在你主动生成或分享时导出，用于复诊沟通。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("隐私") {
                Text("我们采用行业通用标准，帮助保护你的健康信息机密性。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("设置")
    }

    private func revokeAIConsent() {
        activeConsent?.revokedAt = Date()
        try? modelContext.save()
    }

    private func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else {
            return
        }
        UIApplication.shared.open(url)
    }
}

private struct AccountHeaderRow: View {
    @AppStorage("appleAccountLocalUserID") private var appleAccountLocalUserID = ""
    @AppStorage("wantsICloudBackup") private var wantsICloudBackup = false

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: appleAccountLocalUserID.isEmpty ? "person.crop.circle" : "person.crop.circle.fill.badge.checkmark")
                .font(.largeTitle)
                .foregroundStyle(.blue)
                .frame(width: 48, height: 48)
            VStack(alignment: .leading, spacing: 4) {
                Text(appleAccountLocalUserID.isEmpty ? "未登录账号" : "Apple 账号已连接")
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
        if appleAccountLocalUserID.isEmpty {
            return "登录不是使用提醒和记录的前置条件"
        }
        if wantsICloudBackup {
            return "已记录备份偏好"
        }
        return "可管理备份与账号状态"
    }
}

private struct SettingsStatusRow: View {
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

private struct AccountBackupView: View {
    @AppStorage("appleAccountLocalUserID") private var appleAccountLocalUserID = ""
    @AppStorage("wantsICloudBackup") private var wantsICloudBackup = false
    @State private var statusMessage = ""

    private var hasAppleAccountMark: Bool {
        !appleAccountLocalUserID.isEmpty
    }

    private var hasICloudAccount: Bool {
        FileManager.default.ubiquityIdentityToken != nil
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    Label("账号与备份", systemImage: "person.crop.circle")
                        .font(.headline)
                    Text("你可以不登录继续使用提醒、药品和记录。连接 Apple 账号仅用于备份与设备间同步准备。")
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 6)
            }

            Section("Apple 账号") {
                if hasAppleAccountMark {
                    SettingsStatusRow(
                        iconName: "checkmark.circle.fill",
                        tint: .green,
                        title: "已连接 Apple 账号",
                        subtitle: "账号标识仅保存在本机"
                    )
                    Button(role: .destructive) {
                        appleAccountLocalUserID = ""
                        statusMessage = "已断开本机 Apple 账号连接。"
                    } label: {
                        Text("断开 Apple 账号")
                    }
                } else {
                    SignInWithAppleButton(.continue) { request in
                        request.requestedScopes = []
                    } onCompletion: { result in
                        handleSignIn(result)
                    }
                    .signInWithAppleButtonStyle(.black)
                    .frame(height: 48)
                }

                Text("没有自建服务器账号体系时，不创建远程登录会话。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("备份") {
                SettingsStatusRow(
                    iconName: hasICloudAccount ? "icloud.fill" : "icloud.slash",
                    tint: hasICloudAccount ? .blue : .gray,
                    title: hasICloudAccount ? "已检测到 iCloud" : "未检测到 iCloud",
                    subtitle: hasICloudAccount ? "可用于 iCloud 备份准备" : "请先在系统设置中登录 iCloud"
                )
                Toggle("自动备份到 iCloud", isOn: $wantsICloudBackup)
                Text("当前版本只记录你的备份偏好，不会自动上传用药数据。正式启用前会在这里清楚说明同步范围。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("系统设置") {
                Button {
                    openSystemSettings()
                } label: {
                    Text("打开 App 系统设置")
                }
            }

            if !statusMessage.isEmpty {
                Section {
                    Text(statusMessage)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("账号")
    }

    private func handleSignIn(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case let .success(authorization):
            if let credential = authorization.credential as? ASAuthorizationAppleIDCredential {
                appleAccountLocalUserID = credential.user
                statusMessage = "Apple 账号已连接。"
            } else {
                statusMessage = "未能读取 Apple 账号状态。"
            }
        case let .failure(error):
            statusMessage = "Apple 账号连接未完成：\(error.localizedDescription)"
        }
    }

    private func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else {
            return
        }
        UIApplication.shared.open(url)
    }
}

private struct VisitSummaryView: View {
    @Query(sort: \StoredMedication.displayName) private var medications: [StoredMedication]
    @Query(sort: \StoredDoseTask.dueAt, order: .reverse) private var tasks: [StoredDoseTask]
    @Query(sort: \StoredRiskCard.displayPriority) private var riskCards: [StoredRiskCard]
    @State private var pdfURL: URL?
    @State private var exportMessage = ""

    private var summaryText: String {
        VisitSummaryTextBuilder().build(
            medications: medications,
            tasks: tasks,
            riskCards: riskCards,
            generatedAt: Date()
        )
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    Label("复诊沟通摘要", systemImage: "doc.text")
                        .font(.headline)
                    Text("摘要仅汇总用药记录、漏服/延后情况和风险提示，不能替代医生或药师判断。")
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 6)
            }

            Section("导出") {
                Button {
                    generatePDF()
                } label: {
                    Label("生成 PDF", systemImage: "doc.richtext")
                }
                if let pdfURL {
                    ShareLink(item: pdfURL) {
                        Label("分享 PDF", systemImage: "square.and.arrow.up")
                    }
                }
                if !exportMessage.isEmpty {
                    Text(exportMessage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            Section("摘要预览") {
                Text(summaryText)
                    .font(.body.monospaced())
                    .textSelection(.enabled)
            }
        }
        .navigationTitle("服药记录")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                ShareLink(item: summaryText) {
                    Image(systemName: "square.and.arrow.up")
                        .accessibilityLabel("分享文本")
                }
            }
        }
    }

    private func generatePDF() {
        let pageBounds = CGRect(x: 0, y: 0, width: 595, height: 842)
        let renderer = UIGraphicsPDFRenderer(bounds: pageBounds)
        let report = VisitSummaryPDFReport(
            medications: medications,
            tasks: tasks,
            riskCards: riskCards,
            generatedAt: Date()
        )
        let targetURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("服药记录-\(Int(Date().timeIntervalSince1970)).pdf")
        let data = renderer.pdfData { context in
            context.beginPage()
            report.draw(in: pageBounds)
        }
        do {
            try data.write(to: targetURL, options: .atomic)
            pdfURL = targetURL
            exportMessage = "PDF 已生成，可直接分享。"
        } catch {
            exportMessage = "PDF 生成失败，请稍后重试。"
        }
    }
}

private struct VisitSummaryPDFReport {
    let medications: [StoredMedication]
    let tasks: [StoredDoseTask]
    let riskCards: [StoredRiskCard]
    let generatedAt: Date

    private var completedCount: Int {
        tasks.filter { $0.status == .taken || $0.status == .corrected }.count
    }

    private var skippedCount: Int {
        tasks.filter { $0.status == .skipped }.count
    }

    private var delayedCount: Int {
        tasks.filter { $0.status == .delayed }.count
    }

    private var completionRate: Double {
        tasks.isEmpty ? 0 : Double(completedCount) / Double(tasks.count)
    }

    func draw(in pageBounds: CGRect) {
        let margin: CGFloat = 36
        let contentWidth = pageBounds.width - margin * 2
        let accent = UIColor(red: 0.13, green: 0.38, blue: 0.92, alpha: 1)
        let green = UIColor(red: 0.12, green: 0.58, blue: 0.32, alpha: 1)
        let orange = UIColor(red: 0.92, green: 0.43, blue: 0.12, alpha: 1)
        let softBackground = UIColor(red: 0.96, green: 0.975, blue: 0.995, alpha: 1)
        var y = margin

        drawHeader(x: margin, y: y, width: contentWidth, accent: accent)
        y += 86

        let metricWidth = (contentWidth - 24) / 4
        let metrics = [
            ("药品", "\(medications.count)", accent),
            ("完成率", "\(Int(completionRate * 100))%", green),
            ("已服用", "\(completedCount)", green),
            ("需沟通", "\(skippedCount + delayedCount)", orange)
        ]
        for (index, metric) in metrics.enumerated() {
            let x = margin + CGFloat(index) * (metricWidth + 8)
            drawMetricCard(title: metric.0, value: metric.1, color: metric.2, rect: CGRect(x: x, y: y, width: metricWidth, height: 62))
        }
        y += 82

        drawSectionTitle("近 60 天记录概览", x: margin, y: y)
        y += 26
        drawProgressBar(
            rect: CGRect(x: margin, y: y, width: contentWidth, height: 12),
            progress: completionRate,
            background: UIColor.systemGray5,
            fill: green
        )
        y += 28
        drawBodyText(
            "计划 \(tasks.count) 次，已服用 \(completedCount) 次，稍后 \(delayedCount) 次，已忽略 \(skippedCount) 次。该摘要仅用于复诊沟通，不替代医生或药师判断。",
            rect: CGRect(x: margin, y: y, width: contentWidth, height: 42)
        )
        y += 58

        drawSectionTitle("当前药品", x: margin, y: y)
        y += 24
        let medicationRows = Array(medications.prefix(6))
        for medication in medicationRows {
            let relatedTasks = tasks.filter { $0.medicationID == medication.id }
            let taken = relatedTasks.filter { $0.status == .taken || $0.status == .corrected }.count
            drawRoundedPanel(rect: CGRect(x: margin, y: y, width: contentWidth, height: 40), fill: softBackground)
            drawText(medication.displayName, rect: CGRect(x: margin + 14, y: y + 9, width: 168, height: 22), font: .systemFont(ofSize: 12, weight: .semibold))
            drawText([medication.strength, medication.form].filter { !$0.isEmpty }.joined(separator: " · "), rect: CGRect(x: margin + 188, y: y + 10, width: 190, height: 20), font: .systemFont(ofSize: 10), color: .secondaryLabel)
            drawText("\(taken) / \(relatedTasks.count) 次", rect: CGRect(x: margin + contentWidth - 92, y: y + 10, width: 78, height: 20), font: .monospacedDigitSystemFont(ofSize: 11, weight: .semibold), color: green, alignment: .right)
            y += 46
        }
        if medications.count > medicationRows.count {
            drawBodyText("另有 \(medications.count - medicationRows.count) 个药品未在本页展开。", rect: CGRect(x: margin, y: y, width: contentWidth, height: 20))
            y += 28
        }

        drawSectionTitle("异常与风险提示", x: margin, y: y)
        y += 24
        let exceptions = tasks
            .filter { $0.status == .skipped || $0.status == .delayed }
            .sorted { $0.dueAt > $1.dueAt }
            .prefix(4)
        if exceptions.isEmpty {
            drawRoundedPanel(rect: CGRect(x: margin, y: y, width: contentWidth, height: 38), fill: UIColor.systemGray6)
            drawText("近期没有需要优先沟通的漏服或延后记录。", rect: CGRect(x: margin + 14, y: y + 10, width: contentWidth - 28, height: 18), font: .systemFont(ofSize: 11), color: .secondaryLabel)
            y += 48
        } else {
            for task in exceptions {
                let medicationName = medications.first { $0.id == task.medicationID }?.displayName ?? "未知药品"
                let action = task.status == .skipped ? "已忽略" : "稍后提醒"
                drawTimelineDot(x: margin + 8, y: y + 11, color: task.status == .skipped ? orange : accent)
                drawText("\(AppFormatters.day.string(from: task.dueAt)) \(AppFormatters.time.string(from: task.dueAt))", rect: CGRect(x: margin + 24, y: y, width: 120, height: 20), font: .monospacedDigitSystemFont(ofSize: 10, weight: .medium), color: .secondaryLabel)
                drawText("\(medicationName)：\(action)", rect: CGRect(x: margin + 148, y: y, width: contentWidth - 148, height: 20), font: .systemFont(ofSize: 11, weight: .semibold))
                y += 24
            }
            y += 8
        }

        let importantRiskCards = riskCards.filter { $0.requiresProfessionalReview && !$0.isArchived }.prefix(3)
        for card in importantRiskCards {
            let medicationName = medications.first { $0.id == card.medicationID }?.displayName ?? "未知药品"
            drawRoundedPanel(rect: CGRect(x: margin, y: y, width: contentWidth, height: 52), fill: UIColor(red: 1, green: 0.965, blue: 0.91, alpha: 1))
            drawText(medicationName, rect: CGRect(x: margin + 14, y: y + 8, width: 120, height: 18), font: .systemFont(ofSize: 11, weight: .semibold), color: orange)
            drawText(card.title, rect: CGRect(x: margin + 138, y: y + 8, width: contentWidth - 152, height: 18), font: .systemFont(ofSize: 11, weight: .semibold))
            drawText(card.message, rect: CGRect(x: margin + 14, y: y + 28, width: contentWidth - 28, height: 18), font: .systemFont(ofSize: 9), color: .secondaryLabel)
            y += 60
        }

        drawFooter(x: margin, y: pageBounds.height - 54, width: contentWidth)
    }

    private func drawHeader(x: CGFloat, y: CGFloat, width: CGFloat, accent: UIColor) {
        drawText("服药复诊沟通报告", rect: CGRect(x: x, y: y, width: width * 0.62, height: 28), font: .systemFont(ofSize: 22, weight: .bold))
        drawText("生成时间 \(AppFormatters.day.string(from: generatedAt)) \(AppFormatters.time.string(from: generatedAt))", rect: CGRect(x: x, y: y + 32, width: width * 0.62, height: 18), font: .systemFont(ofSize: 10), color: .secondaryLabel)
        drawText("供复诊沟通", rect: CGRect(x: x + width - 118, y: y + 6, width: 118, height: 22), font: .systemFont(ofSize: 11, weight: .semibold), color: accent, alignment: .right)
        drawProgressBar(rect: CGRect(x: x, y: y + 66, width: width, height: 3), progress: 1, background: accent.withAlphaComponent(0.18), fill: accent)
    }

    private func drawMetricCard(title: String, value: String, color: UIColor, rect: CGRect) {
        drawRoundedPanel(rect: rect, fill: color.withAlphaComponent(0.10))
        drawText(value, rect: CGRect(x: rect.minX + 12, y: rect.minY + 10, width: rect.width - 24, height: 24), font: .monospacedDigitSystemFont(ofSize: 19, weight: .bold), color: color)
        drawText(title, rect: CGRect(x: rect.minX + 12, y: rect.minY + 37, width: rect.width - 24, height: 16), font: .systemFont(ofSize: 10, weight: .medium), color: .secondaryLabel)
    }

    private func drawSectionTitle(_ title: String, x: CGFloat, y: CGFloat) {
        drawText(title, rect: CGRect(x: x, y: y, width: 260, height: 20), font: .systemFont(ofSize: 14, weight: .bold))
    }

    private func drawFooter(x: CGFloat, y: CGFloat, width: CGFloat) {
        drawProgressBar(rect: CGRect(x: x, y: y - 10, width: width, height: 1), progress: 1, background: UIColor.systemGray5, fill: UIColor.systemGray5)
        drawText("该报告由用户主动生成和分享。内容仅用于整理记录和复诊沟通，不替代医生或药师判断。", rect: CGRect(x: x, y: y, width: width, height: 28), font: .systemFont(ofSize: 9), color: .secondaryLabel)
    }

    private func drawProgressBar(rect: CGRect, progress: Double, background: UIColor, fill: UIColor) {
        let path = UIBezierPath(roundedRect: rect, cornerRadius: rect.height / 2)
        background.setFill()
        path.fill()
        let fillRect = CGRect(x: rect.minX, y: rect.minY, width: rect.width * CGFloat(max(0, min(progress, 1))), height: rect.height)
        UIBezierPath(roundedRect: fillRect, cornerRadius: rect.height / 2).addClip()
        fill.setFill()
        path.fill()
    }

    private func drawRoundedPanel(rect: CGRect, fill: UIColor) {
        fill.setFill()
        UIBezierPath(roundedRect: rect, cornerRadius: 8).fill()
    }

    private func drawTimelineDot(x: CGFloat, y: CGFloat, color: UIColor) {
        color.setFill()
        UIBezierPath(ovalIn: CGRect(x: x, y: y, width: 8, height: 8)).fill()
    }

    private func drawBodyText(_ text: String, rect: CGRect) {
        drawText(text, rect: rect, font: .systemFont(ofSize: 10), color: .secondaryLabel)
    }

    private func drawText(
        _ text: String,
        rect: CGRect,
        font: UIFont,
        color: UIColor = .label,
        alignment: NSTextAlignment = .left
    ) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = alignment
        paragraph.lineBreakMode = .byTruncatingTail
        (text as NSString).draw(in: rect, withAttributes: [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: paragraph
        ])
    }
}

private struct VisitSummaryTextBuilder {
    func build(
        medications: [StoredMedication],
        tasks: [StoredDoseTask],
        riskCards: [StoredRiskCard],
        generatedAt: Date
    ) -> String {
        var lines: [String] = []
        lines.append("服药记录")
        lines.append("")
        lines.append("生成时间：\(AppFormatters.day.string(from: generatedAt)) \(AppFormatters.time.string(from: generatedAt))")
        lines.append("")
        lines.append("说明：此摘要仅用于复诊沟通，不能替代医生或药师判断；任何剂量、频次、疗程调整都应咨询医生或药师。")
        lines.append("")

        if medications.isEmpty {
            lines.append("用药记录")
            lines.append("暂无药品记录。")
        } else {
            lines.append("用药记录")
            for medication in medications {
                let relatedTasks = tasks.filter { $0.medicationID == medication.id }
                let summary = VisitSummaryBuilder().build(
                    generatedAt: generatedAt,
                    medication: medication.coreMedication,
                    scheduledDoses: relatedTasks.map(\.coreScheduledDose),
                    events: relatedTasks.compactMap(\.coreDoseEvent)
                )
                guard let line = summary.lines.first else {
                    continue
                }
                lines.append("\(line.medicationName)：计划 \(line.scheduledCount) 次，已服用 \(line.takenCount) 次，忽略 \(line.skippedCount) 次，稍后 \(line.delayedCount) 次。")
                if !line.notes.isEmpty {
                    lines.append("备注：\(line.notes.joined(separator: "；"))")
                }
            }
        }

        lines.append("")
        lines.append("近 60 天时间段记录")
        let calendar = Calendar.current
        let cutoff = calendar.date(byAdding: .day, value: -60, to: generatedAt) ?? generatedAt
        let recentTasks = tasks
            .filter { $0.dueAt >= cutoff && $0.dueAt <= generatedAt }
            .sorted { $0.dueAt < $1.dueAt }
        let groupedByWeek = Dictionary(grouping: recentTasks) { task -> String in
            let interval = calendar.dateInterval(of: .weekOfYear, for: task.dueAt)
            let start = interval?.start ?? task.dueAt
            return AppFormatters.day.string(from: start)
        }
        for weekStart in groupedByWeek.keys.sorted() {
            let weekTasks = groupedByWeek[weekStart] ?? []
            let takenCount = weekTasks.filter { $0.status == .taken || $0.status == .corrected }.count
            let delayedCount = weekTasks.filter { $0.status == .delayed }.count
            let skipped = weekTasks.filter { $0.status == .skipped }
            lines.append("\(weekStart) 周：计划 \(weekTasks.count) 次，完成 \(takenCount) 次，延后 \(delayedCount) 次，未服用 \(skipped.count) 次。")
            let exceptions = weekTasks
                .filter { $0.status == .skipped || $0.status == .delayed }
                .prefix(8)
            for task in exceptions {
                let medicationName = medications.first { $0.id == task.medicationID }?.displayName ?? "未知药品"
                let action = task.status == .skipped ? "未服用" : "延后"
                lines.append("- \(AppFormatters.day.string(from: task.dueAt)) \(AppFormatters.time.string(from: task.dueAt))：\(medicationName) \(action)。")
            }
        }

        lines.append("")
        lines.append("风险提示")
        let importantRiskCards = riskCards.filter { $0.requiresProfessionalReview && !$0.isArchived }.prefix(6)
        if importantRiskCards.isEmpty {
            lines.append("暂无需要优先沟通的风险卡片。")
        } else {
            for card in importantRiskCards {
                let medicationName = medications.first { $0.id == card.medicationID }?.displayName ?? "未知药品"
                lines.append("\(medicationName)：\(card.title)。\(card.message)")
            }
        }

        lines.append("")
        lines.append("隐私")
        lines.append("该摘要由用户主动生成和分享，App 不自动上传。")
        return lines.joined(separator: "\n")
    }
}
