import Foundation
import MedicationAdherenceCore
import SwiftData
import UserNotifications
#if canImport(AlarmKit)
import AlarmKit
import SwiftUI
#endif

enum MedicationReminderSchedulingResult: Sendable, Equatable {
    case scheduled
    case unavailable(message: String)

    var failureMessage: String? {
        guard case let .unavailable(message) = self else { return nil }
        return message
    }
}

struct MedicationReminderSyncWarningState: Equatable {
    var messagesByTaskID: [String: String] = [:]
    var globalMessage: String?

    mutating func replace(
        affectedTaskIDs: Set<UUID>,
        results: [UUID: MedicationReminderSchedulingResult]
    ) {
        for taskID in affectedTaskIDs {
            messagesByTaskID.removeValue(forKey: taskID.uuidString)
        }
        for (taskID, result) in results {
            if let message = result.failureMessage {
                messagesByTaskID[taskID.uuidString] = message
            }
        }
    }

    var displayMessage: String? {
        let distinctMessages = Array(Set(messagesByTaskID.values)).sorted()
        let parts = ([globalMessage].compactMap { $0 } + Array(distinctMessages.prefix(3)))
        guard !parts.isEmpty else { return nil }
        let remainingKinds = distinctMessages.count - min(3, distinctMessages.count)
        let suffix = remainingKinds > 0 ? "；另有 \(remainingKinds) 类提醒问题。" : ""
        return parts.joined(separator: "；") + suffix
    }
}

enum MedicationReminderReconciliationOutcome: Sendable, Equatable {
    case committed
    case readFailed(MedicationReminderReconciliationReadStage)
    case scheduleFailed
    case saveFailed
    case systemFailed
}

@MainActor
struct MedicationReminderReconciliationSystemEffects {
    var cancelReminders: @MainActor ([UUID]) -> Void
    var scheduleReminderSnapshot: @MainActor (MedicationReminderPostCommitSnapshot, Bool) async -> Void
    var refreshPendingReminderCount: @MainActor () async -> Void
}

@MainActor
struct MedicationNotificationRequestScheduler {
    let authorizationFailureMessage: @MainActor () async -> String?
    let addRequest: @MainActor (UNNotificationRequest) async throws -> Void

    func schedule(_ request: UNNotificationRequest) async -> MedicationReminderSchedulingResult {
        if let message = await authorizationFailureMessage() {
            return .unavailable(message: message)
        }
        do {
            try await addRequest(request)
            return .scheduled
        } catch {
            return .unavailable(message: "提醒未安排，请稍后重试。")
        }
    }
}

private struct MedicationReminderRequestExpired: Error {}

struct MedicationReminderRequestExecutionOutcome: Equatable {
    let baseScheduled: Bool
    let escalationScheduled: Bool
    let failedKinds: [MedicationReminderRequestKind]
    let usedEscalationNotificationFallback: Bool

    func schedulingResult(
        wantsAlarm: Bool,
        wantsEscalationAlarm: Bool,
        plannedKinds: [MedicationReminderRequestKind]
    ) -> MedicationReminderSchedulingResult {
        let plannedBase = plannedKinds.contains(.baseNotification) || plannedKinds.contains(.baseAlarm)
        guard !plannedBase || baseScheduled else {
            return .unavailable(message: "基础提醒未能安排，请稍后重试。")
        }
        var degradations: [String] = []
        if plannedBase && wantsAlarm && !plannedKinds.contains(.baseAlarm) {
            degradations.append("所选 iPhone 闹钟未安排，已改用普通通知；请检查闹钟权限")
        } else if failedKinds.contains(.baseAlarm) {
            degradations.append("所选 iPhone 闹钟未安排，已改用普通通知")
        }
        if failedKinds.contains(.baseNotification) {
            degradations.append("普通通知未安排，iPhone 闹钟仍已安排")
        }
        if !escalationScheduled {
            degradations.append(plannedBase ? "基础提醒已安排，升级提醒未能安排" : "升级提醒未能安排")
        } else if wantsEscalationAlarm && plannedKinds.contains(.escalationNotification) {
            degradations.append("升级闹钟未安排，已改用普通通知；请检查闹钟权限")
        } else if usedEscalationNotificationFallback {
            degradations.append("升级闹钟未安排，已改用普通通知")
        } else if wantsEscalationAlarm && !plannedKinds.contains(.escalationAlarm) {
            degradations.append("升级提醒因本机排程预算未安排，基础提醒仍已安排")
        }
        if !degradations.isEmpty {
            return .unavailable(message: "\(degradations.joined(separator: "；"))；下次启动 App 后会重试。")
        }
        return .scheduled
    }
}

enum MedicationReminderSystemIdentifiers {
    static func baseNotification(for taskID: UUID) -> String {
        "dose.\(taskID.uuidString)"
    }

    static func escalationNotification(for taskID: UUID) -> String {
        "dose.escalation.\(taskID.uuidString)"
    }

    static func escalationAlarm(for taskID: UUID) -> UUID {
        var rawUUID = taskID.uuid
        rawUUID.0 ^= 0x80
        return UUID(uuid: rawUUID)
    }
}

enum MedicationReminderCancellationReadback {
    static func blockedTaskIDs(
        among taskIDs: Set<UUID>,
        remainingNotificationIDs: Set<String>,
        remainingAlarmIDs: Set<UUID>
    ) -> Set<UUID> {
        Set(taskIDs.filter {
            remainingNotificationIDs.contains(MedicationReminderSystemIdentifiers.baseNotification(for: $0))
                || remainingNotificationIDs.contains(MedicationReminderSystemIdentifiers.escalationNotification(for: $0))
                || remainingAlarmIDs.contains($0)
                || remainingAlarmIDs.contains(MedicationReminderSystemIdentifiers.escalationAlarm(for: $0))
        })
    }

    static func hasUnattributedFailure(
        among taskIDs: Set<UUID>,
        remainingNotificationIDs: Set<String>,
        remainingAlarmIDs: Set<UUID>
    ) -> Bool {
        let knownNotificationIDs = Set(taskIDs.flatMap {
            [MedicationReminderSystemIdentifiers.baseNotification(for: $0),
             MedicationReminderSystemIdentifiers.escalationNotification(for: $0)]
        })
        let knownAlarmIDs = Set(taskIDs.flatMap {
            [$0, MedicationReminderSystemIdentifiers.escalationAlarm(for: $0)]
        })
        return !remainingNotificationIDs.subtracting(knownNotificationIDs).isEmpty
            || !remainingAlarmIDs.subtracting(knownAlarmIDs).isEmpty
    }
}

struct MedicationReminderCancellationTargets {
    let notificationIDs: Set<String>
    let deliveredNotificationIDsToRemove: Set<String>
    let alarmIDs: Set<UUID>

