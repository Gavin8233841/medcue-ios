import Testing
@testable import MedicationAdherenceCore

@Test func riskExtractorFindsWarningsAndInteractions() async throws {
    let label = MedicationLabel(
        name: "Example",
        source: .demo,
        sections: [
            DrugLabelSection(
                title: "Warnings",
                text: "Ask a doctor or pharmacist before use if you take a blood thinning medicine. Alcohol warning applies."
            )
        ]
    )

    let notices = RiskTextExtractor().extract(from: label)

    #expect(notices.contains { $0.kind == .interaction })
    #expect(notices.contains { $0.kind == .foodWarning })
    #expect(notices.contains { $0.kind == .generalWarning })
}

@Test func demoProviderReturnsFallbackLabel() async throws {
    let provider = DemoDrugLabelProvider()
    let label = try await provider.label(for: "ibuprofen")

    #expect(label.name == "Ibuprofen")
    #expect(label.source == .demo)
    #expect(!label.sections.isEmpty)
}

@Test func userProvidedLabelBuilderSplitsChineseInstructionSections() throws {
    let text = """
    禁忌
    对本品过敏者禁用。
    注意事项
    饮酒或合用其他药物时请咨询医生或药师。
    不良反应
    可能出现胃部不适。
    """

    let label = try #require(UserProvidedLabelBuilder().build(medicationName: "示例药", rawText: text))
    let notices = RiskTextExtractor().extract(from: label)

    #expect(label.source == .userProvided)
    #expect(label.sections.map(\.title).contains("禁忌"))
    #expect(label.sections.map(\.title).contains("注意事项"))
    #expect(label.sections.map(\.title).contains("不良反应"))
    #expect(notices.contains { $0.kind == .contraindication })
    #expect(notices.contains { $0.kind == .foodWarning })
    #expect(notices.contains { $0.kind == .interaction })
    #expect(notices.contains { $0.kind == .adverseReaction })
}

@Test func userProvidedLabelBuilderSplitsInlineChineseBracketSections() throws {
    let text = "【药品名称】氯雷他定片。【适应症】用于缓解过敏性鼻炎相关症状。【禁忌】对本品及其成分过敏者禁用。【注意事项】严重肝功能不全者应在医生指导下使用；妊娠期、哺乳期妇女请咨询医生或药师。【药物相互作用】与酮康唑、红霉素、西咪替丁等合用时应咨询医生或药师。【不良反应】可见乏力、嗜睡、口干、头痛等。"

    let label = try #require(UserProvidedLabelBuilder().build(medicationName: "氯雷他定", rawText: text))
    let sectionTitles = label.sections.map(\.title)

    #expect(sectionTitles == ["药品名称", "适应症", "禁忌", "注意事项", "药物相互作用", "不良反应"])
    #expect(label.sections.first { $0.title == "禁忌" }?.text == "对本品及其成分过敏者禁用。")
    #expect(label.sections.first { $0.title == "药物相互作用" }?.text == "与酮康唑、红霉素、西咪替丁等合用时应咨询医生或药师。")
    #expect(label.sections.allSatisfy { !$0.text.contains("【") && !$0.text.contains("】") })

    let notices = RiskTextExtractor().extract(from: label)
    let contraindication = try #require(notices.first { $0.kind == .contraindication })
    let interaction = try #require(notices.first { $0.kind == .interaction })
    let warning = try #require(notices.first { $0.kind == .generalWarning })
    let adverseReaction = try #require(notices.first { $0.kind == .adverseReaction })

    #expect(contraindication.sourceTitle == "禁忌")
    #expect(contraindication.excerpt == "对本品及其成分过敏者禁用。")
    #expect(!contraindication.excerpt.contains("注意事项"))
    #expect(interaction.sourceTitle == "药物相互作用")
    #expect(warning.sourceTitle == "注意事项")
    #expect(adverseReaction.sourceTitle == "不良反应")
}

@Test func riskAssessmentUsesSectionSpecificEvidenceForInlineChineseLabels() throws {
    let text = "【禁忌】对本品及其成分过敏者禁用。【注意事项】严重肝功能不全者应在医生指导下使用。【药物相互作用】与酮康唑、红霉素、西咪替丁等合用时应咨询医生或药师。"
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
    let contraindicationEvidence = try #require(contraindicationCard.evidence)
    let interactionEvidence = try #require(interactionCard.evidence)

    #expect(contraindicationEvidence.sourceTitle == "禁忌")
    #expect(contraindicationEvidence.excerpt == "对本品及其成分过敏者禁用。")
    #expect(!contraindicationEvidence.excerpt.contains("药物相互作用"))
    #expect(interactionEvidence.sourceTitle == "药物相互作用")
    #expect(interactionEvidence.excerpt == "与酮康唑、红霉素、西咪替丁等合用时应咨询医生或药师。")
    #expect(contraindicationCard.message.contains("对本品及其成分过敏者禁用"))
    #expect(interactionCard.message.contains("酮康唑、红霉素、西咪替丁"))
    #expect(interactionCard.safetyNote.contains("不能替代医生或药师判断"))
}

@Test func userProvidedLabelBuilderSplitsSpecialPopulationSections() throws {
    let text = "【注意事项】肝功能不全者应在医生指导下使用。【孕妇及哺乳期妇女用药】孕妇及哺乳期妇女应咨询医生或药师。【儿童用药】儿童应在成人监护下使用。【老年用药】老年患者使用前请咨询医生或药师。"

    let label = try #require(UserProvidedLabelBuilder().build(medicationName: "氯雷他定", rawText: text))
    let sectionTitles = label.sections.map(\.title)

    #expect(sectionTitles == ["注意事项", "孕妇及哺乳期妇女用药", "儿童用药", "老年用药"])
    #expect(label.sections.first { $0.title == "注意事项" }?.text == "肝功能不全者应在医生指导下使用。")
    #expect(label.sections.first { $0.title == "孕妇及哺乳期妇女用药" }?.text == "孕妇及哺乳期妇女应咨询医生或药师。")
    #expect(label.sections.first { $0.title == "儿童用药" }?.text == "儿童应在成人监护下使用。")
    #expect(label.sections.first { $0.title == "老年用药" }?.text == "老年患者使用前请咨询医生或药师。")

    let notices = RiskTextExtractor().extract(from: label)
    #expect(notices.filter { $0.kind == .generalWarning }.count == 4)
    #expect(notices.contains { $0.sourceTitle == "孕妇及哺乳期妇女用药" && $0.excerpt == "孕妇及哺乳期妇女应咨询医生或药师。" })
    #expect(notices.contains { $0.sourceTitle == "儿童用药" && $0.excerpt == "儿童应在成人监护下使用。" })
    #expect(notices.contains { $0.sourceTitle == "老年用药" && $0.excerpt == "老年患者使用前请咨询医生或药师。" })
}
