import Foundation
import Testing
@testable import MedicationAdherenceApp

struct FoundationModelsLocalRuntimeTests {
    @Test func forwardsExistingContextAndTokenLimit() async throws {
        guard #available(iOS 27.0, *) else { return }
        let backing = FoundationAdapterTestRuntime()
        let runtime = FoundationModelsLocalRuntime(backing: backing)
        let prompt = "历史：用户说今天散步20分钟。\n当前问题：我刚才做了什么？"
        let answer = try await runtime.generateResponse(
            prompt: prompt, modelURL: URL(fileURLWithPath: "/tmp/test.gguf"), maxTokens: 137
        )
        #expect(answer == "你好，世界！")
        #expect(await backing.lastPrompt == prompt)
        #expect(await backing.lastMaxTokens == 137)
        #expect(await backing.calls == 1)
    }

    @Test func streamingDoesNotDuplicateCumulativeSnapshots() async throws {
        guard #available(iOS 27.0, *) else { return }
        let backing = FoundationAdapterTestRuntime()
        let runtime = FoundationModelsLocalRuntime(backing: backing)
        var answer = ""
        for try await delta in runtime.generateResponseStream(
            prompt: "hi", modelURL: URL(fileURLWithPath: "/tmp/test.gguf"), maxTokens: 100
        ) { answer += delta }
        #expect(answer == "你好，世界！")
        #expect(await backing.calls == 1)
    }

    @Test func propagatesInferenceFailure() async {
        guard #available(iOS 27.0, *) else { return }
        let runtime = FoundationModelsLocalRuntime(backing: FoundationAdapterTestRuntime(shouldFail: true))
        do {
            _ = try await runtime.generateResponse(
                prompt: "hi", modelURL: URL(fileURLWithPath: "/tmp/test.gguf"), maxTokens: 100
            )
            Issue.record("Expected the inference error to reach the caller")
        } catch {}
    }

    @Test func streamingPreservesSplitCombiningCharacters() async throws {
        guard #available(iOS 27.0, *) else { return }
        let fragments = ["e", "\u{301}", "👩", "\u{200D}", "⚕", "\u{FE0F}"]
        let runtime = FoundationModelsLocalRuntime(backing: FoundationAdapterTestRuntime(deltas: fragments))
        var answer = ""
        for try await delta in runtime.generateResponseStream(
            prompt: "hi", modelURL: URL(fileURLWithPath: "/tmp/test.gguf"), maxTokens: 100
        ) { answer += delta }
        #expect(Array(answer.unicodeScalars) == Array(fragments.joined().unicodeScalars))
    }

    @Test func cancellationReachesBackingInference() async throws {
        guard #available(iOS 27.0, *) else { return }
        let backing = FoundationAdapterTestRuntime(holdOpen: true)
        let runtime = FoundationModelsLocalRuntime(backing: backing)
        let worker = Task {
            for try await _ in runtime.generateResponseStream(
                prompt: "hi", modelURL: URL(fileURLWithPath: "/tmp/test.gguf"), maxTokens: 100
            ) {}
        }
        for _ in 0..<100 {
            if await backing.calls > 0 { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(await backing.calls == 1)
        worker.cancel()
        _ = await worker.result
        for _ in 0..<100 {
            if await backing.wasCancelled { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(await backing.wasCancelled)
    }

}

private actor FoundationAdapterTestRuntime: LocalMedicalGenerating {
    var lastPrompt = ""
    var lastMaxTokens = 0
    var calls = 0
    var wasCancelled = false
    let shouldFail: Bool
    let holdOpen: Bool
    let deltas: [String]
    init(shouldFail: Bool = false, holdOpen: Bool = false, deltas: [String] = ["你", "好，", "世界", "！"]) {
        self.shouldFail = shouldFail
        self.holdOpen = holdOpen
        self.deltas = deltas
    }
    private func recordCancellation() { wasCancelled = true }

    func generateResponse(prompt: String, modelURL: URL, maxTokens: Int) async throws -> String {
        Issue.record("Foundation Models should call the executor's streaming path")
        return ""
    }

    func generateResponseStream(prompt: String, modelURL: URL, maxTokens: Int) -> AsyncThrowingStream<String, Error> {
        calls += 1
        lastPrompt = prompt
        lastMaxTokens = maxTokens
        return AsyncThrowingStream { continuation in
            let worker = Task {
                do {
                    if shouldFail { throw LocalMedicalAIError.runtimeUnavailable }
                    for delta in deltas {
                        continuation.yield(delta)
                        try await Task.sleep(for: .milliseconds(20))
                    }
                    if holdOpen { try await Task.sleep(for: .seconds(60)) }
                    continuation.finish()
                } catch {
                    if error is CancellationError { recordCancellation() }
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { @Sendable _ in worker.cancel() }
        }
    }
}
