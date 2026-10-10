// PR #73 exact algorithm regression tests; only type names renamed for the temporary bridge.
import Testing
@testable import MedicationAdherenceApp

struct MedicationBrowseSearchTextNormalizerTests {
    @Test("规范化应该去除前后空白")
    func normalize_removesWhitespace() {
        let result = MedicationBrowseSearchTextNormalizer.normalize("  阿莫西林  ")
        #expect(result == "阿莫西林")
    }

    @Test("规范化应该转换为小写")
    func normalize_convertsToLowercase() {
        let result = MedicationBrowseSearchTextNormalizer.normalize("Amoxicillin")
        #expect(result == "amoxicillin")
    }

    @Test("规范化应该将全角转为半角")
    func normalize_convertsFullwidthToHalfwidth() {
        #expect(MedicationBrowseSearchTextNormalizer.normalize("１２３") == "123")
        #expect(MedicationBrowseSearchTextNormalizer.normalize("ＡＢＣ") == "abc")
        #expect(MedicationBrowseSearchTextNormalizer.normalize("５００ｍｇ") == "500mg")
    }

    @Test("规范化应该把可忽略标点视为词边界")
    func normalize_replacesIgnorablePunctuationWithWordBoundaries() {
        #expect(MedicationBrowseSearchTextNormalizer.normalize("阿莫西林,胶囊") == "阿莫西林 胶囊")
        #expect(MedicationBrowseSearchTextNormalizer.normalize("500mg。每日三次！") == "500mg 每日三次")
        #expect(MedicationBrowseSearchTextNormalizer.normalize("注意：饭后服用。") == "注意 饭后服用")
        #expect(MedicationBrowseSearchTextNormalizer.normalize("tablet/capsule (oral)-daily") == "tablet capsule oral daily")
    }

    @Test("分词应该按空格分割")
    func tokenize_splitsOnWhitespace() {
        let tokens = MedicationBrowseSearchTextNormalizer.tokenize("阿莫西林 胶囊")
        #expect(tokens == ["阿莫西林", "胶囊"])
    }

    @Test("分词应该把中英文标点视为分隔符而不是粘连词")
    func tokenize_splitsOnPunctuation() {
        #expect(MedicationBrowseSearchTextNormalizer.tokenize("阿莫西林,胶囊") == ["阿莫西林", "胶囊"])
        #expect(MedicationBrowseSearchTextNormalizer.tokenize("amoxicillin/tablet-dose") == ["amoxicillin", "tablet", "dose"])
        #expect(MedicationBrowseSearchTextNormalizer.tokenize("（处方药）：500mg") == ["处方药", "500mg"])
    }

    @Test("分词应该过滤空词")
    func tokenize_filtersEmptyTokens() {
        let tokens = MedicationBrowseSearchTextNormalizer.tokenize("  阿莫西林   胶囊  ")
        #expect(tokens == ["阿莫西林", "胶囊"])
    }

    @Test("分词应该处理单个词")
    func tokenize_singleToken() {
        let tokens = MedicationBrowseSearchTextNormalizer.tokenize("阿莫西林")
        #expect(tokens == ["阿莫西林"])
    }

    @Test("分词应该处理空字符串")
    func tokenize_emptyString() {
        let tokens = MedicationBrowseSearchTextNormalizer.tokenize("")
        #expect(tokens.isEmpty)
    }

    @Test("匹配应该支持中文子串")
    func matches_chineseSubstring() {
        #expect(MedicationBrowseSearchTextNormalizer.matches(query: ["阿莫"], in: "阿莫西林胶囊"))
        #expect(MedicationBrowseSearchTextNormalizer.matches(query: ["西林"], in: "阿莫西林胶囊"))
        #expect(!MedicationBrowseSearchTextNormalizer.matches(query: ["青霉素"], in: "阿莫西林胶囊"))
    }

