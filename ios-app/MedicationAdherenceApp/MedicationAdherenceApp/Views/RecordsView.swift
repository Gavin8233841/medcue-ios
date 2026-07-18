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
        let tasks = measurableTasks
        let doseChanges = doseChanges
        let medications = medications
        let plans = plans
        let lifecycleEvents = lifecycleEvents
        try? await Task.sleep(for: .milliseconds(90))
        guard !Task.isCancelled else {
            return
        }
        trendPreviewDashboard = medicationTrendDashboard(
            tasks: tasks,
            doseChanges: doseChanges,
            medications: medications,
            plans: plans,
            lifecycleEvents: lifecycleEvents
        )
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

private struct DoseDateSelection: Identifiable, Hashable {
    let id: String
    let date: Date

    init(date: Date) {
        self.date = date
        id = AppFormatters.day.string(from: date)
    }
}

private struct RecordsAdherenceDay: Identifiable {
    let date: Date
    let total: Int
    let completed: Int
    let skipped: Int

    var id: Date {
        date
    }

    var completionRate: Double {
        total == 0 ? 0 : Double(completed) / Double(total)
    }
}

private struct RecordsRenderState {
    let snapshot: RecordsViewSnapshot
    let historyTasks: [StoredDoseTask]
    let historyGroups: [HistoryTaskGroup]

    init(
        tasks: [StoredDoseTask],
        medications: [StoredMedication],
        doseChanges: [StoredMedicationDoseChange],
        actionLogs: [StoredDoseActionLog],
        now: Date,
        calendar: Calendar
    ) {
        let snapshot = RecordsViewSnapshot(
            tasks: tasks,
            medications: medications,
            doseChanges: doseChanges,
            actionLogs: actionLogs,
            now: now,
            calendar: calendar
        )
        self.snapshot = snapshot
        self.historyTasks = snapshot.historyTasks
        self.historyGroups = HistoryTaskGroup.build(from: snapshot.historyTasks)
    }
}

private enum RecordsRenderStateSignature {
    static func id(
        tasks: [StoredDoseTask],
        medications: [StoredMedication],
        doseChanges: [StoredMedicationDoseChange],
        actionLogs: [StoredDoseActionLog]
    ) -> String {
        [
            stableTaskSignature(tasks),
            stableMedicationSignature(medications),
            stableDoseChangeSignature(doseChanges),
            stableActionLogSignature(actionLogs)
        ]
        .map(String.init)
        .joined(separator: "|")
    }

    private static func stableActionLogSignature(_ logs: [StoredDoseActionLog]) -> Int {
        var hasher = Hasher()
        hasher.combine(logs.count)
        for log in logs {
            hasher.combine(log.id)
            hasher.combine(log.taskID)
            hasher.combine(log.actionRaw)
            hasher.combine(log.previousStatusRaw)
            hasher.combine(Int(log.previousDueAt.timeIntervalSinceReferenceDate.rounded()))
            hasher.combine(log.previousRecordedAt.map { Int($0.timeIntervalSinceReferenceDate.rounded()) } ?? 0)
            hasher.combine(log.previousReason)
            hasher.combine(log.newStatusRaw)
            hasher.combine(Int(log.occurredAt.timeIntervalSinceReferenceDate.rounded()))
            hasher.combine(Int(log.undoExpiresAt.timeIntervalSinceReferenceDate.rounded()))
            hasher.combine(log.note)
            hasher.combine(log.undoneAt.map { Int($0.timeIntervalSinceReferenceDate.rounded()) } ?? 0)
        }
        return hasher.finalize()
    }
}

private extension StoredDoseTask {
    var recordDisplayReason: String? {
        DoseRecordDisplayText.reason(from: reason)
    }
}

private extension StoredDoseActionLog {
    var recordDisplayNote: String? {
        DoseRecordDisplayText.reason(from: note)
    }
}

private enum DoseRecordDisplayText {
    static func reason(from rawText: String) -> String? {
        let displayParts = rawText
            .components(separatedBy: "；")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { part in
                !part.isEmpty
                    && !part.contains("用户撤销后等待确认")
                    && !part.contains("同一剂量重复提醒已随")
            }

        if displayParts.contains("用户将已处理记录撤销为待处理") {
            return "已撤销上一条处理记录，等待重新确认。"
        }

        guard !displayParts.isEmpty else {
            return nil
        }
        return displayParts.joined(separator: "；")
    }
}

private struct RecordsViewSnapshot {
    let measurableTasks: [StoredDoseTask]
    let medicationByID: [UUID: StoredMedication]
    let taskByID: [UUID: StoredDoseTask]
    let doseChanges: [StoredMedicationDoseChange]
    let actionLogs: [StoredDoseActionLog]
    let tasksByDay: [Date: [StoredDoseTask]]
    let doseChangesByDay: [Date: [StoredMedicationDoseChange]]
    let now: Date
    let calendar: Calendar
    let insight: AdherenceInsight
    let historyTasks: [StoredDoseTask]
    let upcomingTasks: [StoredDoseTask]
    let weekSummaryCounts: (completed: Int, total: Int, skipped: Int, delayed: Int)
    let recentDays: [RecordsAdherenceDay]

    init(
        tasks: [StoredDoseTask],
        medications: [StoredMedication],
        doseChanges: [StoredMedicationDoseChange],
        actionLogs: [StoredDoseActionLog],
        now: Date,
        calendar: Calendar
    ) {
        self.measurableTasks = tasks.adherenceMeasurableTasks
        self.medicationByID = Dictionary(uniqueKeysWithValues: medications.map { ($0.id, $0) })
        let activeMedicationIDs = Set(
            medications
                .filter { $0.lifecycleStatus == .active }
                .map(\.id)
        )
        self.doseChanges = doseChanges
        self.actionLogs = actionLogs
        self.now = now
        self.calendar = calendar
        self.taskByID = Dictionary(uniqueKeysWithValues: tasks.map { ($0.id, $0) })
        self.insight = AdherenceInsightBuilder().build(
            scheduledDoses: measurableTasks.map(\.coreScheduledDose),
            events: measurableTasks.compactMap(\.coreDoseEventUsingEffectiveAdherenceDate),
            timeZone: TimeZone.current
        )
        self.historyTasks = measurableTasks
            .filter { Self.isHistoryTask($0, now: now, calendar: calendar) }
            .sorted { $0.effectiveAdherenceDate > $1.effectiveAdherenceDate }
        self.upcomingTasks = measurableTasks
            .filter {
                activeMedicationIDs.contains($0.medicationID)
                    && $0.dueAt > now
                    && ($0.status == .pending || $0.status == .delayed)
            }
            .sorted { $0.dueAt < $1.dueAt }

        let weekTasks = Self.weekTasks(from: measurableTasks, now: now, calendar: calendar)
        self.weekSummaryCounts = (
            completed: weekTasks.filter { $0.status == .taken || $0.status == .corrected }.count,
            total: weekTasks.count,
            skipped: weekTasks.filter { $0.status == .skipped }.count,
            delayed: weekTasks.filter { $0.status == .delayed }.count
        )
        self.recentDays = Self.recentAdherenceDays(
            from: measurableTasks,
            now: now,
            calendar: calendar
        )
        self.tasksByDay = Self.taskBucketsByDay(from: measurableTasks, calendar: calendar)
        self.doseChangesByDay = Self.doseChangeBucketsByDay(from: doseChanges, calendar: calendar)
    }

    func medication(for task: StoredDoseTask) -> StoredMedication? {
        medicationByID[task.medicationID]
    }

    func medication(for task: StoredDoseTask?) -> StoredMedication? {
        guard let task else {
            return nil
        }
        return medication(for: task)
    }

    func medication(for change: StoredMedicationDoseChange) -> StoredMedication? {
        medicationByID[change.medicationID]
    }

    func medication(forActionLog log: StoredDoseActionLog) -> StoredMedication? {
        task(forActionLog: log).flatMap { medication(for: $0) }
    }

    private func task(forActionLog log: StoredDoseActionLog) -> StoredDoseTask? {
        if let task = taskByID[log.taskID] {
            return task
        }
        return fallbackTask(forActionLog: log)
    }

    func tasks(on date: Date) -> [StoredDoseTask] {
        tasksByDay[calendar.startOfDay(for: date)] ?? []
    }

    func actionLogs(on date: Date) -> [StoredDoseActionLog] {
        deduplicatedActionLogs(
            actionLogs
            .filter { log in
                if calendar.isDate(log.occurredAt, inSameDayAs: date)
                    || calendar.isDate(log.previousDueAt, inSameDayAs: date)
                    || log.previousRecordedAt.map({ calendar.isDate($0, inSameDayAs: date) }) == true {
                    return true
                }
                let relatedTask = taskByID[log.taskID]
                return calendar.isDate(relatedTask?.effectiveAdherenceDate ?? log.occurredAt, inSameDayAs: date)
            }
        )
        .sorted { $0.occurredAt > $1.occurredAt }
    }

    func doseChanges(on date: Date) -> [StoredMedicationDoseChange] {
        doseChangesByDay[calendar.startOfDay(for: date)] ?? []
    }

    private func deduplicatedActionLogs(_ logs: [StoredDoseActionLog]) -> [StoredDoseActionLog] {
        var logsByLogicalAction: [String: StoredDoseActionLog] = [:]
        for log in logs {
            let key = logicalActionKey(for: log)
            if let current = logsByLogicalAction[key] {
                logsByLogicalAction[key] = preferredActionLog(current, log)
            } else {
                logsByLogicalAction[key] = log
            }
        }
        return Array(logsByLogicalAction.values)
    }

    private func preferredActionLog(_ lhs: StoredDoseActionLog, _ rhs: StoredDoseActionLog) -> StoredDoseActionLog {
        let lhsScore = actionLogPreferenceScore(lhs)
        let rhsScore = actionLogPreferenceScore(rhs)
        if lhsScore != rhsScore {
            return lhsScore > rhsScore ? lhs : rhs
        }
        if lhs.occurredAt != rhs.occurredAt {
            return lhs.occurredAt > rhs.occurredAt ? lhs : rhs
        }
        return lhs.id.uuidString < rhs.id.uuidString ? lhs : rhs
    }

    private func actionLogPreferenceScore(_ log: StoredDoseActionLog) -> Int {
        var score = 0
        if !log.note.contains("重复提醒") {
            score += 20
        }
        if log.undoneAt == nil {
            score += 10
        }
        if task(forActionLog: log) != nil {
            score += 5
        }
        return score
    }

