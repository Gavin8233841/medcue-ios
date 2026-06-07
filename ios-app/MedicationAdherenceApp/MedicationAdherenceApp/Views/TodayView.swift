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
    @State private var recentlyReopenedTaskIDs: Set<UUID> = []
    @State private var pendingDoseFeedbackTask: Task<Void, Never>?
    @State private var reopenHighlightTasks: [UUID: Task<Void, Never>] = [:]
    @State private var liveActivityRefreshTask: Task<Void, Never>?
    private let liveActivityRefreshTimer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    private var todayTasks: [StoredDoseTask] {
        tasks.filter { Calendar.current.isDateInToday($0.dueAt) }
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
                if visibleOpenTimelineTasks.isEmpty {
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

            if !handledTodayTasks.isEmpty {
                Section {
                    DisclosureGroup(isExpanded: $showingHandledTasks) {
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
                            .transition(.opacity)
                        }
                    } label: {
                        HandledDoseSummaryRow(
                            count: handledTodayTasks.count,
                            latestText: handledTodayTasks.first.map { handledTaskSummary(for: $0) } ?? "已处理记录可在这里找回"
                        )
                    }
                } header: {
                    Text("今日已处理")
                } footer: {
                    Text("误操作可展开后撤销；归档只隐藏今日列表，不删除历史。")
                }
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
            await liveActivityService.end(for: task.id)
            scheduleLiveActivityRefresh(after: 0.35)
        }
    }

    private func delay(_ task: StoredDoseTask) {
        let occurredAt = Date()
        let newDueAt = Calendar.current.date(byAdding: .minute, value: 15, to: Date()) ?? task.dueAt
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
            task.reason = "用户选择稍后提醒"
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
        if prefersReducedAppMotion {
            commit()
            return
        }
        withAnimation(.easeInOut(duration: 0.16)) {
            pendingDoseFeedback = PendingDoseFeedback(taskID: task.id, action: action)
        }
        pendingDoseFeedbackTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 450_000_000)
            guard !Task.isCancelled else {
                return
            }
            commit()
            withAnimation(.easeOut(duration: 0.16)) {
                pendingDoseFeedback = nil
            }
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
        updateDoseState(animated: false) {
            task.status = log.previousStatus
            task.dueAt = log.previousDueAt
            task.recordedAt = log.previousRecordedAt
            task.reason = unarchivedReason(log.previousReason)
            log.undoneAt = Date()
            try? modelContext.save()
        }
        highlightReopenedTaskIfNeeded(task)
        Task {
            await liveActivityService.end(for: task.id)
            scheduleLiveActivityRefresh(after: 0.35)
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
        updateDoseState(animated: false) {
            task.status = .pending
            task.recordedAt = nil
            task.reason = unarchivedReason("")
            try? modelContext.save()
        }
        highlightReopenedTaskIfNeeded(task)
        Task {
            await liveActivityService.end(for: task.id)
            scheduleLiveActivityRefresh(after: 0.35)
        }
    }

    private func highlightReopenedTaskIfNeeded(_ task: StoredDoseTask) {
        guard isOpenStatus(task.status), !prefersReducedAppMotion else {
            return
        }
        reopenHighlightTasks[task.id]?.cancel()
        withAnimation(.snappy(duration: 0.22, extraBounce: 0.02)) {
            _ = recentlyReopenedTaskIDs.insert(task.id)
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
        case .pending, .delayed:
            return task.status.displayName
        }
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
    }

    let taskID: UUID
    let action: Action
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
            Text(totalCount == 0 ? "暂无今日任务" : "\(completedCount) / \(totalCount) 项已处理")
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
            .opacity(isRecentlyReopened ? 0.96 : 1)
            .offset(y: isRecentlyReopened ? -2 : 0)
            .animation(.snappy(duration: 0.26, extraBounce: 0.03), value: isRecentlyReopened)
        }
        .padding(.vertical, 4)
        .transition(.opacity.combined(with: .move(edge: .top)))
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

private struct HandledDoseSummaryRow: View {
    let count: Int
    let latestText: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.title3)
                .foregroundStyle(.green)
                .frame(width: 30, height: 30)
                .background(Color.green.opacity(0.12), in: Circle())
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
        .padding(.vertical, 4)
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
