import Foundation

struct TodayDoseProjectionTransition: Equatable {
    var pendingDoseFeedback: PendingDoseFeedback?
    var closingOpenDoseKeys: Set<String> = []
    var reopeningHandledDoseKeys: Set<String> = []
    var recentlyReopenedDoseKeys: Set<String> = []
    var isHandledTimelineTemporarilyCollapsed = false
    var handledDropTargetPulse = false
    var pendingHandledArrivalCount = 0
}

struct TodayDoseProjectionInput {
    let tasks: [StoredDoseTask]
    let medications: [StoredMedication]
    let now: Date
    var calendar: Calendar = .current
    var transition = TodayDoseProjectionTransition()
}

struct TodayRenderSnapshot {
    let eligibleTodayTasks: [StoredDoseTask]
    let displayTodayTasks: [StoredDoseTask]
    let visibleOpenTimelineTasks: [StoredDoseTask]
    let handledTodayTasks: [StoredDoseTask]
    let archivedTodayTasks: [StoredDoseTask]
    let nextReminderTask: StoredDoseTask?
    let overdueOpenTaskCount: Int
    let emptyOpenTimelineMessage: String
    let shouldShowSkippedMedicationSummary: Bool
    let shouldShowHandledSection: Bool
    let displayedOpenCount: Int
    let displayedHandledCount: Int
    let handledSummaryText: String
    let skippedMedicationSummary: String
    let completionRateSnapshot: CompletionRateSnapshot

    func completionRateSnapshot(
        replacingDoseKey targetDoseKey: String,
        with status: StoredDoseStatus
    ) -> CompletionRateSnapshot {
        let completedCount = displayTodayTasks.reduce(into: 0) { count, task in
            let effectiveStatus = DoseLogicalGroup.key(for: task) == targetDoseKey
                ? status
                : task.status
            if effectiveStatus == .taken || effectiveStatus == .corrected {
                count += 1
            }
        }
        return CompletionRateSnapshot(
            completedCount: completedCount,
            totalCount: displayTodayTasks.count
        )
    }
}

@MainActor
final class TodayDoseProjectionStore {
    private let cache = RevisionSnapshotCache<TodayRenderSnapshot>()

    func projection(for input: TodayDoseProjectionInput) -> TodayRenderSnapshot {
        cache.value(for: revision(for: input)) {
            makeProjection(for: input)
        }
    }

