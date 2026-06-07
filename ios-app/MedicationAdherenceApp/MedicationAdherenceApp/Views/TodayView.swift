import MedicationAdherenceCore
import SwiftData
import SwiftUI

struct TodayView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \StoredDoseTask.dueAt) private var tasks: [StoredDoseTask]
    @Query(sort: \StoredMedication.displayName) private var medications: [StoredMedication]
    @Query(sort: \StoredMedicationPlan.createdAt) private var plans: [StoredMedicationPlan]
    @Query(sort: \StoredDoseActionLog.occurredAt, order: .reverse) private var actionLogs: [StoredDoseActionLog]
    @AppStorage("prefersReducedAppMotion") private var prefersReducedAppMotion = false
    @StateObject private var notificationService = NotificationService()
    @StateObject private var liveActivityService = MedicationLiveActivityService()
    @StateObject private var weatherMedicationService = WeatherMedicationService()
    @State private var taskPendingArchive: StoredDoseTask?
    @State private var showingArchiveConfirmation = false
    @State private var showingHandledTasks = false
    @State private var pendingDoseFeedback: PendingDoseFeedback?
    @State private var isOpenTimelineTemporarilyCollapsed = false
    @State private var isHandledTimelineTemporarilyCollapsed = false
    @State private var pendingHandledArrivalCount = 0
    @State private var closingOpenTaskIDs: Set<UUID> = []
    @State private var reopeningHandledTaskIDs: Set<UUID> = []
    @State private var handledDropTargetPulse = false
    @State private var doseMigrationSnapshot: DoseMigrationSnapshot?
    @State private var recentlyReopenedTaskIDs: Set<UUID> = []
    @State private var pendingDoseFeedbackTask: Task<Void, Never>?
    @State private var doseLayoutTransitionTask: Task<Void, Never>?
    @State private var reopenHighlightTasks: [UUID: Task<Void, Never>] = [:]
    @State private var liveActivityRefreshTask: Task<Void, Never>?
    private let liveActivityRefreshTimer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    private var todayTasks: [StoredDoseTask] {
        let calendar = Calendar.current
        let delayedFromTodayTaskIDs = Set(actionLogs.compactMap { log -> UUID? in
            guard log.undoneAt == nil,
                  log.actionRaw == DoseActionKind.delay.rawValue,
                  calendar.isDateInToday(log.previousDueAt) || calendar.isDateInToday(log.occurredAt)
            else {
                return nil
            }
            return log.taskID
        })
        return tasks.filter { task in
            calendar.isDateInToday(task.dueAt)
                || (delayedFromTodayTaskIDs.contains(task.id) && isOpenStatus(task.status))
        }
    }

    private var displayTodayTasks: [StoredDoseTask] {
        deduplicatedTodayTasks(
            todayTasks.sorted { lhs, rhs in
                if lhs.dueAt == rhs.dueAt {
                    return lhs.id.uuidString < rhs.id.uuidString
                }
                return lhs.dueAt < rhs.dueAt
            }
        )
    }

    private var openTasks: [StoredDoseTask] {
        displayTodayTasks.filter { $0.status == .pending || $0.status == .delayed }
    }

    private var visibleOpenTimelineTasks: [StoredDoseTask] {
        displayTodayTasks
            .filter { !isArchived($0) && isOpenStatus($0.status) }
            .sorted { lhs, rhs in
                if lhs.dueAt == rhs.dueAt {
                    return lhs.id.uuidString < rhs.id.uuidString
                }
                return lhs.dueAt < rhs.dueAt
            }
    }

    private var handledTodayTasks: [StoredDoseTask] {
        displayTodayTasks
            .filter { !isArchived($0) && !isOpenStatus($0.status) }
            .sorted { lhs, rhs in
                let lhsRecordedAt = lhs.recordedAt ?? lhs.dueAt
                let rhsRecordedAt = rhs.recordedAt ?? rhs.dueAt
                if lhsRecordedAt == rhsRecordedAt {
                    return lhs.id.uuidString < rhs.id.uuidString
                }
                return lhsRecordedAt > rhsRecordedAt
            }
    }

    private var archivedTodayTasks: [StoredDoseTask] {
        displayTodayTasks
            .filter { isArchived($0) }
            .sorted { lhs, rhs in
                if lhs.dueAt == rhs.dueAt {
                    return lhs.id.uuidString < rhs.id.uuidString
                }
                return lhs.dueAt < rhs.dueAt
            }
    }

    private var shouldShowHandledSection: Bool {
        !handledTodayTasks.isEmpty || isHandledTimelineTemporarilyCollapsed || handledDropTargetPulse || !reopeningHandledTaskIDs.isEmpty
    }

    private var displayedOpenCount: Int {
        guard !reopeningHandledTaskIDs.isEmpty else {
            return visibleOpenTimelineTasks.count
        }
        let visibleIDs = Set(visibleOpenTimelineTasks.map(\.id))
        let reopeningCount = reopeningHandledTaskIDs.filter { !visibleIDs.contains($0) }.count
        return visibleOpenTimelineTasks.count + reopeningCount
    }

    private var displayedHandledCount: Int {
        guard !closingOpenTaskIDs.isEmpty else {
            return handledTodayTasks.count + pendingHandledArrivalCount
        }
        let handledIDs = Set(handledTodayTasks.map(\.id))
        let incomingCount = closingOpenTaskIDs.filter { !handledIDs.contains($0) }.count
        return handledTodayTasks.count + incomingCount
    }

    private var handledDisclosureBinding: Binding<Bool> {
        Binding(
            get: { showingHandledTasks && !isHandledTimelineTemporarilyCollapsed },
            set: { showingHandledTasks = $0 }
        )
    }

    private var completedCount: Int {
        displayTodayTasks.filter { $0.status == .taken || $0.status == .corrected }.count
    }

    private var isAllTaken: Bool {
        !displayTodayTasks.isEmpty && completedCount == displayTodayTasks.count
    }

    private var progressValue: Double {
        guard !displayTodayTasks.isEmpty else {
            return 0
        }
        return Double(completedCount) / Double(displayTodayTasks.count)
    }

    private var statusSignature: String {
        todayTasks
            .map { "\($0.id.uuidString)-\($0.statusRaw)-\($0.dueAt.timeIntervalSince1970)" }
            .joined(separator: "|")
    }

    private var weatherMedicationSignature: String {
        medications
            .map { "\($0.id.uuidString)-\($0.displayName)-\($0.form)-\($0.notes)" }
            .joined(separator: "|")
    }

    var body: some View {
        List {
            Section {
                TodayProgressCard(
                    completedCount: completedCount,
                    totalCount: displayTodayTasks.count,
                    progressValue: progressValue,
                    isAllTaken: isAllTaken
                )
            }

            Section("今日待处理") {
                if isOpenTimelineTemporarilyCollapsed {
                    OpenDoseSummaryRow(
                        count: displayedOpenCount,
                        latestText: "正在恢复待处理记录",
                        isReceiving: !reopeningHandledTaskIDs.isEmpty,
                        migrationSnapshot: doseMigrationSnapshot
                    )
                    .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .top)))
                } else if visibleOpenTimelineTasks.isEmpty {
                    Text(todayTasks.isEmpty ? "今天还没有用药任务。" : "当前没有待处理用药。")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(visibleOpenTimelineTasks) { task in
                        TimelineDoseTaskRow(
                            task: task,
                            medication: medication(for: task),
                            completionText: completionVerb(for: medication(for: task)),
                            statusText: statusText(for: task),
                            isOpen: task.status == .pending || task.status == .delayed,
                            feedbackAction: pendingDoseFeedback?.taskID == task.id ? pendingDoseFeedback?.action : nil,
                            isClosing: closingOpenTaskIDs.contains(task.id),
                            isRecentlyReopened: recentlyReopenedTaskIDs.contains(task.id),
                            markTaken: {
                                performWithDoseFeedback(task, action: .taken) {
                                    mark(task, as: .taken, action: .markTaken, reason: "")
                                }
                            },
                            delay: {
                                performWithDoseFeedback(task, action: .delay) {
                                    delay(task)
                                }
                            },
                            skip: {
                                performWithDoseFeedback(task, action: .skip) {
                                    mark(task, as: .skipped, action: .skip, reason: "用户忽略")
                                }
                            }
                        )
                    }
                }
            }
            .animation(.snappy(duration: 0.26, extraBounce: 0.02), value: visibleOpenTimelineTasks.map(\.id))
            .animation(.easeInOut(duration: 0.16), value: pendingDoseFeedback)
            .animation(.snappy(duration: 0.24, extraBounce: 0.01), value: isOpenTimelineTemporarilyCollapsed)
            .animation(.easeInOut(duration: 0.18), value: closingOpenTaskIDs)
            .animation(.snappy(duration: 0.24, extraBounce: 0.02), value: recentlyReopenedTaskIDs)

            if shouldShowHandledSection {
                Section {
                    DisclosureGroup(isExpanded: handledDisclosureBinding) {
                        ForEach(handledTodayTasks) { task in
                            HandledDoseTaskRow(
                                task: task,
                                medication: medication(for: task),
                                statusText: statusText(for: task),
                                undo: { undoOrReopen(task) },
                                archive: {
                                    taskPendingArchive = task
                                    showingArchiveConfirmation = true
                                }
                            )
                            .opacity(reopeningHandledTaskIDs.contains(task.id) ? 0.12 : 1)
                            .blur(radius: reopeningHandledTaskIDs.contains(task.id) ? 4 : 0)
                            .scaleEffect(reopeningHandledTaskIDs.contains(task.id) ? 0.97 : 1)
                            .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .top)))
                        }
                    } label: {
                        HandledDoseSummaryRow(
                            count: displayedHandledCount,
                            latestText: handledDropTargetPulse ? "正在收起刚刚处理的记录" : handledTodayTasks.first.map { handledTaskSummary(for: $0) } ?? "已处理记录可在这里找回",
                            isReceiving: handledDropTargetPulse,
                            migrationSnapshot: handledDropTargetPulse ? doseMigrationSnapshot : nil
                        )
                    }
                } header: {
                    Text("今日已处理")
                } footer: {
                    Text("误操作可展开后撤销；归档只隐藏今日列表，不删除历史。")
                }
                .animation(.snappy(duration: 0.22, extraBounce: 0.01), value: handledTodayTasks.map(\.id))
                .animation(.snappy(duration: 0.22, extraBounce: 0.01), value: isHandledTimelineTemporarilyCollapsed)
                .animation(.easeInOut(duration: 0.18), value: reopeningHandledTaskIDs)
                .animation(.easeInOut(duration: 0.2), value: handledDropTargetPulse)
            }

            if !archivedTodayTasks.isEmpty {
                Section("今日已归档") {
                    ForEach(archivedTodayTasks) { task in
                        ArchivedDoseTaskRow(
                            task: task,
                            medication: medication(for: task),
                            statusText: statusText(for: task),
                            restore: { unarchive(task) },
                            reopen: { undoOrReopen(task) }
                        )
                    }
                }
            }

            Section("下一次提醒") {
                if let nextTask = openTasks.first {
                    HStack {
                        Image(systemName: "bell.badge")
                            .foregroundStyle(.blue)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(medication(for: nextTask)?.displayName ?? "用药提醒")
                                .font(.headline)
                            Text(AppFormatters.time.string(from: nextTask.dueAt))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 6)
                } else {
                    Text("今天没有待提醒任务。")
                        .foregroundStyle(.secondary)
                }
            }

            Section("天气与用药关注") {
                if weatherMedicationService.isLoading && weatherMedicationService.hints.isEmpty {
                    ProgressView("正在读取今日天气")
                }
                ForEach(weatherMedicationService.hints) { hint in
                    WeatherMedicationHintCard(hint: hint)
                }
                if weatherMedicationService.shouldShowAuthorizationButton {
                    Button {
                        Task {
                            await weatherMedicationService.refresh(medications: medications, requestAuthorization: true)
                        }
                    } label: {
                        Label("允许天气提醒", systemImage: "location.fill")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                Text(weatherMedicationService.statusText)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("今日")
        .task(id: weatherMedicationSignature) {
            await weatherMedicationService.refresh(medications: medications)
        }
        .task(id: statusSignature) {
            scheduleLiveActivityRefresh()
        }
        .onReceive(liveActivityRefreshTimer) { _ in
            Task {
                await refreshLiveActivities()
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else {
                return
            }
            scheduleLiveActivityRefresh()
        }
        .confirmationDialog("归档这条今日记录？", isPresented: $showingArchiveConfirmation) {
            Button("归档记录", role: .destructive) {
                if let task = taskPendingArchive {
                    archive(task)
                    taskPendingArchive = nil
                }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("\(taskPendingArchive.flatMap { medication(for: $0)?.displayName } ?? "这条记录") 会从今日已处理列表隐藏，但仍保留在服药历史中。")
        }
        .onDisappear {
            pendingDoseFeedbackTask?.cancel()
            pendingDoseFeedbackTask = nil
            doseLayoutTransitionTask?.cancel()
            doseLayoutTransitionTask = nil
            reopenHighlightTasks.values.forEach { $0.cancel() }
            reopenHighlightTasks = [:]
            liveActivityRefreshTask?.cancel()
            liveActivityRefreshTask = nil
        }
    }

    private func medication(for task: StoredDoseTask) -> StoredMedication? {
        medications.first { $0.id == task.medicationID }
    }

    private func deduplicatedTodayTasks(_ tasks: [StoredDoseTask]) -> [StoredDoseTask] {
        var tasksByLogicalDose: [String: StoredDoseTask] = [:]
        for task in tasks {
            let key = logicalDoseKey(for: task)
            if let current = tasksByLogicalDose[key] {
                tasksByLogicalDose[key] = preferredDisplayTask(current, task)
            } else {
                tasksByLogicalDose[key] = task
            }
        }
        return tasksByLogicalDose.values.sorted { lhs, rhs in
            if lhs.dueAt == rhs.dueAt {
                return lhs.id.uuidString < rhs.id.uuidString
            }
            return lhs.dueAt < rhs.dueAt
        }
    }

    private func logicalDoseKey(for task: StoredDoseTask) -> String {
        let minuteKey = Int(task.dueAt.timeIntervalSince1970 / 60)
        return "\(task.medicationID.uuidString)-\(task.planID.uuidString)-\(minuteKey)"
    }

    private func preferredDisplayTask(_ lhs: StoredDoseTask, _ rhs: StoredDoseTask) -> StoredDoseTask {
        let lhsScore = displayPriorityScore(for: lhs)
        let rhsScore = displayPriorityScore(for: rhs)
        if lhsScore != rhsScore {
            return lhsScore > rhsScore ? lhs : rhs
        }
        let lhsReferenceDate = lhs.recordedAt ?? lhs.dueAt
        let rhsReferenceDate = rhs.recordedAt ?? rhs.dueAt
        if lhsReferenceDate != rhsReferenceDate {
            return lhsReferenceDate > rhsReferenceDate ? lhs : rhs
        }
        return lhs.id.uuidString < rhs.id.uuidString ? lhs : rhs
    }

    private func displayPriorityScore(for task: StoredDoseTask) -> Int {
        var score = 0
        if recentlyReopenedTaskIDs.contains(task.id) {
            score += 1_000
        }
        if pendingDoseFeedback?.taskID == task.id {
            score += 900
        }
        if task.recordedAt != nil {
            score += 120
        }
        switch task.status {
        case .taken, .corrected:
            score += 500
        case .skipped:
            score += 480
        case .delayed:
            score += 360
        case .pending:
            score += 300
        }
        return score
    }

    private func isOpenStatus(_ status: StoredDoseStatus) -> Bool {
        status == .pending || status == .delayed
    }

    private func mark(_ task: StoredDoseTask, as status: StoredDoseStatus, action: DoseActionKind, reason: String) {
        let occurredAt = Date()
        let log = StoredDoseActionLog(
            taskID: task.id,
            action: action,
            previousStatus: task.status,
            previousDueAt: task.dueAt,
            previousRecordedAt: task.recordedAt,
            previousReason: task.reason,
            newStatus: status,
            occurredAt: occurredAt,
            undoExpiresAt: occurredAt.addingTimeInterval(10 * 60),
            note: reason
        )
        modelContext.insert(log)
        updateDoseState {
            task.status = status
            task.recordedAt = occurredAt
            task.reason = reason
            try? modelContext.save()
        }
        Task {
            notificationService.cancelReminder(for: task.id)
            await liveActivityService.end(for: task.id)
            scheduleLiveActivityRefresh(after: 0.35)
        }
    }

    private func delay(_ task: StoredDoseTask) {
        let occurredAt = Date()
        let newDueAt = Calendar.current.date(byAdding: .minute, value: 30, to: occurredAt) ?? task.dueAt
        let log = StoredDoseActionLog(
            taskID: task.id,
            action: .delay,
            previousStatus: task.status,
            previousDueAt: task.dueAt,
            previousRecordedAt: task.recordedAt,
            previousReason: task.reason,
            newStatus: .delayed,
            occurredAt: occurredAt,
            undoExpiresAt: occurredAt.addingTimeInterval(10 * 60),
            note: "用户选择稍后提醒"
        )
        modelContext.insert(log)
        updateDoseState {
            task.status = .delayed
            task.recordedAt = occurredAt
            task.reason = "用户选择 30 分钟后提醒"
            task.dueAt = newDueAt
            try? modelContext.save()
        }
        Task {
            await liveActivityService.end(for: task.id)
            scheduleLiveActivityRefresh(after: 0.35)
        }
        if let medication = medication(for: task) {
            Task {
                await notificationService.scheduleReminder(
                    for: task,
                    medication: medication,
                    deliveryMethod: reminderDeliveryMethod(for: task)
                )
            }
        }
    }

    private func reminderDeliveryMethod(for task: StoredDoseTask) -> StoredReminderDeliveryMethod {
        plans.first { $0.id == task.planID }?.reminderDeliveryMethod ?? .notification
    }

    private func performWithDoseFeedback(_ task: StoredDoseTask, action: PendingDoseFeedback.Action, commit: @escaping () -> Void) {
        pendingDoseFeedbackTask?.cancel()
        doseLayoutTransitionTask?.cancel()
        resetDoseTransitionState(animated: false)
        if prefersReducedAppMotion {
            commit()
            return
        }
        let migrationSnapshot = action.movesToHandledSection ? doseMigrationSnapshot(for: task, action: action) : nil
        withAnimation(.easeInOut(duration: 0.16)) {
            pendingDoseFeedback = PendingDoseFeedback(taskID: task.id, action: action)
        }
        pendingDoseFeedbackTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 450_000_000)
            guard !Task.isCancelled else {
                return
            }
            withAnimation(.easeOut(duration: 0.14)) {
                pendingDoseFeedback = nil
            }

            if action.movesToHandledSection {
                doseMigrationSnapshot = migrationSnapshot
                prepareHandledDropTarget()
                try? await Task.sleep(nanoseconds: 170_000_000)
                guard !Task.isCancelled else {
                    return
                }
                stageHandledArrival(for: task)
                try? await Task.sleep(nanoseconds: 180_000_000)
                guard !Task.isCancelled else {
                    return
                }
            }

            commit()

            guard action.movesToHandledSection else {
                pendingDoseFeedbackTask = nil
                return
            }

            try? await Task.sleep(nanoseconds: 240_000_000)
            guard !Task.isCancelled else {
                return
            }
            withAnimation(.snappy(duration: 0.28, extraBounce: 0.02)) {
                showingHandledTasks = true
                isHandledTimelineTemporarilyCollapsed = false
                handledDropTargetPulse = false
                pendingHandledArrivalCount = 0
                _ = closingOpenTaskIDs.remove(task.id)
                doseMigrationSnapshot = nil
            }
            pendingDoseFeedbackTask = nil
        }
    }

    private func prepareHandledDropTarget() {
        guard !prefersReducedAppMotion else {
            return
        }
        withAnimation(.easeInOut(duration: 0.16)) {
            handledDropTargetPulse = true
            pendingHandledArrivalCount = 1
        }
        withAnimation(.snappy(duration: 0.22, extraBounce: 0.01)) {
            showingHandledTasks = false
            isHandledTimelineTemporarilyCollapsed = true
        }
    }

    private func stageHandledArrival(for task: StoredDoseTask) {
        guard !prefersReducedAppMotion else {
            return
        }
        withAnimation(.easeInOut(duration: 0.18)) {
            _ = closingOpenTaskIDs.insert(task.id)
        }
    }

    private func performReopenTransition(_ task: StoredDoseTask, restore: @escaping () -> Void) {
        pendingDoseFeedbackTask?.cancel()
        doseLayoutTransitionTask?.cancel()
        resetDoseTransitionState(animated: false)
        if prefersReducedAppMotion {
            restore()
            return
        }
        let migrationSnapshot = doseMigrationSnapshotForReopen(task)
        withAnimation(.easeInOut(duration: 0.16)) {
            _ = reopeningHandledTaskIDs.insert(task.id)
            doseMigrationSnapshot = migrationSnapshot
        }
        doseLayoutTransitionTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 170_000_000)
            guard !Task.isCancelled else {
                return
            }
            withAnimation(.snappy(duration: 0.22, extraBounce: 0.01)) {
                showingHandledTasks = false
                isHandledTimelineTemporarilyCollapsed = true
                isOpenTimelineTemporarilyCollapsed = true
            }
            try? await Task.sleep(nanoseconds: 210_000_000)
            guard !Task.isCancelled else {
                return
            }
            restore()
            try? await Task.sleep(nanoseconds: 240_000_000)
            guard !Task.isCancelled else {
                return
            }
            withAnimation(.snappy(duration: 0.30, extraBounce: 0.02)) {
                isOpenTimelineTemporarilyCollapsed = false
                isHandledTimelineTemporarilyCollapsed = false
                _ = reopeningHandledTaskIDs.remove(task.id)
                doseMigrationSnapshot = nil
            }
            doseLayoutTransitionTask = nil
        }
    }

    private func resetDoseTransitionState(animated: Bool = true) {
        let updates = {
            pendingDoseFeedback = nil
            isOpenTimelineTemporarilyCollapsed = false
            isHandledTimelineTemporarilyCollapsed = false
            handledDropTargetPulse = false
            pendingHandledArrivalCount = 0
            closingOpenTaskIDs = []
            reopeningHandledTaskIDs = []
            doseMigrationSnapshot = nil
        }
        if animated {
            withAnimation(.easeOut(duration: 0.16), updates)
        } else {
            updates()
        }
    }

    private func latestUndoableLog(for task: StoredDoseTask) -> StoredDoseActionLog? {
        actionLogs.first { $0.taskID == task.id && $0.canUndo }
    }

    private func undoLatestAction(for task: StoredDoseTask) {
        guard let log = latestUndoableLog(for: task) else {
            return
        }
        restore(task, using: log)
    }

    private func undoOrReopen(_ task: StoredDoseTask) {
        if let log = latestUndoableLog(for: task) {
            restore(task, using: log)
        } else {
            reopen(task)
        }
    }

    private func restore(_ task: StoredDoseTask, using log: StoredDoseActionLog) {
        performReopenTransition(task) {
            prepareReopenedTaskHighlightIfNeeded(task)
            updateDoseState(animated: true) {
                task.status = log.previousStatus
                task.dueAt = log.previousDueAt
                task.recordedAt = log.previousRecordedAt
                task.reason = unarchivedReason(log.previousReason)
                log.undoneAt = Date()
                try? modelContext.save()
            }
            clearReopenedTaskHighlightAfterDelay(task)
            Task {
                await rescheduleReminderIfNeeded(for: task)
                await liveActivityService.end(for: task.id)
                scheduleLiveActivityRefresh(after: 0.35)
            }
        }
    }

    private func reopen(_ task: StoredDoseTask) {
        let occurredAt = Date()
        let log = StoredDoseActionLog(
            taskID: task.id,
            action: .correct,
            previousStatus: task.status,
            previousDueAt: task.dueAt,
            previousRecordedAt: task.recordedAt,
            previousReason: task.reason,
            newStatus: .pending,
            occurredAt: occurredAt,
            undoExpiresAt: occurredAt.addingTimeInterval(10 * 60),
            note: "用户将已处理记录撤销为待处理"
        )
        modelContext.insert(log)
        performReopenTransition(task) {
            prepareReopenedTaskHighlightIfNeeded(task)
            updateDoseState(animated: true) {
                task.status = .pending
                task.recordedAt = nil
                task.reason = unarchivedReason("")
                try? modelContext.save()
            }
            clearReopenedTaskHighlightAfterDelay(task)
            Task {
                await rescheduleReminderIfNeeded(for: task)
                await liveActivityService.end(for: task.id)
                scheduleLiveActivityRefresh(after: 0.35)
            }
        }
    }

    private func rescheduleReminderIfNeeded(for task: StoredDoseTask) async {
        guard task.dueAt > Date(), isOpenStatus(task.status), let medication = medication(for: task) else {
            notificationService.cancelReminder(for: task.id)
            return
        }
        await notificationService.scheduleReminder(
            for: task,
            medication: medication,
            deliveryMethod: reminderDeliveryMethod(for: task)
        )
    }

    private func prepareReopenedTaskHighlightIfNeeded(_ task: StoredDoseTask) {
        guard !prefersReducedAppMotion else {
            return
        }
        reopenHighlightTasks[task.id]?.cancel()
        _ = recentlyReopenedTaskIDs.insert(task.id)
    }

    private func clearReopenedTaskHighlightAfterDelay(_ task: StoredDoseTask) {
        guard !prefersReducedAppMotion else {
            return
        }
        reopenHighlightTasks[task.id] = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 900_000_000)
            guard !Task.isCancelled else {
                return
            }
            withAnimation(.easeOut(duration: 0.18)) {
                _ = recentlyReopenedTaskIDs.remove(task.id)
            }
            reopenHighlightTasks[task.id] = nil
        }
    }

    private func archive(_ task: StoredDoseTask) {
        let archiveNote = "用户已归档"
        updateDoseState {
            if !task.reason.contains(archiveNote) {
                task.reason = [task.reason, archiveNote].filter { !$0.isEmpty }.joined(separator: "；")
            }
            try? modelContext.save()
        }
        Task {
            await liveActivityService.end(for: task.id)
            scheduleLiveActivityRefresh(after: 0.35)
        }
    }

    private func unarchive(_ task: StoredDoseTask) {
        updateDoseState {
            task.reason = unarchivedReason(task.reason)
            try? modelContext.save()
        }
        Task {
            await liveActivityService.end(for: task.id)
            scheduleLiveActivityRefresh(after: 0.35)
        }
    }

    private func isArchived(_ task: StoredDoseTask) -> Bool {
        task.reason.contains("用户已归档")
    }

    private func unarchivedReason(_ reason: String) -> String {
        reason
            .split(separator: "；")
            .map(String.init)
            .filter { $0 != "用户已归档" }
            .joined(separator: "；")
    }

    private func updateDoseState(animated: Bool = true, _ updates: () -> Void) {
        guard animated, !prefersReducedAppMotion else {
            updates()
            return
        }
        withAnimation(.snappy(duration: 0.24, extraBounce: 0.02)) {
            updates()
        }
    }

    private func statusText(for task: StoredDoseTask) -> String {
        switch task.status {
        case .taken, .corrected:
            return completionVerb(for: medication(for: task))
        case .skipped:
            return "已忽略"
        case .pending:
            return task.status.displayName
        case .delayed:
            return "30 分钟后"
        }
    }

    private func doseMigrationSnapshot(for task: StoredDoseTask, action: PendingDoseFeedback.Action) -> DoseMigrationSnapshot {
        let medication = medication(for: task)
        let statusText: String
        switch action {
        case .taken:
            statusText = completionVerb(for: medication)
        case .skip:
            statusText = "已忽略"
        case .delay:
            statusText = "30 分钟后"
        }
        return DoseMigrationSnapshot(
            id: task.id,
            medicationName: medication?.displayName ?? "未知药品",
            doseText: "\(task.doseValue.formatted()) \(localizedMedicationUnit(task.doseUnit))",
            timeText: AppFormatters.time.string(from: task.dueAt),
            symbolName: medication?.photoSymbolName ?? "pills.fill",
            statusText: statusText,
            direction: .toHandled
        )
    }

    private func doseMigrationSnapshotForReopen(_ task: StoredDoseTask) -> DoseMigrationSnapshot {
        let medication = medication(for: task)
        return DoseMigrationSnapshot(
            id: task.id,
            medicationName: medication?.displayName ?? "未知药品",
            doseText: "\(task.doseValue.formatted()) \(localizedMedicationUnit(task.doseUnit))",
            timeText: AppFormatters.time.string(from: task.dueAt),
            symbolName: medication?.photoSymbolName ?? "pills.fill",
            statusText: "待处理",
            direction: .toOpen
        )
    }

    private func handledTaskSummary(for task: StoredDoseTask) -> String {
        let name = medication(for: task)?.displayName ?? "用药记录"
        return "\(statusText(for: task)) · \(name)"
    }

    private func completionVerb(for medication: StoredMedication?) -> String {
        guard let medication else {
            return "已完成"
        }
        let combined = "\(medication.displayName) \(medication.form)".lowercased()
        if combined.contains("tear") || combined.contains("drop") || combined.contains("滴") || combined.contains("眼") || combined.contains("喷") || combined.contains("贴") || combined.contains("膏") {
            return "已使用"
        }
        return "已服用"
    }

    private func refreshLiveActivities() async {
        for task in todayTasks {
            if task.status == .pending || task.status == .delayed {
                await liveActivityService.startIfNeeded(for: task, medication: medication(for: task))
            } else {
                await liveActivityService.end(for: task.id)
            }
        }
    }

    private func scheduleLiveActivityRefresh(after delay: TimeInterval = 0.2) {
        liveActivityRefreshTask?.cancel()
        liveActivityRefreshTask = Task { @MainActor in
            if delay > 0 {
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
            guard !Task.isCancelled else {
                return
            }
            await refreshLiveActivities()
        }
    }
}

