import Testing
import MedicationAdherenceCore
@testable import MedicationAdherenceApp

struct RiskSearchIndexTests {
    @Test("搜索索引应该包含所有字段")
    func searchIndex_includesAllFields() {
        let card = StoredRiskCard(
            medicationID: UUID(),
            kind: .drugInteraction,
            severity: .high,
            title: "药物相互作用",
            message: "与阿司匹林同服可能增加出血风险",
            requiresProfessionalReview: true
        )
        card.sourceTitle = "药品说明书"
        card.sourceExcerpt = "禁忌：对阿司匹林过敏者"

        let index = RiskSearchIndex(card: card, medicationName: "阿莫西林")

        #expect(index.searchableText.contains("阿莫西林"))
        #expect(index.searchableText.contains("药物相互作用"))
        #expect(index.searchableText.contains("阿司匹林"))
        #expect(index.searchableText.contains("出血"))
        #expect(index.searchableText.contains("药品说明书"))
        #expect(index.searchableText.contains("禁忌"))
    }

    @Test("搜索索引应该匹配药品名称")
    func searchIndex_matchesMedicationName() {
        let card = StoredRiskCard(
            medicationID: UUID(),
            kind: .drugInteraction,
            severity: .medium,
            title: "注意事项",
            message: "饭后服用",
            requiresProfessionalReview: false
        )
        let index = RiskSearchIndex(card: card, medicationName: "阿莫西林胶囊")

        #expect(index.matches(query: ["阿莫"]))
        #expect(index.matches(query: ["西林"]))
        #expect(index.matches(query: ["胶囊"]))
    }

    @Test("搜索索引应该匹配警示标题")
    func searchIndex_matchesTitle() {
        let card = StoredRiskCard(
            medicationID: UUID(),
            kind: .adverseEffect,
            severity: .medium,
            title: "常见不良反应",
            message: "可能出现恶心、呕吐",
            requiresProfessionalReview: false
        )
        let index = RiskSearchIndex(card: card, medicationName: "药品A")

        #expect(index.matches(query: ["不良反应"]))
        #expect(index.matches(query: ["常见"]))
    }

    @Test("搜索索引应该匹配警示内容")
    func searchIndex_matchesMessage() {
        let card = StoredRiskCard(
            medicationID: UUID(),
            kind: .adverseEffect,
            severity: .low,
            title: "副作用",
            message: "可能引起头晕、嗜睡，驾驶时需注意",
            requiresProfessionalReview: false
        )
        let index = RiskSearchIndex(card: card, medicationName: "药品B")

        #expect(index.matches(query: ["头晕"]))
        #expect(index.matches(query: ["嗜睡"]))
        #expect(index.matches(query: ["驾驶"]))
    }

    @Test("搜索索引应该匹配来源标题")
    func searchIndex_matchesSourceTitle() {
        let card = StoredRiskCard(
            medicationID: UUID(),
            kind: .contraindication,
            severity: .critical,
            title: "禁忌症",
            message: "孕妇禁用",
            requiresProfessionalReview: true
        )
        card.sourceTitle = "国家药品监督管理局公告"

        let index = RiskSearchIndex(card: card, medicationName: "药品C")

        #expect(index.matches(query: ["药监局"]))
        #expect(index.matches(query: ["公告"]))
    }

    @Test("搜索索引应该匹配风险分类")
    func searchIndex_matchesRiskKind() {
        let card = StoredRiskCard(
            medicationID: UUID(),
            kind: .drugInteraction,
            severity: .high,
            title: "相互作用",
            message: "与华法林同服",
            requiresProfessionalReview: true
        )
        let index = RiskSearchIndex(card: card, medicationName: "药品D")

        #expect(index.matches(query: ["药物相互作用"]))
        #expect(index.matches(query: ["相互作用"]))
    }