    private func logicalActionKey(for log: StoredDoseActionLog) -> String {
        let task = task(forActionLog: log)
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: log.previousDueAt)
        return [
            task?.medicationID.uuidString ?? log.taskID.uuidString,
            log.actionRaw,
            "\(components.year ?? 0)",
            "\(components.month ?? 0)",
            "\(components.day ?? 0)",
            "\(components.hour ?? 0)",
            "\(components.minute ?? 0)",
            task?.doseValue.formatted() ?? "",
            task?.doseUnit ?? ""
        ].joined(separator: "|")
    }

    private func fallbackTask(forActionLog log: StoredDoseActionLog) -> StoredDoseTask? {
        let candidates = measurableTasks.filter { task in
            return isPotentialTask(task, forActionLog: log)
        }
        guard !candidates.isEmpty else {
            return nil
        }
        let rankedCandidates = candidates.sorted { lhs, rhs in
            let lhsScore = fallbackTaskScore(lhs, forActionLog: log)
            let rhsScore = fallbackTaskScore(rhs, forActionLog: log)
            if lhsScore != rhsScore {
                return lhsScore > rhsScore
            }
            let lhsDistance = fallbackTaskDistance(lhs, forActionLog: log)
            let rhsDistance = fallbackTaskDistance(rhs, forActionLog: log)
            if lhsDistance != rhsDistance {
                return lhsDistance < rhsDistance
            }
            return lhs.id.uuidString < rhs.id.uuidString
        }
        guard let first = rankedCandidates.first else {
            return nil
        }
        if let second = rankedCandidates.dropFirst().first {
            let firstScore = fallbackTaskScore(first, forActionLog: log)
            let secondScore = fallbackTaskScore(second, forActionLog: log)
            let firstDistance = fallbackTaskDistance(first, forActionLog: log)
            let secondDistance = fallbackTaskDistance(second, forActionLog: log)
            guard firstScore > secondScore || firstDistance < secondDistance else {
                return nil
            }
        }
        return first
    }

    private func isPotentialTask(_ task: StoredDoseTask, forActionLog log: StoredDoseActionLog) -> Bool {
        let samePreviousDueMinute = calendar.isDate(task.dueAt, equalTo: log.previousDueAt, toGranularity: .minute)
        let sameRecordedMinute = task.effectiveAdherenceRecordedAt.map { calendar.isDate($0, equalTo: log.occurredAt, toGranularity: .minute) } == true
        let samePreviousRecordedMinute = log.previousRecordedAt.flatMap { previousRecordedAt in
            task.effectiveAdherenceRecordedAt.map { calendar.isDate($0, equalTo: previousRecordedAt, toGranularity: .minute) }
        } == true
        guard samePreviousDueMinute || sameRecordedMinute || samePreviousRecordedMinute else {
            return false
        }
        return actionLogStatusMatches(task, log: log)
    }

    private func actionLogStatusMatches(_ task: StoredDoseTask, log: StoredDoseActionLog) -> Bool {
        switch DoseActionKind(rawValue: log.actionRaw) {
        case .markTaken:
            return task.status == .taken || task.status == .corrected || log.undoneAt != nil
        case .delay:
            return task.status == .delayed || log.undoneAt != nil
        case .skip:
            return task.status == .skipped || log.undoneAt != nil
        case .correct:
            return task.status == .corrected || task.status == .pending || log.undoneAt != nil
        case .archiveToday, .restoreArchive:
            return true
        case nil:
            return false
        }
    }

    private func fallbackTaskScore(_ task: StoredDoseTask, forActionLog log: StoredDoseActionLog) -> Int {
        var score = 0
        if calendar.isDate(task.dueAt, equalTo: log.previousDueAt, toGranularity: .minute) {
            score += 50
        }
        if task.effectiveAdherenceRecordedAt.map({ calendar.isDate($0, equalTo: log.occurredAt, toGranularity: .minute) }) == true {
            score += 30
        }
        if log.previousRecordedAt.flatMap({ previousRecordedAt in
            task.effectiveAdherenceRecordedAt.map { calendar.isDate($0, equalTo: previousRecordedAt, toGranularity: .minute) }
        }) == true {
            score += 20
        }
        if actionLogStatusMatches(task, log: log) {
            score += 10
        }
        return score
    }

    private func fallbackTaskDistance(_ task: StoredDoseTask, forActionLog log: StoredDoseActionLog) -> TimeInterval {
        min(
            abs(task.dueAt.timeIntervalSince(log.previousDueAt)),
            abs((task.effectiveAdherenceRecordedAt ?? task.dueAt).timeIntervalSince(log.occurredAt))
        )
    }

    private static func isHistoryTask(_ task: StoredDoseTask, now: Date, calendar: Calendar) -> Bool {
        let startOfToday = calendar.startOfDay(for: now)
        if task.status == .pending || task.status == .delayed {
            return task.dueAt < startOfToday
        }
        if let recordedAt = task.effectiveAdherenceRecordedAt {
            return recordedAt <= now
        }
        return task.dueAt <= now
    }

    private static func isRecordRelevant(_ task: StoredDoseTask, now: Date) -> Bool {
        task.dueAt <= now || task.recordedAt != nil
    }

    private static func weekTasks(from tasks: [StoredDoseTask], now: Date, calendar: Calendar) -> [StoredDoseTask] {
        guard let interval = calendar.dateInterval(of: .weekOfYear, for: now) else {
            return []
        }
        return tasks.filter { interval.contains($0.effectiveAdherenceDate) && isRecordRelevant($0, now: now) }
    }

    private static func recentAdherenceDays(
        from tasks: [StoredDoseTask],
        now: Date,
        calendar: Calendar,
        limit: Int = 28
    ) -> [RecordsAdherenceDay] {
        let today = calendar.startOfDay(for: now)
        return (0..<limit).reversed().compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else {
                return nil
            }
            let dayTasks = tasks.filter { task in
                calendar.isDate(task.effectiveAdherenceDate, inSameDayAs: day) && isRecordRelevant(task, now: now)
            }
            let completed = dayTasks.filter { $0.status == .taken || $0.status == .corrected }.count
            let skipped = dayTasks.filter { $0.status == .skipped }.count
            return RecordsAdherenceDay(date: day, total: dayTasks.count, completed: completed, skipped: skipped)
        }
    }

    private static func taskBucketsByDay(from tasks: [StoredDoseTask], calendar: Calendar) -> [Date: [StoredDoseTask]] {
        var buckets: [Date: [StoredDoseTask]] = [:]
        for task in tasks {
            let dueDay = calendar.startOfDay(for: task.dueAt)
            var dayKeys: Set<Date> = [dueDay]
            if let recordedAt = task.effectiveAdherenceRecordedAt {
                dayKeys.insert(calendar.startOfDay(for: recordedAt))
            }
            for dayKey in dayKeys {
                buckets[dayKey, default: []].append(task)
            }
        }
        return buckets.mapValues { dayTasks in
            dayTasks.sorted { lhs, rhs in
                if lhs.effectiveAdherenceDate != rhs.effectiveAdherenceDate {
                    return lhs.effectiveAdherenceDate < rhs.effectiveAdherenceDate
                }
                return lhs.id.uuidString < rhs.id.uuidString
            }
        }
    }

    private static func doseChangeBucketsByDay(
        from doseChanges: [StoredMedicationDoseChange],
        calendar: Calendar
    ) -> [Date: [StoredMedicationDoseChange]] {
        Dictionary(grouping: doseChanges) { change in
            calendar.startOfDay(for: change.effectiveFrom)
        }
        .mapValues { changes in
            changes.sorted { lhs, rhs in
                if lhs.effectiveFrom != rhs.effectiveFrom {
                    return lhs.effectiveFrom < rhs.effectiveFrom
                }
                return lhs.id.uuidString < rhs.id.uuidString
            }
        }
    }
}

private struct HistoryTaskGroup: Identifiable {
    let id: String
    let tasks: [StoredDoseTask]

    var primaryTask: StoredDoseTask {
        tasks[0]
    }

    var isGrouped: Bool {
        tasks.count > 1
    }

    static func build(from tasks: [StoredDoseTask]) -> [HistoryTaskGroup] {
        var groups: [HistoryTaskGroup] = []
        var currentTasks: [StoredDoseTask] = []
        var currentKey: String?

        for task in tasks {
            let key = groupingKey(for: task)
            if currentKey == key {
                currentTasks.append(task)
            } else {
                appendGroup(from: currentTasks, to: &groups)
                currentTasks = [task]
                currentKey = key
            }
        }

        appendGroup(from: currentTasks, to: &groups)
        return groups
    }

    private static func appendGroup(from tasks: [StoredDoseTask], to groups: inout [HistoryTaskGroup]) {
        guard let firstTask = tasks.first else {
            return
        }
        let lastTask = tasks.last ?? firstTask
        groups.append(HistoryTaskGroup(id: "\(firstTask.id.uuidString)-\(lastTask.id.uuidString)-\(tasks.count)", tasks: tasks))
    }

    private static func groupingKey(for task: StoredDoseTask) -> String {
        let day = AppFormatters.day.string(from: task.effectiveAdherenceDate)
        let normalizedReason = task.reason.trimmingCharacters(in: .whitespacesAndNewlines)
        return [
            day,
            task.medicationID.uuidString,
            task.status.rawValue,
            task.doseValue.formatted(),
            task.doseUnit,
            normalizedReason
        ].joined(separator: "|")
    }
}

private struct RecordsPanelContainer<Content: View>: View {
    let title: String
    let subtitle: String?
    let tint: Color
    @ViewBuilder var content: Content

    init(title: String, subtitle: String? = nil, tint: Color = .blue, @ViewBuilder content: () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.tint = tint
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline)
                if let subtitle {
                    Text(subtitle)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .medicationGlassSurface(cornerRadius: 16, tint: tint, fallbackMaterial: .thinMaterial)
        .shadow(color: Color.black.opacity(0.03), radius: 9, x: 0, y: 4)
    }
}

