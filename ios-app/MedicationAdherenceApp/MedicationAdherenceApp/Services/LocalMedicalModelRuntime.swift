import Foundation
#if canImport(FoundationModels) && compiler(>=6.4)
import FoundationModels
#endif
#if canImport(llama)
import llama
#endif

protocol LocalMedicalGenerating: Sendable {
    func generateResponse(prompt: String, modelURL: URL, maxTokens: Int) async throws -> String
    func generateResponseStream(
        prompt: String,
        modelURL: URL,
        maxTokens: Int
    ) -> LocalMedicalGenerationStream
}

struct LocalMedicalGenerationStream: Sendable {
    let stream: AsyncThrowingStream<String, Error>
    private let cancelAction: @Sendable () -> Void

    init(
        stream: AsyncThrowingStream<String, Error>,
        cancelAction: @escaping @Sendable () -> Void
    ) {
        self.stream = stream
        self.cancelAction = cancelAction
    }

    func cancel() {
        cancelAction()
    }
}

actor LocalMedicalModelRuntime: LocalMedicalGenerating {
    static let shared = LocalMedicalModelRuntime()
    private let thinkingEnabled: Bool

    init(thinkingEnabled: Bool = false) {
        self.thinkingEnabled = thinkingEnabled
    }


    static var isAvailable: Bool {
        #if canImport(llama)
        true
        #else
        false
        #endif
    }

    var isReady: Bool {
        Self.isAvailable
    }

    nonisolated func generateResponse(prompt: String, modelURL: URL, maxTokens: Int) async throws -> String {
        let cancellationSignal = LlamaCancellationSignal()
        do {
            return try await withTaskCancellationHandler(operation: {
                let response = try await runGeneration(
                    prompt: prompt,
                    modelURL: modelURL,
                    maxTokens: maxTokens,
                    cancellationSignal: cancellationSignal
                )
                try cancellationSignal.checkCancellation()
                let trimmedResponse = response.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmedResponse.isEmpty else {
                    throw LocalMedicalAIError.emptyResponse
                }
                return trimmedResponse
            }, onCancel: {
                cancellationSignal.cancel()
            })
        } catch {
            if Task.isCancelled || cancellationSignal.isCancelled {
                throw CancellationError()
            }
            throw error
        }
    }

    // Return the cancellation handle without waiting for the native actor.
    // Only runGeneration creates and releases llama contexts, so a cancelled
    // request and its immediate retry cannot overlap backend init/free.
    nonisolated func generateResponseStream(prompt: String, modelURL: URL, maxTokens: Int) -> LocalMedicalGenerationStream {
        let (stream, continuation) = AsyncThrowingStream<String, Error>.makeStream()
        let cancellationSignal = LlamaCancellationSignal()
        if Task.isCancelled {
            cancellationSignal.cancel()
        }
        let worker = Task {
            do {
                try await withTaskCancellationHandler(operation: {
                    _ = try await self.runGeneration(
                        prompt: prompt,
                        modelURL: modelURL,
                        maxTokens: maxTokens,
                        cancellationSignal: cancellationSignal
                    ) { delta in
                        guard !delta.isEmpty, !cancellationSignal.isCancelled else {
                            return
                        }
                        continuation.yield(delta)
                    }
                    try cancellationSignal.checkCancellation()
                    continuation.finish()
                }, onCancel: {
                    cancellationSignal.cancel()
                })
            } catch {
                if Task.isCancelled || cancellationSignal.isCancelled {
                    continuation.finish(throwing: CancellationError())
                } else {
                    continuation.finish(throwing: error)
                }
            }
        }
        continuation.onTermination = { @Sendable _ in
            cancellationSignal.cancel()
            worker.cancel()
        }
        return LocalMedicalGenerationStream(stream: stream) {
            cancellationSignal.cancel()
            worker.cancel()
            continuation.finish(throwing: CancellationError())
        }
    }

    // This actor-isolated operation intentionally has no suspension points.
    // Cancellation reaches native callbacks through the thread-safe signal,
    // not by scheduling another operation on this busy actor.
    private func runGeneration(
        prompt: String,
        modelURL: URL,
        maxTokens: Int,
        cancellationSignal: LlamaCancellationSignal,
        onToken: (@Sendable (String) -> Void)? = nil
    ) throws -> String {
        try cancellationSignal.checkCancellation()
        #if canImport(llama)
        let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPrompt.isEmpty else {
            throw LocalMedicalAIError.emptyResponse
        }
        let context = try LlamaCppContext(modelURL: modelURL, thinkingEnabled: thinkingEnabled, cancellationSignal: cancellationSignal)
        return try context.generate(prompt: trimmedPrompt, maxTokens: maxTokens, onToken: onToken)
        #else
        throw LocalMedicalAIError.runtimeUnavailable
        #endif
    }
}

