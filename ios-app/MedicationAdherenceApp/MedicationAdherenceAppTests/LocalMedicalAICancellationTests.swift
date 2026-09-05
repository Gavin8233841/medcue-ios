import Foundation
import MedicationAdherenceCore
import Testing
@testable import MedicationAdherenceApp

/// Issue #6: cancellation of a local AI request must propagate through the
/// client stream into the runtime worker, must never surface as a generation
/// failure, and must leave room for an immediate retry. These tests drive the
/// client through a scripted `LocalMedicalGenerating` seam and the view's
/// first-write operation against shared UI state; no real GGUF model or llama
/// binary is involved.
struct LocalMedicalAICancellationTests {
    @Test(arguments: [false, true]) @MainActor
    func delayedLocalTaskCannotResetRetryStreamingUI(cancelStaleTask: Bool) async throws {
        let startGate = StreamReturnGate()
        let staleExecutionID = UUID()
        let retryExecutionID = UUID()
        var activeRequestID: UUID? = staleExecutionID
        var response: LocalStreamingAIResponse?
        let staleTask = Task { @MainActor in
            await startGate.wait()
            return AIAssistantView.beginLocalStreamingResponse(
                executionID: staleExecutionID,
                activeRequestID: activeRequestID,
                response: &response
            )
        }
        if cancelStaleTask {
            staleTask.cancel()
        }

        activeRequestID = retryExecutionID
        let retryTask = Task { @MainActor in
            let started = AIAssistantView.beginLocalStreamingResponse(
                executionID: retryExecutionID,
                activeRequestID: activeRequestID,
                response: &response
            )
            response?.statusText = "retry-status"
            response?.answerText = "retry-answer"
            response?.thinkingText = "retry-thinking"
            response?.isThinkingExpanded = false
            return started
        }
        #expect(await retryTask.value)
        let retryResponse = response

        // Both tasks use the view's real first-write operation on one shared
        // UI response, with the old operation forced to run after the retry.
        await startGate.open()
        #expect(await staleTask.value == false)
        let confirmedRetryResponse = try #require(retryResponse)
        #expect(activeRequestID == retryExecutionID)
        #expect(response?.startedAt == confirmedRetryResponse.startedAt)
        #expect(response?.statusText == "retry-status")
        #expect(response?.answerText == "retry-answer")
        #expect(response?.thinkingText == "retry-thinking")
        #expect(response?.isThinkingExpanded == false)
    }

    @Test @MainActor
    func cancelledLocalTaskCannotCreateStreamingUIWhileStillCurrent() async {
        let startGate = StreamReturnGate()
        let executionID = UUID()
        var response: LocalStreamingAIResponse?
        let task = Task { @MainActor in
            await startGate.wait()
            return AIAssistantView.beginLocalStreamingResponse(
                executionID: executionID,
                activeRequestID: executionID,
                response: &response
            )
        }
        task.cancel()
        await startGate.open()

        #expect(await task.value == false)
        #expect(response == nil)
    }

    @Test @MainActor
    func localTaskCannotCreateStreamingUIAfterRequestWasCleared() {
        var response: LocalStreamingAIResponse?
        let started = AIAssistantView.beginLocalStreamingResponse(
            executionID: UUID(),
            activeRequestID: nil,
            response: &response
        )

        #expect(!started)
        #expect(response == nil)
    }

    @Test
    func cancellationAfterRuntimeStreamCreationBeforeConsumptionTerminatesRuntime() async {
        let returnGate = StreamReturnGate()
        let runtime = CancellationFakeRuntime(
            plans: [
                StreamPlan(
                    initialDelay: .seconds(5),
                    deltas: ["<answer>不应继续生成。</answer>"]
                )
            ],
            returnGate: returnGate
        )
        let client = LocalMedicalAIClient(
            modelURL: URL(fileURLWithPath: "/tmp/test-model.gguf"),
            runtime: runtime
        )
        let collector = EventCollector()
        let consumer = consume(client: client, into: collector)

        #expect(await waitUntil { await runtime.streamCallCount == 1 })
        consumer.cancel()
        await returnGate.open()
        await consumer.value

        #expect(await collector.failureCount == 0)
        #expect(await collector.completionCount == 0)
        #expect(await waitUntil { await runtime.terminationCount == 1 })
    }

