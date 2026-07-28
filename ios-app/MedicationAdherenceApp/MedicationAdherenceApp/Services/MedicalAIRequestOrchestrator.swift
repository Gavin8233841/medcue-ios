import Foundation
import MedicationAdherenceCore

struct MedicalAIExecutionPolicy: Equatable, Sendable {
    let cloudTimeout: Duration
    let trendLookbackDays: Int
    let singleResponseTokenLimit: Int
    let streamingResponseTokenLimit: Int
    let repairTokenLimit: Int

    static let `default` = MedicalAIExecutionPolicy(
        cloudTimeout: .seconds(20),
        trendLookbackDays: 14,
        singleResponseTokenLimit: 220,
        streamingResponseTokenLimit: 640,
        repairTokenLimit: 360
    )
}

enum MedicalAIOrchestrationError: LocalizedError, Equatable {
    case unauthorizedScopes
    case timedOut
    case mismatchedRequestID
    case emptyResponse

    var errorDescription: String? {
        switch self {
        case .unauthorizedScopes:
            "当前授权范围不足，请重新确认共享范围。"
        case .timedOut:
            "医疗智能体响应超时，请稍后重试。"
        case .mismatchedRequestID:
            "医疗智能体返回内容无法与本次请求对应，请重试。"
        case .emptyResponse:
            "医疗智能体暂时没有返回结果，请稍后重试。"
        }
    }
}

struct MedicalAIFinalizedResponse: Equatable, Sendable {
    let displayMessage: String
    let thinking: String
    let persistedMessage: String
    let boundaryFlags: [String]
    let appendedSafetyNote: Bool
    let boundaryBlockedAction: Bool
}

struct MedicalAIResponseFinalizer: Sendable {
    static let reasoningSeparator = "\n[[LOCAL_MODEL_REASONING]]\n"

    func finalize(
        answer: String,
        thinking: String = ""
    ) throws -> MedicalAIFinalizedResponse {
        let trimmedAnswer = answer.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedAnswer.isEmpty else {
            throw MedicalAIOrchestrationError.emptyResponse
        }

        let boundaryGuard = MedicalAIResponseBoundaryGuard()
        let answerReview = boundaryGuard.review(trimmedAnswer)
        let displayMessage = answerReview.displayMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !displayMessage.isEmpty else {
            throw MedicalAIOrchestrationError.emptyResponse
        }

        let trimmedThinking = thinking.trimmingCharacters(in: .whitespacesAndNewlines)
        let thinkingReview = trimmedThinking.isEmpty ? nil : boundaryGuard.review(trimmedThinking)
        let safeThinking = answerReview.blockedActionableInstruction
            || thinkingReview?.blockedActionableInstruction == true
            ? ""
            : trimmedThinking
        let persistedMessage = safeThinking.isEmpty
            ? displayMessage
            : "\(displayMessage)\(Self.reasoningSeparator)\(safeThinking)"

        return MedicalAIFinalizedResponse(
            displayMessage: displayMessage,
            thinking: safeThinking,
            persistedMessage: persistedMessage,
            boundaryFlags: answerReview.flags,
            appendedSafetyNote: answerReview.appendedSafetyNote,
            boundaryBlockedAction: answerReview.blockedActionableInstruction
                || thinkingReview?.blockedActionableInstruction == true
        )
    }
}

struct MedicalAIExecutionResult: Sendable, Equatable {
    let response: MedicalAIResponse
    let finalized: MedicalAIFinalizedResponse
}

struct MedicalAIRequestOrchestrator: Sendable {
    let timeout: Duration

    init(timeout: Duration) {
        self.timeout = timeout
    }

    func execute(
        request: MedicalAIRequest,
        client: any MedicalAIClient
    ) async throws -> MedicalAIExecutionResult {
        try Task.checkCancellation()
        guard MedicalAIRequestValidator().canSend(request) else {
            throw MedicalAIOrchestrationError.unauthorizedScopes
        }

        let response = try await withThrowingTaskGroup(of: MedicalAIResponse.self) { group in
            group.addTask {
                try await client.respond(to: request)
            }
            group.addTask {
                try await Task.sleep(for: timeout)
                throw MedicalAIOrchestrationError.timedOut
            }
            defer { group.cancelAll() }
            guard let first = try await group.next() else {
                throw MedicalAIOrchestrationError.timedOut
            }
            return first
        }
        try Task.checkCancellation()
        guard response.requestID == request.id else {
            throw MedicalAIOrchestrationError.mismatchedRequestID
        }
        let finalized = try MedicalAIResponseFinalizer().finalize(answer: response.message)
        return MedicalAIExecutionResult(response: response, finalized: finalized)
    }
}