private struct PendingDoseFeedback: Equatable {
    enum Action: Equatable {
        case taken
        case delay
        case skip

        var movesToHandledSection: Bool {
            switch self {
            case .taken, .skip:
                return true
            case .delay:
                return false
            }
        }
    }

    let taskID: UUID
    let action: Action
}

private struct DoseMigrationSnapshot: Identifiable, Equatable {
    enum Direction: Equatable {
        case toHandled
        case toOpen
    }

    let id: UUID
    let medicationName: String
    let doseText: String
    let timeText: String
    let symbolName: String
    let statusText: String
    let direction: Direction
}

private struct WeatherMedicationHintCard: View {
    let hint: WeatherMedicationHint

    private var tint: Color {
        switch hint.tintName {
        case "orange":
            .orange
        case "teal":
            .teal
        case "indigo":
            .indigo
        case "yellow":
            .yellow
        case "green":
            .green
        default:
            .blue
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: hint.iconName)
                .font(.title3.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 32, height: 32)
                .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 6) {
                Text(hint.title)
                    .font(.headline)
                Text(hint.message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(hint.sourceSummary)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 6)
    }
}

private struct TodayProgressCard: View {
    let completedCount: Int
    let totalCount: Int
    let progressValue: Double
    let isAllTaken: Bool

