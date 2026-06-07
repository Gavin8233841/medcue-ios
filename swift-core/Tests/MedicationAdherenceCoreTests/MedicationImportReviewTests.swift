import Foundation
import Testing
@testable import MedicationAdherenceCore

@Test func importReviewBlocksMissingMedicationName() {
    let draft = MedicationImportDraft(
        source: .manual,
        displayName: "  ",
        kind: .overTheCounter
    )

    let review = MedicationImportReviewEngine().review(draft)

    #expect(review.canCreateMedication == false)
    #expect(review.requiresUserConfirmation)
    #expect(review.issues.contains { issue in
        issue.kind == .missingRequiredField && issue.field == .displayName
    })
}

@Test func barcodeImportRequiresBarcodeAndFlagsLowConfidence() {
    let draft = MedicationImportDraft(
        source: .barcode,
        displayName: "Ibuprofen",
        kind: .overTheCounter,
        confidenceByField: [.displayName: 0.62]
    )

    let review = MedicationImportReviewEngine(minimumConfidence: 0.8).review(draft)

    #expect(review.canCreateMedication)
    #expect(review.issues.contains { issue in
        issue.kind == .missingRequiredField && issue.field == .barcodeValue
    })
    #expect(review.issues.contains { issue in
        issue.kind == .lowConfidence && issue.field == .displayName
    })
}

@Test func prescriptionTextAlwaysRequiresManualReview() {
    let draft = MedicationImportDraft(
        source: .prescriptionImage,
        displayName: "Artificial Tears",
        kind: .prescription,
        prescriptionText: "每日四次，每次一滴"
    )

    let review = MedicationImportReviewEngine().review(draft)

    #expect(review.canCreateMedication)
    #expect(review.issues.contains { issue in
        issue.kind == .sourceNeedsReview && issue.field == .prescriptionText
    })
}

@Test func confirmedImportBuildsMedication() throws {
    let draft = MedicationImportDraft(
        source: .manual,
        displayName: "  Artificial Tears ",
        kind: .overTheCounter,
        form: "Eye drops",
        directionsText: "Use as directed."
    )

    let medication = try MedicationImportReviewEngine().makeMedication(fromConfirmed: draft)

    #expect(medication.displayName == "Artificial Tears")
    #expect(medication.form == "Eye drops")
    #expect(medication.notes == "Use as directed.")
}
