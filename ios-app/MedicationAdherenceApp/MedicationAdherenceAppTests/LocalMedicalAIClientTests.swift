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
    func streamingResponseRepairsPromptEchoBeforeCompletion() async throws {
        let runtime = StubLocalMedicalRuntime(
            outputs: ["<answer>今天可以核对提醒并及时记录处理情况。</answer>"],
            streamDeltas: ["<answer>当前任务：", "复述提示词</answer>"]
        )
        let client = LocalMedicalAIClient(
            modelURL: URL(fileURLWithPath: "/tmp/test-model.gguf"),
            runtime: runtime
        )

        var completedAnswers: [String] = []
        for try await event in client.streamResponse(to: Self.request()) {
            if case let .generationCompleted(answer, _) = event {
                completedAnswers.append(answer)
            }
        }

        #expect(completedAnswers == ["今天可以核对提醒并及时记录处理情况。"])
        #expect(await runtime.callCount == 1)
    }

    @Test
    func streamingFailedRepairNeverCompletesAResponse() async {
        let runtime = StubLocalMedicalRuntime(
            outputs: ["<answer>当前任务：仍然复述提示词</answer>"],
            streamDeltas: ["<answer>当前任务：复述提示词</answer>"]
        )
        let client = LocalMedicalAIClient(
            modelURL: URL(fileURLWithPath: "/tmp/test-model.gguf"),
            runtime: runtime
        )

        var completed = false
        do {
            for try await event in client.streamResponse(to: Self.request()) {
                if case .generationCompleted = event {
                    completed = true
                }
            }
            Issue.record("Expected unstable response rejection")
        } catch let error as LocalMedicalAIError {
            #expect(error.diagnosticSummary == LocalMedicalAIError.unstableResponse.diagnosticSummary)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }

        #expect(!completed)
        #expect(await runtime.callCount == 1)
    }

    @Test
    func singleAndStreamingResponsesPreserveTheSameThoughtBoundary() async throws {
        let generated = "<thought>先核对记录。</thought><final>今天可以核对提醒并及时记录处理情况。</final>"
        let singleClient = LocalMedicalAIClient(
            modelURL: URL(fileURLWithPath: "/tmp/test-model.gguf"),
            runtime: StubLocalMedicalRuntime(outputs: [generated])
        )
        let streamClient = LocalMedicalAIClient(
            modelURL: URL(fileURLWithPath: "/tmp/test-model.gguf"),
            runtime: StubLocalMedicalRuntime(outputs: [], streamDeltas: [generated])
        )

        let single = try await singleClient.respond(to: Self.request())
        var completed: (answer: String, thinking: String)?
        for try await event in streamClient.streamResponse(to: Self.request()) {
            if case let .generationCompleted(answer, thinking) = event {
                completed = (answer, thinking)
            }
        }

        #expect(single.message.contains("今天可以核对提醒并及时记录处理情况。"))
        #expect(single.message.contains("先核对记录。"))
        #expect(completed?.answer == "今天可以核对提醒并及时记录处理情况。")
        #expect(completed?.thinking == "先核对记录。")
    }

    @Test
    func fabricatedCompletionCountIsRepairedBeforeReturn() async throws {
        let runtime = StubLocalMedicalRuntime(outputs: [
            "<answer>甲药已完成999次，近期有忽略记录，建议核对。</answer>",
            "<answer>近期甲药有忽略记录，建议核对原因并继续记录。</answer>"
        ])
        let client = LocalMedicalAIClient(
            modelURL: URL(fileURLWithPath: "/tmp/test-model.gguf"),
            runtime: runtime
        )

        let response = try await client.respond(to: Self.trendRequest())

        #expect(!response.message.contains("999"))
        #expect(response.message.contains("甲药有忽略记录"))
        #expect(await runtime.callCount == 2)
    }

    @Test
    func inconsistentMedicationCountIsRepairedBeforeReturn() async throws {
        let runtime = StubLocalMedicalRuntime(outputs: [
            "<answer>近期两种药品中甲药有忽略记录，建议核对原因。</answer>",
            "<answer>近期甲药有忽略记录，建议核对原因并继续记录。</answer>"
        ])
        let client = LocalMedicalAIClient(
            modelURL: URL(fileURLWithPath: "/tmp/test-model.gguf"),
            runtime: runtime
        )

        let response = try await client.respond(to: Self.trendRequest())

        #expect(!response.message.contains("两种药品"))
        #expect(response.message.contains("甲药有忽略记录"))
        #expect(await runtime.callCount == 2)
    }

    @Test
    func offTopicOutputIsRepairedBeforeReturn() async throws {
        let runtime = StubLocalMedicalRuntime(outputs: [
            "<answer>今天可以核对日历并记录天气变化。</answer>",
            "<answer>近期甲药有忽略记录，建议核对原因并继续记录。</answer>"
        ])
        let client = LocalMedicalAIClient(
            modelURL: URL(fileURLWithPath: "/tmp/test-model.gguf"),
            runtime: runtime
        )

        let response = try await client.respond(to: Self.trendRequest())

        #expect(!response.message.contains("天气变化"))
        #expect(response.message.contains("甲药有忽略记录"))
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

    private static func trendRequest() -> MedicalAIRequest {
        let medication = Medication(
            displayName: "甲药",
            genericName: "合成测试药品",
            kind: .overTheCounter,
            form: "片剂",
            strength: "10 mg",
            inputSource: .demoData
        )
        return MedicalAIRequest(
            kind: .chat,
            userMessage: "近期忽略或稍后趋势如何？",
            authorization: MedicalAIUserAuthorization(grantedScopes: [.medicationProfile]),
            medicationSnapshots: [MedicalAIMedicationSnapshot(medication: medication)]
        )
    }
}

private actor StubLocalMedicalRuntime: LocalMedicalGenerating {
    private var outputs: [String]
    nonisolated let streamDeltas: [String]
    private let delay: Duration?
    private(set) var callCount = 0

    init(outputs: [String], streamDeltas: [String] = [], delay: Duration? = nil) {
        self.outputs = outputs
        self.streamDeltas = streamDeltas
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

    nonisolated func generateResponseStream(
        prompt: String,
        modelURL: URL,
        maxTokens: Int
    ) -> LocalMedicalGenerationStream {
        let (stream, continuation) = AsyncThrowingStream<String, Error>.makeStream()
        for delta in streamDeltas {
            continuation.yield(delta)
        }
        continuation.finish()
        return LocalMedicalGenerationStream(stream: stream) {}
    }
}
