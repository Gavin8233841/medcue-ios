import Foundation
import MedicationAdherenceCore

struct LocalMedicalAIClient: MedicalAIClient {
    static let localReasoningSeparator = MedicalAIResponseFinalizer.reasoningSeparator

    let modelURL: URL
    var runtime: any LocalMedicalGenerating = LocalMedicalModelRuntime.shared

    private var responsePolicy: LocalMedicalResponsePolicy {
        LocalMedicalResponsePolicy()
    }

    private var provider: MedicalAIProviderProfile {
        MedicalAIProviderProfile(
            providerName: "离线智能体",
            modelName: LocalMedicalModelStore.modelDisplayName,
            serviceLicenseSummary: "在本机生成用药整理内容，不上传本次共享数据。"
        )
    }

    func respond(to request: MedicalAIRequest) async throws -> MedicalAIResponse {
        let answerPlan = responsePolicy.localAnswerPlan(for: request)
        let prompt = responsePolicy.buildLocalPrompt(for: request, answerPlan: answerPlan)
        let generatedMessage = try await runtime.generateResponse(
            prompt: prompt,
            modelURL: modelURL,
            maxTokens: MedicalAIExecutionPolicy.default.singleResponseTokenLimit
        )
        let resolved = try await resolveGeneratedResponse(
            generatedMessage,
            additionalThinking: "",
            request: request,
            answerPlan: answerPlan,
            repairMaxTokens: 220
        )
        return MedicalAIResponse(
            requestID: request.id,
            provider: provider,
            message: resolved.persistedMessage
        )
    }

    func streamResponse(to request: MedicalAIRequest) -> AsyncThrowingStream<LocalLLMGenerationEvent, Error> {
        AsyncThrowingStream { continuation in
            let worker = Task {
                func emit(_ event: LocalLLMGenerationEvent) async throws {
                    try Task.checkCancellation()
                    if case .terminated = continuation.yield(event) {
                        throw CancellationError()
                    }
                    await Task.yield()
                    try Task.checkCancellation()
                }

                do {
                    let answerPlan = responsePolicy.localAnswerPlan(for: request)
                    let prompt = responsePolicy.buildLocalPrompt(for: request, answerPlan: answerPlan)
                    var parser = LocalLLMStreamParser()
                    try Task.checkCancellation()
                    try await emit(.generationStarted)
                    try await emit(.modelLoading)
                    let stream = await runtime.generateResponseStream(
                        prompt: prompt,
                        modelURL: modelURL,
                        maxTokens: MedicalAIExecutionPolicy.default.streamingResponseTokenLimit
                    )
                    try await emit(.prefillStarted)
                    for try await delta in stream {
                        try Task.checkCancellation()
                        for event in parser.consume(delta) {
                            try await emit(event)
                        }
                    }
                    try Task.checkCancellation()
                    let completed = parser.finish()
                    for event in completed.events {
                        try await emit(event)
                    }
                    let resolved = try await resolveGeneratedResponse(
                        completed.answer,
                        additionalThinking: completed.thinking,
                        request: request,
                        answerPlan: answerPlan,
                        repairMaxTokens: MedicalAIExecutionPolicy.default.repairTokenLimit
                    )
                    try Task.checkCancellation()
                    try await emit(.generationCompleted(
                        answer: resolved.answer,
                        thinking: resolved.thinking
                    ))
                    continuation.finish()
                } catch {
                    guard !Task.isCancelled, !(error is CancellationError) else {
                        continuation.finish(throwing: CancellationError())
                        return
                    }
                    do {
                        try await emit(.generationFailed(error.localizedDescription))
                        continuation.finish(throwing: error)
                    } catch {
                        continuation.finish(throwing: CancellationError())
                    }
                }
            }
            continuation.onTermination = { @Sendable _ in
                worker.cancel()
            }
        }
    }

    private func resolveGeneratedResponse(
        _ generatedMessage: String,
        additionalThinking: String,
        request: MedicalAIRequest,
        answerPlan: LocalMedicalAnswerPlan,
        repairMaxTokens: Int
    ) async throws -> LocalMedicalResolvedResponse {
        try Task.checkCancellation()
        let processedMessage = responsePolicy.postprocessLocalResponse(generatedMessage, request: request)
        let answer = responsePolicy.formalAnswerText(from: processedMessage)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let initialThinking = combinedThinking(
            additionalThinking,
            responsePolicy.reasoningText(from: processedMessage)
        )
        let needsRepair = answer.isEmpty
            || responsePolicy.isLowQualityLocalResponse(answer, request: request)
            || responsePolicy.isOffTopicLocalResponse(answer, answerPlan: answerPlan)
        guard needsRepair else {
            return LocalMedicalResolvedResponse(answer: answer, thinking: initialThinking)
        }

        let repairedMessage = try await runtime.generateResponse(
            prompt: responsePolicy.buildRepairPrompt(for: request, answerPlan: answerPlan),
            modelURL: modelURL,
            maxTokens: repairMaxTokens
        )
        try Task.checkCancellation()
        let repairedProcessedMessage = responsePolicy.postprocessLocalResponse(repairedMessage, request: request)
        let repairedAnswer = responsePolicy.formalAnswerText(from: repairedProcessedMessage)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !repairedAnswer.isEmpty,
              !responsePolicy.isLowQualityLocalResponse(repairedAnswer, request: request),
              !responsePolicy.isOffTopicLocalResponse(repairedAnswer, answerPlan: answerPlan) else {
            throw LocalMedicalAIError.unstableResponse
        }
        return LocalMedicalResolvedResponse(
            answer: repairedAnswer,
            thinking: combinedThinking(
                initialThinking,
                responsePolicy.reasoningText(from: repairedProcessedMessage)
            )
        )
    }

    private func combinedThinking(_ values: String...) -> String {
        values
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
    }
}

struct LocalMedicalAnswerPlan {
    let focus: String
    let factSummary: String
    let factGuidance: String
    let requiredFragments: [String]
}

private struct LocalMedicalResolvedResponse {
    let answer: String
    let thinking: String

    var persistedMessage: String {
        guard !thinking.isEmpty else { return answer }
        return "\(answer)\(LocalMedicalAIClient.localReasoningSeparator)\(thinking)"
    }
}

enum LocalMedicalAIError: LocalizedError {
    case modelMissing
    case runtimeUnavailable
    case emptyResponse
    case unstableResponse

    var diagnosticSummary: String {
        switch self {
        case .modelMissing:
            "model-missing"
        case .runtimeUnavailable:
            "runtime-unavailable"
        case .emptyResponse:
            "empty-response"
        case .unstableResponse:
            "unstable-response"
        }
    }

    var errorDescription: String? {
        switch self {
        case .modelMissing:
            return "离线模型还未准备好，请先下载后再试。"
        case .runtimeUnavailable:
            return "离线智能体暂时不可用，请先使用在线智能体。"
        case .emptyResponse:
            return "离线智能体暂时没有返回结果，请稍后重试。"
        case .unstableResponse:
            return "端侧模型这次输出不稳定，没有作为正式回答展示。请换一种问法或稍后再试。"
        }
    }
}
