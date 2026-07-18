import Charts
import MedicationAdherenceCore
import PhotosUI
import SwiftData
import SwiftUI
import UIKit

struct MedicationsView: View {
    @Environment(\.activeAppTab) private var activeAppTab
    @Query(sort: \StoredMedication.displayName) private var medications: [StoredMedication]
    @Query(sort: \StoredMedicationPlan.createdAt) private var plans: [StoredMedicationPlan]
    @Query(sort: \StoredDoseTask.dueAt, order: .reverse) private var tasks: [StoredDoseTask]
    @Query(sort: \StoredMedicationDoseChange.effectiveFrom, order: .reverse) private var doseChanges: [StoredMedicationDoseChange]
    @Query(sort: \StoredMedicationStock.lastUpdated, order: .reverse) private var stocks: [StoredMedicationStock]
    @Query(sort: \StoredRiskCard.displayPriority) private var riskCards: [StoredRiskCard]
    @State private var showingAddOptions = false
    @State private var pendingAddSelection: MedicationAddSelection?
    @State private var selectedAddSelection: MedicationAddSelection?
    @State private var selectedLifecycleStatus: StoredMedicationLifecycleStatus = .active
    @State private var showingMedicationList = false
    @State private var listSnapshot = MedicationListSnapshot.empty
    @State private var lastSnapshotRefreshToken = ""
    @State private var lastSnapshotRefreshAt = Date(timeIntervalSinceReferenceDate: 0)

    init() {
        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: Date())
        let queryStart = calendar.date(byAdding: .day, value: -90, to: todayStart) ?? todayStart.addingTimeInterval(-7_776_000)
        let queryEnd = calendar.date(byAdding: .day, value: 8, to: todayStart) ?? todayStart.addingTimeInterval(691_200)
        _tasks = Query(
            filter: #Predicate<StoredDoseTask> { task in
                task.dueAt >= queryStart && task.dueAt < queryEnd
            },
            sort: \StoredDoseTask.dueAt,
            order: .reverse
        )
    }

    private var isActiveTab: Bool {
        activeAppTab == nil || activeAppTab == .medications
    }

    private var refreshToken: String {
        MedicationListSnapshot.refreshID(
            medications: medications,
            plans: plans,
            tasks: tasks,
            doseChanges: doseChanges,
            stocks: stocks
        )
    }

    private var refreshTaskID: String {
        "\(isActiveTab ? "active" : "inactive")|\(refreshToken)"
    }

    private var shouldPrepareSnapshot: Bool {
        isActiveTab || listSnapshot.isPlaceholder
    }

    private var activeRiskCards: [StoredRiskCard] {
        riskCards.filter(\.isActive)
    }

    var body: some View {
        let snapshot = listSnapshot
        let activeRiskCards = activeRiskCards
        List {
            Section {
                MedicationDashboardSummary(
                    medicationCount: snapshot.medications.count,
                    activeTaskCount: snapshot.activeTaskCount,
                    stockCount: snapshot.stockSummaries.count,
                    lowStockCount: snapshot.lowStockCount,
                    activeRiskCount: activeRiskCards.count,
                    priorityRiskCount: activeRiskCards.filter(\.requiresProfessionalReview).count
                )
                .background(alignment: .top) {
                    AppTopGradientScrollReader(tab: .medications, coordinateSpaceName: "MedicationsTopGradientList")
                }
            }

            Section("药品分组") {
                MedicationLifecycleSelector(
                    selectedStatus: $selectedLifecycleStatus,
                    count: { snapshot.count(for: $0) }
                )
            }

            Section(selectedLifecycleStatus.displayName) {
                let visibleMedications = snapshot.visibleMedications(for: selectedLifecycleStatus)
                let firstMedication = visibleMedications.first
                let nextTask = firstMedication.flatMap { snapshot.nextTask(for: $0) }
                if snapshot.isPlaceholder && !medications.isEmpty {
                    Label("正在整理药品", systemImage: "hourglass")
                        .foregroundStyle(.secondary)
                } else if visibleMedications.isEmpty {
                    Text("还没有添加药品。")
                        .foregroundStyle(.secondary)
                } else {
                    Button {
                        withAnimation(.snappy(duration: 0.24, extraBounce: 0.01)) {
                            showingMedicationList.toggle()
                        }
                    } label: {
                        HStack(spacing: 8) {
                            MedicationLifecycleGroupSummaryRow(
                                status: selectedLifecycleStatus,
                                count: visibleMedications.count,
                                firstMedication: firstMedication,
                                nextTask: nextTask
                            )
                            Image(systemName: showingMedicationList ? "chevron.up" : "chevron.down")
                                .font(.footnote.weight(.bold))
                                .foregroundStyle(.secondary)
                                .accessibilityHidden(true)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(
                        medicationLifecycleGroupAccessibilityLabel(
                            status: selectedLifecycleStatus,
                            count: visibleMedications.count,
                            firstMedication: firstMedication,
                            nextTask: nextTask
                        )
                    )
                    .accessibilityValue(showingMedicationList ? "已展开" : "已折叠")

                    if showingMedicationList {
                        ForEach(visibleMedications) { medication in
                            NavigationLink(value: MedicationDetailRoute(medicationID: medication.id)) {
                                MedicationCardRow(
                                    medication: medication,
                                    plan: snapshot.plan(for: medication),
                                    taskCount: snapshot.taskCount(for: medication),
                                    nextTask: snapshot.nextTask(for: medication),
                                    stockProjection: snapshot.stockProjection(for: medication),
                                    lifecycleClassification: snapshot.lifecycleClassification(for: medication)
                                )
                            }
                        }
                    }
                }
            }
        }
        .coordinateSpace(name: "MedicationsTopGradientList")
        .safeAreaInset(edge: .bottom) {
            Color.clear.frame(height: 96)
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
                pendingAddSelection = MedicationAddSelection(option: option)
                showingAddOptions = false
            }
            .presentationDetents([.height(360)])
            .presentationDragIndicator(.visible)
        }
        .onChange(of: showingAddOptions) { _, isPresented in
            guard !isPresented, let pendingAddSelection else {
                return
            }
            self.pendingAddSelection = nil
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(180))
                selectedAddSelection = pendingAddSelection
            }
        }
        .sheet(item: $selectedAddSelection) { selection in
            AddMedicationView(option: selection.option)
        }
        .navigationDestination(for: MedicationDetailRoute.self) { route in
            MedicationDetailResolverView(medicationID: route.medicationID)
        }
        .onAppear {
            restoreMedicationSnapshotFromCacheIfAvailable()
        }
        .onChange(of: selectedLifecycleStatus) { _, _ in
            withAnimation(.snappy(duration: 0.24, extraBounce: 0.01)) {
                showingMedicationList = false
            }
        }
        .task(id: refreshTaskID) {
            guard shouldPrepareSnapshot else {
                return
            }
            let delay: Duration = isActiveTab
                ? .milliseconds(listSnapshot.isPlaceholder ? 40 : 120)
                : .milliseconds(180)
            await refreshMedicationSnapshot(token: refreshToken, after: delay)
        }
    }

    @MainActor
    private func refreshMedicationSnapshot(token: String, after delay: Duration) async {
        if restoreMedicationSnapshotFromCacheIfAvailable(for: token),
           !listSnapshot.isPlaceholder,
           isActiveTab {
            return
        }
        if lastSnapshotRefreshToken == token,
           !listSnapshot.isPlaceholder,
           Date().timeIntervalSince(lastSnapshotRefreshAt) < 15 {
            return
        }
        let medications = medications
        let plans = plans
        let tasks = tasks
        let doseChanges = doseChanges
        let stocks = stocks
        try? await Task.sleep(for: delay)
        guard !Task.isCancelled else {
            return
        }
        let refreshedSnapshot = MedicationListSnapshot(
            medications: medications,
            plans: plans,
            tasks: tasks,
            doseChanges: doseChanges,
            stocks: stocks,
            now: Date()
        )
        guard !Task.isCancelled else {
            return
        }
        listSnapshot = refreshedSnapshot
        lastSnapshotRefreshToken = token
        lastSnapshotRefreshAt = Date()
        MedicationListSnapshotCache.store(snapshot: refreshedSnapshot, token: token)
    }

    private func medicationLifecycleGroupAccessibilityLabel(
        status: StoredMedicationLifecycleStatus,
        count: Int,
        firstMedication: StoredMedication?,
        nextTask: StoredDoseTask?
    ) -> String {
        var parts = ["\(status.displayName)药品", "\(count) 个"]
        if let firstMedication {
            let medicationName = userFacingMedicationName(for: firstMedication)
            if let nextTask {
                parts.append("\(medicationName)，下次 \(AppFormatters.time.string(from: nextTask.dueAt))")
            } else {
                parts.append("\(medicationName)，暂无今日待处理")
            }
        }
        return parts.joined(separator: "，")
    }

    @MainActor
    @discardableResult
    private func restoreMedicationSnapshotFromCacheIfAvailable(for token: String? = nil) -> Bool {
        let lookupToken = token ?? refreshToken
        guard let cachedEntry = MedicationListSnapshotCache.entry(for: lookupToken) else {
            return false
        }
        listSnapshot = cachedEntry.snapshot
        lastSnapshotRefreshToken = lookupToken
        lastSnapshotRefreshAt = Date()
        return true
    }
}

@MainActor
private enum MedicationListSnapshotCache {
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

private struct MedicationDetailRoute: Hashable {
    let medicationID: UUID
}

private struct MedicationDetailResolverView: View {
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

private struct MedicationListSnapshot {
    static let empty = MedicationListSnapshot(
        medications: [],
        plans: [],
        tasks: [],
        doseChanges: [],
        stocks: [],
        now: Date(timeIntervalSinceReferenceDate: 0),
        isPlaceholder: true
    )

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

private struct MedicationListTrendInput {
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

private struct TodayTaskMarker {
    var count = 0
    var openCount = 0
    var statusVersion = 0
    var recordedVersion = 0
}

private extension StoredDoseStatus {
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

private struct MedicationLifecycleGroupSummaryRow: View {
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

private struct MedicationAddOptionsSheet: View {
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

private func isMedicationAddOptionEnabled(_ option: MedicationAddOption) -> Bool {
    option.id == .manual
}

private struct MedicationDashboardSummary: View {
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

private enum MedicationDashboardDestination: Hashable, Identifiable {
    case overview
    case pendingTasks
    case stock
    case risk

    var id: Self { self }
}

private struct MedicationMetricTile: View {
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
        .medicationGlassSurface(cornerRadius: 8, tint: tint, fallbackMaterial: .thinMaterial)
    }
}

private struct MedicationOverviewMedicationRow: View {
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

private struct MedicationPendingTasksDetailView: View {
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

private struct MedicationStockOverviewView: View {
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

private struct StockOverviewRow: View {
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
    @Query(sort: \StoredMedication.displayName) private var medications: [StoredMedication]
    @Query(sort: \StoredMedicationPlan.createdAt) private var plans: [StoredMedicationPlan]
    @Query(sort: \StoredMedicationLifecycleEvent.occurredAt, order: .reverse) private var lifecycleEvents: [StoredMedicationLifecycleEvent]
    @StateObject private var healthKitService = HealthKitService()
    @State private var selectedTopic: MedicationTrendTopic = .discipline
    @State private var selectedDate: Date?

    init() {
        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: Date())
        let queryStart = calendar.date(byAdding: .day, value: -120, to: todayStart) ?? todayStart.addingTimeInterval(-10_368_000)
        let queryEnd = calendar.date(byAdding: .day, value: 1, to: todayStart) ?? todayStart.addingTimeInterval(86_400)
        _tasks = Query(
            filter: #Predicate<StoredDoseTask> { task in
                task.dueAt >= queryStart && task.dueAt < queryEnd
            },
            sort: \StoredDoseTask.dueAt,
            order: .reverse
        )
    }

    private var dashboard: MedicationTrendDashboard {
        medicationTrendDashboard(
            tasks: tasks.adherenceMeasurableTasks,
            doseChanges: doseChanges,
            medications: medications,
            plans: plans,
            lifecycleEvents: lifecycleEvents,
            healthSignals: healthKitService.recentTrendSamples
        )
    }

    private var selectedMetric: MedicationTrendMetric {
        dashboard.metrics.first { $0.topic == selectedTopic } ?? dashboard.metrics.first ?? emptyTrendMetric(topic: selectedTopic)
    }

    private var selectedPoint: MedicationTrendPoint? {
        let points = selectedMetric.points
        guard !points.isEmpty else {
            return nil
        }
        guard let selectedDate else {
            return points.last
        }
        return points.min { lhs, rhs in
            abs(trendDate(from: lhs.date).timeIntervalSince(selectedDate)) < abs(trendDate(from: rhs.date).timeIntervalSince(selectedDate))
        }
    }

