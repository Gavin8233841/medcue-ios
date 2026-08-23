import Foundation
#if canImport(llama)
import llama
#endif

protocol LocalMedicalGenerating: Sendable {
    func generateResponse(prompt: String, modelURL: URL, maxTokens: Int) async throws -> String
    func generateResponseStream(
        prompt: String,
        modelURL: URL,
        maxTokens: Int
    ) async -> AsyncThrowingStream<String, Error>
}

actor LocalMedicalModelRuntime: LocalMedicalGenerating {
    static let shared = LocalMedicalModelRuntime()

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

    func generateResponse(prompt: String, modelURL: URL, maxTokens: Int) async throws -> String {
        #if canImport(llama)
        try Task.checkCancellation()
        let context = try LlamaCppContext(modelURL: modelURL)
        let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPrompt.isEmpty else {
            throw LocalMedicalAIError.emptyResponse
        }
        let response = try context.generate(prompt: trimmedPrompt, maxTokens: maxTokens)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !response.isEmpty else {
            throw LocalMedicalAIError.emptyResponse
        }
        return response
        #else
        throw LocalMedicalAIError.runtimeUnavailable
        #endif
    }

    func generateResponseStream(prompt: String, modelURL: URL, maxTokens: Int) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let worker = Task {
                do {
                    try Task.checkCancellation()
                    #if canImport(llama)
                    let context = try LlamaCppContext(modelURL: modelURL)
                    let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmedPrompt.isEmpty else {
                        throw LocalMedicalAIError.emptyResponse
                    }
                    _ = try context.generate(prompt: trimmedPrompt, maxTokens: maxTokens) { delta in
                        guard !delta.isEmpty, !Task.isCancelled else {
                            return
                        }
                        continuation.yield(delta)
                    }
                    try Task.checkCancellation()
                    continuation.finish()
                    #else
                    throw LocalMedicalAIError.runtimeUnavailable
                    #endif
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { @Sendable _ in
                worker.cancel()
            }
        }
    }
}

#if canImport(llama)
private final class LlamaCppContext {
    private var model: OpaquePointer
    private var context: OpaquePointer
    private var vocab: OpaquePointer
    private var sampler: UnsafeMutablePointer<llama_sampler>
    private var pendingUTF8Bytes: [CChar] = []
    private let contextLength = 2048

    init(modelURL: URL) throws {
        llama_backend_init()

        var modelParameters = llama_model_default_params()
        #if targetEnvironment(simulator)
        modelParameters.n_gpu_layers = 0
        #endif

        guard let loadedModel = llama_model_load_from_file(modelURL.path, modelParameters) else {
            throw LocalMedicalAIError.modelMissing
        }
        model = loadedModel

        let threadCount = max(1, min(8, ProcessInfo.processInfo.processorCount - 2))
        var contextParameters = llama_context_default_params()
        contextParameters.n_ctx = UInt32(contextLength)
        contextParameters.n_batch = UInt32(contextLength)
        contextParameters.n_ubatch = min(contextParameters.n_ubatch, 512)
        contextParameters.n_threads = Int32(threadCount)
        contextParameters.n_threads_batch = Int32(threadCount)

        guard let loadedContext = llama_init_from_model(loadedModel, contextParameters) else {
            llama_model_free(loadedModel)
            throw LocalMedicalAIError.runtimeUnavailable
        }
        context = loadedContext
        vocab = llama_model_get_vocab(loadedModel)

        let samplerParameters = llama_sampler_chain_default_params()
        sampler = llama_sampler_chain_init(samplerParameters)
        llama_sampler_chain_add(sampler, llama_sampler_init_top_k(40))
        llama_sampler_chain_add(sampler, llama_sampler_init_top_p(0.85, 1))
        llama_sampler_chain_add(sampler, llama_sampler_init_penalties(128, 1.10, 0.02, 0.0))
        llama_sampler_chain_add(sampler, llama_sampler_init_temp(0.40))
        llama_sampler_chain_add(sampler, llama_sampler_init_dist(42))
    }

    deinit {
        llama_sampler_free(sampler)
        llama_free(context)
        llama_model_free(model)
        llama_backend_free()
    }

    func generate(prompt: String, maxTokens: Int, onToken: ((String) -> Void)? = nil) throws -> String {
        try Task.checkCancellation()
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

        try Task.checkCancellation()
        var promptTokensForDecode = promptTokens
        let promptDecodeStatus = promptTokensForDecode.withUnsafeMutableBufferPointer { tokens in
            let promptBatch = llama_batch_get_one(tokens.baseAddress, Int32(tokens.count))
            return llama_decode(context, promptBatch)
        }

        guard promptDecodeStatus == 0 else {
            throw LocalMedicalAIError.runtimeUnavailable
        }
        try Task.checkCancellation()

        var output = ""
        for _ in 0..<tokenLimit {
            try Task.checkCancellation()
            let newToken = llama_sampler_sample(sampler, context, -1)
            try Task.checkCancellation()
            if llama_vocab_is_eog(vocab, newToken) {
                output += flushPendingUTF8Bytes()
                break
            }

            let piece = appendTokenPiece(newToken)
            output += piece
            onToken?(piece)
            try Task.checkCancellation()
            llama_sampler_accept(sampler, newToken)
            var tokenForDecode = newToken
            let tokenBatch = llama_batch_get_one(&tokenForDecode, 1)

            guard llama_decode(context, tokenBatch) == 0 else {
                throw LocalMedicalAIError.runtimeUnavailable
            }
            try Task.checkCancellation()
        }

        output += flushPendingUTF8Bytes()
        return output
    }

    private func chatFormattedPrompt(for prompt: String) -> String {
        guard let template = llama_model_chat_template(model, nil) else {
            return prompt
        }
        return "user".withCString { rolePointer in
            prompt.withCString { contentPointer in
                var message = llama_chat_message(role: rolePointer, content: contentPointer)
                let initialLength = max(4096, prompt.utf8.count * 3)
                var buffer = [CChar](repeating: 0, count: initialLength)
                let written = llama_chat_apply_template(template, &message, 1, true, &buffer, Int32(buffer.count))
                if written <= 0 {
                    return prompt
                }
                if written < buffer.count {
                    return decodeNullTerminatedUTF8(buffer)
                }
                var largerBuffer = [CChar](repeating: 0, count: Int(written) + 1)
                let largerWritten = llama_chat_apply_template(template, &message, 1, true, &largerBuffer, Int32(largerBuffer.count))
                guard largerWritten > 0, largerWritten < largerBuffer.count else {
                    return prompt
                }
                return decodeNullTerminatedUTF8(largerBuffer)
            }
        }
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
            false
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
