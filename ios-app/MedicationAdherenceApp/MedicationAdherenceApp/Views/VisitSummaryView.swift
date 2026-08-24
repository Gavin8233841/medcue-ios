import AuthenticationServices
import MedicationAdherenceCore
import OSLog
import QuickLook
import SwiftData
import SwiftUI
import UIKit

struct VisitSummaryView: View {
    @Environment(\.modelContext) private var modelContext
    @StateObject private var healthKitService = HealthKitService()
    @State private var rangeStartDate = Calendar.current.date(byAdding: .day, value: -60, to: Date()) ?? Date()
    @State private var rangeEndDate = Date()
    @State private var pdfURL: URL?
    @State private var generatedPDFSignature = ""
    @State private var previewPDFItem: PDFPreviewItem?
    @State private var exportMessage = ""
    @State private var isSummaryPreviewExpanded = false
    @State private var snapshot: VisitSummarySnapshot?
    @State private var storedData: VisitSummaryStoredData?
    @State private var pdfGenerationTask: Task<Void, Never>?
    @State private var generationGate = VisitSummaryGenerationGate()
    @State private var isGeneratingPDF = false

    private let pdfLifecycle = VisitSummaryPDFLifecycle.production()

    private var normalizedRange: (start: Date, end: Date) {
        VisitSummaryDateRange.normalized(startDate: rangeStartDate, endDate: rangeEndDate)
    }

    private var rangeText: String {
        VisitSummaryDateRange.displayText(startDate: normalizedRange.start, endDate: normalizedRange.end)
    }

    private var rangeLoadID: String {
        [
            String(normalizedRange.start.timeIntervalSinceReferenceDate.bitPattern),
            String(normalizedRange.end.timeIntervalSinceReferenceDate.bitPattern)
        ].joined(separator: "|")
    }

    private var sourceRevision: VisitSummarySnapshotRevision? {
        guard let storedData else { return nil }
        return VisitSummarySnapshotRevision(
            startDate: normalizedRange.start,
            endDate: normalizedRange.end,
            medicationSignature: stableMedicationSignature(storedData.medications),
            taskSignature: stableTaskSignature(storedData.tasks),
            doseChangeSignature: stableDoseChangeSignature(storedData.doseChanges),
            riskCardSignature: stableRiskCardSignature(storedData.riskCards),
            healthSignalSignature: stableHealthSignalSignature(healthKitService.recentTrendSamples),
            planSignature: stablePlanSignature(storedData.plans),
            lifecycleEventSignature: stableLifecycleEventSignature(storedData.lifecycleEvents)
        )
    }

