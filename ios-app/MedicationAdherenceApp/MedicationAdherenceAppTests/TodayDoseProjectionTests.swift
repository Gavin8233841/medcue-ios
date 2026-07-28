import Foundation
import MedicationAdherenceCore
import Testing
@testable import MedicationAdherenceApp

@Suite(.serialized)
struct TodayDoseProjectionTests {
    @Test @MainActor
    func systemSurfaceSynchronizerEndsHandledDoseSurfacesAfterCommit() async {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let medication = StoredMedication(
            displayName: "测试药品",
            kind: .prescription,
            inputSource: .manual
        )
        let primary = StoredDoseTask(
            medicationID: medication.id,
            dueAt: now,
            doseValue: 1,
            doseUnit: "片",
            status: .taken,
            recordedAt: now
        )
        let duplicate = StoredDoseTask(
            medicationID: medication.id,
            dueAt: now.addingTimeInterval(10),
            doseValue: 1,
            doseUnit: "片",
            status: .skipped,
            recordedAt: now
        )
        let recorder = TodaySystemSurfaceRecorder()
        let synchronizer = TodaySystemSurfaceSynchronizer(
            adapter: recorder.adapter,
            medicationForTask: { _ in medication },
            deliveryMethodForTask: { _ in .notification },
            now: { now }
        )

        await synchronizer.synchronize(.handled([primary, duplicate]))

        #expect(recorder.events == [
            .cancelReminder(primary.id),
            .endLiveActivity(primary.id),
            .cancelReminder(duplicate.id),
            .endLiveActivity(duplicate.id)
        ])
    }

    @Test @MainActor
    func systemSurfaceSynchronizerReopensOnlyThePrimaryLogicalDoseReminder() async {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let medication = StoredMedication(
            displayName: "测试药品",
            kind: .prescription,
            inputSource: .manual
        )
        let primary = StoredDoseTask(
            medicationID: medication.id,
            dueAt: now.addingTimeInterval(600),
            doseValue: 1,
            doseUnit: "片"
        )
        let duplicate = StoredDoseTask(
            medicationID: medication.id,
            dueAt: now.addingTimeInterval(610),
            doseValue: 1,
            doseUnit: "片"
        )
        let recorder = TodaySystemSurfaceRecorder()
        let synchronizer = TodaySystemSurfaceSynchronizer(
            adapter: recorder.adapter,
            medicationForTask: { _ in medication },
            deliveryMethodForTask: { _ in .notification },
            now: { now }
        )

        await synchronizer.synchronize(
            .reopened([primary, duplicate], primaryTaskID: primary.id)
        )

        #expect(recorder.events == [
            .scheduleReminder(primary.id),
            .endLiveActivity(primary.id),
            .cancelReminder(duplicate.id),
            .endLiveActivity(duplicate.id)
        ])
    }

    @Test @MainActor
    func systemSurfaceSynchronizerReschedulesOnlyThePrimaryDelayedDose() async {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let medication = StoredMedication(
            displayName: "测试药品",
            kind: .prescription,
            inputSource: .manual
        )
        let primary = StoredDoseTask(
            medicationID: medication.id,
            dueAt: now.addingTimeInterval(1_800),
            doseValue: 1,
            doseUnit: "片",
            status: .delayed
        )
        let duplicate = StoredDoseTask(
            medicationID: medication.id,
            dueAt: now.addingTimeInterval(1_810),
            doseValue: 1,
            doseUnit: "片",
            status: .skipped,
            recordedAt: now
        )
        let recorder = TodaySystemSurfaceRecorder()
        let synchronizer = TodaySystemSurfaceSynchronizer(
            adapter: recorder.adapter,
            medicationForTask: { _ in medication },
            deliveryMethodForTask: { _ in .notification },
            now: { now }
        )

        await synchronizer.synchronize(
            .delayed([primary, duplicate], primaryTaskID: primary.id)
        )

        #expect(recorder.events == [
            .endLiveActivity(primary.id),
            .scheduleReminder(primary.id),
            .endLiveActivity(duplicate.id),
            .cancelReminder(duplicate.id)
        ])
    }

    @Test @MainActor
    func systemSurfaceSynchronizerRestoresOnlyEligiblePrimarySurfacesDuringRollback() async {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let medication = StoredMedication(
            displayName: "测试药品",
            kind: .prescription,
            inputSource: .manual
        )
        let primary = StoredDoseTask(
            medicationID: medication.id,
            dueAt: now.addingTimeInterval(600),
            doseValue: 1,
            doseUnit: "片"
        )
        let duplicate = StoredDoseTask(
            medicationID: medication.id,
            dueAt: now.addingTimeInterval(610),
            doseValue: 1,
            doseUnit: "片",
            status: .taken,
            recordedAt: now
        )
        let recorder = TodaySystemSurfaceRecorder()
        let synchronizer = TodaySystemSurfaceSynchronizer(
            adapter: recorder.adapter,
            medicationForTask: { _ in medication },
            deliveryMethodForTask: { _ in .notification },
            now: { now }
        )

        await synchronizer.synchronize(
            .rollback([primary, duplicate], primaryTaskID: primary.id)
        )

        #expect(recorder.events == [
            .scheduleReminder(primary.id),
            .startLiveActivity(primary.id),
            .cancelReminder(duplicate.id),
            .endLiveActivity(duplicate.id)
        ])
    }

    @Test @MainActor
    func interactionStatePublishesProjectionTransitionAndResetsTransientVisuals() {
        let state = TodayDoseInteractionState()
        let doseKey = "dose-key"
        state.pendingDoseFeedback = PendingDoseFeedback(doseKey: doseKey, action: .taken)
        state.closingOpenDoseKeys = [doseKey]
        state.reopeningHandledDoseKeys = ["reopening-dose"]
        state.recentlyReopenedDoseKeys = ["recent-dose"]
        state.isHandledTimelineTemporarilyCollapsed = true
        state.handledDropTargetPulse = true
        state.pendingHandledArrivalCount = 1

        #expect(state.isAnimationActive)
        #expect(state.projectionTransition == TodayDoseProjectionTransition(
            pendingDoseFeedback: PendingDoseFeedback(doseKey: doseKey, action: .taken),
            closingOpenDoseKeys: [doseKey],
            reopeningHandledDoseKeys: ["reopening-dose"],
            recentlyReopenedDoseKeys: ["recent-dose"],
            isHandledTimelineTemporarilyCollapsed: true,
            handledDropTargetPulse: true,
            pendingHandledArrivalCount: 1
        ))

        state.resetTransientVisuals()

        #expect(!state.isAnimationActive)
        #expect(state.projectionTransition.recentlyReopenedDoseKeys == ["recent-dose"])
        #expect(state.projectionTransition.pendingDoseFeedback == nil)
        #expect(state.projectionTransition.closingOpenDoseKeys.isEmpty)
        #expect(state.projectionTransition.reopeningHandledDoseKeys.isEmpty)
    }

    @Test @MainActor
    func interactionStateCancelsScheduledTransitionsAsOneLifecycleOperation() {
        let state = TodayDoseInteractionState()
        let feedbackTask = Task<Void, Never> {
            try? await Task.sleep(for: .seconds(30))
        }
        let layoutTask = Task<Void, Never> {
            try? await Task.sleep(for: .seconds(30))
        }
        state.pendingDoseFeedbackTask = feedbackTask
        state.doseLayoutTransitionTask = layoutTask

        #expect(state.isAnimationActive)

        state.cancelScheduledTransitions()

        #expect(feedbackTask.isCancelled)
        #expect(layoutTask.isCancelled)
        #expect(state.pendingDoseFeedbackTask == nil)
        #expect(state.doseLayoutTransitionTask == nil)
        #expect(!state.isAnimationActive)
    }

    @Test @MainActor
    func projectionIncludesOnlyActiveMedicationTasksForToday() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let activeMedication = StoredMedication(
            displayName: "测试药品",
            kind: .prescription,
            inputSource: .manual
        )
        let inactiveMedication = StoredMedication(
            displayName: "已停用药品",
            kind: .prescription,
            inputSource: .manual,
            lifecycleStatus: .interrupted
        )
        let pendingTask = StoredDoseTask(
            medicationID: activeMedication.id,
            dueAt: now.addingTimeInterval(3_600),
            doseValue: 1,
            doseUnit: "片"
        )
        let takenTask = StoredDoseTask(
            medicationID: activeMedication.id,
            dueAt: now.addingTimeInterval(-3_600),
            doseValue: 1,
            doseUnit: "片",
            status: .taken,
            recordedAt: now.addingTimeInterval(-3_500)
        )
        let inactiveTask = StoredDoseTask(
            medicationID: inactiveMedication.id,
            dueAt: now.addingTimeInterval(7_200),
            doseValue: 1,
            doseUnit: "片"
        )

        let projection = TodayDoseProjectionStore().projection(
            for: TodayDoseProjectionInput(
                tasks: [inactiveTask, takenTask, pendingTask],
                medications: [inactiveMedication, activeMedication],
                now: now,
                calendar: calendar
            )
        )

        #expect(projection.visibleOpenTimelineTasks.map(\.id) == [pendingTask.id])
        #expect(projection.handledTodayTasks.map(\.id) == [takenTask.id])
        #expect(projection.archivedTodayTasks.isEmpty)
        #expect(projection.nextReminderTask?.id == pendingTask.id)
        #expect(projection.completionRateSnapshot == CompletionRateSnapshot(completedCount: 1, totalCount: 2))
    }

    @Test @MainActor
    func transitionStateInvalidatesCacheWithoutDoubleCountingHandledDose() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let medication = StoredMedication(
            displayName: "测试药品",
            kind: .prescription,
            inputSource: .manual
        )
        let task = StoredDoseTask(
            medicationID: medication.id,
            dueAt: now.addingTimeInterval(-60),
            doseValue: 1,
            doseUnit: "片",
            status: .taken,
            recordedAt: now
        )
        let doseKey = DoseLogicalGroup.key(for: task)
        let store = TodayDoseProjectionStore()
        let settledProjection = store.projection(
            for: TodayDoseProjectionInput(
                tasks: [task],
                medications: [medication],
                now: now,
                calendar: calendar
            )
        )

        let transitioningProjection = store.projection(
            for: TodayDoseProjectionInput(
                tasks: [task],
                medications: [medication],
                now: now,
                calendar: calendar,
                transition: TodayDoseProjectionTransition(
                    pendingDoseFeedback: PendingDoseFeedback(
                        doseKey: doseKey,
                        action: .taken
                    ),
                    closingOpenDoseKeys: [doseKey],
                    pendingHandledArrivalCount: 1
                )
            )
        )

        #expect(settledProjection.visibleOpenTimelineTasks.isEmpty)
        #expect(settledProjection.displayedHandledCount == 1)
        #expect(transitioningProjection.visibleOpenTimelineTasks.map(\.id) == [task.id])
        #expect(transitioningProjection.handledTodayTasks.map(\.id) == [task.id])
        #expect(transitioningProjection.displayedOpenCount == 1)
        #expect(transitioningProjection.displayedHandledCount == 1)
    }

    @Test @MainActor
    func duplicateLogicalDoseIsCountedOnceUsingRecordedResult() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let medication = StoredMedication(
            displayName: "测试药品",
            kind: .prescription,
            inputSource: .manual
        )
        let dueAt = now.addingTimeInterval(-600)
        let pendingDuplicate = StoredDoseTask(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000101")!,
            medicationID: medication.id,
            dueAt: dueAt,
            doseValue: 1,
            doseUnit: "片"
        )
        let recordedDuplicate = StoredDoseTask(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000102")!,
            medicationID: medication.id,
            dueAt: dueAt.addingTimeInterval(10),
            doseValue: 1,
            doseUnit: "片",
            status: .taken,
            recordedAt: now.addingTimeInterval(-500)
        )

        let projection = TodayDoseProjectionStore().projection(
            for: TodayDoseProjectionInput(
                tasks: [pendingDuplicate, recordedDuplicate],
                medications: [medication],
                now: now,
                calendar: calendar
            )
        )

        #expect(projection.visibleOpenTimelineTasks.isEmpty)
        #expect(projection.handledTodayTasks.map(\.id) == [recordedDuplicate.id])
        #expect(projection.nextReminderTask?.id == nil)
        #expect(projection.completionRateSnapshot == CompletionRateSnapshot(completedCount: 1, totalCount: 1))
    }

    @Test @MainActor
    func projectionOrdersTimelinesAndSummarizesMostRecentHandledDose() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let ibuprofen = StoredMedication(
            displayName: "布洛芬",
            kind: .overTheCounter,
            inputSource: .manual
        )
        let acetaminophen = StoredMedication(
            displayName: "对乙酰氨基酚",
            kind: .overTheCounter,
            inputSource: .manual
        )
        let laterOpenTask = StoredDoseTask(
            medicationID: acetaminophen.id,
            dueAt: now.addingTimeInterval(7_200),
            doseValue: 1,
            doseUnit: "片"
        )
        let earlierOpenTask = StoredDoseTask(
            medicationID: ibuprofen.id,
            dueAt: now.addingTimeInterval(3_600),
            doseValue: 1,
            doseUnit: "片"
        )
        let olderHandledTask = StoredDoseTask(
            medicationID: acetaminophen.id,
            dueAt: now.addingTimeInterval(-7_200),
            doseValue: 1,
            doseUnit: "片",
            status: .taken,
            recordedAt: now.addingTimeInterval(-1_800)
        )
        let newerHandledTask = StoredDoseTask(
            medicationID: ibuprofen.id,
            dueAt: now.addingTimeInterval(-3_600),
            doseValue: 1,
            doseUnit: "片",
            status: .taken,
            recordedAt: now.addingTimeInterval(-900)
        )

        let projection = TodayDoseProjectionStore().projection(
            for: TodayDoseProjectionInput(
                tasks: [
                    laterOpenTask,
                    olderHandledTask,
                    earlierOpenTask,
                    newerHandledTask
                ],
                medications: [acetaminophen, ibuprofen],
                now: now,
                calendar: calendar
            )
        )

        #expect(projection.visibleOpenTimelineTasks.map(\.id) == [
            earlierOpenTask.id,
            laterOpenTask.id
        ])
        #expect(projection.handledTodayTasks.map(\.id) == [
            newerHandledTask.id,
            olderHandledTask.id
        ])
        #expect(projection.handledSummaryText == "已服用 · 布洛芬")
        #expect(projection.nextReminderTask?.id == earlierOpenTask.id)
    }

    @Test @MainActor
    func taskRevisionInvalidatesCachedProjection() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let medication = StoredMedication(
            displayName: "测试药品",
            kind: .prescription,
            inputSource: .manual
        )
        let task = StoredDoseTask(
            medicationID: medication.id,
            dueAt: now.addingTimeInterval(600),
            doseValue: 1,
            doseUnit: "片"
        )
        let store = TodayDoseProjectionStore()
        let pendingProjection = store.projection(
            for: TodayDoseProjectionInput(
                tasks: [task],
                medications: [medication],
                now: now,
                calendar: calendar
            )
        )

        task.status = .taken
        task.recordedAt = now
        let handledProjection = store.projection(
            for: TodayDoseProjectionInput(
                tasks: [task],
                medications: [medication],
                now: now,
                calendar: calendar
            )
        )

        #expect(pendingProjection.visibleOpenTimelineTasks.map(\.id) == [task.id])
        #expect(pendingProjection.handledTodayTasks.isEmpty)
        #expect(handledProjection.visibleOpenTimelineTasks.isEmpty)
        #expect(handledProjection.handledTodayTasks.map(\.id) == [task.id])
    }

    @Test @MainActor
    func crossingDueTimeWithinSameMinuteInvalidatesCachedProjection() {
        let beforeDue = Date(timeIntervalSince1970: 1_800_000_010)
        let dueAt = beforeDue.addingTimeInterval(20)
        let afterDue = beforeDue.addingTimeInterval(30)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let medication = StoredMedication(
            displayName: "测试药品",
            kind: .prescription,
            inputSource: .manual
        )
        let task = StoredDoseTask(
            medicationID: medication.id,
            dueAt: dueAt,
            doseValue: 1,
            doseUnit: "片"
        )
        let store = TodayDoseProjectionStore()

        let beforeProjection = store.projection(
            for: TodayDoseProjectionInput(
                tasks: [task],
                medications: [medication],
                now: beforeDue,
                calendar: calendar
            )
        )
        let afterProjection = store.projection(
            for: TodayDoseProjectionInput(
                tasks: [task],
                medications: [medication],
                now: afterDue,
                calendar: calendar
            )
        )

        #expect(beforeProjection.nextReminderTask?.id == task.id)
        #expect(beforeProjection.overdueOpenTaskCount == 0)
        #expect(afterProjection.nextReminderTask == nil)
        #expect(afterProjection.overdueOpenTaskCount == 1)
    }

    @Test @MainActor
    func projectionOwnsLogicalDoseCompletionReplacement() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let medication = StoredMedication(
            displayName: "测试药品",
            kind: .prescription,
            inputSource: .manual
        )
        let firstTask = StoredDoseTask(
            medicationID: medication.id,
            dueAt: now.addingTimeInterval(600),
            doseValue: 1,
            doseUnit: "片"
        )
        let duplicateTask = StoredDoseTask(
            medicationID: medication.id,
            dueAt: now.addingTimeInterval(610),
            doseValue: 1,
            doseUnit: "片"
        )

        let projection = TodayDoseProjectionStore().projection(
            for: TodayDoseProjectionInput(
                tasks: [duplicateTask, firstTask],
                medications: [medication],
                now: now,
                calendar: calendar
            )
        )
        let projectedCompletion = projection.completionRateSnapshot(
            replacingDoseKey: DoseLogicalGroup.key(for: firstTask),
            with: .taken
        )

        #expect(projection.eligibleTodayTasks.count == 2)
        #expect(projection.displayTodayTasks.count == 1)
        #expect(projection.completionRateSnapshot == CompletionRateSnapshot(completedCount: 0, totalCount: 1))
        #expect(projectedCompletion == CompletionRateSnapshot(completedCount: 1, totalCount: 1))
    }
}

@MainActor
private final class TodaySystemSurfaceRecorder {
    enum Event: Equatable {
        case cancelReminder(UUID)
        case scheduleReminder(UUID)
        case endLiveActivity(UUID)
        case startLiveActivity(UUID)
    }

    private(set) var events: [Event] = []

    var adapter: TodaySystemSurfaceAdapter {
        TodaySystemSurfaceAdapter(
            cancelReminder: { [weak self] taskID in
                self?.events.append(.cancelReminder(taskID))
            },
            scheduleReminder: { [weak self] task, _, _ in
                self?.events.append(.scheduleReminder(task.id))
            },
            endLiveActivity: { [weak self] taskID in
                self?.events.append(.endLiveActivity(taskID))
            },
            startLiveActivity: { [weak self] task, _ in
                self?.events.append(.startLiveActivity(task.id))
            }
        )
    }
}
