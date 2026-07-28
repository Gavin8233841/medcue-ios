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
