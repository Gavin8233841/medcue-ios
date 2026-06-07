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
        urlRequest.timeoutInterval = 60
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

        let decoded = try JSONDecoder().decode(DoubaoResponsesResponse.self, from: data)
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
}

enum DoubaoMedicalAIError: LocalizedError {
    case missingConfiguration
    case invalidResponse
    case httpStatus(code: Int, requestID: String?)
    case emptyMessage

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
