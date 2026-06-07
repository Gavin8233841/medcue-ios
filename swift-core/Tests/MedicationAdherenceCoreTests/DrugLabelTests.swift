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
