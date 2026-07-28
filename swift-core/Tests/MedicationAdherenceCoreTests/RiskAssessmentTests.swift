import Testing
@testable import MedicationAdherenceCore

@Test func riskAssessmentBuildsLabelCardsWithEvidence() {
    let input = RiskAssessmentInput(
        medication: Medication(
            displayName: "Ibuprofen",
            kind: .overTheCounter,
            inputSource: .demoData
        ),
        label: DemoDrugLabels.all.first { $0.name == "Ibuprofen" }
    )

    let cards = RiskAssessmentEngine().assess(input)
    let interactionCard = cards.first { $0.title == "相互作用或需咨询药师" }

    #expect(interactionCard?.kind == .labelRisk)
    #expect(interactionCard?.requiresProfessionalReview == true)
    #expect(interactionCard?.evidence?.source == .demo)
    #expect(interactionCard?.evidence?.sourceTitle == "药物相互作用")
    #expect(interactionCard?.message.contains("阿司匹林预防心梗或卒中") == true)
    #expect(interactionCard?.message.contains("抗凝药、激素类药物") == true)
    #expect(interactionCard?.message.contains("当前正在使用的药品") == true)
    #expect(interactionCard?.safetyNote.contains("不能替代") == true)
}

@Test func labelRiskCardsNameConcreteContraindicationAndInteractionObjects() throws {
    let text = "【禁忌】对本品及其成分过敏者禁用。【药物相互作用】与酮康唑、红霉素、西咪替丁等合用时应咨询医生或药师。"
    let label = try #require(UserProvidedLabelBuilder().build(medicationName: "氯雷他定", rawText: text))
    let cards = RiskAssessmentEngine().assess(
        RiskAssessmentInput(
            medication: Medication(
                displayName: "氯雷他定",
                kind: .overTheCounter,
                inputSource: .manual
            ),
            label: label
        )
    )

    let contraindicationCard = try #require(cards.first { $0.title == "禁忌或不得使用" })
    let interactionCard = try #require(cards.first { $0.title == "相互作用或需咨询药师" })

    #expect(contraindicationCard.message.contains("对本品及其成分过敏者禁用"))
    #expect(contraindicationCard.message.contains("是否属于上述人群、成分过敏或用药条件"))
    #expect(interactionCard.message.contains("酮康唑、红霉素、西咪替丁"))
    #expect(interactionCard.message.contains("当前正在使用的药品、保健品和外用药清单"))
    #expect(contraindicationCard.evidence?.excerpt == "对本品及其成分过敏者禁用。")
    #expect(interactionCard.evidence?.excerpt == "与酮康唑、红霉素、西咪替丁等合用时应咨询医生或药师。")
}

@Test func healthAndDietEntriesOnlyCreateReviewCardsWhenLabelMentionsThem() {
    let label = MedicationLabel(
        name: "Example",
        source: .demo,
        sections: [
            DrugLabelSection(
                title: "Warnings",
                text: "Ask a doctor before use if you have kidney disease. Avoid grapefruit while using this medicine."
            )
        ]
    )
    let input = RiskAssessmentInput(
        medication: Medication(
            displayName: "Example",
            kind: .overTheCounter,
            inputSource: .manual
        ),
        label: label,
        healthConditionEntries: [
            UserRiskContextEntry(name: "kidney disease"),
            UserRiskContextEntry(name: "diabetes")
        ],
        dietaryConcernEntries: [
            UserRiskContextEntry(name: "grapefruit")
        ]
    )

    let cards = RiskAssessmentEngine().assess(input)

    #expect(cards.contains { card in
        card.kind == .healthConditionReview
            && card.title == "病症相关复核：kidney disease"
            && card.message.contains("不代表 App 判断")
    })
    #expect(!cards.contains { card in
        card.kind == .healthConditionReview && card.title.contains("diabetes")
    })
    #expect(cards.contains { card in
        card.kind == .foodReview && card.title == "饮食相关复核：grapefruit"
    })
}

@Test func prescriptionAndUserProvidedSourcesCreateReviewCards() {
    let label = MedicationLabel(
        name: "Example",
        source: .userProvided,
        sections: [
            DrugLabelSection(title: "Warnings", text: "Ask a doctor before use.")
        ]
    )
    let input = RiskAssessmentInput(
        medication: Medication(
            displayName: "Example",
            kind: .prescription,
            inputSource: .prescriptionImage
        ),
        label: label
    )

    let cards = RiskAssessmentEngine().assess(input)

    #expect(cards.contains { $0.id == "source-prescription" })
    #expect(cards.contains { $0.id == "source-prescription-image" })
    #expect(cards.contains { $0.id == "source-user-provided-label" })
    #expect(cards.filter(\.requiresProfessionalReview).count >= 3)
}

@Test func unknownMedicationKindCreatesSourceReviewCard() {
    let input = RiskAssessmentInput(
        medication: Medication(
            displayName: "Unknown",
            kind: .unknown,
            inputSource: .manual
        )
    )

    let cards = RiskAssessmentEngine().assess(input)

    #expect(cards.contains { card in
        card.id == "source-unknown-kind"
            && card.message.contains("药品类型尚未确认")
    })
}

