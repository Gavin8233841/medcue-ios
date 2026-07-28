import Testing
@testable import MedicationAdherenceCore

@Test func readableLabelSummaryKeepsSourceAndSafetyNote() {
    let label = MedicationLabel(
        name: "Example",
        source: .demo,
        sections: [
            DrugLabelSection(title: "Warnings", text: "Ask a doctor before use."),
            DrugLabelSection(title: "Dosage And Administration", text: "Use only as directed.")
        ]
    )

    let summary = ReadableLabelSummaryBuilder().build(from: label)

    #expect(summary.medicationName == "Example")
    #expect(summary.source == .demo)
    #expect(summary.cards.count == 2)
    #expect(summary.cards[0].kind == .warnings)
    #expect(summary.cards[0].heading == "需要重点查看")
    #expect(summary.cards[1].kind == .directions)
    #expect(summary.safetyNote.contains("不能替代"))
}

@Test func readableLabelSummaryLimitsLongExcerpts() {
    let longText = String(repeating: "A", count: 320)
    let label = MedicationLabel(
        name: "Example",
        source: .demo,
        sections: [
            DrugLabelSection(title: "Use", text: longText)
        ]
    )

    let summary = ReadableLabelSummaryBuilder(maxExcerptLength: 120).build(from: label)

    #expect(summary.cards[0].kind == .uses)
    #expect(summary.cards[0].sourceExcerpt.count == 120)
    #expect(summary.cards[0].plainLanguageNote.contains("不代表 App 判断"))
}