private final class LlamaCancellationSignal: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false

    var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }

    func cancel() {
        lock.lock()
        cancelled = true
        lock.unlock()
    }

    func checkCancellation() throws {
        try Task.checkCancellation()
        if isCancelled {
            throw CancellationError()
        }
    }
}

#if canImport(llama)
private func llamaProgressCallback(_ progress: Float, _ userData: UnsafeMutableRawPointer?) -> Bool {
    guard let userData else { return true }
    let signal = Unmanaged<LlamaCancellationSignal>.fromOpaque(userData).takeUnretainedValue()
    return !signal.isCancelled
}

private func llamaAbortCallback(_ userData: UnsafeMutableRawPointer?) -> Bool {
    guard let userData else { return false }
    let signal = Unmanaged<LlamaCancellationSignal>.fromOpaque(userData).takeUnretainedValue()
    return signal.isCancelled
}

private final class LlamaCppContext {
    private var model: OpaquePointer
    private var context: OpaquePointer
    private var vocab: OpaquePointer
    private var sampler: UnsafeMutablePointer<llama_sampler>
    private var pendingUTF8Bytes: [CChar] = []
    private let contextLength = 2048
    private let usesMiniCPM5: Bool
    private let thinkingEnabled: Bool
    private let cancellationSignal: LlamaCancellationSignal

    init(modelURL: URL, thinkingEnabled: Bool, cancellationSignal: LlamaCancellationSignal) throws {
        usesMiniCPM5 = modelURL.lastPathComponent == "MiniCPM5-2B-Q4_K_M.gguf"
        self.thinkingEnabled = thinkingEnabled
        self.cancellationSignal = cancellationSignal
        try cancellationSignal.checkCancellation()
        llama_backend_init()

        var modelParameters = llama_model_default_params()
        modelParameters.progress_callback = llamaProgressCallback
        modelParameters.progress_callback_user_data = Unmanaged.passUnretained(cancellationSignal).toOpaque()
        #if targetEnvironment(simulator)
        modelParameters.n_gpu_layers = 0
        #endif

        guard let loadedModel = llama_model_load_from_file(modelURL.path, modelParameters) else {
            llama_backend_free()
            try cancellationSignal.checkCancellation()
            throw LocalMedicalAIError.modelMissing
        }

        // Until initialization succeeds, Swift will not call deinit. Keep
        // ownership local so every cancellation/failure releases what exists.
        var loadedContext: OpaquePointer?
        var initialized = false
        defer {
            if !initialized {
                withExtendedLifetime(cancellationSignal) {
                    if let loadedContext {
                        llama_free(loadedContext)
                    }
                    llama_model_free(loadedModel)
                    llama_backend_free()
                }
            }
        }
        try cancellationSignal.checkCancellation()

        let threadCount = max(1, min(8, ProcessInfo.processInfo.processorCount - 2))
        var contextParameters = llama_context_default_params()
        contextParameters.n_ctx = UInt32(contextLength)
        contextParameters.n_batch = UInt32(contextLength)
        contextParameters.n_ubatch = min(contextParameters.n_ubatch, 512)
        contextParameters.n_threads = Int32(threadCount)
        contextParameters.n_threads_batch = Int32(threadCount)
        // The bundled llama.h documents this hook for CPU execution only.
        // GPU offload settings are unchanged; do not promise an in-flight
        // Metal command will be interrupted by this callback.
        contextParameters.abort_callback = llamaAbortCallback
        contextParameters.abort_callback_data = Unmanaged.passUnretained(cancellationSignal).toOpaque()

        guard let createdContext = llama_init_from_model(loadedModel, contextParameters) else {
            try cancellationSignal.checkCancellation()
            throw LocalMedicalAIError.runtimeUnavailable
        }
        loadedContext = createdContext
        try cancellationSignal.checkCancellation()
        model = loadedModel
        context = createdContext
        vocab = llama_model_get_vocab(loadedModel)

        let samplerParameters = llama_sampler_chain_default_params()
        sampler = llama_sampler_chain_init(samplerParameters)
        llama_sampler_chain_add(sampler, llama_sampler_init_top_k(40))
        llama_sampler_chain_add(sampler, llama_sampler_init_top_p(0.85, 1))
        llama_sampler_chain_add(sampler, llama_sampler_init_temp(0.0))
        llama_sampler_chain_add(sampler, llama_sampler_init_dist(42))
        initialized = true
    }

