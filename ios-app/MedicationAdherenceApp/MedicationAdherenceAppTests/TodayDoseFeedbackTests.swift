import Foundation
import Testing
@testable import MedicationAdherenceApp

struct TodayDoseFeedbackTests {
    @Test
    func takenSuccessRequiresOneSuccessfulCommit() {
        var state = TodayDoseFeedbackState()
        let request = state.begin(.taken)
        #expect(state.finishCommit(request, succeeded: true) == .success)
        #expect(state.finishCommit(request, succeeded: true) == nil)
        #expect(state.finishReminder(request, scheduled: true, recordIsCurrent: true) == nil)
    }

    @Test(arguments: [
        TodayDoseFeedbackAction.taken, .delayed, .skipped, .reopened, .rollback
    ])
    func failedOrRejectedSaveIsSilent(action: TodayDoseFeedbackAction) {
        var state = TodayDoseFeedbackState()
        let request = state.begin(action)
        #expect(state.finishCommit(request, succeeded: false) == nil)
        #expect(state.finishCommit(request, succeeded: true) == nil)
        #expect(state.finishReminder(request, scheduled: true, recordIsCurrent: true) == nil)
    }

    @Test(arguments: [
        TodayDoseFeedbackAction.skipped, .reopened, .rollback
    ])
    func correctiveActionsAreAcknowledgements(action: TodayDoseFeedbackAction) {
        var state = TodayDoseFeedbackState()
        let request = state.begin(action)
        #expect(state.finishCommit(request, succeeded: true) == .acknowledgement)
        #expect(state.finishCommit(request, succeeded: true) == nil)
    }

    @Test
    func delaySaveDoesNotPromiseThatReminderWasScheduled() {
        var state = TodayDoseFeedbackState()
        let request = state.begin(.delayed)
        #expect(state.finishCommit(request, succeeded: true) == nil)
        #expect(state.finishReminder(request, scheduled: true, recordIsCurrent: true) == .success)
        #expect(state.finishReminder(request, scheduled: true, recordIsCurrent: true) == nil)
    }

    @Test
    func unavailableReminderNeverEmitsSuccessOrReplays() {
        var state = TodayDoseFeedbackState()
        let request = state.begin(.delayed)
        #expect(state.finishCommit(request, succeeded: true) == nil)
        #expect(state.finishReminder(request, scheduled: false, recordIsCurrent: true) == nil)
        #expect(state.finishReminder(request, scheduled: true, recordIsCurrent: true) == nil)
    }

    @Test
    func reminderCannotAcknowledgeAnUncommittedAction() {
        var state = TodayDoseFeedbackState()
        let request = state.begin(.delayed)
        #expect(state.finishReminder(request, scheduled: true, recordIsCurrent: true) == nil)
        #expect(state.finishCommit(request, succeeded: false) == nil)
        #expect(state.finishReminder(request, scheduled: true, recordIsCurrent: true) == nil)
    }

    @Test
    func aNewActionSuppressesThePreviousReminderCompletion() {
        var state = TodayDoseFeedbackState()
        let previous = state.begin(.delayed)
        #expect(state.finishCommit(previous, succeeded: true) == nil)
        let current = state.begin(.taken)
        #expect(state.finishReminder(previous, scheduled: true, recordIsCurrent: true) == nil)
        #expect(state.finishCommit(current, succeeded: true) == .success)
        #expect(state.finishReminder(previous, scheduled: true, recordIsCurrent: true) == nil)
    }

    @Test
    func anOldSaveCannotConsumeTheNewAction() {
        var state = TodayDoseFeedbackState()
        let previous = state.begin(.taken)
        let current = state.begin(.reopened)
        #expect(state.finishCommit(previous, succeeded: true) == nil)
        #expect(state.finishCommit(current, succeeded: true) == .acknowledgement)
    }

    @Test
    func leavingTheScreenInvalidatesPendingFeedback() {
        var state = TodayDoseFeedbackState()
        let request = state.begin(.delayed)
        #expect(state.finishCommit(request, succeeded: true) == nil)
        state.cancel()
        #expect(state.finishReminder(request, scheduled: true, recordIsCurrent: true) == nil)
        #expect(state.finishCommit(request, succeeded: true) == nil)
        let next = state.begin(.taken)
        #expect(state.finishCommit(next, succeeded: true) == .success)
    }

    @Test
    func cancellationBeforeCommitIsSilent() {
        var state = TodayDoseFeedbackState()
        let request = state.begin(.taken)
        state.cancel()
        #expect(state.finishCommit(request, succeeded: true) == nil)
    }

    @Test
    func changedRecordSuppressesItsOldReminderSuccess() {
        var state = TodayDoseFeedbackState()
        let request = state.begin(.delayed)
        #expect(state.finishCommit(request, succeeded: true) == nil)
        #expect(state.finishReminder(request, scheduled: true, recordIsCurrent: false) == nil)
        #expect(state.finishReminder(request, scheduled: true, recordIsCurrent: true) == nil)
    }

    @Test
    func sceneInterruptionDoesNotReplayAfterReturning() {
        var state = TodayDoseFeedbackState()
        let interrupted = state.begin(.delayed)
        #expect(state.finishCommit(interrupted, succeeded: true) == nil)
        state.cancel()
        #expect(state.finishReminder(interrupted, scheduled: true, recordIsCurrent: true) == nil)
        let fresh = state.begin(.delayed)
        #expect(state.finishCommit(fresh, succeeded: true) == nil)
        #expect(state.finishReminder(fresh, scheduled: true, recordIsCurrent: true) == .success)
    }

    @Test
    func identicalSuccessfulActionsHaveDistinctPresentationTriggers() {
        let first = TodayDoseFeedbackPulse(kind: .success)
        let second = TodayDoseFeedbackPulse(kind: .success)
        #expect(first != second)
    }
}
