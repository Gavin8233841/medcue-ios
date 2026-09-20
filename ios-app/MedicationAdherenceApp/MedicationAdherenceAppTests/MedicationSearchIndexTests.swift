import MedicationAdherenceCore
import Testing
@testable import MedicationAdherenceApp

struct MedicationSearchIndexTests {
    @Test("搜索索引包含药品的全部授权字段")
    func searchIndexIncludesAllFields() {
        let medication = makeMedication(
            displayName: "阿莫西林",
            genericName: "Amoxicillin",
            kind: .prescription,
            form: "胶囊",
            strength: "500 mg",
            notes: "饭后服用"
        )

        let index = MedicationSearchIndex(medication: medication)

        #expect(index.searchableText.contains("阿莫西林"))
        #expect(index.searchableText.contains("amoxicillin"))
        #expect(index.searchableText.contains("500 mg"))
        #expect(index.searchableText.contains("胶囊"))
        #expect(index.searchableText.contains("处方药"))
        #expect(index.searchableText.contains("饭后服用"))
    }

    @Test("搜索索引匹配显示名称和通用名")
    func searchIndexMatchesNames() {
        let index = MedicationSearchIndex(medication: makeMedication(
            displayName: "阿莫西林胶囊",
            genericName: "Amoxicillin"
        ))

        #expect(index.matches(query: ["阿莫"]))
        #expect(index.matches(query: ["AMOX"]))
        #expect(index.matches(query: ["cillin"]))
        #expect(!index.matches(query: ["青霉素"]))
    }

    @Test("搜索索引匹配规格和剂型")
    func searchIndexMatchesStrengthAndForm() {
        let index = MedicationSearchIndex(medication: makeMedication(
            displayName: "测试药品",
            form: "胶囊",
            strength: "500 mg"
        ))

        #expect(index.matches(query: ["500"]))
        #expect(index.matches(query: ["500mg"]))
        #expect(index.matches(query: ["５００ｍｇ"]))
        #expect(index.matches(query: ["胶囊"]))
        #expect(!index.matches(query: ["片剂"]))
    }

    @Test("搜索索引匹配药品类别显示名和备注")
    func searchIndexMatchesKindAndNotes() {
        let index = MedicationSearchIndex(medication: makeMedication(
            displayName: "测试药品",
            kind: .prescription,
            notes: "对青霉素过敏者请咨询医生"
        ))

        #expect(index.matches(query: ["处方药"]))
        #expect(index.matches(query: ["青霉素", "咨询"]))
        #expect(!index.matches(query: ["非处方药"]))
    }

    @Test("多个搜索词要求全部命中")
    func searchIndexRequiresAllTokens() {
        let index = MedicationSearchIndex(medication: makeMedication(
            displayName: "阿莫西林",
            genericName: "Amoxicillin",
            form: "胶囊",
            strength: "500mg"
        ))

        #expect(index.matches(query: ["阿莫", "500"]))
        #expect(index.matches(query: ["AMOX", "胶囊"]))
        #expect(!index.matches(query: ["阿莫", "片剂"]))
    }

    @Test("空查询匹配所有药品")
    func searchIndexEmptyQueryMatchesAll() {
        let index = MedicationSearchIndex(medication: makeMedication(displayName: "阿莫西林"))

        #expect(index.matches(query: []))
        #expect(index.matches(query: ["   "]))
    }

    @Test("空字段不会产生重复分隔符")
    func searchIndexHandlesEmptyFields() {
        let index = MedicationSearchIndex(medication: makeMedication(displayName: "阿莫西林"))

        #expect(index.matches(query: ["阿莫"]))
        #expect(!index.searchableText.contains("  "))
    }

    @Test("复杂查询支持中英文、数字和标点规范化")
    func searchIndexSupportsMixedNormalizedQuery() {
        let index = MedicationSearchIndex(medication: makeMedication(
            displayName: "盐酸左氧氟沙星片",
            genericName: "Levofloxacin Hydrochloride",
            kind: .prescription,
            form: "片剂",
            strength: "0.5g",
            notes: "空腹服用前请咨询医生"
        ))

        #expect(index.matches(query: ["左氧", "片剂"]))
        #expect(index.matches(query: ["LEVO", "０．５ｇ"]))
        #expect(index.matches(query: ["处方药", "空腹"]))
        #expect(!index.matches(query: ["阿莫", "胶囊"]))
    }

    private func makeMedication(
        displayName: String,
        genericName: String = "",
        kind: MedicationKind = .unknown,
        form: String = "",
        strength: String = "",
        notes: String = ""
    ) -> StoredMedication {
        StoredMedication(
            displayName: displayName,
            genericName: genericName,
            kind: kind,
            form: form,
            strength: strength,
            inputSource: .manual,
            notes: notes
        )
    }
}
