import Charts
import MedicationAdherenceCore
import PhotosUI
import SwiftData
import SwiftUI
import UIKit

struct MedicationsView: View {
    @Query(sort: \StoredMedication.displayName) private var medications: [StoredMedication]
    @Query(sort: \StoredMedicationPlan.createdAt) private var plans: [StoredMedicationPlan]
    @Query(sort: \StoredDoseTask.dueAt, order: .reverse) private var tasks: [StoredDoseTask]
    @Query(sort: \StoredMedicationDoseChange.effectiveFrom, order: .reverse) private var doseChanges: [StoredMedicationDoseChange]
    @Query(sort: \StoredMedicationStock.lastUpdated, order: .reverse) private var stocks: [StoredMedicationStock]
    @State private var showingAddOptions = false
    @State private var selectedAddSelection: MedicationAddSelection?
    @State private var selectedLifecycleStatus: StoredMedicationLifecycleStatus = .active

    private var insight: AdherenceInsight {
        AdherenceInsightBuilder().build(
            scheduledDoses: tasks.map(\.coreScheduledDose),
            events: tasks.compactMap(\.coreDoseEvent),
            timeZone: TimeZone.current
        )
    }

    private var trendDashboard: MedicationTrendDashboard {
        medicationTrendDashboard(
            tasks: tasks,
            doseChanges: doseChanges,
            medications: medications
        )
    }

    private var lifecycleClassifier: MedicationLifecycleClassifier {
        MedicationLifecycleClassifier()
    }

    var body: some View {
        List {
            Section {
                MedicationDashboardSummary(
                    medicationCount: medications.count,
                    activeTaskCount: activeTaskCount,
                    lowStockCount: stockSummaries.filter(\.projection.needsRefillReminder).count,
                    completionRate: insight.completionRate,
                    trendDashboard: trendDashboard
                )
            }

            Section("药品分组") {
                MedicationLifecycleSelector(
                    selectedStatus: $selectedLifecycleStatus,
                    count: count(for:)
                )
            }

            Section(selectedLifecycleStatus.displayName) {
                let visibleMedications = medications.filter { displayLifecycleStatus(for: $0) == selectedLifecycleStatus }
                if visibleMedications.isEmpty {
                    Text("还没有添加药品。")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(visibleMedications) { medication in
                        NavigationLink {
                            MedicationDetailView(medication: medication)
                        } label: {
                            MedicationCardRow(
                                medication: medication,
                                plan: plans.first(where: { $0.medicationID == medication.id }),
                                taskCount: tasks.filter { $0.medicationID == medication.id }.count,
                                nextTask: nextTask(for: medication),
                                stockProjection: stockProjection(for: medication),
                                lifecycleClassification: lifecycleClassification(for: medication)
                            )
                        }
                    }
                }
            }
        }
        .navigationTitle("药品")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingAddOptions = true
                } label: {
                    Image(systemName: "plus")
                        .accessibilityLabel("添加药品")
                }
            }
        }
        .sheet(isPresented: $showingAddOptions) {
            MedicationAddOptionsSheet { option in
                showingAddOptions = false
                selectedAddSelection = MedicationAddSelection(option: option)
            }
            .presentationDetents([.height(360)])
            .presentationDragIndicator(.visible)
        }
        .sheet(item: $selectedAddSelection) { selection in
            AddMedicationView(option: selection.option)
        }
    }

    private func stockProjection(for medication: StoredMedication) -> MedicationStockProjection? {
        guard let stock = stocks.first(where: { $0.medicationID == medication.id }) else {
            return nil
        }
        let relatedTasks = tasks.filter { $0.medicationID == medication.id }
        return MedicationStockEstimator().project(
            stock: stock.coreStock,
            scheduledDoses: relatedTasks.map(\.coreScheduledDose),
            events: relatedTasks.compactMap(\.coreDoseEvent)
        )
    }

    private var activeTaskCount: Int {
        tasks.filter { task in
            Calendar.current.isDateInToday(task.dueAt) && (task.status == .pending || task.status == .delayed)
        }.count
    }

    private var stockSummaries: [MedicationStockSummary] {
        medications.compactMap { medication in
            guard let projection = stockProjection(for: medication) else {
                return nil
            }
            return MedicationStockSummary(medication: medication, projection: projection)
        }
        .sorted { lhs, rhs in
            if lhs.projection.needsRefillReminder != rhs.projection.needsRefillReminder {
                return lhs.projection.needsRefillReminder && !rhs.projection.needsRefillReminder
            }
            return lhs.medication.displayName < rhs.medication.displayName
        }
    }

    private func nextTask(for medication: StoredMedication) -> StoredDoseTask? {
        tasks
            .filter {
                $0.medicationID == medication.id
                    && Calendar.current.isDateInToday($0.dueAt)
                    && ($0.status == .pending || $0.status == .delayed)
            }
            .sorted { $0.dueAt < $1.dueAt }
            .first
    }

    private func count(for status: StoredMedicationLifecycleStatus) -> Int {
        medications.filter { displayLifecycleStatus(for: $0) == status }.count
    }

    private func lifecycleClassification(for medication: StoredMedication) -> MedicationLifecycleClassification {
        lifecycleClassifier.classify(
            medication: medication,
            plans: plans,
            tasks: tasks
        )
    }

    private func displayLifecycleStatus(for medication: StoredMedication) -> StoredMedicationLifecycleStatus {
        lifecycleClassification(for: medication).displayStatus
    }
}

private struct MedicationStockSummary: Identifiable {
    let id: UUID
    let medication: StoredMedication
    let projection: MedicationStockProjection

    init(medication: StoredMedication, projection: MedicationStockProjection) {
        self.id = medication.id
        self.medication = medication
        self.projection = projection
    }
}

private struct MedicationLifecycleSelector: View {
    @Binding var selectedStatus: StoredMedicationLifecycleStatus
    let count: (StoredMedicationLifecycleStatus) -> Int

    var body: some View {
        HStack(spacing: 8) {
            ForEach(StoredMedicationLifecycleStatus.allCases) { status in
                let isSelected = selectedStatus == status
                Button {
                    withAnimation(.snappy(duration: 0.22)) {
                        selectedStatus = status
                    }
                } label: {
                    VStack(spacing: 7) {
                        Image(systemName: lifecycleIconName(for: status))
                            .font(.headline.weight(.semibold))
                            .frame(height: 20)
                        Text("\(count(status))")
                            .font(.title2.weight(.bold))
                            .monospacedDigit()
                            .frame(height: 24)
                        Text(status.displayName)
                            .font(.caption.weight(.semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.72)
                            .allowsTightening(true)
                            .frame(maxWidth: .infinity)
                    }
                    .foregroundStyle(isSelected ? Color.white : badgeColor(for: status))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 9)
                    .frame(maxWidth: .infinity, minHeight: 86)
                    .background(
                        isSelected ? badgeColor(for: status) : badgeColor(for: status).opacity(0.10),
                        in: RoundedRectangle(cornerRadius: 8)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(isSelected ? Color.clear : badgeColor(for: status).opacity(0.22), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(status.displayName)，\(count(status)) 个药品")
            }
        }
        .padding(.vertical, 3)
    }

    private func lifecycleIconName(for status: StoredMedicationLifecycleStatus) -> String {
        switch status {
        case .active:
            "pills.fill"
        case .interrupted:
            "pause.circle.fill"
        case .archived:
            "archivebox.fill"
        }
    }
}

private struct MedicationAddOptionsSheet: View {
    @Environment(\.dismiss) private var dismiss
    let select: (MedicationAddOption) -> Void

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(MedicationAddWorkflow.options) { option in
                        Button {
                            guard !isAddOptionInDevelopment(option) else {
                                return
                            }
                            select(option)
                        } label: {
                            HStack(spacing: 14) {
                                Image(systemName: addOptionIconName(option))
                                    .font(.title3.weight(.semibold))
                                    .foregroundStyle(isAddOptionInDevelopment(option) ? Color.gray : Color.blue)
                                    .frame(width: 36, height: 36)
                                    .background(
                                        (isAddOptionInDevelopment(option) ? Color.secondary.opacity(0.12) : Color.blue.opacity(0.12)),
                                        in: RoundedRectangle(cornerRadius: 8)
                                    )
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(option.title)
                                        .font(.headline)
                                        .foregroundStyle(isAddOptionInDevelopment(option) ? .secondary : .primary)
                                    if !isAddOptionInDevelopment(option) {
                                        Text(addOptionSubtitle(option))
                                            .font(.footnote)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(2)
                                    }
                                }
                                Spacer()
                                if isAddOptionInDevelopment(option) {
                                    Image(systemName: "lock.fill")
                                        .font(.footnote.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                } else {
                                    Image(systemName: "chevron.right")
                                        .font(.footnote.weight(.bold))
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(.vertical, 4)
                            .contentShape(Rectangle())
                            .opacity(isAddOptionInDevelopment(option) ? 0.56 : 1)
                        }
                        .buttonStyle(.plain)
                        .disabled(isAddOptionInDevelopment(option))
                    }
                }
            }
            .navigationTitle("添加药品")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") {
                        dismiss()
                    }
                }
            }
        }
    }
}

private struct MedicationDashboardSummary: View {
    let medicationCount: Int
    let activeTaskCount: Int
    let lowStockCount: Int
    let completionRate: Double
    let trendDashboard: MedicationTrendDashboard

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("用药概览")
                        .font(.title2.weight(.semibold))
                    Text("药品、提醒、药盒和趋势概况")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "heart.text.square.fill")
                    .font(.title)
                    .foregroundStyle(.blue)
            }

            HStack(spacing: 10) {
                NavigationLink {
                    MedicationOverviewDetailView()
                } label: {
                    MedicationMetricTile(title: "药品", value: "\(medicationCount)", iconName: "pills.fill", tint: .blue)
                }
                .buttonStyle(.plain)

                NavigationLink {
                    MedicationPendingTasksDetailView()
                } label: {
                    MedicationMetricTile(title: "待处理", value: "\(activeTaskCount)", iconName: "bell.badge.fill", tint: .orange)
                }
                .buttonStyle(.plain)
            }
            HStack(spacing: 10) {
                NavigationLink {
                    MedicationStockOverviewView()
                } label: {
                    MedicationMetricTile(title: "药盒低量", value: "\(lowStockCount)", iconName: "shippingbox.fill", tint: lowStockCount > 0 ? .orange : .green)
                }
                .buttonStyle(.plain)

                NavigationLink {
                    MedicationTrendDetailView()
                } label: {
                    MedicationMetricTile(
                        title: "用药趋势",
                        value: trendDashboard.direction == .needsData ? "\(Int(completionRate * 100))%" : "\(Int((trendDashboard.overallScore * 100).rounded()))%",
                        iconName: trendDirectionIconName(trendDashboard.direction),
                        tint: trendDirectionTint(trendDashboard.direction)
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 8)
    }
}

private struct MedicationMetricTile: View {
    let title: String
    let value: String
    let iconName: String
    let tint: Color

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: iconName)
                .font(.headline)
                .foregroundStyle(tint)
                .frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.headline.weight(.semibold))
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 64)
        .background(tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
        .overlay(alignment: .trailing) {
            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(tint.opacity(0.48))
                .padding(.trailing, 9)
        }
    }
}