    private var percentText: String {
        "\(Int((progressValue * 100).rounded()))%"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text(isAllTaken ? "今日用药记录已完成" : "今日完成率")
                    .font(.title2.weight(.semibold))
                Spacer()
                Text(percentText)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(isAllTaken ? .green : .blue)
            }
            ProgressView(value: progressValue)
                .tint(isAllTaken ? .green : .blue)
                .accessibilityLabel("今日完成率")
            Text(totalCount == 0 ? "暂无今日任务" : "\(completedCount) / \(totalCount) 项已按计划完成")
                .font(.headline)
                .foregroundStyle(isAllTaken ? .green : .secondary)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 2)
        .listRowBackground(isAllTaken ? Color.green.opacity(0.16) : nil)
    }
}

private struct TimelineDoseTaskRow: View {
    let task: StoredDoseTask
    let medication: StoredMedication?
    let completionText: String
    let statusText: String
    let isOpen: Bool
    let feedbackAction: PendingDoseFeedback.Action?
    let isClosing: Bool
    let isRecentlyReopened: Bool
    let markTaken: () -> Void
    let delay: () -> Void
    let skip: () -> Void

    private var tint: Color {
        switch task.status {
        case .taken, .corrected:
            .green
        case .skipped:
            .orange
        case .delayed:
            .blue
        case .pending:
            .blue
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(spacing: 6) {
                Text(AppFormatters.time.string(from: task.dueAt))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 48, height: 26)
                    .background(Color(.secondarySystemGroupedBackground), in: Capsule())
                Rectangle()
                    .fill(tint.opacity(0.28))
                    .frame(width: 2)
                    .frame(minHeight: isOpen ? 92 : 70)
            }
            .frame(width: 52)

            VStack(alignment: .leading, spacing: 10) {
                if let medication {
                    NavigationLink {
                        MedicationDetailView(medication: medication)
                    } label: {
                        rowHeader
                    }
                    .buttonStyle(.plain)
                } else {
                    rowHeader
                }

                if isOpen {
                    HStack(spacing: 8) {
                        CompactDoseActionButton(
                            title: completionText,
                            confirmationIconName: "checkmark",
                            tint: .blue,
                            isProminent: true,
                            isConfirming: feedbackAction == .taken,
                            action: markTaken
                        )
                        .id("\(task.id.uuidString)-taken")
                        CompactDoseActionButton(
                            title: "稍后",
                            confirmationIconName: "clock",
                            tint: .gray,
                            isProminent: false,
                            isConfirming: feedbackAction == .delay,
                            action: delay
                        )
                        .id("\(task.id.uuidString)-delay")
                        CompactDoseActionButton(
                            title: "忽略",
                            confirmationIconName: "minus.circle",
                            tint: .orange,
                            isProminent: false,
                            isConfirming: feedbackAction == .skip,
                            action: skip
                        )
                        .id("\(task.id.uuidString)-skip")
                    }
                } else {
                    Text("点开详情，左滑可撤销或归档")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(12)
            .background(rowBackground, in: RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isRecentlyReopened ? Color.blue.opacity(0.34) : Color.clear, lineWidth: 1)
            )
            .opacity(isClosing ? 0.08 : (isRecentlyReopened ? 0.96 : 1))
            .blur(radius: isClosing ? 4 : 0)
            .scaleEffect(isClosing ? 0.96 : 1)
            .offset(y: isClosing ? 14 : (isRecentlyReopened ? -2 : 0))
            .animation(.snappy(duration: 0.26, extraBounce: 0.03), value: isRecentlyReopened)
            .animation(.easeInOut(duration: 0.18), value: isClosing)
        }
        .padding(.vertical, 4)
        .transition(.asymmetric(
            insertion: .opacity.combined(with: .scale(scale: 0.98, anchor: .top)),
            removal: .opacity.combined(with: .move(edge: .bottom))
        ))
    }