    @Test
    func cancellationBeforeGenerationStartsProducesNoFailureOrCompletion() async {
        let runtime = CancellationFakeRuntime(plans: [
            StreamPlan(initialDelay: .milliseconds(300), deltas: ["<answer>今天可以核对提醒并及时记录处理情况。</answer>"])
        ])
        let client = LocalMedicalAIClient(
            modelURL: URL(fileURLWithPath: "/tmp/test-model.gguf"),
            runtime: runtime
        )
        let collector = EventCollector()
        let consumer = consume(client: client, into: collector)
        consumer.cancel()
        await consumer.value

        #expect(await collector.failureCount == 0)
        #expect(await collector.completionCount == 0)
        #expect(await collector.answerDeltaCount == 0)
        // Depending on scheduling the worker may observe cancellation before
        // it ever reaches the runtime; every runtime stream that was created
        // must have been terminated exactly once.
        #expect(await waitUntil { await runtime.terminationCount == runtime.streamCallCount })
        #expect(await runtime.streamCallCount <= 1)
    }

    @Test
    func cancellationDuringStreamingStopsTokenDelivery() async {
        let runtime = CancellationFakeRuntime(plans: [
            StreamPlan(
                deltas: ["<answer>今天", "可以核对", "提醒并", "及时记录", "处理情况。</answer>"],
                gap: .milliseconds(60)
            )
        ])
        let client = LocalMedicalAIClient(
            modelURL: URL(fileURLWithPath: "/tmp/test-model.gguf"),
            runtime: runtime
        )
        let collector = EventCollector()
        let consumer = consume(client: client, into: collector)
        #expect(await waitUntil { await collector.answerDeltaCount >= 1 })
        consumer.cancel()
        await consumer.value

        #expect(await collector.answerDeltaCount < 5)
        #expect(await collector.failureCount == 0)
        #expect(await collector.completionCount == 0)
        #expect(await waitUntil { await runtime.terminationCount == 1 })
    }

    @Test
    func lateRuntimeEventsAfterCancellationAreRejected() async {
        let runtime = CancellationFakeRuntime(plans: [
            StreamPlan(
                deltas: ["<answer>今天", "可以核对", "提醒并", "及时记录", "处理情况。</answer>"],
                gap: .milliseconds(40),
                ignoreCancellation: true
            )
        ])
        let client = LocalMedicalAIClient(
            modelURL: URL(fileURLWithPath: "/tmp/test-model.gguf"),
            runtime: runtime
        )
        let collector = EventCollector()
        let consumer = consume(client: client, into: collector)
        #expect(await waitUntil { await collector.answerDeltaCount >= 1 })
        consumer.cancel()
        await consumer.value
        // Allow the rude runtime to finish attempting its late deliveries.
        try? await Task.sleep(for: .milliseconds(300))

        #expect(await collector.answerDeltaCount < 5)
        #expect(await collector.failureCount == 0)
        #expect(await collector.completionCount == 0)
        #expect(await runtime.terminationCount == 1)
    }

    @Test
    func cancellationSuppressesLateNonCancellationError() async {
        let runtime = CancellationFakeRuntime(plans: [
            StreamPlan(
                deltas: ["<answer>今天", "可以核对", "提醒并", "及时记录", "处理情况。</answer>"],
                gap: .milliseconds(40),
                failure: .runtimeUnavailable,
                ignoreCancellation: true
            )
        ])
        let client = LocalMedicalAIClient(
            modelURL: URL(fileURLWithPath: "/tmp/test-model.gguf"),
            runtime: runtime
        )
        let collector = EventCollector()
        let consumer = consume(client: client, into: collector)
        #expect(await waitUntil { await collector.answerDeltaCount >= 1 })
        consumer.cancel()
        await consumer.value
        try? await Task.sleep(for: .milliseconds(300))

        #expect(await collector.failureCount == 0)
        #expect(await collector.completionCount == 0)
        #expect(await runtime.terminationCount == 1)
    }

    @Test
    func cancellationBetweenParserEventsStopsTheRemainingEvents() async {
        let runtime = CancellationFakeRuntime(plans: [
            StreamPlan(
                initialDelay: .milliseconds(100),
                deltas: ["<think>先核对记录。</think><answer>今天按提醒核对。</answer>"]
            )
        ])
        let client = LocalMedicalAIClient(
            modelURL: URL(fileURLWithPath: "/tmp/test-model.gguf"),
            runtime: runtime
        )
        let collector = EventCollector()
        let handle = ConsumerHandle()
        let consumer = consume(client: client, into: collector) { event in
            if case .thinkingStarted = event {
                await handle.cancel()
            }
        }
        await handle.install(consumer)
        #expect(await waitUntil { await collector.thinkingStartedCount == 1 })
        await consumer.value

        #expect(await collector.answerDeltaCount == 0)
        #expect(await collector.completionCount == 0)
        #expect(await collector.failureCount == 0)
        #expect(await runtime.terminationCount == 1)
    }

