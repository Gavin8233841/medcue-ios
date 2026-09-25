import Foundation
import MedicationAdherenceCore
import SwiftData
import Testing
@testable import MedicationAdherenceApp

@MainActor
private final class ReminderRequestTestState {
    var installed: Set<String> = []
    var fallbackFails = true
    var alarmAttempts = 0
}

struct MedicationReminderPostCommitSchedulerTests {
    @Test @MainActor
    func snapshotCopiesValuesBeforeLiveModelsChange() throws {
        let medication = StoredMedication(
            displayName: "测试药",
            kind: .overTheCounter,
            inputSource: .manual
        )
        let task = StoredDoseTask(
            medicationID: medication.id,
            dueAt: Date(timeIntervalSince1970: 2_000),
            doseValue: 1,
            doseUnit: "片"
        )
        let batch = MedicationReminderScheduleBatch(
            medication: medication,
            deliveryMethod: .notification,
            escalatesToAlarmWhenUnhandled: true,
            tasks: [task],
            cancelledTaskIDs: []
        )

        let snapshot = MedicationReminderPostCommitSnapshot(batch: batch)
        medication.displayName = "已修改"
        task.dueAt = Date(timeIntervalSince1970: 9_000)
        task.doseValue = 3

        let entry = try #require(snapshot.entries.first)
        #expect(entry.medicationName == "测试药")
        #expect(entry.dueAt == Date(timeIntervalSince1970: 2_000))
        #expect(entry.doseText == "1 片")
    }

    @Test @MainActor
    func snapshotPreservesDeliveredNotificationsThatBecomeDueWhileQueued() throws {
        let dueAt = Date(timeIntervalSince1970: 2_000)
        let medication = StoredMedication(
            displayName: "队列等待药", kind: .overTheCounter, inputSource: .manual
        )
        let task = StoredDoseTask(
            medicationID: medication.id, dueAt: dueAt, doseValue: 1, doseUnit: "片"
        )
        let snapshot = MedicationReminderPostCommitSnapshot(batch: MedicationReminderScheduleBatch(
            medication: medication, deliveryMethod: .notification,
            escalatesToAlarmWhenUnhandled: true, tasks: [task], cancelledTaskIDs: []
        ))
        let baseID = MedicationReminderSystemIdentifiers.baseNotification(for: task.id)
        let escalationID = MedicationReminderSystemIdentifiers.escalationNotification(for: task.id)
        let beforeDue = snapshot.preservedDeliveredNotificationIDs(at: dueAt.addingTimeInterval(-1))
        let afterBase = snapshot.preservedDeliveredNotificationIDs(at: dueAt)
        let afterEscalation = snapshot.preservedDeliveredNotificationIDs(
            at: DoseReminderPolicy.competitionDemo.escalationDueAt(for: dueAt)
        )

        #expect(!beforeDue.contains(baseID))
        #expect(afterBase.contains(baseID))
        #expect(!afterBase.contains(escalationID))
        #expect(afterEscalation.contains(baseID))
        #expect(afterEscalation.contains(escalationID))
    }