    init(
        taskIDs: Set<UUID>,
        pendingNotificationIDs: Set<String>,
        deliveredNotificationIDs: Set<String> = [],
        existingAlarmIDs: Set<UUID>,
        pruneAllReminders: Bool,
        preserveBaseForTaskIDs: Set<UUID>,
        preservedDeliveredNotificationIDs: Set<String> = []
    ) {
        var notifications = Set(taskIDs.flatMap {
            [MedicationReminderSystemIdentifiers.baseNotification(for: $0),
             MedicationReminderSystemIdentifiers.escalationNotification(for: $0)]
        })
        var alarms = Set(taskIDs.flatMap {
            [$0, MedicationReminderSystemIdentifiers.escalationAlarm(for: $0)]
        })
        var deliveredToRemove = notifications
        if pruneAllReminders {
            notifications.formUnion(pendingNotificationIDs.filter { $0.hasPrefix("dose.") })
            deliveredToRemove.formUnion(deliveredNotificationIDs.filter { $0.hasPrefix("dose.") })
            // AlarmKit is currently used only for medication reminders in this app.
            alarms.formUnion(existingAlarmIDs)
        }
        notifications.subtract(preserveBaseForTaskIDs.map {
            MedicationReminderSystemIdentifiers.baseNotification(for: $0)
        })
        alarms.subtract(preserveBaseForTaskIDs)
        deliveredToRemove.subtract(preservedDeliveredNotificationIDs)
        notificationIDs = notifications
        deliveredNotificationIDsToRemove = deliveredToRemove
        alarmIDs = alarms
    }
}

enum MedicationReminderRequestTiming {
    static func missedBaseWhileQueued(
        baseDueAt: Date,
        escalationDueAt: Date,
        capturedAt: Date,
        schedulingNow: Date,
        wantsEscalation: Bool
    ) -> Bool {
        baseDueAt > capturedAt && baseDueAt <= schedulingNow
            && wantsEscalation && escalationDueAt > schedulingNow
    }

    static func missedWindow(
        baseDueAt: Date,
        escalationDueAt: Date,
        initialNow: Date,
        schedulingNow: Date,
        wantsEscalation: Bool
    ) -> Bool {
        let wasFuture = baseDueAt > initialNow || (wantsEscalation && escalationDueAt > initialNow)
        let stillFuture = baseDueAt > schedulingNow || (wantsEscalation && escalationDueAt > schedulingNow)
        return wasFuture && !stillFuture
    }

    static func reportExpiredBase(
        _ result: MedicationReminderSchedulingResult,
        expired: Bool
    ) -> MedicationReminderSchedulingResult {
        guard expired else { return result }
        switch result {
        case .scheduled:
            return .unavailable(message: "基础提醒时间已过，已安排升级提醒；请查看用药记录。")
        case let .unavailable(message):
            return .unavailable(message: "基础提醒时间已过；\(message)")
        }
    }

    static func reportMissedBase(
        outcome: MedicationReminderRequestExecutionOutcome,
        plannedKinds: [MedicationReminderRequestKind],
        wantsEscalation: Bool,
        wantsEscalationAlarm: Bool
    ) -> MedicationReminderSchedulingResult {
        guard wantsEscalation else {
            return .unavailable(message: "基础提醒时间已过，未能安排；请查看用药记录。")
        }
        let escalationKinds = plannedKinds.filter {
            $0 == .escalationAlarm || $0 == .escalationNotification
        }
        let escalationOutcome = MedicationReminderRequestExecutionOutcome(
            baseScheduled: false,
            escalationScheduled: outcome.escalationScheduled,
            failedKinds: outcome.failedKinds.filter {
                $0 == .escalationAlarm || $0 == .escalationNotification
            },
            usedEscalationNotificationFallback: outcome.usedEscalationNotificationFallback
        )
        return reportExpiredBase(
            escalationOutcome.schedulingResult(
                wantsAlarm: false,
                wantsEscalationAlarm: wantsEscalationAlarm,
                plannedKinds: escalationKinds
            ),
            expired: true
        )
    }
}

@MainActor
struct MedicationReminderRequestExecutor {
    let addBaseNotification: @MainActor () async -> Bool
    let addBaseAlarm: @MainActor () async -> Bool
    let addEscalationNotification: @MainActor () async -> Bool
    let addEscalationAlarm: @MainActor () async -> Bool

    func execute(_ kinds: [MedicationReminderRequestKind]) async -> MedicationReminderRequestExecutionOutcome {
        var failedKinds: [MedicationReminderRequestKind] = []
        var baseScheduled = false
        if kinds.contains(.baseNotification) {
            let scheduled = await addBaseNotification()
            if !scheduled { failedKinds.append(.baseNotification) }
            baseScheduled = scheduled
        }
        if kinds.contains(.baseAlarm) {
            let alarmScheduled = await addBaseAlarm()
            if !alarmScheduled { failedKinds.append(.baseAlarm) }
            baseScheduled = baseScheduled || alarmScheduled
        }
        if !baseScheduled && kinds.contains(.baseAlarm) && !kinds.contains(.baseNotification) {
            // The failed base alarm left its reserved request slot free.
            let fallbackScheduled = await addBaseNotification()
            if !fallbackScheduled { failedKinds.append(.baseNotification) }
            baseScheduled = fallbackScheduled
        }
        let plannedBase = kinds.contains(.baseNotification) || kinds.contains(.baseAlarm)
        guard !plannedBase || baseScheduled else {
            return MedicationReminderRequestExecutionOutcome(
                baseScheduled: false,
                escalationScheduled: false,
                failedKinds: failedKinds,
                usedEscalationNotificationFallback: false
            )
        }

        if kinds.contains(.escalationAlarm) {
            if await addEscalationAlarm() {
                return MedicationReminderRequestExecutionOutcome(
                    baseScheduled: true,
                    escalationScheduled: true,
                    failedKinds: failedKinds,
                    usedEscalationNotificationFallback: false
                )
            }
            failedKinds.append(.escalationAlarm)
            let fallbackScheduled = await addEscalationNotification()
            if !fallbackScheduled { failedKinds.append(.escalationNotification) }
            return MedicationReminderRequestExecutionOutcome(
                baseScheduled: true,
                escalationScheduled: fallbackScheduled,
                failedKinds: failedKinds,
                usedEscalationNotificationFallback: fallbackScheduled
            )
        }
        if kinds.contains(.escalationNotification) {
            let scheduled = await addEscalationNotification()
            if !scheduled { failedKinds.append(.escalationNotification) }
            return MedicationReminderRequestExecutionOutcome(
                baseScheduled: true,
                escalationScheduled: scheduled,
                failedKinds: failedKinds,
                usedEscalationNotificationFallback: false
            )
        }
        return MedicationReminderRequestExecutionOutcome(
            baseScheduled: true,
            escalationScheduled: true,
            failedKinds: failedKinds,
            usedEscalationNotificationFallback: false
        )
    }
}

