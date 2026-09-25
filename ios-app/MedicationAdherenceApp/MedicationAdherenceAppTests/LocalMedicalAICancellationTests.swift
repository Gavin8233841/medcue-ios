import Foundation
import MedicationAdherenceCore
import os
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
    func cancellationDuringRuntimePreparationReleasesProducer() async throws {
        let preparationGate = CancellationPreparationGate()
        let runtime = CancellationFakeRuntime(plans: [
            StreamPlan(
                deltas: ["<answer>不应继续生成。</answer>"],
                preparationGate: preparationGate
            )
        ])
        let client = LocalMedicalAIClient(
            modelURL: URL(fileURLWithPath: "/tmp/test-model.gguf"),
            runtime: runtime
        )
        let collector = EventCollector()
        let consumer = consume(client: client, into: collector)
        defer {
            consumer.cancel()
            // Failure-only safety net: all acceptance assertions run before
            // this cleanup, so it cannot make the cancellation test pass.
            preparationGate.cancel()
        }

        try #require(await waitUntil { preparationGate.isWaiting })
        #expect(await runtime.activeProducerCount == 1)
        #expect(await runtime.generationStartCount == 0)
        consumer.cancel()
        try #require(await waitUntil { await runtime.producerExitCount == 1 })
        await consumer.value

        #expect(preparationGate.cancellationResumeCount == 1)
        #expect(!preparationGate.isWaiting)
        #expect(await runtime.activeProducerCount == 0)
        #expect(await runtime.generationStartCount == 0)
        #expect(await collector.answerDeltaCount == 0)
        #expect(await collector.failureCount == 0)
        #expect(await collector.completionCount == 0)
        #expect(await waitUntil { await runtime.terminationCount == 1 })
    }

    @Test
    func cancellingDeliveredHandleBeforeConsumptionReleasesPreparation() async throws {
        let preparationGate = CancellationPreparationGate()
        let runtime = CancellationFakeRuntime(plans: [
            StreamPlan(
                deltas: ["<answer>不应继续生成。</answer>"],
                preparationGate: preparationGate
            )
        ])
        let generator: any LocalMedicalGenerating = runtime
        // Calling through the protocol must deliver a handle synchronously,
        // even while the worker will be waiting for preparation to finish.
        let generation = generator.generateResponseStream(
            prompt: "仅用于取消测试。",
            modelURL: URL(fileURLWithPath: "/tmp/test-model.gguf"),
            maxTokens: 1
        )
        defer {
            generation.cancel()
            preparationGate.cancel()
        }

        try #require(await waitUntil { preparationGate.isWaiting })
        generation.cancel()
        try #require(await waitUntil { await runtime.producerExitCount == 1 })

        #expect(preparationGate.cancellationResumeCount == 1)
        #expect(!preparationGate.isWaiting)
        #expect(await runtime.activeProducerCount == 0)
        #expect(await runtime.generationStartCount == 0)
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
        #expect(await waitUntil { await runtime.producerExitCount == 1 })
        try? await Task.sleep(for: .milliseconds(200))
        #expect(await runtime.terminationCount == 1)
        #expect(await runtime.producerExitCount == 1)
        #expect(await runtime.activeProducerCount == 0)
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
        #expect(await waitUntil { await runtime.producerExitCount == 1 })
        try? await Task.sleep(for: .milliseconds(100))
        #expect(await runtime.terminationCount == 1)
        #expect(await runtime.producerExitCount == 1)
        #expect(await runtime.activeProducerCount == 0)
    }

    @Test
    func cancelThenImmediateRetryCompletesNewRequestIndependently() async throws {
        let preparationGates = (0..<3).map { _ in CancellationPreparationGate() }
        let runtime = CancellationFakeRuntime(plans: preparationGates.flatMap { preparationGate in
            [
                StreamPlan(
                    deltas: ["<answer>旧请求不应该完成。</answer>"],
                    preparationGate: preparationGate
                ),
                StreamPlan(deltas: ["<answer>今天可以核对提醒并及时记录处理情况。</answer>"])
            ]
        })
        let client = LocalMedicalAIClient(
            modelURL: URL(fileURLWithPath: "/tmp/test-model.gguf"),
            runtime: runtime
        )
        for (index, preparationGate) in preparationGates.enumerated() {
            let staleCollector = EventCollector()
            let retryCollector = EventCollector()
            let staleConsumer = consume(client: client, into: staleCollector)
            defer {
                staleConsumer.cancel()
                preparationGate.cancel()
            }

            try #require(await waitUntil { preparationGate.isWaiting })
            staleConsumer.cancel()
            // Start the retry before joining the cancelled consumer or worker.
            let retryConsumer = consume(client: client, into: retryCollector)
            defer { retryConsumer.cancel() }
            try #require(await waitUntil { await retryCollector.completionCount == 1 })
            try #require(await waitUntil { await runtime.producerExitCount == (index + 1) * 2 })
            await staleConsumer.value
            await retryConsumer.value

            #expect(preparationGate.cancellationResumeCount == 1)
            #expect(!preparationGate.isWaiting)
            #expect(await runtime.activeProducerCount == 0)
            #expect(await staleCollector.answerDeltaCount == 0)
            #expect(await staleCollector.completionCount == 0)
            #expect(await staleCollector.failureCount == 0)
            #expect(await retryCollector.failureCount == 0)
            let completions = await retryCollector.completions
            #expect(completions.count == 1)
            #expect(completions.first?.answer.contains("核对提醒") == true)
        }
        #expect(await runtime.streamCallCount == 6)
        #expect(await runtime.producerExitCount == 6)
        #expect(await runtime.generationStartCount == 3)
        #expect(await waitUntil { await runtime.terminationCount == 6 })
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
    var preparationGate: CancellationPreparationGate?
}