private struct MedicationOverviewDetailView: View {
    @Query(sort: \StoredMedication.displayName) private var medications: [StoredMedication]
    @Query(sort: \StoredMedicationPlan.createdAt) private var plans: [StoredMedicationPlan]
    @Query(sort: \StoredDoseTask.dueAt, order: .reverse) private var tasks: [StoredDoseTask]
    @Query(sort: \StoredMedicationStock.lastUpdated, order: .reverse) private var stocks: [StoredMedicationStock]

    var body: some View {
        List {
            Section("药品总览") {
                HStack(spacing: 10) {
                    MedicationOverviewStatCard(
                        title: "正在服用",
                        value: "\(count(for: .active))",
                        iconName: "pills.fill",
                        tint: .green
                    )
                    MedicationOverviewStatCard(
                        title: "需复核",
                        value: "\(count(for: .interrupted))",
                        iconName: "pause.circle.fill",
                        tint: .orange
                    )
                    MedicationOverviewStatCard(
                        title: "已归档",
                        value: "\(count(for: .archived))",
                        iconName: "archivebox.fill",
                        tint: .gray
                    )
                }
                .padding(.vertical, 4)
            }

            Section("药品详情") {
                if medications.isEmpty {
                    Text("还没有添加药品。")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(medications) { medication in
                        NavigationLink {
                            MedicationDetailView(medication: medication)
                        } label: {
                            MedicationOverviewMedicationRow(
                                medication: medication,
                                taskCount: tasks.filter { $0.medicationID == medication.id }.count,
                                stockProjection: stockProjection(for: medication)
                            )
                        }
                    }
                }
            }

            Section("说明") {
                Text("这里只展示药品结构、状态和库存概况；完整服药记录仍在“服药记录”入口查看。")
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("药品总览")
    }

    private func count(for status: StoredMedicationLifecycleStatus) -> Int {
        medications.filter { medication in
            MedicationLifecycleClassifier().classify(
                medication: medication,
                plans: plans,
                tasks: tasks
            ).displayStatus == status
        }.count
    }

    private func stockProjection(for medication: StoredMedication) -> MedicationStockProjection? {
        guard let stock = stocks.first(where: { $0.medicationID == medication.id }) else {
            return nil
        }
        let relatedTasks = tasks.filter { $0.medicationID == medication.id }
        return MedicationStockEstimator().project(
            stock: stock.coreStock,
            scheduledDoses: relatedTasks.map(\.coreScheduledDose),
            events: relatedTasks.compactMap(\.coreDoseEvent)
        )
    }
}

private struct MedicationOverviewStatCard: View {
    let title: String
    let value: String
    let iconName: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: iconName)
                .font(.headline.weight(.semibold))
                .foregroundStyle(tint)
            Text(value)
                .font(.title2.weight(.bold))
                .monospacedDigit()
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 92, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct MedicationOverviewMedicationRow: View {
    let medication: StoredMedication
    let taskCount: Int
    let stockProjection: MedicationStockProjection?

    var body: some View {
        HStack(spacing: 12) {
            MedicationPhotoView(photoData: medication.photoData, symbolName: medication.photoSymbolName, tint: .blue, size: 48)
            VStack(alignment: .leading, spacing: 5) {
                Text(medication.displayName)
                    .font(.headline)
                Text([medication.strength, medication.form].filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    Text("\(taskCount) 条记录")
                    if let stockProjection {
                        Text("药盒 \(formatDecimal(stockProjection.projectedRemainingQuantity)) \(localizedMedicationUnit(stockProjection.unit))")
                    } else {
                        Text("药盒未填写")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 5)
    }
}

private struct MedicationPendingTasksDetailView: View {
    @Query(sort: \StoredDoseTask.dueAt) private var tasks: [StoredDoseTask]
    @Query(sort: \StoredMedication.displayName) private var medications: [StoredMedication]

    private var pendingTasks: [StoredDoseTask] {
        tasks
            .filter { Calendar.current.isDateInToday($0.dueAt) && ($0.status == .pending || $0.status == .delayed) }
            .sorted { $0.dueAt < $1.dueAt }
    }

    var body: some View {
        List {
            Section("今日待处理") {
                if pendingTasks.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("今日暂无待处理", systemImage: "checkmark.circle.fill")
                            .font(.headline)
                            .foregroundStyle(.green)
                        Text("新的提醒会继续出现在今日页。")
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 8)
                } else {
                    ForEach(pendingTasks) { task in
                        if let medication = medication(for: task) {
                            NavigationLink {
                                MedicationDetailView(medication: medication)
                            } label: {
                                PendingTaskOverviewRow(task: task, medication: medication)
                            }
                        } else {
                            PendingTaskOverviewRow(task: task, medication: nil)
                        }
                    }
                }
            }

            Section("处理建议") {
                Text("待处理入口只用于定位今日任务；标记已服用、稍后或忽略请回到今日页完成，避免误触。")
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("今日待处理")
    }

    private func medication(for task: StoredDoseTask) -> StoredMedication? {
        medications.first { $0.id == task.medicationID }
    }
}

private struct PendingTaskOverviewRow: View {
    let task: StoredDoseTask
    let medication: StoredMedication?

    var body: some View {
        HStack(spacing: 12) {
            Text(AppFormatters.time.string(from: task.dueAt))
                .font(.headline.monospacedDigit())
                .foregroundStyle(task.status == .delayed ? .orange : .primary)
                .frame(width: 52, alignment: .leading)
            MedicationPhotoView(
                photoData: medication?.photoData,
                symbolName: medication?.photoSymbolName ?? "pills.fill",
                tint: task.status == .delayed ? .orange : .blue,
                size: 44
            )
            VStack(alignment: .leading, spacing: 4) {
                Text(medication?.displayName ?? "未知药品")
                    .font(.headline)
                Text("\(task.doseValue.formatted()) \(localizedMedicationUnit(task.doseUnit))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 5)
    }
}

private struct MedicationStockOverviewView: View {
    @Query(sort: \StoredMedication.displayName) private var medications: [StoredMedication]
    @Query(sort: \StoredDoseTask.dueAt, order: .reverse) private var tasks: [StoredDoseTask]
    @Query(sort: \StoredMedicationStock.lastUpdated, order: .reverse) private var stocks: [StoredMedicationStock]

    private var summaries: [MedicationStockSummary] {
        medications.compactMap { medication in
            guard let projection = stockProjection(for: medication) else {
                return nil
            }
            return MedicationStockSummary(medication: medication, projection: projection)
        }
        .sorted { lhs, rhs in
            if lhs.projection.needsRefillReminder != rhs.projection.needsRefillReminder {
                return lhs.projection.needsRefillReminder && !rhs.projection.needsRefillReminder
            }
            return lhs.medication.displayName < rhs.medication.displayName
        }
    }

    var body: some View {
        List {
            Section("药盒状态") {
                if summaries.isEmpty {
                    Text("还没有填写药盒库存。进入药品详情可补充剩余量和低库存阈值。")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(summaries) { summary in
                        NavigationLink {
                            MedicationDetailView(medication: summary.medication)
                        } label: {
                            StockOverviewRow(summary: summary)
                        }
                    }
                }
            }

            Section("库存规则") {
                Text("药盒会扣除已服用和已修正为服用的记录；预计可用天数来自近期真实记录，数据不足时只提示继续记录。")
                    .foregroundStyle(.secondary)
                Text("库存估算只提醒核对实物，不代表续方、购药或处方决策。")
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("药盒管理")
    }

    private func stockProjection(for medication: StoredMedication) -> MedicationStockProjection? {
        guard let stock = stocks.first(where: { $0.medicationID == medication.id }) else {
            return nil
        }
        let relatedTasks = tasks.filter { $0.medicationID == medication.id }
        return MedicationStockEstimator().project(
            stock: stock.coreStock,
            scheduledDoses: relatedTasks.map(\.coreScheduledDose),
            events: relatedTasks.compactMap(\.coreDoseEvent)
        )
    }
}

private struct StockOverviewRow: View {
    let summary: MedicationStockSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                MedicationPhotoView(
                    photoData: summary.medication.photoData,
                    symbolName: summary.medication.photoSymbolName,
                    tint: summary.projection.needsRefillReminder ? .orange : .green,
                    size: 48
                )
                VStack(alignment: .leading, spacing: 4) {
                    Text(summary.medication.displayName)
                        .font(.headline)
                    Text(stockRemainingText(summary.projection))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                StatusBadge(
                    text: summary.projection.needsRefillReminder ? "需核对" : "正常",
                    color: summary.projection.needsRefillReminder ? .orange : .green
                )
            }

            HStack(spacing: 8) {
                StockSmallMetric(
                    title: "日均消耗",
                    value: summary.projection.averageDailyConsumption.map {
                        "\(formatDecimal($0)) \(localizedMedicationUnit(summary.projection.unit))"
                    } ?? "待记录"
                )
                StockSmallMetric(
                    title: "预计可用",
                    value: summary.projection.estimatedDaysRemaining.map { "\($0) 天" } ?? "待记录"
                )
                StockSmallMetric(
                    title: "记录天数",
                    value: "\(summary.projection.trackedDayCount) 天"
                )
            }

            if let issue = summary.projection.issues.first {
                Text(issue.message)
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }
        }
        .padding(.vertical, 7)
    }
}

private struct StockSmallMetric: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.72)
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8))
    }
}

struct MedicationTrendDetailView: View {
    @Query(sort: \StoredDoseTask.dueAt, order: .reverse) private var tasks: [StoredDoseTask]
    @Query(sort: \StoredMedicationDoseChange.effectiveFrom, order: .reverse) private var doseChanges: [StoredMedicationDoseChange]

    private var trend: AdherenceTrendInsight {
        AdherenceTrendBuilder().build(
            scheduledDoses: tasks.map(\.coreScheduledDose),
            events: tasks.compactMap(\.coreDoseEvent),
            doseChanges: doseChanges.map(\.coreDoseChange),
            timeZone: TimeZone.current
        )
    }

    var body: some View {
        List {
            Section("服用趋势") {
                TrendSummaryCard(trend: trend)
            }

            Section("近期变化") {
                if trend.state == .insufficientData {
                    Text("当前已有 \(trend.daysAnalyzed) 天真实记录，达到 \(trend.minimumRequiredDays) 天后才生成趋势判断。")
                        .foregroundStyle(.secondary)
                } else {
                    MedicationTrendBars(points: trend.points.suffix(14).map { $0 })
                        .frame(height: 150)
                        .padding(.vertical, 8)
                    InfoRow(title: "最近完成率", value: "\(percentageText(trend.recentAverageCompletionRate))%")
                    if let previousAverage = trend.previousAverageCompletionRate {
                        InfoRow(title: "前一周期", value: "\(percentageText(previousAverage))%")
                    }
                    if let change = trend.changeFromPrevious {
                        InfoRow(title: "周期变化", value: trendChangeText(change))
                    }
                    InfoRow(title: "稳定度", value: "\(percentageText(trend.consistencyScore))%")
                    InfoRow(title: "已忽略率", value: "\(percentageText(trend.skippedRate))%")
                    InfoRow(title: "稍后率", value: "\(percentageText(trend.delayedRate))%")
                }
            }

            Section("模型说明") {
                Text(trend.supportingSummary)
                    .foregroundStyle(.secondary)
                if !trend.doseChangeSummary.isEmpty {
                    Text(trend.doseChangeSummary)
                        .foregroundStyle(.secondary)
                }
                Text(trend.safetyNote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("服用趋势")
    }
}

private struct TrendSummaryCard: View {
    let trend: AdherenceTrendInsight

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: trendIconName(trend.state))
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(trendTint(trend.state))
                    .frame(width: 42, height: 42)
                    .background(trendTint(trend.state).opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                VStack(alignment: .leading, spacing: 4) {
                    Text(trendStateTitle(trend.state))
                        .font(.title3.weight(.semibold))
                    Text(trend.message.isEmpty ? "继续记录后生成客观趋势。" : trend.message)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            ProgressView(value: trend.recentAverageCompletionRate)
                .tint(trendTint(trend.state))

            HStack {
                Text("\(trend.daysAnalyzed) 天记录")
                Spacer()
                Text("最近 \(percentageText(trend.recentAverageCompletionRate))%")
                    .monospacedDigit()
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 8)
    }
}

private struct MedicationTrendBars: View {
    let points: [AdherenceTrendPoint]

    var body: some View {
        HStack(alignment: .bottom, spacing: 5) {
            ForEach(Array(points.enumerated()), id: \.offset) { _, point in
                VStack(spacing: 6) {
                    GeometryReader { proxy in
                        let height = max(6, proxy.size.height * point.completionRate)
                        VStack {
                            Spacer(minLength: 0)
                            RoundedRectangle(cornerRadius: 4)
                                .fill(barColor(for: point.completionRate).gradient)
                                .frame(height: height)
                        }
                    }
                    .frame(height: 100)
                    Text("\(point.date.day)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .accessibilityLabel("近 \(points.count) 天服用完成率柱状图")
    }

    private func barColor(for completionRate: Double) -> Color {
        if completionRate >= 0.85 {
            return .green
        }
        if completionRate >= 0.6 {
            return .orange
        }
        return .red
    }
}

private struct MedicationCardRow: View {
    let medication: StoredMedication
    let plan: StoredMedicationPlan?
    let taskCount: Int
    let nextTask: StoredDoseTask?
    let stockProjection: MedicationStockProjection?
    let lifecycleClassification: MedicationLifecycleClassification

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 14) {
                MedicationPhotoView(photoData: medication.photoData, symbolName: medication.photoSymbolName, tint: .blue)
                VStack(alignment: .leading, spacing: 5) {
                    Text(medication.displayName)
                        .font(.headline)
                    Text([medication.strength, medication.form].filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    StatusBadgeFlow {
                        StatusBadge(text: medication.kindDisplayName, color: .green)
                        if medication.lifecycleStatus != .active || lifecycleClassification.shouldPromptReview {
                            StatusBadge(
                                text: lifecycleClassification.displayStatus.displayName,
                                color: badgeColor(for: lifecycleClassification.displayStatus)
                            )
                        }
                        if let stockProjection, stockProjection.needsRefillReminder {
                            StatusBadge(text: "药盒低量", color: .orange)
                        } else if stockProjection != nil {
                            StatusBadge(text: "药盒已记录", color: .green)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack(spacing: 10) {
                MedicationInlineStat(
                    iconName: "clock",
                    title: "下次",
                    value: nextTask.map { AppFormatters.time.string(from: $0.dueAt) } ?? "暂无"
                )
                MedicationInlineStat(
                    iconName: "list.bullet.clipboard",
                    title: "记录",
                    value: "\(taskCount)"
                )
                MedicationInlineStat(
                    iconName: "shippingbox",
                    title: "药盒",
                    value: stockProjection.map { formatDecimal($0.projectedRemainingQuantity) + " " + localizedMedicationUnit($0.unit) } ?? "未填"
                )
            }

            if let plan {
                Text(plan.timingSummary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            if lifecycleClassification.shouldPromptReview {
                Text(lifecycleClassification.explanation)
                    .font(.footnote)
                    .foregroundStyle(.orange)
                    .lineLimit(2)
            }
            if let stockProjection {
                Text(localizedStockProjectionMessage(stockProjection))
                    .font(.footnote)
                    .foregroundStyle(stockProjection.needsRefillReminder ? .orange : .secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 8)
    }
}

private struct MedicationInlineStat: View {
    let iconName: String
    let title: String
    let value: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: iconName)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.blue)
            VStack(alignment: .leading, spacing: 1) {
                Text(value)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(title)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct LifecycleReviewPanel: View {
    let medication: StoredMedication
    let classification: MedicationLifecycleClassification
    let markInterrupted: () -> Void
    let markActive: () -> Void
    let archive: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: iconName)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(tint)
                    .frame(width: 30, height: 30)
                    .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                VStack(alignment: .leading, spacing: 3) {
                    Text(classification.displayStatus.displayName)
                        .font(.headline)
                    Text(classification.explanation)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            if classification.shouldPromptReview {
                Button {
                    markInterrupted()
                } label: {
                    Label("确认标记为服用中断", systemImage: "pause.circle")
                }
            }

            if medication.lifecycleStatus == .interrupted {
                Button {
                    markActive()
                } label: {
                    Label("恢复为正在服用", systemImage: "play.circle")
                }
            }

            if medication.lifecycleStatus != .archived {
                Button(role: .destructive) {
                    archive()
                } label: {
                    Label("归档药物", systemImage: "archivebox")
                }
            }

            Text("状态用于列表归类和提醒管理，不代表停药、换药或处方建议；有疑问请咨询医生或药师。")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 6)
    }

    private var tint: Color {
        badgeColor(for: classification.displayStatus)
    }

    private var iconName: String {
        switch classification.displayStatus {
        case .active:
            "pills.fill"
        case .interrupted:
            "pause.circle.fill"
        case .archived:
            "archivebox.fill"
        }
    }
}

struct MedicationDetailView: View {
    @Environment(\.modelContext) private var modelContext
    let medication: StoredMedication
    @Query(sort: \StoredMedicationPlan.createdAt) private var plans: [StoredMedicationPlan]
    @Query(sort: \StoredDoseTask.dueAt, order: .reverse) private var tasks: [StoredDoseTask]
    @Query(sort: \StoredRiskCard.displayPriority) private var riskCards: [StoredRiskCard]
    @Query(sort: \StoredMedicationStock.lastUpdated, order: .reverse) private var stocks: [StoredMedicationStock]
    @Query(sort: \StoredMedicationLabel.importedAt, order: .reverse) private var labels: [StoredMedicationLabel]
    @Query(sort: \StoredMedicationDoseChange.effectiveFrom, order: .reverse) private var doseChanges: [StoredMedicationDoseChange]
    @State private var showingEditor = false
    @State private var showingStockEditor = false
    @State private var showingPlanEditor = false
    @State private var showingLabelImporter = false
    @State private var showingCameraPhotoCapture = false
    @State private var selectedDetailPhotoItem: PhotosPickerItem?
    @State private var photoStatusMessage = ""

    private var relatedPlans: [StoredMedicationPlan] {
        plans.filter { $0.medicationID == medication.id }
    }

    private var relatedTasks: [StoredDoseTask] {
        tasks.filter { $0.medicationID == medication.id }
    }

    private var relatedDoseChanges: [StoredMedicationDoseChange] {
        doseChanges.filter { $0.medicationID == medication.id }
    }

    private var relatedRiskCards: [StoredRiskCard] {
        riskCards.filter { $0.medicationID == medication.id }
    }

    private var relatedStock: StoredMedicationStock? {
        stocks.first { $0.medicationID == medication.id }
    }

    private var relatedLabel: StoredMedicationLabel? {
        labels.first { $0.medicationID == medication.id }
    }

    private var stockProjection: MedicationStockProjection? {
        guard let relatedStock else {
            return nil
        }
        return MedicationStockEstimator().project(
            stock: relatedStock.coreStock,
            scheduledDoses: relatedTasks.map(\.coreScheduledDose),
            events: relatedTasks.compactMap(\.coreDoseEvent)
        )
    }

    private var effectiveLabel: MedicationLabel? {
        relatedLabel?.coreLabel ?? DemoDrugLabels.all.first { $0.name == medicationDemoLabelLookupName(for: medication) }
    }

    private var labelSummary: ReadableLabelSummary? {
        effectiveLabel.map { ReadableLabelSummaryBuilder().build(from: $0) }
    }

    private var lifecycleClassification: MedicationLifecycleClassification {
        MedicationLifecycleClassifier().classify(
            medication: medication,
            plans: plans,
            tasks: tasks
        )
    }

    var body: some View {
        List {
            Section {
                HStack(alignment: .top, spacing: 16) {
                    MedicationPhotoView(photoData: medication.photoData, symbolName: medication.photoSymbolName, tint: .blue, size: 84)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(medication.displayName)
                            .font(.title2.weight(.semibold))
                        Text([medication.strength, medication.form].filter { !$0.isEmpty }.joined(separator: " · "))
                            .foregroundStyle(.secondary)
                        StatusBadgeFlow {
                            StatusBadge(text: medication.kindDisplayName, color: .green)
                            StatusBadge(
                                text: lifecycleClassification.displayStatus.displayName,
                                color: badgeColor(for: lifecycleClassification.displayStatus)
                            )
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        PhotosPicker(selection: $selectedDetailPhotoItem, matching: .images) {
                            Label(medication.photoData == nil ? "选择药品照片" : "更换药品照片", systemImage: "photo")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        Button {
                            showingCameraPhotoCapture = true
                        } label: {
                            Label("拍照上传", systemImage: "camera")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(!UIImagePickerController.isSourceTypeAvailable(.camera))
                        if medication.photoData != nil {
                            Button(role: .destructive) {
                                medication.photoData = nil
                                photoStatusMessage = "已清除药品照片。"
                                try? modelContext.save()
                            } label: {
                                Label("清除照片", systemImage: "trash")
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }
                }
                .padding(.vertical, 8)
                if !photoStatusMessage.isEmpty {
                    Text(photoStatusMessage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Text("药品照片只保存在本机，用于提醒时辅助识别实物；请按药盒或说明书核对。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("药品信息") {
                InfoRow(title: "规格", value: medication.strength.isEmpty ? "未填写" : medication.strength)
                InfoRow(title: "剂型", value: medication.form.isEmpty ? "未填写" : medication.form)
                InfoRow(title: "来源", value: sourceDisplayName(medication.inputSourceRaw))
                if let visibleNotes = userVisibleMedicationNotes(medication.notes) {
                    Text(visibleNotes)
                        .foregroundStyle(.secondary)
                }
            }

            Section("疗程与提醒") {
                if relatedPlans.isEmpty {
                    Text("尚未建立提醒计划。")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(relatedPlans) { plan in
                        VStack(alignment: .leading, spacing: 8) {
                            InfoRow(title: "剂量", value: "\(plan.doseValue.formatted()) \(localizedMedicationUnit(plan.doseUnit))")
                            InfoRow(title: "疗程", value: courseSummary(for: plan))
                            InfoRow(title: "时间", value: reminderSummary(for: plan, tasks: relatedTasks))
                            InfoRow(title: "时区规则", value: plan.timeZonePolicyRaw)
                            Text(plan.sourceNote)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 6)
                    }
                }
                Button {
                    showingPlanEditor = true
                } label: {
                    Label(relatedPlans.isEmpty ? "建立疗程与提醒" : "修改疗程与提醒", systemImage: "calendar.badge.clock")
                }
                Text("提醒计划必须由用户按说明书、医嘱或药师建议核对。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("剂量变化记录") {
                if relatedDoseChanges.isEmpty {
                    Text("暂无剂量变化记录。")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(Array(relatedDoseChanges.prefix(5))) { change in
                        MedicationDoseChangeRow(
                            change: change,
                            effectiveUntil: doseChangeEffectiveUntil(change, in: relatedDoseChanges)
                        )
                            .padding(.vertical, 5)
                    }
                }
                Text("剂量变化记录可帮助复诊时说明用药方案变化；这里只记录用户确认的信息，不生成诊断、处方或疗效判断。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("药盒库存") {
                if let stockProjection {
                    StockProjectionView(projection: stockProjection)
                } else {
                    Text("尚未填写药盒剩余量。")
                        .foregroundStyle(.secondary)
                }
                Button {
                    showingStockEditor = true
                } label: {
                    Label(relatedStock == nil ? "填写药盒" : "更新药盒", systemImage: "shippingbox")
                }
                Text("药盒库存估算只用于提醒你核对实物，不代表处方续药、购药或采购建议。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("近期记录") {
                if relatedTasks.isEmpty {
                    Text("暂无服药记录。")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(Array(relatedTasks.prefix(5))) { task in
                        HStack(spacing: 12) {
                            MedicationPhotoView(
                                photoData: medication.photoData,
                                symbolName: medication.photoSymbolName,
                                tint: task.status == .taken ? .green : .orange,
                                size: 44
                            )
                            VStack(alignment: .leading, spacing: 4) {
                                Text("\(task.doseValue.formatted()) \(localizedMedicationUnit(task.doseUnit))")
                                    .font(.headline)
                                Text("\(AppFormatters.day.string(from: task.dueAt)) · \(AppFormatters.time.string(from: task.dueAt))")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            StatusBadge(text: task.status.displayName, color: task.status == .taken ? .green : .orange)
                        }
                        .padding(.vertical, 6)
                    }
                }
            }

            Section("说明书与风险识别") {
                if let relatedLabel {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("已导入说明书", systemImage: "doc.text.magnifyingglass")
                            .font(.headline)
                        Text(relatedLabel.sourceTitle)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text("导入时间：\(AppFormatters.day.string(from: relatedLabel.importedAt)) \(AppFormatters.time.string(from: relatedLabel.importedAt))")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        if let reviewedAt = relatedLabel.lastRiskReviewAt {
                            Text("风险识别：\(AppFormatters.day.string(from: reviewedAt)) \(AppFormatters.time.string(from: reviewedAt)) 已更新")
                                .font(.footnote)
                                .foregroundStyle(.green)
                        }
                        StatusBadge(text: "\(relatedRiskCards.count) 条警示", color: relatedRiskCards.isEmpty ? .blue : .orange)
                    }
                    .padding(.vertical, 6)
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("建议导入说明书", systemImage: "doc.badge.plus")
                            .font(.headline)
                        Text("导入药盒或说明书照片后，App 会用本机 OCR 识别文字，并在本地生成可复核的风险卡片。")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 6)
                }

                Button {
                    showingLabelImporter = true
                } label: {
                    Label(relatedLabel == nil ? "导入说明书" : "重新导入说明书", systemImage: "camera.viewfinder")
                }

                if relatedLabel != nil {
                    Button {
                        rebuildLabelRisks()
                    } label: {
                        Label("重新识别风险", systemImage: "arrow.triangle.2.circlepath")
                    }
                }

                Text("说明书识别和风险卡片只用于风险提示与复诊沟通，不能替代医生或药师判断。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("风险与副作用") {
                if relatedRiskCards.isEmpty {
                    Text("暂无风险卡片。")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(Array(relatedRiskCards.prefix(4))) { card in
                        VStack(alignment: .leading, spacing: 7) {
                            Text(card.title)
                                .font(.headline)
                            Text(card.message)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            if !card.safetyNote.isEmpty {
                                Text(card.safetyNote)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 6)
                    }
                }

                if let labelSummary {
                    ForEach(labelSummary.cards.filter { $0.kind == .adverseReactions || $0.kind == .warnings }) { card in
                        VStack(alignment: .leading, spacing: 7) {
                            Text(card.heading)
                                .font(.headline)
                            Text(card.plainLanguageNote)
                                .font(.subheadline)
                            Text(card.sourceExcerpt)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 6)
                    }
                }
            }

            if let labelSummary {
                Section("说明书可读化") {
                    ForEach(labelSummary.cards) { card in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(card.heading)
                                .font(.headline)
                            Text(card.plainLanguageNote)
                                .font(.subheadline)
                            Text(card.sourceExcerpt)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 6)
                    }
                    Text(labelSummary.safetyNote)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            Section("高级操作") {
                LifecycleReviewPanel(
                    medication: medication,
                    classification: lifecycleClassification,
                    markInterrupted: {
                        medication.lifecycleStatus = .interrupted
                        try? modelContext.save()
                    },
                    markActive: {
                        medication.lifecycleStatus = .active
                        try? modelContext.save()
                    },
                    archive: {
                        medication.lifecycleStatus = .archived
                        try? modelContext.save()
                    }
                )
                Picker("药品状态", selection: Binding(
                    get: { medication.lifecycleStatus },
                    set: { newValue in
                        medication.lifecycleStatus = newValue
                        try? modelContext.save()
                    }
                )) {
                    ForEach(StoredMedicationLifecycleStatus.allCases) { status in
                        Text(status.displayName).tag(status)
                    }
                }
                Button {
                    showingEditor = true
                } label: {
                    Label("修改药品信息", systemImage: "pencil")
                }
                Text("修改后仍需按药盒、说明书、医嘱或药师建议核对。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("药品详情")
        .sheet(isPresented: $showingEditor) {
            EditMedicationView(medication: medication)
        }
        .sheet(isPresented: $showingStockEditor) {
            StockEditorView(medication: medication, stock: relatedStock)
        }
        .sheet(isPresented: $showingPlanEditor) {
            PlanEditorView(
                medication: medication,
                plan: relatedPlans.first,
                tasks: relatedTasks,
                doseChanges: relatedDoseChanges
            )
        }
        .sheet(isPresented: $showingLabelImporter) {
            MedicationLabelImporterView(
                medication: medication,
                existingLabel: relatedLabel,
                save: saveUserProvidedLabel
            )
        }
        .onChange(of: selectedDetailPhotoItem) { _, newItem in
            Task {
                await loadDetailPhoto(newItem)
            }
        }
        .sheet(isPresented: $showingCameraPhotoCapture) {
            CameraPhotoCaptureSheet { image in
                let data = image.jpegData(compressionQuality: 0.9) ?? Data()
                medication.photoData = normalizedPhotoData(data)
                photoStatusMessage = "药品照片已通过相机更新。"
                try? modelContext.save()
            }
        }
    }

    private func saveUserProvidedLabel(rawText: String, sourceTitle: String, confidence: Double) {
        let trimmedText = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else {
            return
        }
        let label = relatedLabel ?? StoredMedicationLabel(
            medicationID: medication.id,
            medicationName: medication.displayName,
            rawText: trimmedText,
            sourceTitle: sourceTitle,
            averageOCRConfidence: confidence
        )
        label.medicationName = medication.displayName
        label.rawText = trimmedText
        label.sourceTitle = sourceTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "用户导入说明书" : sourceTitle
        label.averageOCRConfidence = confidence
        label.importedAt = Date()
        if relatedLabel == nil {
            modelContext.insert(label)
        }
        MedicationRiskReviewService.rebuildUserLabelRisks(
            medication: medication,
            label: label,
            in: modelContext
        )
        try? modelContext.save()
    }

    private func rebuildLabelRisks() {
        guard let relatedLabel else {
            return
        }
        MedicationRiskReviewService.rebuildUserLabelRisks(
            medication: medication,
            label: relatedLabel,
            in: modelContext
        )
    }

    private func sourceDisplayName(_ rawValue: String) -> String {
        switch MedicationInputSource(rawValue: rawValue) {
        case .manual:
            "手动添加"
        case .barcode:
            "药盒条码"
        case .prescriptionImage:
            "医嘱/OCR"
        case .demoData:
            "本机记录"
        case nil:
            rawValue
        }
    }

    private func userVisibleMedicationNotes(_ notes: String) -> String? {
        let visibleLines = notes
            .split(whereSeparator: \.isNewline)
            .map(String.init)
            .filter { !$0.contains("演示") }
        let visibleText = visibleLines
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return visibleText.isEmpty ? nil : visibleText
    }

    private func loadDetailPhoto(_ item: PhotosPickerItem?) async {
        guard let item else {
            return
        }
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                await MainActor.run {
                    photoStatusMessage = "没有读取到图片数据。"
                }
                return
            }
            let normalizedData = normalizedPhotoData(data)
            await MainActor.run {
                medication.photoData = normalizedData
                photoStatusMessage = "药品照片已更新。"
                try? modelContext.save()
            }
        } catch {
            await MainActor.run {
                photoStatusMessage = "图片读取失败，请稍后重试。"
            }
        }
    }
}

private struct CameraPhotoCaptureSheet: UIViewControllerRepresentable {
    @Environment(\.dismiss) private var dismiss
    let onImage: (UIImage) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onImage: onImage, dismiss: dismiss)
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.cameraCaptureMode = .photo
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        let onImage: (UIImage) -> Void
        let dismiss: DismissAction

        init(onImage: @escaping (UIImage) -> Void, dismiss: DismissAction) {
            self.onImage = onImage
            self.dismiss = dismiss
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            if let image = info[.originalImage] as? UIImage {
                onImage(image)
            }
            dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            dismiss()
        }
    }
}

private struct AddMedicationView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @StateObject private var notificationService = NotificationService()
    let option: MedicationAddOption
    @State private var displayName = ""
    @State private var strength = ""
    @State private var form = ""
    @State private var doseValue = 1.0
    @State private var doseUnit = "片"
    @State private var initialStockQuantity = 0.0
    @State private var lowStockThreshold = 0.0
    @State private var stockUnit = "片"
    @State private var courseStartDate: Date
    @State private var hasCourseEndDate = false
    @State private var courseEndDate: Date
    @State private var reminderTimes: [Date]
    @State private var reminderDeliveryMethod: StoredReminderDeliveryMethod = .notification
    @State private var kind: MedicationKind
    @State private var importedText = ""
    @State private var barcodeValue = ""
    @State private var showingReviewAlert = false
    @State private var showingSaveConfirmation = false
    @State private var selectedImageItem: PhotosPickerItem?
    @State private var selectedMedicationPhotoItem: PhotosPickerItem?
    @State private var medicationPhotoData: Data?
    @State private var selectedPhotoSymbolName = "pills.fill"
    @State private var isAnalyzingImage = false
    @State private var visionStatusMessage = ""
    @State private var importReview: MedicationImportReview?
    @State private var recognizedBarcodes: [VisionBarcodeRecognitionResult] = []
    @State private var showingCameraScanner = false
    @State private var showingNameScanCamera = false

    private let commonStrengthPresets = ["100 mg", "200 mg", "500 mg", "1 g", "10 ml", "1 滴"]
    private let commonFormPresets = ["片剂", "胶囊", "颗粒剂", "口服液", "滴眼液", "外用", "吸入剂"]

    init(option: MedicationAddOption) {
        self.option = option
        let now = Date()
        _courseStartDate = State(initialValue: now)
        _courseEndDate = State(initialValue: Calendar.current.date(byAdding: .day, value: 30, to: now) ?? now)
        _reminderTimes = State(initialValue: [defaultReminderDate(hour: 21, minute: 0)])
        switch option.id {
        case .manual:
            _kind = State(initialValue: .overTheCounter)
            _selectedPhotoSymbolName = State(initialValue: "pills.fill")
        case .prescriptionDocumentOCR:
            _kind = State(initialValue: .prescription)
            _selectedPhotoSymbolName = State(initialValue: "cross.case.fill")
        case .barcodeScan:
            _kind = State(initialValue: .unknown)
            _selectedPhotoSymbolName = State(initialValue: "pills.fill")
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                if option.id != .manual {
                    Section(option.title) {
                        Text(option.description)
                            .foregroundStyle(.secondary)
                        Text(option.disclaimer)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                if option.id == .prescriptionDocumentOCR {
                    Section("医嘱识别草稿") {
                        PhotosPicker(selection: $selectedImageItem, matching: .images) {
                            Label("选择医嘱图片进行 OCR", systemImage: "photo.badge.magnifyingglass")
                        }
                        .buttonStyle(.borderedProminent)

                        if isAnalyzingImage {
                            ProgressView("正在识别图片")
                        }
                        if !visionStatusMessage.isEmpty {
                            Text(visionStatusMessage)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }

                        TextEditor(text: $importedText)
                            .frame(minHeight: 96)
                        ImportReviewSummaryView(review: importReview)
                        Label("OCR 结果和医疗 AI 复核内容都必须按原始医嘱二次确认。", systemImage: "doc.text.magnifyingglass")
                            .foregroundStyle(.secondary)
                    }
                }

                if option.id == .barcodeScan {
                    Section("条码录入草稿") {
                        Button {
                            showingCameraScanner = true
                        } label: {
                            Label("打开相机扫码", systemImage: "camera.viewfinder")
                        }
                        .buttonStyle(.borderedProminent)

                        PhotosPicker(selection: $selectedImageItem, matching: .images) {
                            Label("选择药盒条码图片识别", systemImage: "barcode.viewfinder")
                        }
                        .buttonStyle(.borderedProminent)

                        if isAnalyzingImage {
                            ProgressView("正在识别条码")
                        }
                        if !visionStatusMessage.isEmpty {
                            Text(visionStatusMessage)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        if !recognizedBarcodes.isEmpty {
                            ForEach(recognizedBarcodes) { barcode in
                                Button {
                                    barcodeValue = barcode.payload
                                    importReview = VisionImportService().makeBarcodeReview(barcode: barcode)
                                } label: {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(barcode.payload)
                                            .font(.body.monospaced())
                                        Text("\(barcode.symbology) · 置信度 \(Int(barcode.confidence * 100))%")
                                            .font(.footnote)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }

                        TextField("药盒条码或药品追溯码", text: $barcodeValue)
                            .textInputAutocapitalization(.never)
                        Button {
                            makeManualBarcodeReview()
                        } label: {
                            Text("生成条码草稿复核")
                        }
                        .disabled(barcodeValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        ImportReviewSummaryView(review: importReview)
                        Label("条码结果只辅助补全信息，可结合药品追溯码、GS1 或其他可靠数据源核对。", systemImage: "barcode.viewfinder")
                            .foregroundStyle(.secondary)
                    }
                }

                Section("药品信息") {
                    if option.id == .manual {
                        Button {
                            showingNameScanCamera = true
                        } label: {
                            Label("从 iPhone 扫描药名", systemImage: "camera.viewfinder")
                        }
                        .disabled(!UIImagePickerController.isSourceTypeAvailable(.camera))
                        if isAnalyzingImage {
                            ProgressView("正在扫描药名")
                        }
                        if !visionStatusMessage.isEmpty {
                            Text(visionStatusMessage)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                    TextField("药品名称", text: $displayName)
                        .textInputAutocapitalization(.words)
                    Picker("常用规格", selection: $strength) {
                        Text("未选择").tag("")
                        ForEach(commonStrengthPresets, id: \.self) { preset in
                            Text(preset).tag(preset)
                        }
                    }
                    TextField("规格，可按药盒补充", text: $strength)
                    Picker("常用剂型", selection: $form) {
                        Text("未选择").tag("")
                        ForEach(commonFormPresets, id: \.self) { preset in
                            Text(preset).tag(preset)
                        }
                    }
                    TextField("剂型，可按说明书补充", text: $form)
                    Picker("类型", selection: $kind) {
                        Text("非处方药").tag(MedicationKind.overTheCounter)
                        Text("处方药").tag(MedicationKind.prescription)
                        Text("待确认").tag(MedicationKind.unknown)
                    }
                    Stepper(value: $doseValue, in: 0.5...10, step: 0.5) {
                        Text("每次 \(doseValue.formatted()) \(localizedMedicationUnit(doseUnit))")
                    }
                    MedicationUnitPicker(title: "剂量单位", unit: $doseUnit)
                }

                Section("药品图片") {
                    Text("非必填；用于提醒时辅助识别实物。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    HStack(spacing: 14) {
                        MedicationPhotoView(
                            photoData: medicationPhotoData,
                            symbolName: selectedPhotoSymbolName,
                            tint: .blue
                        )
                        VStack(alignment: .leading, spacing: 8) {
                            MedicationIconPicker(symbolName: $selectedPhotoSymbolName)
                            PhotosPicker(selection: $selectedMedicationPhotoItem, matching: .images) {
                                Label(medicationPhotoData == nil ? "选择药品图片" : "更换药品图片", systemImage: "photo")
                            }
                            if medicationPhotoData != nil {
                                Button("清除当前图片") {
                                    medicationPhotoData = nil
                                    selectedMedicationPhotoItem = nil
                                }
                            }
                        }
                    }
                }

                Section("疗程与提醒") {
                    DatePicker("疗程开始", selection: $courseStartDate, displayedComponents: .date)
                    Toggle("设置疗程结束", isOn: $hasCourseEndDate)
                    if hasCourseEndDate {
                        DatePicker("疗程结束", selection: $courseEndDate, in: courseStartDate..., displayedComponents: .date)
                    }
                    ForEach(reminderTimes.indices, id: \.self) { index in
                        DatePicker(
                            "提醒 \(index + 1)",
                            selection: Binding(
                                get: { reminderTimes[index] },
                                set: { reminderTimes[index] = $0 }
                            ),
                            displayedComponents: .hourAndMinute
                        )
                    }
                    HStack {
                        Button {
                            reminderTimes.append(defaultReminderDate(hour: 21, minute: 0))
                        } label: {
                            Label("添加提醒", systemImage: "plus.circle")
                        }
                        .disabled(reminderTimes.count >= 4)
                        Spacer()
                        Button {
                            if reminderTimes.count > 1 {
                                reminderTimes.removeLast()
                            }
                        } label: {
                            Label("减少", systemImage: "minus.circle")
                        }
                        .disabled(reminderTimes.count <= 1)
                    }
                    Text("多次提醒只生成待确认计划；处方药必须按医嘱核对。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Picker("提醒方式", selection: $reminderDeliveryMethod) {
                        ForEach(StoredReminderDeliveryMethod.allCases) { method in
                            Text(method.displayName).tag(method)
                        }
                    }
                    Text(reminderDeliveryMethod.detailText)
                        .font(.footnote)
                        .foregroundStyle(reminderDeliveryMethod == .alarm ? .orange : .secondary)
                }

                Section("药盒库存") {
                    Text("非必填；填写后可提示核对药盒剩余量。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Stepper(value: $initialStockQuantity, in: 0...999, step: 1) {
                        Text("药盒剩余 \(initialStockQuantity.formatted()) \(localizedMedicationUnit(stockUnit))")
                    }
                    Stepper(value: $lowStockThreshold, in: 0...999, step: 1) {
                        Text("低库存阈值 \(lowStockThreshold.formatted()) \(localizedMedicationUnit(stockUnit))")
                    }
                    MedicationUnitPicker(title: "库存单位", unit: $stockUnit)
                    Text("药盒提醒只用于提示用户核对实物，不代表处方续药或采购建议。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("添加药品")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        showingSaveConfirmation = true
                    }
                    .disabled(!canSave)
                }
            }
            .onAppear {
                if option.id != .manual {
                    showingReviewAlert = true
                }
            }
            .alert(option.title, isPresented: $showingReviewAlert) {
                Button("我知道了", role: .cancel) {}
            } message: {
                Text(option.disclaimer)
            }
            .alert("确认保存药品？", isPresented: $showingSaveConfirmation) {
                Button("返回核对", role: .cancel) {}
                Button("已核对，保存") {
                    saveMedication()
                }
            } message: {
                Text("请确认药品名称、规格、剂型、剂量和提醒时间已按药盒、说明书、医生或药师建议核对。")
            }
            .sheet(isPresented: $showingCameraScanner) {
                BarcodeScannerSheet { payload, symbology in
                    let barcode = VisionBarcodeRecognitionResult(
                        payload: payload,
                        symbology: symbology,
                        confidence: 1
                    )
                    barcodeValue = payload
                    recognizedBarcodes = [barcode]
                    importReview = VisionImportService().makeBarcodeReview(barcode: barcode)
                    visionStatusMessage = "已通过相机识别条码，保存前仍需核对药盒与说明书。"
                }
            }
            .sheet(isPresented: $showingNameScanCamera) {
                CameraPhotoCaptureSheet { image in
                    let data = image.jpegData(compressionQuality: 0.9) ?? Data()
                    Task {
                        await scanMedicationName(from: data)
                    }
                }
            }
            .onChange(of: selectedImageItem) { _, newItem in
                Task {
                    await analyzeSelectedImage(newItem)
                }
            }
            .onChange(of: selectedMedicationPhotoItem) { _, newItem in
                Task {
                    await loadMedicationPhoto(newItem)
                }
            }
        }
    }

    private var canSave: Bool {
        !displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var inputSource: MedicationInputSource {
        switch option.id {
        case .manual:
            .manual
        case .prescriptionDocumentOCR:
            .prescriptionImage
        case .barcodeScan:
            .barcode
        }
    }

    private func makeManualBarcodeReview() {
        let trimmedBarcode = barcodeValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedBarcode.isEmpty else {
            return
        }
        let barcode = VisionBarcodeRecognitionResult(
            payload: trimmedBarcode,
            symbology: "manual",
            confidence: 1
        )
        recognizedBarcodes = [barcode]
        importReview = VisionImportService().makeBarcodeReview(barcode: barcode)
        visionStatusMessage = "已生成条码草稿，保存前仍需核对药盒与说明书。"
    }

    private func scanMedicationName(from data: Data) async {
        await MainActor.run {
            isAnalyzingImage = true
            visionStatusMessage = ""
        }
        defer {
            Task { @MainActor in
                isAnalyzingImage = false
            }
        }
        do {
            let result = try await VisionImportService().recognizePrescriptionText(from: data)
            let firstLine = result.text
                .split(separator: "\n")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .first { !$0.isEmpty }
            await MainActor.run {
                if let firstLine {
                    displayName = firstLine
                    visionStatusMessage = "已扫描到疑似药品名称，保存前请按药盒核对。"
                } else {
                    visionStatusMessage = "未识别到清晰药名，请手动输入。"
                }
            }
        } catch {
            await MainActor.run {
                visionStatusMessage = "扫描失败，请手动输入药品名称。"
            }
        }
    }

    private func saveMedication() {
        let noteParts = [
            option.disclaimer,
            importedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : "识别草稿：\(importedText.trimmingCharacters(in: .whitespacesAndNewlines))",
            barcodeValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : "条码草稿：\(barcodeValue.trimmingCharacters(in: .whitespacesAndNewlines))"
        ].compactMap { $0 }

        let medication = StoredMedication(
            displayName: displayName.trimmingCharacters(in: .whitespacesAndNewlines),
            kind: kind,
            form: form,
            strength: strength,
            inputSource: inputSource,
            photoSymbolName: selectedPhotoSymbolName,
            photoData: medicationPhotoData,
            notes: noteParts.joined(separator: "\n")
        )
        modelContext.insert(medication)

        let normalizedReminderTimes = normalizedReminderDates(reminderTimes)
        let plan = StoredMedicationPlan(
            medicationID: medication.id,
            doseValue: doseValue,
            doseUnit: doseUnit,
            timingSummary: reminderSummary(from: normalizedReminderTimes),
            timeZonePolicy: .localClock,
            sourceNote: "用户二次确认后建立；可在详情页继续修改疗程、提醒和库存。",
            requiresUserConfirmation: true,
            courseStartAt: courseStartDate,
            courseEndAt: hasCourseEndDate ? courseEndDate : nil,
            reminderTimesRaw: encodedReminderTimes(normalizedReminderTimes),
            reminderDelivery: reminderDeliveryMethod
        )
        modelContext.insert(plan)
        let reminderBatch = MedicationReminderTaskCoordinator().reconcilePlan(
            plan,
            medication: medication,
            in: modelContext
        )

        if initialStockQuantity > 0 || lowStockThreshold > 0 {
            modelContext.insert(StoredMedicationStock(
                medicationID: medication.id,
                remainingQuantity: initialStockQuantity,
                unit: stockUnit.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? doseUnit : stockUnit,
                lowStockThreshold: lowStockThreshold
            ))
        }

        try? modelContext.save()
        scheduleCreatedReminders(reminderBatch)
        dismiss()
    }

    private func scheduleCreatedReminders(_ batch: MedicationReminderScheduleBatch) {
        notificationService.cancelReminders(for: batch.cancelledTaskIDs)
        Task {
            await notificationService.scheduleReminderBatches([batch])
        }
    }

    private func analyzeSelectedImage(_ item: PhotosPickerItem?) async {
        guard let item else {
            return
        }
        isAnalyzingImage = true
        visionStatusMessage = ""
        importReview = nil
        recognizedBarcodes = []
        defer {
            isAnalyzingImage = false
        }

        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                throw VisionImportError.imageDataUnavailable
            }
            let service = VisionImportService()
            switch option.id {
            case .manual:
                visionStatusMessage = "手动添加不需要图片识别。"
            case .prescriptionDocumentOCR:
                let result = try await service.recognizePrescriptionText(from: data)
                importedText = result.text
                importReview = service.makePrescriptionReview(textResult: result)
                visionStatusMessage = "已识别 \(result.lineCount) 行文字，平均置信度 \(Int(result.averageConfidence * 100))%。"
            case .barcodeScan:
                let barcodes = try await service.recognizeBarcodes(from: data)
                recognizedBarcodes = barcodes
                if let first = barcodes.first {
                    barcodeValue = first.payload
                    importReview = service.makeBarcodeReview(barcode: first)
                    visionStatusMessage = "已识别 \(barcodes.count) 个条码，已填入第一个结果。"
                }
            }
        } catch {
            visionStatusMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func loadMedicationPhoto(_ item: PhotosPickerItem?) async {
        guard let item else {
            return
        }
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                return
            }
            medicationPhotoData = normalizedPhotoData(data)
        } catch {
            medicationPhotoData = nil
        }
    }
}

private struct StockProjectionView: View {
    let projection: MedicationStockProjection

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(formatDecimal(projection.projectedRemainingQuantity))
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(projection.needsRefillReminder ? .orange : .primary)
                Text(localizedMedicationUnit(projection.unit))
                    .foregroundStyle(.secondary)
                Spacer()
                StatusBadge(
                    text: projection.needsRefillReminder ? "需要核对药盒" : "药盒正常",
                    color: projection.needsRefillReminder ? .orange : .green
                )
            }
            Text(localizedStockProjectionMessage(projection))
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if !projection.issues.isEmpty {
                ForEach(Array(projection.issues.enumerated()), id: \.offset) { _, issue in
                    Text(issue.message)
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }
            }
        }
        .padding(.vertical, 6)
    }
}

private struct MedicationDoseChangeRow: View {
    let change: StoredMedicationDoseChange
    let effectiveUntil: Date?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.headline.weight(.semibold))
                .foregroundStyle(.purple)
                .frame(width: 34, height: 34)
                .background(Color.purple.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 5) {
                Text(doseChangeText)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(effectivePeriodText)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                if !change.note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(change.note)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
    }

    private var doseChangeText: String {
        let newDose = "\(change.newDoseValue.formatted()) \(localizedMedicationUnit(change.newDoseUnit))"
        guard let previousDoseValue = change.previousDoseValue else {
            return "初始剂量 \(newDose)"
        }
        let previousDose = "\(previousDoseValue.formatted()) \(localizedMedicationUnit(change.previousDoseUnit))"
        return "\(previousDose) 调整为 \(newDose)"
    }

    private var effectivePeriodText: String {
        doseChangeEffectivePeriodText(change: change, effectiveUntil: effectiveUntil)
    }
}

private struct MedicationLabelImporterView: View {
    @Environment(\.dismiss) private var dismiss
    let medication: StoredMedication
    let existingLabel: StoredMedicationLabel?
    let save: (String, String, Double) -> Void
    @State private var rawText: String
    @State private var sourceTitle: String
    @State private var confidence: Double
    @State private var selectedImageItem: PhotosPickerItem?
    @State private var isRecognizing = false
    @State private var statusMessage = ""
    @State private var showingCameraCapture = false

    init(
        medication: StoredMedication,
        existingLabel: StoredMedicationLabel?,
        save: @escaping (String, String, Double) -> Void
    ) {
        self.medication = medication
        self.existingLabel = existingLabel
        self.save = save
        _rawText = State(initialValue: existingLabel?.rawText ?? "")
        _sourceTitle = State(initialValue: existingLabel?.sourceTitle ?? "用户导入说明书")
        _confidence = State(initialValue: existingLabel?.averageOCRConfidence ?? 1)
    }

    private var canSave: Bool {
        !rawText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("导入方式") {
                    Button {
                        showingCameraCapture = true
                    } label: {
                        Label("拍摄说明书", systemImage: "camera")
                    }
                    .disabled(!UIImagePickerController.isSourceTypeAvailable(.camera))

                    PhotosPicker(selection: $selectedImageItem, matching: .images) {
                        Label("选择说明书图片", systemImage: "photo.on.rectangle")
                    }

                    TextField("来源标题", text: $sourceTitle)
                    if isRecognizing {
                        ProgressView("正在识别说明书文字")
                    }
                    if !statusMessage.isEmpty {
                        Text(statusMessage)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("识别文字") {
                    TextEditor(text: $rawText)
                        .frame(minHeight: 220)
                    Text("请按药盒或说明书原件核对文字；保存后 App 会在本地生成风险卡片。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("安全边界") {
                    Text("风险识别只根据导入文本做关键词和章节复核，不代表诊断、处方或剂量建议；如有不适、禁忌或相互作用疑问，应咨询医生或药师。")
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("导入说明书")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存并识别") {
                        save(rawText, sourceTitle, confidence)
                        dismiss()
                    }
                    .disabled(!canSave)
                }
            }
            .onChange(of: selectedImageItem) { _, newItem in
                Task {
                    await recognizeSelectedImage(newItem)
                }
            }
            .sheet(isPresented: $showingCameraCapture) {
                CameraPhotoCaptureSheet { image in
                    let data = image.jpegData(compressionQuality: 0.9) ?? Data()
                    Task {
                        await recognizeImageData(data)
                    }
                }
            }
        }
    }

    private func recognizeSelectedImage(_ item: PhotosPickerItem?) async {
        guard let item else {
            return
        }
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                throw VisionImportError.imageDataUnavailable
            }
            await recognizeImageData(data)
        } catch {
            await MainActor.run {
                statusMessage = "图片读取失败，请重试或直接粘贴说明书文字。"
            }
        }
    }

    private func recognizeImageData(_ data: Data) async {
        await MainActor.run {
            isRecognizing = true
            statusMessage = ""
        }
        defer {
            Task { @MainActor in
                isRecognizing = false
            }
        }
        do {
            let result = try await VisionImportService().recognizePrescriptionText(from: data)
            await MainActor.run {
                rawText = result.text
                confidence = result.averageConfidence
                sourceTitle = sourceTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "说明书 OCR 导入" : sourceTitle
                statusMessage = "已识别 \(result.lineCount) 行文字，保存前请核对原文。"
            }
        } catch {
            await MainActor.run {
                statusMessage = (error as? LocalizedError)?.errorDescription ?? "未识别到清晰文字，请重试或直接粘贴。"
            }
        }
    }
}

private func localizedStockProjectionMessage(_ projection: MedicationStockProjection) -> String {
    let remaining = formatDecimal(projection.projectedRemainingQuantity)
    let unit = localizedMedicationUnit(projection.unit)
    if projection.needsRefillReminder {
        return "库存已达到低库存阈值，估算剩余 \(remaining) \(unit)，请及时核对实物库存。"
    }
    return "库存暂未达到低库存阈值，估算剩余 \(remaining) \(unit)。"
}

private struct StockEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    let medication: StoredMedication
    let stock: StoredMedicationStock?
    @State private var remainingQuantity: Double
    @State private var lowStockThreshold: Double
    @State private var unit: String

    init(medication: StoredMedication, stock: StoredMedicationStock?) {
        self.medication = medication
        self.stock = stock
        _remainingQuantity = State(initialValue: stock?.remainingQuantity ?? 0)
        _lowStockThreshold = State(initialValue: stock?.lowStockThreshold ?? 0)
        _unit = State(initialValue: localizedMedicationUnit(stock?.unit ?? "片"))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(medication.displayName) {
                    Stepper(value: $remainingQuantity, in: 0...9999, step: 1) {
                        Text("药盒剩余 \(remainingQuantity.formatted()) \(localizedMedicationUnit(unit))")
                    }
                    Stepper(value: $lowStockThreshold, in: 0...9999, step: 1) {
                        Text("低库存阈值 \(lowStockThreshold.formatted()) \(localizedMedicationUnit(unit))")
                    }
                    MedicationUnitPicker(title: "单位", unit: $unit)
                }

                Section("说明") {
                    Text("药盒估算会扣除已服用或已修正为服用的记录；单位不一致时会提示复核。")
                        .foregroundStyle(.secondary)
                    Text("此功能只用于依从性提醒和复诊沟通，不代表续方、购药或处方决策。")
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("药盒库存")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        save()
                    }
                    .disabled(unit.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private func save() {
        if let stock {
            stock.remainingQuantity = remainingQuantity
            stock.lowStockThreshold = lowStockThreshold
            stock.unit = unit.trimmingCharacters(in: .whitespacesAndNewlines)
            stock.lastUpdated = Date()
        } else {
            modelContext.insert(StoredMedicationStock(
                medicationID: medication.id,
                remainingQuantity: remainingQuantity,
                unit: unit.trimmingCharacters(in: .whitespacesAndNewlines),
                lowStockThreshold: lowStockThreshold
            ))
        }
        try? modelContext.save()
        dismiss()
    }
}

private struct PlanEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @StateObject private var notificationService = NotificationService()
    let medication: StoredMedication
    let plan: StoredMedicationPlan?
    let tasks: [StoredDoseTask]
    let doseChanges: [StoredMedicationDoseChange]
    @State private var doseValue: Double
    @State private var doseUnit: String
    @State private var doseEffectiveFrom: Date
    @State private var doseChangeNote: String
    @State private var courseStartDate: Date
    @State private var hasCourseEndDate: Bool
    @State private var courseEndDate: Date
    @State private var reminderTimes: [Date]
    @State private var reminderDeliveryMethod: StoredReminderDeliveryMethod
    @State private var sourceNote: String

    init(
        medication: StoredMedication,
        plan: StoredMedicationPlan?,
        tasks: [StoredDoseTask],
        doseChanges: [StoredMedicationDoseChange]
    ) {
        self.medication = medication
        self.plan = plan
        self.tasks = tasks
        self.doseChanges = doseChanges
        let planTasks = plan.map { selectedPlan in tasks.filter { $0.planID == selectedPlan.id } } ?? tasks
        let now = Date()
        let startDate = plan?.courseStartAt ?? planTasks.first?.dueAt ?? now
        let endDate = plan?.courseEndAt ?? Calendar.current.date(byAdding: .day, value: 30, to: startDate) ?? startDate
        _doseValue = State(initialValue: plan?.doseValue ?? planTasks.first?.doseValue ?? 1)
        _doseUnit = State(initialValue: localizedMedicationUnit(plan?.doseUnit ?? planTasks.first?.doseUnit ?? "片"))
        _doseEffectiveFrom = State(initialValue: Calendar.current.startOfDay(for: plan == nil ? startDate : now))
        _doseChangeNote = State(initialValue: "")
        _courseStartDate = State(initialValue: startDate)
        _hasCourseEndDate = State(initialValue: plan?.courseEndAt != nil)
        _courseEndDate = State(initialValue: endDate)
        _reminderTimes = State(initialValue: reminderDates(for: plan, tasks: planTasks))
        _reminderDeliveryMethod = State(initialValue: plan?.reminderDeliveryMethod ?? .notification)
        _sourceNote = State(initialValue: plan?.sourceNote ?? "用户二次确认后建立；可在详情页继续修改疗程、提醒和库存。")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(medication.displayName) {
                    Stepper(value: $doseValue, in: 0.5...20, step: 0.5) {
                        Text("每次 \(doseValue.formatted()) \(localizedMedicationUnit(doseUnit))")
                    }
                    MedicationUnitPicker(title: "剂量单位", unit: $doseUnit)
                    DatePicker("剂量生效日期", selection: $doseEffectiveFrom, displayedComponents: .date)
                    Text("用于记录从哪天开始剂量发生变化；不会生成诊断、处方或剂量建议。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("疗程") {
                    DatePicker("开始日期", selection: $courseStartDate, displayedComponents: .date)
                    Toggle("设置结束日期", isOn: $hasCourseEndDate)
                    if hasCourseEndDate {
                        DatePicker("结束日期", selection: $courseEndDate, in: courseStartDate..., displayedComponents: .date)
                    }
                }

                Section("提醒时间") {
                    ForEach(reminderTimes.indices, id: \.self) { index in
                        DatePicker(
                            "提醒 \(index + 1)",
                            selection: Binding(
                                get: { reminderTimes[index] },
                                set: { reminderTimes[index] = $0 }
                            ),
                            displayedComponents: .hourAndMinute
                        )
                    }
                    HStack {
                        Button {
                            reminderTimes.append(defaultReminderDate(hour: 21, minute: 0))
                        } label: {
                            Label("添加提醒", systemImage: "plus.circle")
                        }
                        .disabled(reminderTimes.count >= 4)
                        Spacer()
                        Button {
                            if reminderTimes.count > 1 {
                                reminderTimes.removeLast()
                            }
                        } label: {
                            Label("减少", systemImage: "minus.circle")
                        }
                        .disabled(reminderTimes.count <= 1)
                    }
                    Picker("提醒方式", selection: $reminderDeliveryMethod) {
                        ForEach(StoredReminderDeliveryMethod.allCases) { method in
                            Text(method.displayName).tag(method)
                        }
                    }
                    Text(reminderDeliveryMethod.detailText)
                        .font(.footnote)
                        .foregroundStyle(reminderDeliveryMethod == .alarm ? .orange : .secondary)
                }

                Section("来源说明") {
                    TextEditor(text: $sourceNote)
                        .frame(minHeight: 90)
                    Text("处方药提醒必须按医嘱核对；非处方药也应按说明书、医生或药师建议确认。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("剂量变化备注") {
                    TextEditor(text: $doseChangeNote)
                        .frame(minHeight: 70)
                    Text("可记录“按复诊结果调整”“更换规格后调整”等原因，便于在周历、月历和复诊资料中回看。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("疗程与提醒")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        save()
                    }
                    .disabled(doseUnit.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || reminderTimes.isEmpty)
                }
            }
        }
    }

    private func save() {
        let normalizedTimes = normalizedReminderDates(reminderTimes)
        let normalizedDoseUnit = doseUnit.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedEffectiveFrom = Calendar.current.startOfDay(for: doseEffectiveFrom)
        let previousDoseValue = plan?.doseValue
        let previousDoseUnit = plan.map { localizedMedicationUnit($0.doseUnit) }
        let isDoseChanged = previousDoseValue.map {
            abs($0 - doseValue) > 0.0001 || previousDoseUnit != normalizedDoseUnit
        } ?? true
        let targetPlan: StoredMedicationPlan
        if let plan {
            plan.doseValue = doseValue
            plan.doseUnit = normalizedDoseUnit
            plan.timingSummary = reminderSummary(from: normalizedTimes)
            plan.sourceNote = sourceNote
            plan.courseStartAt = courseStartDate
            plan.courseEndAt = hasCourseEndDate ? courseEndDate : nil
            plan.reminderTimesRaw = encodedReminderTimes(normalizedTimes)
            plan.reminderDeliveryMethod = reminderDeliveryMethod
            targetPlan = plan
        } else {
            let newPlan = StoredMedicationPlan(
                medicationID: medication.id,
                doseValue: doseValue,
                doseUnit: normalizedDoseUnit,
                timingSummary: reminderSummary(from: normalizedTimes),
                timeZonePolicy: .localClock,
                sourceNote: sourceNote,
                requiresUserConfirmation: true,
                courseStartAt: courseStartDate,
                courseEndAt: hasCourseEndDate ? courseEndDate : nil,
                reminderTimesRaw: encodedReminderTimes(normalizedTimes),
                reminderDelivery: reminderDeliveryMethod
            )
            modelContext.insert(newPlan)
            targetPlan = newPlan
        }

        let reminderBatch = MedicationReminderTaskCoordinator().reconcilePlan(
            targetPlan,
            medication: medication,
            in: modelContext
        )
        if isDoseChanged {
            insertDoseChange(
                planID: targetPlan.id,
                previousDoseValue: previousDoseValue,
                previousDoseUnit: previousDoseUnit ?? "",
                newDoseValue: doseValue,
                newDoseUnit: normalizedDoseUnit,
                effectiveFrom: normalizedEffectiveFrom
            )
        }
        applyDoseChangeToOpenTasks(
            planID: targetPlan.id,
            previousDoseValue: previousDoseValue,
            previousDoseUnit: previousDoseUnit,
            newDoseValue: doseValue,
            newDoseUnit: normalizedDoseUnit,
            effectiveFrom: normalizedEffectiveFrom
        )

        try? modelContext.save()
        rescheduleReminders(reminderBatch)
        dismiss()
    }

    private func insertDoseChange(
        planID: UUID,
        previousDoseValue: Double?,
        previousDoseUnit: String,
        newDoseValue: Double,
        newDoseUnit: String,
        effectiveFrom: Date
    ) {
        let trimmedNote = doseChangeNote.trimmingCharacters(in: .whitespacesAndNewlines)
        let note = trimmedNote.isEmpty
            ? (previousDoseValue == nil ? "初始剂量记录，用户已确认。" : "用户确认后修改剂量；请按医嘱、说明书或药师建议核对。")
            : trimmedNote
        modelContext.insert(StoredMedicationDoseChange(
            medicationID: medication.id,
            planID: planID,
            previousDoseValue: previousDoseValue,
            previousDoseUnit: previousDoseUnit,
            newDoseValue: newDoseValue,
            newDoseUnit: newDoseUnit,
            effectiveFrom: effectiveFrom,
            note: note
        ))
    }

    private func applyDoseChangeToOpenTasks(
        planID: UUID,
        previousDoseValue: Double?,
        previousDoseUnit: String?,
        newDoseValue: Double,
        newDoseUnit: String,
        effectiveFrom: Date
    ) {
        let startOfEffectiveDay = Calendar.current.startOfDay(for: effectiveFrom)
        let currentTasks = (try? modelContext.fetch(FetchDescriptor<StoredDoseTask>())) ?? tasks
        for task in currentTasks where task.planID == planID {
            guard task.status == .pending || task.status == .delayed else {
                continue
            }
            if task.dueAt >= startOfEffectiveDay {
                task.doseValue = newDoseValue
                task.doseUnit = newDoseUnit
            } else if let previousDoseValue, let previousDoseUnit {
                task.doseValue = previousDoseValue
                task.doseUnit = previousDoseUnit
            }
        }
    }

    private func rescheduleReminders(_ batch: MedicationReminderScheduleBatch) {
        notificationService.cancelReminders(for: batch.cancelledTaskIDs)
        Task {
            await notificationService.scheduleReminderBatches([batch])
        }
    }
}

private struct ImportReviewSummaryView: View {
    let review: MedicationImportReview?

    var body: some View {
        if let review {
            VStack(alignment: .leading, spacing: 8) {
                Label(review.canCreateMedication ? "草稿可继续补全" : "草稿仍需补全", systemImage: review.canCreateMedication ? "checkmark.circle" : "exclamationmark.triangle")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(review.canCreateMedication ? .green : .orange)
                ForEach(Array(review.issues.enumerated()), id: \.offset) { _, issue in
                    Text(issue.message)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Text("保存前仍需用户手动核对并勾选二次确认。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 6)
        }
    }
}

private struct EditMedicationView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    let medication: StoredMedication
    @State private var displayName: String
    @State private var strength: String
    @State private var form: String
    @State private var kind: MedicationKind
    @State private var photoData: Data?
    @State private var photoSymbolName: String
    @State private var selectedMedicationPhotoItem: PhotosPickerItem?
    @State private var notes: String

    init(medication: StoredMedication) {
        self.medication = medication
        _displayName = State(initialValue: medication.displayName)
        _strength = State(initialValue: medication.strength)
        _form = State(initialValue: medication.form)
        _kind = State(initialValue: MedicationKind(rawValue: medication.kindRaw) ?? .unknown)
        _photoData = State(initialValue: medication.photoData)
        _photoSymbolName = State(initialValue: medication.photoSymbolName)
        _notes = State(initialValue: medication.notes)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("药品信息") {
                    TextField("药品名称", text: $displayName)
                    TextField("规格", text: $strength)
                    TextField("剂型", text: $form)
                    Picker("类型", selection: $kind) {
                        Text("非处方药").tag(MedicationKind.overTheCounter)
                        Text("处方药").tag(MedicationKind.prescription)
                        Text("待确认").tag(MedicationKind.unknown)
                    }
                }

                Section("药品图片") {
                    HStack(spacing: 14) {
                        MedicationPhotoView(photoData: photoData, symbolName: photoSymbolName, tint: .blue)
                        VStack(alignment: .leading, spacing: 8) {
                            MedicationIconPicker(symbolName: $photoSymbolName)
                            PhotosPicker(selection: $selectedMedicationPhotoItem, matching: .images) {
                                Label(photoData == nil ? "选择药品图片" : "更换药品图片", systemImage: "photo")
                            }
                            if photoData != nil {
                                Button("清除当前图片") {
                                    photoData = nil
                                    selectedMedicationPhotoItem = nil
                                }
                            }
                        }
                    }
                    Text("图片只保存在本机，用于提醒时辅助识别药品实物。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("备注") {
                    TextEditor(text: $notes)
                        .frame(minHeight: 120)
                }
            }
            .navigationTitle("修改药品")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        medication.displayName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
                        medication.strength = strength
                        medication.form = form
                        medication.kindRaw = kind.rawValue
                        medication.photoSymbolName = photoSymbolName
                        medication.photoData = photoData
                        medication.notes = notes
                        try? modelContext.save()
                        dismiss()
                    }
                    .disabled(displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onChange(of: selectedMedicationPhotoItem) { _, newItem in
                Task {
                    await loadMedicationPhoto(newItem)
                }
            }
        }
    }

    private func loadMedicationPhoto(_ item: PhotosPickerItem?) async {
        guard let item else {
            return
        }
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                return
            }
            photoData = normalizedPhotoData(data)
        } catch {
            photoData = nil
        }
    }
}

private struct MedicationAddSelection: Identifiable {
    var option: MedicationAddOption
    var id: String { option.id.rawValue }
}

private func isAddOptionInDevelopment(_ option: MedicationAddOption) -> Bool {
    option.id == .prescriptionDocumentOCR || option.id == .barcodeScan
}

private func addOptionTitle(_ option: MedicationAddOption) -> String {
    option.title
}

private func addOptionSubtitle(_ option: MedicationAddOption) -> String {
    switch option.id {
    case .manual:
        "逐项填写药名、剂量、疗程和提醒。"
    case .prescriptionDocumentOCR:
        "识别医嘱图片后生成待确认草稿。"
    case .barcodeScan:
        "扫描药盒条码后辅助补全信息。"
    }
}

private func addOptionIconName(_ option: MedicationAddOption) -> String {
    switch option.id {
    case .manual:
        "square.and.pencil"
    case .prescriptionDocumentOCR:
        "doc.viewfinder"
    case .barcodeScan:
        "barcode.viewfinder"
    }
}

private func badgeColor(for status: StoredMedicationLifecycleStatus) -> Color {
    switch status {
    case .active:
        .green
    case .interrupted:
        .orange
    case .archived:
        .gray
    }
}

func trendStateTitle(_ state: AdherenceTrendState) -> String {
    switch state {
    case .insufficientData:
        "数据不足"
    case .improving:
        "正在改善"
    case .stable:
        "趋势平稳"
    case .declining:
        "需要关注"
    }
}

func trendTint(_ state: AdherenceTrendState) -> Color {
    switch state {
    case .insufficientData:
        .gray
    case .improving:
        .green
    case .stable:
        .blue
    case .declining:
        .orange
    }
}

func trendIconName(_ state: AdherenceTrendState) -> String {
    switch state {
    case .insufficientData:
        "chart.bar.xaxis"
    case .improving:
        "chart.line.uptrend.xyaxis"
    case .stable:
        "equal.circle.fill"
    case .declining:
        "chart.line.downtrend.xyaxis"
    }
}

private func percentageText(_ value: Double) -> String {
    "\(Int((value * 100).rounded()))"
}

private func trendChangeText(_ value: Double) -> String {
    let points = Int((abs(value) * 100).rounded())
    if value > 0 {
        return "上升 \(points) 个百分点"
    }
    if value < 0 {
        return "下降 \(points) 个百分点"
    }
    return "无明显变化"
}

private func stockRemainingText(_ projection: MedicationStockProjection) -> String {
    let remaining = "\(formatDecimal(projection.projectedRemainingQuantity)) \(localizedMedicationUnit(projection.unit))"
    if let days = projection.estimatedDaysRemaining {
        return "估算剩余 \(remaining) · 约 \(days) 天"
    }
    return "估算剩余 \(remaining)"
}

private func formatDecimal(_ value: Decimal) -> String {
    let number = NSDecimalNumber(decimal: value)
    let formatter = NumberFormatter()
    formatter.minimumFractionDigits = 0
    formatter.maximumFractionDigits = 2
    return formatter.string(from: number) ?? "\(value)"
}

private func courseSummary(for plan: StoredMedicationPlan) -> String {
    let start = plan.courseStartAt.map { AppFormatters.day.string(from: $0) } ?? "未填写开始日期"
    let end = plan.courseEndAt.map { AppFormatters.day.string(from: $0) } ?? "未设置结束日期"
    return "\(start) 至 \(end)"
}

private func reminderSummary(for plan: StoredMedicationPlan, tasks: [StoredDoseTask]) -> String {
    reminderSummary(from: reminderDates(for: plan, tasks: tasks.filter { $0.planID == plan.id }))
}

private func reminderDates(for plan: StoredMedicationPlan?, tasks: [StoredDoseTask]) -> [Date] {
    let storedDates = plan?.reminderTimesRaw?
        .split(separator: ",")
        .compactMap { reminderDate(from: String($0)) } ?? []
    if !storedDates.isEmpty {
        return normalizedReminderDates(storedDates)
    }
    let taskDates = tasks.map(\.dueAt)
    if !taskDates.isEmpty {
        return normalizedReminderDates(taskDates)
    }
    return [defaultReminderDate(hour: 21, minute: 0)]
}

private func reminderSummary(from dates: [Date]) -> String {
    let times = normalizedReminderDates(dates).map { AppFormatters.time.string(from: $0) }
    guard !times.isEmpty else {
        return "未设置提醒时间"
    }
    return "每日 " + times.joined(separator: "、")
}

private func encodedReminderTimes(_ dates: [Date]) -> String {
    normalizedReminderDates(dates)
        .map { AppFormatters.time.string(from: $0) }
        .joined(separator: ",")
}

private func normalizedReminderDates(_ dates: [Date]) -> [Date] {
    var seen: Set<String> = []
    return dates
        .map { defaultReminderDate(hour: Calendar.current.component(.hour, from: $0), minute: Calendar.current.component(.minute, from: $0)) }
        .sorted { $0 < $1 }
        .filter { date in
            let key = AppFormatters.time.string(from: date)
            if seen.contains(key) {
                return false
            }
            seen.insert(key)
            return true
        }
}

private func reminderDate(from rawValue: String) -> Date? {
    let parts = rawValue.split(separator: ":")
    guard parts.count == 2, let hour = Int(parts[0]), let minute = Int(parts[1]) else {
        return nil
    }
    return defaultReminderDate(hour: hour, minute: minute)
}

private func defaultReminderDate(hour: Int, minute: Int) -> Date {
    Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: Date()) ?? Date()
}

private func doseChangeEffectiveUntil(
    _ change: StoredMedicationDoseChange,
    in changes: [StoredMedicationDoseChange]
) -> Date? {
    let calendar = Calendar.current
    let currentStart = calendar.startOfDay(for: change.effectiveFrom)
    let nextChange = changes
        .filter {
            $0.id != change.id
                && $0.medicationID == change.medicationID
                && doseChangePlanMatches($0, change)
                && $0.effectiveFrom > change.effectiveFrom
        }
        .min { $0.effectiveFrom < $1.effectiveFrom }

    guard let nextStart = nextChange.map({ calendar.startOfDay(for: $0.effectiveFrom) }) else {
        return nil
    }
    guard nextStart > currentStart else {
        return currentStart
    }
    return calendar.date(byAdding: .day, value: -1, to: nextStart)
}

private func doseChangePlanMatches(_ first: StoredMedicationDoseChange, _ second: StoredMedicationDoseChange) -> Bool {
    guard let firstPlanID = first.planID, let secondPlanID = second.planID else {
        return true
    }
    return firstPlanID == secondPlanID
}

private func doseChangeEffectivePeriodText(change: StoredMedicationDoseChange, effectiveUntil: Date?) -> String {
    let startText = AppFormatters.day.string(from: change.effectiveFrom)
    guard let effectiveUntil else {
        return "生效阶段：\(startText) 至今"
    }
    if Calendar.current.isDate(effectiveUntil, inSameDayAs: change.effectiveFrom) {
        return "生效阶段：\(startText) 当天，之后有新的剂量记录"
    }
    return "生效阶段：\(startText) 至 \(AppFormatters.day.string(from: effectiveUntil))"
}

private func scheduledDate(on day: Date, matching time: Date) -> Date {
    let calendar = Calendar.current
    let dateComponents = calendar.dateComponents([.year, .month, .day], from: day)
    let timeComponents = calendar.dateComponents([.hour, .minute], from: time)
    var merged = DateComponents()
    merged.year = dateComponents.year
    merged.month = dateComponents.month
    merged.day = dateComponents.day
    merged.hour = timeComponents.hour
    merged.minute = timeComponents.minute
    merged.second = 0
    return calendar.date(from: merged) ?? time
}

private func normalizedPhotoData(_ data: Data) -> Data {
    guard let image = UIImage(data: data) else {
        return data
    }
    let maxSide: CGFloat = 900
    let width = image.size.width
    let height = image.size.height
    let scale = min(1, maxSide / max(width, height))
    let outputImage: UIImage
    if scale < 1 {
        let size = CGSize(width: width * scale, height: height * scale)
        outputImage = UIGraphicsImageRenderer(size: size).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    } else {
        outputImage = image
    }
    return outputImage.jpegData(compressionQuality: 0.82) ?? data
}