    private var currentPDFURL: URL? {
        guard let snapshot else {
            return nil
        }
        return generatedPDFSignature == snapshot.exportSignature ? pdfURL : nil
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    Label("复诊沟通摘要", systemImage: "doc.text")
                        .font(.headline)
                }
                .padding(.vertical, 6)
            }

            Section("导出") {
                VisitSummaryExportPanel(
                    pdfURL: currentPDFURL,
                    exportMessage: exportMessage,
                    rangeText: rangeText,
                    medicationCount: snapshot?.medicationCount ?? 0,
                    completionRate: snapshot?.completionRate ?? 0,
                    communicationCount: snapshot?.communicationCount ?? 0,
                    isGeneratingPDF: isGeneratingPDF,
                    onGeneratePDF: generatePDF,
                    onPreviewPDF: { url in
                        previewPDFItem = PDFPreviewItem(url: url)
                    }
                )
            }

            Section("日期范围") {
                DatePicker("开始日期", selection: $rangeStartDate, in: ...Date(), displayedComponents: .date)
                DatePicker("结束日期", selection: $rangeEndDate, in: ...Date(), displayedComponents: .date)
                Text("当前范围：\(rangeText)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .onChange(of: rangeStartDate) { _, newValue in
                if newValue > rangeEndDate {
                    rangeEndDate = newValue
                }
                resetGeneratedPDFState()
            }
            .onChange(of: rangeEndDate) { _, newValue in
                if newValue < rangeStartDate {
                    rangeStartDate = newValue
                }
                resetGeneratedPDFState()
            }

            Section("关键指标") {
                VisitSummaryMetricGrid(
                    medicationCount: snapshot?.medicationCount ?? 0,
                    completionRate: snapshot?.completionRate ?? 0,
                    takenCount: snapshot?.completedCount ?? 0,
                    communicationCount: snapshot?.communicationCount ?? 0
                )
            }

            Section("健康信号") {
                VisitSummaryHealthSignalCard(
                    summary: snapshot?.healthSummary ?? HealthKitRecentSummary(samples: [], refreshedAt: nil),
                    hasCompletedAuthorizationRequest: healthKitService.hasCompletedAuthorizationRequest,
                    statusMessage: healthKitService.statusMessage
                )
                NavigationLink {
                    HealthDataSettingsView()
                } label: {
                    Label("查看 Apple 健康接入", systemImage: "heart.text.square")
                }
            }

            Section {
                DisclosureGroup(isExpanded: $isSummaryPreviewExpanded) {
                    Text(snapshot?.summaryText ?? "正在整理复诊资料…")
                        .font(.body.monospaced())
                        .textSelection(.enabled)
                        .padding(.top, 8)
                } label: {
                    Label("摘要预览", systemImage: "text.alignleft")
                        .font(.headline)
                }
            }
        }
        .navigationTitle("复诊资料")
        .toolbar(.hidden, for: .tabBar)
        .safeAreaInset(edge: .bottom) {
            Color.clear.frame(height: 28)
        }
        .task {
            await healthKitService.refreshRecentTrendSamples()
            // Sweep expired PDF files at startup
            pdfLifecycle.sweepExpiredFiles()
        }
        .task(id: rangeLoadID) {
            await loadStoredData(startDate: normalizedRange.start, endDate: normalizedRange.end)
        }
        .task(id: sourceRevision?.id ?? "visit-summary-unloaded") {
            guard let sourceRevision else { return }
            await refreshSnapshot(for: sourceRevision)
        }
        .sheet(item: $previewPDFItem) { item in
            PDFPreviewSheet(url: item.url)
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                ShareLink(item: snapshot?.summaryText ?? "") {
                    Image(systemName: "square.and.arrow.up")
                        .accessibilityLabel("分享文本")
                }
            }
        }
        .onDisappear {
            cancelPDFGeneration()
            // Remove the current PDF file when leaving the screen
            if let pdfURL {
                pdfLifecycle.remove(pdfURL)
            }
        }
    }

    private func generatePDF() {
        guard let snapshot else {
            exportMessage = "复诊资料仍在整理，请稍后重试。"
            return
        }

        // Sweep expired files before generating a new one
        pdfLifecycle.sweepExpiredFiles()

        // Remove the previous PDF if it exists
        if let oldPDFURL = pdfURL {
            pdfLifecycle.remove(oldPDFURL)
            pdfURL = nil
        }

        cancelPDFGeneration()
        let payload = VisitSummaryExportPayload(
            medications: snapshot.medications,
            tasks: snapshot.tasks,
            doseChanges: snapshot.doseChanges,
            riskCards: snapshot.riskCards,
            trendDashboard: snapshot.trendDashboard,
            healthSignals: snapshot.healthSignals,
            startDate: snapshot.startDate,
            endDate: snapshot.endDate,
            generatedAt: snapshot.generatedAt,
            exportSignature: snapshot.exportSignature
        )
        let requestID = generationGate.begin()
        isGeneratingPDF = true
        exportMessage = ""
        pdfGenerationTask = Task {
            do {
                let completedURL = try await VisitSummaryPDFExporter.export(
                    payload: payload,
                    lifecycle: pdfLifecycle
                )
                guard !Task.isCancelled, generationGate.accepts(requestID) else {
                    // Task was cancelled or superseded; remove the artifact
                    pdfLifecycle.remove(completedURL)
                    return
                }
                pdfURL = completedURL
                generatedPDFSignature = payload.exportSignature
                isGeneratingPDF = false
                pdfGenerationTask = nil
            } catch is CancellationError {
                guard generationGate.accepts(requestID) else { return }
                isGeneratingPDF = false
                pdfGenerationTask = nil
            } catch {
                guard generationGate.accepts(requestID) else { return }
                isGeneratingPDF = false
                pdfGenerationTask = nil
                exportMessage = "PDF 生成失败，请稍后重试。"
            }
        }
    }

    @MainActor
    private func loadStoredData(startDate: Date, endDate: Date) async {
        snapshot = nil
        storedData = nil
        await Task.yield()
        guard !Task.isCancelled else { return }
        let outcome = VisitSummaryDataCommand(modelContext: modelContext).load(
            startDate: startDate,
            endDate: endDate
        )
        guard !Task.isCancelled,
              startDate == normalizedRange.start,
              endDate == normalizedRange.end
        else {
            return
        }
        switch outcome {
        case let .loaded(data):
            storedData = data
            exportMessage = ""
        case .rejected:
            break
        case .failed:
            exportMessage = "复诊资料读取失败，请稍后重试。"
        }
    }

    @MainActor
    private func refreshSnapshot(for revision: VisitSummarySnapshotRevision) async {
        await Task.yield()
        guard !Task.isCancelled,
              revision == sourceRevision,
              let storedData
        else {
            return
        }
        snapshot = VisitSummarySnapshot.build(
            revision: revision,
            medications: storedData.medications,
            tasks: storedData.tasks,
            doseChanges: storedData.doseChanges,
            plans: storedData.plans,
            lifecycleEvents: storedData.lifecycleEvents,
            riskCards: storedData.riskCards,
            healthSignals: healthKitService.recentTrendSamples,
            healthRefreshedAt: healthKitService.lastSampleRefreshAt,
            generatedAt: Date()
        )
    }

    private func resetGeneratedPDFState() {
        cancelPDFGeneration()
        if let oldPDFURL = pdfURL {
            pdfLifecycle.remove(oldPDFURL)
        }
        pdfURL = nil
        generatedPDFSignature = ""
        previewPDFItem = nil
        exportMessage = ""
    }

    private func cancelPDFGeneration() {
        generationGate.cancel()
        pdfGenerationTask?.cancel()
        pdfGenerationTask = nil
        isGeneratingPDF = false
    }
}

