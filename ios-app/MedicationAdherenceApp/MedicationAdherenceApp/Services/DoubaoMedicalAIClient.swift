import Foundation
import MedicationAdherenceCore

struct DoubaoMedicalAIClient: MedicalAIClient {
    let configuration: MedicalAIConfiguration
    let apiKey: String
    var session: URLSession = .shared

    private var provider: MedicalAIProviderProfile {
        MedicalAIProviderProfile(
            providerName: configuration.providerName.isEmpty ? MedicalAIConfiguration.doubaoProviderName : configuration.providerName,
            modelName: configuration.modelName.isEmpty ? MedicalAIConfiguration.doubaoDefaultModelName : configuration.modelName,
            serviceLicenseSummary: MedicalAIConfiguration.doubaoLicenseSummary
        )
    }

    func respond(to request: MedicalAIRequest) async throws -> MedicalAIResponse {
        guard let endpoint = URL(string: configuration.endpointURLString), !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw DoubaoMedicalAIError.missingConfiguration
        }

        let prompt = MedicalAIRequestPromptBuilder().buildPrompt(for: request)
        var urlRequest = URLRequest(url: endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.timeoutInterval = 20
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        urlRequest.httpBody = try JSONEncoder().encode(DoubaoResponsesRequest(
            model: provider.modelName,
            input: [
                DoubaoInputMessage(
                    role: "user",
                    content: [
                        DoubaoInputContent(type: "input_text", text: prompt)
                    ]
                )
            ]
        ))

        let (data, response) = try await session.data(for: urlRequest)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw DoubaoMedicalAIError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            throw DoubaoMedicalAIError.httpStatus(
                code: httpResponse.statusCode,
                requestID: httpResponse.value(forHTTPHeaderField: "X-Request-Id")
            )
        }

        let decoded: DoubaoResponsesResponse
        do {
            decoded = try JSONDecoder().decode(DoubaoResponsesResponse.self, from: data)
        } catch {
            throw DoubaoMedicalAIError.decodingFailed
        }
        guard let message = decoded.bestText?.trimmingCharacters(in: .whitespacesAndNewlines), !message.isEmpty else {
            throw DoubaoMedicalAIError.emptyMessage
        }

        return MedicalAIResponse(
            requestID: request.id,
            provider: provider,
            message: message
        )
    }
}

private struct DoubaoResponsesRequest: Encodable {
    var model: String
    var input: [DoubaoInputMessage]
}

private struct DoubaoInputMessage: Encodable {
    var role: String
    var content: [DoubaoInputContent]
}

private struct DoubaoInputContent: Encodable {
    var type: String
    var text: String
}

private struct DoubaoResponsesResponse: Decodable {
    var outputText: String?
    var output: [DoubaoOutputItem]?

    var bestText: String? {
        if let outputText, !outputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return outputText
        }
        return output?
            .flatMap { $0.content ?? [] }
            .compactMap(\.text)
            .joined(separator: "\n")
    }

    private enum CodingKeys: String, CodingKey {
        case outputText = "output_text"
        case output
    }
}

private struct DoubaoOutputItem: Decodable {
    var content: [DoubaoOutputContent]?
}

private struct DoubaoOutputContent: Decodable {
    var text: String?
    var type: String?
}

enum DoubaoMedicalAIError: LocalizedError {
    case missingConfiguration
    case invalidResponse
    case httpStatus(code: Int, requestID: String?)
    case decodingFailed
    case emptyMessage

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
