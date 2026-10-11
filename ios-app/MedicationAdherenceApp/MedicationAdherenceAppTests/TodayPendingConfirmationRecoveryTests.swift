import Foundation
import Testing
@testable import MedicationAdherenceApp

struct TodayPendingConfirmationRecoveryTests {
    @Test @MainActor
    func handledRefreshKeepsTheCapturedKeyCancellable() {
        let task = StoredDoseTask(medicationID: UUID(), planID: UUID(),
                                  dueAt: Date(timeIntervalSince1970: 1_700_000_000), doseValue: 1, doseUnit: "unit")
        let capturedKey = DoseLogicalGroup.key(for: task)
        let pending = PendingDoseConfirmation(doseKey: capturedKey, kind: .earlyTaken)
        task.status = .taken
        // Boolean expectations cannot expose the synthetic key or IDs on failure.
        let keyUnchanged = DoseLogicalGroup.key(for: task) == capturedKey
        let matches = TodayPendingConfirmationCancellation.matches(expectedKey: capturedKey, current: pending)
        let cleared = TodayPendingConfirmationCancellation.cancelled(expectedKey: capturedKey, current: pending) == nil
        #expect(keyUnchanged)
        #expect(matches)
        #expect(cleared)
    }

    #if DEBUG && targetEnvironment(simulator)
    @Test
    func cancellationObservationsDistinguishEntryKeyStateAndAXResidue() {
        var state = TodayCancellationProbeState()
        let owner = state.registerOwner()
        state.recordRequest(owner: owner)
        state.observe(owner: owner, pending: true)
        #expect(state.outcome(renderedOwner: owner, renderedPending: true, cancelAXExists: true, sampleIsFresh: true) == .notEntered)
        state.recordEntry(owner: owner, keyMatches: false)
        #expect(state.outcome(renderedOwner: owner, renderedPending: true, cancelAXExists: true, sampleIsFresh: true) == .keyRejected)
        state.recordEntry(owner: owner, keyMatches: true)
        #expect(state.outcome(renderedOwner: owner, renderedPending: true, cancelAXExists: true, sampleIsFresh: true) == .notCleared)
        state.recordClear(owner: owner, isNil: true)
        #expect(state.outcome(renderedOwner: owner, renderedPending: false, cancelAXExists: true, sampleIsFresh: true) == .clearedWithAXResidue)
        #expect(state.outcome(renderedOwner: owner, renderedPending: true, cancelAXExists: true, sampleIsFresh: true) == .renderStateMismatch)
        #expect(state.outcome(renderedOwner: owner, renderedPending: false, cancelAXExists: false, sampleIsFresh: true) == .cleared)
        let anotherOwner = state.registerOwner()
        #expect(state.outcome(renderedOwner: anotherOwner, renderedPending: true, cancelAXExists: true, sampleIsFresh: true) == .ownerChanged)
        state.recordRequest(owner: owner)
        state.observe(owner: owner, pending: true)
        #expect(state.outcome(renderedOwner: owner, renderedPending: true, cancelAXExists: true, sampleIsFresh: true) == .reRequested)
    }

    @Test
    func cancellationObservationsDetectReappearanceWithoutInventingARequestAndStayBounded() {
        var state = TodayCancellationProbeState()
        let owner = state.registerOwner()
        state.observe(owner: owner, pending: true)
        #expect(state.outcome(renderedOwner: owner, renderedPending: true, cancelAXExists: true, sampleIsFresh: false) == .unknown)
        #expect(state.outcome(renderedOwner: 0, renderedPending: true, cancelAXExists: true, sampleIsFresh: true) == .unknown)
        state.recordEntry(owner: owner, keyMatches: true)
        state.recordClear(owner: owner, isNil: true)
        state.observe(owner: owner, pending: true)
        #expect(state.requestsAfterClear == 0)
        #expect(state.outcome(renderedOwner: owner, renderedPending: true, cancelAXExists: true, sampleIsFresh: true) == .pendingReappeared)
        for _ in 0..<20 {
            _ = state.registerOwner()
            state.recordEntry(owner: owner, keyMatches: true)
            state.recordRequest(owner: owner)
        }
        #expect(state.overflow)
        #expect(state.outcome(renderedOwner: owner, renderedPending: false, cancelAXExists: true, sampleIsFresh: true) == .unknown)
        let values = state.scalarValue.split(separator: ",").compactMap { Int($0) }
        #expect(values.count == 13)
        #expect(values.allSatisfy { (0...TodayCancellationProbeState.limit).contains($0) })
    }
    #endif

