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
        "以后每次加倍服用。",
        "请从明天起把用量翻倍。",
        "建议把药量加倍。",
        "把药量翻倍后再服用。",
        "建议用量加倍。"
    ] {
        let review = MedicalAIResponseBoundaryGuard().review(message)
        #expect(review.blockedActionableInstruction)
        #expect(review.flags.contains("dose-change"))
        #expect(!review.displayMessage.contains(message))
    }
}

@Test func medicalAIResponseBoundaryKeepsWarningsAgainstNewMultiplierPhrases() {
    for message in [
        "不要自行把用量翻倍，应先联系医生。",
        "是否需要把药量加倍，应由医生判断。",
        "不要把药量加倍。",
        "请勿把用量翻倍。",
        "别把药量加倍。",
        "切勿把药量加倍。",
        "不可把药量加倍。",
        "不能把药量加倍。",
        "能不能把药量加倍？",
        "可以把药量加倍吗？",
        "可以把药量加倍吗?",
        "不建议把药量加倍。",
        "你问“是否把药量加倍”应由医生判断。",
        "“把药量加倍”是错误建议，请咨询医生。",
        "“请把药量加倍”是错误建议，请勿照做。",
        "不要把药量加倍然后不要把用量翻倍。",
        "你问“是否需要把用量翻倍然后把药量加倍”？"
    ] {
        let review = MedicalAIResponseBoundaryGuard().review(message)
        #expect(!review.blockedActionableInstruction, "Blocked safety education: \(message)")
        #expect(review.displayMessage.contains(message))
    }
}

@Test func medicalAIResponseBoundaryDoesNotLetWarningOrQuestionMaskLaterMultiplierAdvice() {
    for message in [
        "不要自行把用量翻倍然后把药量加倍。",
        "你问“是否需要把用量翻倍”随后把药量翻倍。",
        "不要把药量加倍但是应该把用量翻倍。",
        "请勿把用量翻倍再把药量加倍。",
        "不要把药量加倍却把用量翻倍。",
        "不要把药量加倍而应该把用量翻倍。",
        "不要把药量加倍还要把用量翻倍。",
        "你问是否把药量加倍却应该把用量翻倍。",
        "你问是否要加量我认为把药量加倍。",
        "用户问能否加量我答把药量加倍。",
        "不要自行停药并把药量加倍。",
        "不要自行停药之后把用量翻倍。",
        "请把药量加倍好吗？"
    ] {
        let review = MedicalAIResponseBoundaryGuard().review(message)
        #expect(review.blockedActionableInstruction, "Missed later dose advice: \(message)")
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

@Test func medicalAIResponseBoundaryDoesNotLetUnquotedQuestionMaskPersonalAdvice() {
    for message in [
        "你问是否可以停药我建议停药。",
        "不要自行停药我建议改用另一种药。"
    ] {
        let review = MedicalAIResponseBoundaryGuard().review(message)
        #expect(review.blockedActionableInstruction, "Unblocked advice: \(message)")
        #expect(!review.displayMessage.contains(message))
    }
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