    private func makeProjection(for input: TodayDoseProjectionInput) -> TodayRenderSnapshot {
        let medicationsByID = Dictionary(
            uniqueKeysWithValues: input.medications.map { ($0.id, $0) }
        )
        let transition = input.transition
        let todayTasks = input.tasks.filter { task in
            guard task.isAdherenceMeasurable,
                  medicationsByID[task.medicationID]?.lifecycleStatus == .active
            else {
                return false
            }
            if input.calendar.isDate(task.dueAt, inSameDayAs: input.now) {
                return true
            }
            let doseKey = DoseLogicalGroup.key(for: task)
            if transition.closingOpenDoseKeys.contains(doseKey)
                || transition.pendingDoseFeedback?.doseKey == doseKey {
                return true
            }
            return task.status == .delayed
                && task.recordedAt.map {
                    input.calendar.isDate($0, inSameDayAs: input.now)
                } == true
                && Self.isOpenStatus(task.status)
        }
        let displayTasks = deduplicatedTasks(
            todayTasks,
            transition: transition
        )
        let visibleOpenTasks = displayTasks
            .filter { !Self.isArchived($0) && Self.isOpenStatus($0.status) }
            .sorted(by: Self.dueAtOrder)
        let visibleOpenKeys = Set(visibleOpenTasks.map(DoseLogicalGroup.key(for:)))
        var transitionOpenDoseKeys = transition.closingOpenDoseKeys
        if let pendingDoseFeedback = transition.pendingDoseFeedback {
            transitionOpenDoseKeys.insert(pendingDoseFeedback.doseKey)
        }
        let transitionOpenTasks = displayTasks.filter { task in
            let doseKey = DoseLogicalGroup.key(for: task)
            return !Self.isArchived(task)
                && transitionOpenDoseKeys.contains(doseKey)
                && !visibleOpenKeys.contains(doseKey)
        }
        let displayOpenTasks = (visibleOpenTasks + transitionOpenTasks)
            .sorted(by: Self.dueAtOrder)
        let handledTasks = displayTasks
            .filter { !Self.isArchived($0) && !Self.isOpenStatus($0.status) }
            .sorted(by: Self.handledOrder)
        let archivedTasks = displayTasks
            .filter(Self.isArchived)
            .sorted(by: Self.dueAtOrder)
        let skippedTasks = displayTasks
            .filter { !Self.isArchived($0) && $0.status == .skipped }
            .sorted(by: Self.dueAtOrder)
        let openTasks = displayTasks.filter { Self.isOpenStatus($0.status) }
        let nextReminderTask = openTasks
            .filter { $0.dueAt >= input.now }
            .sorted(by: Self.dueAtOrder)
            .first
        let overdueOpenTaskCount = openTasks.filter { $0.dueAt < input.now }.count
        let completedCount = displayTasks.filter {
            $0.status == .taken || $0.status == .corrected
        }.count
        let completionSnapshot = CompletionRateSnapshot(
            completedCount: completedCount,
            totalCount: displayTasks.count
        )
        let isAfterLastReminderToday = displayTasks
            .map(\.dueAt)
            .max()
            .map { input.now >= $0 } ?? false
        let emptyOpenMessage: String
        if todayTasks.isEmpty {
            emptyOpenMessage = "今天还没有用药任务。"
        } else if !skippedTasks.isEmpty && !completionSnapshot.isComplete {
            emptyOpenMessage = "待处理已清空，今日有 \(skippedTasks.count) 项已忽略。"
        } else if completionSnapshot.isComplete {
            emptyOpenMessage = "今日用药已完成。"
        } else {
            emptyOpenMessage = "当前没有待处理用药。"
        }

        let shouldShowSkippedMedicationSummary = !skippedTasks.isEmpty
            && (isAfterLastReminderToday || visibleOpenTasks.isEmpty)
        let shouldShowHandledSection = !handledTasks.isEmpty
            || transition.isHandledTimelineTemporarilyCollapsed
            || transition.handledDropTargetPulse
            || !transition.reopeningHandledDoseKeys.isEmpty
        let displayedOpenCount: Int
        if transition.reopeningHandledDoseKeys.isEmpty {
            displayedOpenCount = displayOpenTasks.count
        } else {
            let visibleKeys = Set(displayOpenTasks.map(DoseLogicalGroup.key(for:)))
            let reopeningCount = transition.reopeningHandledDoseKeys
                .filter { !visibleKeys.contains($0) }
                .count
            displayedOpenCount = displayOpenTasks.count + reopeningCount
        }
        let displayedHandledCount: Int
        if !transition.closingOpenDoseKeys.isEmpty {
            let handledKeys = Set(handledTasks.map(DoseLogicalGroup.key(for:)))
            let incomingCount = transition.closingOpenDoseKeys
                .filter { !handledKeys.contains($0) }
                .count
            displayedHandledCount = handledTasks.count + incomingCount
        } else if transition.reopeningHandledDoseKeys.isEmpty {
            let handledKeys = Set(handledTasks.map(DoseLogicalGroup.key(for:)))
            let pendingTaskIsAlreadyHandled = transition.pendingDoseFeedback.map { feedback in
                feedback.action.movesToHandledSection && handledKeys.contains(feedback.doseKey)
            } ?? false
            displayedHandledCount = handledTasks.count
                + (pendingTaskIsAlreadyHandled ? 0 : transition.pendingHandledArrivalCount)
        } else {
            let handledKeys = Set(handledTasks.map(DoseLogicalGroup.key(for:)))
            let leavingVisibleCount = transition.reopeningHandledDoseKeys
                .filter(handledKeys.contains)
                .count
            displayedHandledCount = max(0, handledTasks.count - leavingVisibleCount)
        }
        let handledSummaryText: String
        if transition.handledDropTargetPulse {
            handledSummaryText = "正在收起刚刚处理的记录"
        } else if !transition.reopeningHandledDoseKeys.isEmpty {
            handledSummaryText = "正在恢复到待处理记录"
        } else {
            handledSummaryText = handledTasks.first.map {
                Self.handledTaskSummary($0, medicationsByID: medicationsByID)
            } ?? "已处理记录可在这里找回"
        }
        let skippedMedicationSummary = skippedTasks
            .map {
                medicationsByID[$0.medicationID].map(userFacingMedicationName(for:))
                    ?? "未知药品"
            }
            .joined(separator: "、")

        return TodayRenderSnapshot(
            eligibleTodayTasks: todayTasks,
            displayTodayTasks: displayTasks,
            visibleOpenTimelineTasks: displayOpenTasks,
            handledTodayTasks: handledTasks,
            archivedTodayTasks: archivedTasks,
            nextReminderTask: nextReminderTask,
            overdueOpenTaskCount: overdueOpenTaskCount,
            emptyOpenTimelineMessage: emptyOpenMessage,
            shouldShowSkippedMedicationSummary: shouldShowSkippedMedicationSummary,
            shouldShowHandledSection: shouldShowHandledSection,
            displayedOpenCount: displayedOpenCount,
            displayedHandledCount: displayedHandledCount,
            handledSummaryText: handledSummaryText,
            skippedMedicationSummary: skippedMedicationSummary,
            completionRateSnapshot: completionSnapshot
        )
    }

    private func deduplicatedTasks(
        _ tasks: [StoredDoseTask],
        transition: TodayDoseProjectionTransition
    ) -> [StoredDoseTask] {
        var tasksByLogicalDose: [String: StoredDoseTask] = [:]
        for task in tasks {
            let key = DoseLogicalGroup.key(for: task)
            if let current = tasksByLogicalDose[key] {
                tasksByLogicalDose[key] = preferredDisplayTask(
                    current,
                    task,
                    transition: transition
                )
            } else {
                tasksByLogicalDose[key] = task
            }
        }
        return tasksByLogicalDose.values.sorted(by: Self.dueAtOrder)
    }

