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
    #expect(response.provider.providerName == "医疗智能体")
    #expect(response.provider.modelName == "unconfigured")
    #expect(response.message.contains("医疗智能体暂时无法连接"))
    #expect(response.message.contains("未发送任何用药数据"))
    #expect(!response.message.contains("API"))
    #expect(!response.message.contains("鉴权"))
    #expect(!response.message.contains("App 层"))
    #expect(!response.message.contains("供应商适配器"))
    #expect(!response.provider.providerName.contains("未配置"))
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
        evidence: RiskAssessmentEvidence(
            sourceTitle: "药物相互作用",
            excerpt: "与华法林等抗凝药同用时应咨询医生或药师。"
        ),
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
    #expect(prompt.contains("来源章节：药物相互作用"))
    #expect(prompt.contains("依据片段：与华法林等抗凝药同用时应咨询医生或药师。"))
    #expect(prompt.contains("不能替代医生或药师判断"))
    #expect(prompt.contains("100字以内"))
    #expect(prompt.contains("不要使用 Markdown、LaTeX、表格、列表符号或表情符号"))
    #expect(prompt.contains("请在回答末尾保留一句边界提示"))
    #expect(prompt.contains("帮我把风险提醒说清楚"))
    #expect(prompt.contains("建议咨询医生或药师"))
    #expect(!prompt.contains("需要医生或药师复核"))
}

