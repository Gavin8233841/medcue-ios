import Foundation
import MedicationAdherenceCore

struct BaichuanMedicalAIClient: MedicalAIClient {
    let configuration: MedicalAIConfiguration
    let apiKey: String
    var session: URLSession = MedicalAIURLSessionFactory.make()

    private var provider: MedicalAIProviderProfile {
        MedicalAIProviderProfile(
            providerName: configuration.providerName.isEmpty ? MedicalAIConfiguration.baichuanProviderName : configuration.providerName,
            modelName: configuration.modelName.isEmpty ? MedicalAIConfiguration.baichuanDefaultModelName : configuration.modelName,
            serviceLicenseSummary: MedicalAIConfiguration.baichuanLicenseSummary
        )
    }

    func respond(to request: MedicalAIRequest) async throws -> MedicalAIResponse {
        guard !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw BaichuanMedicalAIError.missingConfiguration
        }
        let endpoint = try MedicalAIEndpointPolicy.validatedURL(
            for: configuration,
            expectedProvider: .baichuan
        )

        let prompt = MedicalAIRequestPromptBuilder().buildPrompt(for: request)
        var urlRequest = URLRequest(url: endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.timeoutInterval = 20
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        urlRequest.httpBody = try JSONEncoder().encode(BaichuanChatCompletionRequest(
            model: provider.modelName,
            messages: [
                BaichuanChatMessage(role: "user", content: prompt)
            ]
        ))

        let (data, response) = try await session.data(for: urlRequest)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw BaichuanMedicalAIError.invalidResponse
        }
        try MedicalAIEndpointPolicy.validateResponseURL(httpResponse.url, expectedEndpoint: endpoint)

        guard (200..<300).contains(httpResponse.statusCode) else {
            throw BaichuanMedicalAIError.httpStatus(
                code: httpResponse.statusCode,
                requestID: httpResponse.value(forHTTPHeaderField: "X-BC-Request-Id")
            )
        }

        let decoded: BaichuanChatCompletionResponse
        do {
            decoded = try JSONDecoder().decode(BaichuanChatCompletionResponse.self, from: data)
        } catch {
            throw BaichuanMedicalAIError.decodingFailed
        }
        guard let message = decoded.choices.first?.message.content.trimmingCharacters(in: .whitespacesAndNewlines), !message.isEmpty else {
            throw BaichuanMedicalAIError.emptyMessage
        }

        return MedicalAIResponse(
            requestID: request.id,
            provider: provider,
            message: message
        )
    }
}

private struct BaichuanChatCompletionRequest: Encodable {
    var model: String
    var messages: [BaichuanChatMessage]
    var stream: Bool = false
    var temperature: Double = 0.2
    var topP: Double = 0.85
    var topK: Int = 5
    var maxTokens: Int = 240
    var metadata: BaichuanMetadata = BaichuanMetadata()

    private enum CodingKeys: String, CodingKey {
        case model
        case messages
        case stream
        case temperature
        case topP = "top_p"
        case topK = "top_k"
        case maxTokens = "max_tokens"
        case metadata
    }
}

private struct BaichuanMetadata: Encodable {
    var evidenceScope: String = "grounded"
    var disableFollowUpQuestionExtension: Bool = true
    var outputStyle: String = "patient"

    private enum CodingKeys: String, CodingKey {
        case evidenceScope = "evidence_scope"
        case disableFollowUpQuestionExtension = "disable_follow-up_question_extension"
        case outputStyle = "output_style"
    }
}

private struct BaichuanChatMessage: Encodable {
    var role: String
    var content: String
}

private struct BaichuanChatCompletionResponse: Decodable {
    var choices: [Choice]

    struct Choice: Decodable {
        var message: Message
    }

    struct Message: Decodable {
        var role: String?
        var content: String
    }
}

enum BaichuanMedicalAIError: LocalizedError {
    case missingConfiguration
    case invalidResponse
    case httpStatus(code: Int, requestID: String?)
    case decodingFailed
    case emptyMessage

    var isRateLimited: Bool {
        if case let .httpStatus(code, _) = self {
            return code == 429
        }
        return false
    }

    var diagnosticSummary: String {
        switch self {
        case .missingConfiguration:
            "missing-configuration"
        case .invalidResponse:
            "invalid-response"
        case let .httpStatus(code, requestID):
            "http-status code=\(code) requestID=\(requestID ?? "none")"
        case .decodingFailed:
            "decoding-failed"
        case .emptyMessage:
            "empty-message"
        }
    }

    var errorDescription: String? {
        switch self {
        case .missingConfiguration:
            return "医疗智能体暂时无法连接，未发送任何用药数据。请稍后重试。"
        case .invalidResponse:
            return "医疗智能体返回内容暂时无法读取，请稍后重试。"
        case let .httpStatus(code, _):
            if code == 401 || code == 403 {
                return "医疗智能体暂时无法连接，请稍后重试。"
            }
            if code == 429 {
                return "医疗智能体请求过于频繁，请稍后重试。"
            }
            return "医疗智能体请求失败，请稍后重试。"
        case .decodingFailed:
            return "医疗智能体返回格式暂时无法读取，请稍后重试。"
        case .emptyMessage:
            return "医疗智能体暂时没有返回结果，请稍后重试。"
        }
    }
}