    deinit {
        // Both native callbacks borrow this signal. Keep it alive until all
        // native owners are gone, including during failure/cancel teardown.
        withExtendedLifetime(cancellationSignal) {
            llama_sampler_free(sampler)
            llama_free(context)
            llama_model_free(model)
            llama_backend_free()
        }
    }

    func generate(prompt: String, maxTokens: Int, onToken: ((String) -> Void)? = nil) throws -> String {
        try cancellationSignal.checkCancellation()
        pendingUTF8Bytes.removeAll()
        llama_memory_clear(llama_get_memory(context), true)
        llama_sampler_reset(sampler)

        let formattedPrompt = chatFormattedPrompt(for: prompt)
        let tokenLimit = max(
            1,
            min(maxTokens, MedicalAIExecutionPolicy.default.streamingResponseTokenLimit)
        )
        let promptTokens = truncatePromptTokens(
            tokenize(formattedPrompt, addBOS: true),
            maxPromptTokens: max(1, contextLength - tokenLimit - 32)
        )
        guard !promptTokens.isEmpty else {
            throw LocalMedicalAIError.emptyResponse
        }

        try cancellationSignal.checkCancellation()
        var promptTokensForDecode = promptTokens
        let promptDecodeStatus = promptTokensForDecode.withUnsafeMutableBufferPointer { tokens in
            let promptBatch = llama_batch_get_one(tokens.baseAddress, Int32(tokens.count))
            return llama_decode(context, promptBatch)
        }

        guard promptDecodeStatus == 0 else {
            if promptDecodeStatus == 2 || cancellationSignal.isCancelled {
                throw CancellationError()
            }
            throw LocalMedicalAIError.runtimeUnavailable
        }
        try cancellationSignal.checkCancellation()

        // The thinking opener belongs to the prompt; restore the marker for the
        // existing stream parser so reasoning is never mistaken for the answer.
        let opener = usesMiniCPM5 && thinkingEnabled ? "<think>\n" : ""
        var output = opener
        if !opener.isEmpty { onToken?(opener) }
        for _ in 0..<tokenLimit {
            try cancellationSignal.checkCancellation()
            let newToken = llama_sampler_sample(sampler, context, -1)
            try cancellationSignal.checkCancellation()
            if llama_vocab_is_eog(vocab, newToken) {
                output += flushPendingUTF8Bytes()
                break
            }

            let piece = appendTokenPiece(newToken)
            output += piece
            onToken?(piece)
            try cancellationSignal.checkCancellation()
            // llama_sampler_sample already accepts this token into sampler history.
            var tokenForDecode = newToken
            let tokenBatch = llama_batch_get_one(&tokenForDecode, 1)

            let decodeStatus = llama_decode(context, tokenBatch)
            guard decodeStatus == 0 else {
                if decodeStatus == 2 || cancellationSignal.isCancelled {
                    throw CancellationError()
                }
                throw LocalMedicalAIError.runtimeUnavailable
            }
            try cancellationSignal.checkCancellation()
        }

        try cancellationSignal.checkCancellation()
        output += flushPendingUTF8Bytes()
        try cancellationSignal.checkCancellation()
        return output
    }