@Test func medicalAIPromptBuilderDoesNotSendUnclearMedicationNameAsName() {
    let medication = Medication(
        displayName: "1",
        kind: .overTheCounter,
        form: "片剂",
        strength: "100 mg",
        inputSource: .manual
    )
    let request = MedicalAIRequest(
        kind: .chat,
        userMessage: "今天需要吃哪几个药",
        authorization: MedicalAIUserAuthorization(grantedScopes: [.medicationProfile]),
        medicationSnapshots: [
            MedicalAIMedicationSnapshot(medication: medication)
        ]
    )

    let prompt = MedicalAIRequestPromptBuilder().buildPrompt(for: request)

    #expect(prompt.contains("待核对药品名称（100 mg · 片剂）"))
    #expect(!prompt.contains("\n1. 1\n"))
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

@Test func medicalAIPromptBuilderIncludesEnvironmentInsightsForWeatherQuestions() {
    let request = MedicalAIRequest(
        kind: .chat,
        userMessage: "今天的天气对用药有什么影响",
        authorization: MedicalAIUserAuthorization(grantedScopes: []),
        environmentInsights: [
            MedicalAIEnvironmentInsight(
                title: "干燥环境关注",
                message: "湿度偏低，滴眼类药品请按既定计划核对使用。",
                sourceSummary: "22°C · 湿度 28% · 降水 10% · 风速 18km/h",
                severityText: "关注"
            )
        ]
    )

    let prompt = MedicalAIRequestPromptBuilder().buildPrompt(for: request)

    #expect(prompt.contains("今日环境关注"))
    #expect(prompt.contains("必须优先结合这些环境关注和已授权用药数据"))
    #expect(prompt.contains("干燥环境关注"))
    #expect(prompt.contains("湿度偏低"))
    #expect(prompt.contains("环境来源：22°C · 湿度 28% · 降水 10% · 风速 18km/h"))
}

@Test func medicalAIEnvironmentQuestionDetectorRecognizesNaturalWeatherQuestions() {
    let detector = MedicalAIEnvironmentQuestionDetector()

    #expect(detector.shouldAttachEnvironmentContext(to: "今天太热会影响我的用药安排吗"))
    #expect(detector.shouldAttachEnvironmentContext(to: "花粉和雾霾会不会影响氯雷他定"))
    #expect(detector.shouldAttachEnvironmentContext(to: "air quality and pollen today"))
    #expect(detector.shouldAttachEnvironmentContext(to: "外出下雨要注意什么"))
    #expect(detector.shouldAttachEnvironmentContext(to: "今天温差大，我的用药计划要注意什么"))
    #expect(detector.shouldAttachEnvironmentContext(to: "台风和暴雨会影响我今天带药吗"))
    #expect(detector.shouldAttachEnvironmentContext(to: "沙尘和空气污染会不会影响鼻炎药"))
    #expect(detector.shouldAttachEnvironmentContext(to: "sunlight and heat today"))
    #expect(!detector.shouldAttachEnvironmentContext(to: "这个药有什么风险需要复核"))
    #expect(!detector.shouldAttachEnvironmentContext(to: "帮我整理复诊沟通重点"))
}

@Test func medicalAIPromptBuilderUsesProductizedImportReviewWording() {
    let draft = MedicationImportDraft(
        source: .barcode,
        displayName: "布洛芬",
        barcodeValue: "6900000000000",
        confidenceByField: [.displayName: 0.91]
    )
    let review = MedicationImportReviewEngine().review(draft)
    let request = MedicalAIRequest(
        kind: .barcodeImportReview,
        userMessage: "核对这次条码导入",
        authorization: MedicalAIUserAuthorization(grantedScopes: [.importDraft]),
        importReview: review
    )

    let prompt = MedicalAIRequestPromptBuilder().buildPrompt(for: request)

    #expect(prompt.contains("请求类型：药盒条码导入核对"))
    #expect(prompt.contains("导入识别内容核对"))
    #expect(!prompt.contains("导入草稿复核"))
    #expect(!prompt.contains("药盒条码导入复核"))
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

@Test func medicalAIResponseBoundaryBlocksDirectStopAndDoseInstructions() {
    let review = MedicalAIResponseBoundaryGuard().review("根据描述可以停药，并将剂量改为每天两次。")

    #expect(review.blockedActionableInstruction)
    #expect(review.flags.contains("stop-medication"))
    #expect(review.flags.contains("dose-change"))
    #expect(!review.displayMessage.contains("可以停药"))
    #expect(!review.displayMessage.contains("剂量改为每天两次"))
    #expect(review.displayMessage.contains("不能作为操作依据"))
    #expect(review.displayMessage.contains("请联系医生或药师核对"))
}

@Test func medicalAIResponseBoundaryBlocksDirectDiagnosis() {
    let review = MedicalAIResponseBoundaryGuard().review("根据这些症状，可以诊断为高血压。")

    #expect(review.blockedActionableInstruction)
    #expect(review.flags.contains("diagnosis"))
    #expect(!review.displayMessage.contains("诊断为高血压"))
    #expect(review.displayMessage.contains("请联系医生或药师核对"))
}

@Test func medicalAIResponseBoundaryBlocksDirectPrescriptionInstruction() {
    let review = MedicalAIResponseBoundaryGuard().review("建议开始服用阿莫西林，每次一粒。")

    #expect(review.blockedActionableInstruction)
    #expect(review.flags.contains("prescription"))
    #expect(!review.displayMessage.contains("开始服用阿莫西林"))
    #expect(review.displayMessage.contains("请联系医生或药师核对"))
}

@Test func medicalAIResponseBoundaryBlocksDirectMedicationSwitch() {
    let review = MedicalAIResponseBoundaryGuard().review("建议把氯雷他定换成西替利嗪。")

    #expect(review.blockedActionableInstruction)
    #expect(review.flags.contains("switch-medication"))
    #expect(!review.displayMessage.contains("换成西替利嗪"))
    #expect(review.displayMessage.contains("请联系医生或药师核对"))
}

@Test func medicalAIResponseBoundaryBlocksDirectDoseIncrease() {
    let review = MedicalAIResponseBoundaryGuard().review("把每次剂量增加到两片。")

    #expect(review.blockedActionableInstruction)
    #expect(review.flags.contains("dose-change"))
    #expect(!review.displayMessage.contains("剂量增加到两片"))
    #expect(review.displayMessage.contains("请联系医生或药师核对"))
}

@Test func medicalAIResponseBoundaryBlocksDirectFrequencyChange() {
    let review = MedicalAIResponseBoundaryGuard().review("把服药频次从每天一次调整为每天三次。")

    #expect(review.blockedActionableInstruction)
    #expect(review.flags.contains("frequency-change"))
    #expect(!review.displayMessage.contains("调整为每天三次"))
    #expect(review.displayMessage.contains("请联系医生或药师核对"))
}

@Test func medicalAIResponseBoundaryBlocksDirectTreatmentDecisionVariants() {
    let cases = [
        (message: "你患有高血压。", flag: "diagnosis", leakedText: "患有高血压"),
        (message: "可以服用阿莫西林。", flag: "prescription", leakedText: "服用阿莫西林"),
        (message: "请停止服用布洛芬。", flag: "stop-medication", leakedText: "停止服用布洛芬"),
        (message: "改用西替利嗪。", flag: "switch-medication", leakedText: "改用西替利嗪"),
        (message: "将剂量减少到半片。", flag: "dose-change", leakedText: "剂量减少到半片"),
        (message: "每日改为三次。", flag: "frequency-change", leakedText: "每日改为三次")
    ]

    for item in cases {
        let review = MedicalAIResponseBoundaryGuard().review(item.message)

        #expect(review.blockedActionableInstruction)
        #expect(review.flags.contains(item.flag))
        #expect(!review.displayMessage.contains(item.leakedText))
    }
}

@Test func medicalAIResponseBoundaryKeepsAdviceAgainstSelfDirectedMedicationChanges() {
    let review = MedicalAIResponseBoundaryGuard().review("不要自行停药、换药或调整剂量。")

    #expect(!review.blockedActionableInstruction)
    #expect(review.displayMessage.contains("不要自行停药、换药或调整剂量"))
}

@Test func medicalAIResponseBoundaryKeepsQuotedUserTreatmentQuestion() {
    let review = MedicalAIResponseBoundaryGuard().review("你问“是否可以停药并把剂量改为每天两次”，这需要医生判断。")

    #expect(!review.blockedActionableInstruction)
    #expect(review.displayMessage.contains("你问“是否可以停药并把剂量改为每天两次”"))
}

@Test func medicalAIResponseBoundaryKeepsDoseLimitsAndAvoidanceText() {
    let review = MedicalAIResponseBoundaryGuard().review("单日剂量不应超过说明书上限；如已有肝功能异常，应避免使用或调整剂量。")

    #expect(!review.blockedActionableInstruction)
    #expect(!review.flags.contains("dose-change"))
    #expect(!review.flags.contains("stop-medication"))
    #expect(review.displayMessage.contains("单日剂量不应超过"))
    #expect(review.displayMessage.contains("以上内容仅用于用药风险提示和复诊沟通"))
}

@Test func medicalAIResponseBoundaryKeepsDrugLabelRiskDescription() {
    let review = MedicalAIResponseBoundaryGuard().review("说明书提示，如出现严重不适应停止使用并咨询医生或药师。")

    #expect(!review.blockedActionableInstruction)
    #expect(review.displayMessage.contains("说明书提示，如出现严重不适应停止使用并咨询医生或药师"))
}

@Test func medicalAIResponseBoundaryKeepsProfessionalReviewQuestion() {
    let review = MedicalAIResponseBoundaryGuard().review("是否需要调整剂量应由医生判断。")

    #expect(!review.blockedActionableInstruction)
    #expect(review.displayMessage.contains("是否需要调整剂量应由医生判断"))
}

@Test func medicalAIResponseBoundaryStillBlocksDirectInstructionBeforeReviewAdvice() {
    let review = MedicalAIResponseBoundaryGuard().review("可以停药，请咨询医生。")

    #expect(review.blockedActionableInstruction)
    #expect(review.flags.contains("stop-medication"))
    #expect(!review.displayMessage.contains("可以停药"))
}

@Test func medicalAIResponseBoundaryDoesNotLetQuestionWordMaskLaterInstruction() {
    let review = MedicalAIResponseBoundaryGuard().review("无论是否不适，都建议停药。")

    #expect(review.blockedActionableInstruction)
    #expect(review.flags.contains("stop-medication"))
    #expect(!review.displayMessage.contains("建议停药"))
}

@Test func medicalAIResponseBoundaryDoesNotLetSourcePrefixMaskSeparateInstruction() {
    let review = MedicalAIResponseBoundaryGuard().review("说明书提示需要复核，建议停药。")

    #expect(review.blockedActionableInstruction)
    #expect(review.flags.contains("stop-medication"))
    #expect(!review.displayMessage.contains("建议停药"))
}

@Test func medicalAIResponseBoundaryNormalizesMarkdownWithoutReplacingMeaning() {
    let review = MedicalAIResponseBoundaryGuard().review("""
    ## 注意
    - **请核对说明书**
    1. `不要自行改药`
    """)

    #expect(review.displayMessage.contains("注意"))
    #expect(review.displayMessage.contains("请核对说明书"))
    #expect(review.displayMessage.contains("不要自行改药"))
    #expect(!review.displayMessage.contains("##"))
    #expect(!review.displayMessage.contains("**"))
    #expect(!review.displayMessage.contains("`"))
    #expect(review.flags.contains("plain-text-normalized"))
    #expect(review.flags.contains("missing-safety-boundary"))
    #expect(!review.blockedActionableInstruction)
}

@Test func medicalAIResponseBoundaryHandlesEmptyMessage() {
    let review = MedicalAIResponseBoundaryGuard().review("   ")

    #expect(review.displayMessage.contains("暂无可读回复"))
    #expect(!review.displayMessage.contains("医疗 AI"))
    #expect(review.displayMessage.contains("以上内容仅用于用药风险提示和复诊沟通"))
    #expect(review.appendedSafetyNote)
    #expect(review.flags == ["empty-response"])
}