private struct RecordsEmptyStateLine: View {
    let systemImage: String
    let title: String
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(.secondary.opacity(0.09))
                Image(systemName: systemImage)
                    .foregroundStyle(.secondary)
            }
            .frame(width: 38, height: 38)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct RecordsTrendPreviewCard: View {
    let dashboard: MedicationTrendDashboard?

    private var direction: MedicationTrendDirection {
        dashboard?.direction ?? .needsData
    }

    private var tint: Color {
        trendDirectionTint(direction)
    }

    private var scoreText: String {
        guard let dashboard else {
            return "--"
        }
        return "\(Int((dashboard.overallScore * 100).rounded()))%"
    }

    private var subtitle: String {
        dashboard?.summary ?? "至少一周记录后生成趋势。"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: trendDirectionIconName(direction))
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(tint)
                    .frame(width: 44, height: 44)
                    .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                VStack(alignment: .leading, spacing: 5) {
                    Text("用药趋势")
                        .font(.title3.weight(.semibold))
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)

                VStack(alignment: .trailing, spacing: 3) {
                    Text(scoreText)
                        .font(.system(.title3, design: .rounded).weight(.bold))
                        .foregroundStyle(tint)
                        .monospacedDigit()
                        .contentTransition(.numericText())
                    Text(trendDirectionTitle(direction))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }

            ProgressView(value: dashboard?.overallScore ?? 0)
                .tint(tint)

            HStack(spacing: 8) {
                ForEach(Array((dashboard?.metrics ?? []).prefix(3)), id: \.topic) { metric in
                    RecordsTrendMiniMetric(metric: metric)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .medicationGlassSurface(cornerRadius: 16, tint: tint, fallbackMaterial: .thinMaterial)
        .shadow(color: Color.black.opacity(0.035), radius: 10, x: 0, y: 4)
    }
}

private struct RecordsTrendMiniMetric: View {
    let metric: MedicationTrendMetric

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(metric.title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text(metric.direction == .needsData ? "暂无" : "\(Int((metric.score * 100).rounded()))%")
                .font(.caption.weight(.bold))
                .foregroundStyle(trendDirectionTint(metric.direction))
                .monospacedDigit()
                .contentTransition(.numericText())
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(trendDirectionTint(metric.direction).opacity(0.09), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

private enum RecordsTrendPreviewSignature {
    static func id(
        tasks: [StoredDoseTask],
        doseChanges: [StoredMedicationDoseChange],
        medications: [StoredMedication],
        plans: [StoredMedicationPlan],
        lifecycleEvents: [StoredMedicationLifecycleEvent]
    ) -> String {
        [
            stableTaskSignature(tasks),
            stableDoseChangeSignature(doseChanges),
            stableMedicationSignature(medications),
            stablePlanSignature(plans),
            stableLifecycleEventSignature(lifecycleEvents)
        ]
        .map(String.init)
        .joined(separator: "|")
    }
}

private struct RecordsDisclosureButtonLabel: View {
    let title: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 10) {
            Text(title)
                .font(.subheadline.weight(.semibold))
            Spacer()
            Image(systemName: systemImage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .foregroundStyle(.primary.opacity(0.86))
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .background(.secondary.opacity(0.055), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct RecordsModuleIndexCard<
    OverviewDestination: View,
    CalendarDestination: View,
    TrendDestination: View,
    HistoryDestination: View
>: View {
    let insight: AdherenceInsight
    let historyCount: Int
    let latestHistoryTask: StoredDoseTask?
    let weekSummaryCounts: (completed: Int, total: Int, skipped: Int, delayed: Int)
    let weekDays: [Date]
    let tasksForDay: (Date) -> [StoredDoseTask]
    let doseChangesForDay: (Date) -> [StoredMedicationDoseChange]
    let dashboard: MedicationTrendDashboard?
    private let overviewDestination: () -> OverviewDestination
    private let calendarDestination: () -> CalendarDestination
    private let trendDestination: () -> TrendDestination
    private let historyDestination: () -> HistoryDestination

    init(
        insight: AdherenceInsight,
        historyCount: Int,
        latestHistoryTask: StoredDoseTask?,
        weekSummaryCounts: (completed: Int, total: Int, skipped: Int, delayed: Int),
        weekDays: [Date],
        tasksForDay: @escaping (Date) -> [StoredDoseTask],
        doseChangesForDay: @escaping (Date) -> [StoredMedicationDoseChange],
        dashboard: MedicationTrendDashboard?,
        @ViewBuilder overviewDestination: @escaping () -> OverviewDestination,
        @ViewBuilder calendarDestination: @escaping () -> CalendarDestination,
        @ViewBuilder trendDestination: @escaping () -> TrendDestination,
        @ViewBuilder historyDestination: @escaping () -> HistoryDestination
    ) {
        self.insight = insight
        self.historyCount = historyCount
        self.latestHistoryTask = latestHistoryTask
        self.weekSummaryCounts = weekSummaryCounts
        self.weekDays = weekDays
        self.tasksForDay = tasksForDay
        self.doseChangesForDay = doseChangesForDay
        self.dashboard = dashboard
        self.overviewDestination = overviewDestination
        self.calendarDestination = calendarDestination
        self.trendDestination = trendDestination
        self.historyDestination = historyDestination
    }

    private var completionPercent: Int {
        Int((insight.completionRate * 100).rounded())
    }

    private var trendValue: String {
        guard let dashboard else {
            return "待积累"
        }
        return "\(Int((dashboard.overallScore * 100).rounded()))%"
    }

    private var trendSubtitle: String {
        guard let dashboard else {
            return "继续记录 · 满 7 天生成"
        }
        return "\(trendDirectionTitle(dashboard.direction)) · 置信度 \(Int((dashboard.confidenceScore * 100).rounded()))%"
    }

    private var historySubtitle: String {
        guard let latestHistoryTask else {
            return "暂无过去记录"
        }
        return "最近 \(AppFormatters.day.string(from: latestHistoryTask.effectiveAdherenceDate))"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            MedicationGlassGroup(spacing: 10) {
                RecordsModuleNavigationTile(
                    title: "概览",
                    value: "\(completionPercent)%",
                    detail: "连续 \(insight.currentStreakDays) 天 · \(historyCount) 条",
                    tint: RecordsModulePalette.overview,
                    systemImage: "chart.bar.fill",
                    destination: overviewDestination
                ) {
                    RecordsModuleProgressPreview(
                        progress: insight.completionRate,
                        leadingText: "完成率",
                        trailingText: "\(completionPercent)%",
                        tint: RecordsModulePalette.overview
                    )
                }
                RecordsCalendarModuleNavigationTile(
                    title: "日历",
                    value: "\(weekSummaryCounts.completed)/\(weekSummaryCounts.total)",
                    detail: "本周完成",
                    tint: RecordsModulePalette.calendar,
                    systemImage: "calendar",
                    days: weekDays,
                    tasksForDay: tasksForDay,
                    doseChangesForDay: doseChangesForDay,
                    destination: calendarDestination
                )
                RecordsModuleNavigationTile(
                    title: "趋势",
                    value: trendValue,
                    detail: trendSubtitle,
                    tint: RecordsModulePalette.trend,
                    systemImage: "chart.line.uptrend.xyaxis",
                    destination: trendDestination
                ) {
                    RecordsModuleTrendPreview(dashboard: dashboard, tint: RecordsModulePalette.trend)
                }
                RecordsModuleNavigationTile(
                    title: "记录",
                    value: "\(historyCount)",
                    detail: historySubtitle,
                    tint: RecordsModulePalette.history,
                    systemImage: "clock.arrow.circlepath",
                    destination: historyDestination
                ) {
                    RecordsModuleHistoryPreview(latestTask: latestHistoryTask, tint: RecordsModulePalette.history)
                }
            }
        }
    }
}

private enum RecordsModulePalette {
    static let overview = Color(red: 0.46, green: 0.58, blue: 0.64)
    static let calendar = Color(red: 0.42, green: 0.60, blue: 0.51)
    static let trend = Color(red: 0.56, green: 0.50, blue: 0.69)
    static let history = Color(red: 0.62, green: 0.55, blue: 0.44)
}

private struct RecordsModuleNavigationTile<Destination: View, Preview: View>: View {
    let title: String
    let value: String
    let detail: String
    let tint: Color
    let systemImage: String
    private let destination: () -> Destination
    @ViewBuilder private let preview: Preview

    init(
        title: String,
        value: String,
        detail: String,
        tint: Color,
        systemImage: String,
        @ViewBuilder destination: @escaping () -> Destination,
        @ViewBuilder preview: () -> Preview
    ) {
        self.title = title
        self.value = value
        self.detail = detail
        self.tint = tint
        self.systemImage = systemImage
        self.destination = destination
        self.preview = preview()
    }

    var body: some View {
        NavigationLink {
            destination()
        } label: {
            RecordsModuleTileChrome(title: title, value: value, detail: detail, tint: tint, systemImage: systemImage) {
                preview
            }
        }
        .buttonStyle(.plain)
    }
}

private extension RecordsModuleNavigationTile where Preview == EmptyView {
    init(
        title: String,
        value: String,
        detail: String,
        tint: Color,
        systemImage: String,
        @ViewBuilder destination: @escaping () -> Destination
    ) {
        self.init(
            title: title,
            value: value,
            detail: detail,
            tint: tint,
            systemImage: systemImage,
            destination: destination
        ) {
            EmptyView()
        }
    }
}

private struct RecordsCalendarModuleNavigationTile<Destination: View>: View {
    let title: String
    let value: String
    let detail: String
    let tint: Color
    let systemImage: String
    let days: [Date]
    let tasksForDay: (Date) -> [StoredDoseTask]
    let doseChangesForDay: (Date) -> [StoredMedicationDoseChange]
    private let destination: () -> Destination

    init(
        title: String,
        value: String,
        detail: String,
        tint: Color,
        systemImage: String,
        days: [Date],
        tasksForDay: @escaping (Date) -> [StoredDoseTask],
        doseChangesForDay: @escaping (Date) -> [StoredMedicationDoseChange],
        @ViewBuilder destination: @escaping () -> Destination
    ) {
        self.title = title
        self.value = value
        self.detail = detail
        self.tint = tint
        self.systemImage = systemImage
        self.days = days
        self.tasksForDay = tasksForDay
        self.doseChangesForDay = doseChangesForDay
        self.destination = destination
    }

    var body: some View {
        NavigationLink {
            destination()
        } label: {
            RecordsModuleTileChrome(title: title, value: value, detail: detail, tint: tint, systemImage: systemImage) {
                RecordsIndexWeekStrip(
                    days: days,
                    tasksForDay: tasksForDay,
                    doseChangesForDay: doseChangesForDay,
                    tint: tint
                )
            }
        }
        .buttonStyle(.plain)
    }
}

private struct RecordsModuleTileChrome<Preview: View>: View {
    let title: String
    let value: String
    let detail: String
    let tint: Color
    let systemImage: String
    @ViewBuilder var preview: Preview

    init(
        title: String,
        value: String,
        detail: String,
        tint: Color,
        systemImage: String,
        @ViewBuilder preview: () -> Preview
    ) {
        self.title = title
        self.value = value
        self.detail = detail
        self.tint = tint
        self.systemImage = systemImage
        self.preview = preview()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 15, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [tint.opacity(0.18), tint.opacity(0.08)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    Image(systemName: systemImage)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(tint)
                }
                .frame(width: 42, height: 42)

                Text(title)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Spacer(minLength: 8)

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }

            HStack(alignment: .lastTextBaseline, spacing: 10) {
                Text(value)
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(tint)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)

                Text(detail)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)

                Spacer(minLength: 0)
            }

            preview
                .frame(height: 42, alignment: .bottom)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 15)
        .frame(maxWidth: .infinity, minHeight: 164, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            tint.opacity(0.105),
                            tint.opacity(0.045),
                            Color(.systemBackground).opacity(0.05)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        }
        .medicationGlassSurface(cornerRadius: 22, tint: tint, fallbackMaterial: .thinMaterial, isInteractive: true)
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [tint.opacity(0.18), Color.white.opacity(0.08), tint.opacity(0.08)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.8
                )
        }
        .shadow(color: tint.opacity(0.07), radius: 14, x: 0, y: 6)
    }
}

private extension RecordsModuleTileChrome where Preview == EmptyView {
    init(title: String, value: String, detail: String, tint: Color, systemImage: String) {
        self.init(title: title, value: value, detail: detail, tint: tint, systemImage: systemImage) {
            EmptyView()
        }
    }
}

private struct RecordsModuleProgressPreview: View {
    let progress: Double
    let leadingText: String
    let trailingText: String
    let tint: Color

    private var clampedProgress: Double {
        min(max(progress, 0), 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(tint.opacity(0.11))
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [tint.opacity(0.56), tint.opacity(0.30)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: max(8, proxy.size.width * clampedProgress))
                }
            }
            .frame(height: 5)

            HStack(spacing: 8) {
                Text(leadingText)
                Spacer(minLength: 8)
                Text(trailingText)
                    .monospacedDigit()
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
        }
        .padding(.top, 2)
    }
}

private struct RecordsModuleTrendPreview: View {
    let dashboard: MedicationTrendDashboard?
    let tint: Color

    private var progress: Double {
        guard let dashboard else {
            return 0.18
        }
        return min(max(dashboard.overallScore, 0), 1)
    }

