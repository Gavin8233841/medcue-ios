import Foundation
import MedicationAdherenceCore
import SwiftData
import Testing
@testable import MedicationAdherenceApp

@Suite(.serialized)
struct MedicationReminderTaskCoordinatorTests {
    @Test @MainActor
    func inactiveReconcileUsesReferenceDayForCancellationAndReportsSameTask() throws {
        let calendar = makeCalendar()
        let referenceDate = makeReferenceDate(calendar: calendar)
        let container = try MedicationAdherenceModelContainer.make(isStoredInMemoryOnly: true)
        let context = ModelContext(container)
        context.autosaveEnabled = false
        let medication = StoredMedication(
            displayName: "测试药",
            kind: .overTheCounter,
            inputSource: .manual,
            lifecycleStatus: .interrupted,
            createdAt: referenceDate
        )
        let plan = makePlan(
            medicationID: medication.id,
            reminderTime: "08:00",
            referenceDate: referenceDate,
            calendar: calendar
        )
        let task = StoredDoseTask(
            medicationID: medication.id,
            planID: plan.id,
            dueAt: calendar.date(bySettingHour: 8, minute: 0, second: 0, of: referenceDate)!,
            doseValue: 1,
            doseUnit: "片"
        )
        context.insert(medication)
        context.insert(plan)
        context.insert(task)
        try context.save()

        let outcome = MedicationReminderTaskCoordinator(
            calendar: calendar,
            referenceDate: referenceDate
        ).reconcileAllPlans(in: context)
        guard case let .reconciled(batches) = outcome else {
            Issue.record("停用药品协调不应读取失败")
            return
        }

        let batch = try #require(batches.first)
        #expect(batches.count == 1)
        #expect(batch.tasks.isEmpty)
        #expect(batch.cancelledTaskIDs == [task.id])
        #expect(task.status == .skipped)
        #expect(task.recordedAt == nil)
        #expect(task.reason == "药物已中断，未来提醒已停用。")
    }

    @Test(
        "Each required read failure stops before mutation, save, and system effects",
        arguments: MedicationReminderReconciliationReadStage.allCases
    )
    @MainActor
    func requiredReadFailureStopsBeforeMutation(
        stage: MedicationReminderReconciliationReadStage
    ) async throws {
        let calendar = makeCalendar()
        let referenceDate = makeReferenceDate(calendar: calendar)
        let container = try MedicationAdherenceModelContainer.make(isStoredInMemoryOnly: true)
        let context = ModelContext(container)
        context.autosaveEnabled = false
        let medication = StoredMedication(
            displayName: "读取失败测试药",
            kind: .overTheCounter,
            inputSource: .manual,
            createdAt: referenceDate
        )
        let firstPlan = makePlan(
            medicationID: medication.id,
            reminderTime: "08:00",
            referenceDate: referenceDate,
            calendar: calendar
        )
        let secondPlan = makePlan(
            medicationID: medication.id,
            reminderTime: "09:00",
            referenceDate: referenceDate,
            calendar: calendar
        )
        let existingDueAt = calendar.date(
            bySettingHour: 8,
            minute: 0,
            second: 0,
            of: calendar.date(byAdding: .day, value: 1, to: referenceDate)!
        )!
        let existingTask = StoredDoseTask(
            medicationID: medication.id,
            planID: firstPlan.id,
            dueAt: existingDueAt,
            doseValue: 99,
            doseUnit: "粒"
        )
        let existingLog = StoredDoseActionLog(
            taskID: existingTask.id,
            action: .markTaken,
            previousStatus: .pending,
            previousDueAt: existingDueAt,
            previousRecordedAt: nil,
            previousReason: "",
            newStatus: .taken,
            occurredAt: referenceDate,
            undoExpiresAt: referenceDate.addingTimeInterval(300)
        )
        let existingDoseChange = StoredMedicationDoseChange(
            medicationID: medication.id,
            planID: firstPlan.id,
            previousDoseValue: 99,
            previousDoseUnit: "粒",
            newDoseValue: 2,
            newDoseUnit: "片",
            effectiveFrom: calendar.startOfDay(for: referenceDate),
            changedAt: referenceDate,
            note: "合成测试数据"
        )
        context.insert(medication)
        context.insert(firstPlan)
        context.insert(secondPlan)
        context.insert(existingTask)
        context.insert(existingLog)
        context.insert(existingDoseChange)
        try context.save()

        medication.notes = "尚未保存的用户编辑"
        #expect(context.hasChanges)

        var saveCallCount = 0
        var cancelledTaskIDCalls: [[UUID]] = []
        var scheduledBatchCalls: [(count: Int, prune: Bool)] = []
        var refreshCallCount = 0
        let service = NotificationService(
            reminderTaskCoordinator: MedicationReminderTaskCoordinator(
                calendar: calendar,
                referenceDate: referenceDate,
                dataSource: makeDataSource(failing: stage)
            ),
            reconciliationSaveOperation: { _ in
                saveCallCount += 1
            },
            reconciliationSystemEffects: MedicationReminderReconciliationSystemEffects(
                cancelReminders: { cancelledTaskIDCalls.append($0) },
                scheduleReminderBatches: { batches, prune in
                    scheduledBatchCalls.append((batches.count, prune))
                },
                refreshPendingReminderCount: { refreshCallCount += 1 }
            )
        )

        let outcome = await service.reconcileAndScheduleReminders(in: context)

        #expect(outcome == .readFailed(stage))
        #expect(service.lastReminderReconciliationOutcome == .readFailed(stage))
        #expect(saveCallCount == 0)
        #expect(cancelledTaskIDCalls.isEmpty)
        #expect(scheduledBatchCalls.isEmpty)
        #expect(refreshCallCount == 0)
        #expect(medication.notes == "尚未保存的用户编辑")
        #expect(context.hasChanges)
        #expect(existingTask.status == .pending)
        #expect(existingTask.dueAt == existingDueAt)
        #expect(existingTask.doseValue == 99)
        #expect(existingTask.doseUnit == "粒")
        #expect(existingLog.undoneAt == nil)
        #expect(existingDoseChange.newDoseValue == 2)
        let tasks = try context.fetch(FetchDescriptor<StoredDoseTask>())
        #expect(tasks.map(\.id) == [existingTask.id])
    }

