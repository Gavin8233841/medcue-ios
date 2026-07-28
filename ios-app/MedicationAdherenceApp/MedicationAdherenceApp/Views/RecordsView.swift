import MedicationAdherenceCore
import SwiftData
import SwiftUI

struct RecordsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \StoredDoseTask.dueAt, order: .reverse) private var tasks: [StoredDoseTask]
    @Query(sort: \StoredMedication.displayName) private var medications: [StoredMedication]
    @Query(sort: \StoredMedicationPlan.createdAt) private var plans: [StoredMedicationPlan]
    @Query(sort: \StoredMedicationDoseChange.effectiveFrom, order: .reverse) private var doseChanges: [StoredMedicationDoseChange]
    @Query(sort: \StoredMedicationLifecycleEvent.occurredAt, order: .reverse) private var lifecycleEvents: [StoredMedicationLifecycleEvent]
    @Query(sort: \StoredDoseActionLog.occurredAt, order: .reverse) private var actionLogs: [StoredDoseActionLog]
    let hidesTabBar: Bool
    @State private var selectedDate = Date()
    @State private var displayedMonth = Calendar.current.dateInterval(of: .month, for: Date())?.start ?? Date()
    @State private var monthTransitionDirection = 1
    @State private var selectedDateForDetail: DoseDateSelection?
    @State private var selectedTaskForCorrection: StoredDoseTask?
    @State private var expandedHistoryGroupIDs: Set<String> = []
    @State private var trendPreviewDashboard: MedicationTrendDashboard?
    @State private var lastTrendPreviewToken = ""
    @State private var lastTrendPreviewAt = Date(timeIntervalSinceReferenceDate: 0)
    @State private var renderState: RecordsRenderState?
    @State private var lastRenderStateToken = ""

    init(hidesTabBar: Bool = true) {
        self.hidesTabBar = hidesTabBar
    }

    private var measurableTasks: [StoredDoseTask] {
        tasks.adherenceMeasurableTasks
    }

    private var isPresentingModalDetail: Bool {
        selectedDateForDetail != nil || selectedTaskForCorrection != nil
    }

    private var trendPreviewToken: String {
        RecordsTrendPreviewSignature.id(
            tasks: measurableTasks,
            doseChanges: doseChanges,
            medications: medications,
            plans: plans,
            lifecycleEvents: lifecycleEvents
        )
    }

    private var renderStateToken: String {
        RecordsRenderStateSignature.id(
            tasks: tasks,
            medications: medications,
            doseChanges: doseChanges,
            actionLogs: actionLogs
        )
    }

    var body: some View {
        let renderToken = renderStateToken
        let state = (lastRenderStateToken == renderToken ? renderState : nil) ?? makeRenderState()

        ScrollView {
            LazyVStack(spacing: 10) {
                RecordsModuleIndexCard(
                    insight: state.snapshot.insight,
                    historyCount: state.historyTasks.count,
                    latestHistoryTask: state.historyTasks.first,
                    weekSummaryCounts: state.snapshot.weekSummaryCounts,
                    weekDays: daysInCurrentWeek(),
                    tasksForDay: state.snapshot.tasks(on:),
                    doseChangesForDay: state.snapshot.doseChanges(on:),
                    dashboard: trendPreviewDashboard,
                    overviewDestination: {
                        RecordsOverviewDetailPage(
                            insight: state.snapshot.insight,
                            historyCount: state.historyTasks.count,
                            upcomingCount: state.snapshot.upcomingTasks.count,
                            recentDays: state.snapshot.recentDays
                        )
                    },
                    calendarDestination: {
                        RecordsCalendarDetailPage(
                            selectedDate: $selectedDate,
                            displayedMonth: $displayedMonth,
                            monthRange: monthBrowsingRange,
                            days: daysInDisplayedMonth(),
                            snapshot: state.snapshot,
                            doseChanges: doseChanges,
                            transitionDirection: monthTransitionDirection,
                            moveMonth: moveDisplayedMonth,
                            openDay: openDayDetail,
                            openTask: { selectedTaskForCorrection = $0 }
                        )
                    },
                    trendDestination: {
                        MedicationTrendDetailView()
                    },
                    historyDestination: {
                        RecordsHistoryDetailPage(
                            historyTasks: state.historyTasks,
                            historyGroups: state.historyGroups,
                            expandedHistoryGroupIDs: $expandedHistoryGroupIDs,
                            medication: state.snapshot.medication(for:),
                            openTask: { selectedTaskForCorrection = $0 }
                        )
                    }
                )
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, hidesTabBar ? 28 : 96)
            .background(alignment: .top) {
                AppTopGradientScrollReader(tab: .records, coordinateSpaceName: "RecordsTopGradientScroll")
            }
        }
        .coordinateSpace(name: "RecordsTopGradientScroll")
        .background(Color(.systemGroupedBackground))
        .accessibilityHidden(isPresentingModalDetail)
        .navigationTitle("记录")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(hidesTabBar ? .hidden : .visible, for: .tabBar)
        .onChange(of: selectedDate) { _, newValue in
            syncDisplayedMonth(to: newValue)
        }
        .task(id: renderToken) {
            refreshRenderStateIfNeeded(token: renderToken)
        }
        .task(id: trendPreviewToken) {
            await refreshTrendPreview(token: trendPreviewToken)
        }
        .sheet(item: $selectedTaskForCorrection) { task in
            DoseRecordCorrectionView(
                task: task,
                medication: state.snapshot.medication(for: task)
            )
        }
        .navigationDestination(item: $selectedDateForDetail) { selection in
            DayDoseDetailSheet(
                date: selection.date,
                tasks: state.snapshot.tasks(on: selection.date),
                actionLogs: state.snapshot.actionLogs(on: selection.date),
                doseChanges: state.snapshot.doseChanges(on: selection.date),
                allDoseChanges: doseChanges,
                medication: state.snapshot.medication(for:),
                medicationForDoseChange: state.snapshot.medication(for:),
                medicationForActionLog: state.snapshot.medication(forActionLog:),
                isPresentingCorrection: selectedTaskForCorrection != nil,
                openTask: { selectedTaskForCorrection = $0 }
            )
        }
    }

    private func makeRenderState() -> RecordsRenderState {
        RecordsRenderState(
            tasks: tasks,
            medications: medications,
            doseChanges: doseChanges,
            actionLogs: actionLogs,
            now: Date(),
            calendar: Calendar.current
        )
    }

    @MainActor
    private func refreshRenderStateIfNeeded(token: String) {
        guard token != lastRenderStateToken || renderState == nil else {
            return
        }
        renderState = makeRenderState()
        lastRenderStateToken = token
    }

    @MainActor
    private func refreshTrendPreview(token: String) async {
        if lastTrendPreviewToken == token,
           trendPreviewDashboard != nil,
           Date().timeIntervalSince(lastTrendPreviewAt) < 30 {
            return
        }
        let input = medicationTrendDashboardInput(
            tasks: measurableTasks,
            doseChanges: doseChanges,
            medications: medications,
            plans: plans,
            lifecycleEvents: lifecycleEvents
        )
        try? await Task.sleep(for: .milliseconds(90))
        guard !Task.isCancelled else {
            return
        }
        let dashboard = await Task.detached(priority: .userInitiated) {
            input.build()
        }.value
        guard !Task.isCancelled else {
            return
        }
        trendPreviewDashboard = dashboard
        lastTrendPreviewToken = token
        lastTrendPreviewAt = Date()
    }

    private func daysInCurrentWeek() -> [Date] {
        let calendar = Calendar.current
        let weekAnchor = calendar.dateInterval(of: .weekOfYear, for: selectedDate)?.start ?? Date()
        return (0..<7).compactMap { offset in
            calendar.date(byAdding: .day, value: offset, to: weekAnchor)
        }
    }

    private func daysInCurrentMonth() -> [Date] {
        daysInMonth(containing: selectedDate)
    }

    private func daysInDisplayedMonth() -> [Date] {
        daysInMonth(containing: displayedMonth)
    }

    private func daysInMonth(containing date: Date) -> [Date] {
        let calendar = Calendar.current
        let monthAnchor = calendar.dateInterval(of: .month, for: date)?.start ?? Date()
        guard let range = calendar.range(of: .day, in: .month, for: monthAnchor) else {
            return []
        }
        return range.compactMap { day in
            calendar.date(byAdding: .day, value: day - 1, to: monthAnchor)
        }
    }

    private func openDayDetail(_ date: Date) {
        selectedDate = date
        selectedDateForDetail = DoseDateSelection(date: date)
    }

    private var monthBrowsingRange: ClosedRange<Date> {
        let calendar = Calendar.current
        let currentMonth = calendar.dateInterval(of: .month, for: Date())?.start ?? Date()
        let earliestMonth = calendar.date(byAdding: .month, value: -23, to: currentMonth) ?? currentMonth
        return earliestMonth...currentMonth
    }

    private func moveDisplayedMonth(by offset: Int) {
        let calendar = Calendar.current
        guard let nextMonth = calendar.date(byAdding: .month, value: offset, to: displayedMonth) else {
            return
        }
        let clampedMonth = clampedMonth(nextMonth)
        guard !calendar.isDate(displayedMonth, equalTo: clampedMonth, toGranularity: .month) else {
            return
        }
        monthTransitionDirection = offset < 0 ? -1 : 1
        displayedMonth = clampedMonth
        if !calendar.isDate(selectedDate, equalTo: clampedMonth, toGranularity: .month) {
            selectedDate = nearestSelectableDay(in: clampedMonth)
        }
    }

    private func syncDisplayedMonth(to date: Date) {
        let calendar = Calendar.current
        let month = calendar.dateInterval(of: .month, for: date)?.start ?? date
        let clamped = clampedMonth(month)
        if !calendar.isDate(displayedMonth, equalTo: clamped, toGranularity: .month) {
            displayedMonth = clamped
        }
    }

    private func clampedMonth(_ date: Date) -> Date {
        let calendar = Calendar.current
        let month = calendar.dateInterval(of: .month, for: date)?.start ?? date
        return min(max(month, monthBrowsingRange.lowerBound), monthBrowsingRange.upperBound)
    }

    private func nearestSelectableDay(in month: Date) -> Date {
        let calendar = Calendar.current
        if calendar.isDate(month, equalTo: Date(), toGranularity: .month) {
            return Date()
        }
        return month
    }
}