    @Test
    func runtimeStreamCleanupRunsExactlyOncePerRequest() async {
        let runtime = CancellationFakeRuntime(plans: [
            StreamPlan(
                deltas: ["<answer>今天", "可以核对", "提醒并", "及时记录", "处理情况。</answer>"],
                gap: .milliseconds(50)
            )
        ])
        let client = LocalMedicalAIClient(
            modelURL: URL(fileURLWithPath: "/tmp/test-model.gguf"),
            runtime: runtime
        )
        let collector = EventCollector()
        let consumer = consume(client: client, into: collector)
        #expect(await waitUntil { await collector.answerDeltaCount >= 1 })
        consumer.cancel()
        await consumer.value

        #expect(await waitUntil { await runtime.terminationCount == 1 })
        try? await Task.sleep(for: .milliseconds(200))
        #expect(await runtime.terminationCount == 1)
        #expect(await runtime.streamCallCount == 1)
    }

    @Test
    func normalCompletionReleasesRuntimeExactlyOnce() async {
        let runtime = CancellationFakeRuntime(plans: [
            StreamPlan(deltas: ["<answer>今天可以核对提醒并及时记录处理情况。</answer>"])
        ])
        let client = LocalMedicalAIClient(
            modelURL: URL(fileURLWithPath: "/tmp/test-model.gguf"),
            runtime: runtime
        )
        let collector = EventCollector()
        let consumer = consume(client: client, into: collector)
        await consumer.value

        #expect(await collector.failureCount == 0)
        #expect(await collector.completionCount == 1)
        #expect(await waitUntil { await runtime.terminationCount == 1 })
        try? await Task.sleep(for: .milliseconds(100))
        #expect(await runtime.terminationCount == 1)
    }

    @Test
    func cancelThenImmediateRetryCompletesNewRequestIndependently() async {
        let runtime = CancellationFakeRuntime(plans: [
            StreamPlan(
                initialDelay: .milliseconds(150),
                deltas: ["<answer>旧请求", "不应该", "完成。</answer>"],
                gap: .milliseconds(150)
            ),
            StreamPlan(deltas: ["<answer>今天可以核对提醒并及时记录处理情况。</answer>"])
        ])
        let client = LocalMedicalAIClient(
            modelURL: URL(fileURLWithPath: "/tmp/test-model.gguf"),
            runtime: runtime
        )
        let staleCollector = EventCollector()
        let retryCollector = EventCollector()

        let staleConsumer = consume(client: client, into: staleCollector)
        // Wait until the stale request has actually reached the runtime so the
        // cancel below cannot race ahead of the first stream creation.
        #expect(await waitUntil { await runtime.streamCallCount >= 1 })
        staleConsumer.cancel()

        let retryConsumer = consume(client: client, into: retryCollector)
        await staleConsumer.value
        await retryConsumer.value

        #expect(await staleCollector.completionCount == 0)
        #expect(await staleCollector.failureCount == 0)
        #expect(await retryCollector.failureCount == 0)
        let completions = await retryCollector.completions
        #expect(completions.count == 1)
        #expect(completions.first?.answer.contains("核对提醒") == true)
        #expect(await runtime.streamCallCount == 2)
        #expect(await runtime.generateResponseCallCount == 0)
    }

    @Test
    func runtimeCancellationErrorIsNotReportedAsGenerationFailure() async {
        let runtime = CancellationFakeRuntime(plans: [
            StreamPlan(deltas: ["<answer>今天"], failure: .cancellation)
        ])
        let client = LocalMedicalAIClient(
            modelURL: URL(fileURLWithPath: "/tmp/test-model.gguf"),
            runtime: runtime
        )
        let collector = EventCollector()
        let consumer = consume(client: client, into: collector)
        await consumer.value

        #expect(await collector.threwCancellation)
        #expect(await collector.failureCount == 0)
        #expect(await collector.completionCount == 0)
    }

    @Test
    func nonCancellationErrorYieldsExactlyOneFailureEvent() async {
        let runtime = CancellationFakeRuntime(plans: [
            StreamPlan(deltas: ["<answer>今天"], failure: .runtimeUnavailable)
        ])
        let client = LocalMedicalAIClient(
            modelURL: URL(fileURLWithPath: "/tmp/test-model.gguf"),
            runtime: runtime
        )
        let collector = EventCollector()
        let consumer = consume(client: client, into: collector)
        await consumer.value

        #expect(await collector.failureCount == 1)
        #expect(await collector.completionCount == 0)
        #expect(await collector.threwCancellation == false)
        #expect(await collector.thrownErrorDescription == String(describing: LocalMedicalAIError.runtimeUnavailable))
    }