    @Test @MainActor
    func successfulEmptySnapshotStillCommitsAndPrunesLegitimateEmptyState() async throws {
        let container = try MedicationAdherenceModelContainer.make(isStoredInMemoryOnly: true)
        let context = ModelContext(container)
        context.autosaveEnabled = false
        var saveCallCount = 0
        var cancelledTaskIDCalls: [[UUID]] = []
        var scheduledBatchCalls: [(count: Int, prune: Bool)] = []
        var refreshCallCount = 0
        let service = NotificationService(
            reconciliationSaveOperation: { _ in
                saveCallCount += 1
            },
            reconciliationSystemEffects: MedicationReminderReconciliationSystemEffects(
                cancelReminders: { cancelledTaskIDCalls.append($0) },
                scheduleReminderBatches: { batches, prune in
                    scheduledBatchCalls.append((batches.count, prune))
                },
                refreshPendingReminderCount: { refreshCallCount += 1 }
            )
        )

        let outcome = await service.reconcileAndScheduleReminders(in: context)

        #expect(outcome == .committed)
        #expect(service.lastReminderReconciliationOutcome == .committed)
        #expect(saveCallCount == 1)
        #expect(cancelledTaskIDCalls == [[]])
        #expect(scheduledBatchCalls.count == 1)
        #expect(scheduledBatchCalls.first?.count == 0)
        #expect(scheduledBatchCalls.first?.prune == true)
        #expect(refreshCallCount == 1)
    }

    @Test @MainActor
    func saveFailureRollsBackReconciledTasksAndDoesNotApplySystemEffects() async throws {
        defer {
            UserDefaults.standard.removeObject(forKey: AppPersistenceCommitter.failureMessageDefaultsKey)
        }
        let calendar = makeCalendar()
        let referenceDate = makeReferenceDate(calendar: calendar)
        let container = try MedicationAdherenceModelContainer.make(isStoredInMemoryOnly: true)
        let context = ModelContext(container)
        context.autosaveEnabled = false
        let medication = StoredMedication(
            displayName: "保存失败测试药",
            kind: .overTheCounter,
            inputSource: .manual,
            createdAt: referenceDate
        )
        let plan = makePlan(
            medicationID: medication.id,
            reminderTime: "20:00",
            referenceDate: referenceDate,
            calendar: calendar
        )
        context.insert(medication)
        context.insert(plan)
        try context.save()

        var systemEffectCallCount = 0
        let service = NotificationService(
            reminderTaskCoordinator: MedicationReminderTaskCoordinator(
                calendar: calendar,
                referenceDate: referenceDate
            ),
            reconciliationSaveOperation: { _ in throw InjectedSaveFailure() },
            reconciliationSystemEffects: MedicationReminderReconciliationSystemEffects(
                cancelReminders: { _ in systemEffectCallCount += 1 },
                scheduleReminderBatches: { _, _ in systemEffectCallCount += 1 },
                refreshPendingReminderCount: { systemEffectCallCount += 1 }
            )
        )

        let outcome = await service.reconcileAndScheduleReminders(in: context)

        #expect(outcome == .saveFailed)
        #expect(service.lastReminderReconciliationOutcome == .saveFailed)
        #expect(systemEffectCallCount == 0)
        #expect(try context.fetch(FetchDescriptor<StoredDoseTask>()).isEmpty)
        #expect(!context.hasChanges)
    }