@Test func drugClassCardsAreInformationalOnly() {
    let input = RiskAssessmentInput(
        medication: Medication(
            displayName: "Ibuprofen",
            kind: .overTheCounter,
            inputSource: .demoData
        ),
        drugClasses: [
            DrugClass(classID: "N0000175722", name: "Analgesics", source: "MEDRT")
        ]
    )

    let cards = RiskAssessmentEngine().assess(input)
    let classCard = cards.first { $0.kind == .drugClassContext }

    #expect(classCard?.title == "药品类别信息：Analgesics")
    #expect(classCard?.requiresProfessionalReview == false)
    #expect(classCard?.message.contains("不") == true)
    #expect(classCard?.message.contains("自动判断相互作用") == true)
}

@Test func demoRiskAssessmentDataGeneratesOfflineCards() {
    let cards = RiskAssessmentEngine().assess(DemoRiskAssessmentData.ibuprofenReview)

    #expect(cards.contains { $0.kind == .labelRisk })
    #expect(cards.contains { $0.kind == .healthConditionReview })
    #expect(cards.contains { $0.kind == .drugClassContext })
    #expect(cards.allSatisfy { $0.safetyNote == RiskAssessmentEngine.defaultSafetyNote })
}

@Test func realisticChineseOTCLabelKeepsConcreteRiskObjects() throws {
    let text = """
    【禁忌】对本品及其他非甾体抗炎药过敏者禁用；活动性消化道溃疡或出血患者禁用。
    【注意事项】肝功能不全、肾功能不全、哮喘或既往胃出血患者使用前应咨询医生或药师；饮酒者慎用。
    【药物相互作用】与阿司匹林、华法林、糖皮质激素或其他止痛药合用时应咨询医生或药师。
    【孕妇及哺乳期妇女用药】孕妇及哺乳期妇女使用前请咨询医生或药师。
    【儿童用药】儿童必须在成人监护下使用。
    【老年用药】老年患者应在医生或药师指导下使用。
    """
    let label = try #require(UserProvidedLabelBuilder().build(medicationName: "布洛芬", rawText: text))
    let cards = RiskAssessmentEngine().assess(
        RiskAssessmentInput(
            medication: Medication(
                displayName: "布洛芬",
                genericName: "ibuprofen",
                kind: .overTheCounter,
                inputSource: .manual
            ),
            label: label,
            healthConditionEntries: [
                UserRiskContextEntry(name: "肝功能"),
                UserRiskContextEntry(name: "肾功能"),
                UserRiskContextEntry(name: "哮喘"),
                UserRiskContextEntry(name: "胃出血"),
                UserRiskContextEntry(name: "孕妇及哺乳期"),
                UserRiskContextEntry(name: "儿童"),
                UserRiskContextEntry(name: "老年")
            ],
            dietaryConcernEntries: [
                UserRiskContextEntry(name: "饮酒")
            ]
        )
    )

    let contraindicationCard = try #require(cards.first { $0.title == "禁忌或不得使用" })
    let interactionCard = try #require(cards.first { $0.title == "相互作用或需咨询药师" })
    let foodCard = try #require(cards.first { $0.title == "饮食注意" })

    #expect(contraindicationCard.message.contains("非甾体抗炎药过敏者禁用"))
    #expect(contraindicationCard.evidence?.excerpt.contains("活动性消化道溃疡或出血患者禁用") == true)
    #expect(interactionCard.message.contains("阿司匹林、华法林、糖皮质激素"))
    #expect(interactionCard.evidence?.sourceTitle == "药物相互作用")
    #expect(foodCard.message.contains("饮酒者慎用"))
    #expect(foodCard.evidence?.sourceTitle == "注意事项")
    #expect(cards.contains { $0.title == "病症相关复核：肝功能" && $0.evidence?.excerpt.contains("肝功能不全") == true })
    #expect(cards.contains { $0.title == "病症相关复核：肾功能" && $0.evidence?.excerpt.contains("肾功能不全") == true })
    #expect(cards.contains { $0.title == "病症相关复核：孕妇及哺乳期" && $0.evidence?.sourceTitle == "孕妇及哺乳期妇女用药" })
    #expect(cards.contains { $0.title == "病症相关复核：儿童" && $0.evidence?.sourceTitle == "儿童用药" })
    #expect(cards.contains { $0.title == "病症相关复核：老年" && $0.evidence?.sourceTitle == "老年用药" })
    #expect(cards.allSatisfy { !$0.message.contains("相关风险") })
}

@Test func labelTextAloneDoesNotCreateUserContextReviewCards() throws {
    let text = """
    【注意事项】肝功能不全、肾功能不全者使用前应咨询医生或药师；饮酒者慎用。
    【药物相互作用】与华法林或其他止痛药合用时应咨询医生或药师。
    """
    let label = try #require(UserProvidedLabelBuilder().build(medicationName: "布洛芬", rawText: text))

    let cards = RiskAssessmentEngine().assess(
        RiskAssessmentInput(
            medication: Medication(
                displayName: "布洛芬",
                genericName: "ibuprofen",
                kind: .overTheCounter,
                inputSource: .manual
            ),
            label: label
        )
    )

    #expect(cards.contains { $0.kind == .labelRisk && $0.title == "饮食注意" })
    #expect(cards.contains { $0.kind == .labelRisk && $0.title == "相互作用或需咨询药师" })
    #expect(!cards.contains { $0.kind == .healthConditionReview })
    #expect(!cards.contains { $0.kind == .foodReview })
    #expect(!cards.contains { $0.message.contains("你的健康记录中") })
    #expect(!cards.contains { $0.message.contains("你的饮食注意记录中") })
}
