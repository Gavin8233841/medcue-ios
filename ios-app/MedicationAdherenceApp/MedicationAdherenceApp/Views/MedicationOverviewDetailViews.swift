import MedicationAdherenceCore
import SwiftData
import SwiftUI

struct MedicationOverviewDetailView: View {
    @Query(sort: \StoredMedication.displayName) private var medications: [StoredMedication]
    @Query(sort: \StoredMedicationPlan.createdAt) private var plans: [StoredMedicationPlan]
    @Query(sort: \StoredDoseTask.dueAt, order: .reverse) private var tasks: [StoredDoseTask]
    @Query(sort: \StoredMedicationStock.lastUpdated, order: .reverse) private var stocks: [StoredMedicationStock]

    init() {
        let window = MedicationTaskObservationWindow.medicationOverview()
        let queryStart = window.start
        let queryEnd = window.end
        _tasks = Query(
            filter: #Predicate<StoredDoseTask> { task in
                task.dueAt >= queryStart && task.dueAt < queryEnd
            },
            sort: \StoredDoseTask.dueAt,
            order: .reverse
        )
    }

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
                                taskCount: tasks.adherenceMeasurableTasks.filter { $0.medicationID == medication.id }.count,
                                stockProjection: stockProjection(for: medication)
                            )
                        }
                    }
                }
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
        let relatedTasks = tasks.adherenceMeasurableTasks.filter { $0.medicationID == medication.id }
        return MedicationStockEstimator().project(
            stock: stock.coreStock,
            scheduledDoses: relatedTasks.map(\.coreScheduledDose),
            events: relatedTasks.compactMap(\.coreDoseEventUsingEffectiveAdherenceDate)
        )
    }
}

struct MedicationOverviewStatCard: View {
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
        .medicationGlassSurface(cornerRadius: 8, tint: tint, fallbackMaterial: .thinMaterial)
    }
}

struct MedicationOverviewMedicationRow: View {
    let medication: StoredMedication
    let taskCount: Int
    let stockProjection: MedicationStockProjection?

    var body: some View {
        HStack(spacing: 12) {
            MedicationPhotoView(photoData: medication.photoData, symbolName: medication.photoSymbolName, tint: medicationColor(for: medication), size: 48)
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 7) {
                    MedicationColorMarker(color: medicationColor(for: medication), size: 9)
                    Text(userFacingMedicationName(for: medication))
                        .font(.headline)
                }
                if medicationNeedsNameReview(medication) {
                    Text("药名待补全")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.orange)
                }
                Text([medication.strength, medication.form].filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    Text("\(taskCount) 条记录")
                    if !medication.boxNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text("药盒编号 \(medication.boxNumber)")
                    }
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

struct MedicationPendingTasksDetailView: View {
    @Environment(\.openMedicationToday) private var openMedicationToday
    @Query(sort: \StoredDoseTask.dueAt) private var tasks: [StoredDoseTask]
    @Query(sort: \StoredMedication.displayName) private var medications: [StoredMedication]

    init() {
        let window = MedicationTaskObservationWindow.today()
        let queryStart = window.start
        let queryEnd = window.end
        _tasks = Query(
            filter: #Predicate<StoredDoseTask> { task in
                task.dueAt >= queryStart && task.dueAt < queryEnd
            },
            sort: \StoredDoseTask.dueAt
        )
    }

