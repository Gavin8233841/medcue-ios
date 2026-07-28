import Foundation
import MedicationAdherenceCore
import Testing
@testable import MedicationAdherenceApp

struct VisionImportPipelineTests {
    @Test
    func newerRequestInvalidatesOlderCompletionAndCancelInvalidatesCurrent() {
        var gate = VisionImportGenerationGate()
        let first = gate.begin()
        let second = gate.begin()

        let acceptedFirst = gate.finish(first)
        let acceptedSecond = gate.finish(second)
        let acceptedSecondAgain = gate.finish(second)
        #expect(!acceptedFirst)
        #expect(acceptedSecond)
        #expect(!acceptedSecondAgain)

        let third = gate.begin()
        gate.cancel()
        let acceptedAfterCancel = gate.finish(third)
        #expect(!acceptedAfterCancel)
    }

    @Test
    func prescriptionPipelineBuildsReviewFromRecognizerOutput() async throws {
        let textResult = VisionTextRecognitionResult(
            text: "药品名称：阿莫西林\n规格：500 mg",
            averageConfidence: 0.91,
            lineCount: 2
        )
        let pipeline = VisionImportPipeline(
            textRecognizer: { _ in textResult },
            barcodeRecognizer: { _ in [] }
        )

        let output = try await pipeline.analyze(Data([0x01]), purpose: .prescription)

        guard case let .prescription(result, review) = output else {
            Issue.record("Expected prescription result")
            return
        }
        #expect(result == textResult)
        #expect(review.draft.displayName == "阿莫西林")
        #expect(review.draft.strength == "500 mg")
    }

    @Test
    func cancelledRecognitionCannotReturnAResult() async {
        let pipeline = VisionImportPipeline(
            textRecognizer: { _ in
                try await Task.sleep(for: .seconds(5))
                return VisionTextRecognitionResult(text: "迟到结果", averageConfidence: 1, lineCount: 1)
            },
            barcodeRecognizer: { _ in [] }
        )
        let task = Task {
            try await pipeline.analyze(Data([0x01]), purpose: .labelText)
        }
        task.cancel()

        do {
            _ = try await task.value
            Issue.record("Expected cancellation")
        } catch is CancellationError {
            // Expected.
        } catch {
            Issue.record("Expected CancellationError, got \(error)")
        }
    }
}