    private var leadingText: String {
        dashboard == nil ? "趋势准备中" : "综合趋势"
    }

    private var trailingText: String {
        guard let dashboard else {
            return "继续记录"
        }
        return trendDirectionTitle(dashboard.direction)
    }

    var body: some View {
        RecordsModuleProgressPreview(
            progress: progress,
            leadingText: leadingText,
            trailingText: trailingText,
            tint: tint
        )
    }
}

private struct RecordsModuleHistoryPreview: View {
    let latestTask: StoredDoseTask?
    let tint: Color

    var body: some View {
        HStack(spacing: 8) {
            statusCapsule(text: latestStatusText, emphasized: latestTask != nil)
            statusCapsule(text: "可修正", emphasized: false)
            Spacer(minLength: 0)
        }
        .padding(.top, 1)
    }

    private var latestStatusText: String {
        guard let latestTask else {
            return "暂无记录"
        }
        switch latestTask.status {
        case .taken:
            return "最近已服用"
        case .corrected:
            return "最近已修正"
        case .skipped:
            return "最近已忽略"
        case .delayed:
            return "最近稍后"
        case .pending:
            return "最近待处理"
        }
    }

    private func statusCapsule(text: String, emphasized: Bool) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(emphasized ? tint : Color.secondary)
            .lineLimit(1)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule(style: .continuous)
                    .fill(emphasized ? tint.opacity(0.12) : Color.secondary.opacity(0.075))
            )
    }
}

private struct RecordsCalendarProgressRing: View {
    let progress: Double
    let color: Color
    let isEmpty: Bool
    var size: CGFloat = 34
    var lineWidth: CGFloat = 4

    private var clampedProgress: Double {
        min(max(progress, 0), 1)
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.secondary.opacity(isEmpty ? 0.12 : 0.16), lineWidth: lineWidth)
            if !isEmpty {
                Circle()
                    .trim(from: 0, to: max(clampedProgress, 0.06))
                    .stroke(
                        color.opacity(clampedProgress == 0 ? 0.34 : 0.76),
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
            }
        }
        .frame(width: size, height: size)
    }
}

private struct RecordsIndexWeekStrip: View {
    let days: [Date]
    let tasksForDay: (Date) -> [StoredDoseTask]
    let doseChangesForDay: (Date) -> [StoredMedicationDoseChange]
    let tint: Color

    private let calendar = Calendar.current

    var body: some View {
        HStack(spacing: 5) {
            ForEach(days, id: \.self) { day in
                let tasks = tasksForDay(day)
                let completed = tasks.filter { $0.status == .taken || $0.status == .corrected }.count
                let total = tasks.count
                let hasDoseChange = !doseChangesForDay(day).isEmpty
                VStack(spacing: 3) {
                    Text(weekdayText(for: day))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                    ZStack(alignment: .center) {
                        RecordsCalendarProgressRing(
                            progress: progress(completed: completed, total: total),
                            color: dayIndicatorColor(completed: completed, total: total, hasDoseChange: hasDoseChange),
                            isEmpty: total == 0,
                            size: 26,
                            lineWidth: 3
                        )
                        Text(dayNumberText(for: day))
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(calendar.isDateInToday(day) ? tint : .primary.opacity(0.76))
                        if hasDoseChange {
                            Circle()
                                .fill(Color.purple.opacity(0.76))
                                .frame(width: 5.5, height: 5.5)
                                .frame(width: 26, height: 26, alignment: .topTrailing)
                                .offset(x: 1.5, y: -1.5)
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(calendar.isDateInToday(day) ? tint.opacity(0.12) : Color.secondary.opacity(0.035))
                        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                )
                .accessibilityHidden(true)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
    }

    private var accessibilitySummary: String {
        let daySummaries = days.map { day in
            let tasks = tasksForDay(day)
            let completed = tasks.filter { $0.status == .taken || $0.status == .corrected }.count
            return "\(weekdayText(for: day)) \(dayNumberText(for: day)) \(summaryText(completed: completed, total: tasks.count))"
        }
        return "本周日历预览，\(daySummaries.joined(separator: "，"))"
    }

    private func weekdayText(for date: Date) -> String {
        let index = calendar.component(.weekday, from: date) - 1
        let symbols = ["日", "一", "二", "三", "四", "五", "六"]
        return symbols.indices.contains(index) ? symbols[index] : ""
    }

    private func dayNumberText(for date: Date) -> String {
        String(calendar.component(.day, from: date))
    }

    private func summaryText(completed: Int, total: Int) -> String {
        guard total > 0 else {
            return "—"
        }
        if completed == 0 {
            return "\(total)项"
        }
        return "\(completed)/\(total)"
    }

    private func progress(completed: Int, total: Int) -> Double {
        total == 0 ? 0 : Double(completed) / Double(total)
    }

    private func dayIndicatorColor(completed: Int, total: Int, hasDoseChange: Bool) -> Color {
        if hasDoseChange {
            return Color(red: 0.56, green: 0.50, blue: 0.69).opacity(0.62)
        }
        guard total > 0 else {
            return Color.secondary.opacity(0.18)
        }
        if completed == total {
            return Color(red: 0.42, green: 0.60, blue: 0.51).opacity(0.68)
        }
        if completed > 0 {
            return tint.opacity(0.58)
        }
        return Color.secondary.opacity(0.28)
    }
}

private struct RecordsOverviewDetailPage: View {
    let insight: AdherenceInsight
    let historyCount: Int
    let upcomingCount: Int
    let recentDays: [RecordsAdherenceDay]

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 14) {
                RecordsInsightCard(
                    insight: insight,
                    historyCount: historyCount,
                    upcomingCount: upcomingCount,
                    recentDays: recentDays,
                    tint: RecordsModulePalette.overview
                )
                RecordsOverviewCompletionMixCard(
                    insight: insight,
                    tint: RecordsModulePalette.overview
                )
                RecordsOverviewContinuityCard(
                    insight: insight,
                    historyCount: historyCount,
                    upcomingCount: upcomingCount,
                    tint: RecordsModulePalette.overview
                )
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 28)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("记录概览")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
    }
}

private struct RecordsCalendarDetailPage: View {
    @Binding var selectedDate: Date
    @Binding var displayedMonth: Date
    let monthRange: ClosedRange<Date>
    let days: [Date]
    let snapshot: RecordsViewSnapshot
    let doseChanges: [StoredMedicationDoseChange]
    let transitionDirection: Int
    let moveMonth: (Int) -> Void
    let openDay: (Date) -> Void
    let openTask: (StoredDoseTask) -> Void

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 14) {
                RecordsPanelContainer(
                    title: "月历记录",
                    subtitle: "左右切换月份，点日期查看当天详情",
                    tint: RecordsModulePalette.calendar
                ) {
                    MonthDoseCalendarView(
                        selectedDate: $selectedDate,
                        displayedMonth: $displayedMonth,
                        monthRange: monthRange,
                        days: days,
                        tasksForDay: snapshot.tasks(on:),
                        doseChangesForDay: snapshot.doseChanges(on:),
                        openDay: openDay,
                        transitionDirection: transitionDirection,
                        moveMonth: moveMonth,
                        tint: RecordsModulePalette.calendar
                    )
                }

                RecordsPanelContainer(title: AppFormatters.day.string(from: selectedDate), tint: RecordsModulePalette.calendar) {
                    DayDoseListView(
                        date: selectedDate,
                        tasks: snapshot.tasks(on: selectedDate),
                        doseChanges: snapshot.doseChanges(on: selectedDate),
                        allDoseChanges: doseChanges,
                        medication: snapshot.medication(for:),
                        medicationForDoseChange: snapshot.medication(for:),
                        openTask: openTask
                    )
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 28)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("记录日历")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
    }
}

private struct RecordsHistoryDetailPage: View {
    let historyTasks: [StoredDoseTask]
    let historyGroups: [HistoryTaskGroup]
    @Binding var expandedHistoryGroupIDs: Set<String>
    let medication: (StoredDoseTask) -> StoredMedication?
    let openTask: (StoredDoseTask) -> Void

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 14) {
                RecordsPanelContainer(
                    title: "服药记录",
                    subtitle: "\(historyTasks.count) 条过去记录",
                    tint: RecordsModulePalette.history
                ) {
                    if historyGroups.isEmpty {
                        RecordsEmptyStateLine(
                            systemImage: "clock.arrow.circlepath",
                            title: "还没有过去的服药记录",
                            message: "完成或修正服药后，会在这里形成可复核的历史。"
                        )
                    } else {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(historyGroups.enumerated()), id: \.element.id) { index, group in
                                HistoryTaskGroupView(
                                    group: group,
                                    medication: medication(group.primaryTask),
                                    isExpanded: expandedHistoryGroupIDs.contains(group.id),
                                    openTask: openTask,
                                    toggleExpanded: {
                                        withAnimation(.snappy(duration: 0.26, extraBounce: 0.015)) {
                                            toggleHistoryGroup(group.id)
                                        }
                                    }
                                )
                                .padding(.vertical, 8)

                                if index < historyGroups.count - 1 {
                                    Divider()
                                        .opacity(0.42)
                                        .padding(.leading, 76)
                                }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 28)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("服药记录")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
    }

    private func toggleHistoryGroup(_ id: String) {
        if expandedHistoryGroupIDs.contains(id) {
            expandedHistoryGroupIDs.remove(id)
        } else {
            expandedHistoryGroupIDs.insert(id)
        }
    }
}

private struct RecordsInsightCard: View {
    let insight: AdherenceInsight
    let historyCount: Int
    let upcomingCount: Int
    let recentDays: [RecordsAdherenceDay]
    let tint: Color

    private var completionPercent: Int {
        Int((insight.completionRate * 100).rounded())
    }

    private var streakDisplay: AdherenceStreakDisplay {
        AdherenceStreakDisplay(insight: insight)
    }

    private var accentColor: Color {
        tint
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(accentColor.opacity(0.12))
                    Image(systemName: "calendar.badge.checkmark")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(accentColor)
                }
                .frame(width: 48, height: 48)

                VStack(alignment: .leading, spacing: 4) {
                    Text("服药记录概览")
                        .font(.title3.weight(.semibold))
                    Text(insight.message)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
            }

            HStack(spacing: 0) {
                RecordsMetricPill(title: streakDisplay.title, value: streakDisplay.value, tint: .green)
                RecordsMetricDivider()
                RecordsMetricPill(title: "完成率", value: "\(completionPercent)%", tint: accentColor)
                RecordsMetricDivider()
                RecordsMetricPill(title: "历史记录", value: "\(historyCount)", tint: accentColor)
            }

            RecordsMiniHeatmap(days: recentDays)

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    RecordsExceptionChip(title: "忽略", value: insight.skippedCount, isEmphasized: insight.skippedCount > 0)
                    RecordsExceptionChip(title: "稍后", value: insight.delayedCount)
                }

                if upcomingCount > 0 {
                    RecordsPlanFoldNote(count: upcomingCount)
                }
            }
        }
        .padding(16)
        .medicationGlassSurface(cornerRadius: 16, tint: accentColor, fallbackMaterial: .thinMaterial)
        .shadow(color: Color.black.opacity(0.035), radius: 10, x: 0, y: 4)
    }
}

