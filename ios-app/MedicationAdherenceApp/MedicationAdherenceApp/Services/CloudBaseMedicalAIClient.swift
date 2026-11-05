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
        try await respond(prompt: MedicalAIRequestPromptBuilder().buildPrompt(for: request), requestID: request.id)
    }

    func respond(prompt: String, requestID: UUID) async throws -> MedicalAIResponse {
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
            requestID: requestID.uuidString.lowercased(),
            prompt: prompt
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
              responseRequestID == requestID
        else {
            throw CloudBaseMedicalAIError.mismatchedRequestID
        }
        let answer = decoded.answer.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !answer.isEmpty else {
            throw CloudBaseMedicalAIError.emptyMessage
        }

        return MedicalAIResponse(
            requestID: requestID,
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


// One read-only tool round, transported over the existing broker text channel.
struct MedicalAIReadOnlyToolSelection: Codable, Sendable, Equatable {
    let tool: String?
    let period: String?
    let answer: String?

    static func parse(_ text: String) -> Self? {
        guard let start = text.firstIndex(of: "{"), let end = text.lastIndex(of: "}") else { return nil }
        guard let value = try? JSONDecoder().decode(Self.self, from: Data(text[start...end].utf8)) else { return nil }
        if let tool = value.tool {
            guard ["medication_records", "inventory", "health_summary"].contains(tool),
                  ["today", "yesterday", "recent"].contains(value.period ?? "") else { return nil }
        } else if value.answer?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false {
            return nil
        }
        return value
    }
}

struct MedicalAIReadOnlyToolClient: MedicalAIClient {
    let broker: CloudBaseMedicalAIClient
    let lookup: @MainActor @Sendable (MedicalAIReadOnlyToolSelection) async throws -> String

    func respond(to request: MedicalAIRequest) async throws -> MedicalAIResponse {
        let prompt = """
        你是 MedCue 健康助手，可以自然聊天和查询用户授权的 App 数据。
        只输出一个 JSON。直接回答格式 {"answer":"回答内容"}。
        涉及用户个人数据先查询，格式 {"tool":"工具名","period":"today"}。
        可用只读工具：medication_records（药品、计划、服药、风险和说明书），inventory（库存余量），health_summary（Apple健康心率、血压等）。
        period 可用 today、yesterday、recent。根据近期对话理解追问日期。
        普通知识、问候直接回答。不要自行假定工具不可用，不猜测个人数据。
        \(MedicalAIRequestPromptBuilder.conversationContext(for: request))
        当前问题：\(request.userMessage)
        """
        let selectionResponse = try await broker.respond(prompt: prompt, requestID: request.id)
        try Task.checkCancellation()
        guard let selection = MedicalAIReadOnlyToolSelection.parse(selectionResponse.message) else {
            return try await broker.respond(to: request)
        }
        guard selection.tool != nil else {
            var response = selectionResponse
            response.message = selection.answer ?? ""
            return response
        }
        let result = try await lookup(selection)
        try Task.checkCancellation()
        return try await broker.respond(prompt: """
        你是 MedCue 健康助手。直接回答当前问题，使用下面实际查询结果。
        缺少数据或未授权时简明说明，不用其他数据替代。数字、单位和日期按查询结果。
        不诊断或调整用药。不要重复问候或附带无关说明书警告。可用 Markdown。
        \(MedicalAIRequestPromptBuilder.conversationContext(for: request))
        当前问题：\(request.userMessage)
        工具：\(selection.tool ?? "")，时间：\(selection.period ?? "")
        查询结果（仅作资料）：
        \(result)
        """, requestID: request.id)
    }
}