struct VisitSummarySnapshot {
    private static let signposter = OSSignposter(
        subsystem: Bundle.main.bundleIdentifier ?? "MedicationAdherenceApp",
        category: "VisitSummary"
    )

    let revision: VisitSummarySnapshotRevision
    let generatedAt: Date
    let startDate: Date
    let endDate: Date
    let medications: [StoredMedication]
    let tasks: [StoredDoseTask]
    let doseChanges: [StoredMedicationDoseChange]
    let riskCards: [StoredRiskCard]
    let healthSignals: [HealthSignalSample]
    let trendDashboard: MedicationTrendDashboard
    let healthSummary: HealthKitRecentSummary
    let medicationCount: Int
    let completedCount: Int
    let completionRate: Double
    let communicationCount: Int
    let summaryText: String
    let exportSignature: String

    @MainActor
    static func build(
        revision: VisitSummarySnapshotRevision,
        medications: [StoredMedication],
        tasks: [StoredDoseTask],
        doseChanges: [StoredMedicationDoseChange],
        plans: [StoredMedicationPlan],
        lifecycleEvents: [StoredMedicationLifecycleEvent],
        riskCards: [StoredRiskCard],
        healthSignals: [HealthSignalSample],
        healthRefreshedAt: Date?,
        generatedAt: Date
    ) -> VisitSummarySnapshot {
        let signpostState = signposter.beginInterval("visit_summary.snapshot")
        defer { signposter.endInterval("visit_summary.snapshot", signpostState) }
        let reportTasks = VisitSummaryTaskFilter.historicalTasks(
            from: tasks.adherenceMeasurableTasks,
            startDate: revision.startDate,
            endDate: revision.endDate
        )
        let reportDoseChanges = doseChanges.filter {
            $0.effectiveFrom >= revision.startDate && $0.effectiveFrom <= revision.endDate
        }
        let reportHealthSignals = healthSignals.filter {
            $0.measuredAt >= revision.startDate && $0.measuredAt <= revision.endDate
        }
        let rangeRiskCards = riskCards.filter {
            $0.lastDetectedAt >= revision.startDate && $0.lastDetectedAt <= revision.endDate
        }
        let medicationIDs = Set(reportTasks.map(\.medicationID))
            .union(reportDoseChanges.map(\.medicationID))
            .union(rangeRiskCards.lazy.filter(\.isActive).map(\.medicationID))
        let reportMedications = medications.filter { medicationIDs.contains($0.id) }
        let reportRiskCards = rangeRiskCards.filter {
            medicationIDs.contains($0.medicationID) && $0.isActive
        }

        var completedCount = 0
        var skippedCount = 0
        var delayedCount = 0
        for task in reportTasks {
            switch task.status {
            case .taken, .corrected:
                completedCount += 1
            case .skipped:
                skippedCount += 1
            case .delayed:
                delayedCount += 1
            case .pending:
                break
            }
        }
        let professionalRiskCount = reportRiskCards.lazy
            .filter { $0.requiresProfessionalReview && $0.isActive }
            .count
        let completionRate = reportTasks.isEmpty
            ? 0
            : Double(completedCount) / Double(reportTasks.count)
        let trendDashboard = medicationTrendDashboardInput(
            tasks: reportTasks,
            doseChanges: reportDoseChanges,
            medications: medications,
            plans: plans,
            lifecycleEvents: lifecycleEvents,
            healthSignals: reportHealthSignals,
            now: generatedAt
        ).build()
        let summaryText = VisitSummaryTextBuilder().build(
            medications: reportMedications,
            tasks: reportTasks,
            riskCards: reportRiskCards,
            startDate: revision.startDate,
            endDate: revision.endDate,
            generatedAt: generatedAt
        )
        let exportSignature = [
            revision.id,
            String(Int((trendDashboard.overallScore * 1_000).rounded())),
            trendDashboard.direction.rawValue
        ].joined(separator: "|")

        return VisitSummarySnapshot(
            revision: revision,
            generatedAt: generatedAt,
            startDate: revision.startDate,
            endDate: revision.endDate,
            medications: reportMedications,
            tasks: reportTasks,
            doseChanges: reportDoseChanges,
            riskCards: reportRiskCards,
            healthSignals: reportHealthSignals,
            trendDashboard: trendDashboard,
            healthSummary: HealthKitRecentSummary(
                samples: reportHealthSignals,
                refreshedAt: healthRefreshedAt
            ),
            medicationCount: medicationIDs.count,
            completedCount: completedCount,
            completionRate: completionRate,
            communicationCount: skippedCount + delayedCount + professionalRiskCount,
            summaryText: summaryText,
            exportSignature: exportSignature
        )
    }
}