private struct RecordsOverviewCompletionMixCard: View {
    let insight: AdherenceInsight
    let tint: Color

    private var pendingCount: Int {
        max(0, insight.scheduledCount - insight.takenCount - insight.skippedCount - insight.delayedCount)
    }

    private var segments: [RecordsOverviewMixSegment] {
        [
            RecordsOverviewMixSegment(title: "已完成", count: insight.takenCount, color: tint),
            RecordsOverviewMixSegment(title: "忽略", count: insight.skippedCount, color: .orange),
            RecordsOverviewMixSegment(title: "稍后", count: insight.delayedCount, color: .blue),
            RecordsOverviewMixSegment(title: "待补记", count: pendingCount, color: .secondary)
        ]
    }

    private var visibleSegments: [RecordsOverviewMixSegment] {
        segments.filter { $0.count > 0 }
    }

    private var totalCount: Int {
        max(1, segments.reduce(0) { $0 + $1.count })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("处理构成", systemImage: "chart.bar.xaxis")
                    .font(.headline)
                Spacer()
                Text("\(insight.scheduledCount) 项")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(tint)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 6)
                    .background(tint.opacity(0.10), in: Capsule())
            }

            GeometryReader { proxy in
                let displayedSegments = visibleSegments.isEmpty ? [RecordsOverviewMixSegment(title: "暂无", count: 1, color: .secondary)] : visibleSegments
                let spacingWidth = CGFloat(max(0, displayedSegments.count - 1)) * 4
                let availableWidth = max(0, proxy.size.width - spacingWidth)
                HStack(spacing: 4) {
                    ForEach(displayedSegments) { segment in
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(segment.color.opacity(segment.title == "暂无" ? 0.18 : 0.68))
                            .frame(width: max(8, availableWidth * CGFloat(segment.count) / CGFloat(totalCount)))
                    }
                }
            }
            .frame(height: 10)
            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))

            HStack(spacing: 8) {
                ForEach(segments) { segment in
                    RecordsOverviewSmallStat(title: segment.title, value: "\(segment.count)", tint: segment.color)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .medicationGlassSurface(cornerRadius: 16, tint: tint, fallbackMaterial: .thinMaterial)
        .shadow(color: Color.black.opacity(0.03), radius: 9, x: 0, y: 4)
    }
}

private struct RecordsOverviewContinuityCard: View {
    let insight: AdherenceInsight
    let historyCount: Int
    let upcomingCount: Int
    let tint: Color

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 2)

    private var completionPercent: String {
        "\(Int((insight.completionRate * 100).rounded()))%"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("记录稳定性", systemImage: "waveform.path.ecg")
                .font(.headline)

            LazyVGrid(columns: columns, spacing: 10) {
                RecordsOverviewStatTile(title: "当前连续", value: "\(insight.currentStreakDays) 天", tint: .green)
                RecordsOverviewStatTile(title: "最长连续", value: "\(insight.longestStreakDays) 天", tint: tint)
                RecordsOverviewStatTile(title: "完成率", value: completionPercent, tint: tint)
                RecordsOverviewStatTile(title: "未来计划", value: "\(upcomingCount) 条", tint: .secondary)
            }

            HStack(spacing: 8) {
                Image(systemName: "doc.text.magnifyingglass")
                    .font(.caption.weight(.semibold))
                Text("\(historyCount) 条历史记录可用于复诊回顾")
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 11)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.secondary.opacity(0.055), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .medicationGlassSurface(cornerRadius: 16, tint: tint, fallbackMaterial: .thinMaterial)
        .shadow(color: Color.black.opacity(0.03), radius: 9, x: 0, y: 4)
    }
}

private struct RecordsOverviewMixSegment: Identifiable {
    let title: String
    let count: Int
    let color: Color

    var id: String {
        title
    }
}

private struct RecordsOverviewSmallStat: View {
    let title: String
    let value: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(.caption.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(tint)
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

private struct RecordsOverviewStatTile: View {
    let title: String
    let value: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(value)
                .font(.system(.headline, design: .rounded).weight(.bold))
                .monospacedDigit()
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct RecordsMetricPill: View {
    let title: String
    let value: String
    var tint: Color = .primary

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(value)
                .font(.system(.title3, design: .rounded).weight(.bold))
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .contentTransition(.numericText())
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, minHeight: 54, alignment: .leading)
    }
}

private struct RecordsMetricDivider: View {
    var body: some View {
        Rectangle()
            .fill(.separator.opacity(0.45))
            .frame(width: 1, height: 34)
            .padding(.horizontal, 12)
    }
}

private struct RecordsExceptionChip: View {
    let title: String
    let value: Int
    var isEmphasized = false

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(isEmphasized ? Color.orange : Color.secondary.opacity(0.55))
                .frame(width: 7, height: 7)
            Text(title)
                .font(.caption.weight(.semibold))
            Text("\(value)")
                .font(.caption.monospacedDigit().weight(.semibold))
                .foregroundStyle(isEmphasized ? .orange : .secondary)
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background((isEmphasized ? Color.orange.opacity(0.09) : Color.secondary.opacity(0.08)), in: Capsule())
    }
}

private struct RecordsPlanFoldNote: View {
    let count: Int

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "calendar.badge.clock")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text("未来计划 \(count) 条")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.secondary.opacity(0.055), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
    }
}

private struct RecordsMiniHeatmap: View {
    let days: [RecordsAdherenceDay]

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 14)

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("近 28 天记录")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                HStack(spacing: 5) {
                    heatmapLegendDot(.secondary.opacity(0.18))
                    heatmapLegendDot(.secondary.opacity(0.34))
                    heatmapLegendDot(.secondary.opacity(0.68))
                }
                .accessibilityHidden(true)
            }

            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(days) { day in
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(color(for: day))
                        .frame(height: 12)
                        .accessibilityLabel("\(AppFormatters.day.string(from: day.date))，\(day.total == 0 ? "没有记录" : "\(day.completed) / \(day.total) 项已完成")")
                }
            }
        }
        .padding(12)
        .background(.secondary.opacity(0.055), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func heatmapLegendDot(_ color: Color) -> some View {
        RoundedRectangle(cornerRadius: 2, style: .continuous)
            .fill(color)
            .frame(width: 12, height: 12)
    }

    private func color(for day: RecordsAdherenceDay) -> Color {
        guard day.total > 0 else {
            return .secondary.opacity(0.16)
        }
        if day.skipped > 0 {
            return .orange.opacity(0.78)
        }
        switch day.completionRate {
        case 0.95...:
            return .green.opacity(0.76)
        case 0.65..<0.95:
            return .blue.opacity(0.58)
        default:
            return .red.opacity(0.36)
        }
    }
}

private struct HistorySummaryRow: View {
    let count: Int
    let visibleCount: Int
    let visibleGroupCount: Int
    let latestTask: StoredDoseTask?
    let medication: (StoredDoseTask?) -> StoredMedication?

    var body: some View {
        HStack(spacing: 12) {
            MedicationSymbolView(symbolName: "clock.arrow.circlepath", tint: .secondary)
                .frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 4) {
                Text("\(count) 条过去记录")
                    .font(.headline)
                Text(latestSummary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Text(visibleSummaryText)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 9)
                .padding(.vertical, 6)
                .background(.secondary.opacity(0.09), in: Capsule())
        }
        .padding(.vertical, 4)
    }

    private var visibleSummaryText: String {
        visibleGroupCount == visibleCount ? "显示 \(visibleCount)" : "\(visibleCount) 条 · \(visibleGroupCount) 组"
    }

    private var latestSummary: String {
        guard let latestTask else {
            return "暂无记录"
        }
        let name = medication(latestTask).map(userFacingMedicationName(for:)) ?? "用药记录"
        return "\(AppFormatters.day.string(from: latestTask.effectiveAdherenceDate)) · \(name)"
    }
}

private struct RecordHistoryRow: View {
    let task: StoredDoseTask
    let medication: StoredMedication?

    private var tint: Color {
        switch task.status {
        case .taken, .corrected:
            return .green
        case .skipped:
            return .orange
        case .delayed:
            return .blue
        case .pending:
            return .secondary
        }
    }

    private var statusBadgeColor: Color {
        tint
    }

