import Foundation
import MedicationAdherenceCore
import SwiftData
import Testing
import UserNotifications
@testable import MedicationAdherenceApp

@Suite(.serialized)
struct ElderDoseSchedulingTests {
    @Test @MainActor
    func explicitDelayTargetUsesActionTimeForFutureDueAndOverdueTasks() {
        let occurredAt = Date(timeIntervalSince1970: 1_800_000_000)
        let target = occurredAt.addingTimeInterval(30 * 60)

        for offset in [TimeInterval(3_600), 0, -3_600] {
            let task = StoredDoseTask(
                medicationID: UUID(),
                dueAt: occurredAt.addingTimeInterval(offset),
                doseValue: 1,
                doseUnit: "片"
            )
            let duplicate = StoredDoseTask(
                medicationID: task.medicationID,
                dueAt: task.dueAt.addingTimeInterval(10),
                doseValue: 1,
                doseUnit: "片"
            )
            let transitions = DoseActionTransitionPlanner().makeTransitions(
                mutation: .delay,
                taskGroup: [task, duplicate],
                primaryTask: task,
                occurredAt: occurredAt,
                primaryReason: "稍后提醒",
                mergedReason: "合并提醒",
                delayedDueAt: target
            )

            #expect(transitions.count == 2)
            #expect(transitions.allSatisfy { $0.newDueAt == target })
            #expect(transitions.allSatisfy { $0.newRecordedAt == occurredAt })
            #expect(transitions.allSatisfy { $0.newStatus == .delayed })
            #expect(task.dueAt == occurredAt.addingTimeInterval(offset))
        }
    }

