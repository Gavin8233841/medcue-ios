import Foundation
import Testing
@testable import MedicationAdherenceApp

/// Session-state coverage only. Rendering, focus and scroll restoration need UI evidence.
struct MedicationBrowseSessionTests {
    @Test @MainActor
    func emptySessionDoesNotAutomaticallySelectAMedication() {
        let session = MedicationBrowseSession()

        #expect(session.selectedMedicationID == nil)
        #expect(session.returnAnchorID == nil)
        #expect(session.searchText.isEmpty)
        #expect(session.selectedLifecycleStatus == .active)
        #expect(!session.isGroupExpanded)
    }

    @Test @MainActor
    func selectionRecordsTheMedicationAsTheReturnAnchor() {
        var session = MedicationBrowseSession()
        let medicationID = UUID()

        session.select(medicationID)

        #expect(session.selectedMedicationID == medicationID)
        #expect(session.returnAnchorID == medicationID)
    }

    @Test @MainActor
    func searchChangesPreserveSelectionAndReturnAnchor() {
        var session = MedicationBrowseSession()
        let medicationID = UUID()
        session.select(medicationID)

        for search in ["synthetic search with no matching row", "", "another query"] {
            session.searchText = search

            #expect(session.searchText == search)
            #expect(session.selectedMedicationID == medicationID)
            #expect(session.returnAnchorID == medicationID)
        }
    }

    @Test @MainActor
    func lifecycleFilterChangesPreserveSelectionAnchorAndSearch() {
        var session = MedicationBrowseSession()
        let medicationID = UUID()
        session.select(medicationID)
        session.searchText = "synthetic medication"

        for status in StoredMedicationLifecycleStatus.allCases {
            session.isGroupExpanded = true
            session.setLifecycleStatus(status)

            #expect(session.selectedLifecycleStatus == status)
            #expect(!session.isGroupExpanded)
            #expect(session.searchText == "synthetic medication")
            #expect(session.selectedMedicationID == medicationID)
            #expect(session.returnAnchorID == medicationID)
        }
    }

    @Test @MainActor
    func groupExpansionChangesPreserveSelectionAndReturnAnchor() {
        var session = MedicationBrowseSession()
        let medicationID = UUID()
        session.select(medicationID)

        for expanded in [true, false, true] {
            session.isGroupExpanded = expanded

            #expect(session.isGroupExpanded == expanded)
            #expect(session.selectedMedicationID == medicationID)
            #expect(session.returnAnchorID == medicationID)
        }
    }

    @Test @MainActor
    func returningToListRetainsSelectionAndBrowsingContext() {
        var session = MedicationBrowseSession()
        let medicationID = UUID()
        session.setLifecycleStatus(.archived)
        session.searchText = "synthetic medication"
        session.isGroupExpanded = true
        session.select(medicationID)

        session.returnToList()
        session.returnToList()

        #expect(session.selectedMedicationID == medicationID)
        #expect(session.returnAnchorID == medicationID)
        #expect(session.selectedLifecycleStatus == .archived)
        #expect(session.searchText == "synthetic medication")
        #expect(session.isGroupExpanded)
    }

    @Test @MainActor
    func hidingSelectionWithFiltersDoesNotActAsDeletion() {
        var session = MedicationBrowseSession()
        let medicationID = UUID()
        session.select(medicationID)

        session.setLifecycleStatus(.interrupted)
        session.searchText = "synthetic nonmatching query"
        session.isGroupExpanded = false
        session.returnToList()

        #expect(session.selectedMedicationID == medicationID)
        #expect(session.returnAnchorID == medicationID)

        session.medicationsWereDeleted([medicationID])

        #expect(session.selectedMedicationID == nil)
        #expect(session.returnAnchorID == nil)
    }

    @Test @MainActor
    func deletingTheSelectedMedicationPreservesOtherBrowsingContext() {
        var session = MedicationBrowseSession()
        let medicationID = UUID()
        session.setLifecycleStatus(.interrupted)
        session.searchText = "synthetic medication"
        session.isGroupExpanded = true
        session.select(medicationID)

        session.medicationsWereDeleted([UUID(), medicationID, UUID()])
        session.returnToList()

        #expect(session.selectedMedicationID == nil)
        #expect(session.returnAnchorID == nil)
        #expect(session.selectedLifecycleStatus == .interrupted)
        #expect(session.searchText == "synthetic medication")
        #expect(session.isGroupExpanded)
    }

    @Test @MainActor
    func deletingUnrelatedMedicationsPreservesSelectionAndAnchor() {
        var session = MedicationBrowseSession()
        let medicationID = UUID()
        session.select(medicationID)

        session.medicationsWereDeleted([UUID(), UUID()])

        #expect(session.selectedMedicationID == medicationID)
        #expect(session.returnAnchorID == medicationID)
    }

    @Test @MainActor
    func emptyDeletionSetPreservesSelectionAndAnchor() {
        var session = MedicationBrowseSession()
        let medicationID = UUID()
        session.select(medicationID)

        session.medicationsWereDeleted([])

        #expect(session.selectedMedicationID == medicationID)
        #expect(session.returnAnchorID == medicationID)
    }

    @Test @MainActor
    func repeatedSelectionIsIdempotentAndPreservesBrowsingContext() {
        var session = MedicationBrowseSession()
        let medicationID = UUID()
        session.setLifecycleStatus(.archived)
        session.searchText = "synthetic medication"
        session.isGroupExpanded = true

        session.select(medicationID)
        session.select(medicationID)

        #expect(session.selectedMedicationID == medicationID)
        #expect(session.returnAnchorID == medicationID)
        #expect(session.selectedLifecycleStatus == .archived)
        #expect(session.searchText == "synthetic medication")
        #expect(session.isGroupExpanded)
    }

    @Test @MainActor
    func choosingAnotherMedicationUpdatesTheReturnAnchor() {
        var session = MedicationBrowseSession()
        let firstID = UUID()
        let secondID = UUID()
        session.select(firstID)
        session.returnToList()

        session.select(secondID)
        session.returnToList()
        session.medicationsWereDeleted([firstID])

        #expect(session.selectedMedicationID == secondID)
        #expect(session.returnAnchorID == secondID)
    }

    @Test @MainActor
    func emptySessionRemainsUnselectedAfterBrowsingAndDeletionEvents() {
        var session = MedicationBrowseSession()
        session.searchText = "synthetic nonmatching query"
        session.setLifecycleStatus(.archived)
        session.isGroupExpanded = true
        session.medicationsWereDeleted([UUID()])
        session.returnToList()

        #expect(session.selectedMedicationID == nil)
        #expect(session.returnAnchorID == nil)
    }

    @Test @MainActor
    func repeatedDeletionDoesNotRestoreSelectionAndAllowsExplicitReselection() {
        var session = MedicationBrowseSession()
        let deletedID = UUID()
        let replacementID = UUID()
        session.select(deletedID)

        session.medicationsWereDeleted([deletedID])
        session.medicationsWereDeleted([deletedID])
        session.returnToList()

        #expect(session.selectedMedicationID == nil)
        #expect(session.returnAnchorID == nil)

        session.select(replacementID)

        #expect(session.selectedMedicationID == replacementID)
        #expect(session.returnAnchorID == replacementID)
    }
}