/// Scripted `LocalMedicalGenerating` seam. The handle is delivered before
/// the worker enters this actor and dequeues its plan. Stream termination and
/// actual worker exit are counted separately; neither proves llama teardown.
private actor CancellationFakeRuntime: LocalMedicalGenerating {
    private var plans: [StreamPlan]
    private(set) var streamCallCount = 0
    private(set) var terminationCount = 0
    private(set) var activeProducerCount = 0
    private(set) var producerExitCount = 0
    private(set) var generationStartCount = 0
    private(set) var generateResponseCallCount = 0

    init(plans: [StreamPlan]) {
        self.plans = plans
    }

    func generateResponse(prompt: String, modelURL: URL, maxTokens: Int) async throws -> String {
        generateResponseCallCount += 1
        throw LocalMedicalAIError.unstableResponse
    }

    nonisolated func generateResponseStream(
        prompt: String,
        modelURL: URL,
        maxTokens: Int
    ) -> LocalMedicalGenerationStream {
        let (stream, continuation) = AsyncThrowingStream<String, Error>.makeStream()
        let producer = Task {
            await self.produce(into: continuation)
        }
        continuation.onTermination = { @Sendable _ in
            producer.cancel()
            Task {
                await self.recordTermination()
            }
        }
        return LocalMedicalGenerationStream(stream: stream) {
            producer.cancel()
            continuation.finish(throwing: CancellationError())
        }
    }

    private func produce(into continuation: AsyncThrowingStream<String, Error>.Continuation) async {
        streamCallCount += 1
        let plan = plans.isEmpty ? StreamPlan() : plans.removeFirst()
        activeProducerCount += 1
        defer {
            activeProducerCount -= 1
            producerExitCount += 1
        }
        do {
            if let preparationGate = plan.preparationGate {
                try await preparationGate.wait()
            }
            if !plan.ignoreCancellation {
                try Task.checkCancellation()
            }
            generationStartCount += 1
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
        } catch {
            continuation.finish(throwing: error)
        }
    }

    private func recordTermination() {
        terminationCount += 1
    }
}

/// A single-use preparation wait that has no successful/open path. The
/// producer's cancellation handler must release its continuation. The lock
/// also handles cancellation arriving before continuation registration.
private final class CancellationPreparationGate: Sendable {
    private struct State: Sendable {
        var isCancelled = false
        var continuation: CheckedContinuation<Void, Error>?
        var cancellationResumeCount = 0
    }

    private let state = OSAllocatedUnfairLock(initialState: State())

    var isWaiting: Bool {
        state.withLock { $0.continuation != nil }
    }

    var cancellationResumeCount: Int {
        state.withLock { $0.cancellationResumeCount }
    }

    func wait() async throws {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                let shouldResume = state.withLock { state in
                    if state.isCancelled {
                        state.cancellationResumeCount += 1
                        return true
                    }
                    precondition(state.continuation == nil)
                    state.continuation = continuation
                    return false
                }
                if shouldResume {
                    continuation.resume(throwing: CancellationError())
                }
            }
        } onCancel: {
            cancel()
        }
    }

    func cancel() {
        let continuation = state.withLock { state in
            guard !state.isCancelled else { return nil as CheckedContinuation<Void, Error>? }
            state.isCancelled = true
            let continuation = state.continuation
            state.continuation = nil
            if continuation != nil {
                state.cancellationResumeCount += 1
            }
            return continuation
        }
        continuation?.resume(throwing: CancellationError())
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