    private func chatFormattedPrompt(for prompt: String) -> String {
        guard let template = llama_model_chat_template(model, nil) else { return prompt }
        let system = "你是 MedCue 健康助手。仅当用户只是在打招呼时才简短问候；其他问题直接回答，不重复欢迎、自我介绍或邀请。不仿照历史回答中的寒暄。用户要求换语言时立即使用指定语言。用户说身体不适时回应不适并询问症状，不要回复通用欢迎语。一般健康知识可以直接回答，无需个人资料。涉及用户本人的数据才依据提供的资料，缺失时说明并帮助用户找到下一步，不编造个人数值，不诊断或开处方。简短回答，只回应当前问题，不主动展开无关药品、剂量或警告。能力介绍只谈能提供的帮助，不复述个人资料。回答完即结束。"
            + (thinkingEnabled ? "先核对资料再回答。" : "不输出思考过程。")
        let formatted = "system".withCString { systemRole in
            system.withCString { systemContent in
                "user".withCString { userRole in
                    prompt.withCString { content in
                        let messages = [
                            llama_chat_message(role: systemRole, content: systemContent),
                            llama_chat_message(role: userRole, content: content)
                        ]
                        return messages.withUnsafeBufferPointer { messageBuffer in
                            var buffer = [CChar](repeating: 0, count: max(4096, (system.utf8.count + prompt.utf8.count) * 3))
                            let written = llama_chat_apply_template(template, messageBuffer.baseAddress, messages.count, true, &buffer, Int32(buffer.count))
                            guard written > 0 else { return prompt }
                            if written < buffer.count { return decodeNullTerminatedUTF8(buffer) }
                            buffer = [CChar](repeating: 0, count: Int(written) + 1)
                            let largerWritten = llama_chat_apply_template(template, messageBuffer.baseAddress, messages.count, true, &buffer, Int32(buffer.count))
                            guard largerWritten > 0, largerWritten < buffer.count else { return prompt }
                            return decodeNullTerminatedUTF8(buffer)
                        }
                    }
                }
            }
        }
        // Matches the official MiniCPM5 template's enable_thinking=false suffix.
        guard usesMiniCPM5 else { return formatted }
        return formatted + (thinkingEnabled ? "<think>\n" : "<think>\n\n</think>\n\n")
    }

    private func truncatePromptTokens(_ tokens: [llama_token], maxPromptTokens: Int) -> [llama_token] {
        guard tokens.count > maxPromptTokens else {
            return tokens
        }
        let headCount = min(256, maxPromptTokens / 3)
        let tailCount = maxPromptTokens - headCount
        return Array(tokens.prefix(headCount)) + Array(tokens.suffix(tailCount))
    }

    private func tokenize(_ text: String, addBOS: Bool) -> [llama_token] {
        let tokenCapacity = text.utf8.count + (addBOS ? 1 : 0) + 1
        let tokens = UnsafeMutablePointer<llama_token>.allocate(capacity: tokenCapacity)
        defer {
            tokens.deallocate()
        }

        let tokenCount = llama_tokenize(
            vocab,
            text,
            Int32(text.utf8.count),
            tokens,
            Int32(tokenCapacity),
            addBOS,
            true // Recognize the control tokens emitted by the model chat template.
        )
        guard tokenCount > 0 else {
            return []
        }
        return (0..<Int(tokenCount)).map { tokens[$0] }
    }

    private func appendTokenPiece(_ token: llama_token) -> String {
        pendingUTF8Bytes.append(contentsOf: tokenPiece(token))
        let bytes = pendingUTF8Bytes.map { UInt8(bitPattern: $0) }
        if let string = String(bytes: bytes, encoding: .utf8) {
            pendingUTF8Bytes.removeAll()
            return string
        }
        return ""
    }

    private func flushPendingUTF8Bytes() -> String {
        guard !pendingUTF8Bytes.isEmpty else {
            return ""
        }
        let string = String(
            decoding: pendingUTF8Bytes.map { UInt8(bitPattern: $0) },
            as: UTF8.self
        )
        pendingUTF8Bytes.removeAll()
        return string
    }

    private func decodeNullTerminatedUTF8(_ characters: [CChar]) -> String {
        let bytes = characters
            .prefix { $0 != 0 }
            .map { UInt8(bitPattern: $0) }
        return String(decoding: bytes, as: UTF8.self)
    }

    private func tokenPiece(_ token: llama_token) -> [CChar] {
        let initialCapacity: Int32 = 8
        let buffer = UnsafeMutablePointer<CChar>.allocate(capacity: Int(initialCapacity))
        defer {
            buffer.deallocate()
        }

        let count = llama_token_to_piece(vocab, token, buffer, initialCapacity, 0, false)
        if count >= 0 {
            return Array(UnsafeBufferPointer(start: buffer, count: Int(count)))
        }

        let requiredCapacity = Int(-count)
        let largerBuffer = UnsafeMutablePointer<CChar>.allocate(capacity: requiredCapacity)
        defer {
            largerBuffer.deallocate()
        }
        let largerCount = llama_token_to_piece(vocab, token, largerBuffer, Int32(requiredCapacity), 0, false)
        guard largerCount > 0 else {
            return []
        }
        return Array(UnsafeBufferPointer(start: largerBuffer, count: Int(largerCount)))
    }

}
#endif

