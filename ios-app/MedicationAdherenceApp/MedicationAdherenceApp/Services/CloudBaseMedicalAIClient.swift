import Foundation
import MedicationAdherenceCore

enum MedicalAIClientFactory {
    static func make(
        configuration: MedicalAIConfiguration,
        credential: String,
        session: URLSession = MedicalAIURLSessionFactory.make()
    ) -> any MedicalAIClient {
        switch configuration.providerKind {
        case .broker:
            return CloudBaseMedicalAIClient(
                configuration: configuration,
                clientToken: credential,
                session: session
            )
        case .doubao:
            return DoubaoMedicalAIClient(
                configuration: configuration,
                apiKey: credential,
                session: session
            )
        case .baichuan:
            return BaichuanMedicalAIClient(
                configuration: configuration,
                apiKey: credential,
                session: session
            )
        }
    }
}

struct CloudBaseMedicalAIClient: MedicalAIClient {
    let configuration: MedicalAIConfiguration
    let clientToken: String
    var session: URLSession = MedicalAIURLSessionFactory.make()

    private var provider: MedicalAIProviderProfile {
        MedicalAIProviderProfile(
            providerName: configuration.providerName.isEmpty
                ? MedicalAIConfiguration.brokerProviderName
                : configuration.providerName,
            modelName: configuration.modelName.isEmpty
                ? MedicalAIConfiguration.brokerDefaultModelName
                : configuration.modelName,
            serviceLicenseSummary: MedicalAIConfiguration.brokerLicenseSummary
        )
    }

    func respond(to request: MedicalAIRequest) async throws -> MedicalAIResponse {
        let token = clientToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else {
            throw CloudBaseMedicalAIError.missingConfiguration
        }
        let endpoint = try MedicalAIEndpointPolicy.validatedURL(
            for: configuration,
            expectedProvider: .broker
        )

        var urlRequest = URLRequest(url: endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.timeoutInterval = 20
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        urlRequest.httpBody = try JSONEncoder().encode(CloudBaseBrokerRequest(
            requestID: request.id.uuidString.lowercased(),
            prompt: MedicalAIRequestPromptBuilder().buildPrompt(for: request)
        ))

        let (data, response) = try await session.data(for: urlRequest)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw CloudBaseMedicalAIError.invalidResponse
        }
        try MedicalAIEndpointPolicy.validateResponseURL(
            httpResponse.url,
            expectedEndpoint: endpoint
        )
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw CloudBaseMedicalAIError.httpStatus(code: httpResponse.statusCode)
        }

        let decoded: CloudBaseBrokerResponse
        do {
            decoded = try JSONDecoder().decode(CloudBaseBrokerResponse.self, from: data)
        } catch {
            throw CloudBaseMedicalAIError.decodingFailed
        }
        guard let responseRequestID = UUID(uuidString: decoded.requestID),
              responseRequestID == request.id
        else {
            throw CloudBaseMedicalAIError.mismatchedRequestID
        }
        let answer = decoded.answer.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !answer.isEmpty else {
            throw CloudBaseMedicalAIError.emptyMessage
        }

        return MedicalAIResponse(
            requestID: request.id,
            provider: provider,
            message: answer
        )
    }
}

private struct CloudBaseBrokerRequest: Encodable {
    let requestID: String
    let prompt: String

    private enum CodingKeys: String, CodingKey {
        case requestID = "request_id"
        case prompt
    }
}

private struct CloudBaseBrokerResponse: Decodable {
    let requestID: String
    let answer: String

    private enum CodingKeys: String, CodingKey {
        case requestID = "request_id"
        case answer
    }
}

enum CloudBaseMedicalAIError: LocalizedError, Equatable, Sendable {
    case missingConfiguration
    case invalidResponse
    case httpStatus(code: Int)
    case decodingFailed
    case mismatchedRequestID
    case emptyMessage

    var diagnosticSummary: String {
        switch self {
        case .missingConfiguration:
            "missing-configuration"
        case .invalidResponse:
            "invalid-response"
        case let .httpStatus(code):
            "http-status code=\(code)"
        case .decodingFailed:
            "decoding-failed"
        case .mismatchedRequestID:
            "mismatched-request-id"
        case .emptyMessage:
            "empty-message"
        }
    }

    var errorDescription: String? {
        switch self {
        case .missingConfiguration:
            return "医疗智能体暂时无法连接，未发送任何用药数据。请稍后重试。"
        case .invalidResponse, .decodingFailed, .mismatchedRequestID:
            return "医疗智能体返回内容暂时无法读取，请稍后重试。"
        case let .httpStatus(code):
            if code == 401 || code == 403 {
                return "医疗智能体暂时无法连接，请稍后重试。"
            }
            if code == 429 {
                return "医疗智能体请求过于频繁，请稍后重试。"
            }
            if code == 504 {
                return "医疗智能体响应超时，请稍后重试。"
            }
            return "医疗智能体请求失败，请稍后重试。"
        case .emptyMessage:
            return "医疗智能体暂时没有返回结果，请稍后重试。"
        }
    }
}
