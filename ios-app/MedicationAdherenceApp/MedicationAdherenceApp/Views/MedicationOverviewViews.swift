import Charts
import MedicationAdherenceCore
import PhotosUI
import SwiftData
import SwiftUI
import UIKit

@MainActor
enum MedicationListSnapshotCache {
    struct Entry {
        let snapshot: MedicationListSnapshot
    }

    private static var token = ""
    private static var storedAt = Date(timeIntervalSinceReferenceDate: 0)
    private static var entry = Entry(snapshot: .empty)
    private static let timeToLive: TimeInterval = 300

    static func store(snapshot: MedicationListSnapshot, token: String) {
        self.token = token
        self.entry = Entry(snapshot: snapshot)
        storedAt = Date()
    }

    static func entry(for token: String) -> Entry? {
        guard self.token == token,
              !entry.snapshot.isPlaceholder,
              Date().timeIntervalSince(storedAt) <= timeToLive
        else {
            return nil
        }
        return entry
    }
}

struct MedicationDetailRoute: Hashable {
    let medicationID: UUID
}

struct MedicationDetailResolverView: View {
    let medicationID: UUID
    @Query(sort: \StoredMedication.displayName) private var medications: [StoredMedication]

    var body: some View {
        if let medication = medications.first(where: { $0.id == medicationID }) {
            MedicationDetailView(medication: medication)
        } else {
            List {
                Text("没有找到这项药品，可能已被归档或删除。")
                    .foregroundStyle(.secondary)
            }
            .navigationTitle("药品详情")
        }
    }
}

struct MedicationListSnapshot {
    static var empty: MedicationListSnapshot {
        MedicationListSnapshot(
        medications: [],
        plans: [],
        tasks: [],
        doseChanges: [],
        stocks: [],
        now: Date(timeIntervalSinceReferenceDate: 0),
        isPlaceholder: true
        )
    }

    let medications: [StoredMedication]
    let measurableTasks: [StoredDoseTask]
    let stockSummaries: [MedicationStockSummary]
    let activeTaskCount: Int
    let lowStockCount: Int
    let completionRate: Double
    let trendInputID: String
    let trendInput: MedicationListTrendInput
    let isPlaceholder: Bool

    private let plansByMedicationID: [UUID: StoredMedicationPlan]
    private let tasksByMedicationID: [UUID: [StoredDoseTask]]
    private let nextTasksByMedicationID: [UUID: StoredDoseTask]
    private let stockProjectionByMedicationID: [UUID: MedicationStockProjection]
    private let lifecycleByMedicationID: [UUID: MedicationLifecycleClassification]
    private let lifecycleCounts: [StoredMedicationLifecycleStatus: Int]

    static func refreshID(
        medications: [StoredMedication],
        plans: [StoredMedicationPlan],
        tasks: [StoredDoseTask],
        doseChanges: [StoredMedicationDoseChange],
        stocks: [StoredMedicationStock],
        calendar: Calendar = .current
    ) -> String {
        let todayStart = calendar.startOfDay(for: Date())
        let todayTaskMarker = tasks.reduce(into: TodayTaskMarker()) { marker, task in
            guard calendar.isDate(task.dueAt, inSameDayAs: todayStart) else {
                return
            }
            marker.count += 1
            if task.status == .pending || task.status == .delayed {
                marker.openCount += 1
            }
            marker.statusVersion &+= task.status.versionValue
            marker.recordedVersion &+= Int(task.recordedAt?.timeIntervalSinceReferenceDate.rounded() ?? 0)
        }
        var parts: [String] = []
        parts.reserveCapacity(14)
        parts.append(String(stableMedicationSignature(medications)))
        parts.append(String(stablePlanSignature(plans)))
        parts.append(String(stableTaskSignature(tasks)))
        parts.append(String(todayTaskMarker.count))
        parts.append(String(todayTaskMarker.openCount))
        parts.append(String(todayTaskMarker.statusVersion))
        parts.append(String(todayTaskMarker.recordedVersion))
        parts.append(String(stableDoseChangeSignature(doseChanges)))
        parts.append(String(stableStockSignature(stocks)))
        return parts.joined(separator: "|")
    }