// The app builds authorized context and history before calling this runtime.
// Each request uses a fresh text session, preserving that existing prompt exactly.
enum LocalMedicalRuntimeFactory {
    static func make(backing: any LocalMedicalGenerating = LocalMedicalModelRuntime.shared) -> any LocalMedicalGenerating {
        #if canImport(FoundationModels) && compiler(>=6.4)
        if #available(iOS 27.0, *) {
            return FoundationModelsLocalRuntime(backing: backing)
        }
        #endif
        return backing
    }
}

#if canImport(FoundationModels) && compiler(>=6.4)
@available(iOS 27.0, *)
struct FoundationModelsLocalRuntime: LocalMedicalGenerating {
    let backing: any LocalMedicalGenerating

    func generateResponse(prompt: String, modelURL: URL, maxTokens: Int) async throws -> String {
        let session = makeSession(modelURL: modelURL, maxTokens: maxTokens)
        return try await session.respond(to: prompt, options: GenerationOptions(maximumResponseTokens: maxTokens)).content
    }

    func generateResponseStream(prompt: String, modelURL: URL, maxTokens: Int) -> LocalMedicalGenerationStream {
        let (stream, continuation) = AsyncThrowingStream<String, Error>.makeStream()
        let worker = Task {
                do {
                    let session = makeSession(modelURL: modelURL, maxTokens: maxTokens)
                    var deliveredCount = 0
                    for try await snapshot in session.streamResponse(to: prompt, options: GenerationOptions(maximumResponseTokens: maxTokens)) {
                        try Task.checkCancellation()
                        let delta = String(String.UnicodeScalarView(snapshot.content.unicodeScalars.dropFirst(deliveredCount)))
                        deliveredCount = snapshot.content.unicodeScalars.count
                        if !delta.isEmpty { continuation.yield(delta) }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        continuation.onTermination = { @Sendable _ in worker.cancel() }
        return LocalMedicalGenerationStream(stream: stream) {
            worker.cancel()
            continuation.finish(throwing: CancellationError())
        }
    }

    private func makeSession(modelURL: URL, maxTokens: Int) -> LanguageModelSession {
        LanguageModelSession(model: LocalFoundationLanguageModel(
            backing: backing,
            executorConfiguration: .init(modelURL: modelURL, maxTokens: maxTokens)
        ))
    }
}

@available(iOS 27.0, *)
private struct LocalFoundationLanguageModel: LanguageModel {
    typealias Executor = LocalFoundationExecutor
    let backing: any LocalMedicalGenerating
    let executorConfiguration: LocalFoundationExecutor.Configuration
    let capabilities = LanguageModelCapabilities([])
}

@available(iOS 27.0, *)
private struct LocalFoundationExecutor: LanguageModelExecutor {
    typealias Model = LocalFoundationLanguageModel
    struct Configuration: Hashable, Sendable {
        let modelURL: URL
        let maxTokens: Int
    }
    let configuration: Configuration

    init(configuration: Configuration) { self.configuration = configuration }

    func respond(to request: LanguageModelExecutorGenerationRequest, model: Model,
                 streamingInto channel: LanguageModelExecutorGenerationChannel) async throws {
        // This private adapter serves the app's fresh, single-prompt sessions only.
        let entries = Array(request.transcript)
        guard entries.count == 1, case let .prompt(input) = entries[0] else {
            throw LanguageModelError.unsupportedTranscriptContent(.init(
                unsupportedContent: entries, debugDescription: "Expected the app's preassembled text prompt."
            ))
        }
        let prompt = try input.segments.map { segment in
            guard case let .text(text) = segment else {
                throw LanguageModelError.unsupportedTranscriptContent(.init(
                    unsupportedContent: entries, debugDescription: "The local runtime accepts text."
                ))
            }
            return text.content
        }.joined()
        let generation = model.backing.generateResponseStream(
            prompt: prompt, modelURL: configuration.modelURL,
            maxTokens: request.generationOptions.maximumResponseTokens ?? configuration.maxTokens
        )
        defer { generation.cancel() }
        try await withTaskCancellationHandler(operation: {
            for try await delta in generation.stream {
                try Task.checkCancellation()
                // The existing runtime exposes text deltas, without token usage counts.
                await channel.send(.response(action: .appendText(delta, tokenCount: 0)))
            }
        }, onCancel: {
            generation.cancel()
        })
    }
}
#endif