    private var rowBackground: Color {
        if isRecentlyReopened {
            return Color.blue.opacity(0.12)
        }
        return Color(.secondarySystemGroupedBackground)
    }

    private var rowHeader: some View {
        HStack(alignment: .center, spacing: 10) {
            MedicationPhotoView(
                photoData: medication?.photoData,
                symbolName: medication?.photoSymbolName ?? "pills.fill",
                tint: tint,
                size: 40
            )
            VStack(alignment: .leading, spacing: 6) {
                Text(medication?.displayName ?? "未知药品")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.86)
                Text("\(task.doseValue.formatted()) \(localizedMedicationUnit(task.doseUnit))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            StatusBadge(text: statusText, color: tint)
        }
    }
}

private struct OpenDoseSummaryRow: View {
    let count: Int
    let latestText: String
    let isReceiving: Bool
    let migrationSnapshot: DoseMigrationSnapshot?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Image(systemName: "tray.and.arrow.up.fill")
                    .font(.title3)
                    .foregroundStyle(.blue)
                    .frame(width: 30, height: 30)
                    .background(Color.blue.opacity(isReceiving ? 0.18 : 0.12), in: Circle())
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(count) 条待处理")
                        .font(.headline)
                    Text(latestText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
            }
            if let migrationSnapshot {
                DoseMigrationPill(snapshot: migrationSnapshot, tint: .blue)
                    .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .leading)))
            }
        }
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.blue.opacity(isReceiving ? 0.08 : 0))
        )
        .scaleEffect(isReceiving ? 1.01 : 1)
        .animation(.easeInOut(duration: 0.18), value: isReceiving)
        .accessibilityElement(children: .combine)
    }
}

