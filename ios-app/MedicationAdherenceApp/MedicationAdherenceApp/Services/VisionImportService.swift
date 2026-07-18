import Foundation
import MedicationAdherenceCore
import UIKit
import Vision

struct VisionTextRecognitionResult: Sendable, Equatable {
    var text: String
    var averageConfidence: Double
    var lineCount: Int
}

struct VisionBarcodeRecognitionResult: Sendable, Equatable, Identifiable {
    var id: String { "\(symbology)-\(payload)" }
    var payload: String
    var symbology: String
    var confidence: Double
}

enum VisionImportError: LocalizedError {
    case imageDataUnavailable
    case textNotFound
    case barcodeNotFound

    var errorDescription: String? {
        switch self {
        case .imageDataUnavailable:
            "无法读取图片数据。"
        case .textNotFound:
            "未识别到可用文字，请换一张更清晰的医嘱或说明书照片。"
        case .barcodeNotFound:
            "未识别到条码，请换一张对焦清晰、条码完整的药盒照片。"
        }
    }
}

struct VisionImportService {
    func recognizePrescriptionText(from imageData: Data) async throws -> VisionTextRecognitionResult {
        try await Task.detached(priority: .userInitiated) {
            guard let cgImage = Self.cgImage(from: imageData) else {
                throw VisionImportError.imageDataUnavailable
            }

            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.recognitionLanguages = ["zh-Hans", "en-US"]

            let handler = VNImageRequestHandler(cgImage: cgImage)
            try handler.perform([request])

            let observations = request.results ?? []
            let recognized = observations.compactMap { observation -> (String, Double)? in
                guard let text = observation.topCandidates(1).first else {
                    return nil
                }
                return (text.string, Double(text.confidence))
            }
            let lines = recognized.map(\.0).filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            guard !lines.isEmpty else {
                throw VisionImportError.textNotFound
            }
            let averageConfidence = recognized.map(\.1).reduce(0, +) / Double(max(recognized.count, 1))
            return VisionTextRecognitionResult(
                text: lines.joined(separator: "\n"),
                averageConfidence: averageConfidence,
                lineCount: lines.count
            )
        }.value
    }

    func recognizeBarcodes(from imageData: Data) async throws -> [VisionBarcodeRecognitionResult] {
        try await Task.detached(priority: .userInitiated) {
            guard let cgImage = Self.cgImage(from: imageData) else {
                throw VisionImportError.imageDataUnavailable
            }

            let request = VNDetectBarcodesRequest()
            let handler = VNImageRequestHandler(cgImage: cgImage)
            try handler.perform([request])

            let barcodes = (request.results ?? []).compactMap { observation -> VisionBarcodeRecognitionResult? in
                guard let payload = observation.payloadStringValue,
                      !payload.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                else {
                    return nil
                }
                return VisionBarcodeRecognitionResult(
                    payload: payload,
                    symbology: observation.symbology.rawValue,
                    confidence: Double(observation.confidence)
                )
            }
            guard !barcodes.isEmpty else {
                throw VisionImportError.barcodeNotFound
            }
            return barcodes
        }.value
    }

    func makePrescriptionReview(textResult: VisionTextRecognitionResult) -> MedicationImportReview {
        let extractedFields = MedicationImportTextExtractor.structuredFields(
            fromPrescriptionText: textResult.text
        )
        var confidenceByField: [MedicationImportField: Double] = [.prescriptionText: textResult.averageConfidence]
        if extractedFields.displayName != nil {
            confidenceByField[.displayName] = textResult.averageConfidence
        }
        if extractedFields.genericName != nil {
            confidenceByField[.genericName] = textResult.averageConfidence
        }
        if extractedFields.strength != nil {
            confidenceByField[.strength] = textResult.averageConfidence
        }
        if extractedFields.form != nil {
            confidenceByField[.form] = textResult.averageConfidence
        }
        if extractedFields.directionsText != nil {
            confidenceByField[.directions] = textResult.averageConfidence
        }
        if extractedFields.doseAmount != nil {
            confidenceByField[.doseAmount] = textResult.averageConfidence
        }
        let draft = MedicationImportDraft(
            source: .prescriptionImage,
            displayName: extractedFields.displayName,
            genericName: extractedFields.genericName,
            kind: .unknown,
            form: extractedFields.form,
            strength: extractedFields.strength,
            doseValue: extractedFields.doseAmount.map { NSDecimalNumber(decimal: $0.value).doubleValue },
            doseUnit: extractedFields.doseAmount?.unit,
            directionsText: extractedFields.directionsText,
            prescriptionText: textResult.text,
            confidenceByField: confidenceByField,
            sourceNote: "来自用户确认的医嘱图片；保存前需按原始医嘱逐项核对。"
        )
        return MedicationImportReviewEngine().review(draft)
    }

    func makeBarcodeReview(barcode: VisionBarcodeRecognitionResult) -> MedicationImportReview {
        let draft = MedicationImportDraft(
            source: .barcode,
            displayName: nil,
            kind: .unknown,
            barcodeValue: barcode.payload,
            confidenceByField: [.barcodeValue: barcode.confidence],
            sourceNote: "来自用户确认的药盒条码；保存前请按药盒和说明书核对。"
        )
        return MedicationImportReviewEngine().review(draft)
    }

    private static func cgImage(from imageData: Data) -> CGImage? {
        guard let image = UIImage(data: imageData) else {
            return nil
        }
        return image.cgImage
    }
}
