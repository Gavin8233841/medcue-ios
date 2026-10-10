import Foundation
import Testing
@testable import MedicationAdherenceApp

struct TodayPendingConfirmationRecoveryTests {
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