    private func preferredDisplayTask(
        _ lhs: StoredDoseTask,
        _ rhs: StoredDoseTask,
        transition: TodayDoseProjectionTransition
    ) -> StoredDoseTask {
        let lhsScore = displayPriorityScore(for: lhs, transition: transition)
        let rhsScore = displayPriorityScore(for: rhs, transition: transition)
        if lhsScore != rhsScore {
            return lhsScore > rhsScore ? lhs : rhs
        }
        let lhsReferenceDate = lhs.effectiveAdherenceDate
        let rhsReferenceDate = rhs.effectiveAdherenceDate
        if lhsReferenceDate != rhsReferenceDate {
            return lhsReferenceDate > rhsReferenceDate ? lhs : rhs
        }
        return lhs.id.uuidString < rhs.id.uuidString ? lhs : rhs
    }

    private func displayPriorityScore(
        for task: StoredDoseTask,
        transition: TodayDoseProjectionTransition
    ) -> Int {
        let doseKey = DoseLogicalGroup.key(for: task)
        var score = 0
        if transition.recentlyReopenedDoseKeys.contains(doseKey) {
            score += 1_000
        }
        if transition.pendingDoseFeedback?.doseKey == doseKey {
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

    private func revision(for input: TodayDoseProjectionInput) -> String {
        let transition = input.transition
        let pendingFeedbackRevision: String
        if let pendingDoseFeedback = transition.pendingDoseFeedback {
            let action: String
            switch pendingDoseFeedback.action {
            case .taken:
                action = "taken"
            case .delay:
                action = "delay"
            case .skip:
                action = "skip"
            }
            pendingFeedbackRevision = "\(pendingDoseFeedback.doseKey):\(action)"
        } else {
            pendingFeedbackRevision = "none"
        }
        return [
            String(stableTaskSignature(input.tasks)),
            String(stableMedicationSignature(input.medications)),
            transition.closingOpenDoseKeys.sorted().joined(separator: ","),
            transition.reopeningHandledDoseKeys.sorted().joined(separator: ","),
            transition.recentlyReopenedDoseKeys.sorted().joined(separator: ","),
            pendingFeedbackRevision,
            String(transition.isHandledTimelineTemporarilyCollapsed),
            String(transition.handledDropTargetPulse),
            String(transition.pendingHandledArrivalCount),
            input.calendar.identifier.debugDescription,
            input.calendar.timeZone.identifier,
            timeStateRevision(for: input)
        ].joined(separator: "|")
    }

    private func timeStateRevision(for input: TodayDoseProjectionInput) -> String {
        let startOfDay = input.calendar.startOfDay(for: input.now)
        let passedDueCount = input.tasks.reduce(into: 0) { count, task in
            if task.dueAt < input.now {
                count += 1
            }
        }
        return "\(startOfDay.timeIntervalSinceReferenceDate):\(passedDueCount)"
    }

    private static func isOpenStatus(_ status: StoredDoseStatus) -> Bool {
        status == .pending || status == .delayed
    }

    private static func isArchived(_ task: StoredDoseTask) -> Bool {
        task.reason.contains("用户已归档")
    }

    private static func dueAtOrder(_ lhs: StoredDoseTask, _ rhs: StoredDoseTask) -> Bool {
        if lhs.dueAt == rhs.dueAt {
            return lhs.id.uuidString < rhs.id.uuidString
        }
        return lhs.dueAt < rhs.dueAt
    }

    private static func handledOrder(_ lhs: StoredDoseTask, _ rhs: StoredDoseTask) -> Bool {
        let lhsRecordedAt = lhs.effectiveAdherenceDate
        let rhsRecordedAt = rhs.effectiveAdherenceDate
        if lhsRecordedAt == rhsRecordedAt {
            return lhs.id.uuidString < rhs.id.uuidString
        }
        return lhsRecordedAt > rhsRecordedAt
    }

    private static func handledTaskSummary(
        _ task: StoredDoseTask,
        medicationsByID: [UUID: StoredMedication]
    ) -> String {
        let medication = medicationsByID[task.medicationID]
        let name = medication.map(userFacingMedicationName(for:)) ?? "用药记录"
        return "\(statusText(for: task, medication: medication)) · \(name)"
    }

    private static func statusText(
        for task: StoredDoseTask,
        medication: StoredMedication?
    ) -> String {
        switch task.status {
        case .taken, .corrected:
            return completionVerb(for: medication)
        case .skipped:
            return "已忽略"
        case .pending:
            return task.status.displayName
        case .delayed:
            return "\(DoseDelayPolicy.delayMinutes) 分钟后"
        }
    }

    private static func completionVerb(for medication: StoredMedication?) -> String {
        guard let medication else {
            return "已完成"
        }
        let combined = "\(medication.displayName) \(medication.form)".lowercased()
        if combined.contains("tear")
            || combined.contains("drop")
            || combined.contains("滴")
            || combined.contains("眼")
            || combined.contains("喷")
            || combined.contains("贴")
            || combined.contains("膏") {
            return "已使用"
        }
        return "已服用"
    }
}
