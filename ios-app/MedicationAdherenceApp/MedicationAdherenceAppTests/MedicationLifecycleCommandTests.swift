import Foundation
import MedicationAdherenceCore
import SwiftData
import Testing
@testable import MedicationAdherenceApp

@Suite(.serialized)
struct MedicationLifecycleCommandTests {
    @Test @MainActor
    func interruptionCommitsLifecycleEventAndDisablesOnlyOpenFutureTasks() throws {
        let fixture = try MedicationLifecycleFixture()

        let outcome = MedicationLifecycleCommand(
            modelContext: fixture.context,
            calendar: fixture.calendar
        ).update(
            MedicationLifecycleUpdate(
                medicationID: fixture.medication.id,
                status: .interrupted,
                note: "用户标记中断",
                occurredAt: fixture.now
            )
        )

        guard case let .committed(commit) = outcome else {
            Issue.record("Expected lifecycle update to commit")
            return
        }
        #expect(fixture.medication.lifecycleStatus == .interrupted)
        #expect(commit.disabledTaskIDs == [fixture.futureOpen.id])
        #expect(commit.reminderBatches.isEmpty)
        #expect(fixture.futureOpen.status == .skipped)
        #expect(fixture.futureOpen.recordedAt == nil)
        #expect(fixture.futureOpen.reason == "药物已中断，未来提醒已停用。")
        #expect(fixture.pastOpen.status == .pending)
        #expect(fixture.futureTaken.status == .taken)
        let event = try #require(try fixture.context.fetch(FetchDescriptor<StoredMedicationLifecycleEvent>()).first)
        #expect(event.status == .interrupted)
        #expect(event.occurredAt == fixture.now)
        #expect(event.note == "用户标记中断")
    }

    @Test @MainActor
    func reactivationReconcilesPlansAndReturnsCommittedReminderBatches() throws {
        let fixture = try MedicationLifecycleFixture(initialStatus: .interrupted)
        fixture.futureOpen.status = .skipped
        fixture.futureOpen.reason = "药物已中断，未来提醒已停用。"
        try fixture.context.save()

        let outcome = MedicationLifecycleCommand(
            modelContext: fixture.context,
            calendar: fixture.calendar
        ).update(
            MedicationLifecycleUpdate(
                medicationID: fixture.medication.id,
                status: .active,
                note: "用户恢复服用",
                occurredAt: fixture.now
            )
        )

        guard case let .committed(commit) = outcome else {
            Issue.record("Expected lifecycle reactivation to commit")
            return
        }
        #expect(fixture.medication.lifecycleStatus == .active)
        #expect(commit.disabledTaskIDs.isEmpty)
        #expect(commit.reminderBatches.count == 1)
        #expect(commit.reminderBatches[0].medication.id == fixture.medication.id)
        #expect(!commit.reminderBatches[0].tasks.isEmpty)
        #expect(commit.reminderBatches[0].tasks.contains { $0.id == fixture.futureOpen.id })
        #expect(fixture.futureOpen.status == .pending)
        #expect(fixture.futureOpen.recordedAt == nil)
        #expect(fixture.futureOpen.reason.isEmpty)
    }

    @Test @MainActor
    func saveFailureRestoresMedicationAndEveryMutatedTask() throws {
        let fixture = try MedicationLifecycleFixture()
        let originalStatus = fixture.futureOpen.status
        let originalRecordedAt = fixture.futureOpen.recordedAt
        let originalReason = fixture.futureOpen.reason

        let outcome = MedicationLifecycleCommand(
            modelContext: fixture.context,
            calendar: fixture.calendar,
            saveOperation: { _ in throw SyntheticMedicationLifecycleSaveError.unavailable }
        ).update(
            MedicationLifecycleUpdate(
                medicationID: fixture.medication.id,
                status: .archived,
                note: "用户归档",
                occurredAt: fixture.now
            )
        )

        guard case .saveFailed = outcome else {
            Issue.record("Expected save failure")
            return
        }
        #expect(fixture.medication.lifecycleStatus == .active)
        #expect(fixture.futureOpen.status == originalStatus)
        #expect(fixture.futureOpen.recordedAt == originalRecordedAt)
        #expect(fixture.futureOpen.reason == originalReason)
        #expect(try fixture.context.fetch(FetchDescriptor<StoredMedicationLifecycleEvent>()).isEmpty)
        #expect(!fixture.context.hasChanges)
    }

