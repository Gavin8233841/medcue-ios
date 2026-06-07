import Testing
@testable import MedicationAdherenceCore

@Test func medicationAddWorkflowExposesThreeEntryOptions() {
    let options = MedicationAddWorkflow.options

    #expect(options.map(\.id) == [.manual, .prescriptionDocumentOCR, .barcodeScan])
    #expect(options.allSatisfy { $0.requiresUserConfirmation })
}

@Test func prescriptionOCRAndBarcodeRequireExtraReview() {
    let ocr = MedicationAddWorkflow.options.first { $0.id == .prescriptionDocumentOCR }
    let barcode = MedicationAddWorkflow.options.first { $0.id == .barcodeScan }

    #expect(ocr?.requiresMedicalAIReview == true)
    #expect(ocr?.disclaimer.contains("二次确认") == true)
    #expect(barcode?.requiresReliableExternalAPI == true)
    #expect(barcode?.requiresMedicalAIReview == true)
}
