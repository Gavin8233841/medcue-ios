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
        let draft = MedicationImportDraft(
            source: .prescriptionImage,
            displayName: nil,
            kind: .unknown,
            prescriptionText: textResult.text,
            confidenceByField: [.prescriptionText: textResult.averageConfidence],
            sourceNote: "Vision 本机 OCR 识别，共 \(textResult.lineCount) 行；必须按原始医嘱逐项核对。"
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
            sourceNote: "Vision 本机条码识别，类型：\(barcode.symbology)。可靠药品数据源未接入前，只能作为辅助录入草稿。"
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
