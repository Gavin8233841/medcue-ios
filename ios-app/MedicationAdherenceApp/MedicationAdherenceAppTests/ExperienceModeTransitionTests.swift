import Foundation
import Testing
@testable import MedicationAdherenceApp

struct ExperienceModeTransitionTests {
    @Test @MainActor
    func cancellationAndBackgroundInvalidationNeverProduceACommit() throws {
        var transition = AppExperienceModeTransition()
        let firstRequest = transition.request(.elder, current: .complete, source: .settings)
        let first = try #require(firstRequest)
        transition.cancel(first.id)
        let cancelledCommit = transition.confirm(first.id, current: .complete, canCommit: true)
        #expect(cancelledCommit == nil)
        let secondRequest = transition.request(.elder, current: .complete, source: .settings)
        let second = try #require(secondRequest)
        transition.cancel() // The scene becoming inactive invalidates the request.
        let backgroundCommit = transition.confirm(second.id, current: .complete, canCommit: true)
        #expect(backgroundCommit == nil)
        #expect(transition.pending == nil)
    }

    @Test @MainActor
    func confirmationProducesExactlyOneCommitAndRepeatedRequestsKeepTheOwner() throws {
        var transition = AppExperienceModeTransition()
        let requested = transition.request(.elder, current: .complete, source: .settings)
        let request = try #require(requested)
        let repeatedRequest = transition.request(.elder, current: .complete, source: .firstLaunch)
        #expect(repeatedRequest == nil)
        #expect(transition.pending?.id == request.id)
        let commit = transition.confirm(request.id, current: .complete, canCommit: true)
        #expect(commit?.target == .elder)
        let repeatedCommit = transition.confirm(request.id, current: .elder, canCommit: true)
        #expect(repeatedCommit == nil)
        #expect(transition.pending == nil)
    }

    @Test @MainActor
    func staleCallbacksCannotCancelOrConfirmANewerRequest() throws {
        var transition = AppExperienceModeTransition()
        let oldRequest = transition.request(.elder, current: .complete, source: .settings)
        let old = try #require(oldRequest)
        transition.cancel(old.id)
        let currentRequest = transition.request(.elder, current: .complete, source: .settings)
        let current = try #require(currentRequest)
        transition.cancel(old.id)
        let staleCommit = transition.confirm(old.id, current: .complete, canCommit: true)
        #expect(staleCommit == nil)
        #expect(transition.pending?.id == current.id)
        let currentCommit = transition.confirm(current.id, current: .complete, canCommit: true)
        #expect(currentCommit?.id == current.id)
    }

    @Test @MainActor
    func changedModeOrNewBusyStateInvalidatesConfirmation() throws {
        var transition = AppExperienceModeTransition()
        let requested = transition.request(.elder, current: .complete, source: .settings)
        let request = try #require(requested)
        let changedModeCommit = transition.confirm(request.id, current: .elder, canCommit: true)
        #expect(changedModeCommit == nil)
        let exitRequest = transition.request(.complete, current: .elder, source: .elderExit)
        let exit = try #require(exitRequest)
        let busyCommit = transition.confirm(exit.id, current: .elder, canCommit: false)
        #expect(busyCommit == nil)
        let invalidatedCommit = transition.confirm(exit.id, current: .elder, canCommit: true)
        #expect(invalidatedCommit == nil)
        #expect(transition.pending == nil)
    }

    @Test @MainActor
    func guardReadsCurrentStateInsteadOfTheRequestTimeSnapshot() {
        let state = ExperienceModeGuardTestState()
        let guardCallbacks = AppExperienceModeRequestGuard(
            canCommit: { !state.isSaving }, onBlocked: { state.notices += 1 }
        )
        #expect(guardCallbacks.canCommit())
        state.isSaving = true
        #expect(!guardCallbacks.canCommit())
        guardCallbacks.onBlocked()
        #expect(state.notices == 1)
    }

    @Test @MainActor
    func sameModeIsNoOpExceptExplicitFirstUseElderConfirmation() throws {
        var transition = AppExperienceModeTransition()
        let completeRequest = transition.request(.complete, current: .complete, source: .settings)
        #expect(completeRequest == nil)
        let elderRequest = transition.request(.elder, current: .elder, source: .settings)
        #expect(elderRequest == nil)
        let firstUseRequest = transition.request(.elder, current: .elder, source: .firstLaunch)
        let firstUse = try #require(firstUseRequest)
        let firstUseCommit = transition.confirm(firstUse.id, current: .elder, canCommit: true)
        #expect(firstUseCommit?.target == .elder)
    }

    @Test @MainActor
    func unknownPreferenceFallsBackWithoutRewritingTheStoredValue() throws {
        let name = "medcue.mode-policy-test.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set("future-mode", forKey: AppExperienceMode.storageKey)
        #expect(AppExperienceMode.resolve(try #require(defaults.string(forKey: AppExperienceMode.storageKey))) == .complete)
        #expect(defaults.string(forKey: AppExperienceMode.storageKey) == "future-mode")
        #expect(defaults.object(forKey: "hasCompletedFirstLaunchSetup") == nil)
        #expect(defaults.object(forKey: AppExperienceMode.firstLaunchChoiceKey) == nil)
    }
}

@MainActor
private final class ExperienceModeGuardTestState {
    var isSaving = false
    var notices = 0
}
