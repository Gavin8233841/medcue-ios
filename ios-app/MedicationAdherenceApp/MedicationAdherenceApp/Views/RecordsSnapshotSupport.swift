import MedicationAdherenceCore
import SwiftData
import SwiftUI

struct DoseDateSelection: Identifiable, Hashable {
    let id: String
    let date: Date

    init(date: Date) {
        self.date = date
        id = AppFormatters.day.string(from: date)
    }
}

struct RecordsAdherenceDay: Identifiable {
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

struct RecordsRenderState {
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

enum RecordsRenderStateSignature {
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

extension StoredDoseTask {
    var recordDisplayReason: String? {
        DoseRecordDisplayText.reason(from: reason)
    }
}

extension StoredDoseActionLog {
    var recordDisplayNote: String? {
        DoseRecordDisplayText.reason(from: note)
    }
}

enum DoseRecordDisplayText {
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

struct RecordsViewSnapshot {
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

struct HistoryTaskGroup: Identifiable {
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
