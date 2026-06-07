import Foundation
import MedicationAdherenceCore

struct BaichuanMedicalAIClient: MedicalAIClient {
    let configuration: MedicalAIConfiguration
    let apiKey: String
    var session: URLSession = .shared

    private var provider: MedicalAIProviderProfile {
        MedicalAIProviderProfile(
            providerName: configuration.providerName.isEmpty ? MedicalAIConfiguration.baichuanProviderName : configuration.providerName,
            modelName: configuration.modelName.isEmpty ? MedicalAIConfiguration.baichuanDefaultModelName : configuration.modelName,
            serviceLicenseSummary: MedicalAIConfiguration.baichuanLicenseSummary
        )
    }

    func respond(to request: MedicalAIRequest) async throws -> MedicalAIResponse {
        guard let endpoint = URL(string: configuration.endpointURLString), !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw BaichuanMedicalAIError.missingConfiguration
        }

        let prompt = MedicalAIRequestPromptBuilder().buildPrompt(for: request)
        var urlRequest = URLRequest(url: endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.timeoutInterval = 60
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

        guard (200..<300).contains(httpResponse.statusCode) else {
            throw BaichuanMedicalAIError.httpStatus(
                code: httpResponse.statusCode,
                requestID: httpResponse.value(forHTTPHeaderField: "X-BC-Request-Id")
            )
        }

        let decoded = try JSONDecoder().decode(BaichuanChatCompletionResponse.self, from: data)
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
    case emptyMessage

    var isRateLimited: Bool {
        if case let .httpStatus(code, _) = self {
            return code == 429
        }
        return false
    }

    var errorDescription: String? {
        switch self {
        case .missingConfiguration:
            return "医疗 AI 暂不可用，未发送用药数据。请稍后重试。"
        case .invalidResponse:
            return "医疗 AI 返回内容暂时无法读取，请稍后重试。"
        case let .httpStatus(code, requestID):
            let requestPart = requestID.map { "，请求 ID：\($0)" } ?? ""
            if code == 401 || code == 403 {
                return "医疗 AI 暂不可用，未发送用药数据。请稍后重试\(requestPart)。"
            }
            if code == 429 {
                return "医疗 AI 请求过于频繁，请稍后重试\(requestPart)。"
            }
            return "医疗 AI 请求失败，请稍后重试\(requestPart)。"
        case .emptyMessage:
            return "医疗 AI 暂时没有返回结果，请稍后重试。"
        }
    }
}
