import Foundation
import MedicationAdherenceCore
import Testing
@testable import MedicationAdherenceApp

struct RiskSearchIndexTests {
    @Test("搜索索引包含风险的全部授权字段")
    func searchIndexIncludesAllFields() {
        let card = makeCard(
            kind: .drugClassContext,
            severity: .high,
            title: "联合用药提示",
            message: "与阿司匹林同服可能增加出血风险",
            sourceTitle: "药品说明书",
            sourceExcerpt: "禁忌：对阿司匹林过敏者"
        )

        let index = RiskSearchIndex(
            card: card,
            medicationName: "阿莫西林",
            medicationGenericName: "Amoxicillin"
        )

        #expect(index.searchableText.contains("阿莫西林"))
        #expect(index.searchableText.contains("amoxicillin"))
        #expect(index.searchableText.contains("联合用药提示"))
        #expect(index.searchableText.contains("阿司匹林"))
        #expect(index.searchableText.contains("药物相互作用"))
        #expect(index.searchableText.contains("高"))
        #expect(index.searchableText.contains("药品说明书"))
        #expect(index.searchableText.contains("禁忌"))
    }

    @Test("搜索索引匹配关联药品显示名和通用名")
    func searchIndexMatchesMedicationNames() {
        let index = RiskSearchIndex(
            card: makeCard(),
            medicationName: "阿莫西林胶囊",
            medicationGenericName: "Amoxicillin"
        )

        #expect(index.matches(query: ["阿莫"]))
        #expect(index.matches(query: ["胶囊"]))
        #expect(index.matches(query: ["AMOX"]))
    }

    @Test("搜索索引匹配警示标题和正文")
    func searchIndexMatchesWarningContent() {
        let index = RiskSearchIndex(
            card: makeCard(
                title: "常见不良反应",
                message: "可能出现头晕、嗜睡，驾驶时需注意"
            ),
            medicationName: "测试药品"
        )

        #expect(index.matches(query: ["不良反应"]))
        #expect(index.matches(query: ["头晕", "驾驶"]))
        #expect(!index.matches(query: ["出血"]))
    }

    @Test("搜索索引匹配来源标题和片段")
    func searchIndexMatchesSource() {
        let index = RiskSearchIndex(
            card: makeCard(
                sourceTitle: "国家药品监督管理局公告",
                sourceExcerpt: "动物实验显示有致畸作用"
            ),
            medicationName: "测试药品"
        )

        #expect(index.matches(query: ["药品监督", "公告"]))
        #expect(index.matches(query: ["动物实验", "致畸"]))
    }

    @Test("搜索索引匹配风险分组显示名")
    func searchIndexMatchesRiskGroup() {
        let interaction = RiskSearchIndex(
            card: makeCard(kind: .drugClassContext),
            medicationName: "药品 A"
        )
        let lifestyle = RiskSearchIndex(
            card: makeCard(kind: .foodReview),
            medicationName: "药品 B"
        )

        #expect(interaction.matches(query: ["药物相互作用"]))
        #expect(lifestyle.matches(query: ["饮食", "生活方式"]))
    }

    @Test("搜索索引匹配严重程度显示名")
    func searchIndexMatchesSeverity() {
        let index = RiskSearchIndex(
            card: makeCard(severity: .critical),
            medicationName: "测试药品"
        )

        #expect(index.matches(query: ["紧急"]))
        #expect(!index.matches(query: ["低"]))
    }

    @Test("多个搜索词要求全部命中")
    func searchIndexRequiresAllTokens() {
        let index = RiskSearchIndex(
            card: makeCard(
                kind: .drugClassContext,
                title: "联合用药提示",
                message: "与阿司匹林同服增加出血风险"
            ),
            medicationName: "阿莫西林"
        )

        #expect(index.matches(query: ["阿莫", "阿司匹林"]))
        #expect(index.matches(query: ["相互作用", "出血"]))
        #expect(!index.matches(query: ["阿莫", "青霉素"]))
    }

    @Test("空查询匹配所有风险")
    func searchIndexEmptyQueryMatchesAll() {
        let index = RiskSearchIndex(card: makeCard(), medicationName: "测试药品")

        #expect(index.matches(query: []))
        #expect(index.matches(query: ["   "]))
    }

    @Test("空来源字段不会产生重复分隔符")
    func searchIndexHandlesEmptyFields() {
        let index = RiskSearchIndex(card: makeCard(), medicationName: "测试药品")

        #expect(index.matches(query: ["注意事项"]))
        #expect(!index.searchableText.contains("  "))
    }

    @Test("搜索索引支持大小写和全半角规范化")
    func searchIndexSupportsNormalizedQuery() {
        let index = RiskSearchIndex(
            card: makeCard(
                title: "Side Effects",
                message: "服用后2小时内可能 dizziness"
            ),
            medicationName: "Amoxicillin"
        )

        #expect(index.matches(query: ["AMOX"]))
        #expect(index.matches(query: ["SIDE", "DIZZ"]))
        #expect(index.matches(query: ["２小时"]))
    }

    private func makeCard(
        kind: RiskAssessmentCardKind = .labelRisk,
        severity: StoredRiskSeverity = .medium,
        title: String = "注意事项",
        message: String = "饭后服用",
        sourceTitle: String = "",
        sourceExcerpt: String = ""
    ) -> StoredRiskCard {
        StoredRiskCard(
            id: UUID().uuidString,
            medicationID: UUID(),
            kindRaw: kind.rawValue,
            severityRaw: severity.rawValue,
            displayPriority: severity.badgePriority,
            title: title,
            message: message,
            sourceTitle: sourceTitle,
            sourceExcerpt: sourceExcerpt,
            requiresProfessionalReview: severity.isActionable,
            safetyNote: RiskAssessmentEngine.defaultSafetyNote
        )
    }
}
