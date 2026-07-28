import Foundation
import MedicationAdherenceCore
import Testing
import os
@testable import MedicationAdherenceApp

@Suite(.serialized)
struct CloudBaseMedicalAIClientTests {
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
