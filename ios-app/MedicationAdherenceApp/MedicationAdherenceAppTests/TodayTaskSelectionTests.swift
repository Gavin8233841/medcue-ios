import Foundation
import Testing
@testable import MedicationAdherenceApp

struct TodayTaskSelectionTests {
    private func task(_ key: String = "dose") -> TodayTaskReference {
        TodayTaskReference(id: UUID(), medicationID: UUID(), doseKey: key)
    }

    @Test @MainActor
    func defaultWaitsForRealOpenTasksAndNeverTakesOverAManualSelection() {
        var selection = TodayTaskSelection()
        let earliest = task("earliest")
        let later = task("later")
        selection.ensureDefault(nil)
        #expect(selection.reference == nil)
        selection.ensureDefault(earliest)
        #expect(selection.reference == earliest)
        let accepted = selection.select(later, isLocked: false)
        #expect(accepted)
        selection.ensureDefault(earliest)
        #expect(selection.reference == later)
    }

    @Test @MainActor
    func refreshAndDelayKeepTheSameIdentityEvenWhenItsLogicalKeyChanges() {
        var selection = TodayTaskSelection()
        let earliest = task("earliest")
        let chosen = task("before-delay")
        selection.rememberActionTarget(chosen)
        let delayed = TodayTaskReference(id: chosen.id, medicationID: chosen.medicationID, doseKey: "after-delay")
        let resolved = selection.resolve(candidates: [delayed, earliest], firstOpen: earliest, pendingKey: nil)
        #expect(resolved == delayed)
        #expect(selection.selectionEvent == 0) // Timer/feedback does not announce a new selection.
    }

    @Test @MainActor
    func selectingTheSameTaskAgainRequestsAVisibleReveal() {
        var selection = TodayTaskSelection()
        let chosen = task()
        let first = selection.select(chosen, isLocked: false)
        let second = selection.select(chosen, isLocked: false)
        #expect(first && second)
        #expect(selection.reference == chosen)
        #expect(selection.selectionEvent == 2)
    }

    @Test @MainActor
    func busySelectionAndResetCannotChangeTheConfirmationContext() {
        var selection = TodayTaskSelection()
        let chosen = task("chosen")
        let other = task("other")
        selection.rememberActionTarget(chosen)
        selection.syncConfirmation(chosen.doseKey, candidates: [chosen, other])
        let accepted = selection.select(other, isLocked: true)
        selection.returnToList(other, isLocked: true)
        #expect(!accepted)
        #expect(selection.reference == chosen)
        #expect(selection.selectionEvent == 0)
        #expect(selection.resolve(candidates: [other, chosen], firstOpen: other, pendingKey: chosen.doseKey) == chosen)
    }

    @Test @MainActor
    func pendingConfirmationNeverMovesToAnotherUUIDWithTheSameKey() {
        var selection = TodayTaskSelection()
        let chosen = task("shared-key")
        let replacement = TodayTaskReference(id: UUID(), medicationID: chosen.medicationID, doseKey: chosen.doseKey)
        selection.rememberActionTarget(chosen)
        selection.syncConfirmation(chosen.doseKey, candidates: [chosen, replacement])
        selection.syncConfirmation(chosen.doseKey, candidates: [replacement])
        #expect(selection.confirmationReference == chosen)
        #expect(selection.resolve(candidates: [replacement], firstOpen: replacement, pendingKey: chosen.doseKey) == nil)
    }

    @Test @MainActor
    func unknownOrAmbiguousConfirmationHasNoActionableFallback() {
        var selection = TodayTaskSelection()
        let a = task("shared-key")
        let b = task("shared-key")
        selection.syncConfirmation("shared-key", candidates: [a, b])
        #expect(selection.resolve(candidates: [a, b], firstOpen: a, pendingKey: "shared-key") == nil)
        selection.syncConfirmation("unknown", candidates: [a])
        #expect(selection.resolve(candidates: [a], firstOpen: a, pendingKey: "unknown") == nil)
    }

    @Test @MainActor
    func pendingKeyChangeCannotCommitTheDelayedOrReassignedTask() {
        var selection = TodayTaskSelection()
        let chosen = task("original")
        selection.rememberActionTarget(chosen)
        selection.syncConfirmation(chosen.doseKey, candidates: [chosen])
        let moved = TodayTaskReference(id: chosen.id, medicationID: chosen.medicationID, doseKey: "changed")
        let reassigned = TodayTaskReference(id: chosen.id, medicationID: UUID(), doseKey: chosen.doseKey)
        #expect(selection.resolve(candidates: [moved], firstOpen: moved, pendingKey: chosen.doseKey) == nil)
        #expect(selection.resolve(candidates: [reassigned], firstOpen: reassigned, pendingKey: chosen.doseKey) == nil)
        selection.syncConfirmation(nil, candidates: [moved])
        #expect(selection.resolve(candidates: [moved], firstOpen: moved, pendingKey: nil) == moved)
    }

    @Test @MainActor
    func disappearingSelectionRequiresExplicitReturnInsteadOfJumpingToAnotherDrug() {
        var selection = TodayTaskSelection()
        let chosen = task("chosen")
        let remaining = task("remaining")
        selection.rememberActionTarget(chosen)
        selection.ensureDefault(remaining)
        #expect(selection.resolve(candidates: [remaining], firstOpen: remaining, pendingKey: nil) == nil)
        selection.returnToList(remaining, isLocked: false)
        #expect(selection.resolve(candidates: [remaining], firstOpen: remaining, pendingKey: nil) == remaining)
        #expect(selection.selectionEvent == 1)
    }

    @Test @MainActor
    func fetchFailureTakesPriorityOverResultsAndInitialLoading() {
        #expect(TodayTaskLoadState.resolve(hasFetchError: true, isLoading: false, hasResults: true) == .failed)
        #expect(TodayTaskLoadState.resolve(hasFetchError: true, isLoading: true, hasResults: false) == .failed)
        #expect(TodayTaskLoadState.resolve(hasFetchError: false, isLoading: true, hasResults: false) == .loading)
        #expect(TodayTaskLoadState.resolve(hasFetchError: false, isLoading: true, hasResults: true) == .ready)
        #expect(TodayTaskLoadState.resolve(hasFetchError: false, isLoading: false, hasResults: false) == .ready)
    }

    @Test @MainActor
    func widthHeightAndAccessibilityBudgetsChooseLayoutWithoutChangingSelection() {
        var selection = TodayTaskSelection()
        let chosen = task()
        selection.rememberActionTarget(chosen)
        #expect(TodayTaskWorkspaceLayout.expands(width: 668, height: 360, isAccessibilitySize: false))
        #expect(!TodayTaskWorkspaceLayout.expands(width: 667, height: 900, isAccessibilitySize: false))
        #expect(!TodayTaskWorkspaceLayout.expands(width: 900, height: 359, isAccessibilitySize: false))
        #expect(!TodayTaskWorkspaceLayout.expands(width: 900, height: 900, isAccessibilitySize: true))
        #expect(selection.reference == chosen)
    }
}