private struct HandledDoseSummaryRow: View {
    let count: Int
    let latestText: String
    let isReceiving: Bool
    let migrationSnapshot: DoseMigrationSnapshot?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.green)
                    .frame(width: 30, height: 30)
                    .background(Color.green.opacity(isReceiving ? 0.18 : 0.12), in: Circle())
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(count) 条已处理")
                        .font(.headline)
                    Text(latestText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
            }
            if let migrationSnapshot {
                DoseMigrationPill(snapshot: migrationSnapshot, tint: .green)
                    .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .leading)))
            }
        }
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.green.opacity(isReceiving ? 0.08 : 0))
        )
        .scaleEffect(isReceiving ? 1.01 : 1)
        .animation(.easeInOut(duration: 0.18), value: isReceiving)
        .accessibilityElement(children: .combine)
    }
}

private struct DoseMigrationPill: View {
    let snapshot: DoseMigrationSnapshot
    let tint: Color

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: snapshot.symbolName)
                .font(.caption.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 22, height: 22)
                .background(tint.opacity(0.14), in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(snapshot.medicationName)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
                Text("\(snapshot.timeText) · \(snapshot.doseText)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Text(snapshot.statusText)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(tint)
                .lineLimit(1)
        }
        .frame(height: 40)
        .padding(.horizontal, 8)
        .background(tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(tint.opacity(0.12), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
    }
}

private struct HandledDoseTaskRow: View {
    let task: StoredDoseTask
    let medication: StoredMedication?
    let statusText: String
    let undo: () -> Void
    let archive: () -> Void

    private var tint: Color {
        switch task.status {
        case .taken, .corrected:
            .green
        case .skipped:
            .orange
        case .pending, .delayed:
            .blue
        }
    }

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Text(AppFormatters.time.string(from: task.dueAt))
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 46, height: 26)
                .background(Color(.tertiarySystemGroupedBackground), in: Capsule())
            MedicationPhotoView(
                photoData: medication?.photoData,
                symbolName: medication?.photoSymbolName ?? "pills.fill",
                tint: tint,
                size: 34
            )
            VStack(alignment: .leading, spacing: 5) {
                Text(medication?.displayName ?? "未知药品")
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text("\(task.doseValue.formatted()) \(localizedMedicationUnit(task.doseUnit))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            StatusBadge(text: statusText, color: tint)
        }
        .padding(.vertical, 7)
        .contentShape(Rectangle())
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button {
                undo()
            } label: {
                Label("撤销", systemImage: "arrow.uturn.backward")
            }
            .tint(.orange)

            Button {
                archive()
            } label: {
                Label("归档", systemImage: "archivebox")
            }
            .tint(.gray)
        }
    }
}