    var body: some View {
        List {
            Section("用药趋势") {
                MedicationTrendDashboardCard(dashboard: dashboard)
            }

            Section("趋势主题") {
                MedicationTrendTopicPicker(selectedTopic: $selectedTopic, metrics: dashboard.metrics)
                    .padding(.vertical, 4)
                MedicationTrendMetricSummary(metric: selectedMetric)
            }

            Section("近期曲线") {
                if selectedMetric.points.isEmpty {
                    Text("还没有可用于趋势计算的服药记录。")
                        .foregroundStyle(.secondary)
                } else {
                    MedicationTrendLineChart(
                        metric: selectedMetric,
                        selectedDate: $selectedDate
                    )
                    .padding(.vertical, 8)

                    MedicationTrendEventLegend(metric: selectedMetric)

                    if let selectedPoint {
                        MedicationTrendPointDetail(point: selectedPoint, topic: selectedMetric.topic)
                    }
                }
            }

            Section("周期对比") {
                TrendPeriodComparisonPanel(metric: selectedMetric)
            }

        }
        .safeAreaInset(edge: .bottom) {
            Color.clear.frame(height: 84)
        }
        .navigationTitle("用药趋势")
        .toolbar(.hidden, for: .tabBar)
        .task {
            await healthKitService.refreshRecentTrendSamples()
        }
    }
}

private struct MedicationTrendDashboardCard: View {
    let dashboard: MedicationTrendDashboard

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: trendDirectionIconName(dashboard.direction))
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(trendDirectionTint(dashboard.direction))
                    .frame(width: 42, height: 42)
                    .background(trendDirectionTint(dashboard.direction).opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                VStack(alignment: .leading, spacing: 4) {
                    Text(dashboard.title)
                        .font(.title3.weight(.semibold))
                    Text(dashboard.summary)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(dashboard.dataQualitySummary)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            ProgressView(value: dashboard.overallScore)
                .tint(trendDirectionTint(dashboard.direction))

            HStack {
                Text(trendDirectionTitle(dashboard.direction))
                Spacer()
                Text("综合 \(percentageText(dashboard.overallScore))%")
                    .monospacedDigit()
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 8)
    }
}

private struct MedicationTrendTopicPicker: View {
    @Binding var selectedTopic: MedicationTrendTopic
    let metrics: [MedicationTrendMetric]

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
            ForEach(metrics) { metric in
                Button {
                    selectedTopic = metric.topic
                } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 6) {
                            Image(systemName: trendTopicIconName(metric.topic))
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(trendDirectionTint(metric.direction))
                            Text(metric.title)
                                .font(.caption.weight(.semibold))
                                .lineLimit(1)
                                .minimumScaleFactor(0.82)
                            Spacer(minLength: 0)
                        }
                        HStack(alignment: .firstTextBaseline) {
                            Text(trendMetricValueText(metric))
                                .font(.headline.monospacedDigit().weight(.semibold))
                            Spacer()
                            Text(trendDirectionTitle(metric.direction))
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
                    .background(
                        selectedTopic == metric.topic ? trendDirectionTint(metric.direction).opacity(0.16) : Color(.secondarySystemGroupedBackground),
                        in: RoundedRectangle(cornerRadius: 8)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(selectedTopic == metric.topic ? trendDirectionTint(metric.direction).opacity(0.45) : .clear, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }
}

private struct MedicationTrendMetricSummary: View {
    let metric: MedicationTrendMetric

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(metric.title, systemImage: trendTopicIconName(metric.topic))
                    .font(.headline)
                    .foregroundStyle(trendDirectionTint(metric.direction))
                Spacer()
                StatusBadge(text: trendDirectionTitle(metric.direction), color: trendDirectionTint(metric.direction))
            }
            Text(metric.summary)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 6)
    }
}

private struct TrendPeriodComparisonPanel: View {
    let metric: MedicationTrendMetric

    private var tint: Color {
        trendDirectionTint(metric.direction)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center, spacing: 10) {
                Label("周期对比", systemImage: "chart.bar.xaxis")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Spacer(minLength: 8)
                TrendDeltaChip(comparison: metric.comparison, tint: tint)
            }

            HStack(alignment: .lastTextBaseline, spacing: 10) {
                Text(trendMetricValueText(metric))
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .foregroundStyle(tint)
                    .monospacedDigit()
                    .contentTransition(.numericText(value: metric.comparison.recentScore))
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
                Text(trendMetricPrimaryValueTitle(metric))
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }

            VStack(spacing: 12) {
                TrendPeriodBar(
                    title: metric.comparison.recentPeriodTitle,
                    value: metric.comparison.recentScore,
                    dayCount: metric.comparison.recentDayCount,
                    scheduledCount: metric.comparison.recentScheduledCount,
                    tint: tint,
                    isPrimary: true
                )

                if let previousScore = metric.comparison.previousScore {
                    TrendPeriodBar(
                        title: metric.comparison.previousPeriodTitle,
                        value: previousScore,
                        dayCount: metric.comparison.previousDayCount,
                        scheduledCount: metric.comparison.previousScheduledCount,
                        tint: .secondary,
                        isPrimary: false
                    )
                } else {
                    TrendPreviousPeriodPlaceholder(title: metric.comparison.previousPeriodTitle)
                }
            }
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(tint.opacity(0.14), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
    }
}

private struct TrendDeltaChip: View {
    let comparison: MedicationTrendPeriodComparison
    let tint: Color

    private var title: String {
        guard comparison.previousScore != nil, let delta = comparison.delta else {
            return "等待对比"
        }
        return trendDeltaText(delta)
    }

    private var chipTint: Color {
        guard comparison.previousScore != nil, let delta = comparison.delta else {
            return .secondary
        }
        if abs(delta) < 0.005 {
            return .secondary
        }
        return delta > 0 ? .green : .orange
    }

    var body: some View {
        Label(title, systemImage: comparison.delta.map { $0 >= 0 ? "arrow.up.right" : "arrow.down.right" } ?? "minus")
            .font(.caption.monospacedDigit().weight(.semibold))
            .foregroundStyle(chipTint)
            .lineLimit(1)
            .minimumScaleFactor(0.78)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(chipTint.opacity(0.12), in: Capsule())
            .overlay(
                Capsule()
                    .stroke(chipTint.opacity(0.18), lineWidth: 1)
            )
            .accessibilityLabel("周期对比 \(title)")
    }
}

private struct TrendPeriodBar: View {
    let title: String
    let value: Double
    let dayCount: Int
    let scheduledCount: Int
    let tint: Color
    let isPrimary: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(title)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text("\(percentageText(value))%")
                    .font((isPrimary ? Font.headline : Font.subheadline).monospacedDigit().weight(.semibold))
                    .foregroundStyle(isPrimary ? tint : .secondary)
                    .lineLimit(1)
            }
            Text("\(dayCount) 天 · \(scheduledCount) 次计划")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.secondary.opacity(0.12))
                    Capsule()
                        .fill(isPrimary ? tint.opacity(0.82) : Color.secondary.opacity(0.45))
                        .frame(width: max(8, proxy.size.width * normalizedTrendScore(value)))
                }
            }
            .frame(height: isPrimary ? 10 : 8)
        }
    }
}

private struct TrendPreviousPeriodPlaceholder: View {
    let title: String

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: "clock.badge.questionmark")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 22, height: 22)
                .background(Color.secondary.opacity(0.10), in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.primary)
                Text("记录不足时不强行生成周期结论。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct MedicationTrendLineChart: View {
    let metric: MedicationTrendMetric
    @Binding var selectedDate: Date?

    private var points: [MedicationTrendChartPoint] {
        metric.points.map {
            MedicationTrendChartPoint(
                date: trendDate(from: $0.date),
                score: $0.score,
                doseChangeCount: $0.doseChangeCount,
                archivedMedicationCount: $0.archivedMedicationCount,
                interruptedMedicationCount: $0.interruptedMedicationCount,
                healthSignalCount: $0.healthSignalCount,
                annotation: $0.annotation
            )
        }
    }

    private var sortedPoints: [MedicationTrendChartPoint] {
        points.sorted { $0.date < $1.date }
    }

    private var renderedPoints: [MedicationTrendRenderedPoint] {
        sortedPoints.enumerated().map { index, point in
            let startIndex = max(0, index - 2)
            let endIndex = min(sortedPoints.count - 1, index + 1)
            let window = sortedPoints[startIndex...endIndex]
            let smoothedScore = window.reduce(0) { partialResult, item in
                partialResult + item.chartScore
            } / Double(window.count)
            return MedicationTrendRenderedPoint(point: point, visualScore: smoothedScore)
        }
    }

    private var eventPoints: [MedicationTrendRenderedPoint] {
        renderedPoints.filter(\.point.hasEventMarker)
    }

    private var selectedPoint: MedicationTrendChartPoint? {
        guard let selectedDate else {
            return sortedPoints.last
        }
        return sortedPoints.min { lhs, rhs in
            abs(lhs.date.timeIntervalSince(selectedDate)) < abs(rhs.date.timeIntervalSince(selectedDate))
        }
    }

    private var selectedRenderedPoint: MedicationTrendRenderedPoint? {
        guard let selectedPoint else {
            return renderedPoints.last
        }
        return renderedPoints.first { $0.point.id == selectedPoint.id }
    }

    private var chartAxisValues: [Double] {
        [0, 0.5, 0.8, 1]
    }

    private var chartXDomain: ClosedRange<Date> {
        guard let first = sortedPoints.first?.date, let last = sortedPoints.last?.date else {
            let today = Calendar.current.startOfDay(for: Date())
            return today...today
        }
        let calendar = Calendar.current
        let start = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: first)) ?? first
        let end = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: last)) ?? last
        return start...end
    }

    private var chartXAxisLabelDates: [Date] {
        guard let first = sortedPoints.first?.date, let last = sortedPoints.last?.date else {
            return []
        }
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: first)
        let end = calendar.startOfDay(for: last)
        let daySpan = max(1, calendar.dateComponents([.day], from: start, to: end).day ?? sortedPoints.count)
        let step = max(2, Int(ceil(Double(daySpan) / 4.0)))
        var dates: [Date] = []
        var current = start
        while current < end {
            dates.append(current)
            guard let next = calendar.date(byAdding: .day, value: step, to: current), next > current else {
                break
            }
            current = next
        }
        return dates
    }

    private var visibleDomainLength: Int {
        let visibleDays = min(14, max(7, sortedPoints.count))
        return visibleDays * 24 * 60 * 60
    }

    private var chartInitialScrollDate: Date {
        guard let last = sortedPoints.last?.date else {
            return Date()
        }
        let calendar = Calendar.current
        return calendar.date(byAdding: .day, value: -min(13, max(6, sortedPoints.count - 1)), to: last) ?? last
    }

    var body: some View {
        let tint = trendDirectionTint(metric.direction)
        VStack(alignment: .leading, spacing: 14) {
            if let selectedPoint {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(AppFormatters.day.string(from: selectedPoint.date))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(selectedPointValueText(selectedPoint))
                            .font(.title2.monospacedDigit().weight(.bold))
                            .foregroundStyle(tint)
                    }

                    Spacer(minLength: 8)

                    if selectedPoint.hasEventMarker {
                        Image(systemName: eventMarkerIconName(for: selectedPoint))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(eventMarkerTint(for: selectedPoint))
                            .frame(width: 30, height: 30)
                            .background(eventMarkerTint(for: selectedPoint).opacity(0.12), in: Circle())
                    }
                }
            }

            Chart {
                ForEach(renderedPoints) { renderedPoint in
                    AreaMark(
                        x: .value("日期", renderedPoint.date),
                        yStart: .value("下限", 0),
                        yEnd: .value("分数", renderedPoint.visualScore)
                    )
                    .interpolationMethod(.monotone)
                    .foregroundStyle(
                        LinearGradient(
                            colors: [tint.opacity(0.20), tint.opacity(0.04)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                    LineMark(
                        x: .value("日期", renderedPoint.date),
                        y: .value("分数", renderedPoint.visualScore)
                    )
                    .interpolationMethod(.monotone)
                    .foregroundStyle(tint)
                    .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                }

                ForEach(eventPoints) { renderedPoint in
                    PointMark(
                        x: .value("事件日期", renderedPoint.date),
                        y: .value("事件分数", renderedPoint.visualScore)
                    )
                    .symbolSize(selectedPoint?.id == renderedPoint.id ? 82 : 52)
                    .foregroundStyle(eventMarkerTint(for: renderedPoint.point))
                }

                RuleMark(y: .value("参考线", 0.8))
                    .foregroundStyle(Color.secondary.opacity(0.26))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))

                if let selectedPoint, let selectedRenderedPoint {
                    RuleMark(x: .value("选中日期", selectedPoint.date))
                        .foregroundStyle(tint.opacity(0.42))
                        .lineStyle(StrokeStyle(lineWidth: 1))

                    PointMark(
                        x: .value("选中日期", selectedPoint.date),
                        y: .value("选中趋势", selectedRenderedPoint.visualScore)
                    )
                    .symbolSize(64)
                    .foregroundStyle(tint)
                }
            }
            .chartXScale(domain: chartXDomain)
            .chartYScale(domain: 0...1)
            .chartScrollableAxes(.horizontal)
            .chartXVisibleDomain(length: visibleDomainLength)
            .chartScrollPosition(initialX: chartInitialScrollDate)
            .chartXSelection(value: $selectedDate)
            .chartYAxis {
                AxisMarks(position: .leading, values: chartAxisValues) { value in
                    AxisGridLine()
                        .foregroundStyle(Color.secondary.opacity(0.16))
                    AxisValueLabel {
                        if let score = value.as(Double.self) {
                            Text("\(percentageText(score))%")
                                .font(.caption2.monospacedDigit())
                        }
                    }
                }
            }
            .chartXAxis {
                AxisMarks(values: chartXAxisLabelDates) {
                    AxisGridLine()
                        .foregroundStyle(Color.secondary.opacity(0.10))
                    AxisValueLabel(format: .dateTime.month(.defaultDigits).day())
                        .font(.caption2)
                }
            }
            .frame(height: 230)
        }
        .padding(14)
        .medicationGlassSurface(cornerRadius: 18, tint: tint, fallbackMaterial: .regularMaterial, isInteractive: true)
        .accessibilityLabel("\(metric.title)趋势曲线")
    }

    private func selectedPointValueText(_ point: MedicationTrendChartPoint) -> String {
        if metric.topic == .healthSignal && point.healthSignalCount == 0 {
            return "暂无数据"
        }
        return "\(percentageText(point.score))%"
    }

    private func eventMarkerTint(for point: MedicationTrendChartPoint) -> Color {
        if point.doseChangeCount > 0 {
            return .purple
        }
        if point.archivedMedicationCount > 0 || point.interruptedMedicationCount > 0 {
            return .orange
        }
        if point.healthSignalCount > 0 {
            return .teal
        }
        return trendDirectionTint(metric.direction)
    }

    private func eventMarkerIconName(for point: MedicationTrendChartPoint) -> String {
        if point.doseChangeCount > 0 {
            return "arrow.triangle.2.circlepath"
        }
        if point.archivedMedicationCount > 0 {
            return "archivebox.fill"
        }
        if point.interruptedMedicationCount > 0 {
            return "pause.circle.fill"
        }
        if point.healthSignalCount > 0 {
            return "heart.text.square.fill"
        }
        return "circle.fill"
    }
}