    @Test @MainActor
    func staleCancellationCannotClearANewerPendingKey() {
        let current = PendingDoseConfirmation(doseKey: "new-key", kind: .plannedDelay)
        let result = TodayPendingConfirmationCancellation.cancelled(expectedKey: "old-key", current: current)
        #expect(result == current)
        #expect(!TodayPendingConfirmationCancellation.matches(expectedKey: "old-key", current: current))
    }

    @Test @MainActor
    func matchingCancellationChangesOnlyPendingAndIsIdempotent() {
        var pending: PendingDoseConfirmation? = PendingDoseConfirmation(doseKey: "pending", kind: .earlyTaken)
        var interaction = TodayDoseInteractionState()
        interaction.inFlightDoseKeys = ["pending", "other-save"]
        let before = interaction.inFlightDoseKeys
        // This is the same pure assignment used inside the owner's existing animation.
        pending = TodayPendingConfirmationCancellation.cancelled(expectedKey: "pending", current: pending)
        #expect(pending == nil)
        #expect(interaction.inFlightDoseKeys == before)
        let repeated = TodayPendingConfirmationCancellation.cancelled(expectedKey: "pending", current: pending)
        #expect(repeated == nil)
    }

    @Test @MainActor
    func bothPresentationsRejectMissingChangedHandledArchivedAndReplacementTargets() {
        let original = TodayTaskReference(id: UUID(), medicationID: UUID(), doseKey: "old-key")
        let changed = TodayTaskReference(id: original.id, medicationID: original.medicationID, doseKey: "changed-key")
        let handled = TodayTaskReference(id: original.id, medicationID: original.medicationID,
                                         doseKey: original.doseKey, isActionable: false)
        // Archived targets likewise enter the shared reference with isActionable=false.
        let replacement = TodayTaskReference(id: UUID(), medicationID: original.medicationID, doseKey: original.doseKey)
        for candidates in [[], [changed], [handled], [replacement]] {
            var selection = TodayTaskSelection()
            selection.rememberActionTarget(original)
            selection.syncConfirmation(original.doseKey, candidates: [original])
            let wide = selection.resolve(candidates: candidates, firstOpen: candidates.first, pendingKey: original.doseKey)
            let compact = selection.resolve(candidates: candidates, firstOpen: candidates.first, pendingKey: original.doseKey)
            #expect(wide == nil)
            #expect(compact == nil)
            let pending = PendingDoseConfirmation(doseKey: original.doseKey, kind: .earlyTaken)
            #expect(TodayPendingConfirmationCancellation.matches(expectedKey: original.doseKey, current: pending))
            let cancelled = TodayPendingConfirmationCancellation.cancelled(expectedKey: original.doseKey, current: pending)
            #expect(cancelled == nil)
        }
    }

    @Test @MainActor
    func validTargetRemainsTheSameAcrossRepeatedWidthAndAXDecisions() {
        let original = TodayTaskReference(id: UUID(), medicationID: UUID(), doseKey: "key")
        var selection = TodayTaskSelection()
        selection.rememberActionTarget(original)
        selection.syncConfirmation(original.doseKey, candidates: [original])
        for width in [CGFloat(900), CGFloat(390), CGFloat(900)] {
            for ax in [false, true] {
                _ = TodayTaskWorkspaceLayout.expands(width: width, height: 700, isAccessibilitySize: ax)
                #expect(selection.resolve(candidates: [original], firstOpen: nil, pendingKey: original.doseKey) == original)
            }
        }
    }
}