    @Test @MainActor
    func unchangedStatusIsRejectedWithoutWriting() throws {
        let fixture = try MedicationLifecycleFixture()

        let outcome = MedicationLifecycleCommand(
            modelContext: fixture.context,
            calendar: fixture.calendar
        ).update(
            MedicationLifecycleUpdate(
                medicationID: fixture.medication.id,
                status: .active,
                note: "重复状态",
                occurredAt: fixture.now
            )
        )

        guard case .rejected(.unchangedStatus) = outcome else {
            Issue.record("Expected unchanged status rejection")
            return
        }
        #expect(try fixture.context.fetch(FetchDescriptor<StoredMedicationLifecycleEvent>()).isEmpty)
    }
}

private enum SyntheticMedicationLifecycleSaveError: Error {
    case unavailable
}

@MainActor
private struct MedicationLifecycleFixture {
    let container: ModelContainer
    let context: ModelContext
    let calendar: Calendar
    let now: Date
    let medication: StoredMedication
    let plan: StoredMedicationPlan
    let futureOpen: StoredDoseTask
    let pastOpen: StoredDoseTask
    let futureTaken: StoredDoseTask

    init(initialStatus: StoredMedicationLifecycleStatus = .active) throws {
        var configuredCalendar = Calendar(identifier: .gregorian)
        configuredCalendar.timeZone = TimeZone(secondsFromGMT: 8 * 60 * 60)!
        calendar = configuredCalendar
        now = configuredCalendar.date(from: DateComponents(year: 2026, month: 7, day: 26, hour: 12))!
        container = try ModelContainer(
            for: StoredMedication.self,
            StoredMedicationPlan.self,
            StoredDoseTask.self,
            StoredMedicationLifecycleEvent.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        context = ModelContext(container)
        medication = StoredMedication(
            displayName: "测试药",
            kind: .overTheCounter,
            inputSource: .manual,
            lifecycleStatus: initialStatus,
            createdAt: now.addingTimeInterval(-86_400)
        )
        plan = StoredMedicationPlan(
            medicationID: medication.id,
            doseValue: 1,
            doseUnit: "片",
            timingSummary: "每日 20:00",
            timeZonePolicy: .localClock,
            sourceNote: "",
            courseStartAt: configuredCalendar.startOfDay(for: now),
            courseEndAt: configuredCalendar.date(byAdding: .day, value: 2, to: now),
            reminderTimesRaw: "20:00"
        )
        futureOpen = StoredDoseTask(
            medicationID: medication.id,
            planID: plan.id,
            dueAt: configuredCalendar.date(byAdding: .hour, value: 8, to: now)!,
            doseValue: 1,
            doseUnit: "片",
            status: .pending,
            reason: "原未来说明"
        )
        pastOpen = StoredDoseTask(
            medicationID: medication.id,
            planID: plan.id,
            dueAt: configuredCalendar.date(byAdding: .day, value: -1, to: now)!,
            doseValue: 1,
            doseUnit: "片",
            status: .pending
        )
        futureTaken = StoredDoseTask(
            medicationID: medication.id,
            planID: plan.id,
            dueAt: configuredCalendar.date(byAdding: .day, value: 1, to: now)!,
            doseValue: 1,
            doseUnit: "片",
            status: .taken,
            recordedAt: now
        )
        context.insert(medication)
        context.insert(plan)
        [futureOpen, pastOpen, futureTaken].forEach(context.insert)
        try context.save()
    }
}