private struct MedicationTrendRenderedPoint: Identifiable {
    let point: MedicationTrendChartPoint
    let visualScore: Double

    var id: Date { point.id }
    var date: Date { point.date }
}

private struct MedicationTrendEventLegend: View {
    let metric: MedicationTrendMetric

    private var items: [TrendEventLegendItem] {
        var result: [TrendEventLegendItem] = []
        if metric.points.contains(where: { $0.doseChangeCount > 0 }) {
            result.append(TrendEventLegendItem(title: "剂量变化", color: .purple, iconName: "arrow.triangle.2.circlepath"))
        }
        if metric.points.contains(where: { $0.interruptedMedicationCount > 0 || $0.archivedMedicationCount > 0 }) {
            result.append(TrendEventLegendItem(title: "状态变化", color: .orange, iconName: "pause.circle.fill"))
        }
        if metric.points.contains(where: { $0.healthSignalCount > 0 }) {
            result.append(TrendEventLegendItem(title: "健康数据", color: .teal, iconName: "heart.text.square.fill"))
        }
        return result
    }

    var body: some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("事件标记")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    ForEach(items) { item in
                        Label {
                            Text(item.title)
                                .font(.caption.weight(.semibold))
                                .lineLimit(1)
                                .minimumScaleFactor(0.82)
                        } icon: {
                            Image(systemName: item.iconName)
                                .font(.caption.weight(.bold))
                        }
                        .foregroundStyle(item.color)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 6)
                        .background(item.color.opacity(0.12), in: Capsule())
                    }
                }
            }
            .padding(.bottom, 4)
            .accessibilityElement(children: .combine)
        }
    }
}

private struct TrendEventLegendItem: Identifiable {
    let title: String
    let color: Color
    let iconName: String

    var id: String { title }
}

private struct MedicationTrendPointDetail: View {
    let point: MedicationTrendPoint
    let topic: MedicationTrendTopic

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(AppFormatters.day.string(from: trendDate(from: point.date)))
                    .font(.headline)
                Spacer()
                Text(pointValueText)
                    .font(.headline.monospacedDigit())
            }

            TrendPointStatGrid(point: point)

            if !detailText.isEmpty {
                Text(detailText)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            if !eventBadges.isEmpty {
                VStack(alignment: .leading, spacing: 7) {
                    Text("当日事件")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    StatusBadgeFlow {
                        ForEach(eventBadges, id: \.text) { badge in
                            StatusBadge(text: badge.text, color: badge.color)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8))
    }

    private var pointValueText: String {
        if topic == .healthSignal && point.healthSignalCount == 0 {
            return "暂无数据"
        }
        return "\(percentageText(point.score))%"
    }

    private var detailText: String {
        if !point.annotation.isEmpty {
            return point.annotation
        }
        switch topic {
        case .discipline:
            return ""
        case .timing:
            return ""
        case .doseChange:
            return point.doseChangeCount == 0 ? "" : "当天记录 \(point.doseChangeCount) 次剂量变化。"
        case .regimenLoad:
            var parts: [String] = []
            if point.prescriptionMedicationCount > 0 {
                parts.append("\(point.prescriptionMedicationCount) 个处方药计划")
            }
            if point.nonPrescriptionMedicationCount > 0 {
                parts.append("\(point.nonPrescriptionMedicationCount) 个非处方药计划")
            }
            if point.interruptedMedicationCount > 0 {
                parts.append("\(point.interruptedMedicationCount) 个中断状态")
            }
            if point.archivedMedicationCount > 0 {
                parts.append("\(point.archivedMedicationCount) 个归档状态或操作")
            }
            if point.importedMedicationCount > 0 {
                parts.append("\(point.importedMedicationCount) 个导入来源计划")
            }
            return parts.joined(separator: "，")
        case .healthSignal:
            return point.healthSignalCount == 0 ? "" : "当天有 \(point.healthSignalCount) 条授权健康数据。"
        }
    }

    private var eventBadges: [TrendEventBadge] {
        var badges: [TrendEventBadge] = []
        if point.doseChangeCount > 0 {
            badges.append(TrendEventBadge(text: "\(point.doseChangeCount) 次剂量变化", color: .purple))
        }
        if point.interruptedMedicationCount > 0 {
            badges.append(TrendEventBadge(text: "\(point.interruptedMedicationCount) 个中断状态", color: .orange))
        }
        if point.archivedMedicationCount > 0 {
            badges.append(TrendEventBadge(text: "\(point.archivedMedicationCount) 个归档状态", color: .gray))
        }
        if point.healthSignalCount > 0 {
            badges.append(TrendEventBadge(text: "\(point.healthSignalCount) 条健康数据", color: .teal))
        }
        return badges
    }
}

private struct TrendPointStatGrid: View {
    let point: MedicationTrendPoint

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
            TrendPointMiniStat(title: "计划", value: "\(point.scheduledCount)", tint: .blue)
            TrendPointMiniStat(title: "完成", value: "\(point.completedCount)", tint: .green)
            TrendPointMiniStat(title: "稍后", value: "\(point.delayedCount)", tint: .orange)
            TrendPointMiniStat(title: "忽略", value: "\(point.skippedCount)", tint: .red)
        }
    }
}

private struct TrendEventBadge {
    let text: String
    let color: Color
}

private struct TrendPointMiniStat: View {
    let title: String
    let value: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.headline.monospacedDigit().weight(.bold))
                .foregroundStyle(tint)
                .contentTransition(.numericText())
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(tint.opacity(0.12), lineWidth: 1)
        )
    }
}

private struct MedicationTrendChartPoint: Identifiable {
    let date: Date
    let score: Double
    let doseChangeCount: Int
    let archivedMedicationCount: Int
    let interruptedMedicationCount: Int
    let healthSignalCount: Int
    let annotation: String

    var id: Date { date }

    var hasEventMarker: Bool {
        doseChangeCount > 0
            || archivedMedicationCount > 0
            || interruptedMedicationCount > 0
            || healthSignalCount > 0
    }

    var chartScore: Double {
        min(1, max(0, score))
    }
}

private func emptyTrendMetric(topic: MedicationTrendTopic) -> MedicationTrendMetric {
    MedicationTrendMetric(
        topic: topic,
        title: trendTopicTitle(topic),
        score: 0,
        direction: .needsData,
        summary: "继续记录后生成趋势。",
        dataSourceSummary: "",
        formulaSummary: "继续记录后生成透明的权重说明。",
        comparison: MedicationTrendPeriodComparison(
            recentScore: 0,
            confidenceScore: 0,
            recentDayCount: 0,
            previousDayCount: 0,
            recentScheduledCount: 0,
            previousScheduledCount: 0,
            evidenceSummary: "继续记录后生成数据质量说明。"
        ),
        contributorSummary: [],
        formulaComponents: [],
        points: []
    )
}

private func trendTopicTitle(_ topic: MedicationTrendTopic) -> String {
    switch topic {
    case .discipline:
        "用药纪律"
    case .timing:
        "时间稳定"
    case .doseChange:
        "剂量变化"
    case .regimenLoad:
        "用药负担"
    case .healthSignal:
        "健康信号"
    }
}

private func trendTopicIconName(_ topic: MedicationTrendTopic) -> String {
    switch topic {
    case .discipline:
        "checklist.checked"
    case .timing:
        "clock.badge.checkmark"
    case .doseChange:
        "arrow.triangle.2.circlepath"
    case .regimenLoad:
        "pills.fill"
    case .healthSignal:
        "heart.text.square.fill"
    }
}

private func trendDate(from date: DateOnly) -> Date {
    Calendar.current.date(from: DateComponents(year: date.year, month: date.month, day: date.day, hour: 12)) ?? Date()
}

func medicationTrendDashboard(
    tasks: [StoredDoseTask],
    doseChanges: [StoredMedicationDoseChange],
    medications: [StoredMedication],
    plans: [StoredMedicationPlan],
    lifecycleEvents: [StoredMedicationLifecycleEvent] = [],
    healthSignals: [HealthSignalSample] = []
) -> MedicationTrendDashboard {
    MedicationTrendDashboardBuilder().build(
        scheduledDoses: tasks.map(\.coreScheduledDose),
        events: tasks.compactMap(\.coreDoseEventUsingEffectiveAdherenceDate),
        doseChanges: doseChanges.map(\.coreDoseChange),
        planContexts: medicationTrendPlanContexts(tasks: tasks, medications: medications, plans: plans),
        lifecycleEvents: medicationTrendLifecycleEvents(tasks: tasks, storedEvents: lifecycleEvents),
        healthSignals: healthSignals,
        timeZone: TimeZone.current
    )
}

private func medicationTrendPlanContexts(
    tasks: [StoredDoseTask],
    medications: [StoredMedication],
    plans: [StoredMedicationPlan]
) -> [MedicationTrendPlanContext] {
    var medicationIDByPlanID = Dictionary(uniqueKeysWithValues: plans.map { ($0.id, $0.medicationID) })
    for task in tasks where medicationIDByPlanID[task.planID] == nil {
        medicationIDByPlanID[task.planID] = task.medicationID
    }

    return medicationIDByPlanID.compactMap { planID, medicationID in
        guard let medication = medications.first(where: { $0.id == medicationID }) else {
            return nil
        }
        return MedicationTrendPlanContext(
            planID: planID,
            medicationID: medicationID,
            medicationKind: MedicationKind(rawValue: medication.kindRaw) ?? .unknown,
            inputSource: MedicationInputSource(rawValue: medication.inputSourceRaw) ?? .manual,
            lifecycleState: medicationTrendLifecycleState(for: medication.lifecycleStatus)
        )
    }
}

private func medicationTrendLifecycleEvents(
    tasks: [StoredDoseTask],
    storedEvents: [StoredMedicationLifecycleEvent]
) -> [MedicationLifecycleEvent] {
    let taskArchiveEvents = tasks
        .filter { $0.reason.contains("用户已归档") }
        .map {
            MedicationLifecycleEvent(
                medicationID: $0.medicationID,
                state: .archived,
                occurredAt: $0.effectiveAdherenceDate,
                note: "用户归档今日记录"
            )
        }
    return storedEvents.map(\.coreLifecycleEvent) + taskArchiveEvents
}

private func medicationTrendLifecycleState(for status: StoredMedicationLifecycleStatus) -> MedicationLifecycleState {
    switch status {
    case .active:
        .active
    case .interrupted:
        .interrupted
    case .archived:
        .archived
    }
}

func trendDirectionTitle(_ direction: MedicationTrendDirection) -> String {
    switch direction {
    case .improving:
        "正在改善"
    case .stable:
        "趋势平稳"
    case .fluctuating:
        "近期波动"
    case .declining:
        "需要关注"
    case .needsData:
        "继续记录"
    }
}

func trendDirectionTint(_ direction: MedicationTrendDirection) -> Color {
    switch direction {
    case .improving:
        .green
    case .stable:
        .blue
    case .fluctuating:
        .teal
    case .declining:
        .orange
    case .needsData:
        .gray
    }
}

func trendDirectionIconName(_ direction: MedicationTrendDirection) -> String {
    switch direction {
    case .improving:
        "chart.line.uptrend.xyaxis"
    case .stable:
        "equal.circle.fill"
    case .fluctuating:
        "waveform.path.ecg"
    case .declining:
        "chart.line.downtrend.xyaxis"
    case .needsData:
        "chart.xyaxis.line"
    }
}

private func metricComparisonText(_ comparison: MedicationTrendPeriodComparison) -> String {
    let recent = "\(comparison.recentPeriodTitle) \(percentageText(comparison.recentScore))%"
    guard comparison.previousScore != nil, let delta = comparison.delta else {
        return "\(recent)，前一周期不足"
    }
    return "\(recent)，较\(comparison.previousPeriodTitle) \(trendDeltaText(delta))"
}

private func trendMetricValueText(_ metric: MedicationTrendMetric) -> String {
    if metric.direction == .needsData {
        return "暂无数据"
    }
    return "\(percentageText(metric.comparison.recentScore))%"
}

private func trendMetricPrimaryValueTitle(_ metric: MedicationTrendMetric) -> String {
    metric.direction == .needsData ? "当前状态" : "近 7 天"
}