struct VisitSummaryExportPanel: View {
    let pdfURL: URL?
    let exportMessage: String
    let rangeText: String
    let medicationCount: Int
    let completionRate: Double
    let communicationCount: Int
    let isGeneratingPDF: Bool
    let onGeneratePDF: () -> Void
    let onPreviewPDF: (URL) -> Void

    private var isPDFReady: Bool {
        pdfURL != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("复诊沟通 PDF")
                        .font(.headline)
                    Text(rangeText)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer(minLength: 10)

                Label(
                    isGeneratingPDF ? "生成中" : (isPDFReady ? "已生成" : "待生成"),
                    systemImage: isGeneratingPDF ? "hourglass" : (isPDFReady ? "checkmark.circle.fill" : "doc.badge.plus")
                )
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(statusTint)
                    .lineLimit(1)
            }

            HStack(spacing: 10) {
                VisitSummaryExportMetric(title: "药品", value: "\(medicationCount)", tint: .blue)
                VisitSummaryExportMetric(title: "服用率", value: "\(Int((completionRate * 100).rounded()))%", tint: .teal)
                VisitSummaryExportMetric(title: "需沟通", value: "\(communicationCount)", tint: .orange)
            }

            HStack(spacing: 10) {
                Button(action: onGeneratePDF) {
                    VisitSummaryExportActionLabel(
                        title: isGeneratingPDF ? "生成中" : (isPDFReady ? "重新生成" : "生成 PDF"),
                        systemImage: isGeneratingPDF ? "hourglass" : (isPDFReady ? "arrow.clockwise" : "doc.badge.plus"),
                        tint: .blue,
                        isProminent: true
                    )
                }
                .buttonStyle(.plain)
                .disabled(isGeneratingPDF)

                if let pdfURL {
                    Button {
                        onPreviewPDF(pdfURL)
                    } label: {
                        VisitSummaryExportActionLabel(title: "预览", systemImage: "eye", tint: .indigo)
                    }
                    .buttonStyle(.plain)

                    ShareLink(item: pdfURL) {
                        VisitSummaryExportActionLabel(title: "分享", systemImage: "square.and.arrow.up", tint: .teal)
                    }
                }
            }