@MainActor
final class NotificationService: ObservableObject {
    static let reminderNotificationUnavailableMessageKey = "reminderNotificationUnavailableMessage"
    static let reminderSystemSyncMessageKey = "reminderSystemSyncMessage"
    private static let reminderSystemSyncMessagesByTaskKey = "reminderSystemSyncMessagesByTask"
    private static let reminderSystemSyncGlobalMessageKey = "reminderSystemSyncGlobalMessage"

    @Published private(set) var authorizationMessage = "尚未请求通知权限"
    @Published private(set) var pendingReminderCount = 0
    @Published private(set) var lastReminderReconciliationOutcome: MedicationReminderReconciliationOutcome?

    var notificationIdentifierPrefix: String { "dose." }
    private var escalationAlarmIdentifierPrefix: String { "dose.escalation." }
    private let notificationPolicy = MedicationNotificationPolicy.default
    private let reminderPolicy = DoseReminderPolicy.competitionDemo
    private let defaults: UserDefaults
    private let injectedReminderTaskCoordinator: MedicationReminderTaskCoordinator?
    private let reconciliationSaveOperation: (ModelContext) throws -> Void
    private let reconciliationSystemEffects: MedicationReminderReconciliationSystemEffects?
    private let reminderOperationQueue: ReminderOperationQueue
    private var lastSystemOperationFailed = false

    init(
        reminderTaskCoordinator: MedicationReminderTaskCoordinator? = nil,
        reconciliationSaveOperation: @escaping (ModelContext) throws -> Void = { try $0.save() },
        reconciliationSystemEffects: MedicationReminderReconciliationSystemEffects? = nil,
        reminderOperationQueue: ReminderOperationQueue = MedicationReminderSystemOperationQueue.shared,
        defaults: UserDefaults = .standard
    ) {
        injectedReminderTaskCoordinator = reminderTaskCoordinator
        self.reconciliationSaveOperation = reconciliationSaveOperation
        self.reconciliationSystemEffects = reconciliationSystemEffects
        self.reminderOperationQueue = reminderOperationQueue
        self.defaults = defaults
    }

    @discardableResult
    func requestAuthorization() async -> Bool {
        do {
            let granted = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            authorizationMessage = message(for: settings.authorizationStatus)
            updateNotificationUnavailableMessage(granted ? notificationUnavailableMessage(for: settings) : "普通提醒不可用：通知权限未开启，请在系统设置中允许通知。")
            return granted && notificationUnavailableMessage(for: settings) == nil
        } catch {
            authorizationMessage = "通知权限暂时无法开启，请稍后重试或前往系统设置检查。"
            updateNotificationUnavailableMessage("普通提醒不可用：暂时无法请求通知权限，请稍后重试或前往系统设置检查。")
            return false
        }
    }

