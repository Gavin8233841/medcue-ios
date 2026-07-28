import Foundation
import MedicationAdherenceCore
import Testing
@testable import MedicationAdherenceApp

struct LocalMedicalAIClientTests {
    @Test
    func lowQualityInitialOutputIsRepairedExactlyOnce() async throws {
        let runtime = StubLocalMedicalRuntime(outputs: [
            "<answer>当前任务：复述提示词</answer>",
            "<answer>今天可以核对提醒并及时记录处理情况。</answer>"
        ])
        let client = LocalMedicalAIClient(
            modelURL: URL(fileURLWithPath: "/tmp/test-model.gguf"),
            runtime: runtime
        )

        let response = try await client.respond(to: Self.request())

        #expect(response.message == "今天可以核对提醒并及时记录处理情况。")
        #expect(await runtime.callCount == 2)
    }

    @Test
    func failedRepairIsRejectedInsteadOfDisplayingUnstableText() async {
        let runtime = StubLocalMedicalRuntime(outputs: [
            "<answer>当前任务：复述提示词</answer>",
            "<answer>用户问题：仍然复述提示词</answer>"
        ])
        let client = LocalMedicalAIClient(
            modelURL: URL(fileURLWithPath: "/tmp/test-model.gguf"),
            runtime: runtime
        )

        do {
            _ = try await client.respond(to: Self.request())
            Issue.record("Expected unstable response rejection")
        } catch let error as LocalMedicalAIError {
            #expect(error.diagnosticSummary == LocalMedicalAIError.unstableResponse.diagnosticSummary)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
        #expect(await runtime.callCount == 2)
    }

    @Test
    func callerCancellationStopsGenerationBeforeAResponseIsReturned() async {
        let runtime = StubLocalMedicalRuntime(
            outputs: ["<answer>今天可以核对提醒并及时记录处理情况。</answer>"],
            delay: .seconds(5)
        )
        let client = LocalMedicalAIClient(
            modelURL: URL(fileURLWithPath: "/tmp/test-model.gguf"),
            runtime: runtime
        )
        let task = Task {
            try await client.respond(to: Self.request())
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

    private static func request() -> MedicalAIRequest {
        MedicalAIRequest(
            kind: .chat,
            userMessage: "今天需要注意什么？",
            authorization: MedicalAIUserAuthorization(
                grantedScopes: [],
                grantedAt: Date(),
                expiresAt: Date().addingTimeInterval(300)
            )
        )
    }
}

private actor StubLocalMedicalRuntime: LocalMedicalGenerating {
    private var outputs: [String]
    private let delay: Duration?
    private(set) var callCount = 0

    init(outputs: [String], delay: Duration? = nil) {
        self.outputs = outputs
        self.delay = delay
    }

    func generateResponse(prompt: String, modelURL: URL, maxTokens: Int) async throws -> String {
        callCount += 1
        if let delay {
            try await Task.sleep(for: delay)
        }
        guard !outputs.isEmpty else {
            throw LocalMedicalAIError.emptyResponse
        }
        return outputs.removeFirst()
    }

    func generateResponseStream(
        prompt: String,
        modelURL: URL,
        maxTokens: Int
    ) async -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }
}
