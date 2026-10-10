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
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .body) private var minimumBrowseColumnWidth: CGFloat = 300
    @ScaledMetric(relativeTo: .body) private var minimumDetailColumnWidth: CGFloat = 420
    @State private var browseSession = MedicationBrowseSession()
    @State private var preferredCompactColumn: NavigationSplitViewColumn = .sidebar
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
        GeometryReader { geometry in
            // Keep one host and one detail subtree through every size change. These
            // are content budgets, not device dimensions or a Duo posture detector.
            let canShowColumns = horizontalSizeClass == .regular
                && !dynamicTypeSize.isAccessibilitySize
                && geometry.size.width >= minimumBrowseColumnWidth + minimumDetailColumnWidth
            NavigationSplitView(preferredCompactColumn: $preferredCompactColumn) {
                ScrollViewReader { proxy in
                    medicationList
                        .onChange(of: preferredCompactColumn) { _, column in
                            if column == .sidebar, let anchor = browseSession.returnToList() {
                                proxy.scrollTo(anchor, anchor: .center)
                            }
                        }
                        .onAppear {
                            if preferredCompactColumn == .sidebar, let anchor = browseSession.returnToList() {
                                proxy.scrollTo(anchor, anchor: .center)
                            }
                        }
                }
                .navigationSplitViewColumnWidth(min: minimumBrowseColumnWidth, ideal: minimumBrowseColumnWidth)
            } detail: {
                selectedMedicationDetail
            }
            .navigationSplitViewStyle(.balanced)
            .environment(\.horizontalSizeClass, canShowColumns ? .regular : .compact)
        }
        .onChange(of: Set(medications.map(\.id))) { previousIDs, currentIDs in
            // The full query, never the filtered/snapshot list, establishes removal.
            let removedIDs = previousIDs.subtracting(currentIDs)
            let wasSelected = browseSession.selectedMedicationID
            browseSession.medicationsWereDeleted(removedIDs)
            if wasSelected != nil && browseSession.selectedMedicationID == nil {
                preferredCompactColumn = .sidebar
            }
        }
    }

    @ViewBuilder
    private var selectedMedicationDetail: some View {
        if let id = browseSession.selectedMedicationID,
           let medication = medications.first(where: { $0.id == id }) {
            // Identity changes only when selecting a DIFFERENT medication, never
            // when the window, query filter or text size changes.
            MedicationDetailView(medication: medication)
                .id(id)
        } else {
            ContentUnavailableView("选择药品", systemImage: "pills", description: Text("从列表选择药品，查看计划与记录。"))
                .navigationTitle("药品详情")
        }
    }

    private var lifecycleSelection: Binding<StoredMedicationLifecycleStatus> {
        Binding(
            get: { browseSession.selectedLifecycleStatus },
            set: { status in
                withAnimation(.snappy(duration: 0.24, extraBounce: 0.01)) {
                    browseSession.setLifecycleStatus(status)
                }
            }
        )
    }

    private var searchQuery: [String] {
        MedicationBrowseSearchTextNormalizer.tokenize(browseSession.searchText)
    }

    private func filteredMedications(for status: StoredMedicationLifecycleStatus) -> [StoredMedication] {
        let visibleMedications = listSnapshot.visibleMedications(for: status)
        guard !searchQuery.isEmpty else {
            return visibleMedications
        }
        return visibleMedications.filter { medication in
            MedicationBrowseSearchIndex(medication: medication).matches(query: searchQuery)
        }
    }

    @ViewBuilder
    private var medicationList: some View {
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
                    selectedStatus: lifecycleSelection,
                    count: { snapshot.count(for: $0) }
                )
            }

            Section(browseSession.selectedLifecycleStatus.displayName) {
                let visibleMedications = filteredMedications(for: browseSession.selectedLifecycleStatus)
                let firstMedication = visibleMedications.first
                let nextTask = firstMedication.flatMap { snapshot.nextTask(for: $0) }
                if snapshot.isPlaceholder && !medications.isEmpty {
                    Label("正在整理药品", systemImage: "hourglass")
                        .foregroundStyle(.secondary)
                } else if visibleMedications.isEmpty {
                    if !searchQuery.isEmpty {
                        ContentUnavailableView.search(text: browseSession.searchText)
                    } else {
                        Text("还没有添加药品。")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    if searchQuery.isEmpty {
                        Button {
                            withAnimation(.snappy(duration: 0.24, extraBounce: 0.01)) {
                                browseSession.isGroupExpanded.toggle()
                            }
                        } label: {
                            medicationLifecycleGroupHeader(
                                status: browseSession.selectedLifecycleStatus,
                                count: visibleMedications.count,
                                firstMedication: firstMedication,
                                nextTask: nextTask,
                                isExpanded: browseSession.isGroupExpanded
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(
                            medicationLifecycleGroupAccessibilityLabel(
                                status: browseSession.selectedLifecycleStatus,
                                count: visibleMedications.count,
                                firstMedication: firstMedication,
                                nextTask: nextTask
                            )
                        )
                        .accessibilityValue(browseSession.isGroupExpanded ? "已展开" : "已折叠")
                    } else {
                        medicationLifecycleGroupHeader(
                            status: browseSession.selectedLifecycleStatus,
                            count: visibleMedications.count,
                            firstMedication: firstMedication,
                            nextTask: nextTask,
                            isExpanded: true
                        )
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(
                            medicationLifecycleGroupAccessibilityLabel(
                                status: browseSession.selectedLifecycleStatus,
                                count: visibleMedications.count,
                                firstMedication: firstMedication,
                                nextTask: nextTask
                            )
                        )
                        .accessibilityValue("搜索结果已展开")
                        .accessibilityAddTraits(.isHeader)
                    }

                    if browseSession.isGroupExpanded || !searchQuery.isEmpty {
                        ForEach(visibleMedications) { medication in
                            Button {
                                guard medications.contains(where: { $0.id == medication.id }) else { return }
                                browseSession.select(medication.id)
                                preferredCompactColumn = .detail
                            } label: {
                                HStack(alignment: .top, spacing: 8) {
                                    MedicationCardRow(
                                        medication: medication,
                                        plan: snapshot.plan(for: medication),
                                        taskCount: snapshot.taskCount(for: medication),
                                        nextTask: snapshot.nextTask(for: medication),
                                        stockProjection: snapshot.stockProjection(for: medication),
                                        lifecycleClassification: snapshot.lifecycleClassification(for: medication)
                                    )
                                    if browseSession.selectedMedicationID == medication.id {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(.tint)
                                            .accessibilityHidden(true)
                                    }
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .id(medication.id)
                            .accessibilityIdentifier("medication.browse.row.\(medication.id.uuidString)")
                            .accessibilityAddTraits(browseSession.selectedMedicationID == medication.id ? .isSelected : [])
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
        .searchable(
            text: $browseSession.searchText,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: "搜索药品名称、通用名或规格"
        )
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

    private func medicationLifecycleGroupHeader(
        status: StoredMedicationLifecycleStatus,
        count: Int,
        firstMedication: StoredMedication?,
        nextTask: StoredDoseTask?,
        isExpanded: Bool
    ) -> some View {
        HStack(spacing: 8) {
            MedicationLifecycleGroupSummaryRow(
                status: status,
                count: count,
                firstMedication: firstMedication,
                nextTask: nextTask
            )
            Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                .font(.footnote.weight(.bold))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
        }
        .contentShape(Rectangle())
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

// Ephemeral navigation state only. No model objects, persistence, or actions.
// Kept in this already-compiled file to avoid the separately owned PBX project.
struct MedicationBrowseSession {
    private(set) var selectedMedicationID: UUID?
    private(set) var returnAnchorID: UUID?
    var searchText = ""
    var selectedLifecycleStatus: StoredMedicationLifecycleStatus = .active
    var isGroupExpanded = false

    mutating func select(_ id: UUID) {
        selectedMedicationID = id
        returnAnchorID = id
    }

    mutating func setLifecycleStatus(_ status: StoredMedicationLifecycleStatus) {
        selectedLifecycleStatus = status
        isGroupExpanded = false
    }

    @discardableResult
    func returnToList() -> UUID? {
        // Back changes presentation only; the selected item and return anchor survive.
        returnAnchorID
    }

    mutating func medicationsWereDeleted(_ ids: Set<UUID>) {
        if let selectedMedicationID, ids.contains(selectedMedicationID) {
            self.selectedMedicationID = nil
        }
        if let returnAnchorID, ids.contains(returnAnchorID) {
            self.returnAnchorID = nil
        }
    }
}

// Temporary search bridge from PR #73 @ 903f67ee1a77531c5874f5638688de39ab6a851e.
// Algorithms below are unchanged except for type names and removal of imports.
// On serial integration of #73, use its formal helpers and remove these types.

/// 搜索文本规范化工具，用于统一搜索查询和可搜索内容的格式
enum MedicationBrowseSearchTextNormalizer {
    /// 规范化单个字符串：统一大小写、全半角、可忽略标点和空白
    static func normalize(_ text: String) -> String {
        var result = text
        result = result.lowercased()
        result = convertFullwidthToHalfwidth(result)
        result = replaceIgnorablePunctuationWithWhitespace(result)
        return result.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }

    /// 将查询字符串按空格分割为非空词
    static func tokenize(_ query: String) -> [String] {
        let normalized = normalize(query)
        return normalized.split(whereSeparator: { $0.isWhitespace }).map(String.init)
    }

    /// 检查所有查询词是否都能在目标文本中找到（子串匹配）
    static func matches(query: [String], in text: String) -> Bool {
        let normalizedQuery = query.flatMap(tokenize)
        guard !normalizedQuery.isEmpty else {
            return true
        }
        let normalizedText = normalize(text)
        let compactText = removingSeparators(from: normalizedText)
        return normalizedQuery.allSatisfy { token in
            normalizedText.contains(token)
                || compactText.contains(removingSeparators(from: token))
        }
    }

    private static func convertFullwidthToHalfwidth(_ text: String) -> String {
        var result = ""
        for char in text {
            let scalar = char.unicodeScalars.first
            if scalar?.value == 0x3000 {
                result.append(" ")
                continue
            }
            if let scalar = scalar, (0xFF01...0xFF5E).contains(scalar.value) {
                let halfwidthValue = scalar.value - 0xFEE0
                if let halfwidthScalar = UnicodeScalar(halfwidthValue) {
                    result.append(Character(halfwidthScalar))
                    continue
                }
            }
            result.append(char)
        }
        return result
    }

    private static func replaceIgnorablePunctuationWithWhitespace(_ text: String) -> String {
        String(text.map { character in
            character.unicodeScalars.allSatisfy(CharacterSet.punctuationCharacters.contains)
                ? " "
                : character
        })
    }

    private static func removingSeparators(from text: String) -> String {
        text.filter { !$0.isWhitespace }
    }
}

/// 药品搜索索引，用于快速匹配搜索查询
struct MedicationBrowseSearchIndex {
    let medication: StoredMedication
    let searchableText: String

    init(medication: StoredMedication) {
        self.medication = medication

        let fields = [
            medication.displayName,
            medication.genericName,
            medication.strength,
            medication.form,
            medication.kindDisplayName,
            medication.notes
        ]
        .compactMap { $0 }
        .filter { !$0.isEmpty }

        self.searchableText = MedicationBrowseSearchTextNormalizer.normalize(
            fields.joined(separator: " ")
        )
    }

    func matches(query: [String]) -> Bool {
        MedicationBrowseSearchTextNormalizer.matches(query: query, in: searchableText)
    }
}
