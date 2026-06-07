import Foundation
import Testing
@testable import MedicationAdherenceCore

@Test func medicalAIValidatorRequiresOnlyAuthorizedDataScopes() {
    let medication = Medication(displayName: "Ibuprofen", kind: .overTheCounter, inputSource: .demoData)
    let request = MedicalAIRequest(
        kind: .riskOptimization,
        userMessage: "请优化风险提醒",
        authorization: MedicalAIUserAuthorization(grantedScopes: [.medicationProfile, .riskCards]),
        medicationSnapshots: [
            MedicalAIMedicationSnapshot(
                medication: medication,
                riskCards: [
                    RiskAssessmentCard(
                        id: "risk",
                        kind: .labelRisk,
                        displayPriority: 10,
                        title: "相互作用",
                        message: "说明书提示需要复核。",
                        requiresProfessionalReview: true
                    )
                ]
            )
        ]
    )

    let missing = MedicalAIRequestValidator().missingRequiredScopes(for: request)

    #expect(missing.isEmpty)
    #expect(MedicalAIRequestValidator().canSend(request))
}

@Test func medicalAIValidatorBlocksMissingDoseEventAuthorization() {
    let medication = Medication(displayName: "Ibuprofen", kind: .overTheCounter, inputSource: .demoData)
    let scheduledDose = ScheduledDose(planID: UUID(), dueAt: Date(), dose: DoseAmount(value: 1, unit: "tablet"))
    let request = MedicalAIRequest(
        kind: .chat,
        userMessage: "读取记录后提醒我",
        authorization: MedicalAIUserAuthorization(grantedScopes: [.medicationProfile]),
        medicationSnapshots: [
            MedicalAIMedicationSnapshot(
                medication: medication,
                scheduledDoses: [scheduledDose],
                doseEvents: [
                    DoseEvent(scheduledDoseID: scheduledDose.id, status: .taken, recordedAt: Date())
                ]
            )
        ]
    )

    let missing = MedicalAIRequestValidator().missingRequiredScopes(for: request)

    #expect(missing == [.doseEvents])
    #expect(!MedicalAIRequestValidator().canSend(request))
}

@Test func unconfiguredMedicalAIClientReturnsPlaceholderResponse() async throws {
    let request = MedicalAIRequest(
        kind: .chat,
        userMessage: "你好",
        authorization: MedicalAIUserAuthorization(grantedScopes: [])
    )

    let response = try await UnconfiguredMedicalAIClient().respond(to: request)

    #expect(response.requestID == request.id)
    #expect(response.provider.modelName == "unconfigured")
    #expect(response.message.contains("尚未配置"))
}

@Test func medicalAIPromptBuilderKeepsSafetyBoundaryAndAuthorizedSnapshot() {
    let medication = Medication(
        displayName: "Ibuprofen",
        genericName: "ibuprofen",
        kind: .overTheCounter,
        form: "Tablet",
        strength: "200 mg",
        inputSource: .demoData
    )
    let riskCard = RiskAssessmentCard(
        id: "risk",
        kind: .labelRisk,
        displayPriority: 10,
        title: "药物相互作用复核",
        message: "说明书提示与抗凝药同用时需要咨询医生或药师。",
        requiresProfessionalReview: true
    )
    let request = MedicalAIRequest(
        kind: .riskOptimization,
        userMessage: "帮我把风险提醒说清楚",
        authorization: MedicalAIUserAuthorization(grantedScopes: [.medicationProfile, .riskCards]),
        medicationSnapshots: [
            MedicalAIMedicationSnapshot(medication: medication, riskCards: [riskCard])
        ]
    )

    let prompt = MedicalAIRequestPromptBuilder().buildPrompt(for: request)

    #expect(prompt.contains("Ibuprofen"))
    #expect(prompt.contains("药物相互作用复核"))
    #expect(prompt.contains("不能替代医生或药师判断"))
    #expect(prompt.contains("100字以内"))
    #expect(prompt.contains("不要使用 Markdown、LaTeX、表格、列表符号或表情符号"))
    #expect(prompt.contains("请在回答末尾保留一句边界提示"))
    #expect(prompt.contains("帮我把风险提醒说清楚"))
}

@Test func medicalAIPromptBuilderStatesWhenNoSnapshotIsShared() {
    let request = MedicalAIRequest(
        kind: .chat,
        userMessage: "你好",
        authorization: MedicalAIUserAuthorization(grantedScopes: [])
    )

    let prompt = MedicalAIRequestPromptBuilder().buildPrompt(for: request)

    #expect(prompt.contains("本次请求未包含药品快照"))
}

@Test func medicalAIResponseBoundaryAppendsSafetyNoteWhenMissing() {
    let review = MedicalAIResponseBoundaryGuard().review("可以先核对说明书中的禁忌和相互作用。")

    #expect(review.displayMessage.contains("以上内容仅用于用药风险提示和复诊沟通"))
    #expect(review.appendedSafetyNote)
    #expect(review.flags == ["missing-safety-boundary"])
    #expect(!review.blockedActionableInstruction)
}

@Test func medicalAIResponseBoundaryKeepsAlreadyBoundedMessage() {
    let message = "请核对说明书并咨询药师。\n\(MedicalAIResponseBoundaryGuard.safetyNote)"

    let review = MedicalAIResponseBoundaryGuard().review(message)

    #expect(review.displayMessage == message)
    #expect(review.flags == [])
    #expect(!review.appendedSafetyNote)
}

@Test func medicalAIResponseBoundaryBlocksActionableMedicationDecision() {
    let review = MedicalAIResponseBoundaryGuard().review("根据描述可以停药，并将剂量改为每天两次。")

    #expect(!review.blockedActionableInstruction)
    #expect(review.flags.contains("stop-medication"))
    #expect(review.flags.contains("dose-change"))
    #expect(review.displayMessage.contains("剂量改为每天两次"))
    #expect(review.displayMessage.contains("以上内容仅用于用药风险提示和复诊沟通"))
}

@Test func medicalAIResponseBoundaryBlocksDoseLimitsAndAvoidanceInstructions() {
    let review = MedicalAIResponseBoundaryGuard().review("单日剂量不应超过说明书上限；如已有肝功能异常，应避免使用或调整剂量。")

    #expect(!review.blockedActionableInstruction)
    #expect(review.flags.contains("dose-change"))
    #expect(review.flags.contains("stop-medication"))
    #expect(review.displayMessage.contains("单日剂量不应超过"))
    #expect(review.displayMessage.contains("以上内容仅用于用药风险提示和复诊沟通"))
}

@Test func medicalAIResponseBoundaryHandlesEmptyMessage() {
    let review = MedicalAIResponseBoundaryGuard().review("   ")

    #expect(review.displayMessage.contains("暂无可读回复"))
    #expect(review.displayMessage.contains("以上内容仅用于用药风险提示和复诊沟通"))
    #expect(review.appendedSafetyNote)
    #expect(review.flags == ["empty-response"])
}