    var body: some View {
        HStack(spacing: 12) {
            MedicationPhotoView(
                photoData: medication?.photoData,
                symbolName: medication?.photoSymbolName ?? "pills.fill",
                tint: tint
            )
            VStack(alignment: .leading, spacing: 4) {
                Text(medication.map(userFacingMedicationName(for:)) ?? "未知药品")
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text("\(timePrefix)：\(AppFormatters.day.string(from: displayDate)) · \(AppFormatters.time.string(from: displayDate))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if let displayReason = task.recordDisplayReason {
                    Text(displayReason)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
            StatusBadge(text: task.status.displayName, color: statusBadgeColor)
        }
        .contentShape(Rectangle())
    }

    private var displayDate: Date {
        task.effectiveAdherenceDate
    }

    private var timePrefix: String {
        if task.status == .pending {
            return "待补记"
        }
        if task.status == .delayed {
            return "稍后"
        }
        return task.effectiveAdherenceRecordedAt == nil ? "计划" : "记录"
    }
}

private struct HistoryTaskGroupView: View {
    let group: HistoryTaskGroup
    let medication: StoredMedication?
    let isExpanded: Bool
    let openTask: (StoredDoseTask) -> Void
    let toggleExpanded: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Button {
                if group.isGrouped {
                    toggleExpanded()
                } else {
                    openTask(group.primaryTask)
                }
            } label: {
                if group.isGrouped {
                    GroupedRecordHistoryRow(
                        group: group,
                        medication: medication,
                        isExpanded: isExpanded
                    )
                } else {
                    RecordHistoryRow(
                        task: group.primaryTask,
                        medication: medication
                    )
                }
            }
            .buttonStyle(.plain)

            if group.isGrouped && isExpanded {
                VStack(spacing: 0) {
                    ForEach(Array(group.tasks.enumerated()), id: \.element.id) { index, task in
                        Button {
                            openTask(task)
                        } label: {
                            GroupedRecordChildRow(
                                task: task,
                                sequenceNumber: index + 1,
                                totalCount: group.tasks.count
                            )
                        }
                        .buttonStyle(.plain)
                        .padding(.vertical, 8)

                        if index < group.tasks.count - 1 {
                            Divider()
                                .opacity(0.34)
                                .padding(.leading, 28)
                        }
                    }
                }
                .padding(.leading, 54)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
}

private struct GroupedRecordHistoryRow: View {
    let group: HistoryTaskGroup
    let medication: StoredMedication?
    let isExpanded: Bool

    private var task: StoredDoseTask {
        group.primaryTask
    }

    private var tint: Color {
        switch task.status {
        case .taken, .corrected:
            return .green
        case .delayed:
            return .blue
        case .skipped:
            return .orange
        case .pending:
            return .secondary
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            MedicationPhotoView(
                photoData: medication?.photoData,
                symbolName: medication?.photoSymbolName ?? "pills.fill",
                tint: tint
            )
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(medication.map(userFacingMedicationName(for:)) ?? "未知药品")
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text("合并 \(group.tasks.count) 条")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(tint)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(tint.opacity(0.10), in: Capsule())
                }

                Text(timeRangeText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                if let displayReason = task.recordDisplayReason {
                    Text(displayReason)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 7) {
                StatusBadge(text: task.status.displayName, color: tint)
                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .contentShape(Rectangle())
    }

    private var timeRangeText: String {
        guard let latest = group.tasks.first, let earliest = group.tasks.last else {
            return "记录时间待核对"
        }
        let latestDate = latest.effectiveAdherenceDate
        let earliestDate = earliest.effectiveAdherenceDate
        let dayText = AppFormatters.day.string(from: latestDate)
        let earliestTime = AppFormatters.time.string(from: earliestDate)
        let latestTime = AppFormatters.time.string(from: latestDate)
        if earliestTime == latestTime {
            return "\(dayText) · \(latestTime) 同一时段"
        }
        return "\(dayText) · \(earliestTime)-\(latestTime)"
    }
}

private struct GroupedRecordChildRow: View {
    let task: StoredDoseTask
    let sequenceNumber: Int
    let totalCount: Int

    private var displayDate: Date {
        task.effectiveAdherenceDate
    }

    var body: some View {
        HStack(spacing: 10) {
            Capsule()
                .fill(statusAccentColor)
                .frame(width: 3, height: 22)
                .opacity(statusAccentOpacity)
            Text(AppFormatters.time.string(from: displayDate))
                .font(.subheadline.monospacedDigit().weight(.semibold))
                .foregroundStyle(.primary.opacity(0.82))
            VStack(alignment: .leading, spacing: 2) {
                Text(task.status.displayName)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(detailText)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
    }

    private var detailText: String {
        "第 \(sequenceNumber)/\(totalCount) 条 · \(task.doseValue.formatted()) \(localizedMedicationUnit(task.doseUnit))"
    }

    private var statusAccentColor: Color {
        switch task.status {
        case .taken, .corrected:
            return .green
        case .delayed:
            return .blue
        case .skipped:
            return .orange
        case .pending:
            return .secondary
        }
    }

    private var statusAccentOpacity: Double {
        task.status == .pending ? 0.46 : 0.66
    }
}

private struct DoseRecordCorrectionView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var plans: [StoredMedicationPlan]
    @Query private var allTasks: [StoredDoseTask]
    let task: StoredDoseTask
    let medication: StoredMedication?
    @StateObject private var notificationService = NotificationService()
    @StateObject private var liveActivityService = MedicationLiveActivityService()
    @State private var status: StoredDoseStatus
    @State private var plannedAt: Date
    @State private var recordedAt: Date
    @State private var note: String
    @State private var showingEarlyRecordConfirmation = false

    init(task: StoredDoseTask, medication: StoredMedication?) {
        self.task = task
        self.medication = medication
        _status = State(initialValue: task.status)
        _plannedAt = State(initialValue: task.dueAt)
        _recordedAt = State(initialValue: min(task.effectiveAdherenceRecordedAt ?? task.recordedAt ?? task.dueAt, Date()))
        _note = State(initialValue: task.recordDisplayReason ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("记录") {
                    HStack(spacing: 12) {
                        MedicationPhotoView(
                            photoData: medication?.photoData,
                            symbolName: medication?.photoSymbolName ?? "pills.fill",
                            tint: .blue,
                            size: 44
                        )
                        VStack(alignment: .leading, spacing: 4) {
                            Text(medication.map(userFacingMedicationName(for:)) ?? "未知药品")
                                .font(.headline)
                            Text("\(task.doseValue.formatted()) \(localizedMedicationUnit(task.doseUnit))")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Picker("状态", selection: $status) {
                        Text("待处理").tag(StoredDoseStatus.pending)
                        Text("已服用").tag(StoredDoseStatus.taken)
                        Text("稍后提醒").tag(StoredDoseStatus.delayed)
                        Text("已忽略").tag(StoredDoseStatus.skipped)
                        Text("已修正").tag(StoredDoseStatus.corrected)
                    }
                    DatePicker("计划时间", selection: $plannedAt)
                    if status != .pending {
                        DatePicker("实际记录时间", selection: $recordedAt, in: ...Date())
                    }
                }

                Section("备注") {
                    TextEditor(text: $note)
                        .frame(minHeight: 96)
                }
            }
            .navigationTitle("修正记录")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        saveWithEarlyRecordCheck()
                    }
                }
            }
            .alert("确认提前记录？", isPresented: $showingEarlyRecordConfirmation) {
                Button("确认已提前服用") {
                    save(confirmedEarlyRecord: true)
                }
                Button("返回修改", role: .cancel) {}
            } message: {
                Text("实际记录时间距离计划时间较久。请确认这是按医嘱、说明书或医生或药师建议提前服用。")
            }
        }
    }

    private func saveWithEarlyRecordCheck() {
        let clampedRecordedAt = min(recordedAt, Date())
        guard shouldConfirmEarlyRecord(recordedAt: clampedRecordedAt) else {
            save(confirmedEarlyRecord: false)
            return
        }
        showingEarlyRecordConfirmation = true
    }

    private func shouldConfirmEarlyRecord(recordedAt: Date) -> Bool {
        guard status == .taken || status == .corrected else {
            return false
        }
        return DoseReminderPolicy.competitionDemo.requiresEarlyTakenConfirmation(
            plannedDueAt: plannedAt,
            now: recordedAt
        )
    }

    private func save(confirmedEarlyRecord: Bool) {
        let occurredAt = Date()
        let group = correctionGroup()
        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let savedReason = DoseCorrectionPolicy.taskReasonForSavedStatus(
            previousStatus: task.status,
            newStatus: status,
            trimmedNote: trimmedNote
        )
        let primaryCorrectionNote = correctionLogNote(
            userNote: trimmedNote,
            confirmedEarlyRecord: confirmedEarlyRecord
        )

        for groupTask in group {
            let correctionNote = groupTask.id == task.id
                ? primaryCorrectionNote
                : groupedCorrectionLogNote(primaryNote: primaryCorrectionNote)
            modelContext.insert(StoredDoseActionLog(
                taskID: groupTask.id,
                action: .correct,
                previousStatus: groupTask.status,
                previousDueAt: groupTask.dueAt,
                previousRecordedAt: groupTask.recordedAt,
                previousReason: groupTask.reason,
                newStatus: status,
                occurredAt: occurredAt,
                undoExpiresAt: occurredAt.addingTimeInterval(10 * 60),
                note: correctionNote
            ))
            groupTask.status = status
            groupTask.dueAt = plannedAt
            groupTask.recordedAt = status == .pending ? nil : min(recordedAt, occurredAt)
            groupTask.reason = savedReason
        }
        try? modelContext.save()
        synchronizeReminderAfterCorrection(for: group)
        dismiss()
    }

    private func correctionGroup() -> [StoredDoseTask] {
        let fetchedTasks = (try? modelContext.fetch(FetchDescriptor<StoredDoseTask>())) ?? allTasks
        let group = DoseLogicalGroup.group(containing: task, in: fetchedTasks)
        return group.isEmpty ? [task] : group
    }

    private func correctionLogNote(userNote: String, confirmedEarlyRecord: Bool) -> String {
        var parts = [userNote].filter { !$0.isEmpty }
        if confirmedEarlyRecord {
            parts.append("用户确认提前服用。")
        }
        return parts.joined(separator: "；")
    }

    private func groupedCorrectionLogNote(primaryNote: String) -> String {
        let mergeNote = "同一剂量重复提醒已随本次记录修正合并。"
        guard !primaryNote.isEmpty else {
            return mergeNote
        }
        return "\(mergeNote)；\(primaryNote)"
    }

    private func synchronizeReminderAfterCorrection(for group: [StoredDoseTask]) {
        let shouldKeepReminder = (task.status == .pending || task.status == .delayed) && task.dueAt > Date()
        guard shouldKeepReminder, let medication else {
            Task { @MainActor in
                for groupTask in group {
                    notificationService.cancelReminder(for: groupTask.id)
                    await liveActivityService.end(for: groupTask.id)
                }
            }
            return
        }

        let deliveryMethod = plans.first { $0.id == task.planID }?.reminderDeliveryMethod ?? .notification
        Task { @MainActor in
            for groupTask in group {
                if groupTask.id == task.id {
                    await notificationService.scheduleReminder(
                        for: groupTask,
                        medication: medication,
                        deliveryMethod: deliveryMethod
                    )
                } else {
                    notificationService.cancelReminder(for: groupTask.id)
                }
                await liveActivityService.end(for: groupTask.id)
            }
            await liveActivityService.startIfNeeded(for: task, medication: medication)
        }
    }
}

private struct WeekSummaryRow: View {
    let completedCount: Int
    let totalCount: Int
    let skippedCount: Int
    let delayedCount: Int
    let isMonthExpanded: Bool
    var showsMonthToggle = true

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 14) {
                MedicationSymbolView(symbolName: "calendar", tint: .secondary)
                    .frame(width: 52, height: 52)
                VStack(alignment: .leading, spacing: 5) {
                    Text("本周记录")
                        .font(.headline)
                    Text(totalCount == 0 ? "本周暂无任务" : "\(completedCount) / \(totalCount) 项已完成")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    if skippedCount > 0 || delayedCount > 0 {
                        Text("忽略 \(skippedCount) 次，稍后 \(delayedCount) 次")
                            .font(.footnote)
                            .foregroundStyle(.orange)
                    }
                }
                Spacer()
                if showsMonthToggle {
                    HStack(spacing: 5) {
                        Text(isMonthExpanded ? "收起月历" : "展开月历")
                        Image(systemName: isMonthExpanded ? "chevron.up" : "chevron.down")
                            .font(.caption2.weight(.bold))
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(.secondary.opacity(0.09), in: Capsule())
                    .accessibilityLabel(isMonthExpanded ? "收起月历" : "展开月历")
                }
            }

            ProgressView(value: totalCount == 0 ? 0 : Double(completedCount), total: Double(max(totalCount, 1)))
                .tint(progressTint)
        }
        .padding(.vertical, 6)
    }

    private var progressTint: Color {
        if skippedCount > 0 || delayedCount > 0 {
            return .orange
        }
        if completedCount == totalCount && totalCount > 0 {
            return .green
        }
        if totalCount > 0 {
            return .blue
        }
        return .secondary.opacity(0.55)
    }
}

private struct MonthNavigationButton: View {
    let systemImage: String
    let accessibilityText: String
    let isEnabled: Bool

    var body: some View {
        Image(systemName: systemImage)
            .font(.caption.weight(.bold))
            .frame(width: 32, height: 32)
            .background(.secondary.opacity(isEnabled ? 0.08 : 0.035), in: Circle())
            .foregroundStyle(.secondary.opacity(isEnabled ? 0.95 : 0.32))
            .accessibilityLabel(accessibilityText)
    }
}

private struct WeekDoseCalendarView: View {
    @Binding var selectedDate: Date
    let days: [Date]
    let tasksForDay: (Date) -> [StoredDoseTask]
    let doseChangesForDay: (Date) -> [StoredMedicationDoseChange]
    let openDay: (Date) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("本周日历")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            HStack(spacing: 7) {
                ForEach(days, id: \.self) { day in
                    DoseCalendarDayButton(
                        day: day,
                        tasks: tasksForDay(day),
                        doseChangeCount: doseChangesForDay(day).count,
                        isSelected: Calendar.current.isDate(day, inSameDayAs: selectedDate),
                        showsWeekday: true,
                        action: {
                            selectedDate = day
                            openDay(day)
                        }
                    )
                }
            }
        }
        .padding(.vertical, 8)
    }
}

