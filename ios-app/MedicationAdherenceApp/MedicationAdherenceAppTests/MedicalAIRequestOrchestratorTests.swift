import Foundation
import MedicationAdherenceCore
import Testing
@testable import MedicationAdherenceApp

struct MedicalAIRequestOrchestratorTests {
    @Test
    func cloudExecutionTimesOutAndCancelsTheUnderlyingClient() async {
        let request = Self.request()
        let client = SlowMedicalAIClient(delay: .seconds(5), response: Self.response(for: request, message: "结果"))
        let orchestrator = MedicalAIRequestOrchestrator(timeout: .milliseconds(20))

        do {
            _ = try await orchestrator.execute(request: request, client: client)
            Issue.record("Expected timeout")
        } catch let error as MedicalAIOrchestrationError {
            #expect(error == .timedOut)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test
    func callerCancellationIsPreservedInsteadOfBecomingTransportFailure() async {
        let request = Self.request()
        let client = SlowMedicalAIClient(delay: .seconds(5), response: Self.response(for: request, message: "结果"))
        let task = Task {
            try await MedicalAIRequestOrchestrator(timeout: .seconds(20)).execute(
                request: request,
                client: client
            )
        }
        task.cancel()

        do {
            _ = try await task.value
            Issue.record("Expected cancellation")
        } catch is CancellationError {
            // Expected.
        } catch {
            Issue.record("Expected CancellationError, got \(error)")
        }
    }

    @Test
    func finalizerRejectsEmptyResponseBeforePersistence() {
        #expect(throws: MedicalAIOrchestrationError.emptyResponse) {
            try MedicalAIResponseFinalizer().finalize(answer: " \n ")
        }
    }

    @Test
    func finalizerAppliesMedicalBoundaryAndDropsUnsafeThinking() throws {
        let finalized = try MedicalAIResponseFinalizer().finalize(
            answer: "你应该立即把剂量加倍。",
            thinking: "建议用户自行停药。"
        )

        #expect(finalized.boundaryBlockedAction)
        #expect(finalized.thinking.isEmpty)
        #expect(!finalized.displayMessage.contains("加倍"))
        #expect(finalized.persistedMessage == finalized.displayMessage)
    }

    @Test
    func finalizerKeepsConcreteDoseInstructionOutOfDisplayAndPersistence() throws {
        let finalized = try MedicalAIResponseFinalizer().finalize(
            answer: "说明书提示：每天服用 2 片。"
        )

        #expect(finalized.boundaryBlockedAction)
        #expect(!finalized.displayMessage.contains("每天服用 2 片"))
        #expect(finalized.persistedMessage == finalized.displayMessage)
    }

    @Test
    func finalizerKeepsColloquialMultiplierAdviceOutOfDisplayAndPersistence() throws {
        let finalized = try MedicalAIResponseFinalizer().finalize(
            answer: "建议把药量加倍。",
            thinking: "这个问题需要调整用量。"
        )

        #expect(finalized.boundaryBlockedAction)
        #expect(finalized.boundaryFlags.contains("dose-change"))
        #expect(!finalized.displayMessage.contains("药量加倍"))
        #expect(finalized.thinking.isEmpty)
        #expect(finalized.persistedMessage == finalized.displayMessage)
    }

    @Test
    func finalizerKeepsLaterMultiplierAdviceOutOfDisplayAndPersistence() throws {
        for answer in [
            "不要自行把用量翻倍然后把药量加倍。",
            "你问“是否需要把用量翻倍”随后把药量翻倍。",
            "不要把药量加倍却把用量翻倍。",
            "你问是否要加量我认为把药量加倍。",
            "不要自行停药并把药量加倍。",
            "请把药量加倍好吗？",
            "麻烦你把药量加倍好吗？"
        ] {
            let finalized = try MedicalAIResponseFinalizer().finalize(answer: answer)
            #expect(finalized.boundaryBlockedAction)
            #expect(finalized.boundaryFlags.contains("dose-change"))
            #expect(!finalized.displayMessage.contains(answer))
            #expect(finalized.persistedMessage == finalized.displayMessage)
        }
    }

    @Test
    func mismatchedResponseRequestIDIsRejected() async {
        let request = Self.request()
        let wrongResponse = MedicalAIResponse(
            requestID: UUID(),
            provider: Self.provider,
            message: "结果"
        )

        do {
            _ = try await MedicalAIRequestOrchestrator(timeout: .seconds(1)).execute(
                request: request,
                client: ImmediateMedicalAIClient(response: wrongResponse)
            )
            Issue.record("Expected request ID rejection")
        } catch let error as MedicalAIOrchestrationError {
            #expect(error == .mismatchedRequestID)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    private static let provider = MedicalAIProviderProfile(
        providerName: "测试服务",
        modelName: "test-model",
        serviceLicenseSummary: "测试"
    )

    private static func request() -> MedicalAIRequest {
        MedicalAIRequest(
            kind: .chat,
            userMessage: "请整理记录",
            authorization: MedicalAIUserAuthorization(
                grantedScopes: [],
                grantedAt: Date(),
                expiresAt: Date().addingTimeInterval(300)
            )
        )
    }

    private static func response(for request: MedicalAIRequest, message: String) -> MedicalAIResponse {
        MedicalAIResponse(requestID: request.id, provider: provider, message: message)
    }
}

private struct ImmediateMedicalAIClient: MedicalAIClient {
    let response: MedicalAIResponse

    func respond(to request: MedicalAIRequest) async throws -> MedicalAIResponse {
        response
    }
}

private struct SlowMedicalAIClient: MedicalAIClient {
    let delay: Duration
    let response: MedicalAIResponse

    func respond(to request: MedicalAIRequest) async throws -> MedicalAIResponse {
        try await Task.sleep(for: delay)
        return response
    }
}
