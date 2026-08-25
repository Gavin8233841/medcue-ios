import Testing
import MedicationAdherenceCore
@testable import MedicationAdherenceApp

struct MedicationSearchIndexTests {
    @Test("搜索索引应该包含所有字段")
    func searchIndex_includesAllFields() {
        let medication = StoredMedication(
            brandName: "阿莫西林",
            genericName: "Amoxicillin",
            formulation: "胶囊"
        )
        medication.strength = "500mg"
        medication.kindRaw = "antibiotics"
        medication.notes = "饭后服用"

        let index = MedicationSearchIndex(medication: medication)

        #expect(index.searchableText.contains("阿莫西林"))
        #expect(index.searchableText.contains("amoxicillin"))
        #expect(index.searchableText.contains("500mg"))
        #expect(index.searchableText.contains("胶囊"))
        #expect(index.searchableText.contains("抗生素"))
        #expect(index.searchableText.contains("饭后服用"))
    }

    @Test("搜索索引应该匹配显示名称")
    func searchIndex_matchesDisplayName() {
        let medication = StoredMedication(
            brandName: "阿莫西林胶囊",
            genericName: nil,
            formulation: "胶囊"
        )
        let index = MedicationSearchIndex(medication: medication)

        #expect(index.matches(query: ["阿莫"]))
        #expect(index.matches(query: ["西林"]))
        #expect(!index.matches(query: ["青霉素"]))
    }

    @Test("搜索索引应该匹配通用名")
    func searchIndex_matchesGenericName() {
        let medication = StoredMedication(
            brandName: "阿莫西林",
            genericName: "Amoxicillin",
            formulation: "胶囊"
        )
        let index = MedicationSearchIndex(medication: medication)

        #expect(index.matches(query: ["amox"]))
        #expect(index.matches(query: ["AMOX"]))
        #expect(index.matches(query: ["cillin"]))
    }

    @Test("搜索索引应该匹配规格")
    func searchIndex_matchesStrength() {
        let medication = StoredMedication(
            brandName: "阿莫西林",
            genericName: nil,
            formulation: "胶囊"
        )
        medication.strength = "500mg"

        let index = MedicationSearchIndex(medication: medication)

        #expect(index.matches(query: ["500"]))
        #expect(index.matches(query: ["500mg"]))
        #expect(index.matches(query: ["mg"]))
    }

    @Test("搜索索引应该匹配剂型")
    func searchIndex_matchesForm() {
        let medication = StoredMedication(
            brandName: "阿莫西林",
            genericName: nil,
            formulation: "胶囊"
        )
        let index = MedicationSearchIndex(medication: medication)

        #expect(index.matches(query: ["胶囊"]))
        #expect(!index.matches(query: ["片剂"]))
    }

    @Test("搜索索引应该匹配药品类别")
    func searchIndex_matchesMedicationKind() {
        let medication = StoredMedication(
            brandName: "阿莫西林",
            genericName: nil,
            formulation: "胶囊"
        )
        medication.kindRaw = "antibiotics"

        let index = MedicationSearchIndex(medication: medication)

        #expect(index.matches(query: ["抗生素"]))
        #expect(index.matches(query: ["antibiotic"]))
    }

    @Test("搜索索引应该匹配备注")
    func searchIndex_matchesNotes() {
        let medication = StoredMedication(
            brandName: "阿莫西林",
            genericName: nil,
            formulation: "胶囊"
        )
        medication.notes = "对青霉素过敏者禁用"

        let index = MedicationSearchIndex(medication: medication)

        #expect(index.matches(query: ["青霉素"]))
        #expect(index.matches(query: ["过敏"]))
        #expect(index.matches(query: ["禁用"]))
    }

    @Test("搜索索引应该要求多个词都匹配")
    func searchIndex_multipleTokensAllMatch() {
        let medication = StoredMedication(
            brandName: "阿莫西林",
            genericName: "Amoxicillin",
            formulation: "胶囊"
        )
        medication.strength = "500mg"

        let index = MedicationSearchIndex(medication: medication)

        #expect(index.matches(query: ["阿莫", "500"]))
        #expect(index.matches(query: ["amox", "胶囊"]))
        #expect(!index.matches(query: ["阿莫", "片剂"]))
    }

    @Test("空查询应该匹配所有药品")
    func searchIndex_emptyQueryMatchesAll() {
        let medication = StoredMedication(
            brandName: "阿莫西林",
            genericName: nil,
            formulation: "胶囊"
        )
        let index = MedicationSearchIndex(medication: medication)

        #expect(index.matches(query: []))
    }

    @Test("搜索索引应该处理空字段")
    func searchIndex_handlesEmptyFields() {
        let medication = StoredMedication(
            brandName: "阿莫西林",
            genericName: "",
            formulation: "胶囊"
        )
        medication.strength = ""
        medication.notes = ""

        let index = MedicationSearchIndex(medication: medication)

        #expect(index.matches(query: ["阿莫"]))
        #expect(!index.searchableText.contains("  "))
    }

    @Test("搜索索引应该不区分全角半角")
    func searchIndex_fullwidthHalfwidthMatching() {
        let medication = StoredMedication(
            brandName: "阿莫西林",
            genericName: nil,
            formulation: "胶囊"
        )
        medication.strength = "500mg"

        let index = MedicationSearchIndex(medication: medication)

        #expect(index.matches(query: ["５００"]))
        #expect(index.matches(query: ["５００ｍｇ"]))
    }

    @Test("搜索索引应该支持复杂查询")
    func searchIndex_complexQuery() {
        let medication = StoredMedication(
            brandName: "盐酸左氧氟沙星片",
            genericName: "Levofloxacin Hydrochloride",
            formulation: "片剂"
        )
        medication.strength = "0.5g"
        medication.kindRaw = "antibiotics"
        medication.notes = "空腹服用效果更好"

        let index = MedicationSearchIndex(medication: medication)

        #expect(index.matches(query: ["左氧", "片剂"]))
        #expect(index.matches(query: ["levo", "0.5"]))
        #expect(index.matches(query: ["抗生素", "空腹"]))
        #expect(!index.matches(query: ["阿莫", "胶囊"]))
    }
}
