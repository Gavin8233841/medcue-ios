import Testing
@testable import MedicationAdherenceCore

@Test func medicationAddWorkflowExposesThreeEntryOptions() {
    let options = MedicationAddWorkflow.options

    #expect(options.map(\.id) == [.manual, .prescriptionDocumentOCR, .barcodeScan])
    #expect(options.allSatisfy { $0.requiresUserConfirmation })
    #expect(MedicationAddWorkflow.manualOption.id == .manual)
    #expect(MedicationAddWorkflow.manualOption.description.hasPrefix("逐项填写"))
    #expect(options.first?.title == "手动添加")
}

@Test func prescriptionOCRAndBarcodeRequireExtraReview() {
    let ocr = MedicationAddWorkflow.options.first { $0.id == .prescriptionDocumentOCR }
    let barcode = MedicationAddWorkflow.options.first { $0.id == .barcodeScan }

    #expect(ocr?.requiresMedicalAIReview == true)
    #expect(ocr?.title == "拍照导入医嘱")
    #expect(ocr?.description.contains("提取文字后再逐项确认") == true)
    #expect(ocr?.disclaimer.contains("二次确认") == true)
    #expect(barcode?.requiresReliableExternalAPI == false)
    #expect(barcode?.requiresMedicalAIReview == true)
    #expect(barcode?.description == "扫描或输入药盒条码，记录后再核对药品信息。")
}
