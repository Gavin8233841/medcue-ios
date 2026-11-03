import Charts
import MedicationAdherenceCore
import PhotosUI
import SwiftData
import SwiftUI
import UIKit

struct MedicationsView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
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
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var listSnapshot = MedicationListSnapshot.empty
    @State private var lastSnapshotRefreshToken = ""
    @State private var lastSnapshotRefreshAt = Date(timeIntervalSinceReferenceDate: 0)

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
        let layout = horizontalSizeClass == .regular
            ? AnyLayout(HStackLayout(alignment: .top, spacing: 24))
            : AnyLayout(VStackLayout(alignment: .leading, spacing: 20))
        ScrollView {
            layout {
                VStack(alignment: .leading, spacing: 18) {
                    if horizontalSizeClass == .regular {
                        Text("我的药盒").font(.title2.bold())
                    }
                HStack {
                    Text("\(snapshot.medications.count) 种药品 · \(snapshot.activeTaskCount) 项待处理")
                        .font(.subheadline).foregroundStyle(.secondary)
                    Spacer()
                    Menu {
                        NavigationLink("用药概览") { MedicationOverviewDetailView() }
                        NavigationLink("待处理任务") { MedicationPendingTasksDetailView() }
                        NavigationLink("药盒与余量") { MedicationStockOverviewView() }
                    } label: { Image(systemName: "ellipsis").padding(10) }
                    .accessibilityLabel("更多用药信息")
                    .medicationGlassButtonStyle()
                }
                .background(alignment: .top) {
                    AppTopGradientScrollReader(tab: .medications, coordinateSpaceName: "MedicationsTopGradientList")
                }
                NavigationLink { RisksView() } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "shield.lefthalf.filled")
                        Text("风险复核").fontWeight(.semibold)
                        Text(activeRiskCards.isEmpty ? "暂无活跃" : "\(activeRiskCards.count) 项可查看")
                            .font(.subheadline)
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption.bold())
                    }
                    .foregroundStyle(activeRiskCards.isEmpty ? Color.secondary : Color.orange)
                    .padding(16)
                    .background(.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 20))
                }
                .buttonStyle(.plain)
                if horizontalSizeClass == .regular {
                    ForEach(StoredMedicationLifecycleStatus.allCases) { status in
                        Button { selectedLifecycleStatus = status } label: {
                            HStack {
                                Text(status.displayName)
                                Spacer()
                                Text("\(snapshot.count(for: status))").monospacedDigit()
                            }.padding(12).frame(maxWidth: .infinity)
                        }
                        .medicationGlassButtonStyle(prominent: selectedLifecycleStatus == status)
                    }
                    NavigationLink { MedicationStockOverviewView() } label: {
                        Label("药盒与余量", systemImage: "shippingbox")
                    }.padding(.top, 8)
                } else {
                    Picker("药品分组", selection: $selectedLifecycleStatus) {
                        ForEach(StoredMedicationLifecycleStatus.allCases) { status in
                            Text("\(status.displayName) \(snapshot.count(for: status))").tag(status)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                }
                .frame(maxWidth: horizontalSizeClass == .regular ? 240 : .infinity, alignment: .leading)
                let visibleMedications = snapshot.visibleMedications(for: selectedLifecycleStatus)
                if snapshot.isPlaceholder && !medications.isEmpty {
                    ProgressView("正在整理药品").frame(maxWidth: .infinity)
                } else if visibleMedications.isEmpty {
                    ContentUnavailableView("暂无\(selectedLifecycleStatus.displayName)药品", systemImage: "pills")
                } else {
                    LazyVGrid(columns: dynamicTypeSize.isAccessibilitySize ? [GridItem(.flexible())] : (horizontalSizeClass == .regular ? [GridItem(.flexible()), GridItem(.flexible())] : [GridItem(.adaptive(minimum: 160), spacing: 16)]), spacing: 16) {
                        ForEach(visibleMedications) { medication in
                            NavigationLink(value: MedicationDetailRoute(medicationID: medication.id)) {
                                MedicationGalleryCard(medication: medication, nextTask: snapshot.nextTask(for: medication))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .frame(maxWidth: 1100)
            .padding(.horizontal, 20).padding(.vertical, 12)
            .frame(maxWidth: .infinity)
        }
        .background(Color(.systemGroupedBackground))
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