private struct CompactDoseActionButton: View {
    let title: String
    let confirmationIconName: String
    let tint: Color
    let isProminent: Bool
    let isConfirming: Bool
    let action: () -> Void

    var body: some View {
        Button {
            action()
        } label: {
            ZStack {
                Text(title)
                    .opacity(isConfirming ? 0 : 1)
                    .blur(radius: isConfirming ? 3 : 0)
                    .scaleEffect(isConfirming ? 0.94 : 1)
                Image(systemName: confirmationIconName)
                    .font(.caption.weight(.bold))
                    .opacity(isConfirming ? 1 : 0)
                    .blur(radius: isConfirming ? 0 : 2)
                    .scaleEffect(isConfirming ? 1 : 0.86)
            }
            .font(.caption.weight(.semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.9)
            .frame(maxWidth: .infinity)
            .frame(height: 36)
            .foregroundStyle(isProminent ? .white : tint)
            .background(background, in: RoundedRectangle(cornerRadius: 8))
            .animation(.easeInOut(duration: 0.16), value: isConfirming)
        }
        .buttonStyle(CompactDoseActionButtonStyle())
        .disabled(isConfirming)
        .accessibilityLabel(title)
    }

    private var background: Color {
        if isProminent {
            return tint
        }
        return tint.opacity(tint == .gray ? 0.14 : 0.16)
    }
}

private struct CompactDoseActionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.78 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

private struct ArchivedDoseTaskRow: View {
    let task: StoredDoseTask
    let medication: StoredMedication?
    let statusText: String
    let restore: () -> Void
    let reopen: () -> Void

