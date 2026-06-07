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
    #expect(interactionCard?.evidence?.sourceTitle == "Warnings")
    #expect(interactionCard?.safetyNote.contains("不能替代") == true)
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