    private var pendingTasks: [StoredDoseTask] {
        let activeMedicationIDs = Set(
            medications
                .filter { $0.lifecycleStatus == .active }
                .map(\.id)
        )
        return tasks
            .filter {
                $0.isAdherenceMeasurable
                    && activeMedicationIDs.contains($0.medicationID)
                    && Calendar.current.isDateInToday($0.dueAt)
                    && ($0.status == .pending || $0.status == .delayed)
            }
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

            if !pendingTasks.isEmpty {
                Section("处理") {
                    Button {
                        openMedicationToday()
                    } label: {
                        Label("去今日页处理", systemImage: "calendar")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .navigationTitle("今日待处理")
    }

    private func medication(for task: StoredDoseTask) -> StoredMedication? {
        medications.first { $0.id == task.medicationID }
    }
}

struct PendingTaskOverviewRow: View {
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
                tint: medication.map(medicationColor(for:)) ?? (task.status == .delayed ? .orange : .blue),
                size: 44
            )
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 7) {
                    if let medication {
                        MedicationColorMarker(color: medicationColor(for: medication), size: 8)
                    }
                    Text(medication.map(userFacingMedicationName(for:)) ?? "未知药品")
                        .font(.headline)
                }
                Text("\(task.doseValue.formatted()) \(localizedMedicationUnit(task.doseUnit))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 5)
    }
}

struct MedicationStockOverviewView: View {
    @Query(sort: \StoredMedication.displayName) private var medications: [StoredMedication]
    @Query(sort: \StoredDoseTask.dueAt, order: .reverse) private var tasks: [StoredDoseTask]
    @Query(sort: \StoredMedicationStock.lastUpdated, order: .reverse) private var stocks: [StoredMedicationStock]

    init() {
        let window = MedicationTaskObservationWindow.medicationOverview()
        let queryStart = window.start
        let queryEnd = window.end
        _tasks = Query(
            filter: #Predicate<StoredDoseTask> { task in
                task.dueAt >= queryStart && task.dueAt < queryEnd
            },
            sort: \StoredDoseTask.dueAt,
            order: .reverse
        )
    }

    private var summaries: [MedicationStockSummary] {
        medications.filter { $0.lifecycleStatus == .active }.compactMap { medication in
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
                    Text("暂无药盒库存")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(summaries) { summary in
                        NavigationLink {
                            MedicationDetailView(medication: summary.medication)
                        } label: {
                            StockOverviewRow(summary: summary)
                        }
                        .accessibilityHint("打开药品详情，更新药盒库存")
                    }
                }
            }

        }
        .navigationTitle("药盒管理")
    }

    private func stockProjection(for medication: StoredMedication) -> MedicationStockProjection? {
        guard let stock = stocks.first(where: { $0.medicationID == medication.id }) else {
            return nil
        }
        let relatedTasks = tasks.adherenceMeasurableTasks.filter { $0.medicationID == medication.id }
        return MedicationStockEstimator().project(
            stock: stock.coreStock,
            scheduledDoses: relatedTasks.map(\.coreScheduledDose),
            events: relatedTasks.compactMap(\.coreDoseEventUsingEffectiveAdherenceDate)
        )
    }
}

struct StockOverviewRow: View {
    let summary: MedicationStockSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                MedicationPhotoView(
                    photoData: summary.medication.photoData,
                    symbolName: summary.medication.photoSymbolName,
                    tint: medicationColor(for: summary.medication),
                    size: 48
                )
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 7) {
                        MedicationColorMarker(color: medicationColor(for: summary.medication), size: 9)
                        Text(userFacingMedicationName(for: summary.medication))
                            .font(.headline)
                    }
                    if medicationNeedsNameReview(summary.medication) {
                        Text("药名待补全")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.orange)
                    }
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
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
    }

    private var accessibilitySummary: String {
        var parts = [
            userFacingMedicationName(for: summary.medication),
            stockRemainingText(summary.projection),
            summary.projection.needsRefillReminder ? "需要核对" : "正常"
        ]
        if let averageDailyConsumption = summary.projection.averageDailyConsumption {
            parts.append("日均消耗 \(formatDecimal(averageDailyConsumption)) \(localizedMedicationUnit(summary.projection.unit))")
        } else {
            parts.append("日均消耗待记录")
        }
        if let estimatedDaysRemaining = summary.projection.estimatedDaysRemaining {
            parts.append("预计可用 \(estimatedDaysRemaining) 天")
        } else {
            parts.append("预计可用待记录")
        }
        parts.append("记录天数 \(summary.projection.trackedDayCount) 天")
        return parts.joined(separator: "，")
    }
}

struct StockSmallMetric: View {
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
