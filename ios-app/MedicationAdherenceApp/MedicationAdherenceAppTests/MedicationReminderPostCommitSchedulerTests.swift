import Foundation
import MedicationAdherenceCore
import Testing
@testable import MedicationAdherenceApp

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
    func schedulingPlanSortsFutureEntriesAndCapsSystemRequests() {
        let medication = StoredMedication(
            displayName: "测试药",
            kind: .overTheCounter,
            inputSource: .manual
        )
        let now = Date(timeIntervalSince1970: 1_000)
        let tasks = [3_000.0, 500.0, 2_000.0, 4_000.0].map { timestamp in
            StoredDoseTask(
                medicationID: medication.id,
                dueAt: Date(timeIntervalSince1970: timestamp),
                doseValue: 1,
                doseUnit: "片"
            )
        }
        let explicitlyCancelled = UUID()
        let snapshot = MedicationReminderPostCommitSnapshot(batch: MedicationReminderScheduleBatch(
            medication: medication,
            deliveryMethod: .notification,
            escalatesToAlarmWhenUnhandled: true,
            tasks: tasks,
            cancelledTaskIDs: [explicitlyCancelled]
        ))

        let plan = snapshot.schedulingPlan(now: now, maximumScheduledEntries: 2)

        #expect(plan.entries.map(\.dueAt) == [
            Date(timeIntervalSince1970: 2_000),
            Date(timeIntervalSince1970: 3_000)
        ])
        #expect(plan.taskIDsToCancel.contains(explicitlyCancelled))
        #expect(plan.taskIDsToCancel.contains(tasks[3].id))
        #expect(plan.taskIDsToCancel.contains(tasks[1].id))
    }
}