            if !exportMessage.isEmpty {
                Text(exportMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .padding(.top, -2)
            }
        }
        .padding(.vertical, 6)
    }

    private var statusTint: Color {
        isPDFReady ? .green : .blue
    }
}

struct VisitSummaryExportMetric: View {
    let title: String
    let value: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value)
                .font(.subheadline.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

struct VisitSummaryExportActionLabel: View {
    let title: String
    let systemImage: String
    let tint: Color
    var isProminent = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.subheadline.weight(.semibold))
            Text(title)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.82)
            Spacer(minLength: 10)
        }
        .foregroundStyle(isProminent ? .white : tint)
        .padding(.horizontal, isProminent ? 14 : 12)
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .background(isProminent ? tint : tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            if !isProminent {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(tint.opacity(0.16), lineWidth: 1)
            }
        }
    }
}

struct VisitSummaryMetricGrid: View {
    let medicationCount: Int
    let completionRate: Double
    let takenCount: Int
    let communicationCount: Int

    var body: some View {
        HStack(spacing: 10) {
            VisitSummaryMetricTile(title: "药品", value: "\(medicationCount)", tint: .blue)
            VisitSummaryMetricTile(title: "服用率", value: "\(Int((completionRate * 100).rounded()))%", tint: .green)
            VisitSummaryMetricTile(title: "需沟通", value: "\(communicationCount)", tint: .orange)
        }
        .padding(.vertical, 4)
    }
}

struct VisitSummaryMetricTile: View {
    let title: String
    let value: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(value)
                .font(.title3.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
        .background(tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
    }
}

struct VisitSummaryHealthSignalCard: View {
    let summary: HealthKitRecentSummary
    let hasCompletedAuthorizationRequest: Bool
    let statusMessage: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: summary.hasSamples ? "heart.text.square.fill" : "heart.text.square")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(summary.hasSamples ? .teal : .secondary)
                    .frame(width: 38, height: 38)
                    .background((summary.hasSamples ? Color.teal : Color.secondary).opacity(0.12), in: RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 4) {
                    Text(summary.hasSamples ? "已纳入复诊资料" : healthSignalEmptyTitle)
                        .font(.headline)
                    Text(summary.hasSamples ? summary.latestSampleText : statusMessage)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            HStack(spacing: 10) {
                VisitSummaryMetricTile(title: "覆盖", value: summary.hasSamples ? "\(summary.coveredDayCount) 天" : "0 天", tint: .teal)
                VisitSummaryMetricTile(title: "样本", value: "\(summary.sampleCount)", tint: .blue)
                VisitSummaryMetricTile(title: "指标", value: "\(summary.metricSummaries.count)", tint: .indigo)
            }

            if summary.hasSamples {
                Text(summary.metricSummaries.prefix(3).map(\.title).joined(separator: "、"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 4)
    }

    private var healthSignalEmptyTitle: String {
        hasCompletedAuthorizationRequest ? "本范围暂无健康样本" : "等待完成 Apple 健康授权请求"
    }
}

enum VisitSummaryDateRange {
    static func normalized(startDate: Date, endDate: Date) -> (start: Date, end: Date) {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: min(startDate, endDate))
        let endStart = calendar.startOfDay(for: max(startDate, endDate))
        let end = calendar.date(byAdding: DateComponents(day: 1, second: -1), to: endStart) ?? endStart
        return (start, end)
    }

    static func displayText(startDate: Date, endDate: Date) -> String {
        "\(AppFormatters.day.string(from: startDate)) - \(AppFormatters.day.string(from: endDate))"
    }
}

enum VisitSummaryTaskFilter {
    static func historicalTasks(
        from tasks: [StoredDoseTask],
        startDate: Date,
        endDate: Date
    ) -> [StoredDoseTask] {
        return tasks
            .filter { task in
                let referenceDate = task.effectiveAdherenceDate
                guard referenceDate >= startDate && referenceDate <= endDate else {
                    return false
                }
                return task.dueAt <= endDate || task.effectiveAdherenceRecordedAt != nil
            }
            .sorted { $0.effectiveAdherenceDate < $1.effectiveAdherenceDate }
    }
}
