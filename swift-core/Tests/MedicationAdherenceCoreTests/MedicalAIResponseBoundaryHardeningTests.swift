import Testing
@testable import MedicationAdherenceCore

@Test func medicalAIResponseBoundaryBlocksGradualDoseReductionInstruction() {
    let review = MedicalAIResponseBoundaryGuard().review("建议逐渐减量，并观察三天。")

    #expect(review.blockedActionableInstruction)
    #expect(review.flags.contains("dose-change"))
    #expect(!review.displayMessage.contains("逐渐减量"))
}

@Test func medicalAIResponseBoundaryBlocksConditionalStopInstruction() {
    let review = MedicalAIResponseBoundaryGuard().review("如果症状缓解，可以停用该药。")

    #expect(review.blockedActionableInstruction)
    #expect(review.flags.contains("stop-medication"))
    #expect(!review.displayMessage.contains("可以停用"))
}

@Test func medicalAIResponseBoundaryBlocksStopAfterSymptomReliefInstruction() {
    let review = MedicalAIResponseBoundaryGuard().review("症状缓解后可停用本药。")

    #expect(review.blockedActionableInstruction)
    #expect(review.flags.contains("stop-medication"))
    #expect(!review.displayMessage.contains("可停用"))
}

@Test func medicalAIResponseBoundaryKeepsWarningAgainstGradualDoseReduction() {
    let review = MedicalAIResponseBoundaryGuard().review("不要自行逐渐减量或停用药物。")

    #expect(!review.blockedActionableInstruction)
    #expect(review.displayMessage.contains("不要自行逐渐减量或停用药物"))
}

@Test func medicalAIResponseBoundaryKeepsProfessionalReviewForDoseTapering() {
    let review = MedicalAIResponseBoundaryGuard().review("是否需要逐渐减量，应由医生判断。")

    #expect(!review.blockedActionableInstruction)
    #expect(review.displayMessage.contains("是否需要逐渐减量，应由医生判断"))
}

@Test func medicalAIResponseBoundaryDoesNotTrustClaimedSource() {
    for message in [
        "说明书提示建议停药。",
        "标签写明可以服用阿莫西林。",
        "如出现不适，说明书提示建议停药并把用量翻一番。"
    ] {
        let review = MedicalAIResponseBoundaryGuard().review(message)
        #expect(review.blockedActionableInstruction)
        #expect(!review.displayMessage.contains(message))
    }
}

@Test func medicalAIResponseBoundaryBlocksDoseMultiplierAdvice() {
    for message in [
        "把用量翻一番。",
        "下一次剂量翻倍。",
        "以后每次加倍服用。"
    ] {
        let review = MedicalAIResponseBoundaryGuard().review(message)
        #expect(review.blockedActionableInstruction)
        #expect(review.flags.contains("dose-change"))
        #expect(!review.displayMessage.contains(message))
    }
}

@Test func medicalAIResponseBoundaryKeepsGenericEmergencyReferral() {
    let message = "如出现严重不适，应停止使用并咨询医生或药师。"
    let review = MedicalAIResponseBoundaryGuard().review(message)
    #expect(!review.blockedActionableInstruction)
    #expect(review.displayMessage.contains(message))
}

@Test func medicalAIResponseBoundaryDoesNotLetRiskConditionMaskDoseChange() {
    let message = "如出现严重不适应停止使用并咨询医生，随后把用量翻一番。"
    let review = MedicalAIResponseBoundaryGuard().review(message)
    #expect(review.blockedActionableInstruction)
    #expect(review.flags.contains("dose-change"))
    #expect(!review.displayMessage.contains("用量翻一番"))
}

@Test func medicalAIResponseBoundaryDoesNotLetQuestionMaskLaterInstruction() {
    let message = "你问“是否可以停药”但建议停药。"
    let review = MedicalAIResponseBoundaryGuard().review(message)
    #expect(review.blockedActionableInstruction)
    #expect(review.flags.contains("stop-medication"))
    #expect(!review.displayMessage.contains("建议停药"))
}

@Test func medicalAIResponseBoundaryRequiresReferralForStopUseRiskText() {
    let message = "说明书提示如出现轻微不适应停止使用。"
    let review = MedicalAIResponseBoundaryGuard().review(message)
    #expect(review.blockedActionableInstruction)
    #expect(review.flags.contains("stop-medication"))
    #expect(!review.displayMessage.contains("应停止使用"))
}

@Test func medicalAIResponseBoundaryBlocksUnverifiedConcreteDoseInstructions() {
    let cases = [
        "说明书提示：每天服用 2 片。",
        "请每次服用 10 mg。",
        "每天 take 2 tablets。",
        "Take 2 tablets twice daily.",
        "每天服用 3 次。",
        "不要自行停药并建议每天服用 2 片。",
        "患者目前每天服用 2 片并建议改为每天 3 片。"
    ]

    for message in cases {
        let review = MedicalAIResponseBoundaryGuard().review(message)
        #expect(review.blockedActionableInstruction, "Unblocked instruction: \(message)")
        #expect(!review.displayMessage.contains(message), "Displayed instruction: \(message)")
    }
}

@Test func medicalAIResponseBoundaryKeepsCurrentDoseHistoryAndReferral() {
    for message in [
        "患者目前每天服用 2 片，具体用量请向医生核对。",
        "是否需要每天服用 2 片，应由医生判断。",
        "Do not take 2 tablets without checking with a clinician."
    ] {
        let review = MedicalAIResponseBoundaryGuard().review(message)
        #expect(!review.blockedActionableInstruction, "Blocked description: \(message)")
        #expect(review.displayMessage.contains(message))
    }
}