private func trendMetricRecordDaysText(_ metric: MedicationTrendMetric) -> String {
    if metric.topic == .healthSignal {
        let daysWithSamples = metric.points.filter { $0.healthSignalCount > 0 }.count
        return daysWithSamples == 0 ? "等待授权样本" : "\(daysWithSamples) 天有健康数据"
    }
    return "\(metric.points.count) 天"
}

private func normalizedTrendScore(_ value: Double) -> Double {
    min(1, max(0, value))
}

private func trendScoreTint(_ score: Double) -> Color {
    if score >= 0.86 {
        return .green
    }
    if score >= 0.68 {
        return .blue
    }
    if score >= 0.48 {
        return .orange
    }
    return .red
}

private func trendSlopeShortText(_ comparison: MedicationTrendPeriodComparison) -> String {
    if comparison.trendStrengthScore < 0.04 {
        return "近 7 天内部平稳"
    }
    let direction = comparison.trendSlopePerDay > 0 ? "上行" : "下行"
    let dailyPoints = Int((abs(comparison.trendSlopePerDay) * 100).rounded())
    return "\(direction)约 \(dailyPoints) 点/天"
}

private func trendSlopeSummaryText(_ comparison: MedicationTrendPeriodComparison) -> String {
    let strength = percentageText(comparison.trendStrengthScore)
    if comparison.trendStrengthScore < 0.04 {
        return "近 7 天内部走势平稳，方向强度 \(strength)%"
    }
    let direction = comparison.trendSlopePerDay > 0 ? "上行" : "下行"
    let dailyPoints = Int((abs(comparison.trendSlopePerDay) * 100).rounded())
    return "近 7 天呈\(direction)，约 \(dailyPoints) 个百分点/天，方向强度 \(strength)%"
}

