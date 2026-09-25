import Foundation
import MedicationAdherenceCore
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
        #expect(oneSlotLeft.assignments.isEmpty)
        #expect(oneSlotLeft.deferredTaskIDs.count == 4)
    }

    @Test
    func requestBudgetChoosesAvailableAlarmAndEscalationFallbacks() {
        let candidate = MedicationReminderRequestCandidate(
            taskID: UUID(), dueAt: Date(timeIntervalSince1970: 2_000),
            wantsAlarm: true, wantsEscalation: true
        )
        let policy = MedicationNotificationPolicy(maximumScheduledRequests: 2)

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

        #expect(await executor.execute(kinds) == .escalationFailed)
        #expect(state.installed == ["dose.stable-task"])
        state.fallbackFails = false
        #expect(await executor.execute(kinds) == .scheduled)
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
        #expect(await executor.execute([.baseNotification, .escalationAlarm]) == .baseFailed)
        #expect(escalationAttempts == 0)
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