    func refreshAuthorizationStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        authorizationMessage = message(for: settings.authorizationStatus)
        updateNotificationUnavailableMessage(notificationUnavailableMessage(for: settings))
    }

    @discardableResult
    func hasUsableNotificationAuthorization() async -> Bool {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        authorizationMessage = message(for: settings.authorizationStatus)
        if let unavailableMessage = notificationUnavailableMessage(for: settings) {
            updateNotificationUnavailableMessage(unavailableMessage)
            return false
        }

        updateNotificationUnavailableMessage(nil)
        return true
    }

    func refreshPendingReminderCount() async {
        let requests = await UNUserNotificationCenter.current().pendingNotificationRequests()
        pendingReminderCount = requests.filter { isBaseNotificationIdentifier($0.identifier) }.count
    }

    @discardableResult
    func reconcileAndScheduleReminders(in modelContext: ModelContext) async -> MedicationReminderReconciliationOutcome {
        let batches: [MedicationReminderScheduleBatch]
        let reminderTaskCoordinator = injectedReminderTaskCoordinator ?? MedicationReminderTaskCoordinator()
        switch reminderTaskCoordinator.reconcileAllPlans(in: modelContext) {
        case let .reconciled(reconciledBatches):
            batches = reconciledBatches
        case let .readFailed(stage):
            let outcome = MedicationReminderReconciliationOutcome.readFailed(stage)
            lastReminderReconciliationOutcome = outcome
            return outcome
        case .scheduleFailed:
            lastReminderReconciliationOutcome = .scheduleFailed
            return .scheduleFailed
        }
        do {
            try reconciliationSaveOperation(modelContext)
        } catch {
            modelContext.rollback()
            AppPersistenceCommitter.reportFailure(operation: "reminder-reconciliation")
            lastReminderReconciliationOutcome = .saveFailed
            return .saveFailed
        }

        let snapshot = MedicationReminderPostCommitSnapshot(batches: batches)
        let committedSnapshot: MedicationReminderPostCommitSnapshot?
        if reconciliationSystemEffects == nil {
            do {
                committedSnapshot = try MedicationReminderCommittedSnapshotReader.read(in: modelContext)
            } catch {
                var warnings = loadReminderSyncWarningState()
                warnings.globalMessage = "全局提醒信息暂时无法读取；现有提醒保持不变，请稍后重试。"
                persistReminderSyncWarningState(warnings)
                lastReminderReconciliationOutcome = .systemFailed
                return .systemFailed
            }
        } else {
            committedSnapshot = nil
        }
        lastReminderReconciliationOutcome = nil
        let operation = reminderOperationQueue.enqueue { @MainActor [self, snapshot, committedSnapshot] in
            if let reconciliationSystemEffects {
                reconciliationSystemEffects.cancelReminders(snapshot.cancelledTaskIDs)
                await reconciliationSystemEffects.scheduleReminderSnapshot(snapshot, true)
                await reconciliationSystemEffects.refreshPendingReminderCount()
            } else {
                _ = await scheduleReminderSnapshotImmediately(
                    committedSnapshot ?? snapshot,
                    pruneExistingPrefixRequests: true
                )
                await refreshPendingReminderCount()
                if lastSystemOperationFailed {
                    lastReminderReconciliationOutcome = .systemFailed
                    return
                }
            }
        }
        await operation.value
        if lastReminderReconciliationOutcome == .systemFailed {
            return .systemFailed
        }
        lastReminderReconciliationOutcome = .committed
        return .committed
    }

    func beginScheduleReminder(
        for task: StoredDoseTask,
        medication: StoredMedication,
        deliveryMethod: StoredReminderDeliveryMethod = .notification,
        escalatesToAlarmWhenUnhandled: Bool = true,
        refreshPendingCount: Bool = true
    ) -> Task<MedicationReminderSchedulingResult, Never> {
        let entry = MedicationReminderPostCommitEntry(
            task: task,
            medication: medication,
            deliveryMethod: deliveryMethod,
            escalatesToAlarmWhenUnhandled: escalatesToAlarmWhenUnhandled
        )
        let snapshot = MedicationReminderPostCommitSnapshot(entries: [entry], cancelledTaskIDs: [])
        return reminderOperationQueue.enqueue { @MainActor [self, snapshot] in
            await scheduleReminderImmediately(
                snapshot,
                refreshPendingCount: refreshPendingCount
            )
        }
    }

    @discardableResult
    func scheduleReminder(
        for task: StoredDoseTask,
        medication: StoredMedication,
        deliveryMethod: StoredReminderDeliveryMethod = .notification,
        escalatesToAlarmWhenUnhandled: Bool = true,
        refreshPendingCount: Bool = true
    ) async -> MedicationReminderSchedulingResult {
        await beginScheduleReminder(
            for: task,
            medication: medication,
            deliveryMethod: deliveryMethod,
            escalatesToAlarmWhenUnhandled: escalatesToAlarmWhenUnhandled,
            refreshPendingCount: refreshPendingCount
        ).value
    }

    private func scheduleReminderImmediately(
        _ snapshot: MedicationReminderPostCommitSnapshot,
        refreshPendingCount: Bool
    ) async -> MedicationReminderSchedulingResult {
        let results = await scheduleReminderSnapshotImmediately(
            snapshot,
            refreshPendingCount: refreshPendingCount
        )
        return snapshot.entries.first.flatMap { results[$0.taskID] }
            ?? .unavailable(message: "提醒未安排，请检查通知或闹钟权限后重试。")
    }

    func scheduleReminders(
        for tasks: [StoredDoseTask],
        medication: StoredMedication,
        deliveryMethod: StoredReminderDeliveryMethod = .notification
    ) async {
        let entries = tasks.map {
            MedicationReminderPostCommitEntry(
                task: $0,
                medication: medication,
                deliveryMethod: deliveryMethod,
                escalatesToAlarmWhenUnhandled: true
            )
        }
        let snapshot = MedicationReminderPostCommitSnapshot(
            entries: entries,
            cancelledTaskIDs: medication.lifecycleStatus == .active ? [] : tasks.map(\.id)
        )
        _ = await beginApplyReminderSnapshot(snapshot).value
    }

    func beginApplyReminderSnapshot(
        _ snapshot: MedicationReminderPostCommitSnapshot,
        pruneExistingPrefixRequests: Bool = false
    ) -> Task<[UUID: MedicationReminderSchedulingResult], Never> {
        reminderOperationQueue.enqueue { @MainActor [self, snapshot] in
            return await scheduleReminderSnapshotImmediately(
                snapshot,
                pruneExistingPrefixRequests: pruneExistingPrefixRequests
            )
        }
    }

    @discardableResult
    func beginApplyCommittedReminderState(
        in modelContext: ModelContext
    ) -> Task<[UUID: MedicationReminderSchedulingResult], Never> {
        do {
            let snapshot = try MedicationReminderCommittedSnapshotReader.read(in: modelContext)
            return beginApplyReminderSnapshot(snapshot, pruneExistingPrefixRequests: true)
        } catch {
            return reminderOperationQueue.enqueue { @MainActor [self] in
                lastSystemOperationFailed = true
                var warnings = loadReminderSyncWarningState()
                warnings.globalMessage = "全局提醒信息暂时无法读取；现有提醒保持不变，请稍后重试。"
                persistReminderSyncWarningState(warnings)
                return [:]
            }
        }
    }

    func beginScheduleReminderBatches(
        _ batches: [MedicationReminderScheduleBatch],
        additionalCancelledTaskIDs: [UUID] = [],
        pruneExistingPrefixRequests: Bool = false
    ) -> Task<Void, Never> {
        let snapshot = MedicationReminderPostCommitSnapshot(
            batches: batches,
            additionalCancelledTaskIDs: additionalCancelledTaskIDs
        )
        let operation = beginApplyReminderSnapshot(
            snapshot,
            pruneExistingPrefixRequests: pruneExistingPrefixRequests
        )
        return Task {
            _ = await operation.value
        }
    }

    func scheduleReminderBatches(
        _ batches: [MedicationReminderScheduleBatch],
        pruneExistingPrefixRequests: Bool = false
    ) async {
        await beginScheduleReminderBatches(
            batches,
            pruneExistingPrefixRequests: pruneExistingPrefixRequests
        ).value
    }

    private func scheduleReminderSnapshotImmediately(
        _ snapshot: MedicationReminderPostCommitSnapshot,
        pruneExistingPrefixRequests: Bool = false,
        refreshPendingCount: Bool = true
    ) async -> [UUID: MedicationReminderSchedulingResult] {
        lastSystemOperationFailed = false
        var warningState = pruneExistingPrefixRequests
            ? MedicationReminderSyncWarningState()
            : loadReminderSyncWarningState()
        let initialNow = snapshot.capturedAt
        var seenTaskIDs: Set<UUID> = []
        let activeEntries = snapshot.entriesPendingAtCapture()
            .sorted {
                $0.dueAt == $1.dueAt
                    ? $0.taskID.uuidString < $1.taskID.uuidString
                    : $0.dueAt < $1.dueAt
            }
            .filter { seenTaskIDs.insert($0.taskID).inserted }
        let affectedTaskIDs = Set(snapshot.entries.map(\.taskID) + snapshot.cancelledTaskIDs)
        guard let cleanup = await removeExistingReminderRequests(
            for: affectedTaskIDs,
            pruneAllReminders: pruneExistingPrefixRequests,
            snapshot: snapshot
        ) else {
            lastSystemOperationFailed = true
            let message = "提醒状态暂时无法核对，请稍后重试。"
            if affectedTaskIDs.isEmpty {
                warningState.globalMessage = message
            } else {
                warningState.replace(
                    affectedTaskIDs: affectedTaskIDs,
                    results: Dictionary(uniqueKeysWithValues: affectedTaskIDs.map {
                        ($0, .unavailable(message: message))
                    })
                )
            }
            persistReminderSyncWarningState(warningState)
            if refreshPendingCount {
                await refreshPendingReminderCount()
            }
            return Dictionary(uniqueKeysWithValues: activeEntries.map {
                ($0.taskID, .unavailable(message: "提醒状态暂时无法核对，请稍后重试。"))
            })
        }
        lastSystemOperationFailed = cleanup.failed
        let notificationAvailable: Bool
        let beforeAuthorizationNow = Date()
        if !activeEntries.contains(where: {
            $0.dueAt > beforeAuthorizationNow || ($0.escalatesToAlarmWhenUnhandled
                && reminderPolicy.escalationDueAt(for: $0.dueAt) > beforeAuthorizationNow)
        }) {
            notificationAvailable = false
        } else {
            notificationAvailable = await ensureNotificationAuthorizationForScheduling()
        }
        let alarmAvailable = hasAlarmAuthorization
        let schedulingNow = Date()
        let schedulableEntries = activeEntries.filter {
            !cleanup.blockedTaskIDs.contains($0.taskID)
                && ($0.dueAt > schedulingNow || ($0.escalatesToAlarmWhenUnhandled
                    && reminderPolicy.escalationDueAt(for: $0.dueAt) > schedulingNow))
        }
        let plan = notificationPolicy.requestPlan(
            candidates: schedulableEntries.map {
                MedicationReminderRequestCandidate(
                    taskID: $0.taskID,
                    dueAt: $0.dueAt > schedulingNow
                        ? $0.dueAt : reminderPolicy.escalationDueAt(for: $0.dueAt),
                    wantsAlarm: $0.deliveryMethodRaw == StoredReminderDeliveryMethod.alarm.rawValue,
                    wantsEscalation: $0.escalatesToAlarmWhenUnhandled
                        && reminderPolicy.escalationDueAt(for: $0.dueAt) > schedulingNow,
                    wantsBase: $0.dueAt > schedulingNow,
                    escalationDueAt: reminderPolicy.escalationDueAt(for: $0.dueAt)
                )
            },
            occupiedRequestCount: cleanup.occupiedRequestCount,
            notificationAvailable: notificationAvailable,
            alarmAvailable: alarmAvailable
        )
        let entriesByID = Dictionary(uniqueKeysWithValues: schedulableEntries.map { ($0.taskID, $0) })
        var results: [UUID: MedicationReminderSchedulingResult] = [:]
        for taskID in cleanup.blockedTaskIDs {
            if affectedTaskIDs.contains(taskID) {
                results[taskID] = .unavailable(message: "旧提醒暂时无法取消，请稍后重试。")
            }
        }
        for entry in activeEntries where !cleanup.blockedTaskIDs.contains(entry.taskID) {
            if MedicationReminderRequestTiming.missedWindow(
                baseDueAt: entry.dueAt,
                escalationDueAt: reminderPolicy.escalationDueAt(for: entry.dueAt),
                initialNow: initialNow,
                schedulingNow: schedulingNow,
                wantsEscalation: entry.escalatesToAlarmWhenUnhandled
            ) {
                results[entry.taskID] = .unavailable(
                    message: "提醒时间在同步期间已过，未能安排；请查看用药记录。"
                )
                lastSystemOperationFailed = true
            }
        }
        let scheduled = await scheduleOrderedReminderRequests(
            plan,
            entriesByID: entriesByID,
            plannedAt: schedulingNow,
            notificationAvailable: notificationAvailable,
            alarmAvailable: alarmAvailable
        )
        results.merge(scheduled.results) { _, new in new }
        lastSystemOperationFailed = lastSystemOperationFailed || scheduled.systemFailed
        for taskID in plan.deferredTaskIDs {
            results[taskID] = .unavailable(message: "近期提醒已达到本机排程预算，请稍后刷新。")
        }
        for taskID in plan.unavailableTaskIDs {
            results[taskID] = .unavailable(message: "提醒未安排，请检查通知或闹钟权限。")
        }
        for entry in activeEntries where !cleanup.blockedTaskIDs.contains(entry.taskID)
            && MedicationReminderRequestTiming.missedBaseWhileQueued(
                baseDueAt: entry.dueAt,
                escalationDueAt: reminderPolicy.escalationDueAt(for: entry.dueAt),
                capturedAt: initialNow,
                schedulingNow: schedulingNow,
                wantsEscalation: entry.escalatesToAlarmWhenUnhandled
            ) {
            let prior = results[entry.taskID]
                ?? .unavailable(message: "升级提醒未能安排，请查看用药记录。")
            results[entry.taskID] = MedicationReminderRequestTiming.reportExpiredBase(
                prior, expired: true
            )
            lastSystemOperationFailed = true
        }
        warningState.replace(affectedTaskIDs: affectedTaskIDs, results: results)
        if cleanup.hasUnattributedFailure {
            warningState.globalMessage = "部分旧提醒未能从系统取消，请稍后重试。"
        }
        persistReminderSyncWarningState(warningState)
        if refreshPendingCount {
            await refreshPendingReminderCount()
        }
        return results
    }

    private struct OrderedReminderState {
        var baseScheduled = false
        var baseNotificationScheduled = false
        var escalationScheduled = false
        var missedBase = false
        var fallbackQueued = false
        var fallbackKind: MedicationReminderRequestKind?
        var failedKinds: [MedicationReminderRequestKind] = []
        var usedEscalationNotificationFallback = false
        var systemFailed = false
    }

    private func scheduleOrderedReminderRequests(
        _ plan: MedicationReminderRequestPlan,
        entriesByID: [UUID: MedicationReminderPostCommitEntry],
        plannedAt: Date,
        notificationAvailable: Bool,
        alarmAvailable: Bool
    ) async -> (results: [UUID: MedicationReminderSchedulingResult], systemFailed: Bool) {
        let assignmentsByID = Dictionary(uniqueKeysWithValues: plan.assignments.map { ($0.taskID, $0) })
        var queue = MedicationReminderRequestExecutionQueue(plan.orderedRequests)
        var states: [UUID: OrderedReminderState] = [:]

        while let request = queue.next() {
            guard let entry = entriesByID[request.taskID],
                  let assignment = assignmentsByID[request.taskID] else { continue }
            var state = states[request.taskID] ?? OrderedReminderState()
            let isBase = request.kind == .baseNotification || request.kind == .baseAlarm
            let plannedBase = assignment.kinds.contains(.baseNotification)
                || assignment.kinds.contains(.baseAlarm)
            if request.isOptional && state.baseNotificationScheduled {
                states[request.taskID] = state
                continue
            }
            if !isBase && plannedBase && !state.baseScheduled && !state.missedBase {
                states[request.taskID] = state
                continue
            }

            if request.dueAt <= Date() {
                if isBase {
                    if !state.baseScheduled { state.missedBase = true }
                    else if request.isOptional { state.failedKinds.append(.baseNotification) }
                } else {
                    state.failedKinds.append(request.kind)
                }
                state.systemFailed = true
            } else {
                let outcome = await performReminderRequest(request.kind, for: entry)
                state.failedKinds.append(contentsOf: outcome.failedKinds)
                state.systemFailed = state.systemFailed || !outcome.failedKinds.isEmpty
                if isBase {
                    state.baseScheduled = state.baseScheduled || outcome.baseScheduled
                    if request.kind == .baseNotification && outcome.baseScheduled {
                        state.baseNotificationScheduled = true
                    }
                    if request.kind == .baseAlarm && outcome.baseScheduled
                        && outcome.failedKinds.contains(.baseAlarm) {
                        state.baseNotificationScheduled = true
                    }
                    if !state.baseScheduled && entry.dueAt <= Date() {
                        state.missedBase = true
                        state.systemFailed = true
                    }
                } else {
                    state.escalationScheduled = state.escalationScheduled || outcome.escalationScheduled
                    state.usedEscalationNotificationFallback =
                        state.usedEscalationNotificationFallback
                        || outcome.usedEscalationNotificationFallback
                }
            }

            let escalationAt = reminderPolicy.escalationDueAt(for: entry.dueAt)
            let plannedEscalation = assignment.kinds.contains(.escalationAlarm)
                || assignment.kinds.contains(.escalationNotification)
            if state.missedBase && !state.fallbackQueued && !plannedEscalation
                && entry.escalatesToAlarmWhenUnhandled && escalationAt > Date() {
                let fallbackKind: MedicationReminderRequestKind?
                if alarmAvailable { fallbackKind = .escalationAlarm }
                else if notificationAvailable { fallbackKind = .escalationNotification }
                else { fallbackKind = nil }
                if let fallbackKind {
                    queue.insertEscalation(MedicationReminderPlannedRequest(
                        taskID: entry.taskID, dueAt: escalationAt,
                        kind: fallbackKind, isOptional: false
                    ))
                    state.fallbackQueued = true
                    state.fallbackKind = fallbackKind
                }
            }
            states[request.taskID] = state
        }

        var results: [UUID: MedicationReminderSchedulingResult] = [:]
        for assignment in plan.assignments {
            guard let entry = entriesByID[assignment.taskID] else { continue }
            let state = states[assignment.taskID] ?? OrderedReminderState()
            let plannedEscalation = assignment.kinds.contains(.escalationAlarm)
                || assignment.kinds.contains(.escalationNotification) || state.fallbackQueued
            let missedBaseWithoutDelivery = state.missedBase && !state.baseScheduled
            let outcome = MedicationReminderRequestExecutionOutcome(
                baseScheduled: state.baseScheduled,
                escalationScheduled: state.escalationScheduled
                    || (!plannedEscalation && !state.missedBase),
                failedKinds: state.failedKinds,
                usedEscalationNotificationFallback: state.usedEscalationNotificationFallback
            )
            let plannedKinds = assignment.kinds + (state.fallbackKind.map { [$0] } ?? [])
            let wantsEscalationAlarm = entry.escalatesToAlarmWhenUnhandled
                && reminderPolicy.escalationDueAt(for: entry.dueAt) > plannedAt
            if missedBaseWithoutDelivery {
                results[entry.taskID] = MedicationReminderRequestTiming.reportMissedBase(
                    outcome: outcome,
                    plannedKinds: plannedKinds,
                    wantsEscalation: entry.escalatesToAlarmWhenUnhandled,
                    wantsEscalationAlarm: wantsEscalationAlarm
                )
            } else {
                let result = outcome.schedulingResult(
                    wantsAlarm: entry.deliveryMethodRaw == StoredReminderDeliveryMethod.alarm.rawValue,
                    wantsEscalationAlarm: wantsEscalationAlarm,
                    plannedKinds: plannedKinds
                )
                results[entry.taskID] = MedicationReminderRequestTiming.reportExpiredBase(
                    result, expired: state.missedBase
                )
            }
        }
        return (results, states.values.contains { $0.systemFailed })
    }

    private func performReminderRequest(
        _ kind: MedicationReminderRequestKind,
        for entry: MedicationReminderPostCommitEntry
    ) async -> MedicationReminderRequestExecutionOutcome {
        let escalationAt = reminderPolicy.escalationDueAt(for: entry.dueAt)
        return await MedicationReminderRequestExecutor(
            addBaseNotification: {
                await self.scheduleNotificationReminder(for: entry, refreshPendingCount: false) == .scheduled
            },
            addBaseAlarm: {
                await self.scheduleAlarmReminder(for: entry)
            },
            addEscalationNotification: {
                await self.scheduleEscalationNotification(for: entry, escalationAt: escalationAt)
            },
            addEscalationAlarm: {
                #if canImport(AlarmKit)
                if #available(iOS 26.0, *) {
                    return await self.scheduleAlarmReminder(
                        for: entry,
                        alarmID: self.escalationAlarmID(for: entry.taskID),
                        dueAt: escalationAt,
                        titlePrefix: "仍未确认"
                    )
                }
                #endif
                return false
            }
        ).execute([kind])
    }

    @discardableResult
    func cancelReminders(for taskIDs: [UUID]) -> Task<Void, Never> {
        reminderOperationQueue.enqueue { @MainActor [self, taskIDs] in
            _ = await scheduleReminderSnapshotImmediately(
                MedicationReminderPostCommitSnapshot(entries: [], cancelledTaskIDs: taskIDs)
            )
        }
    }

    @discardableResult
    func cancelReminder(for taskID: UUID) -> Task<Void, Never> {
        reminderOperationQueue.enqueue { @MainActor [self, taskID] in
            _ = await scheduleReminderSnapshotImmediately(
                MedicationReminderPostCommitSnapshot(entries: [], cancelledTaskIDs: [taskID])
            )
        }
    }

    private struct ReminderCleanupResult {
        let occupiedRequestCount: Int
        let blockedTaskIDs: Set<UUID>
        let failed: Bool
        let hasUnattributedFailure: Bool
    }

    private func removeExistingReminderRequests(
        for taskIDs: Set<UUID>,
        pruneAllReminders: Bool,
        snapshot: MedicationReminderPostCommitSnapshot
    ) async -> ReminderCleanupResult? {
        let center = UNUserNotificationCenter.current()
        let pendingBefore = await center.pendingNotificationRequests()
        let deliveredBefore = await center.deliveredNotifications()
        guard let alarmsBefore = try? pendingAlarmIDs() else { return nil }
        let cleanupNow = Date()
        let preserveBaseForTaskIDs = Set(snapshot.entries.filter {
            $0.medicationIsActive && $0.taskIsOpen && $0.dueAt <= cleanupNow
        }.map(\.taskID))
        let targets = MedicationReminderCancellationTargets(
            taskIDs: taskIDs,
            pendingNotificationIDs: Set(pendingBefore.map(\.identifier)),
            deliveredNotificationIDs: Set(deliveredBefore.map { $0.request.identifier }),
            existingAlarmIDs: alarmsBefore,
            pruneAllReminders: pruneAllReminders,
            preserveBaseForTaskIDs: preserveBaseForTaskIDs,
            preservedDeliveredNotificationIDs: snapshot.preservedDeliveredNotificationIDs(at: cleanupNow)
        )
        let notificationIDs = targets.notificationIDs
        if !notificationIDs.isEmpty {
            let identifiers = notificationIDs.sorted()
            center.removePendingNotificationRequests(withIdentifiers: identifiers)
        }
        if !targets.deliveredNotificationIDsToRemove.isEmpty {
            center.removeDeliveredNotifications(
                withIdentifiers: targets.deliveredNotificationIDsToRemove.sorted()
            )
        }
        let alarmIDs = targets.alarmIDs
        #if canImport(AlarmKit)
        if #available(iOS 26.0, *) {
            for id in alarmIDs.intersection(alarmsBefore).sorted(by: {
                $0.uuidString < $1.uuidString
            }) {
                do {
                    try AlarmManager.shared.cancel(id: id)
                } catch {
                    // The readback below distinguishes a race with a fired alarm
                    // from a cancellation that actually left a stale alarm.
                }
                // Keep the existing alert-stopping behavior for alarms that
                // are already presenting while the user records an action.
                try? AlarmManager.shared.stop(id: id)
            }
        }
        #endif

        let readback = await MedicationReminderNotificationReadback.converge(
            targetedPendingIDs: notificationIDs,
            readPendingIDs: {
                Set((await center.pendingNotificationRequests()).map(\.identifier))
            },
            readDeliveredIDs: {
                Set((await center.deliveredNotifications()).map { $0.request.identifier })
            },
            unwantedDeliveredIDs: { deliveredIDs in
                MedicationReminderCancellationTargets(
                    taskIDs: taskIDs,
                    pendingNotificationIDs: [],
                    deliveredNotificationIDs: deliveredIDs,
                    existingAlarmIDs: [],
                    pruneAllReminders: pruneAllReminders,
                    preserveBaseForTaskIDs: preserveBaseForTaskIDs,
                    preservedDeliveredNotificationIDs: snapshot.preservedDeliveredNotificationIDs(at: Date())
                ).deliveredNotificationIDsToRemove.intersection(deliveredIDs)
            },
            removePendingIDs: { ids in
                center.removePendingNotificationRequests(withIdentifiers: ids.sorted())
            },
            removeDeliveredIDs: { ids in
                center.removeDeliveredNotifications(withIdentifiers: ids.sorted())
            },
            pause: {
                try? await Task.sleep(for: .milliseconds(80))
            }
        )
        // A pending request can fire while delivered cleanup suspends. Both
        // snapshots are refreshed in each readback round before deciding.
        guard let alarmsAfter = try? pendingAlarmIDs() else { return nil }
        let remainingNotificationIDs = notificationIDs.intersection(readback.pendingIDs)
            .union(readback.remainingDeliveredIDs)
        let remainingAlarmIDs = alarmIDs.intersection(alarmsAfter)
        let blockedTaskIDs = MedicationReminderCancellationReadback.blockedTaskIDs(
            among: taskIDs,
            remainingNotificationIDs: remainingNotificationIDs,
            remainingAlarmIDs: remainingAlarmIDs
        )
        return ReminderCleanupResult(
            occupiedRequestCount: readback.pendingIDs.count + alarmsAfter.count,
            blockedTaskIDs: blockedTaskIDs,
            failed: !remainingNotificationIDs.isEmpty || !remainingAlarmIDs.isEmpty,
            hasUnattributedFailure: MedicationReminderCancellationReadback.hasUnattributedFailure(
                among: taskIDs,
                remainingNotificationIDs: remainingNotificationIDs,
                remainingAlarmIDs: remainingAlarmIDs
            )
        )
    }

    private var hasAlarmAuthorization: Bool {
        #if canImport(AlarmKit)
        if #available(iOS 26.0, *) {
            return AlarmManager.shared.authorizationState == .authorized
        }
        #endif
        return false
    }

    private func pendingAlarmIDs() throws -> Set<UUID> {
        #if canImport(AlarmKit)
        if #available(iOS 26.0, *) {
            do {
                return Set(try AlarmManager.shared.alarms.map(\.id))
            } catch {
                guard AlarmManager.shared.authorizationState != .authorized else {
                    throw error
                }
                return []
            }
        }
        #endif
        return []
    }

    private func scheduleNotificationReminder(
        for entry: MedicationReminderPostCommitEntry,
        refreshPendingCount: Bool = true
    ) async -> MedicationReminderSchedulingResult {
        guard entry.dueAt > Date() else {
            authorizationMessage = "提醒时间已过，未安排本地提醒"
            if refreshPendingCount {
                await refreshPendingReminderCount()
            }
            return .unavailable(message: "提醒时间已过，请重新设置提醒。")
        }

        let payload = NotificationPayload(
            scheduledDoseID: entry.taskID,
            medicationID: entry.medicationID,
            planID: entry.planID,
            medicationName: entry.medicationName,
            doseText: entry.doseText
        )

        let content = UNMutableNotificationContent()
        content.title = "该服药了"
        content.body = "\(payload.medicationName) · \(payload.doseText)"
        content.sound = .default
        content.categoryIdentifier = MedicationNotificationDelegate.categoryIdentifier
        content.userInfo = [
            "scheduledDoseID": payload.scheduledDoseID.uuidString,
            "medicationID": payload.medicationID.uuidString,
            "planID": payload.planID.uuidString
        ]

        let components = notificationPolicy.triggerDateComponents(for: entry.dueAt, calendar: .current)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let identifier = notificationIdentifier(for: entry.taskID)
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [identifier])
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        let result = await MedicationNotificationRequestScheduler(
            authorizationFailureMessage: {
                guard await self.ensureNotificationAuthorizationForScheduling() else {
                    return "提醒未安排，请在系统设置中允许通知。"
                }
                return nil
            },
            addRequest: { request in
                guard entry.dueAt > Date() else { throw MedicationReminderRequestExpired() }
                try await UNUserNotificationCenter.current().add(request)
            }
        ).schedule(request)
        switch result {
        case .scheduled:
            authorizationMessage = "已安排下一次本地提醒"
            updateNotificationUnavailableMessage(nil)
            if refreshPendingCount {
                await refreshPendingReminderCount()
            }
        case .unavailable:
            authorizationMessage = "本地提醒暂时无法安排，请稍后重试。"
            updateNotificationUnavailableMessage(result.failureMessage)
        }
        return result
    }

    private func scheduleAlarmReminder(for entry: MedicationReminderPostCommitEntry) async -> Bool {
        #if canImport(AlarmKit)
        if #available(iOS 26.0, *) {
            do {
                guard AlarmManager.shared.authorizationState == .authorized else {
                    authorizationMessage = "iPhone 闹钟未授权，已改用推送通知"
                    return false
                }
                guard entry.dueAt > Date() else { return false }

                let payload = NotificationPayload(
                    scheduledDoseID: entry.taskID,
                    medicationID: entry.medicationID,
                    planID: entry.planID,
                    medicationName: entry.medicationName,
                    doseText: entry.doseText
                )
                let title = LocalizedStringResource(stringLiteral: "\(payload.medicationName) · \(payload.doseText)")
                let stopButton = AlarmButton(
                    text: "完成",
                    textColor: .white,
                    systemImageName: "checkmark"
                )
                let presentation = AlarmPresentation(alert: AlarmPresentation.Alert(title: title, stopButton: stopButton))
                let attributes = AlarmAttributes<MedicationAlarmMetadata>(
                    presentation: presentation,
                    metadata: MedicationAlarmMetadata(
                        scheduledDoseID: payload.scheduledDoseID,
                        medicationID: payload.medicationID,
                        planID: payload.planID
                    ),
                    tintColor: .teal
                )
                let configuration = AlarmManager.AlarmConfiguration<MedicationAlarmMetadata>.alarm(
                    schedule: .fixed(entry.dueAt),
                    attributes: attributes
                )
                _ = try await AlarmManager.shared.schedule(id: entry.taskID, configuration: configuration)
                authorizationMessage = "已安排 iPhone 闹钟提醒"
                return true
            } catch {
                authorizationMessage = "iPhone 闹钟暂时无法安排，已改用推送通知。"
                return false
            }
        }
        #endif
        authorizationMessage = "当前系统不支持 iPhone 闹钟提醒，已改用推送通知"
        return false
    }

    private func scheduleEscalationNotification(
        for entry: MedicationReminderPostCommitEntry,
        escalationAt: Date
    ) async -> Bool {
        guard await ensureNotificationAuthorizationForScheduling() else {
            return false
        }
        guard escalationAt > Date() else { return false }

        let content = UNMutableNotificationContent()
        content.title = "仍未确认服药"
        content.body = "\(entry.medicationName) · 请在 App 内确认已服用、稍后或忽略"
        content.sound = .default
        content.categoryIdentifier = MedicationNotificationDelegate.categoryIdentifier
        content.userInfo = [
            "scheduledDoseID": entry.taskID.uuidString,
            "medicationID": entry.medicationID.uuidString,
            "planID": entry.planID.uuidString,
            "reminderKind": "escalation"
        ]

        let components = notificationPolicy.triggerDateComponents(for: escalationAt, calendar: .current)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let identifier = escalationAlarmNotificationIdentifier(for: entry.taskID)
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [identifier])
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        do {
            try await UNUserNotificationCenter.current().add(request)
            updateNotificationUnavailableMessage(nil)
            return true
        } catch {
            updateNotificationUnavailableMessage("普通提醒不可用：升级提醒暂时无法安排，请稍后重试。")
            return false
        }
    }

    #if canImport(AlarmKit)
    @available(iOS 26.0, *)
    private func scheduleAlarmReminder(
        for entry: MedicationReminderPostCommitEntry,
        alarmID: UUID,
        dueAt: Date,
        titlePrefix: String
    ) async -> Bool {
        do {
            guard AlarmManager.shared.authorizationState == .authorized else {
                return false
            }
            guard dueAt > Date() else { return false }

            let payload = NotificationPayload(
                scheduledDoseID: entry.taskID,
                medicationID: entry.medicationID,
                planID: entry.planID,
                medicationName: entry.medicationName,
                doseText: entry.doseText
            )
            let title = LocalizedStringResource(stringLiteral: "\(titlePrefix)：\(payload.medicationName) · \(payload.doseText)")
            let stopButton = AlarmButton(
                text: "打开 App 确认",
                textColor: .white,
                systemImageName: "checkmark"
            )
            let presentation = AlarmPresentation(alert: AlarmPresentation.Alert(title: title, stopButton: stopButton))
            let attributes = AlarmAttributes<MedicationAlarmMetadata>(
                presentation: presentation,
                metadata: MedicationAlarmMetadata(
                    scheduledDoseID: payload.scheduledDoseID,
                    medicationID: payload.medicationID,
                    planID: payload.planID
                ),
                tintColor: .orange
            )
            let configuration = AlarmManager.AlarmConfiguration<MedicationAlarmMetadata>.alarm(
                schedule: .fixed(dueAt),
                attributes: attributes
            )
            _ = try await AlarmManager.shared.schedule(id: alarmID, configuration: configuration)
            return true
        } catch {
            return false
        }
    }
    #endif

    private func notificationIdentifier(for taskID: UUID) -> String {
        MedicationReminderSystemIdentifiers.baseNotification(for: taskID)
    }

    private func escalationAlarmNotificationIdentifier(for taskID: UUID) -> String {
        MedicationReminderSystemIdentifiers.escalationNotification(for: taskID)
    }

    private func escalationAlarmID(for taskID: UUID) -> UUID {
        MedicationReminderSystemIdentifiers.escalationAlarm(for: taskID)
    }

    private func isBaseNotificationIdentifier(_ identifier: String) -> Bool {
        identifier.hasPrefix(notificationIdentifierPrefix)
            && !identifier.hasPrefix(escalationAlarmIdentifierPrefix)
    }

    private func ensureNotificationAuthorizationForScheduling() async -> Bool {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        if settings.authorizationStatus == .notDetermined {
            return await requestAuthorization()
        }

        authorizationMessage = message(for: settings.authorizationStatus)
        if let unavailableMessage = notificationUnavailableMessage(for: settings) {
            updateNotificationUnavailableMessage(unavailableMessage)
            return false
        }

        updateNotificationUnavailableMessage(nil)
        return true
    }

    private func notificationUnavailableMessage(for settings: UNNotificationSettings) -> String? {
        let status: MedicationNotificationAuthorizationStatus
        switch settings.authorizationStatus {
        case .notDetermined:
            status = .notDetermined
        case .denied:
            status = .denied
        case .authorized, .provisional, .ephemeral:
            status = .authorized
        @unknown default:
            status = .unknown
        }
        let disposition = notificationPolicy.authorizationDisposition(
            status: status,
            hasPresentationSurface: settings.alertSetting == .enabled
                || settings.lockScreenSetting == .enabled
                || settings.notificationCenterSetting == .enabled,
            hasSound: settings.soundSetting == .enabled
        )
        return notificationPolicy.unavailableMessage(for: disposition)
    }

    private func updateNotificationUnavailableMessage(_ message: String?) {
        if let message, !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            defaults.set(message, forKey: Self.reminderNotificationUnavailableMessageKey)
        } else {
            defaults.removeObject(forKey: Self.reminderNotificationUnavailableMessageKey)
        }
    }

    private func loadReminderSyncWarningState() -> MedicationReminderSyncWarningState {
        MedicationReminderSyncWarningState(
            messagesByTaskID: defaults.dictionary(forKey: Self.reminderSystemSyncMessagesByTaskKey)
                as? [String: String] ?? [:],
            globalMessage: defaults.string(forKey: Self.reminderSystemSyncGlobalMessageKey)
        )
    }

    private func persistReminderSyncWarningState(_ state: MedicationReminderSyncWarningState) {
        if state.messagesByTaskID.isEmpty {
            defaults.removeObject(forKey: Self.reminderSystemSyncMessagesByTaskKey)
        } else {
            defaults.set(state.messagesByTaskID, forKey: Self.reminderSystemSyncMessagesByTaskKey)
        }
        if let globalMessage = state.globalMessage {
            defaults.set(globalMessage, forKey: Self.reminderSystemSyncGlobalMessageKey)
        } else {
            defaults.removeObject(forKey: Self.reminderSystemSyncGlobalMessageKey)
        }
        updateReminderSystemSyncMessage(state.displayMessage)
    }

    private func updateReminderSystemSyncMessage(_ message: String?) {
        if let message, !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            defaults.set(message, forKey: Self.reminderSystemSyncMessageKey)
        } else {
            defaults.removeObject(forKey: Self.reminderSystemSyncMessageKey)
        }
    }

    private func message(for status: UNAuthorizationStatus) -> String {
        switch status {
        case .notDetermined:
            return "尚未请求通知权限"
        case .denied:
            return "通知权限未开启"
        case .authorized:
            return "通知权限已开启"
        case .provisional:
            return "通知权限已临时开启"
        case .ephemeral:
            return "通知权限已开启"
        @unknown default:
            return "通知权限状态未知"
        }
    }
}
