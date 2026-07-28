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
                .accessibilityIdentifier(AppAccessibilityID.medicationAdd)
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
