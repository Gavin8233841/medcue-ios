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

@Test func importReviewBlocksUnclearMedicationName() {
    let draft = MedicationImportDraft(
        source: .manual,
        displayName: "1",
        kind: .overTheCounter,
        form: "片剂",
        strength: "100 mg"
    )

    let review = MedicationImportReviewEngine().review(draft)

    #expect(review.canCreateMedication == false)
    #expect(review.issues.contains { issue in
        issue.kind == .missingRequiredField
            && issue.field == .displayName
            && issue.message.contains("清晰可核对")
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

@Test func prescriptionTextExtractorFindsExplicitMedicationNameLabel() {
    let text = """
    医嘱单
    药品名称：氯雷他定片
    用法用量：每日一次，每次一片
    """

    let displayName = MedicationImportTextExtractor.displayName(fromPrescriptionText: text)

    #expect(displayName == "氯雷他定片")
}

@Test func prescriptionTextExtractorFindsExplicitStructuredFields() {
    let text = """
    医嘱单
    药品名称：氯雷他定片
    规格：10 mg
    剂型：片剂
    用法用量：每日一次，每次一片
    """

    let fields = MedicationImportTextExtractor.structuredFields(fromPrescriptionText: text)

    #expect(fields.displayName == "氯雷他定片")
    #expect(fields.genericName == nil)
    #expect(fields.strength == "10 mg")
    #expect(fields.form == "片剂")
    #expect(fields.doseAmount?.value == Decimal(1))
    #expect(fields.doseAmount?.unit == "片")
    #expect(fields.directionsText == "每日一次，每次一片")
}

@Test func prescriptionTextExtractorSeparatesBrandAndGenericName() {
    let text = """
    商品名：开瑞坦
    通用名：氯雷他定片
    规格：10 mg
    用法用量：每日一次，每次一片
    """

    let fields = MedicationImportTextExtractor.structuredFields(fromPrescriptionText: text)

    #expect(fields.displayName == "开瑞坦")
    #expect(fields.genericName == "氯雷他定片")
}

@Test func prescriptionTextExtractorUsesGenericNameAsDisplayNameFallback() {
    let text = """
    通用名：氯雷他定片
    规格：10 mg
    """

    let fields = MedicationImportTextExtractor.structuredFields(fromPrescriptionText: text)

    #expect(fields.displayName == "氯雷他定片")
    #expect(fields.genericName == "氯雷他定片")
}

@Test func scannedDisplayNameUsesExplicitMedicationLabel() {
    let text = """
    医嘱单
    药品名称：氯雷他定片
    规格：10 mg
    """

    let displayName = MedicationImportTextExtractor.scannedDisplayName(fromText: text)

    #expect(displayName == "氯雷他定片")
}

@Test func scannedDisplayNameAcceptsPackageFrontNameLine() {
    let text = """
    氯雷他定片
    10 mg
    """

    let displayName = MedicationImportTextExtractor.scannedDisplayName(fromText: text)

    #expect(displayName == "氯雷他定片")
}

@Test func scannedDisplayNameRejectsInstructionAndStrengthLines() {
    let text = """
    药品说明书
    规格：10 mg
    用法用量：每日一次，每次一片
    """

    let displayName = MedicationImportTextExtractor.scannedDisplayName(fromText: text)

    #expect(displayName == nil)
}

@Test func prescriptionTextExtractorAcceptsEnglishLabelsWithSpaces() {
    let text = """
    Medication Name: Ibuprofen
    Strength: 200 mg
    Dosage Form: Tablet
    Directions: Take one tablet after meals.
    """

    let fields = MedicationImportTextExtractor.structuredFields(fromPrescriptionText: text)

    #expect(fields.displayName == "Ibuprofen")
    #expect(fields.strength == "200 mg")
    #expect(fields.form == "Tablet")
    #expect(fields.doseAmount?.value == Decimal(1))
    #expect(fields.doseAmount?.unit == "片")
    #expect(fields.directionsText == "Take one tablet after meals.")
}

@Test func prescriptionTextExtractorDoesNotTreatDirectionsAsMedicationName() {
    let text = """
    每日一次，每次一片
    规格：10 mg
    复诊时携带药盒
    """

    let displayName = MedicationImportTextExtractor.displayName(fromPrescriptionText: text)

    #expect(displayName == nil)
}

@Test func prescriptionTextExtractorDoesNotTreatEnglishStatusAsMedicationName() {
    let text = """
    Medication Status: Active
    Strength: 200 mg
    Directions: Take one tablet after meals.
    """

    let fields = MedicationImportTextExtractor.structuredFields(fromPrescriptionText: text)

    #expect(fields.displayName == nil)
    #expect(fields.strength == "200 mg")
    #expect(fields.directionsText == "Take one tablet after meals.")
}

@Test func prescriptionTextExtractorDoesNotPrefillMassStrengthAsDoseAmount() {
    let text = """
    药品名称：布洛芬片
    规格：200 mg
    用法用量：每次 200 mg
    """

    let fields = MedicationImportTextExtractor.structuredFields(fromPrescriptionText: text)

    #expect(fields.displayName == "布洛芬片")
    #expect(fields.strength == "200 mg")
    #expect(fields.doseAmount == nil)
    #expect(fields.directionsText == "每次 200 mg")
}

@Test func confirmedImportBuildsMedication() throws {
    let draft = MedicationImportDraft(
        source: .manual,
        displayName: "  Artificial Tears ",
        genericName: "Carboxymethylcellulose Sodium",
        kind: .overTheCounter,
        form: "Eye drops",
        directionsText: "Use as directed."
    )

    let medication = try MedicationImportReviewEngine().makeMedication(fromConfirmed: draft)

    #expect(medication.displayName == "Artificial Tears")
    #expect(medication.genericName == "Carboxymethylcellulose Sodium")
    #expect(medication.form == "Eye drops")
    #expect(medication.notes == "Use as directed.")
}

@Test func confirmedImportRejectsUnclearMedicationName() {
    let draft = MedicationImportDraft(
        source: .manual,
        displayName: "100 mg",
        kind: .overTheCounter
    )

    #expect(throws: MedicationImportReviewError.missingDisplayName) {
        try MedicationImportReviewEngine().makeMedication(fromConfirmed: draft)
    }
}
