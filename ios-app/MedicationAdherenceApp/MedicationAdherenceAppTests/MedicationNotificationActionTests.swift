import Foundation
import MedicationAdherenceCore
import SwiftData
import Testing
import UserNotifications
@testable import MedicationAdherenceApp

@Suite(.serialized)
struct MedicationNotificationActionTests {
    @Test @MainActor
    func delayFromNotificationUsesClickTimeForLateResponsesAndSchedulesCommittedTask() async throws {
        for elapsedMinutes in [20, 45] {
            let fixture = try NotificationDoseFixture()
            let occurredAt = fixture.plannedAt.addingTimeInterval(TimeInterval(elapsedMinutes * 60 + 59))
            let expectedDueAt = occurredAt.addingTimeInterval(30 * 60)
            let probe = NotificationActionProbe(container: fixture.container)

            let succeeded = await MedicationNotificationDelegate.shared.handleNotificationAction(
                "MEDICATION_DELAY_30_MINUTES",
                taskID: fixture.primary.id,
                in: fixture.context,
                occurredAt: occurredAt,
                effects: probe.effects()
            )

            #expect(succeeded)
            let saved = ModelContext(fixture.container)
            let tasks = try saved.fetch(FetchDescriptor<StoredDoseTask>())
            let logs = try saved.fetch(FetchDescriptor<StoredDoseActionLog>())
            #expect(tasks.count == 2)
            #expect(tasks.allSatisfy { $0.status == .delayed && $0.dueAt == expectedDueAt })
            #expect(logs.count == 2)
            #expect(logs.allSatisfy { $0.occurredAt == occurredAt })
            #expect(logs.first { $0.taskID == fixture.primary.id }?.note == "通过通知选择 30 分钟后提醒")
            #expect(probe.scheduled.count == 1)
            #expect(probe.scheduled.first?.0 == fixture.primary.id)
            #expect(probe.scheduled.first?.1 == expectedDueAt)
            #expect(probe.requestTriggerDates.count == 1)
            #expect(abs(try #require(probe.requestTriggerDates.first).timeIntervalSince(expectedDueAt)) < 1)
            #expect(probe.cancelled == [fixture.duplicate.id])
            #expect(Set(probe.ended) == Set([fixture.primary.id, fixture.duplicate.id]))
            #expect(probe.events.first == "schedule")
            #expect(probe.events.last == "start-next")
        }
    }

    @Test @MainActor
    func failedNotificationDelayDoesNotScheduleCancelOrEndActivity() async throws {
        let fixture = try NotificationDoseFixture()
        let probe = NotificationActionProbe(container: fixture.container)
        let persistence = DoseActionPersistence { _ in throw SyntheticNotificationSaveError.unavailable }

        let succeeded = await MedicationNotificationDelegate.shared.handleNotificationAction(
            "MEDICATION_DELAY_30_MINUTES",
            taskID: fixture.primary.id,
            in: fixture.context,
            occurredAt: fixture.plannedAt.addingTimeInterval(45 * 60),
            effects: probe.effects(),
            persistence: persistence
        )

        #expect(!succeeded)
        #expect(probe.events.isEmpty)
        let saved = ModelContext(fixture.container)
        let tasks = try saved.fetch(FetchDescriptor<StoredDoseTask>())
        let logs = try saved.fetch(FetchDescriptor<StoredDoseActionLog>())
        #expect(tasks.count == 2)
        #expect(tasks.allSatisfy { $0.status == .pending && $0.dueAt == fixture.plannedAt })
        #expect(logs.isEmpty)
    }

    @Test @MainActor
    func takenAndSkipNotificationsKeepExistingStateAndCancellation() async throws {
        for (identifier, status) in [
            ("MEDICATION_MARK_TAKEN", StoredDoseStatus.taken),
            ("MEDICATION_SKIP", StoredDoseStatus.skipped)
        ] {
            let fixture = try NotificationDoseFixture()
            let probe = NotificationActionProbe(container: fixture.container)
            let occurredAt = fixture.plannedAt.addingTimeInterval(20 * 60)
            let succeeded = await MedicationNotificationDelegate.shared.handleNotificationAction(
                identifier,
                taskID: fixture.primary.id,
                in: fixture.context,
                occurredAt: occurredAt,
                effects: probe.effects()
            )

            #expect(succeeded)
            let saved = ModelContext(fixture.container)
            let tasks = try saved.fetch(FetchDescriptor<StoredDoseTask>())
            let logs = try saved.fetch(FetchDescriptor<StoredDoseActionLog>())
            #expect(tasks.allSatisfy { $0.status == status && $0.dueAt == fixture.plannedAt })
            #expect(logs.count == 2)
            #expect(probe.scheduled.isEmpty)
            #expect(Set(probe.cancelled) == Set([fixture.primary.id, fixture.duplicate.id]))
            #expect(Set(probe.ended) == Set([fixture.primary.id, fixture.duplicate.id]))
            #expect(probe.events.last == "start-next")
        }
    }
}

@MainActor
private struct NotificationDoseFixture {
    let container: ModelContainer
    let context: ModelContext
    let plannedAt: Date
    let primary: StoredDoseTask
    let duplicate: StoredDoseTask

    init() throws {
        container = try MedicationAdherenceModelContainer.make(isStoredInMemoryOnly: true)
        context = ModelContext(container)
        context.autosaveEnabled = false
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        plannedAt = calendar.dateInterval(of: .hour, for: Date().addingTimeInterval(24 * 60 * 60))!.start
        let medication = StoredMedication(displayName: "合成测试药品", kind: .prescription, inputSource: .manual)
        primary = StoredDoseTask(medicationID: medication.id, dueAt: plannedAt, doseValue: 1, doseUnit: "片")
        duplicate = StoredDoseTask(medicationID: medication.id, dueAt: plannedAt, doseValue: 1, doseUnit: "片")
        context.insert(medication)
        context.insert(primary)
        context.insert(duplicate)
        try context.save()
    }
}

@MainActor
private final class NotificationActionProbe {
    let container: ModelContainer
    var scheduled: [(UUID, Date)] = []
    var requestTriggerDates: [Date] = []
    var cancelled: [UUID] = []
    var ended: [UUID] = []
    var events: [String] = []

    init(container: ModelContainer) {
        self.container = container
    }

    func effects() -> NotificationDoseActionEffects {
        NotificationDoseActionEffects(
            scheduleReminder: { task, _, _ in
                #expect(task.status == .delayed)
                let saved = ModelContext(self.container)
                let committed = try? saved.fetch(FetchDescriptor<StoredDoseTask>())
                    .first { $0.id == task.id }
                #expect(committed?.status == .delayed)
                #expect(committed?.dueAt == task.dueAt)
                let components = MedicationNotificationPolicy.default.triggerDateComponents(for: task.dueAt, calendar: .current)
                let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
                let request = UNNotificationRequest(identifier: task.id.uuidString, content: UNMutableNotificationContent(), trigger: trigger)
                if let triggerDate = (request.trigger as? UNCalendarNotificationTrigger)?.nextTriggerDate() {
                    self.requestTriggerDates.append(triggerDate)
                }
                self.scheduled.append((task.id, task.dueAt))
                self.events.append("schedule")
            },
            cancelReminder: { id in
                self.cancelled.append(id)
                self.events.append("cancel")
            },
            endLiveActivity: { id in
                self.ended.append(id)
                self.events.append("end")
            },
            startNextLiveActivity: { _ in self.events.append("start-next") }
        )
    }
}

private enum SyntheticNotificationSaveError: Error {
    case unavailable
}