    init(
        medications: [StoredMedication],
        plans: [StoredMedicationPlan],
        tasks: [StoredDoseTask],
        doseChanges: [StoredMedicationDoseChange],
        stocks: [StoredMedicationStock],
        now: Date,
        calendar: Calendar = .current,
        isPlaceholder: Bool = false
    ) {
        self.medications = medications
        self.isPlaceholder = isPlaceholder
        let activeMedicationIDs = Set(
            medications
                .filter { $0.lifecycleStatus == .active }
                .map(\.id)
        )
        let measurableTasks = tasks.adherenceMeasurableTasks
        self.measurableTasks = measurableTasks
        self.plansByMedicationID = Dictionary(
            plans.reversed().map { ($0.medicationID, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        self.tasksByMedicationID = Dictionary(grouping: measurableTasks, by: \.medicationID)
        let todayOpenTasks = measurableTasks
            .filter { task in
                activeMedicationIDs.contains(task.medicationID)
                    && calendar.isDateInToday(task.dueAt)
                    && (task.status == .pending || task.status == .delayed)
            }
            .sorted { lhs, rhs in
                if lhs.dueAt != rhs.dueAt {
                    return lhs.dueAt < rhs.dueAt
                }
                return lhs.id.uuidString < rhs.id.uuidString
            }
        self.activeTaskCount = todayOpenTasks.count
        self.nextTasksByMedicationID = Dictionary(
            todayOpenTasks.map { ($0.medicationID, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        let estimator = MedicationStockEstimator()
        var projectionByMedicationID: [UUID: MedicationStockProjection] = [:]
        for stock in stocks {
            guard projectionByMedicationID[stock.medicationID] == nil else {
                continue
            }
            let relatedTasks = tasksByMedicationID[stock.medicationID] ?? []
            projectionByMedicationID[stock.medicationID] = estimator.project(
                stock: stock.coreStock,
                scheduledDoses: relatedTasks.map(\.coreScheduledDose),
                events: relatedTasks.compactMap(\.coreDoseEventUsingEffectiveAdherenceDate)
            )
        }
        self.stockProjectionByMedicationID = projectionByMedicationID
        self.stockSummaries = medications.filter { $0.lifecycleStatus == .active }.compactMap { medication in
            guard let projection = projectionByMedicationID[medication.id] else {
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
        self.lowStockCount = stockSummaries.filter(\.projection.needsRefillReminder).count

        let scheduledDoses = measurableTasks.map(\.coreScheduledDose)
        let doseEvents = measurableTasks.compactMap(\.coreDoseEventUsingEffectiveAdherenceDate)
        self.completionRate = AdherenceInsightBuilder().build(
            scheduledDoses: scheduledDoses,
            events: doseEvents,
            timeZone: TimeZone.current,
            now: now
        ).completionRate

        let classifier = MedicationLifecycleClassifier()
        var lifecycleByMedicationID: [UUID: MedicationLifecycleClassification] = [:]
        var lifecycleCounts: [StoredMedicationLifecycleStatus: Int] = [:]
        for medication in medications {
            let classification = classifier.classify(
                medication: medication,
                plans: plans,
                tasks: tasksByMedicationID[medication.id] ?? [],
                now: now
            )
            lifecycleByMedicationID[medication.id] = classification
            lifecycleCounts[classification.displayStatus, default: 0] += 1
        }
        self.lifecycleByMedicationID = lifecycleByMedicationID
        self.lifecycleCounts = lifecycleCounts
        self.trendInput = MedicationListTrendInput(
            medications: medications,
            plans: plans,
            tasks: measurableTasks,
            doseChanges: doseChanges
        )
        self.trendInputID = medications.isEmpty
            && plans.isEmpty
            && measurableTasks.isEmpty
            && doseChanges.isEmpty
            && stocks.isEmpty
            ? "empty"
            : "ready"
    }

    func visibleMedications(for status: StoredMedicationLifecycleStatus) -> [StoredMedication] {
        medications.filter { lifecycleClassification(for: $0).displayStatus == status }
    }

    func count(for status: StoredMedicationLifecycleStatus) -> Int {
        lifecycleCounts[status, default: 0]
    }

    func plan(for medication: StoredMedication) -> StoredMedicationPlan? {
        plansByMedicationID[medication.id]
    }

    func taskCount(for medication: StoredMedication) -> Int {
        tasksByMedicationID[medication.id]?.count ?? 0
    }

    func nextTask(for medication: StoredMedication) -> StoredDoseTask? {
        nextTasksByMedicationID[medication.id]
    }

    func stockProjection(for medication: StoredMedication) -> MedicationStockProjection? {
        stockProjectionByMedicationID[medication.id]
    }

    func lifecycleClassification(for medication: StoredMedication) -> MedicationLifecycleClassification {
        lifecycleByMedicationID[medication.id] ?? MedicationLifecycleClassification(
            displayStatus: medication.lifecycleStatus,
            reason: medication.lifecycleStatus == .archived ? .archived : .ongoing,
            shouldPromptReview: false
        )
    }
}

struct MedicationListTrendInput {
    let medications: [StoredMedication]
    let plans: [StoredMedicationPlan]
    let tasks: [StoredDoseTask]
    let doseChanges: [StoredMedicationDoseChange]
}

func stableMedicationSignature(_ medications: [StoredMedication]) -> Int {
    var hasher = Hasher()
    hasher.combine(medications.count)
    for medication in medications {
        hasher.combine(medication.id)
        hasher.combine(medication.displayName)
        hasher.combine(medication.genericName)
        hasher.combine(medication.kindRaw)
        hasher.combine(medication.form)
        hasher.combine(medication.strength)
        hasher.combine(medication.inputSourceRaw)
        hasher.combine(medication.photoSymbolName)
        hasher.combine(medication.photoData?.count ?? 0)
        hasher.combine(medication.boxNumber)
        hasher.combine(medication.notes)
        hasher.combine(medication.lifecycleStatusRaw)
        hasher.combine(medication.isDemoContent)
        hasher.combine(Int(medication.createdAt.timeIntervalSinceReferenceDate.rounded()))
    }
    return hasher.finalize()
}

func stablePlanSignature(_ plans: [StoredMedicationPlan]) -> Int {
    var hasher = Hasher()
    hasher.combine(plans.count)
    for plan in plans {
        hasher.combine(plan.id)
        hasher.combine(plan.medicationID)
        hasher.combine(plan.doseValue)
        hasher.combine(plan.doseUnit)
        hasher.combine(plan.timingSummary)
        hasher.combine(plan.timeZonePolicyRaw)
        hasher.combine(plan.sourceNote)
        hasher.combine(plan.requiresUserConfirmation)
        hasher.combine(plan.courseStartAt.map { Int($0.timeIntervalSinceReferenceDate.rounded()) } ?? 0)
        hasher.combine(plan.courseEndAt.map { Int($0.timeIntervalSinceReferenceDate.rounded()) } ?? 0)
        hasher.combine(plan.reminderTimesRaw ?? "")
        hasher.combine(plan.reminderDeliveryRaw ?? "")
        hasher.combine(Int(plan.createdAt.timeIntervalSinceReferenceDate.rounded()))
    }
    return hasher.finalize()
}

func stableTaskSignature(_ tasks: [StoredDoseTask]) -> Int {
    var hasher = Hasher()
    hasher.combine(tasks.count)
    for task in tasks {
        hasher.combine(task.id)
        hasher.combine(task.medicationID)
        hasher.combine(task.planID)
        hasher.combine(Int(task.dueAt.timeIntervalSinceReferenceDate.rounded()))
        hasher.combine(task.doseValue)
        hasher.combine(task.doseUnit)
        hasher.combine(task.statusRaw)
        hasher.combine(task.recordedAt.map { Int($0.timeIntervalSinceReferenceDate.rounded()) } ?? 0)
        hasher.combine(task.reason)
    }
    return hasher.finalize()
}

func stableDoseChangeSignature(_ doseChanges: [StoredMedicationDoseChange]) -> Int {
    var hasher = Hasher()
    hasher.combine(doseChanges.count)
    for change in doseChanges {
        hasher.combine(change.id)
        hasher.combine(change.medicationID)
        hasher.combine(change.planID)
        hasher.combine(change.previousDoseValue)
        hasher.combine(change.previousDoseUnit)
        hasher.combine(change.newDoseValue)
        hasher.combine(change.newDoseUnit)
        hasher.combine(Int(change.effectiveFrom.timeIntervalSinceReferenceDate.rounded()))
        hasher.combine(Int(change.changedAt.timeIntervalSinceReferenceDate.rounded()))
        hasher.combine(change.note)
    }
    return hasher.finalize()
}

func stableStockSignature(_ stocks: [StoredMedicationStock]) -> Int {
    var hasher = Hasher()
    hasher.combine(stocks.count)
    for stock in stocks {
        hasher.combine(stock.id)
        hasher.combine(stock.medicationID)
        hasher.combine(stock.remainingQuantity)
        hasher.combine(stock.unit)
        hasher.combine(stock.lowStockThreshold)
        hasher.combine(Int(stock.lastUpdated.timeIntervalSinceReferenceDate.rounded()))
    }
    return hasher.finalize()
}

func stableRiskCardSignature(_ riskCards: [StoredRiskCard]) -> Int {
    var hasher = Hasher()
    hasher.combine(riskCards.count)
    for card in riskCards {
        hasher.combine(card.id)
        hasher.combine(card.medicationID)
        hasher.combine(card.kindRaw)
        hasher.combine(card.severityRaw)
        hasher.combine(card.sourceKindRaw)
        hasher.combine(card.displayPriority)
        hasher.combine(card.title)
        hasher.combine(card.message)
        hasher.combine(card.sourceTitle)
        hasher.combine(card.sourceExcerpt)
        hasher.combine(card.detectionSignature)
        hasher.combine(card.requiresProfessionalReview)
        hasher.combine(card.safetyNote)
        hasher.combine(Int(card.firstDetectedAt.timeIntervalSinceReferenceDate.rounded()))
        hasher.combine(Int(card.lastDetectedAt.timeIntervalSinceReferenceDate.rounded()))
        hasher.combine(card.readAt.map { Int($0.timeIntervalSinceReferenceDate.rounded()) } ?? 0)
        hasher.combine(card.resolvedAt.map { Int($0.timeIntervalSinceReferenceDate.rounded()) } ?? 0)
        hasher.combine(card.resolutionNote)
        hasher.combine(card.reviewedAt.map { Int($0.timeIntervalSinceReferenceDate.rounded()) } ?? 0)
        hasher.combine(card.archivedAt.map { Int($0.timeIntervalSinceReferenceDate.rounded()) } ?? 0)
        hasher.combine(card.reviewNote)
    }
    return hasher.finalize()
}

func stableLifecycleEventSignature(_ lifecycleEvents: [StoredMedicationLifecycleEvent]) -> Int {
    var hasher = Hasher()
    hasher.combine(lifecycleEvents.count)
    for event in lifecycleEvents {
        hasher.combine(event.id)
        hasher.combine(event.medicationID)
        hasher.combine(event.statusRaw)
        hasher.combine(Int(event.occurredAt.timeIntervalSinceReferenceDate.rounded()))
        hasher.combine(event.note)
    }
    return hasher.finalize()
}

func stableHealthSignalSignature(_ healthSignals: [HealthSignalSample]) -> Int {
    var hasher = Hasher()
    hasher.combine(healthSignals.count)
    for signal in healthSignals {
        hasher.combine(signal.id)
        hasher.combine(signal.kind.rawValue)
        hasher.combine(Int(signal.measuredAt.timeIntervalSinceReferenceDate.rounded()))
        hasher.combine(signal.value)
        hasher.combine(signal.unit)
    }
    return hasher.finalize()
}

struct TodayTaskMarker {
    var count = 0
    var openCount = 0
    var statusVersion = 0
    var recordedVersion = 0
}

extension StoredDoseStatus {
    var versionValue: Int {
        switch self {
        case .pending:
            1
        case .taken:
            2
        case .delayed:
            3
        case .skipped:
            4
        case .corrected:
            5
        }
    }
}

struct MedicationStockSummary: Identifiable {
    let id: UUID
    let medication: StoredMedication
    let projection: MedicationStockProjection

    init(medication: StoredMedication, projection: MedicationStockProjection) {
        self.id = medication.id
        self.medication = medication
        self.projection = projection
    }
}

struct MedicationLifecycleSelector: View {
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
                    VStack(spacing: 5) {
                        Image(systemName: lifecycleIconName(for: status))
                            .font(.subheadline.weight(.semibold))
                            .frame(height: 18)
                        Text("\(count(status))")
                            .font(.title3.weight(.bold))
                            .monospacedDigit()
                            .frame(height: 22)
                        Text(status.displayName)
                            .font(.caption.weight(.semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.72)
                            .allowsTightening(true)
                            .frame(maxWidth: .infinity)
                    }
                    .foregroundStyle(isSelected ? Color.white : badgeColor(for: status))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 7)
                    .frame(maxWidth: .infinity, minHeight: 74)
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

struct MedicationLifecycleGroupSummaryRow: View {
    let status: StoredMedicationLifecycleStatus
    let count: Int
    let firstMedication: StoredMedication?
    let nextTask: StoredDoseTask?

    private var tint: Color {
        badgeColor(for: status)
    }

    private var subtitle: String {
        if let firstMedication {
            let name = userFacingMedicationName(for: firstMedication)
            if let nextTask {
                return "\(name) · 下次 \(AppFormatters.time.string(from: nextTask.dueAt))"
            }
            return "\(name) · 暂无今日待处理"
        }
        return "暂无药品"
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: iconName)
                .font(.title2.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 42, height: 42)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text("\(status.displayName)药品")
                    .font(.headline)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Text("\(count)")
                .font(.system(.headline, design: .rounded).weight(.bold))
                .foregroundStyle(tint)
                .monospacedDigit()
                .contentTransition(.numericText())
        }
        .padding(.vertical, 5)
    }

    private var iconName: String {
        switch status {
        case .active:
            return "pills.fill"
        case .interrupted:
            return "pause.circle.fill"
        case .archived:
            return "archivebox.fill"
        }
    }
}

struct MedicationAddOptionsSheet: View {
    @Environment(\.dismiss) private var dismiss
    let select: (MedicationAddOption) -> Void

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(MedicationAddWorkflow.options) { option in
                        let isEnabled = isMedicationAddOptionEnabled(option)
                        Button {
                            select(option)
                        } label: {
                            HStack(spacing: 14) {
                                Image(systemName: addOptionIconName(option))
                                    .font(.title3.weight(.semibold))
                                    .foregroundStyle(isEnabled ? Color.blue : Color.secondary)
                                    .frame(width: 36, height: 36)
                                    .background(
                                        (isEnabled ? Color.blue : Color.secondary).opacity(isEnabled ? 0.12 : 0.10),
                                        in: RoundedRectangle(cornerRadius: 8)
                                    )
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(option.title)
                                        .font(.headline)
                                        .foregroundStyle(isEnabled ? .primary : .secondary)
                                    Text(addOptionSubtitle(option))
                                        .font(.footnote)
                                        .foregroundStyle(isEnabled ? .secondary : .tertiary)
                                        .lineLimit(2)
                                }
                                Spacer()
                                if isEnabled {
                                    Image(systemName: "chevron.right")
                                        .font(.footnote.weight(.bold))
                                        .foregroundStyle(.secondary)
                                } else {
                                    Text("暂不可用")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.tertiary)
                                }
                            }
                            .padding(.vertical, 4)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(!isEnabled)
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

func isMedicationAddOptionEnabled(_ option: MedicationAddOption) -> Bool {
    option.id == .manual
}

struct MedicationDashboardSummary: View {
    let medicationCount: Int
    let activeTaskCount: Int
    let stockCount: Int
    let lowStockCount: Int
    let activeRiskCount: Int
    let priorityRiskCount: Int
    @State private var selectedDestination: MedicationDashboardDestination?
    private let columns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("用药概览")
                        .font(.title2.weight(.semibold))
                    Text("药品、提醒、药盒和风险复核")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "heart.text.square.fill")
                    .font(.title)
                    .foregroundStyle(.blue)
            }

            LazyVGrid(columns: columns, spacing: 10) {
                Button {
                    selectedDestination = .overview
                } label: {
                    MedicationMetricTile(
                        title: "药品",
                        value: "\(medicationCount)",
                        subtitle: medicationCount == 0 ? "等待添加" : "查看详情",
                        iconName: "pills.fill",
                        tint: .blue
                    )
                }
                .buttonStyle(.plain)

                Button {
                    selectedDestination = .pendingTasks
                } label: {
                    MedicationMetricTile(
                        title: "待处理",
                        value: "\(activeTaskCount)",
                        subtitle: activeTaskCount == 0 ? "今日清空" : "去今日页",
                        iconName: "bell.badge.fill",
                        tint: activeTaskCount > 0 ? .orange : .green
                    )
                }
                .buttonStyle(.plain)

                Button {
                    selectedDestination = .stock
                } label: {
                    MedicationMetricTile(
                        title: "药盒",
                        value: "\(stockCount)",
                        subtitle: lowStockCount > 0 ? "\(lowStockCount) 项需核对" : "均正常",
                        iconName: "shippingbox.fill",
                        tint: lowStockCount > 0 ? .orange : .green
                    )
                }
                .buttonStyle(.plain)

                Button {
                    selectedDestination = .risk
                } label: {
                    MedicationMetricTile(
                        title: "风险复核",
                        value: "\(priorityRiskCount > 0 ? priorityRiskCount : activeRiskCount)",
                        subtitle: priorityRiskCount > 0 ? "需重点查看" : (activeRiskCount > 0 ? "可查看" : "暂无活跃"),
                        iconName: "shield.lefthalf.filled",
                        tint: priorityRiskCount > 0 ? .orange : (activeRiskCount > 0 ? .indigo : .secondary)
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 8)
        .navigationDestination(item: $selectedDestination) { destination in
            switch destination {
            case .overview:
                MedicationOverviewDetailView()
            case .pendingTasks:
                MedicationPendingTasksDetailView()
            case .stock:
                MedicationStockOverviewView()
            case .risk:
                RisksView()
            }
        }
    }
}

enum MedicationDashboardDestination: Hashable, Identifiable {
    case overview
    case pendingTasks
    case stock
    case risk

    var id: Self { self }
}

struct MedicationMetricTile: View {
    let title: String
    let value: String
    var subtitle: String? = nil
    let iconName: String
    let tint: Color
    var compact = false

    var body: some View {
        let iconSize: CGFloat = compact ? 24 : 28
        let minHeight: CGFloat = compact ? 66 : 76
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: compact ? 5 : 7) {
                HStack(spacing: 8) {
                    Image(systemName: iconName)
                        .font(compact ? .subheadline.weight(.semibold) : .headline)
                        .foregroundStyle(tint)
                        .frame(width: iconSize, height: iconSize)
                        .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                    Text(title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                }
                if let subtitle, !compact {
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(value)
                .font((compact ? Font.title2 : Font.title).weight(.bold))
                .monospacedDigit()
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.68)
                .frame(minWidth: 36, alignment: .trailing)
        }
        .padding(compact ? 9 : 12)
        .frame(maxWidth: .infinity, minHeight: minHeight, alignment: .leading)
        .background(tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
    }
}

struct MedicationOverviewDetailView: View {
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

struct MedicationCardRow: View {
    let medication: StoredMedication
    let plan: StoredMedicationPlan?
    let taskCount: Int
    let nextTask: StoredDoseTask?
    let stockProjection: MedicationStockProjection?
    let lifecycleClassification: MedicationLifecycleClassification

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 14) {
                MedicationPhotoView(photoData: medication.photoData, symbolName: medication.photoSymbolName, tint: medicationColor(for: medication))
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 7) {
                        MedicationColorMarker(color: medicationColor(for: medication), size: 9)
                        Text(userFacingMedicationName(for: medication))
                            .font(.headline)
                    }
                    if medicationNeedsNameReview(medication) {
                        StatusBadge(text: "药名待补全", color: .orange)
                    }
                    Text([medication.strength, medication.form].filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    StatusBadgeFlow {
                        StatusBadge(text: medication.kindDisplayName, color: .green)
                        if !medication.boxNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            StatusBadge(text: "编号 \(medication.boxNumber)", color: .blue)
                        }
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
            if !medication.boxNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Label("药盒编号 \(medication.boxNumber)", systemImage: "number.square.fill")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
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

struct MedicationInlineStat: View {
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

struct LifecycleReviewPanel: View {
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
                    LifecycleActionButton(
                        title: "确认服用中断",
                        subtitle: "停用未来提醒，保留既有记录",
                        systemImage: "pause.circle.fill",
                        tint: .orange
                    )
                }
                .buttonStyle(.plain)
            }

            if medication.lifecycleStatus == .interrupted {
                Button {
                    markActive()
                } label: {
                    LifecycleActionButton(
                        title: "恢复正在服用",
                        subtitle: "重新纳入今日和提醒计划",
                        systemImage: "play.circle.fill",
                        tint: .green
                    )
                }
                .buttonStyle(.plain)
            }

            if medication.lifecycleStatus != .archived {
                Button(role: .destructive) {
                    archive()
                } label: {
                    LifecycleActionButton(
                        title: "归档药物",
                        subtitle: "从今日提醒移出，归档后可删除",
                        systemImage: "archivebox.fill",
                        tint: .orange
                    )
                }
                .buttonStyle(.plain)
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

struct LifecycleActionButton: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let tint: Color

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.headline.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 34, height: 34)
                .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 8)

            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(.tertiary)
        }
        .padding(12)
        .background(tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(tint.opacity(0.12), lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}