private struct MonthDoseCalendarView: View {
    @Binding var selectedDate: Date
    @Binding var displayedMonth: Date
    let monthRange: ClosedRange<Date>
    let days: [Date]
    let tasksForDay: (Date) -> [StoredDoseTask]
    let doseChangesForDay: (Date) -> [StoredMedicationDoseChange]
    let openDay: (Date) -> Void
    let transitionDirection: Int
    let moveMonth: (Int) -> Void
    let tint: Color

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 7)

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Button {
                    withAnimation(.snappy(duration: 0.24, extraBounce: 0.01)) {
                        moveMonth(-1)
                    }
                } label: {
                    MonthNavigationButton(
                        systemImage: "chevron.left",
                        accessibilityText: "上一月",
                        isEnabled: canMoveBackward
                    )
                }
                .buttonStyle(.plain)
                .disabled(!canMoveBackward)
                .accessibilityLabel("上一月")

                Spacer()
                Text(monthTitle)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Spacer()
                Button {
                    withAnimation(.snappy(duration: 0.24, extraBounce: 0.01)) {
                        moveMonth(1)
                    }
                } label: {
                    MonthNavigationButton(
                        systemImage: "chevron.right",
                        accessibilityText: "下一月",
                        isEnabled: canMoveForward
                    )
                }
                .buttonStyle(.plain)
                .disabled(!canMoveForward)
                .accessibilityLabel("下一月")
            }
            .foregroundStyle(.secondary)

            HStack(spacing: 0) {
                ForEach(weekdaySymbols, id: \.self) { symbol in
                    Text(symbol)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }

            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(Array(monthCells.enumerated()), id: \.offset) { _, cellDate in
                    if let day = cellDate {
                        DoseCalendarDayButton(
                            day: day,
                            tasks: tasksForDay(day),
                            doseChangeCount: doseChangesForDay(day).count,
                            isSelected: Calendar.current.isDate(day, inSameDayAs: selectedDate),
                            showsWeekday: false,
                            tint: tint,
                            action: {
                                selectedDate = day
                                openDay(day)
                            }
                        )
                    } else {
                        Color.clear
                            .frame(maxWidth: .infinity, minHeight: 52)
                    }
                }
            }
            .id(displayedMonth)
            .transition(monthGridTransition)
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 28)
                .onEnded { value in
                    if value.translation.width < -44 {
                        moveMonth(1)
                    } else if value.translation.width > 44 {
                        moveMonth(-1)
                    }
                }
        )
        .animation(.smooth(duration: 0.18), value: displayedMonth)
    }

    private var monthTitle: String {
        AppFormatters.month.string(from: displayedMonth)
    }

    private var weekdaySymbols: [String] {
        ["日", "一", "二", "三", "四", "五", "六"]
    }

    private var monthCells: [Date?] {
        guard let firstDay = days.first else {
            return []
        }
        let leadingCount = Calendar.current.component(.weekday, from: firstDay) - 1
        return Array(repeating: nil, count: max(0, leadingCount)) + days.map(Optional.some)
    }

    private var canMoveBackward: Bool {
        monthRange.contains(previousMonth)
    }

    private var canMoveForward: Bool {
        monthRange.contains(nextMonth)
    }

    private var previousMonth: Date {
        Calendar.current.date(byAdding: .month, value: -1, to: displayedMonth) ?? displayedMonth
    }

    private var nextMonth: Date {
        Calendar.current.date(byAdding: .month, value: 1, to: displayedMonth) ?? displayedMonth
    }

    private var monthGridTransition: AnyTransition {
        .opacity
    }
}

private struct DoseCalendarDayButton: View {
    let day: Date
    let tasks: [StoredDoseTask]
    let doseChangeCount: Int
    let isSelected: Bool
    let showsWeekday: Bool
    var tint: Color = .blue
    let action: () -> Void

    private var completedCount: Int {
        tasks.filter { $0.status == .taken || $0.status == .corrected }.count
    }

    private var isFuturePlanOnly: Bool {
        recordsTasksAreFuturePlanOnly(tasks, on: day, now: Date())
    }

    var body: some View {
        Button(action: action) {
            if showsWeekday {
                weekBody
            } else {
                monthBody
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityText)
    }

    private var weekBody: some View {
        VStack(spacing: 5) {
            Text(weekdayText)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            ZStack(alignment: .center) {
                RecordsCalendarProgressRing(
                    progress: dayProgress,
                    color: indicatorColor.opacity(indicatorOpacity),
                    isEmpty: tasks.isEmpty,
                    size: 34,
                    lineWidth: 4
                )
                Text(dayNumberText)
                    .font(.subheadline.weight(.semibold))
                if doseChangeCount > 0 {
                    Circle()
                        .fill(Color.purple.opacity(0.72))
                        .frame(width: 6, height: 6)
                        .frame(width: 34, height: 34, alignment: .topTrailing)
                        .offset(x: 1.5, y: -1.5)
                }
            }
            if !tasks.isEmpty {
                Text(dayProgressText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 58)
        .background(dayBackground, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(isSelected ? tint.opacity(0.45) : Color.clear, lineWidth: 1)
        }
    }

    private var monthBody: some View {
        VStack(spacing: 4) {
            ZStack(alignment: .center) {
                RecordsCalendarProgressRing(
                    progress: dayProgress,
                    color: indicatorColor.opacity(indicatorOpacity),
                    isEmpty: tasks.isEmpty,
                    size: 32,
                    lineWidth: 3.5
                )
                Text(dayNumberText)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(isSelected ? tint : .primary.opacity(0.82))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                if doseChangeCount > 0 {
                    Circle()
                        .fill(Color.purple.opacity(0.72))
                        .frame(width: 5, height: 5)
                        .frame(width: 32, height: 32, alignment: .topTrailing)
                        .offset(x: 1.5, y: -1.5)
                }
            }
            Text(tasks.isEmpty ? " " : dayProgressText)
                .font(.system(size: 8, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.72)
            .frame(height: 9)
        }
        .padding(.horizontal, 2)
        .frame(maxWidth: .infinity, minHeight: 52)
        .background(dayBackground, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(isSelected ? tint.opacity(0.46) : Color.clear, lineWidth: 1)
        }
    }

    private var dayBackground: Color {
        isSelected ? tint.opacity(0.14) : Color.secondary.opacity(0.032)
    }

    private var dayNumberText: String {
        "\(Calendar.current.component(.day, from: day))"
    }

    private var accessibilityText: String {
        let taskText = tasks.isEmpty ? "没有用药任务" : (isFuturePlanOnly ? "\(tasks.count) 项计划中" : "\(completedCount) / \(tasks.count) 项已完成")
        let doseChangeText = doseChangeCount > 0 ? "，\(doseChangeCount) 条剂量变化" : ""
        return "\(AppFormatters.day.string(from: day))，\(taskText)\(doseChangeText)"
    }

    private var dayProgressText: String {
        isFuturePlanOnly ? "\(tasks.count)项" : "\(completedCount)/\(tasks.count)"
    }

    private var dayProgress: Double {
        guard !tasks.isEmpty else {
            return 0
        }
        return isFuturePlanOnly ? 0 : Double(completedCount) / Double(tasks.count)
    }

    private var weekdayText: String {
        let symbols = ["日", "一", "二", "三", "四", "五", "六"]
        let index = Calendar.current.component(.weekday, from: day) - 1
        return symbols[max(0, min(index, symbols.count - 1))]
    }

    private var indicatorColor: Color {
        guard !tasks.isEmpty else {
            return doseChangeCount > 0 ? .purple : .secondary
        }
        if tasks.contains(where: { $0.status == .skipped }) {
            return .orange
        }
        if tasks.allSatisfy({ $0.status == .taken || $0.status == .corrected }) {
            return .green
        }
        if isFuturePlanOnly {
            return .secondary
        }
        return tint
    }

    private var indicatorOpacity: Double {
        guard !tasks.isEmpty else {
            return doseChangeCount > 0 ? 0.62 : 0
        }
        if tasks.contains(where: { $0.status == .skipped }) {
            return 0.72
        }
        if tasks.allSatisfy({ $0.status == .taken || $0.status == .corrected }) {
            return 0.68
        }
        if isFuturePlanOnly {
            return 0.34
        }
        return 0.56
    }
}

private struct DayDoseListView: View {
    let date: Date
    let tasks: [StoredDoseTask]
    let doseChanges: [StoredMedicationDoseChange]
    let allDoseChanges: [StoredMedicationDoseChange]
    let medication: (StoredDoseTask) -> StoredMedication?
    let medicationForDoseChange: (StoredMedicationDoseChange) -> StoredMedication?
    let openTask: (StoredDoseTask) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if tasks.isEmpty {
                Text("这一天没有用药任务。")
                    .foregroundStyle(.secondary)
            } else if isFuturePlanOnly {
                Text("这一天有 \(tasks.count) 项计划提醒，尚未到记录时间。")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(tasks) { task in
                    Button {
                        openTask(task)
                    } label: {
                        DayDoseTaskLine(task: task, medication: medication(task))
                    }
                    .buttonStyle(.plain)
                }
            }

            if !doseChanges.isEmpty {
                Divider()
                Text("剂量变化")
                    .font(.subheadline.weight(.semibold))
                ForEach(doseChanges) { change in
                    DoseChangeLine(
                        change: change,
                        effectiveUntil: doseChangeEffectiveUntil(change, in: allDoseChanges),
                        medication: medicationForDoseChange(change)
                    )
                }
            }
        }
        .padding(.vertical, 8)
    }

    private var isFuturePlanOnly: Bool {
        recordsTasksAreFuturePlanOnly(tasks, on: date, now: Date())
    }
}

private struct DayDoseDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    let date: Date
    let tasks: [StoredDoseTask]
    let actionLogs: [StoredDoseActionLog]
    let doseChanges: [StoredMedicationDoseChange]
    let allDoseChanges: [StoredMedicationDoseChange]
    let medication: (StoredDoseTask) -> StoredMedication?
    let medicationForDoseChange: (StoredMedicationDoseChange) -> StoredMedication?
    let medicationForActionLog: (StoredDoseActionLog) -> StoredMedication?
    let isPresentingCorrection: Bool
    let openTask: (StoredDoseTask) -> Void

    private var completedCount: Int {
        tasks.filter { $0.status == .taken || $0.status == .corrected }.count
    }

    private var skippedCount: Int {
        tasks.filter { $0.status == .skipped }.count
    }

    private var delayedCount: Int {
        tasks.filter { $0.status == .delayed }.count
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                DayDoseDetailHeroCard(
                    date: date,
                    totalCount: tasks.count,
                    completedCount: completedCount,
                    skippedCount: skippedCount,
                    delayedCount: delayedCount,
                    doseChangeCount: doseChanges.count,
                    isFuturePlanOnly: isFuturePlanOnly
                )

                RecordsPanelContainer(
                    title: "当天服药详情",
                    subtitle: tasks.isEmpty ? "这一天没有服药记录" : nil
                ) {
                    if tasks.isEmpty {
                        RecordsEmptyStateLine(
                            systemImage: "calendar.badge.clock",
                            title: "这一天没有用药任务",
                            message: "暂无记录。"
                        )
                    } else if isFuturePlanOnly {
                        RecordsEmptyStateLine(
                            systemImage: "calendar.badge.clock",
                            title: "\(tasks.count) 项计划提醒",
                            message: "尚未到记录时间。"
                        )
                    } else {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(tasks.enumerated()), id: \.element.id) { index, task in
                                Button {
                                    openTask(task)
                                } label: {
                                    DayDoseDetailTaskRow(task: task, medication: medication(task))
                                }
                                .buttonStyle(.plain)
                                .padding(.vertical, 10)

                                if index < tasks.count - 1 {
                                    Divider()
                                        .opacity(0.42)
                                        .padding(.leading, 56)
                                }
                            }
                        }
                    }
                }

