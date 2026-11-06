import Foundation
import MedicationAdherenceCore
import Testing
import os
@testable import MedicationAdherenceApp

@Suite(.serialized)
struct CloudBaseMedicalAIClientTests {
    @Test @MainActor
    func mixedHealthAndMedicationQueryUsesBothSourcesAndOneCloudRequest() async throws {
        let request = MedicalAIRequest(kind: .chat, userMessage: "请用表格告诉我昨天的健康数据和用药数据",
            authorization: .init(grantedScopes: []))
        let lookups = OSAllocatedUnfairLock(initialState: [String]())
        let calls = OSAllocatedUnfairLock(initialState: 0)
        BrokerTestURLProtocol.handler = { urlRequest in
            calls.withLock { $0 += 1 }
            let body = try #require(try requestBodyData(from: urlRequest))
            let object = try #require(JSONSerialization.jsonObject(with: body) as? [String: String])
            let prompt = try #require(object["prompt"])
            #expect(prompt.contains("合成心率72"))
            #expect(prompt.contains("合成用药已记录"))
            let response = HTTPURLResponse(url: urlRequest.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, try JSONSerialization.data(withJSONObject: ["request_id": request.id.uuidString, "answer": "合成汇总"]))
        }
        defer { BrokerTestURLProtocol.handler = nil }
        let broker = CloudBaseMedicalAIClient(configuration: brokerConfiguration(), clientToken: "test-token", session: brokerTestSession())
        let client = MedicalAIReadOnlyToolClient(broker: broker) { selection in
            #expect(selection.period == "yesterday")
            lookups.withLock { $0.append(selection.tool ?? "") }
            return selection.tool == "health_summary" ? "合成心率72" : "合成用药已记录"
        }
        _ = try await client.respond(to: request)
        #expect(lookups.withLock { $0 } == ["health_summary", "medication_records"])
        #expect(calls.withLock { $0 } == 1)
    }

    @Test
    func personalDataRoutingPreservesDateAndGeneralQuestions() {
        func request(_ text: String, previous: String? = nil) -> MedicalAIRequest {
            MedicalAIRequest(kind: .chat, userMessage: text,
                conversation: previous.map { [.init(role: "user", text: $0)] },
                authorization: .init(grantedScopes: []))
        }
        #expect(MedicalAIReadOnlyToolSelection.query(for: request("你好")) == nil)
        for question in ["什么是心率", "血压计怎么用", "如何测量心率", "心率是什么意思", "告诉我心率是什么", "我想了解血压计怎么用"] {
            #expect(MedicalAIReadOnlyToolSelection.query(for: request(question)) == nil)
        }
        #expect(MedicalAIReadOnlyToolSelection.query(for: request("把昨天的健康数据列个表给我看看"))?.period == "yesterday")
        #expect(MedicalAIReadOnlyToolSelection.query(for: request("那昨天呢", previous: "今天心率多少"))?.tool == "health_summary")
        #expect(MedicalAIReadOnlyToolSelection.query(for: request("药还剩多少库存"))?.tool == "inventory")
        #expect(MedicalAIReadOnlyToolSelection.query(for: request("昨晚睡了多久"))?.period == "today")
        #expect(MedicalAIReadOnlyToolSelection.query(for: request("我昨晚睡得怎么样"))?.tool == "health_summary")
        #expect(MedicalAIReadOnlyToolSelection.query(for: request("昨天走了多少步数"))?.period == "yesterday")
    }