private func trendDeltaText(_ delta: Double) -> String {
    let points = Int((abs(delta) * 100).rounded())
    if points == 0 {
        return "持平"
    }
    return delta > 0 ? "上升 \(points) 个百分点" : "下降 \(points) 个百分点"
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

private struct LifecycleActionButton: View {
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

struct MedicationDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
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
    @State private var riskReviewStatusMessage = ""
    @State private var showingDeleteConfirmation = false
    @State private var pendingPermissionGate: AppPermissionGate?

    private var relatedPlans: [StoredMedicationPlan] {
        plans.filter { $0.medicationID == medication.id }
    }

    private var relatedTasks: [StoredDoseTask] {
        tasks.filter { $0.medicationID == medication.id }
    }

    private var relatedMeasurableTasks: [StoredDoseTask] {
        relatedTasks.adherenceMeasurableTasks
    }

    private var relatedDoseChanges: [StoredMedicationDoseChange] {
        doseChanges.filter { $0.medicationID == medication.id }
    }

    private var relatedRiskCards: [StoredRiskCard] {
        riskCards.filter { $0.medicationID == medication.id }
    }

    private var activeRelatedRiskCards: [StoredRiskCard] {
        relatedRiskCards.filter(\.isActive).sorted(by: riskCardSort)
    }

    private var archivedRelatedRiskCards: [StoredRiskCard] {
        relatedRiskCards.filter { $0.isArchived || $0.isResolved }.sorted(by: riskCardSort)
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
            scheduledDoses: relatedMeasurableTasks.map(\.coreScheduledDose),
            events: relatedMeasurableTasks.compactMap(\.coreDoseEventUsingEffectiveAdherenceDate)
        )
    }

    private var effectiveLabel: MedicationLabel? {
        relatedLabel?.coreLabel
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
                VStack(alignment: .leading, spacing: 14) {
                    MedicationHeroPhotoView(
                        photoData: medication.photoData,
                        symbolName: medication.photoSymbolName,
                        tint: medicationColor(for: medication),
                        title: medication.photoData == nil ? "添加药盒或药品照片" : "药盒或药品照片",
                        subtitle: medication.photoData == nil ? "建议拍药盒正面或药品实物，提醒时便于核对。" : "提醒和记录中会优先显示这张本机照片。",
                        boxNumber: medication.boxNumber
                    )
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            MedicationColorMarker(color: medicationColor(for: medication), size: 11)
                            Text(userFacingMedicationName(for: medication))
                                .font(.title2.weight(.semibold))
                        }
                        if !medication.genericName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                           medication.genericName != medication.displayName {
                            Text("通用名 \(medication.genericName)")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        if medicationNeedsNameReview(medication) {
                            Label(medicationNameReviewHint(for: medication), systemImage: "exclamationmark.triangle")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.orange)
                        }
                        Text([medication.strength, medication.form].filter { !$0.isEmpty }.joined(separator: " · "))
                            .foregroundStyle(.secondary)
                        StatusBadgeFlow {
                            StatusBadge(text: medication.kindDisplayName, color: .green)
                            StatusBadge(
                                text: lifecycleClassification.displayStatus.displayName,
                                color: badgeColor(for: lifecycleClassification.displayStatus)
                            )
                            if !medication.boxNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                StatusBadge(text: "编号 \(medication.boxNumber)", color: .blue)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        HStack {
                            PhotosPicker(selection: $selectedDetailPhotoItem, matching: .images) {
                                Label(medication.photoData == nil ? "选择照片" : "更换照片", systemImage: "photo")
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            Button {
                                startDetailPhotoCameraFlow()
                            } label: {
                                Label("拍照", systemImage: "camera")
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
                                    Label("清除", systemImage: "trash")
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }
                        }
                    }
                }
                .padding(.vertical, 8)
                if !photoStatusMessage.isEmpty {
                    Text(photoStatusMessage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            Section("药品信息") {
                HStack {
                    Text("颜色标识")
                    Spacer()
                    HStack(spacing: 8) {
                        MedicationColorMarker(color: medicationColor(for: medication), size: 12)
                        Text(medicationColorOption(for: medication).displayName)
                            .foregroundStyle(.secondary)
                    }
                }
                InfoRow(title: "通用名", value: medication.genericName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "未填写" : medication.genericName)
                InfoRow(title: "规格", value: medication.strength.isEmpty ? "未填写" : medication.strength)
                InfoRow(title: "剂型", value: medication.form.isEmpty ? "未填写" : medication.form)
                InfoRow(title: "药盒编号", value: medication.boxNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "未填写" : medication.boxNumber)
                InfoRow(title: "来源", value: sourceDisplayName(medication.inputSourceRaw))
                if let visibleNotes = MedicationNotesDisplayPolicy.visibleText(from: medication.notes) {
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
                            InfoRow(title: "时区规则", value: timeZonePolicyDisplayName(plan.timeZonePolicyRaw))
                            if let visiblePlanNote = userVisiblePlanSourceNote(plan.sourceNote) {
                                InfoRow(title: "备注", value: visiblePlanNote)
                            }
                        }
                        .padding(.vertical, 6)
                    }
                }
                Button {
                    showingPlanEditor = true
                } label: {
                    Label(relatedPlans.isEmpty ? "建立疗程与提醒" : "修改疗程与提醒", systemImage: "calendar.badge.clock")
                }
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
            }

            Section("近期记录") {
                if relatedMeasurableTasks.isEmpty {
                    Text("暂无服药记录。")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(Array(relatedMeasurableTasks.prefix(5))) { task in
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
                        Label(labelStatusTitle(for: relatedLabel), systemImage: "doc.text.magnifyingglass")
                            .font(.headline)
                        Text(relatedLabel.sourceTitle)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text(labelTimestampText(for: relatedLabel))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        if let reviewedAt = relatedLabel.lastRiskReviewAt {
                            Text("风险识别：\(AppFormatters.day.string(from: reviewedAt)) \(AppFormatters.time.string(from: reviewedAt)) 已更新")
                                .font(.footnote)
                                .foregroundStyle(.green)
                        }
                        StatusBadge(
                            text: activeRelatedRiskCards.isEmpty ? "暂无活跃警示" : "\(activeRelatedRiskCards.count) 条活跃警示",
                            color: activeRelatedRiskCards.isEmpty ? .blue : .orange
                        )
                        if !archivedRelatedRiskCards.isEmpty {
                            StatusBadge(text: "\(archivedRelatedRiskCards.count) 条已归档", color: .secondary)
                        }
                    }
                    .padding(.vertical, 6)
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("建议导入说明书", systemImage: "doc.badge.plus")
                            .font(.headline)
                        StatusBadge(text: "未导入", color: .secondary)
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

                if !riskReviewStatusMessage.isEmpty {
                    Text(riskReviewStatusMessage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

            }

            Section("风险与副作用") {
                if activeRelatedRiskCards.isEmpty {
                    Text("暂无风险提醒。")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(Array(activeRelatedRiskCards.prefix(4))) { card in
                        NavigationLink {
                            RiskCardDetailView(card: card, medicationName: userFacingMedicationName(for: medication))
                        } label: {
                            MedicationRiskCardRow(card: card)
                        }
                    }
                }

                if activeRelatedRiskCards.count > 4 {
                    NavigationLink {
                        RisksView()
                    } label: {
                        Label("查看全部风险提醒", systemImage: "exclamationmark.triangle")
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
                        updateLifecycleStatus(.interrupted, note: "用户在药品详情标记服用中断")
                    },
                    markActive: {
                        updateLifecycleStatus(.active, note: "用户在药品详情恢复正在服用")
                    },
                    archive: {
                        updateLifecycleStatus(.archived, note: "用户在药品详情归档药物")
                    }
                )
                Picker("药品状态", selection: Binding(
                    get: { medication.lifecycleStatus },
                    set: { newValue in
                        updateLifecycleStatus(newValue, note: "用户在药品详情修改药品状态")
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
                if medication.lifecycleStatus == .archived {
                    Button(role: .destructive) {
                        showingDeleteConfirmation = true
                    } label: {
                        Label("删除归档药物", systemImage: "trash")
                    }
                }
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
        .appPermissionPrimer(pendingGate: $pendingPermissionGate) { gate in
            guard gate == .camera else {
                return
            }
            Task {
                await requestDetailPhotoCameraAccess()
            }
        }
        .confirmationDialog("删除归档药物？", isPresented: $showingDeleteConfirmation, titleVisibility: .visible) {
            Button("删除药物和相关记录", role: .destructive) {
                deleteArchivedMedication()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("会删除该药物的提醒、记录、说明书、风险提醒、库存和剂量变化。")
        }
    }

    private func startDetailPhotoCameraFlow() {
        guard AppPermissionGate.isCameraAvailable() else {
            photoStatusMessage = "当前设备没有可用相机。"
            return
        }
        if AppPermissionGate.isCameraAuthorized() {
            showingCameraPhotoCapture = true
            return
        }
        if AppPermissionGate.hasCompletedAuthorization(for: .camera) {
            Task {
                await requestDetailPhotoCameraAccess()
            }
        } else {
            pendingPermissionGate = .camera
        }
    }

    @MainActor
    private func requestDetailPhotoCameraAccess() async {
        guard await AppPermissionGate.requestCameraAccess() else {
            photoStatusMessage = "相机权限未开启，无法拍摄药盒或药品照片。"
            return
        }
        showingCameraPhotoCapture = true
    }

    private func updateLifecycleStatus(_ status: StoredMedicationLifecycleStatus, note: String) {
        guard medication.lifecycleStatus != status else {
            return
        }
        let previousStatus = medication.lifecycleStatus
        medication.lifecycleStatus = status
        modelContext.insert(
            StoredMedicationLifecycleEvent(
                medicationID: medication.id,
                status: status,
                note: note
            )
        )
        try? modelContext.save()
        if status == .archived || status == .interrupted {
            disableFutureTasksForInactiveMedication(status)
        } else if previousStatus == .archived || previousStatus == .interrupted {
            rebuildFutureTasksForReactivatedMedication()
        }
    }

    private func disableFutureTasksForInactiveMedication(_ status: StoredMedicationLifecycleStatus) {
        let now = Calendar.current.startOfDay(for: Date())
        let affectedTasks = relatedTasks.filter { task in
            (task.status == .pending || task.status == .delayed)
                && task.dueAt >= now
        }
        guard !affectedTasks.isEmpty else {
            return
        }
        let notificationService = NotificationService()
        for task in affectedTasks {
            notificationService.cancelReminder(for: task.id)
            task.status = .skipped
            task.recordedAt = nil
            task.reason = status == .interrupted ? "药物已中断，未来提醒已停用。" : "药物已归档，未来提醒已停用。"
        }
        try? modelContext.save()
        Task {
            let liveActivityService = MedicationLiveActivityService()
            for task in affectedTasks {
                await liveActivityService.end(for: task.id)
            }
        }
    }

    private func rebuildFutureTasksForReactivatedMedication() {
        let coordinator = MedicationReminderTaskCoordinator()
        let notificationService = NotificationService()
        let batches = relatedPlans.map { plan in
            coordinator.reconcilePlan(plan, medication: medication, in: modelContext)
        }
        try? modelContext.save()
        let cancelledTaskIDs = batches.flatMap(\.cancelledTaskIDs)
        if !cancelledTaskIDs.isEmpty {
            notificationService.cancelReminders(for: cancelledTaskIDs)
        }
        Task {
            for batch in batches {
                for task in batch.tasks {
                    await notificationService.scheduleReminder(
                        for: task,
                        medication: batch.medication,
                        deliveryMethod: batch.deliveryMethod
                    )
                }
            }
            await notificationService.refreshPendingReminderCount()
        }
    }

    private func deleteArchivedMedication() {
        guard medication.lifecycleStatus == .archived else {
            return
        }
        let medicationID = medication.id
        let relatedTaskIDs = Set(tasks.filter { $0.medicationID == medicationID }.map(\.id))
        let notificationService = NotificationService()
        for taskID in relatedTaskIDs {
            notificationService.cancelReminder(for: taskID)
        }
        Task {
            let liveActivityService = MedicationLiveActivityService()
            for taskID in relatedTaskIDs {
                await liveActivityService.end(for: taskID)
            }
        }
        for log in fetchAllDoseActionLogs() where relatedTaskIDs.contains(log.taskID) {
            modelContext.delete(log)
        }
        for task in tasks where task.medicationID == medicationID {
            modelContext.delete(task)
        }
        for plan in plans where plan.medicationID == medicationID {
            modelContext.delete(plan)
        }
        for change in doseChanges where change.medicationID == medicationID {
            modelContext.delete(change)
        }
        for card in riskCards where card.medicationID == medicationID {
            modelContext.delete(card)
        }
        for stock in stocks where stock.medicationID == medicationID {
            modelContext.delete(stock)
        }
        for label in labels where label.medicationID == medicationID {
            modelContext.delete(label)
        }
        for event in fetchAllLifecycleEvents() where event.medicationID == medicationID {
            modelContext.delete(event)
        }
        modelContext.delete(medication)
        try? modelContext.save()
        dismiss()
    }

    private func fetchAllDoseActionLogs() -> [StoredDoseActionLog] {
        (try? modelContext.fetch(FetchDescriptor<StoredDoseActionLog>())) ?? []
    }

    private func fetchAllLifecycleEvents() -> [StoredMedicationLifecycleEvent] {
        (try? modelContext.fetch(FetchDescriptor<StoredMedicationLifecycleEvent>())) ?? []
    }

    private func saveUserProvidedLabel(rawText: String, sourceTitle: String, confidence: Double) {
        let trimmedText = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else {
            return
        }
        let labelMedicationName = userFacingMedicationName(for: medication)
        let label = relatedLabel ?? StoredMedicationLabel(
            medicationID: medication.id,
            medicationName: labelMedicationName,
            rawText: trimmedText,
            sourceTitle: sourceTitle,
            averageOCRConfidence: confidence
        )
        label.medicationName = labelMedicationName
        label.rawText = trimmedText
        let normalizedSourceTitle = normalizedUserConfirmedLabelSourceTitle(sourceTitle)
        label.sourceTitle = normalizedSourceTitle
        label.averageOCRConfidence = confidence
        label.importedAt = Date()
        if relatedLabel == nil {
            modelContext.insert(label)
        }
        let result = MedicationRiskReviewService.rebuildUserLabelRisks(
            medication: medication,
            label: label,
            in: modelContext
        )
        riskReviewStatusMessage = result.userFacingSummary
        try? modelContext.save()
    }

    private func rebuildLabelRisks() {
        guard let relatedLabel else {
            return
        }
        let result = MedicationRiskReviewService.rebuildUserLabelRisks(
            medication: medication,
            label: relatedLabel,
            in: modelContext
        )
        riskReviewStatusMessage = result.userFacingSummary
    }

    private func sourceDisplayName(_ rawValue: String) -> String {
        switch MedicationInputSource(rawValue: rawValue) {
        case .manual:
            "手动添加"
        case .barcode:
            "药盒条码"
        case .prescriptionImage:
            "医嘱图片导入"
        case .demoData:
            "已保存记录"
        case nil:
            rawValue
        }
    }

    private func timeZonePolicyDisplayName(_ rawValue: String) -> String {
        switch ReminderTimeZonePolicy(rawValue: rawValue) {
        case .localClock:
            "按当地时间提醒"
        case .fixedInterval:
            "按固定间隔提醒"
        case nil:
            "需核对提醒规则"
        }
    }

    private func labelStatusTitle(for label: StoredMedicationLabel) -> String {
        label.sourceTitle == "本地保存说明书摘要" ? "已保存说明书摘要" : "已导入说明书"
    }

    private func labelTimestampText(for label: StoredMedicationLabel) -> String {
        let timestamp = "\(AppFormatters.day.string(from: label.importedAt)) \(AppFormatters.time.string(from: label.importedAt))"
        return label.sourceTitle == "本地保存说明书摘要" ? "保存时间：\(timestamp)" : "导入时间：\(timestamp)"
    }

    private func normalizedUserConfirmedLabelSourceTitle(_ title: String) -> String {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedTitle.isEmpty || trimmedTitle == "本地保存说明书摘要" {
            return "用户确认说明书"
        }
        return trimmedTitle
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

private func userVisiblePlanSourceNote(_ note: String) -> String? {
    let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedNote.isEmpty else {
        return nil
    }

    let hiddenFragments = [
        "用户二次确认后建立",
        "可在详情页继续修改疗程、提醒和库存",
        "按说明书建议建立，用户确认后提醒"
    ]
    guard !hiddenFragments.contains(where: { trimmedNote.contains($0) }) else {
        return nil
    }
    return trimmedNote
}

private func storedPlanSourceNote(from visibleNote: String) -> String {
    visibleNote.trimmingCharacters(in: .whitespacesAndNewlines)
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

private enum AddMedicationCameraAction {
    case barcodeScanner
    case prescriptionImage
    case nameScan
    case medicationPhoto
}

private struct MedicationPhotoSourceSheet: View {
    let hasPhoto: Bool
    let canUseCamera: Bool
    @Binding var selectedPhotoItem: PhotosPickerItem?
    let takePhoto: () -> Void
    let clearPhoto: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 14) {
                Button(action: takePhoto) {
                    MedicationPhotoSourceButtonLabel(
                        title: "拍照",
                        subtitle: canUseCamera ? "拍摄药盒正面或药品实物" : "当前设备没有可用相机",
                        systemImage: "camera.fill",
                        tint: .blue
                    )
                }
                .buttonStyle(.plain)
                .disabled(!canUseCamera)
                .opacity(canUseCamera ? 1 : 0.5)

                PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                    MedicationPhotoSourceButtonLabel(
                        title: hasPhoto ? "更换照片" : "选择照片",
                        subtitle: "从相册选择一张用于提醒核对",
                        systemImage: "photo.fill.on.rectangle.fill",
                        tint: .blue
                    )
                }
                .buttonStyle(.plain)

                if hasPhoto {
                    Button(role: .destructive, action: clearPhoto) {
                        MedicationPhotoSourceButtonLabel(
                            title: "清除当前照片",
                            subtitle: "保留药品资料，只移除照片",
                            systemImage: "trash.fill",
                            tint: .red
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 24)
            .navigationTitle("添加药品照片")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        dismiss()
                    }
                }
            }
            .onChange(of: selectedPhotoItem) { _, newItem in
                if newItem != nil {
                    dismiss()
                }
            }
        }
    }
}

private struct MedicationPhotoSourceButtonLabel: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let tint: Color

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.headline.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 36, height: 36)
                .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct AddMedicationView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @StateObject private var notificationService = NotificationService()
    let option: MedicationAddOption
    @State private var displayName = ""
    @State private var genericName = ""
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
    @State private var escalatesToAlarmWhenUnhandled = true
    @State private var kind: MedicationKind
    @State private var importedText = ""
    @State private var barcodeValue = ""
    @State private var showingReviewAlert = false
    @State private var showingSaveConfirmation = false
    @State private var selectedImageItem: PhotosPickerItem?
    @State private var selectedMedicationPhotoItem: PhotosPickerItem?
    @State private var showingMedicationPhotoSourceDialog = false
    @State private var medicationPhotoData: Data?
    @State private var selectedPhotoSymbolName = "pills.fill"
    @State private var boxNumber = ""
    @State private var isAnalyzingImage = false
    @State private var visionStatusMessage = ""
    @State private var importReview: MedicationImportReview?
    @State private var recognizedBarcodes: [VisionBarcodeRecognitionResult] = []
    @State private var showingCameraScanner = false
    @State private var showingPrescriptionImageCamera = false
    @State private var showingNameScanCamera = false
    @State private var showingMedicationPhotoCamera = false
    @State private var pendingPermissionGate: AppPermissionGate?
    @State private var pendingCameraAction: AddMedicationCameraAction?
    @State private var shouldSaveAfterPermissionGrant = false
    @State private var hasShownNameScanSuggestion = false
    @State private var showingNameScanSuggestion = false

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
                    Section("医嘱识别内容") {
                        Button {
                            startCameraFlow(.prescriptionImage)
                        } label: {
                            Label("拍摄医嘱图片识别", systemImage: "camera.viewfinder")
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(!UIImagePickerController.isSourceTypeAvailable(.camera))

                        PhotosPicker(selection: $selectedImageItem, matching: .images) {
                            Label("选择医嘱图片识别", systemImage: "photo.badge.magnifyingglass")
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
                        Label("提取内容必须按原始医嘱二次确认。", systemImage: "doc.text.magnifyingglass")
                            .foregroundStyle(.secondary)
                    }
                }

                if option.id == .barcodeScan {
                    Section("条码待确认信息") {
                        Button {
                            startCameraFlow(.barcodeScanner)
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
                                        Text("识别结果 · 点击填入")
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
                            Text("生成待确认信息")
                        }
                        .disabled(barcodeValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        ImportReviewSummaryView(review: importReview)
                        Label("条码结果用于记录药盒来源，保存前请按药盒和说明书核对。", systemImage: "barcode.viewfinder")
                            .foregroundStyle(.secondary)
                    }
                }

                Section("药品信息") {
                    HStack(spacing: 10) {
                        Text("名称")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                            .frame(width: 44, alignment: .leading)
                        TextField("药品名称", text: displayNameBinding)
                            .textInputAutocapitalization(.words)
                            .multilineTextAlignment(.leading)
                        if option.id == .manual {
                            Button {
                                startCameraFlow(.nameScan)
                            } label: {
                                Image(systemName: "camera.viewfinder")
                                    .font(.title3.weight(.semibold))
                                    .foregroundStyle(UIImagePickerController.isSourceTypeAvailable(.camera) ? .blue : .secondary)
                            }
                            .buttonStyle(.plain)
                            .disabled(!UIImagePickerController.isSourceTypeAvailable(.camera))
                            .accessibilityLabel("从 iPhone 扫描药名")
                        }
                    }
                    .padding(.vertical, 2)
                    if isAnalyzingImage {
                        ProgressView("正在扫描药名")
                    }
                    if !visionStatusMessage.isEmpty {
                        Text(visionStatusMessage)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    if !displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !hasMeaningfulDisplayName {
                        Text("请输入可核对的药品名称。")
                            .font(.footnote)
                            .foregroundStyle(.orange)
                    }
                    if option.id != .manual || !genericName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        TextField("通用名（可选）", text: $genericName)
                            .textInputAutocapitalization(.words)
                    }
                    MedicationPresetTextField(
                        title: "规格",
                        placeholder: "例如 200 mg 或 10 ml",
                        presets: commonStrengthPresets,
                        text: $strength
                    )
                    MedicationFormAndUnitRow(
                        title: "形态/单位",
                        placeholder: "例如 片剂、滴眼液",
                        presets: commonFormPresets,
                        form: $form,
                        unit: $doseUnit
                    )
                    Picker("类型", selection: $kind) {
                        Text("非处方药").tag(MedicationKind.overTheCounter)
                        Text("处方药").tag(MedicationKind.prescription)
                        Text("待确认").tag(MedicationKind.unknown)
                    }
                    Stepper(value: $doseValue, in: 0.5...10, step: 0.5) {
                        Text("每次 \(doseValue.formatted())")
                    }
                }

                Section("药盒照片与编号") {
                    TextField("药盒编号，例如 A1", text: $boxNumber)
                        .textInputAutocapitalization(.characters)
                    Button {
                        showingMedicationPhotoSourceDialog = true
                    } label: {
                        MedicationHeroPhotoView(
                            photoData: medicationPhotoData,
                            symbolName: selectedPhotoSymbolName,
                            tint: .blue,
                            title: medicationPhotoData == nil ? "在此处添加照片" : "药盒或药品照片",
                            subtitle: boxNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "用于提醒和记录核对。" : "药盒编号已记录。",
                            boxNumber: boxNumber
                        )
                    }
                    .buttonStyle(.plain)
                    if medicationPhotoData != nil {
                        Button("清除当前图片") {
                            medicationPhotoData = nil
                            selectedMedicationPhotoItem = nil
                        }
                    }
                }

                Section("疗程与提醒") {
                    DatePicker("疗程开始", selection: $courseStartDate, displayedComponents: .date)
                    Toggle("设置疗程结束", isOn: $hasCourseEndDate)
                    if hasCourseEndDate {
                        DatePicker("疗程结束", selection: $courseEndDate, in: courseStartDate..., displayedComponents: .date)
                    }
                    ReminderTimesEditor(reminderTimes: $reminderTimes)
                    Picker("提醒方式", selection: $reminderDeliveryMethod) {
                        ForEach(StoredReminderDeliveryMethod.allCases) { method in
                            Text(method.displayName).tag(method)
                        }
                    }
                    Text(reminderDeliveryMethod.detailText)
                        .font(.footnote)
                        .foregroundStyle(reminderDeliveryMethod == .alarm ? .orange : .secondary)
                    Toggle("未处理时使用 iPhone 闹钟再提醒", isOn: $escalatesToAlarmWhenUnhandled)
                    Text("普通提醒 5 分钟内未处理时，可用 iPhone 闹钟加强提醒；关闭后只保留普通提醒。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("药盒库存（可选）") {
                    HStack {
                        Text("剩余数量")
                        Spacer()
                        TextField("0", value: $initialStockQuantity, format: .number.precision(.fractionLength(0...1)))
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 92)
                        Text(localizedMedicationUnit(stockUnit))
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("低量提醒")
                        Spacer()
                        TextField("0", value: $lowStockThreshold, format: .number.precision(.fractionLength(0...1)))
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 92)
                        Text(localizedMedicationUnit(stockUnit))
                            .foregroundStyle(.secondary)
                    }
                    MedicationUnitPicker(title: "库存单位", unit: $stockUnit)
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
                    beginSaveMedicationFlow()
                }
            } message: {
                Text("请确认药品名称、规格、药品形态、每次用量和提醒时间已按药盒、说明书、医生或药师建议核对。")
            }
            .alert("也可以扫描药品名称", isPresented: $showingNameScanSuggestion) {
                Button("继续输入", role: .cancel) {}
                Button("使用扫描") {
                    startCameraFlow(.nameScan)
                }
            } message: {
                Text("你可以点名称右侧的相机图标，扫描药盒上的药品名称。扫描文字仍需按药盒或说明书二次核查。")
            }
            .sheet(isPresented: $showingMedicationPhotoSourceDialog) {
                MedicationPhotoSourceSheet(
                    hasPhoto: medicationPhotoData != nil,
                    canUseCamera: UIImagePickerController.isSourceTypeAvailable(.camera),
                    selectedPhotoItem: $selectedMedicationPhotoItem,
                    takePhoto: {
                        showingMedicationPhotoSourceDialog = false
                        startCameraFlow(.medicationPhoto)
                    },
                    clearPhoto: {
                        medicationPhotoData = nil
                        selectedMedicationPhotoItem = nil
                        showingMedicationPhotoSourceDialog = false
                    }
                )
                .presentationDetents([.height(medicationPhotoData == nil ? 240 : 300)])
                .presentationDragIndicator(.visible)
            }
            .appPermissionPrimer(pendingGate: $pendingPermissionGate) { gate in
                Task {
                    await continueAfterPermissionPrimer(gate)
                }
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
            .sheet(isPresented: $showingPrescriptionImageCamera) {
                CameraPhotoCaptureSheet { image in
                    guard let data = image.jpegData(compressionQuality: 0.9) else {
                        visionStatusMessage = "没有读取到医嘱图片，请重新拍摄。"
                        return
                    }
                    Task {
                        await analyzeImageData(data)
                    }
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
            .sheet(isPresented: $showingMedicationPhotoCamera) {
                CameraPhotoCaptureSheet { image in
                    let data = image.jpegData(compressionQuality: 0.9) ?? Data()
                    medicationPhotoData = normalizedPhotoData(data)
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

    private var displayNameBinding: Binding<String> {
        Binding(
            get: { displayName },
            set: { newValue in
                if option.id == .manual,
                   !hasShownNameScanSuggestion,
                   displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                   !newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    hasShownNameScanSuggestion = true
                    showingNameScanSuggestion = true
                }
                displayName = newValue
            }
        )
    }

    private var canSave: Bool {
        hasMeaningfulDisplayName
    }

    private var hasMeaningfulDisplayName: Bool {
        MedicationNamePolicy.normalizedDisplayName(displayName) != nil
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
        visionStatusMessage = "已生成待确认信息，请核对药盒与说明书。"
    }

    private func startCameraFlow(_ action: AddMedicationCameraAction) {
        guard AppPermissionGate.isCameraAvailable() else {
            visionStatusMessage = "当前设备没有可用相机。"
            return
        }
        if AppPermissionGate.isCameraAuthorized() {
            openCameraAction(action)
            return
        }
        pendingCameraAction = action
        if AppPermissionGate.hasCompletedAuthorization(for: .camera) {
            Task {
                await requestCameraAccessAndOpenPendingAction()
            }
        } else {
            pendingPermissionGate = .camera
        }
    }

    private func openCameraAction(_ action: AddMedicationCameraAction) {
        switch action {
        case .barcodeScanner:
            showingCameraScanner = true
        case .prescriptionImage:
            showingPrescriptionImageCamera = true
        case .nameScan:
            showingNameScanCamera = true
        case .medicationPhoto:
            showingMedicationPhotoCamera = true
        }
    }

    @MainActor
    private func requestCameraAccessAndOpenPendingAction() async {
        guard let action = pendingCameraAction else {
            return
        }
        guard await AppPermissionGate.requestCameraAccess() else {
            visionStatusMessage = "相机权限未开启，无法使用拍摄或扫码。"
            pendingCameraAction = nil
            return
        }
        pendingCameraAction = nil
        openCameraAction(action)
    }

    private func beginSaveMedicationFlow() {
        Task {
            await saveMedicationAfterPermissionCheck()
        }
    }

    @MainActor
    private func saveMedicationAfterPermissionCheck() async {
        shouldSaveAfterPermissionGrant = true
        guard await ensureReminderPermissionForSave() else {
            if pendingPermissionGate == nil {
                shouldSaveAfterPermissionGrant = false
            }
            return
        }
        guard await ensureEscalationAlarmPermissionForSave() else {
            if pendingPermissionGate == nil {
                shouldSaveAfterPermissionGrant = false
            }
            return
        }
        shouldSaveAfterPermissionGrant = false
        saveMedication()
    }

    @MainActor
    private func ensureReminderPermissionForSave() async -> Bool {
        switch reminderDeliveryMethod {
        case .notification:
            if await notificationService.hasUsableNotificationAuthorization() {
                AppPermissionGate.markAuthorizationCompleted(for: .notifications)
                return true
            }
            if AppPermissionGate.hasCompletedAuthorization(for: .notifications) {
                return await requestReminderPermissionForSave(.notifications)
            }
            pendingPermissionGate = .notifications
            return false
        case .alarm:
            if AppPermissionGate.isAlarmAuthorized() {
                AppPermissionGate.markAuthorizationCompleted(for: .alarm)
                return true
            }
            if AppPermissionGate.hasCompletedAuthorization(for: .alarm) {
                return await requestReminderPermissionForSave(.alarm)
            }
            pendingPermissionGate = .alarm
            return false
        }
    }

    @MainActor
    private func ensureEscalationAlarmPermissionForSave() async -> Bool {
        guard escalatesToAlarmWhenUnhandled,
              reminderDeliveryMethod == .notification
        else {
            return true
        }
        if AppPermissionGate.isAlarmAuthorized() {
            AppPermissionGate.markAuthorizationCompleted(for: .alarm)
            return true
        }
        if AppPermissionGate.hasCompletedAuthorization(for: .alarm) {
            return await requestReminderPermissionForSave(.alarm)
        }
        pendingPermissionGate = .alarm
        return false
    }

    @MainActor
    private func requestReminderPermissionForSave(_ gate: AppPermissionGate) async -> Bool {
        switch gate {
        case .notifications:
            let granted = await notificationService.requestAuthorization()
            if granted {
                AppPermissionGate.markAuthorizationCompleted(for: .notifications)
            } else {
                visionStatusMessage = "通知权限未开启，暂不能保存为推送提醒。"
            }
            return granted
        case .alarm:
            let granted = await AppPermissionGate.requestAlarmAccess()
            if granted {
                AppPermissionGate.markAuthorizationCompleted(for: .alarm)
            } else {
                visionStatusMessage = "iPhone 闹钟权限未开启，暂不能保存为闹钟提醒。"
            }
            return granted
        case .camera, .health, .location:
            return false
        }
    }

    @MainActor
    private func continueAfterPermissionPrimer(_ gate: AppPermissionGate) async {
        switch gate {
        case .camera:
            await requestCameraAccessAndOpenPendingAction()
        case .notifications, .alarm:
            guard shouldSaveAfterPermissionGrant else {
                return
            }
            guard await requestReminderPermissionForSave(gate) else {
                shouldSaveAfterPermissionGrant = false
                return
            }
            await saveMedicationAfterPermissionCheck()
        case .health, .location:
            break
        }
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
            let scannedName = MedicationImportTextExtractor.scannedDisplayName(fromText: result.text)
            let structuredFields = MedicationImportTextExtractor.structuredFields(fromPrescriptionText: result.text)
            await MainActor.run {
                if let scannedName {
                    displayName = scannedName
                    if genericName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                       let extractedGenericName = structuredFields.genericName {
                        genericName = extractedGenericName
                    }
                    visionStatusMessage = "已扫描到药品名称，保存前请按药盒核对。"
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
        guard let normalizedDisplayName = MedicationNamePolicy.normalizedDisplayName(displayName) else {
            return
        }
        let noteParts = [
            option.disclaimer,
            importedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : "识别文字：\(importedText.trimmingCharacters(in: .whitespacesAndNewlines))",
            barcodeValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : "条码信息：\(barcodeValue.trimmingCharacters(in: .whitespacesAndNewlines))"
        ].compactMap { $0 }

        let medication = StoredMedication(
            displayName: normalizedDisplayName,
            genericName: genericName.trimmingCharacters(in: .whitespacesAndNewlines),
            kind: kind,
            form: form,
            strength: strength,
            inputSource: inputSource,
            photoSymbolName: selectedPhotoSymbolName,
            photoData: medicationPhotoData,
            boxNumber: boxNumber.trimmingCharacters(in: .whitespacesAndNewlines),
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
            sourceNote: "",
            requiresUserConfirmation: true,
            courseStartAt: courseStartDate,
            courseEndAt: hasCourseEndDate ? courseEndDate : nil,
            reminderTimesRaw: encodedReminderTimes(normalizedReminderTimes),
            reminderDelivery: reminderDeliveryMethod,
            escalatesToAlarmWhenUnhandled: escalatesToAlarmWhenUnhandled
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
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                throw VisionImportError.imageDataUnavailable
            }
            await analyzeImageData(data)
        } catch {
            visionStatusMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func analyzeImageData(_ data: Data) async {
        isAnalyzingImage = true
        visionStatusMessage = ""
        importReview = nil
        recognizedBarcodes = []
        defer {
            isAnalyzingImage = false
        }

        do {
            let service = VisionImportService()
            switch option.id {
            case .manual:
                visionStatusMessage = "手动添加不需要图片识别。"
            case .prescriptionDocumentOCR:
                let result = try await service.recognizePrescriptionText(from: data)
                let review = service.makePrescriptionReview(textResult: result)
                importedText = result.text
                importReview = review
                if let extractedDisplayName = review.draft.displayName,
                   !extractedDisplayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                   !hasMeaningfulDisplayName {
                    displayName = extractedDisplayName
                }
                if genericName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                   let extractedGenericName = review.draft.genericName,
                   !extractedGenericName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    genericName = extractedGenericName
                }
                if strength.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                   let extractedStrength = review.draft.strength,
                   !extractedStrength.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    strength = extractedStrength
                }
                if form.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                   let extractedForm = review.draft.form,
                   !extractedForm.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    form = extractedForm
                }
                if isDefaultDoseInput,
                   let extractedDoseValue = review.draft.doseValue,
                   let extractedDoseUnit = review.draft.doseUnit,
                   !extractedDoseUnit.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    doseValue = extractedDoseValue
                    doseUnit = extractedDoseUnit
                    stockUnit = extractedDoseUnit
                }
                let extractedFieldTitles = importFieldTitles(from: review.draft)
                if extractedFieldTitles.isEmpty {
                    visionStatusMessage = "已识别图片文字，请按原始医嘱核对后保存。"
                } else {
                    visionStatusMessage = "已提取到\(extractedFieldTitles.joined(separator: "、"))；请按原始医嘱核对。"
                }
            case .barcodeScan:
                let barcodes = try await service.recognizeBarcodes(from: data)
                recognizedBarcodes = barcodes
                if let first = barcodes.first {
                    barcodeValue = first.payload
                    importReview = service.makeBarcodeReview(barcode: first)
                    visionStatusMessage = "已识别条码并填入待确认信息。"
                }
            }
        } catch {
            visionStatusMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private var isDefaultDoseInput: Bool {
        abs(doseValue - 1) < 0.0001 && localizedMedicationUnit(doseUnit) == "片"
    }

    private func importFieldTitles(from draft: MedicationImportDraft) -> [String] {
        [
            ("药品名称", draft.displayName),
            ("通用名", draft.genericName),
            ("规格", draft.strength),
            ("剂型", draft.form),
            ("每次剂量", formattedImportedDose(from: draft)),
            ("用法用量", draft.directionsText)
        ].compactMap { title, value in
            guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !value.isEmpty
            else {
                return nil
            }
            return title
        }
    }

    private func formattedImportedDose(from draft: MedicationImportDraft) -> String? {
        guard let doseValue = draft.doseValue,
              let doseUnit = draft.doseUnit?.trimmingCharacters(in: .whitespacesAndNewlines),
              !doseUnit.isEmpty
        else {
            return nil
        }
        return "\(doseValue.formatted()) \(localizedMedicationUnit(doseUnit))"
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
    @State private var showingSaveConfirmation = false
    @State private var pendingPermissionGate: AppPermissionGate?

    init(
        medication: StoredMedication,
        existingLabel: StoredMedicationLabel?,
        save: @escaping (String, String, Double) -> Void
    ) {
        self.medication = medication
        self.existingLabel = existingLabel
        self.save = save
        _rawText = State(initialValue: existingLabel?.rawText ?? "")
        _sourceTitle = State(initialValue: Self.initialSourceTitle(for: existingLabel))
        _confidence = State(initialValue: existingLabel?.averageOCRConfidence ?? 1)
    }

    private var canSave: Bool {
        !rawText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private static func initialSourceTitle(for label: StoredMedicationLabel?) -> String {
        guard let sourceTitle = label?.sourceTitle.trimmingCharacters(in: .whitespacesAndNewlines), !sourceTitle.isEmpty else {
            return "用户导入说明书"
        }
        return sourceTitle == "本地保存说明书摘要" ? "用户确认说明书" : sourceTitle
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("导入方式") {
                    Button {
                        startCameraCaptureFlow()
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

                Section("说明书内容") {
                    TextEditor(text: $rawText)
                        .frame(minHeight: 220)
                    Text("请先按药盒或说明书原件核对文字。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("保存后用于") {
                    Text("App 会根据说明书内容生成风险提醒；不会自动诊断、处方或调整剂量。如有禁忌、相互作用或不适，请咨询医生或药师。")
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
                        showingSaveConfirmation = true
                    }
                    .disabled(!canSave)
                }
            }
            .alert("确认保存说明书？", isPresented: $showingSaveConfirmation) {
                Button("取消", role: .cancel) {}
                Button("已核对，保存") {
                    save(rawText, sourceTitle, confidence)
                    dismiss()
                }
            } message: {
                Text("请确认已按药盒或说明书原件核对文字。保存后会更新本药品的说明书摘要，并重新生成风险提醒。")
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
            .appPermissionPrimer(pendingGate: $pendingPermissionGate) { gate in
                guard gate == .camera else {
                    return
                }
                Task {
                    await requestCameraCaptureAccess()
                }
            }
        }
    }

    private func startCameraCaptureFlow() {
        guard AppPermissionGate.isCameraAvailable() else {
            statusMessage = "当前设备没有可用相机。"
            return
        }
        if AppPermissionGate.isCameraAuthorized() {
            showingCameraCapture = true
            return
        }
        if AppPermissionGate.hasCompletedAuthorization(for: .camera) {
            Task {
                await requestCameraCaptureAccess()
            }
        } else {
            pendingPermissionGate = .camera
        }
    }

    @MainActor
    private func requestCameraCaptureAccess() async {
        guard await AppPermissionGate.requestCameraAccess() else {
            statusMessage = "相机权限未开启，无法拍摄说明书。"
            return
        }
        showingCameraCapture = true
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
                sourceTitle = sourceTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "说明书图片导入" : sourceTitle
                statusMessage = "已识别说明书文字，请按原文核对后保存。"
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
                Section(userFacingMedicationName(for: medication)) {
                    Stepper(value: $remainingQuantity, in: 0...9999, step: 1) {
                        Text("药盒剩余 \(remainingQuantity.formatted()) \(localizedMedicationUnit(unit))")
                    }
                    Stepper(value: $lowStockThreshold, in: 0...9999, step: 1) {
                        Text("低库存阈值 \(lowStockThreshold.formatted()) \(localizedMedicationUnit(unit))")
                    }
                    MedicationUnitPicker(title: "单位", unit: $unit)
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
    @State private var escalatesToAlarmWhenUnhandled: Bool
    @State private var sourceNote: String
    @State private var pendingPermissionGate: AppPermissionGate?
    @State private var shouldSaveAfterPermissionGrant = false
    @State private var permissionStatusMessage = ""

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
        _escalatesToAlarmWhenUnhandled = State(initialValue: plan?.escalatesToAlarmWhenUnhandled ?? true)
        _sourceNote = State(initialValue: userVisiblePlanSourceNote(plan?.sourceNote ?? "") ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(userFacingMedicationName(for: medication)) {
                    Stepper(value: $doseValue, in: 0.5...20, step: 0.5) {
                        Text("每次 \(doseValue.formatted()) \(localizedMedicationUnit(doseUnit))")
                    }
                    MedicationUnitPicker(title: "剂量单位", unit: $doseUnit)
                    DatePicker("剂量生效日期", selection: $doseEffectiveFrom, displayedComponents: .date)
                    Text("仅记录剂量变化时间，不生成医疗建议。")
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
                    ReminderTimesEditor(reminderTimes: $reminderTimes)
                    Picker("提醒方式", selection: $reminderDeliveryMethod) {
                        ForEach(StoredReminderDeliveryMethod.allCases) { method in
                            Text(method.displayName).tag(method)
                        }
                    }
                    Text(reminderDeliveryMethod.detailText)
                        .font(.footnote)
                        .foregroundStyle(reminderDeliveryMethod == .alarm ? .orange : .secondary)
                    Toggle("未处理时使用 iPhone 闹钟再提醒", isOn: $escalatesToAlarmWhenUnhandled)
                    Text("普通提醒 5 分钟内未处理时，可用 iPhone 闹钟加强提醒；关闭后只保留普通提醒。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    if !permissionStatusMessage.isEmpty {
                        Text(permissionStatusMessage)
                            .font(.footnote)
                            .foregroundStyle(.orange)
                    }
                }

                Section("备注（可选）") {
                    TextEditor(text: $sourceNote)
                        .frame(minHeight: 90)
                    Text("可以记录医生、药师或复诊时调整提醒的原因。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("剂量变化备注") {
                    TextEditor(text: $doseChangeNote)
                        .frame(minHeight: 70)
                    Text("可记录复诊调整或规格变化原因。")
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
                        beginSaveFlow()
                    }
                    .disabled(doseUnit.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || reminderTimes.isEmpty)
                }
            }
            .appPermissionPrimer(pendingGate: $pendingPermissionGate) { gate in
                Task {
                    await continuePlanSaveAfterPermissionPrimer(gate)
                }
            }
        }
    }

    private func beginSaveFlow() {
        Task {
            await saveAfterPermissionCheck()
        }
    }

    @MainActor
    private func saveAfterPermissionCheck() async {
        permissionStatusMessage = ""
        shouldSaveAfterPermissionGrant = true
        guard await ensureReminderPermissionForSave() else {
            if pendingPermissionGate == nil {
                shouldSaveAfterPermissionGrant = false
            }
            return
        }
        guard await ensureEscalationAlarmPermissionForSave() else {
            if pendingPermissionGate == nil {
                shouldSaveAfterPermissionGrant = false
            }
            return
        }
        shouldSaveAfterPermissionGrant = false
        save()
    }

    @MainActor
    private func ensureReminderPermissionForSave() async -> Bool {
        switch reminderDeliveryMethod {
        case .notification:
            if await notificationService.hasUsableNotificationAuthorization() {
                AppPermissionGate.markAuthorizationCompleted(for: .notifications)
                return true
            }
            if AppPermissionGate.hasCompletedAuthorization(for: .notifications) {
                return await requestReminderPermissionForSave(.notifications)
            }
            pendingPermissionGate = .notifications
            return false
        case .alarm:
            if AppPermissionGate.isAlarmAuthorized() {
                AppPermissionGate.markAuthorizationCompleted(for: .alarm)
                return true
            }
            if AppPermissionGate.hasCompletedAuthorization(for: .alarm) {
                return await requestReminderPermissionForSave(.alarm)
            }
            pendingPermissionGate = .alarm
            return false
        }
    }

    @MainActor
    private func ensureEscalationAlarmPermissionForSave() async -> Bool {
        guard escalatesToAlarmWhenUnhandled,
              reminderDeliveryMethod == .notification
        else {
            return true
        }
        if AppPermissionGate.isAlarmAuthorized() {
            AppPermissionGate.markAuthorizationCompleted(for: .alarm)
            return true
        }
        if AppPermissionGate.hasCompletedAuthorization(for: .alarm) {
            return await requestReminderPermissionForSave(.alarm)
        }
        pendingPermissionGate = .alarm
        return false
    }

    @MainActor
    private func requestReminderPermissionForSave(_ gate: AppPermissionGate) async -> Bool {
        switch gate {
        case .notifications:
            let granted = await notificationService.requestAuthorization()
            if granted {
                AppPermissionGate.markAuthorizationCompleted(for: .notifications)
            } else {
                permissionStatusMessage = "通知权限未开启，暂不能保存为推送提醒。"
            }
            return granted
        case .alarm:
            let granted = await AppPermissionGate.requestAlarmAccess()
            if granted {
                AppPermissionGate.markAuthorizationCompleted(for: .alarm)
            } else {
                permissionStatusMessage = "iPhone 闹钟权限未开启，暂不能保存为闹钟提醒。"
            }
            return granted
        case .camera, .health, .location:
            return false
        }
    }

    @MainActor
    private func continuePlanSaveAfterPermissionPrimer(_ gate: AppPermissionGate) async {
        guard gate == .notifications || gate == .alarm,
              shouldSaveAfterPermissionGrant
        else {
            return
        }
        guard await requestReminderPermissionForSave(gate) else {
            shouldSaveAfterPermissionGrant = false
            return
        }
        await saveAfterPermissionCheck()
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
            plan.sourceNote = storedPlanSourceNote(from: sourceNote)
            plan.courseStartAt = courseStartDate
            plan.courseEndAt = hasCourseEndDate ? courseEndDate : nil
            plan.reminderTimesRaw = encodedReminderTimes(normalizedTimes)
            plan.reminderDeliveryMethod = reminderDeliveryMethod
            plan.escalatesToAlarmWhenUnhandled = escalatesToAlarmWhenUnhandled
            targetPlan = plan
        } else {
            let newPlan = StoredMedicationPlan(
                medicationID: medication.id,
                doseValue: doseValue,
                doseUnit: normalizedDoseUnit,
                timingSummary: reminderSummary(from: normalizedTimes),
                timeZonePolicy: .localClock,
                sourceNote: storedPlanSourceNote(from: sourceNote),
                requiresUserConfirmation: true,
                courseStartAt: courseStartDate,
                courseEndAt: hasCourseEndDate ? courseEndDate : nil,
                reminderTimesRaw: encodedReminderTimes(normalizedTimes),
                reminderDelivery: reminderDeliveryMethod,
                escalatesToAlarmWhenUnhandled: escalatesToAlarmWhenUnhandled
            )
            modelContext.insert(newPlan)
            targetPlan = newPlan
        }

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
        let reminderBatch = MedicationReminderTaskCoordinator().reconcilePlan(
            targetPlan,
            medication: medication,
            in: modelContext
        )
        applyDoseTimelineToOpenTasks(planID: targetPlan.id)

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

    private func applyDoseTimelineToOpenTasks(planID: UUID) {
        let currentTasks = (try? modelContext.fetch(FetchDescriptor<StoredDoseTask>())) ?? tasks
        let changes = ((try? modelContext.fetch(FetchDescriptor<StoredMedicationDoseChange>())) ?? doseChanges)
            .filter { $0.medicationID == medication.id && ($0.planID == nil || $0.planID == planID) }
            .sorted { lhs, rhs in
                if lhs.effectiveFrom != rhs.effectiveFrom {
                    return lhs.effectiveFrom < rhs.effectiveFrom
                }
                return lhs.changedAt < rhs.changedAt
            }
        for task in currentTasks where task.planID == planID {
            guard task.status == .pending || task.status == .delayed else {
                continue
            }
            let effectiveDose = effectiveDoseAmount(for: task, changes: changes)
            task.doseValue = effectiveDose.value
            task.doseUnit = effectiveDose.unit
        }
    }

    private func effectiveDoseAmount(
        for task: StoredDoseTask,
        changes: [StoredMedicationDoseChange]
    ) -> (value: Double, unit: String) {
        let taskDay = Calendar.current.startOfDay(for: task.dueAt)
        if let latestAppliedChange = changes.last(where: { Calendar.current.startOfDay(for: $0.effectiveFrom) <= taskDay }) {
            return (latestAppliedChange.newDoseValue, latestAppliedChange.newDoseUnit)
        }
        if let firstFutureChange = changes.first(where: {
            Calendar.current.startOfDay(for: $0.effectiveFrom) > taskDay && $0.previousDoseValue != nil
        }) {
            return (firstFutureChange.previousDoseValue ?? task.doseValue, firstFutureChange.previousDoseUnit)
        }
        return (task.doseValue, task.doseUnit)
    }

    private func rescheduleReminders(_ batch: MedicationReminderScheduleBatch) {
        notificationService.cancelReminders(for: batch.cancelledTaskIDs)
        Task {
            await notificationService.scheduleReminderBatches([batch])
        }
    }
}

private struct MedicationPresetTextField: View {
    let title: String
    let placeholder: String
    let presets: [String]
    @Binding var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 44, alignment: .leading)

                TextField(placeholder, text: $text)
                    .textInputAutocapitalization(.never)
                    .multilineTextAlignment(.leading)

                Menu {
                    Button("清空") {
                        text = ""
                    }
                    ForEach(presets, id: \.self) { preset in
                        Button(preset) {
                            text = preset
                        }
                    }
                } label: {
                    Image(systemName: "chevron.down.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("选择\(title)")
                }
            }
        }
        .padding(.vertical, 2)
    }
}

private struct MedicationFormAndUnitRow: View {
    let title: String
    let placeholder: String
    let presets: [String]
    @Binding var form: String
    @Binding var unit: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 72, alignment: .leading)

                TextField(placeholder, text: $form)
                    .textInputAutocapitalization(.never)
                    .multilineTextAlignment(.leading)

                Menu {
                    Button("清空形态") {
                        form = ""
                    }
                    ForEach(presets, id: \.self) { preset in
                        Button(preset) {
                            form = preset
                        }
                    }
                } label: {
                    Image(systemName: "chevron.down.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("选择药品形态")
                }

                Divider()
                    .frame(height: 22)

                Menu {
                    ForEach(MedicationDoseUnitOption.common) { option in
                        Button(option.displayName) {
                            unit = option.id
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(localizedMedicationUnit(unit))
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.blue)
                            .lineLimit(1)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.blue)
                    }
                    .accessibilityLabel("选择剂量单位，当前为\(localizedMedicationUnit(unit))")
                }
            }
        }
        .padding(.vertical, 2)
    }
}

private struct ImportReviewSummaryView: View {
    let review: MedicationImportReview?

    var body: some View {
        if let review {
            VStack(alignment: .leading, spacing: 8) {
                Label(review.canCreateMedication ? "信息可继续补全" : "信息仍需补全", systemImage: review.canCreateMedication ? "checkmark.circle" : "exclamationmark.triangle")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(review.canCreateMedication ? .green : .orange)
                let recognizedFields = recognizedFieldRows(for: review.draft)
                if !recognizedFields.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(recognizedFields) { field in
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text(field.title)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 56, alignment: .leading)
                                Text(field.value)
                                    .font(.caption)
                                    .foregroundStyle(.primary)
                                    .lineLimit(2)
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }
                ForEach(Array(review.issues.enumerated()), id: \.offset) { _, issue in
                    Text(issue.message)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Text("保存前请核对药盒、说明书或医嘱原件。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 6)
        }
    }

    private func recognizedFieldRows(for draft: MedicationImportDraft) -> [ImportReviewFieldRow] {
        [
            ("药名", draft.displayName),
            ("通用名", draft.genericName),
            ("规格", draft.strength),
            ("剂型", draft.form),
            ("剂量", formattedDoseAmount(from: draft)),
            ("用法", draft.directionsText)
        ].compactMap { title, value in
            guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !value.isEmpty
            else {
                return nil
            }
            return ImportReviewFieldRow(title: title, value: value)
        }
    }

    private func formattedDoseAmount(from draft: MedicationImportDraft) -> String? {
        guard let doseValue = draft.doseValue,
              let doseUnit = draft.doseUnit?.trimmingCharacters(in: .whitespacesAndNewlines),
              !doseUnit.isEmpty
        else {
            return nil
        }
        return "\(doseValue.formatted()) \(localizedMedicationUnit(doseUnit))"
    }
}

private struct ImportReviewFieldRow: Identifiable {
    var title: String
    var value: String
    var id: String { title }
}

private struct ReminderTimesEditor: View {
    @Binding var reminderTimes: [Date]

    private let preferredReminderTimes: [(hour: Int, minute: Int)] = [
        (8, 0),
        (13, 0),
        (18, 0),
        (21, 0)
    ]

    var body: some View {
        ForEach(Array(reminderTimes.indices), id: \.self) { index in
            DatePicker(
                "提醒 \(index + 1)",
                selection: Binding(
                    get: {
                        guard reminderTimes.indices.contains(index) else {
                            return defaultReminderDate(hour: 21, minute: 0)
                        }
                        return reminderTimes[index]
                    },
                    set: { newValue in
                        guard reminderTimes.indices.contains(index) else {
                            return
                        }
                        reminderTimes[index] = newValue
                    }
                ),
                displayedComponents: .hourAndMinute
            )
            .id("reminder-\(index)-\(reminderTimes.count)")
        }

        Button {
            addReminder()
        } label: {
            ReminderActionRow(
                title: "添加提醒",
                detail: "已设置 \(reminderTimes.count) 条",
                systemImage: "plus.circle.fill",
                tint: .blue,
                isDisabled: false
            )
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())

        Button {
            removeReminder()
        } label: {
            ReminderActionRow(
                title: "减少提醒",
                detail: reminderTimes.count > 1 ? "删除最后一条" : "至少保留一条",
                systemImage: "minus.circle.fill",
                tint: .red,
                isDisabled: reminderTimes.count <= 1
            )
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .disabled(reminderTimes.count <= 1)
    }

    private func addReminder() {
        let nextReminder = nextAvailableReminderTime()
        withAnimation(.snappy(duration: 0.2, extraBounce: 0.02)) {
            reminderTimes.append(nextReminder)
            reminderTimes = normalizedReminderDates(reminderTimes)
        }
    }

    private func removeReminder() {
        guard reminderTimes.count > 1 else {
            return
        }
        withAnimation(.snappy(duration: 0.2, extraBounce: 0.02)) {
            _ = reminderTimes.removeLast()
            reminderTimes = normalizedReminderDates(reminderTimes)
        }
    }

    private func nextAvailableReminderTime() -> Date {
        let occupiedTimes = Set(normalizedReminderDates(reminderTimes).map(AppFormatters.time.string(from:)))
        for preferredTime in preferredReminderTimes {
            let date = defaultReminderDate(hour: preferredTime.hour, minute: preferredTime.minute)
            if !occupiedTimes.contains(AppFormatters.time.string(from: date)) {
                return date
            }
        }

        let calendar = Calendar.current
        let normalizedDates = normalizedReminderDates(reminderTimes)
        var proposedDate = calendar.date(
            byAdding: .hour,
            value: 2,
            to: normalizedDates.last ?? defaultReminderDate(hour: 21, minute: 0)
        ) ?? defaultReminderDate(hour: 23, minute: 0)

        for _ in 0..<24 {
            let components = calendar.dateComponents([.hour, .minute], from: proposedDate)
            let date = defaultReminderDate(
                hour: components.hour ?? 21,
                minute: components.minute ?? 0
            )
            if !occupiedTimes.contains(AppFormatters.time.string(from: date)) {
                return date
            }
            proposedDate = calendar.date(byAdding: .minute, value: 30, to: proposedDate) ?? date
        }

        let fallbackMinute = min(59, reminderTimes.count)
        return defaultReminderDate(hour: 23, minute: fallbackMinute)
    }
}

private struct ReminderActionRow: View {
    let title: String
    let detail: String
    let systemImage: String
    let tint: Color
    let isDisabled: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.headline.weight(.semibold))
                .foregroundStyle(isDisabled ? .secondary : tint)
                .frame(width: 22)
            Text(title)
                .font(.body.weight(.semibold))
                .foregroundStyle(isDisabled ? .secondary : .primary)
            Spacer()
            Text(detail)
                .font(.footnote.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 5)
    }
}

private enum MedicationNotesDisplayPolicy {
    static func visibleText(from notes: String) -> String? {
        let visibleLines = noteLines(from: notes).filter(isUserVisibleLine)
        return normalizedText(from: visibleLines)
    }

    static func hiddenText(from notes: String) -> String? {
        let hiddenLines = noteLines(from: notes).filter { !isUserVisibleLine($0) }
        return normalizedText(from: hiddenLines)
    }

    static func mergedNotes(visibleText: String, hiddenText: String?) -> String {
        [
            normalizedText(from: [visibleText]),
            hiddenText?.trimmingCharacters(in: .whitespacesAndNewlines)
        ]
            .compactMap { text in
                guard let text, !text.isEmpty else {
                    return nil
                }
                return text
            }
            .joined(separator: "\n")
    }

    private static func noteLines(from notes: String) -> [String] {
        notes
            .split(whereSeparator: \.isNewline)
            .map(String.init)
    }

    private static func normalizedText(from lines: [String]) -> String? {
        let text = lines
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    private static func isUserVisibleLine(_ line: String) -> Bool {
        let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedLine.isEmpty else {
            return false
        }
        let hiddenFragments = [
            "演示",
            "手动录入内容需要按药品包装、说明书或医嘱核对",
            "识别结果仅用于辅助录入",
            "条码结果只用于辅助核对药盒来源",
            "识别文字：",
            "条码信息："
        ]
        return !hiddenFragments.contains { trimmedLine.contains($0) }
    }
}

private struct EditMedicationView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    let medication: StoredMedication
    private let preservedHiddenNotes: String?
    @State private var displayName: String
    @State private var genericName: String
    @State private var strength: String
    @State private var form: String
    @State private var kind: MedicationKind
    @State private var photoData: Data?
    @State private var photoSymbolName: String
    @State private var selectedMedicationPhotoItem: PhotosPickerItem?
    @State private var colorTagRaw: String
    @State private var boxNumber: String
    @State private var notes: String

    init(medication: StoredMedication) {
        self.medication = medication
        preservedHiddenNotes = MedicationNotesDisplayPolicy.hiddenText(from: medication.notes)
        _displayName = State(initialValue: MedicationNamePolicy.normalizedDisplayName(medication.displayName) ?? "")
        _genericName = State(initialValue: medication.genericName)
        _strength = State(initialValue: medication.strength)
        _form = State(initialValue: medication.form)
        _kind = State(initialValue: MedicationKind(rawValue: medication.kindRaw) ?? .unknown)
        _photoData = State(initialValue: medication.photoData)
        _photoSymbolName = State(initialValue: medication.photoSymbolName)
        _colorTagRaw = State(initialValue: MedicationColorOption.resolved(for: medication).id)
        _boxNumber = State(initialValue: medication.boxNumber)
        _notes = State(initialValue: MedicationNotesDisplayPolicy.visibleText(from: medication.notes) ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("药品信息") {
                    TextField("药品名称", text: $displayName)
                    if displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && medicationNeedsNameReview(medication) {
                        Text("原药名无法核对，请补全真实药品名称。")
                            .font(.footnote)
                            .foregroundStyle(.orange)
                    } else if !displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !hasMeaningfulDisplayName {
                        Text("请输入可核对的药品名称。")
                            .font(.footnote)
                            .foregroundStyle(.orange)
                    }
                    TextField("通用名（可选）", text: $genericName)
                    TextField("规格", text: $strength)
                    TextField("剂型", text: $form)
                    Picker("类型", selection: $kind) {
                        Text("非处方药").tag(MedicationKind.overTheCounter)
                        Text("处方药").tag(MedicationKind.prescription)
                        Text("待确认").tag(MedicationKind.unknown)
                    }
                }

                Section("颜色标识") {
                    MedicationColorSelectionGrid(selection: $colorTagRaw)
                }

                Section("药盒照片与编号") {
                    TextField("药盒编号，例如 A1", text: $boxNumber)
                        .textInputAutocapitalization(.characters)
                    MedicationHeroPhotoView(
                        photoData: photoData,
                        symbolName: photoSymbolName,
                        tint: selectedMedicationColor,
                        title: photoData == nil ? "添加药盒或药品照片" : "药盒或药品照片",
                        subtitle: boxNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "用于提醒和记录核对。" : "药盒编号已记录。",
                        boxNumber: boxNumber
                    )
                    PhotosPicker(selection: $selectedMedicationPhotoItem, matching: .images) {
                        Label(photoData == nil ? "选择照片" : "更换照片", systemImage: "photo")
                    }
                    if photoData != nil {
                        Button("清除当前图片") {
                            photoData = nil
                            selectedMedicationPhotoItem = nil
                        }
                    }
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
                        guard let normalizedDisplayName = MedicationNamePolicy.normalizedDisplayName(displayName) else {
                            return
                        }
                        medication.displayName = normalizedDisplayName
                        medication.genericName = genericName.trimmingCharacters(in: .whitespacesAndNewlines)
                        medication.strength = strength
                        medication.form = form
                        medication.kindRaw = kind.rawValue
                        medication.photoSymbolName = photoSymbolName
                        medication.photoData = photoData
                        medication.colorTagRaw = colorTagRaw
                        medication.boxNumber = boxNumber.trimmingCharacters(in: .whitespacesAndNewlines)
                        medication.notes = MedicationNotesDisplayPolicy.mergedNotes(
                            visibleText: notes,
                            hiddenText: preservedHiddenNotes
                        )
                        try? modelContext.save()
                        dismiss()
                    }
                    .disabled(!hasMeaningfulDisplayName)
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

    private var hasMeaningfulDisplayName: Bool {
        MedicationNamePolicy.normalizedDisplayName(displayName) != nil
    }

    private var selectedMedicationColor: Color {
        MedicationColorOption.option(forRawValue: colorTagRaw)?.color ?? MedicationColorOption.common[0].color
    }
}

private struct MedicationColorSelectionGrid: View {
    @Binding var selection: String

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 10)], spacing: 10) {
            ForEach(MedicationColorOption.common) { option in
                Button {
                    selection = option.id
                } label: {
                    HStack(spacing: 8) {
                        MedicationColorMarker(color: option.color, size: 13)
                        Text(option.displayName)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.primary)
                        Spacer(minLength: 0)
                        if selection == option.id {
                            Image(systemName: "checkmark")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(option.color)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(option.color.opacity(selection == option.id ? 0.15 : 0.08), in: RoundedRectangle(cornerRadius: 8))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(option.color.opacity(selection == option.id ? 0.38 : 0.14), lineWidth: 1)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("颜色标识 \(option.displayName)")
                .accessibilityAddTraits(selection == option.id ? .isSelected : [])
            }
        }
        .padding(.vertical, 4)
    }
}

private struct MedicationAddSelection: Identifiable {
    var option: MedicationAddOption
    var id: String { option.id.rawValue }
}

private func addOptionTitle(_ option: MedicationAddOption) -> String {
    option.title
}

private func addOptionSubtitle(_ option: MedicationAddOption) -> String {
    switch option.id {
    case .manual:
        "逐项填写药名、剂量、疗程和提醒。"
    case .prescriptionDocumentOCR:
        "识别医嘱图片后生成待确认信息。"
    case .barcodeScan:
        "扫描或输入药盒条码，保存前再核对药盒信息。"
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