                if !actionLogs.isEmpty {
                    RecordsPanelContainer(title: "操作记录") {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(actionLogs.enumerated()), id: \.element.id) { index, log in
                                DoseActionLogRow(
                                    log: log,
                                    medication: medicationForActionLog(log)
                                )
                                .padding(.vertical, 9)

                                if index < actionLogs.count - 1 {
                                    Divider()
                                        .opacity(0.42)
                                        .padding(.leading, 46)
                                }
                            }
                        }
                    }
                }

                if !doseChanges.isEmpty {
                    RecordsPanelContainer(title: "剂量变化") {
                        LazyVStack(alignment: .leading, spacing: 8) {
                            ForEach(doseChanges) { change in
                                DoseChangeLine(
                                    change: change,
                                    effectiveUntil: doseChangeEffectiveUntil(change, in: allDoseChanges),
                                    medication: medicationForDoseChange(change)
                                )
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 28)
        }
        .transaction { transaction in
            transaction.animation = nil
        }
        .accessibilityHidden(isPresentingCorrection)
        .background(Color(.systemGroupedBackground))
        .navigationTitle("日期详情")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("完成") {
                    dismiss()
                }
            }
        }
    }

    private var daySummaryText: String {
        var parts: [String] = []
        parts.append(tasks.isEmpty ? "这一天没有用药任务。" : (isFuturePlanOnly ? "\(tasks.count) 项计划提醒，尚未到记录时间。" : "\(tasks.count) 项用药记录。"))
        if !doseChanges.isEmpty {
            parts.append("\(doseChanges.count) 条剂量变化。")
        }
        return parts.joined(separator: " ")
    }

    private var isFuturePlanOnly: Bool {
        recordsTasksAreFuturePlanOnly(tasks, on: date, now: Date())
    }
}

private struct DoseActionLogRow: View {
    let log: StoredDoseActionLog
    let medication: StoredMedication?

    private var isClosed: Bool {
        log.undoneAt != nil
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: iconName)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 30, height: 30)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(log.actionDisplayName)
                        .font(.subheadline.weight(.semibold))
                    if isClosed {
                        Text("已撤销")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.secondary.opacity(0.10), in: Capsule())
                    }
                }
                Text("\(medication.map(userFacingMedicationName(for:)) ?? "未知药品") · \(AppFormatters.time.string(from: log.occurredAt))")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                if let displayNote = log.recordDisplayNote {
                    Text(displayNote)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    private var tint: Color {
        switch DoseActionKind(rawValue: log.actionRaw) {
        case .markTaken:
            .green
        case .delay:
            .blue
        case .skip:
            .orange
        case .archiveToday, .restoreArchive:
            .secondary
        case .correct, nil:
            .blue
        }
    }

    private var iconName: String {
        switch DoseActionKind(rawValue: log.actionRaw) {
        case .markTaken:
            "checkmark.circle.fill"
        case .delay:
            "clock.arrow.circlepath"
        case .skip:
            "forward.circle.fill"
        case .archiveToday:
            "archivebox.fill"
        case .restoreArchive:
            "tray.and.arrow.up.fill"
        case .correct, nil:
            "pencil.circle.fill"
        }
    }
}

private struct RecordsLinearProgressBar: View {
    let progress: Double
    let tint: Color

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.secondary.opacity(0.10))
                Capsule()
                    .fill(tint.opacity(0.58))
                    .frame(width: max(0, proxy.size.width * progress))
            }
        }
        .frame(height: 5)
        .accessibilityLabel("当天完成进度")
        .accessibilityValue("\(Int((progress * 100).rounded()))%")
    }
}

private struct DayDoseDetailHeroCard: View {
    let date: Date
    let totalCount: Int
    let completedCount: Int
    let skippedCount: Int
    let delayedCount: Int
    let doseChangeCount: Int
    let isFuturePlanOnly: Bool

    private var summaryText: String {
        if totalCount == 0, doseChangeCount == 0 {
            return "没有需要展示的服药记录。"
        }
        if isFuturePlanOnly {
            return "\(totalCount) 项计划提醒，尚未到记录时间。"
        }
        if completedCount == totalCount, totalCount > 0 {
            return doseChangeCount > 0 ? "当天记录已完成，并有剂量变化。" : "当天记录已完成。"
        }
        if skippedCount > 0 || delayedCount > 0 {
            return "有忽略或稍后记录。"
        }
        if doseChangeCount > 0 {
            return "\(doseChangeCount) 条剂量变化。"
        }
        return "\(completedCount) / \(totalCount) 项已完成。"
    }

    private var completionRatio: Double {
        guard totalCount > 0, !isFuturePlanOnly else {
            return 0
        }
        return min(max(Double(completedCount) / Double(totalCount), 0), 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: "calendar")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(progressTint)
                    .frame(width: 46, height: 46)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                VStack(alignment: .leading, spacing: 5) {
                    Text(AppFormatters.day.string(from: date))
                        .font(.title3.weight(.semibold))
                    Text(summaryText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }

            RecordsLinearProgressBar(
                progress: completionRatio,
                tint: progressTint
            )

            HStack(spacing: 0) {
                RecordsMetricPill(title: isFuturePlanOnly ? "计划" : "总记录", value: "\(totalCount)")
                RecordsMetricDivider()
                RecordsMetricPill(title: "已完成", value: "\(completedCount)")
                RecordsMetricDivider()
                RecordsMetricPill(title: "剂量变化", value: "\(doseChangeCount)")
            }
        }
        .padding(18)
        .medicationGlassSurface(cornerRadius: 18, tint: progressTint, fallbackMaterial: .regularMaterial)
        .shadow(color: Color.black.opacity(0.035), radius: 10, x: 0, y: 4)
    }

    private var progressTint: Color {
        if skippedCount > 0 || delayedCount > 0 {
            return .orange
        }
        if completionRatio >= 0.999, totalCount > 0 {
            return .green
        }
        if totalCount > 0, !isFuturePlanOnly {
            return .blue
        }
        if doseChangeCount > 0 {
            return .purple
        }
        return .secondary
    }
}

private struct DayDoseDetailTaskRow: View {
    let task: StoredDoseTask
    let medication: StoredMedication?

    private var badgeColor: Color {
        switch task.status {
        case .taken, .corrected:
            return .green
        case .delayed:
            return .blue
        case .skipped:
            return .orange
        case .pending:
            return .secondary
        }
    }

    private var recordTimingTolerance: TimeInterval {
        DoseReminderPolicy.competitionDemo.autoSkipInterval
    }

    private var timeDetailText: String {
        let planned = AppFormatters.time.string(from: task.dueAt)
        guard task.status != .pending, let recordedAt = task.effectiveAdherenceRecordedAt else {
            return "计划 \(planned)"
        }
        let recorded = AppFormatters.time.string(from: recordedAt)
        switch task.status {
        case .delayed:
            return "计划 \(planned) · 稍后操作 \(recorded)"
        case .skipped:
            let actionTitle = task.isAutoSkippedByReminderSettlement ? "自动忽略" : "忽略操作"
            return "计划 \(planned) · \(actionTitle) \(recorded)"
        case .pending, .taken, .corrected:
            break
        }
        if recorded == planned {
            return "计划 \(planned) · 已按时记录"
        }
        if recordedAt < task.dueAt.addingTimeInterval(-recordTimingTolerance) {
            return "计划 \(planned) · 提前记录 \(recorded)"
        }
        if recordedAt > task.dueAt.addingTimeInterval(recordTimingTolerance) {
            return "计划 \(planned) · 延后记录 \(recorded)"
        }
        return "计划 \(planned) · 记录 \(recorded)"
    }

    var body: some View {
        HStack(spacing: 12) {
            MedicationPhotoView(
                photoData: medication?.photoData,
                symbolName: medication?.photoSymbolName ?? "pills.fill",
                tint: badgeColor,
                size: 42
            )

            VStack(alignment: .leading, spacing: 4) {
                Text(medication.map(userFacingMedicationName(for:)) ?? "未知药品")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(timeDetailText)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.84)
                Text("\(task.doseValue.formatted()) \(localizedMedicationUnit(task.doseUnit))")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                if let displayReason = task.recordDisplayReason {
                    Text(displayReason)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 6) {
                StatusBadge(text: task.status.displayName, color: badgeColor)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .contentShape(Rectangle())
    }
}

private struct DoseChangeLine: View {
    let change: StoredMedicationDoseChange
    let effectiveUntil: Date?
    let medication: StoredMedication?

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.purple)
                .frame(width: 30, height: 30)
                .background(Color.purple.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 3) {
                Text(medication.map(userFacingMedicationName(for:)) ?? "未知药品")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(doseChangeText)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Text(doseChangeEffectivePeriodText(change: change, effectiveUntil: effectiveUntil))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                if !change.note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(change.note)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
    }

    private var doseChangeText: String {
        let newDose = "\(change.newDoseValue.formatted()) \(localizedMedicationUnit(change.newDoseUnit))"
        guard let previousDoseValue = change.previousDoseValue else {
            return "初始剂量 \(newDose)"
        }
        let previousDose = "\(previousDoseValue.formatted()) \(localizedMedicationUnit(change.previousDoseUnit))"
        return "\(previousDose) 调整为 \(newDose)"
    }
}

private struct DayDoseTaskLine: View {
    let task: StoredDoseTask
    let medication: StoredMedication?

    private var tint: Color {
        switch task.status {
        case .taken, .corrected:
            return .green
        case .delayed:
            return .blue
        case .skipped:
            return .orange
        case .pending:
            return .secondary
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            MedicationPhotoView(
                photoData: medication?.photoData,
                symbolName: medication?.photoSymbolName ?? "pills.fill",
                tint: tint,
                size: 40
            )
            VStack(alignment: .leading, spacing: 3) {
                Text(medication.map(userFacingMedicationName(for:)) ?? "未知药品")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Text("\(AppFormatters.time.string(from: task.dueAt)) · \(task.doseValue.formatted()) \(localizedMedicationUnit(task.doseUnit))")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            StatusBadge(text: task.status.displayName, color: tint)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
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

private func recordsTasksAreFuturePlanOnly(_ tasks: [StoredDoseTask], on date: Date, now: Date) -> Bool {
    let calendar = Calendar.current
    return calendar.startOfDay(for: date) > calendar.startOfDay(for: now)
        && !tasks.isEmpty
        && tasks.allSatisfy { task in
            (task.status == .pending || task.status == .delayed) && task.dueAt > now
        }
}