    @Test @MainActor
    func omittedDelayTargetPreservesCompleteModePlannedTimePolicy() throws {
        let occurredAt = Date(timeIntervalSince1970: 1_800_000_000)
        let task = StoredDoseTask(
            medicationID: UUID(),
            dueAt: occurredAt.addingTimeInterval(-3_600),
            doseValue: 1,
            doseUnit: "片"
        )
        let transition = try #require(DoseActionTransitionPlanner().makeTransitions(
            mutation: .delay,
            taskGroup: [task],
            primaryTask: task,
            occurredAt: occurredAt,
            primaryReason: "稍后提醒",
            mergedReason: "合并提醒"
        ).first)

        #expect(transition.newDueAt == task.dueAt.addingTimeInterval(30 * 60))
    }

    @Test @MainActor
    func explicitDelayTargetIsIgnoredForTakenAction() throws {
        let occurredAt = Date(timeIntervalSince1970: 1_800_000_000)
        let task = StoredDoseTask(
            medicationID: UUID(),
            dueAt: occurredAt.addingTimeInterval(-600),
            doseValue: 1,
            doseUnit: "片"
        )
        let transition = try #require(DoseActionTransitionPlanner().makeTransitions(
            mutation: .markTaken,
            taskGroup: [task],
            primaryTask: task,
            occurredAt: occurredAt,
            primaryReason: "已服用",
            mergedReason: "合并记录",
            delayedDueAt: occurredAt.addingTimeInterval(1_800)
        ).first)

        #expect(transition.newDueAt == task.dueAt)
        #expect(transition.newStatus == .taken)
    }

    @Test @MainActor
    func crossMidnightDelayPersistsTargetAndKeepsOriginalDoseIdentity() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        let occurredAt = try #require(calendar.date(from: DateComponents(
            year: 2026, month: 9, day: 5, hour: 23, minute: 50
        )))
        let target = occurredAt.addingTimeInterval(30 * 60)
        let container = try MedicationAdherenceModelContainer.make(isStoredInMemoryOnly: true)
        let context = ModelContext(container)
        context.autosaveEnabled = false
        let originalDueAt = occurredAt.addingTimeInterval(-3_600)
        let task = StoredDoseTask(
            medicationID: UUID(),
            dueAt: originalDueAt,
            doseValue: 2,
            doseUnit: "片"
        )
        let taskID = task.id
        let planID = task.planID
        let medicationID = task.medicationID
        context.insert(task)
        try context.save()

        try DoseActionPersistence().commit(
            DoseActionTransitionPlanner().makeTransitions(
                mutation: .delay,
                taskGroup: [task],
                primaryTask: task,
                occurredAt: occurredAt,
                primaryReason: "稍后提醒",
                mergedReason: "合并提醒",
                delayedDueAt: target
            ),
            in: context
        )

        let verificationContext = ModelContext(container)
        let persistedTask = try #require(verificationContext.fetch(FetchDescriptor<StoredDoseTask>()).first)
        let logs = try verificationContext.fetch(FetchDescriptor<StoredDoseActionLog>())
        let log = try #require(logs.first)
        #expect(persistedTask.id == taskID)
        #expect(persistedTask.planID == planID)
        #expect(persistedTask.medicationID == medicationID)
        #expect(persistedTask.doseValue == 2)
        #expect(persistedTask.doseUnit == "片")
        #expect(persistedTask.dueAt == target)
        #expect(persistedTask.status == .delayed)
        #expect(calendar.component(.day, from: persistedTask.dueAt) == 6)
        #expect(logs.count == 1)
        #expect(log.previousDueAt == originalDueAt)
        #expect(log.occurredAt == occurredAt)
        #expect(log.actionRaw == DoseActionKind.delay.rawValue)
    }

    @Test @MainActor
    func deniedNotificationAuthorizationDoesNotSubmitRequest() async {
        var submitted = false
        let scheduler = MedicationNotificationRequestScheduler(
            authorizationFailureMessage: { "通知未开启" },
            addRequest: { _ in submitted = true }
        )

        let result = await scheduler.schedule(makeRequest())

        #expect(result == .unavailable(message: "通知未开启"))
        #expect(!submitted)
    }

    @Test @MainActor
    func notificationAddFailureIsReturnedWithoutSuccess() async {
        var events: [String] = []
        let scheduler = MedicationNotificationRequestScheduler(
            authorizationFailureMessage: {
                events.append("authorization")
                return nil
            },
            addRequest: { _ in
                events.append("add")
                throw SyntheticReminderSchedulingError.unavailable
            }
        )

        let result = await scheduler.schedule(makeRequest())

        #expect(result == .unavailable(message: "提醒未安排，请稍后重试。"))
        #expect(events == ["authorization", "add"])
    }

    @Test @MainActor
    func scheduledResultFollowsAcceptedRequestAndPreservesPayload() async throws {
        let request = makeRequest()
        var submittedRequest: UNNotificationRequest?
        let scheduler = MedicationNotificationRequestScheduler(
            authorizationFailureMessage: { @MainActor in nil },
            addRequest: { @MainActor request in
                await Task.yield()
                submittedRequest = request
            }
        )

        let result = await scheduler.schedule(request)

        #expect(result == .scheduled)
        let submitted = try #require(submittedRequest)
        #expect(submitted === request)
        #expect(result.failureMessage == nil)
    }

    @Test @MainActor
    func delayedSyncReturnsPrimaryReminderFailureAndCancelsDuplicates() async {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let medication = StoredMedication(displayName: "测试药品", kind: .prescription, inputSource: .manual)
        let task = StoredDoseTask(medicationID: medication.id, dueAt: now.addingTimeInterval(1_800), doseValue: 1, doseUnit: "片", status: .delayed)
        let duplicate = StoredDoseTask(medicationID: medication.id, dueAt: task.dueAt, doseValue: 1, doseUnit: "片", status: .delayed)
        let failure = MedicationReminderSchedulingResult.unavailable(message: "通知未开启")
        var scheduledIDs: [UUID] = []
        var cancelledIDs: [UUID] = []
        let synchronizer = TodaySystemSurfaceSynchronizer(
            adapter: TodaySystemSurfaceAdapter(
                cancelReminder: { cancelledIDs.append($0) },
                scheduleReminder: { task, _, _ in
                    scheduledIDs.append(task.id)
                    return failure
                },
                endLiveActivity: { _ in },
                startLiveActivity: { _, _ in }
            ),
            medicationForTask: { _ in medication },
            deliveryMethodForTask: { _ in .notification },
            now: { now }
        )

        let result = await synchronizer.synchronize(.delayed([task, duplicate], primaryTaskID: task.id))

        #expect(result == .reminder(failure))
        #expect(scheduledIDs == [task.id])
        #expect(cancelledIDs == [duplicate.id])
    }

    @Test @MainActor
    func delayedSyncWithoutCurrentMedicationDoesNotClaimReminderScheduled() async {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let task = StoredDoseTask(medicationID: UUID(), dueAt: now.addingTimeInterval(1_800), doseValue: 1, doseUnit: "片", status: .delayed)
        var submitted = false
        let synchronizer = TodaySystemSurfaceSynchronizer(
            adapter: TodaySystemSurfaceAdapter(
                cancelReminder: { _ in },
                scheduleReminder: { _, _, _ in
                    submitted = true
                    return .scheduled
                },
                endLiveActivity: { _ in },
                startLiveActivity: { _, _ in }
            ),
            medicationForTask: { _ in nil },
            deliveryMethodForTask: { _ in .notification },
            now: { now }
        )

        let result = await synchronizer.synchronize(.delayed([task], primaryTaskID: task.id))

        #expect(result == .reminder(.unavailable(message: "提醒未安排，请重新查看这项用药。")))
        #expect(!submitted)
    }

    private func makeRequest() -> UNNotificationRequest {
        UNNotificationRequest(
            identifier: "elder-scheduling-test",
            content: UNMutableNotificationContent(),
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1_800, repeats: false)
        )
    }
}

private enum SyntheticReminderSchedulingError: Error {
    case unavailable
}
