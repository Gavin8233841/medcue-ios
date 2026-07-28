import Foundation
import MedicationAdherenceCore

enum VisionImportPurpose: Equatable, Sendable {
    case prescription
    case barcode
    case medicationName
    case labelText
}

enum VisionImportPipelineOutput: Equatable, Sendable {
    case prescription(VisionTextRecognitionResult, MedicationImportReview)
    case barcodes([VisionBarcodeRecognitionResult])
    case medicationName(VisionTextRecognitionResult, String?, MedicationImportExtractedFields)
    case labelText(VisionTextRecognitionResult)
}

struct VisionImportGenerationGate: Sendable {
    private var currentID: UUID?

    mutating func begin() -> UUID {
        let id = UUID()
        currentID = id
        return id
    }

    mutating func finish(_ id: UUID) -> Bool {
        guard currentID == id else { return false }
        currentID = nil
        return true
    }

    mutating func cancel() {
        currentID = nil
    }
}

struct VisionImportPipeline: Sendable {
    typealias TextRecognizer = @Sendable (Data) async throws -> VisionTextRecognitionResult
    typealias BarcodeRecognizer = @Sendable (Data) async throws -> [VisionBarcodeRecognitionResult]

    private let textRecognizer: TextRecognizer
    private let barcodeRecognizer: BarcodeRecognizer

    init(
        textRecognizer: @escaping TextRecognizer = {
            try await VisionImportService().recognizePrescriptionText(from: $0)
        },
        barcodeRecognizer: @escaping BarcodeRecognizer = {
            try await VisionImportService().recognizeBarcodes(from: $0)
        }
    ) {
        self.textRecognizer = textRecognizer
        self.barcodeRecognizer = barcodeRecognizer
    }

    func analyze(
        _ imageData: Data,
        purpose: VisionImportPurpose
    ) async throws -> VisionImportPipelineOutput {
        try Task.checkCancellation()
        switch purpose {
        case .prescription:
            let result = try await textRecognizer(imageData)
            try Task.checkCancellation()
            let review = VisionImportService().makePrescriptionReview(textResult: result)
            return .prescription(result, review)
        case .barcode:
            let barcodes = try await barcodeRecognizer(imageData)
            try Task.checkCancellation()
            return .barcodes(barcodes)
        case .medicationName:
            let result = try await textRecognizer(imageData)
            try Task.checkCancellation()
            return .medicationName(
                result,
                MedicationImportTextExtractor.scannedDisplayName(fromText: result.text),
                MedicationImportTextExtractor.structuredFields(fromPrescriptionText: result.text)
            )
        case .labelText:
            let result = try await textRecognizer(imageData)
            try Task.checkCancellation()
            return .labelText(result)
        }
    }
}