    @Test @MainActor
    func greetingAndHealthQueryEachNeedOnlyOneCloudRequest() async throws {
        for question in ["你好", "今天心率多少"] {
            let request = MedicalAIRequest(kind: .chat, userMessage: question, authorization: .init(grantedScopes: []))
            let calls = OSAllocatedUnfairLock(initialState: 0)
            let lookups = OSAllocatedUnfairLock(initialState: 0)
            BrokerTestURLProtocol.handler = { urlRequest in
                let body = try #require(try requestBodyData(from: urlRequest))
                let object = try JSONSerialization.jsonObject(with: body) as! [String: String]
                #expect(object["request_id"] == request.id.uuidString.lowercased())
                calls.withLock { $0 += 1 }
                if question == "你好" { #expect(!(object["prompt"] ?? "").contains("72")) }
                else { #expect((object["prompt"] ?? "").contains("72")) }
                let response = HTTPURLResponse(url: urlRequest.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
                let answer = question == "你好" ? "你好，有什么健康问题想聊吗？" : "今天登记心率为72次/分钟。"
                return (response, try JSONSerialization.data(withJSONObject: ["request_id": request.id.uuidString, "answer": answer]))
            }
            defer { BrokerTestURLProtocol.handler = nil }
            let client = MedicalAIReadOnlyToolClient(
                broker: .init(configuration: brokerConfiguration(), clientToken: "test", session: brokerTestSession()),
                lookup: { selection in
                    #expect(selection.tool == "health_summary")
                    lookups.withLock { $0 += 1 }
                    return "合成测试记录：心率72次/分钟"
                }
            )
            let result = try await client.respond(to: request)
            #expect(result.requestID == request.id)
            #expect(calls.withLock { $0 } == 1)
            #expect(lookups.withLock { $0 } == (question == "你好" ? 0 : 1))
        }
    }

    @Test
    func successfulResponseUsesTheMinimalAuthenticatedBrokerContract() async throws {
        let requestID = UUID(uuidString: "5F7BDCEE-D912-47D7-8B30-7D997006DE7D")!
        let request = MedicalAIRequest(
            id: requestID,
            kind: .chat,
            userMessage: "这是一条不包含个人资料的连通性测试。",
            authorization: MedicalAIUserAuthorization(
                grantedScopes: [],
                note: "仅用于客户端契约测试。"
            ),
            localeIdentifier: "zh_CN",
            createdAt: Date(timeIntervalSince1970: 1_800_000_000)
        )
        let capturedRequest = LockedURLRequest()
        BrokerTestURLProtocol.handler = { urlRequest in
            capturedRequest.store(
                urlRequest,
                body: try requestBodyData(from: urlRequest)
            )
            guard let url = urlRequest.url,
                  let response = HTTPURLResponse(
                url: url,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )
            else {
                throw BrokerTestError.invalidResponse
            }
            let data = try JSONSerialization.data(withJSONObject: [
                "request_id": requestID.uuidString.lowercased(),
                "answer": "连通性测试完成。"
            ])
            return (response, data)
        }
        defer {
            BrokerTestURLProtocol.handler = nil
        }

        let response = try await CloudBaseMedicalAIClient(
            configuration: brokerConfiguration(),
            clientToken: "test-client-token",
            session: brokerTestSession()
        ).respond(to: request)

        #expect(response.requestID == requestID)
        #expect(response.message == "连通性测试完成。")
        #expect(response.provider.providerName == MedicalAIConfiguration.brokerProviderName)

        let sentRequest = try #require(capturedRequest.load())
        #expect(sentRequest.url?.absoluteString == MedicalAIConfiguration.brokerRespondEndpoint)
        #expect(sentRequest.httpMethod == "POST")
        #expect(sentRequest.value(forHTTPHeaderField: "Authorization") == "Bearer test-client-token")
        #expect(sentRequest.value(forHTTPHeaderField: "Content-Type") == "application/json")

        let body = try #require(capturedRequest.loadBody())
        let object = try #require(
            JSONSerialization.jsonObject(with: body) as? [String: String]
        )
        #expect(Set(object.keys) == ["request_id", "prompt"])
        #expect(object["request_id"] == requestID.uuidString.lowercased())
        #expect(object["prompt"] == MedicalAIRequestPromptBuilder().buildPrompt(for: request))
    }

    @Test
    func mismatchedResponseRequestIDIsRejected() async throws {
        let request = MedicalAIRequest(
            id: UUID(uuidString: "7C511304-BF51-4828-9B27-9F4FD8046376")!,
            kind: .chat,
            userMessage: "契约测试。",
            authorization: MedicalAIUserAuthorization(grantedScopes: [])
        )
        BrokerTestURLProtocol.handler = { urlRequest in
            guard let url = urlRequest.url,
                  let response = HTTPURLResponse(
                    url: url,
                    statusCode: 200,
                    httpVersion: "HTTP/1.1",
                    headerFields: ["Content-Type": "application/json"]
                  )
            else {
                throw BrokerTestError.invalidResponse
            }
            let data = try JSONSerialization.data(withJSONObject: [
                "request_id": "31f296f1-bb2c-4874-bab4-b9605cabd8ce",
                "answer": "不应被接收的响应。"
            ])
            return (response, data)
        }
        defer {
            BrokerTestURLProtocol.handler = nil
        }

        do {
            _ = try await CloudBaseMedicalAIClient(
                configuration: brokerConfiguration(),
                clientToken: "test-client-token",
                session: brokerTestSession()
            ).respond(to: request)
            Issue.record("Expected mismatched request ID to be rejected")
        } catch let error as CloudBaseMedicalAIError {
            #expect(error == .mismatchedRequestID)
        } catch {
            Issue.record("Unexpected error type: \(type(of: error))")
        }
    }

    @Test
    func malformedOrEmptySuccessfulResponsesAreRejected() async throws {
        let request = MedicalAIRequest(
            id: UUID(uuidString: "277EA7C1-49DC-41BD-8881-5AAAC5E28D24")!,
            kind: .chat,
            userMessage: "响应格式测试。",
            authorization: MedicalAIUserAuthorization(grantedScopes: [])
        )
        let cases: [(Data, CloudBaseMedicalAIError)] = [
            (Data("not-json".utf8), .decodingFailed),
            (
                try JSONSerialization.data(withJSONObject: [
                    "request_id": request.id.uuidString.lowercased(),
                    "answer": " \n "
                ]),
                .emptyMessage
            )
        ]

        for (data, expectedError) in cases {
            BrokerTestURLProtocol.handler = { urlRequest in
                guard let url = urlRequest.url,
                      let response = HTTPURLResponse(
                        url: url,
                        statusCode: 200,
                        httpVersion: "HTTP/1.1",
                        headerFields: ["Content-Type": "application/json"]
                      )
                else {
                    throw BrokerTestError.invalidResponse
                }
                return (response, data)
            }

            do {
                _ = try await CloudBaseMedicalAIClient(
                    configuration: brokerConfiguration(),
                    clientToken: "test-client-token",
                    session: brokerTestSession()
                ).respond(to: request)
                Issue.record("Expected malformed broker response to be rejected")
            } catch let error as CloudBaseMedicalAIError {
                #expect(error == expectedError)
            } catch {
                Issue.record("Unexpected error type: \(type(of: error))")
            }
        }
        BrokerTestURLProtocol.handler = nil
    }

    @Test
    func brokerHTTPFailuresDoNotExposeResponseBodyOrToken() async throws {
        let request = MedicalAIRequest(
            kind: .chat,
            userMessage: "错误映射测试。",
            authorization: MedicalAIUserAuthorization(grantedScopes: [])
        )
        let sensitiveBody = "provider-secret-body test-client-token"

        for statusCode in [401, 429, 502, 504] {
            BrokerTestURLProtocol.handler = { urlRequest in
                guard let url = urlRequest.url,
                      let response = HTTPURLResponse(
                        url: url,
                        statusCode: statusCode,
                        httpVersion: "HTTP/1.1",
                        headerFields: ["Content-Type": "application/json"]
                      )
                else {
                    throw BrokerTestError.invalidResponse
                }
                return (response, Data(sensitiveBody.utf8))
            }

            do {
                _ = try await CloudBaseMedicalAIClient(
                    configuration: brokerConfiguration(),
                    clientToken: "test-client-token",
                    session: brokerTestSession()
                ).respond(to: request)
                Issue.record("Expected HTTP \(statusCode) to be rejected")
            } catch let error as CloudBaseMedicalAIError {
                #expect(error == .httpStatus(code: statusCode))
                #expect(!error.diagnosticSummary.contains(sensitiveBody))
                #expect(!(error.errorDescription ?? "").contains(sensitiveBody))
                #expect(!error.diagnosticSummary.contains("test-client-token"))
                #expect(!(error.errorDescription ?? "").contains("test-client-token"))
            } catch {
                Issue.record("Unexpected error type: \(type(of: error))")
            }
        }
        BrokerTestURLProtocol.handler = nil
    }

    @Test
    func clientFactoryRoutesBrokerConfigurationToTheBrokerAdapter() async throws {
        let request = MedicalAIRequest(
            id: UUID(uuidString: "6CB34AA0-AEEC-4225-8D6F-07A5E270F8ED")!,
            kind: .chat,
            userMessage: "工厂路由测试。",
            authorization: MedicalAIUserAuthorization(grantedScopes: [])
        )
        BrokerTestURLProtocol.handler = { urlRequest in
            guard let url = urlRequest.url,
                  let response = HTTPURLResponse(
                    url: url,
                    statusCode: 200,
                    httpVersion: "HTTP/1.1",
                    headerFields: ["Content-Type": "application/json"]
                  )
            else {
                throw BrokerTestError.invalidResponse
            }
            let data = try JSONSerialization.data(withJSONObject: [
                "request_id": request.id.uuidString.lowercased(),
                "answer": "Broker adapter 已响应。"
            ])
            return (response, data)
        }
        defer {
            BrokerTestURLProtocol.handler = nil
        }

        let client = MedicalAIClientFactory.make(
            configuration: brokerConfiguration(),
            credential: "test-client-token",
            session: brokerTestSession()
        )
        let response = try await client.respond(to: request)

        #expect(response.requestID == request.id)
        #expect(response.provider.providerName == MedicalAIConfiguration.brokerProviderName)
        #expect(response.message == "Broker adapter 已响应。")
    }

    private func brokerConfiguration() -> MedicalAIConfiguration {
        MedicalAIConfiguration(
            providerName: MedicalAIConfiguration.brokerProviderName,
            modelName: MedicalAIConfiguration.brokerDefaultModelName,
            endpointURLString: MedicalAIConfiguration.brokerRespondEndpoint,
            hasAPIKey: true
        )
    }

    private func brokerTestSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [BrokerTestURLProtocol.self]
        return URLSession(configuration: configuration)
    }
}

private enum BrokerTestError: Error {
    case invalidResponse
}

private final class LockedURLRequest {
    private let lock = NSLock()
    private var request: URLRequest?
    private var body: Data?