    @Test @MainActor
    func retryAfterReadFailureCreatesOneLogicalTaskSet() async throws {
        let calendar = makeCalendar()
        let referenceDate = makeReferenceDate(calendar: calendar)
        let container = try MedicationAdherenceModelContainer.make(isStoredInMemoryOnly: true)
        let context = ModelContext(container)
        context.autosaveEnabled = false
        let medication = StoredMedication(
            displayName: "重试测试药",
            kind: .overTheCounter,
            inputSource: .manual,
            createdAt: referenceDate
        )
        let plan = makePlan(
            medicationID: medication.id,
            reminderTime: "21:00",
            referenceDate: referenceDate,
            calendar: calendar
        )
        context.insert(medication)
        context.insert(plan)
        try context.save()

        let noSystemEffects = MedicationReminderReconciliationSystemEffects(
            cancelReminders: { _ in },
            scheduleReminderBatches: { _, _ in },
            refreshPendingReminderCount: {}
        )
        let failingService = NotificationService(
            reminderTaskCoordinator: MedicationReminderTaskCoordinator(
                calendar: calendar,
                referenceDate: referenceDate,
                dataSource: makeDataSource(failing: .doseChanges)
            ),
            reconciliationSaveOperation: { _ in },
            reconciliationSystemEffects: noSystemEffects
        )

        let failedOutcome = await failingService.reconcileAndScheduleReminders(in: context)
        #expect(failedOutcome == .readFailed(.doseChanges))
        #expect(failingService.lastReminderReconciliationOutcome == .readFailed(.doseChanges))
        #expect(try context.fetch(FetchDescriptor<StoredDoseTask>()).isEmpty)

        let retryingService = NotificationService(
            reminderTaskCoordinator: MedicationReminderTaskCoordinator(
                calendar: calendar,
                referenceDate: referenceDate
            ),
            reconciliationSaveOperation: { context in
                try context.save()
            },
            reconciliationSystemEffects: noSystemEffects
        )
        let firstRetryOutcome = await retryingService.reconcileAndScheduleReminders(in: context)
        #expect(firstRetryOutcome == .committed)
        #expect(retryingService.lastReminderReconciliationOutcome == .committed)
        let firstRetryTaskIDs = Set(try context.fetch(FetchDescriptor<StoredDoseTask>()).map(\.id))
        #expect(!firstRetryTaskIDs.isEmpty)

        let secondRetryOutcome = await retryingService.reconcileAndScheduleReminders(in: context)
        #expect(secondRetryOutcome == .committed)
        let secondRetryTaskIDs = Set(try context.fetch(FetchDescriptor<StoredDoseTask>()).map(\.id))
        #expect(secondRetryTaskIDs == firstRetryTaskIDs)
    }

    @MainActor
    private func makeDataSource(
        failing stage: MedicationReminderReconciliationReadStage
    ) -> MedicationReminderReconciliationDataSource {
        MedicationReminderReconciliationDataSource(
            fetchMedications: { context in
                if stage == .medications { throw InjectedReadFailure() }
                return try context.fetch(FetchDescriptor<StoredMedication>())
            },
            fetchPlans: { context in
                if stage == .plans { throw InjectedReadFailure() }
                return try context.fetch(FetchDescriptor<StoredMedicationPlan>())
            },
            fetchTasks: { context in
                if stage == .tasks { throw InjectedReadFailure() }
                return try context.fetch(FetchDescriptor<StoredDoseTask>())
            },
            fetchActionLogs: { context in
                if stage == .actionLogs { throw InjectedReadFailure() }
                return try context.fetch(FetchDescriptor<StoredDoseActionLog>())
            },
            fetchDoseChanges: { context in
                if stage == .doseChanges { throw InjectedReadFailure() }
                return try context.fetch(FetchDescriptor<StoredMedicationDoseChange>())
            }
        )
    }

    private func makeCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 8 * 60 * 60)!
        return calendar
    }

    private func makeReferenceDate(calendar: Calendar) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 9, day: 20, hour: 12))!
    }

    private func makePlan(
        medicationID: UUID,
        reminderTime: String,
        referenceDate: Date,
        calendar: Calendar
    ) -> StoredMedicationPlan {
        StoredMedicationPlan(
            medicationID: medicationID,
            doseValue: 1,
            doseUnit: "片",
            timingSummary: "每日 \(reminderTime)",
            timeZonePolicy: .localClock,
            sourceNote: "",
            courseStartAt: calendar.startOfDay(for: referenceDate),
            reminderTimesRaw: reminderTime,
            createdAt: referenceDate
        )
    }
}

private struct InjectedReadFailure: Error {}
private struct InjectedSaveFailure: Error {}