    @Test("匹配应该不区分大小写（英文）")
    func matches_englishCaseInsensitive() {
        #expect(MedicationBrowseSearchTextNormalizer.matches(query: ["amox"], in: "amoxicillin"))
        #expect(MedicationBrowseSearchTextNormalizer.matches(query: ["AMOX"], in: "amoxicillin"))
        #expect(MedicationBrowseSearchTextNormalizer.matches(query: ["Amox"], in: "AMOXICILLIN"))
    }

    @Test("匹配应该要求所有词都命中")
    func matches_multipleTokensAllRequired() {
        #expect(MedicationBrowseSearchTextNormalizer.matches(query: ["阿莫", "胶囊"], in: "阿莫西林胶囊"))
        #expect(!MedicationBrowseSearchTextNormalizer.matches(query: ["阿莫", "片剂"], in: "阿莫西林胶囊"))
    }

    @Test("匹配应该支持混合中英文数字")
    func matches_mixedChineseEnglishNumber() {
        let text = "阿莫西林 amoxicillin 500mg 胶囊"
        #expect(MedicationBrowseSearchTextNormalizer.matches(query: ["阿莫", "500"], in: text))
        #expect(MedicationBrowseSearchTextNormalizer.matches(query: ["amox", "胶囊"], in: text))
        #expect(MedicationBrowseSearchTextNormalizer.matches(query: ["500", "mg"], in: text))
    }

    @Test("匹配应该处理空查询（匹配所有）")
    func matches_emptyQueryMatchesAll() {
        #expect(MedicationBrowseSearchTextNormalizer.matches(query: [], in: "任意文本"))
        #expect(MedicationBrowseSearchTextNormalizer.matches(query: [], in: ""))
    }

    @Test("规范化应该处理复杂场景")
    func normalize_complexScenario() {
        let input = "  阿莫西林，Amoxicillin！５００ｍｇ。  "
        let result = MedicationBrowseSearchTextNormalizer.normalize(input)
        #expect(result == "阿莫西林 amoxicillin 500mg")
    }

    @Test("端到端：规范化查询并匹配")
    func endToEnd_normalizeAndMatch() {
        let searchableText = MedicationBrowseSearchTextNormalizer.normalize("阿莫西林胶囊 Amoxicillin Capsules 500mg")
        let query = MedicationBrowseSearchTextNormalizer.tokenize("阿莫 500")
        #expect(MedicationBrowseSearchTextNormalizer.matches(query: query, in: searchableText))
    }

    @Test("端到端：全角查询匹配半角内容")
    func endToEnd_fullwidthQueryMatchesHalfwidth() {
        let searchableText = MedicationBrowseSearchTextNormalizer.normalize("500mg")
        let query = MedicationBrowseSearchTextNormalizer.tokenize("５００")
        #expect(MedicationBrowseSearchTextNormalizer.matches(query: query, in: searchableText))
    }

    @Test("端到端：标点分隔的查询词可以跨字段匹配")
    func endToEnd_punctuationSeparatedQueryMatchesAcrossFields() {
        let searchableText = MedicationBrowseSearchTextNormalizer.normalize("阿莫西林 胶囊 500 mg")

        #expect(MedicationBrowseSearchTextNormalizer.matches(query: ["阿莫西林,胶囊"], in: searchableText))
        #expect(MedicationBrowseSearchTextNormalizer.matches(query: ["500/mg"], in: searchableText))
    }

    @Test("端到端：可忽略分隔符的存在与否不应造成漏搜")
    func endToEnd_ignoresSeparatorPresenceDifferences() {
        #expect(MedicationBrowseSearchTextNormalizer.matches(query: ["500mg"], in: "500 mg"))
        #expect(MedicationBrowseSearchTextNormalizer.matches(query: ["500 mg"], in: "500mg"))
        #expect(MedicationBrowseSearchTextNormalizer.matches(query: ["D3"], in: "Vitamin D-3"))
        #expect(MedicationBrowseSearchTextNormalizer.matches(query: ["D-3"], in: "Vitamin D3"))
        #expect(MedicationBrowseSearchTextNormalizer.matches(query: ["阿莫西林（胶囊）"], in: "阿莫西林 胶囊"))
    }
}
