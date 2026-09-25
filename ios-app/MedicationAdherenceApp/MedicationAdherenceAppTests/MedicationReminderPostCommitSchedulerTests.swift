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
                kinds: [.baseNotification, .baseAlarm, .escalationAlarm]
            ),
            MedicationReminderRequestAssignment(
                taskID: second,
                kinds: [.baseNotification, .escalationAlarm]
            )
        ])
        #expect(plan.deferredTaskIDs == [third])
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