    func store(_ request: URLRequest, body: Data?) {
        lock.lock()
        self.request = request
        self.body = body
        lock.unlock()
    }

    func load() -> URLRequest? {
        lock.lock()
        defer { lock.unlock() }
        return request
    }

    func loadBody() -> Data? {
        lock.lock()
        defer { lock.unlock() }
        return body
    }
}

private final class BrokerTestURLProtocol: URLProtocol {
    fileprivate typealias Handler = (URLRequest) throws -> (HTTPURLResponse, Data)
    private static let handlerStore = OSAllocatedUnfairLock<Handler?>(
        uncheckedState: nil
    )

    fileprivate static var handler: Handler? {
        get {
            handlerStore.withLockUnchecked { $0 }
        }
        set {
            handlerStore.withLockUnchecked { $0 = newValue }
        }
    }

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

private func requestBodyData(from request: URLRequest) throws -> Data? {
    if let body = request.httpBody {
        return body
    }
    guard let stream = request.httpBodyStream else {
        return nil
    }

    stream.open()
    defer { stream.close() }
    var data = Data()
    var buffer = [UInt8](repeating: 0, count: 4_096)
    while stream.hasBytesAvailable {
        let count = stream.read(&buffer, maxLength: buffer.count)
        if count < 0 {
            throw stream.streamError ?? BrokerTestError.invalidResponse
        }
        if count == 0 {
            break
        }
        data.append(buffer, count: count)
    }
    return data
}