    private var tint: Color {
        switch task.status {
        case .taken, .corrected:
            .green
        case .skipped:
            .orange
        case .pending, .delayed:
            .blue
        }
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            MedicationPhotoView(
                photoData: medication?.photoData,
                symbolName: medication?.photoSymbolName ?? "pills.fill",
                tint: tint,
                size: 40
            )
            VStack(alignment: .leading, spacing: 5) {
                Text(medication?.displayName ?? "未知药品")
                    .font(.subheadline.weight(.semibold))
                Text("\(AppFormatters.time.string(from: task.dueAt)) · \(task.doseValue.formatted()) \(localizedMedicationUnit(task.doseUnit))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                StatusBadge(text: statusText, color: tint)
            }
            Spacer()
            Button("恢复") {
                restore()
            }
            .font(.caption.weight(.semibold))
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(.vertical, 6)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button {
                restore()
            } label: {
                Label("恢复", systemImage: "tray.and.arrow.up")
            }
            .tint(.blue)

            Button {
                reopen()
            } label: {
                Label("撤销", systemImage: "arrow.uturn.backward")
            }
            .tint(.orange)
        }
    }
}

private struct DoseTaskRow: View {
    let task: StoredDoseTask
    let medication: StoredMedication?
    let completionText: String
    let markTaken: () -> Void
    let delay: () -> Void
    let skip: () -> Void
    let undo: () -> Void
    let undoLog: StoredDoseActionLog?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let medication {
                NavigationLink {
                    MedicationDetailView(medication: medication)
                } label: {
                    DoseTaskHeader(task: task, medication: medication)
                }
            } else {
                HStack(alignment: .top, spacing: 14) {
                    MedicationPhotoView(photoData: nil, symbolName: "pills.fill", tint: .blue)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("未知药品")
                            .font(.headline)
                        Text("\(task.doseValue.formatted()) \(localizedMedicationUnit(task.doseUnit)) · \(AppFormatters.time.string(from: task.dueAt))")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        StatusBadge(text: task.status.displayName, color: .orange)
                    }
                    Spacer()
                }
            }