    @Test @MainActor
    func committedGlobalSnapshotRanksNewNearTermDoseAheadOfOtherPlans() throws {
        let container = try MedicationAdherenceModelContainer.make(isStoredInMemoryOnly: true)
        let context = ModelContext(container)
        let now = Date()
        let farMedication = StoredMedication(
            displayName: "远期药", kind: .overTheCounter, inputSource: .manual
        )
        let nearMedication = StoredMedication(
            displayName: "近期药", kind: .overTheCounter, inputSource: .manual
        )
        let farPlan = StoredMedicationPlan(
            medicationID: farMedication.id, doseValue: 1, doseUnit: "片",
            timingSummary: "每日", timeZonePolicy: .localClock, sourceNote: ""
        )
        let nearPlan = StoredMedicationPlan(
            medicationID: nearMedication.id, doseValue: 1, doseUnit: "片",
            timingSummary: "每日", timeZonePolicy: .localClock, sourceNote: ""
        )
        let farTask = StoredDoseTask(
            medicationID: farMedication.id, planID: farPlan.id,
            dueAt: now.addingTimeInterval(86_400), doseValue: 1, doseUnit: "片"
        )
        let nearTask = StoredDoseTask(
            medicationID: nearMedication.id, planID: nearPlan.id,
            dueAt: now.addingTimeInterval(600), doseValue: 1, doseUnit: "片"
        )
        for medication in [farMedication, nearMedication] { context.insert(medication) }
        for plan in [farPlan, nearPlan] { context.insert(plan) }
        for task in [farTask, nearTask] { context.insert(task) }
        try context.save()
        farTask.dueAt = now.addingTimeInterval(60) // Deliberately unsaved view edit.

        let snapshot = try MedicationReminderCommittedSnapshotReader.read(in: context)
        #expect(Set(snapshot.entries.map(\.taskID)) == [farTask.id, nearTask.id])
        #expect(snapshot.entries.first(where: { $0.taskID == farTask.id })?.dueAt
            == now.addingTimeInterval(86_400))
        let plan = MedicationNotificationPolicy(maximumScheduledRequests: 1).requestPlan(
            candidates: snapshot.entries.map {
                MedicationReminderRequestCandidate(
                    taskID: $0.taskID,
                    dueAt: $0.dueAt,
                    wantsAlarm: false,
                    wantsEscalation: false
                )
            },
            occupiedRequestCount: 0,
            notificationAvailable: true,
            alarmAvailable: false
        )
        #expect(plan.assignments.map(\.taskID) == [nearTask.id])
        #expect(plan.deferredTaskIDs == [farTask.id])
    }

    @Test @MainActor
    func committedOpenDoseKeepsFutureEscalationAfterBaseTime() async throws {
        let container = try MedicationAdherenceModelContainer.make(isStoredInMemoryOnly: true)
        let context = ModelContext(container)
        let medication = StoredMedication(
            displayName: "升级窗口药", kind: .overTheCounter, inputSource: .manual
        )
        let plan = StoredMedicationPlan(
            medicationID: medication.id, doseValue: 1, doseUnit: "片",
            timingSummary: "每日", timeZonePolicy: .localClock, sourceNote: ""
        )
        let task = StoredDoseTask(
            medicationID: medication.id, planID: plan.id,
            dueAt: Date().addingTimeInterval(-120), doseValue: 1, doseUnit: "片"
        )
        context.insert(medication)
        context.insert(plan)
        context.insert(task)
        try context.save()

        let snapshot = try MedicationReminderCommittedSnapshotReader.read(in: context)
        let entry = try #require(snapshot.entries.first { $0.taskID == task.id })
        let baseNotificationID = MedicationReminderSystemIdentifiers.baseNotification(for: task.id)
        #expect(snapshot.preservedDeliveredNotificationIDs.contains(baseNotificationID))
        let candidate = MedicationReminderRequestCandidate(
            taskID: entry.taskID,
            dueAt: DoseReminderPolicy.competitionDemo.escalationDueAt(for: entry.dueAt),
            wantsAlarm: false, wantsEscalation: true, wantsBase: false
        )
        let requestPlan = MedicationNotificationPolicy(maximumScheduledRequests: 1).requestPlan(
            candidates: [candidate], occupiedRequestCount: 0,
            notificationAvailable: true, alarmAvailable: true
        )
        let kinds = try #require(requestPlan.assignments.first?.kinds)
        #expect(kinds == [.escalationAlarm])
        let earlierBase = MedicationReminderRequestCandidate(
            taskID: UUID(), dueAt: Date().addingTimeInterval(60),
            wantsAlarm: false, wantsEscalation: false
        )
        let limitedPlan = MedicationNotificationPolicy(maximumScheduledRequests: 1).requestPlan(
            candidates: [candidate, earlierBase], occupiedRequestCount: 0,
            notificationAvailable: true, alarmAvailable: true
        )
        #expect(limitedPlan.assignments.map(\.taskID) == [earlierBase.taskID])
        #expect(limitedPlan.deferredTaskIDs == [task.id])
        let outcome = await MedicationReminderRequestExecutor(
            addBaseNotification: { Issue.record("Past base reminder must not be rescheduled"); return false },
            addBaseAlarm: { Issue.record("Past base alarm must not be rescheduled"); return false },
            addEscalationNotification: { Issue.record("Alarm succeeded; fallback must not run"); return false },
            addEscalationAlarm: { true }
        ).execute(kinds)
        #expect(outcome.schedulingResult(
            wantsAlarm: candidate.wantsAlarm,
            wantsEscalationAlarm: candidate.wantsEscalation,
            plannedKinds: kinds
        ) == .scheduled)
        let failedEscalation = MedicationReminderRequestExecutionOutcome(
            baseScheduled: false,
            escalationScheduled: false,
            failedKinds: [.escalationAlarm, .escalationNotification],
            usedEscalationNotificationFallback: false
        )
        let failureMessage = failedEscalation.schedulingResult(
            wantsAlarm: false, wantsEscalationAlarm: true, plannedKinds: kinds
        ).failureMessage
        #expect(failureMessage?.contains("升级提醒未能安排") == true)
        #expect(failureMessage?.contains("基础提醒已安排") == false)

        let openTargets = MedicationReminderCancellationTargets(
            taskIDs: [task.id], pendingNotificationIDs: [],
            deliveredNotificationIDs: [baseNotificationID], existingAlarmIDs: [],
            pruneAllReminders: true, preserveBaseForTaskIDs: [task.id],
            preservedDeliveredNotificationIDs: snapshot.preservedDeliveredNotificationIDs
        )
        #expect(!openTargets.deliveredNotificationIDsToRemove.contains(baseNotificationID))
        task.status = .taken
        try context.save()
        let completedSnapshot = try MedicationReminderCommittedSnapshotReader.read(in: context)
        #expect(!completedSnapshot.preservedDeliveredNotificationIDs.contains(baseNotificationID))
        let completedTargets = MedicationReminderCancellationTargets(
            taskIDs: [], pendingNotificationIDs: [],
            deliveredNotificationIDs: [baseNotificationID], existingAlarmIDs: [],
            pruneAllReminders: true, preserveBaseForTaskIDs: [],
            preservedDeliveredNotificationIDs: completedSnapshot.preservedDeliveredNotificationIDs
        )
        #expect(completedTargets.deliveredNotificationIDsToRemove.contains(baseNotificationID))
    }

    @Test
    func globalReplanPreservesPresentingBaseWhileReplacingFutureEscalation() {
        let activeTask = UUID()
        let obsoleteTask = UUID()
        let targets = MedicationReminderCancellationTargets(
            taskIDs: [activeTask],
            pendingNotificationIDs: [
                MedicationReminderSystemIdentifiers.baseNotification(for: activeTask),
                MedicationReminderSystemIdentifiers.escalationNotification(for: activeTask),
                MedicationReminderSystemIdentifiers.baseNotification(for: obsoleteTask)
            ],
            existingAlarmIDs: [
                activeTask,
                MedicationReminderSystemIdentifiers.escalationAlarm(for: activeTask),
                obsoleteTask
            ],
            pruneAllReminders: true,
            preserveBaseForTaskIDs: [activeTask]
        )
        #expect(!targets.notificationIDs.contains(
            MedicationReminderSystemIdentifiers.baseNotification(for: activeTask)
        ))
        #expect(!targets.alarmIDs.contains(activeTask))
        #expect(targets.notificationIDs.contains(
            MedicationReminderSystemIdentifiers.escalationNotification(for: activeTask)
        ))
        #expect(targets.alarmIDs.contains(
            MedicationReminderSystemIdentifiers.escalationAlarm(for: activeTask)
        ))
        #expect(targets.notificationIDs.contains(
            MedicationReminderSystemIdentifiers.baseNotification(for: obsoleteTask)
        ))
        #expect(targets.alarmIDs.contains(obsoleteTask))
    }

    @Test @MainActor
    func baseTimeCrossingDuringSystemWaitStillSchedulesEscalation() async {
        let beforeWait = Date(timeIntervalSince1970: 1_000)
        let baseAt = beforeWait.addingTimeInterval(1)
        let escalationAt = baseAt.addingTimeInterval(300)
        let planned: [MedicationReminderRequestKind] = [.baseNotification, .escalationAlarm]
        let before = MedicationReminderRequestTiming.kindsStillDue(
            from: planned, baseDueAt: baseAt, escalationDueAt: escalationAt,
            now: beforeWait, wantsEscalation: true,
            notificationAvailable: true, alarmAvailable: true
        )
        #expect(before == planned)

        let afterWait = beforeWait.addingTimeInterval(2)
        let after = MedicationReminderRequestTiming.kindsStillDue(
            from: planned, baseDueAt: baseAt, escalationDueAt: escalationAt,
            now: afterWait, wantsEscalation: true,
            notificationAvailable: true, alarmAvailable: true
        )
        #expect(after == [.escalationAlarm])
        let reservedBaseOnly = MedicationReminderRequestTiming.kindsStillDue(
            from: [.baseNotification], baseDueAt: baseAt, escalationDueAt: escalationAt,
            now: afterWait, wantsEscalation: true,
            notificationAvailable: true, alarmAvailable: true
        )
        #expect(reservedBaseOnly == [.escalationAlarm])
        let outcome = await MedicationReminderRequestExecutor(
            addBaseNotification: { Issue.record("Expired base must not be added"); return false },
            addBaseAlarm: { Issue.record("Expired base must not be added"); return false },
            addEscalationNotification: { Issue.record("Alarm succeeds without fallback"); return false },
            addEscalationAlarm: { true }
        ).execute(after)
        #expect(outcome.schedulingResult(
            wantsAlarm: false, wantsEscalationAlarm: true, plannedKinds: after
        ) == .scheduled)
        let reported = MedicationReminderRequestTiming.reportExpiredBase(
            outcome.schedulingResult(
                wantsAlarm: false, wantsEscalationAlarm: true, plannedKinds: after
            ),
            expired: true
        )
        #expect(reported.failureMessage?.contains("基础提醒时间已过") == true)

        let crossingExecutor = MedicationReminderRequestExecutor(
            addBaseNotification: { false },
            addBaseAlarm: { Issue.record("Unplanned base alarm must not be added"); return false },
            addEscalationNotification: { Issue.record("Alarm succeeds without fallback"); return false },
            addEscalationAlarm: { true }
        )
        let initialAttempt = await crossingExecutor.execute(planned)
        #expect(!initialAttempt.baseScheduled && !initialAttempt.escalationScheduled)
        let retryKind = MedicationReminderRequestTiming.escalationKindAfterFailedBase(
            from: planned, baseDueAt: baseAt, escalationDueAt: escalationAt,
            now: afterWait, wantsEscalation: true,
            notificationAvailable: true, alarmAvailable: true
        )
        #expect(retryKind == .escalationAlarm)
        if let retryKind {
            let retried = await crossingExecutor.execute([retryKind])
            #expect(retried.schedulingResult(
                wantsAlarm: false, wantsEscalationAlarm: true, plannedKinds: [retryKind]
            ) == .scheduled)
        }

        let afterEscalation = MedicationReminderRequestTiming.kindsStillDue(
            from: planned, baseDueAt: baseAt, escalationDueAt: escalationAt,
            now: escalationAt, wantsEscalation: false,
            notificationAvailable: true, alarmAvailable: true
        )
        #expect(afterEscalation.isEmpty)
    }

    @Test
    func actualRequestBudgetCountsOtherPlansAndEveryDeliverySurface() {
        let now = Date(timeIntervalSince1970: 1_000)
        let first = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let second = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
        let third = UUID(uuidString: "00000000-0000-0000-0000-000000000003")!
        let candidates = [
            MedicationReminderRequestCandidate(
                taskID: third, dueAt: now.addingTimeInterval(30),
                wantsAlarm: false, wantsEscalation: true
            ),
            MedicationReminderRequestCandidate(
                taskID: second, dueAt: now.addingTimeInterval(20),
                wantsAlarm: false, wantsEscalation: true
            ),
            MedicationReminderRequestCandidate(
                taskID: first, dueAt: now.addingTimeInterval(10),
                wantsAlarm: true, wantsEscalation: true
            )
        ]
        let policy = MedicationNotificationPolicy(maximumScheduledRequests: 6)

        let plan = policy.requestPlan(
            candidates: candidates,
            occupiedRequestCount: 1,
            notificationAvailable: true,
            alarmAvailable: true
        )

        #expect(plan.assignments == [
            MedicationReminderRequestAssignment(
                taskID: first,
                kinds: [.baseAlarm, .escalationAlarm]
            ),
            MedicationReminderRequestAssignment(
                taskID: second,
                kinds: [.baseNotification, .escalationAlarm]
            ),
            MedicationReminderRequestAssignment(
                taskID: third,
                kinds: [.baseNotification]
            )
        ])
        #expect(plan.deferredTaskIDs.isEmpty)
        #expect(plan.unavailableTaskIDs.isEmpty)
        #expect(plan.assignments.flatMap(\.kinds).count + 1 == 6)

        let oneSlotLeft = policy.requestPlan(
            candidates: candidates + [
                MedicationReminderRequestCandidate(
                    taskID: UUID(), dueAt: now.addingTimeInterval(40),
                    wantsAlarm: false, wantsEscalation: false
                )
            ],
            occupiedRequestCount: 5,
            notificationAvailable: true,
            alarmAvailable: true
        )
        #expect(oneSlotLeft.assignments == [
            MedicationReminderRequestAssignment(taskID: first, kinds: [.baseAlarm])
        ])
        #expect(oneSlotLeft.deferredTaskIDs.count == 3)

        let ordinaryWithOneSlot = MedicationNotificationPolicy(maximumScheduledRequests: 60)
            .requestPlan(
                candidates: [candidates[1]], occupiedRequestCount: 59,
                notificationAvailable: true, alarmAvailable: true
            )
        #expect(ordinaryWithOneSlot.assignments == [
            MedicationReminderRequestAssignment(taskID: second, kinds: [.baseNotification])
        ])
        let partialOutcome = MedicationReminderRequestExecutionOutcome(
            baseScheduled: true,
            escalationScheduled: true,
            failedKinds: [],
            usedEscalationNotificationFallback: false
        )
        #expect(partialOutcome.schedulingResult(
            wantsAlarm: false,
            wantsEscalationAlarm: true,
            plannedKinds: [.baseNotification]
        ).failureMessage?.contains("升级提醒因本机排程预算未安排") == true)
    }

    @Test
    func globalBudgetUsesEachRequestsDueTimeAcrossTasks() {
        let start = Date(timeIntervalSince1970: 1_000)
        let first = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let second = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
        let policy = MedicationNotificationPolicy(maximumScheduledRequests: 2)
        let plan = policy.requestPlan(
            candidates: [
                MedicationReminderRequestCandidate(
                    taskID: first, dueAt: start.addingTimeInterval(60),
                    wantsAlarm: true, wantsEscalation: true,
                    escalationDueAt: start.addingTimeInterval(360)
                ),
                MedicationReminderRequestCandidate(
                    taskID: second, dueAt: start.addingTimeInterval(120),
                    wantsAlarm: false, wantsEscalation: false
                )
            ], occupiedRequestCount: 0,
            notificationAvailable: true, alarmAvailable: true
        )

        #expect(plan.assignments == [
            MedicationReminderRequestAssignment(taskID: first, kinds: [.baseAlarm]),
            MedicationReminderRequestAssignment(taskID: second, kinds: [.baseNotification])
        ])
        #expect(plan.deferredTaskIDs.isEmpty)
    }

    @Test
    func queuedCleanupReportsMissedEscalationWindow() {
        let dueAt = Date(timeIntervalSince1970: 1_000)
        let escalationAt = dueAt.addingTimeInterval(300)
        #expect(MedicationReminderRequestTiming.missedWindow(
            baseDueAt: dueAt, escalationDueAt: escalationAt,
            initialNow: escalationAt.addingTimeInterval(-1),
            schedulingNow: escalationAt,
            wantsEscalation: true
        ))
        #expect(!MedicationReminderRequestTiming.missedWindow(
            baseDueAt: dueAt, escalationDueAt: escalationAt,
            initialNow: escalationAt.addingTimeInterval(-2),
            schedulingNow: escalationAt.addingTimeInterval(-1),
            wantsEscalation: true
        ))
    }

    @Test
    func requestBudgetChoosesAvailableAlarmAndEscalationFallbacks() {
        let candidate = MedicationReminderRequestCandidate(
            taskID: UUID(), dueAt: Date(timeIntervalSince1970: 2_000),
            wantsAlarm: true, wantsEscalation: true
        )
        let policy = MedicationNotificationPolicy(maximumScheduledRequests: 2)

        let selectedAlarmWithTwoSlots = policy.requestPlan(
            candidates: [candidate], occupiedRequestCount: 0,
            notificationAvailable: true, alarmAvailable: true
        )
        #expect(selectedAlarmWithTwoSlots.assignments.first?.kinds == [.baseAlarm, .escalationAlarm])

        let noAlarm = policy.requestPlan(
            candidates: [candidate], occupiedRequestCount: 0,
            notificationAvailable: true, alarmAvailable: false
        )
        #expect(noAlarm.assignments.first?.kinds == [.baseNotification, .escalationNotification])

        let noNotification = policy.requestPlan(
            candidates: [candidate], occupiedRequestCount: 0,
            notificationAvailable: false, alarmAvailable: true
        )
        #expect(noNotification.assignments.first?.kinds == [.baseAlarm, .escalationAlarm])

        let noPermission = policy.requestPlan(
            candidates: [candidate], occupiedRequestCount: 0,
            notificationAvailable: false, alarmAvailable: false
        )
        #expect(noPermission.assignments.isEmpty)
        #expect(noPermission.unavailableTaskIDs == [candidate.taskID])

        let notificationOnly = MedicationReminderRequestCandidate(
            taskID: UUID(), dueAt: candidate.dueAt,
            wantsAlarm: false, wantsEscalation: false
        )
        let noBaseRoute = policy.requestPlan(
            candidates: [notificationOnly], occupiedRequestCount: 0,
            notificationAvailable: false, alarmAvailable: true
        )
        #expect(noBaseRoute.unavailableTaskIDs == [notificationOnly.taskID])
        #expect(noBaseRoute.deferredTaskIDs.isEmpty)
    }

    @Test @MainActor
    func partialEscalationFailureRetriesWithStableRequestIdentifiers() async {
        let state = ReminderRequestTestState()
        let executor = MedicationReminderRequestExecutor(
            addBaseNotification: {
                state.installed.insert("dose.stable-task")
                return true
            },
            addBaseAlarm: { false },
            addEscalationNotification: {
                if state.fallbackFails { return false }
                state.installed.insert("dose.escalation.stable-task")
                return true
            },
            addEscalationAlarm: {
                state.alarmAttempts += 1
                return false
            }
        )
        let kinds: [MedicationReminderRequestKind] = [.baseNotification, .escalationAlarm]

        let first = await executor.execute(kinds)
        #expect(first.baseScheduled)
        #expect(!first.escalationScheduled)
        #expect(first.failedKinds == [.escalationAlarm, .escalationNotification])
        #expect(state.installed == ["dose.stable-task"])
        state.fallbackFails = false
        let retried = await executor.execute(kinds)
        #expect(retried.baseScheduled && retried.escalationScheduled)
        #expect(retried.failedKinds == [.escalationAlarm])
        #expect(retried.usedEscalationNotificationFallback)
        #expect(state.installed == ["dose.stable-task", "dose.escalation.stable-task"])
        #expect(state.alarmAttempts == 2)
    }

    @Test @MainActor
    func failedBaseDoesNotAddMisleadingEscalation() async {
        var escalationAttempts = 0
        let executor = MedicationReminderRequestExecutor(
            addBaseNotification: { false },
            addBaseAlarm: { false },
            addEscalationNotification: {
                escalationAttempts += 1
                return true
            },
            addEscalationAlarm: {
                escalationAttempts += 1
                return true
            }
        )
        let outcome = await executor.execute([.baseNotification, .escalationAlarm])
        #expect(!outcome.baseScheduled)
        #expect(outcome.failedKinds == [.baseNotification])
        #expect(escalationAttempts == 0)
    }

    @Test @MainActor
    func selectedBaseAlarmFailureIsReportedDespiteNotificationFallback() async {
        let executor = MedicationReminderRequestExecutor(
            addBaseNotification: { true },
            addBaseAlarm: { false },
            addEscalationNotification: { true },
            addEscalationAlarm: { true }
        )

        let outcome = await executor.execute([.baseNotification, .baseAlarm])
        #expect(outcome.baseScheduled && outcome.escalationScheduled)
        #expect(outcome.failedKinds == [.baseAlarm])
        let result = outcome.schedulingResult(
            wantsAlarm: true,
            wantsEscalationAlarm: false,
            plannedKinds: [.baseNotification, .baseAlarm]
        )
        #expect(result.failureMessage?.contains("所选 iPhone 闹钟未安排") == true)
    }

    @Test @MainActor
    func baseAlarmFailureReusesItsReservedSlotForNotificationFallback() async {
        var notificationAttempts = 0
        let outcome = await MedicationReminderRequestExecutor(
            addBaseNotification: {
                notificationAttempts += 1
                return true
            },
            addBaseAlarm: { false },
            addEscalationNotification: { false },
            addEscalationAlarm: { false }
        ).execute([.baseAlarm])
        #expect(notificationAttempts == 1)
        #expect(outcome.baseScheduled)
        #expect(outcome.failedKinds == [.baseAlarm])
        #expect(outcome.schedulingResult(
            wantsAlarm: true,
            wantsEscalationAlarm: false,
            plannedKinds: [.baseAlarm]
        ).failureMessage?.contains("已改用普通通知") == true)
    }

    @Test @MainActor
    func simultaneousBaseAlarmAndEscalationFailureReportsBoth() async {
        let kinds: [MedicationReminderRequestKind] = [
            .baseNotification, .baseAlarm, .escalationAlarm
        ]
        let outcome = await MedicationReminderRequestExecutor(
            addBaseNotification: { true },
            addBaseAlarm: { false },
            addEscalationNotification: { false },
            addEscalationAlarm: { false }
        ).execute(kinds)
        let message = outcome.schedulingResult(
            wantsAlarm: true,
            wantsEscalationAlarm: true,
            plannedKinds: kinds
        ).failureMessage
        #expect(message?.contains("所选 iPhone 闹钟未安排") == true)
        #expect(message?.contains("升级提醒未能安排") == true)

        let unavailableEscalation = await MedicationReminderRequestExecutor(
            addBaseNotification: { true },
            addBaseAlarm: { false },
            addEscalationNotification: { false },
            addEscalationAlarm: { false }
        ).execute([.baseNotification, .escalationNotification])
        let unavailableMessage = unavailableEscalation.schedulingResult(
            wantsAlarm: false,
            wantsEscalationAlarm: true,
            plannedKinds: [.baseNotification, .escalationNotification]
        ).failureMessage
        #expect(unavailableMessage?.contains("升级提醒未能安排") == true)
        #expect(unavailableMessage?.contains("已改用普通通知") == false)
    }

    @Test @MainActor
    func unavailableAlarmPermissionReportsFallbackAsPartialResult() async {
        let candidate = MedicationReminderRequestCandidate(
            taskID: UUID(), dueAt: Date(timeIntervalSince1970: 2_000),
            wantsAlarm: true, wantsEscalation: true
        )
        let plan = MedicationNotificationPolicy(maximumScheduledRequests: 2).requestPlan(
            candidates: [candidate], occupiedRequestCount: 0,
            notificationAvailable: true, alarmAvailable: false
        )
        let kinds = plan.assignments[0].kinds
        let outcome = await MedicationReminderRequestExecutor(
            addBaseNotification: { true },
            addBaseAlarm: { Issue.record("Unavailable alarm must not be added"); return false },
            addEscalationNotification: { true },
            addEscalationAlarm: { Issue.record("Unavailable alarm must not be added"); return false }
        ).execute(kinds)
        let result = outcome.schedulingResult(
            wantsAlarm: candidate.wantsAlarm,
            wantsEscalationAlarm: candidate.wantsEscalation,
            plannedKinds: kinds
        )
        #expect(result.failureMessage?.contains("所选 iPhone 闹钟未安排") == true)
        #expect(result.failureMessage?.contains("升级闹钟未安排") == true)
        #expect(result.failureMessage?.contains("闹钟权限") == true)
    }

    @Test @MainActor
    func authorizationRefreshPreservesUnresolvedSystemWarning() async throws {
        let suite = try #require(UserDefaults(suiteName: "MedCue.ReminderWarning.\(UUID().uuidString)"))
        let message = "部分提醒未能同步到系统"
        suite.set(message, forKey: NotificationService.reminderSystemSyncMessageKey)
        defer {
            suite.removeObject(forKey: NotificationService.reminderSystemSyncMessageKey)
            suite.removeObject(forKey: NotificationService.reminderNotificationUnavailableMessageKey)
        }

        await NotificationService(defaults: suite).refreshAuthorizationStatus()

        #expect(suite.string(forKey: NotificationService.reminderSystemSyncMessageKey) == message)
    }

    @Test
    func successfulLocalRetryClearsOnlyItsResolvedWarning() {
        let recoveredTask = UUID()
        let stillPendingTask = UUID()
        var warnings = MedicationReminderSyncWarningState()
        warnings.replace(
            affectedTaskIDs: [recoveredTask, stillPendingTask],
            results: [
                recoveredTask: .unavailable(message: "所选 iPhone 闹钟未安排"),
                stillPendingTask: .unavailable(message: "另一项提醒未安排")
            ]
        )
        #expect(warnings.displayMessage?.contains("所选 iPhone 闹钟未安排") == true)

        warnings.replace(
            affectedTaskIDs: [recoveredTask],
            results: [recoveredTask: .scheduled]
        )
        #expect(warnings.displayMessage == "另一项提醒未安排")
        warnings.replace(
            affectedTaskIDs: [stillPendingTask],
            results: [stillPendingTask: .scheduled]
        )
        #expect(warnings.displayMessage == nil)
    }

    @Test
    func staleCancellationReadbackBlocksReplacementUntilRetry() {
        let first = UUID()
        let otherMedicationTask = UUID()
        let requested = Set([first])
        let staleNotification = MedicationReminderSystemIdentifiers.baseNotification(for: first)
        let unrelatedNotification = MedicationReminderSystemIdentifiers.baseNotification(
            for: otherMedicationTask
        )

        let blocked = MedicationReminderCancellationReadback.blockedTaskIDs(
            among: requested,
            remainingNotificationIDs: [staleNotification, unrelatedNotification],
            remainingAlarmIDs: []
        )
        #expect(blocked == requested)
        #expect(!MedicationReminderCancellationReadback.hasUnattributedFailure(
            among: requested,
            remainingNotificationIDs: [staleNotification],
            remainingAlarmIDs: []
        ))
        #expect(MedicationReminderCancellationReadback.hasUnattributedFailure(
            among: requested,
            remainingNotificationIDs: [staleNotification, unrelatedNotification],
            remainingAlarmIDs: []
        ))

        let afterRetry = MedicationReminderCancellationReadback.blockedTaskIDs(
            among: requested,
            remainingNotificationIDs: [unrelatedNotification],
            remainingAlarmIDs: []
        )
        #expect(afterRetry.isEmpty)
        #expect(MedicationReminderCancellationReadback.blockedTaskIDs(
            among: requested,
            remainingNotificationIDs: [],
            remainingAlarmIDs: [MedicationReminderSystemIdentifiers.escalationAlarm(for: first)]
        ) == requested)
    }
}