    @Test("搜索索引应该匹配严重程度")
    func searchIndex_matchesSeverity() {
        let card = StoredRiskCard(
            medicationID: UUID(),
            kind: .adverseEffect,
            severity: .critical,
            title: "严重副作用",
            message: "过敏性休克",
            requiresProfessionalReview: true
        )
        let index = RiskSearchIndex(card: card, medicationName: "药品E")

        #expect(index.matches(query: ["危急"]))
        #expect(index.matches(query: ["critical"]))
    }

    @Test("搜索索引应该要求多个词都匹配")
    func searchIndex_multipleTokensAllMatch() {
        let card = StoredRiskCard(
            medicationID: UUID(),
            kind: .drugInteraction,
            severity: .high,
            title: "药物相互作用",
            message: "与阿司匹林同服增加出血风险",
            requiresProfessionalReview: true
        )
        let index = RiskSearchIndex(card: card, medicationName: "阿莫西林")

        #expect(index.matches(query: ["阿莫", "阿司匹林"]))
        #expect(index.matches(query: ["相互作用", "出血"]))
        #expect(!index.matches(query: ["阿莫", "青霉素"]))
    }

    @Test("空查询应该匹配所有风险")
    func searchIndex_emptyQueryMatchesAll() {
        let card = StoredRiskCard(
            medicationID: UUID(),
            kind: .adverseEffect,
            severity: .low,
            title: "轻微副作用",
            message: "可能口干",
            requiresProfessionalReview: false
        )
        let index = RiskSearchIndex(card: card, medicationName: "药品F")

        #expect(index.matches(query: []))
    }

    @Test("搜索索引应该处理空字段")
    func searchIndex_handlesEmptyFields() {
        let card = StoredRiskCard(
            medicationID: UUID(),
            kind: .adverseEffect,
            severity: .medium,
            title: "注意事项",
            message: "饭后服用",
            requiresProfessionalReview: false
        )
        card.sourceTitle = ""
        card.sourceExcerpt = ""

        let index = RiskSearchIndex(card: card, medicationName: "药品G")

        #expect(index.matches(query: ["注意"]))
        #expect(!index.searchableText.contains("  "))
    }

    @Test("搜索索引应该支持复杂查询")
    func searchIndex_complexQuery() {
        let card = StoredRiskCard(
            medicationID: UUID(),
            kind: .contraindication,
            severity: .critical,
            title: "孕妇及哺乳期妇女用药",
            message: "孕妇禁用，可能导致胎儿畸形",
            requiresProfessionalReview: true
        )
        card.sourceTitle = "药品说明书第7条"
        card.sourceExcerpt = "动物实验显示有致畸作用"

        let index = RiskSearchIndex(card: card, medicationName: "左氧氟沙星")

        #expect(index.matches(query: ["左氧", "孕妇"]))
        #expect(index.matches(query: ["禁用", "畸形"]))
        #expect(index.matches(query: ["说明书", "致畸"]))
        #expect(!index.matches(query: ["阿莫", "胶囊"]))
    }

    @Test("搜索索引应该不区分全角半角")
    func searchIndex_fullwidthHalfwidthMatching() {
        let card = StoredRiskCard(
            medicationID: UUID(),
            kind: .adverseEffect,
            severity: .medium,
            title: "注意事项",
            message: "服用后2小时内避免驾驶",
            requiresProfessionalReview: false
        )
        let index = RiskSearchIndex(card: card, medicationName: "药品H")

        #expect(index.matches(query: ["２小时"]))
        #expect(index.matches(query: ["２"]))
    }

    @Test("搜索索引应该支持英文不区分大小写")
    func searchIndex_englishCaseInsensitive() {
        let card = StoredRiskCard(
            medicationID: UUID(),
            kind: .adverseEffect,
            severity: .low,
            title: "Side Effects",
            message: "May cause dizziness",
            requiresProfessionalReview: false
        )
        let index = RiskSearchIndex(card: card, medicationName: "Amoxicillin")

        #expect(index.matches(query: ["amox"]))
        #expect(index.matches(query: ["AMOX"]))
        #expect(index.matches(query: ["dizz"]))
        #expect(index.matches(query: ["SIDE"]))
    }
}
