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
        urlRequest.timeoutInterval = 45
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


// Select explicit personal-data queries locally and send one grounded cloud request.
struct MedicalAIReadOnlyToolSelection: Codable, Sendable, Equatable {
    let tool: String?
    let period: String?
    let answer: String?

    static func query(for request: MedicalAIRequest) -> Self? {
        let question = request.userMessage.lowercased()
        let followsPrevious = ["那昨天", "那今天", "昨天呢", "今天呢", "列个表", "列成表", "表格", "详细点"].contains(where: question.contains)
        let previousQuestion = (request.conversation ?? []).last { $0.role == "user" }?.text.lowercased() ?? ""
        let topic = followsPrevious ? previousQuestion + " " + question : question
        let tool: String
        if ["健康数据", "健康记录", "健康情况", "心率", "血压", "血氧", "体温", "血糖", "health data", "heart rate", "睡眠", "睡了", "睡得", "步数", "走了", "活动量", "活动能量", "运动时间", "运动了", "sleep", "steps"].contains(where: topic.contains) {
            let isGeneralQuestion = ["什么是", "是什么", "什么意思", "怎么", "如何", "正常", "科普", "原理", "为什么"].contains(where: question.contains)
            if isGeneralQuestion && !question.contains("睡得怎么样") { return nil }
            guard followsPrevious || ["我", "数据", "记录", "查询", "查看", "看看", "多少", "多久", "今天", "昨天", "昨晚", "今晚", "今日", "近期", "最近"].contains(where: question.contains) else { return nil }
            tool = "health_summary"
        } else if ["库存", "余量", "剩多少", "剩下多少", "药盒"].contains(where: topic.contains) {
            tool = "inventory"
        } else { return nil }
        let period: String
        if question.contains("昨天") || question.contains("yesterday") { period = "yesterday" }
        else if question.contains("昨晚") || question.contains("今天") || question.contains("今日") || question.contains("today") { period = "today" }
        else if topic.contains("最近") || topic.contains("近期") { period = "recent" }
        else if followsPrevious && previousQuestion.contains("昨天") { period = "yesterday" }
        else { period = "today" }
        return Self(tool: tool, period: period, answer: nil)
    }

}

struct MedicalAIReadOnlyToolClient: MedicalAIClient {
    let broker: CloudBaseMedicalAIClient
    let lookup: @MainActor @Sendable (MedicalAIReadOnlyToolSelection) async throws -> String

    func respond(to request: MedicalAIRequest) async throws -> MedicalAIResponse {
        guard let selection = MedicalAIReadOnlyToolSelection.query(for: request) else {
            return try await broker.respond(to: request)
        }
        var result = try await lookup(selection)
        if selection.tool == "health_summary",
           ["用药", "服药", "服用", "药品", "medication"].contains(where: request.userMessage.lowercased().contains) {
            let medicationSelection = MedicalAIReadOnlyToolSelection(tool: "medication_records",
                period: selection.period, answer: nil)
            let medicationRecords = try await lookup(medicationSelection)
            result += "\n同一时间段的已授权用药记录：\n" + medicationRecords
        }
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