            HStack(spacing: 10) {
                Button(action: markTaken) {
                    Label(completionText, systemImage: "checkmark")
                }
                .buttonStyle(.borderedProminent)
                Button(action: delay) {
                    Label("稍后", systemImage: "clock")
                }
                .buttonStyle(.bordered)
                Button(action: skip) {
                    Label("跳过", systemImage: "forward")
                }
                .buttonStyle(.bordered)
                .tint(.orange)
                if undoLog != nil {
                    Button(action: undo) {
                        Label("撤销", systemImage: "arrow.uturn.backward")
                    }
                    .buttonStyle(.bordered)
                }
            }
            .controlSize(.large)
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
    }
}

private struct DoseTaskHeader: View {
    let task: StoredDoseTask
    let medication: StoredMedication

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            MedicationPhotoView(photoData: medication.photoData, symbolName: medication.photoSymbolName, tint: .blue)
            VStack(alignment: .leading, spacing: 6) {
                Text(medication.displayName)
                    .font(.headline)
                Text("\(task.doseValue.formatted()) \(localizedMedicationUnit(task.doseUnit)) · \(AppFormatters.time.string(from: task.dueAt))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                StatusBadge(text: task.status.displayName, color: task.status == .taken ? .green : .orange)
            }
            Spacer()
        }
    }
}

private struct ResolvedDoseTaskRow: View {
    let task: StoredDoseTask
    let medication: StoredMedication?
    let undoLog: StoredDoseActionLog?
    let statusText: String
    let reopen: () -> Void
    let archive: () -> Void
    let showDetail: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            MedicationPhotoView(
                photoData: medication?.photoData,
                symbolName: medication?.photoSymbolName ?? "pills.fill",
                tint: task.status == .taken || task.status == .corrected ? .green : .orange,
                size: 44
            )
            VStack(alignment: .leading, spacing: 4) {
                Text(medication?.displayName ?? "未知药品")
                    .font(.headline)
                Text("\(task.doseValue.formatted()) \(localizedMedicationUnit(task.doseUnit)) · \(AppFormatters.time.string(from: task.dueAt))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            StatusBadge(text: statusText, color: task.status == .taken || task.status == .corrected ? .green : .orange)
        }
        .padding(.vertical, 6)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(action: reopen) {
                Label("撤销", systemImage: "arrow.uturn.backward")
            }
            .tint(.orange)

            Button(action: archive) {
                Label("归档", systemImage: "archivebox")
            }
            .tint(.gray)

            Button(action: showDetail) {
                Label("详情", systemImage: "info.circle")
            }
            .tint(.blue)
        }
    }
}