    private func consume(
        client: LocalMedicalAIClient,
        into collector: EventCollector,
        afterEvent: (@Sendable (LocalLLMGenerationEvent) async -> Void)? = nil
    ) -> Task<Void, Never> {
        Task {
            let stream = client.streamResponse(to: Self.request())
            do {
                for try await event in stream {
                    await collector.record(event)
                    await afterEvent?(event)
                }
            } catch {
                await collector.recordError(error)
            }
        }
    }

    private func waitUntil(
        timeout: Duration = .seconds(5),
        condition: @escaping @Sendable () async -> Bool
    ) async -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while clock.now < deadline {
            if await condition() {
                return true
            }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return await condition()
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

private struct StreamPlan: Sendable {
    enum Failure: Sendable {
        case none
        case cancellation
        case runtimeUnavailable
    }

    var initialDelay: Duration = .zero
    var deltas: [String] = []
    var gap: Duration = .zero
    var failure: Failure = .none
    var ignoreCancellation = false
}

/// Scripted `LocalMedicalGenerating` seam. Each streaming call dequeues one
/// plan; termination of the returned stream is recorded so tests can prove
/// the client tears the runtime worker down exactly once.
private actor CancellationFakeRuntime: LocalMedicalGenerating {
    private var plans: [StreamPlan]
    private let returnGate: StreamReturnGate?
    private(set) var streamCallCount = 0
    private(set) var terminationCount = 0
    private(set) var generateResponseCallCount = 0

    init(plans: [StreamPlan], returnGate: StreamReturnGate? = nil) {
        self.plans = plans
        self.returnGate = returnGate
    }

    func generateResponse(prompt: String, modelURL: URL, maxTokens: Int) async throws -> String {
        generateResponseCallCount += 1
        throw LocalMedicalAIError.unstableResponse
    }

    func generateResponseStream(
        prompt: String,
        modelURL: URL,
        maxTokens: Int
    ) async -> LocalMedicalGenerationStream {
        streamCallCount += 1
        let plan = plans.isEmpty ? StreamPlan() : plans.removeFirst()
        let (stream, continuation) = AsyncThrowingStream<String, Error>.makeStream()
        let producer = Task {
            if plan.initialDelay > .zero {
                try? await Task.sleep(for: plan.initialDelay)
            }
            for delta in plan.deltas {
                if plan.gap > .zero {
                    try? await Task.sleep(for: plan.gap)
                }
                if !plan.ignoreCancellation, Task.isCancelled {
                    break
                }
                continuation.yield(delta)
            }
            switch plan.failure {
            case .none:
                continuation.finish()
            case .cancellation:
                continuation.finish(throwing: CancellationError())
            case .runtimeUnavailable:
                continuation.finish(throwing: LocalMedicalAIError.runtimeUnavailable)
            }
        }
        continuation.onTermination = { @Sendable _ in
            producer.cancel()
            Task {
                await self.recordTermination()
            }
        }
        let generation = LocalMedicalGenerationStream(stream: stream) {
            producer.cancel()
            continuation.finish(throwing: CancellationError())
        }
        if let returnGate {
            await returnGate.wait()
        }
        return generation
    }

    private func recordTermination() {
        terminationCount += 1
    }
}

private actor StreamReturnGate {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        guard !isOpen else {
            return
        }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func open() {
        guard !isOpen else {
            return
        }
        isOpen = true
        let pendingWaiters = waiters
        waiters.removeAll()
        pendingWaiters.forEach { $0.resume() }
    }
}

private actor EventCollector {
    private(set) var events: [LocalLLMGenerationEvent] = []
    private(set) var threwCancellation = false
    private(set) var thrownErrorDescription: String?

    func record(_ event: LocalLLMGenerationEvent) {
        events.append(event)
    }

    func recordError(_ error: Error) {
        threwCancellation = error is CancellationError
        thrownErrorDescription = String(describing: error)
    }

    var answerDeltaCount: Int {
        events.filter { event in
            if case .answerDelta = event {
                return true
            }
            return false
        }.count
    }

    var thinkingStartedCount: Int {
        events.filter { event in
            if case .thinkingStarted = event {
                return true
            }
            return false
        }.count
    }

    var failureCount: Int {
        events.filter { event in
            if case .generationFailed = event {
                return true
            }
            return false
        }.count
    }

    var completionCount: Int {
        completions.count
    }

    var completions: [(answer: String, thinking: String)] {
        events.compactMap { event in
            if case let .generationCompleted(answer, thinking) = event {
                return (answer, thinking)
            }
            return nil
        }
    }
}

private actor ConsumerHandle {
    private var task: Task<Void, Never>?

    func install(_ task: Task<Void, Never>) {
        self.task = task
    }

    func cancel() {
        task?.cancel()
    }
}
