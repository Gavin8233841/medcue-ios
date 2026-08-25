import Testing
@testable import MedicationAdherenceApp

struct SearchTextNormalizerTests {
    @Test("规范化应该去除前后空白")
    func normalize_removesWhitespace() {
        let result = SearchTextNormalizer.normalize("  阿莫西林  ")
        #expect(result == "阿莫西林")
    }

    @Test("规范化应该转换为小写")
    func normalize_convertsToLowercase() {
        let result = SearchTextNormalizer.normalize("Amoxicillin")
        #expect(result == "amoxicillin")
    }

    @Test("规范化应该将全角转为半角")
    func normalize_convertsFullwidthToHalfwidth() {
        #expect(SearchTextNormalizer.normalize("１２３") == "123")
        #expect(SearchTextNormalizer.normalize("ＡＢＣ") == "abc")
        #expect(SearchTextNormalizer.normalize("５００ｍｇ") == "500mg")
    }

    @Test("规范化应该去除可忽略的标点")
    func normalize_removesIgnorablePunctuation() {
        #expect(SearchTextNormalizer.normalize("阿莫西林,胶囊") == "阿莫西林胶囊")
        #expect(SearchTextNormalizer.normalize("500mg。每日三次！") == "500mg每日三次")
        #expect(SearchTextNormalizer.normalize("注意：饭后服用。") == "注意饭后服用")
    }

    @Test("分词应该按空格分割")
    func tokenize_splitsOnWhitespace() {
        let tokens = SearchTextNormalizer.tokenize("阿莫西林 胶囊")
        #expect(tokens == ["阿莫西林", "胶囊"])
    }

    @Test("分词应该过滤空词")
    func tokenize_filtersEmptyTokens() {
        let tokens = SearchTextNormalizer.tokenize("  阿莫西林   胶囊  ")
        #expect(tokens == ["阿莫西林", "胶囊"])
    }

    @Test("分词应该处理单个词")
    func tokenize_singleToken() {
        let tokens = SearchTextNormalizer.tokenize("阿莫西林")
        #expect(tokens == ["阿莫西林"])
    }

    @Test("分词应该处理空字符串")
    func tokenize_emptyString() {
        let tokens = SearchTextNormalizer.tokenize("")
        #expect(tokens.isEmpty)
    }

    @Test("匹配应该支持中文子串")
    func matches_chineseSubstring() {
        #expect(SearchTextNormalizer.matches(query: ["阿莫"], in: "阿莫西林胶囊"))
        #expect(SearchTextNormalizer.matches(query: ["西林"], in: "阿莫西林胶囊"))
        #expect(!SearchTextNormalizer.matches(query: ["青霉素"], in: "阿莫西林胶囊"))
    }

    @Test("匹配应该不区分大小写（英文）")
    func matches_englishCaseInsensitive() {
        #expect(SearchTextNormalizer.matches(query: ["amox"], in: "amoxicillin"))
        #expect(SearchTextNormalizer.matches(query: ["AMOX"], in: "amoxicillin"))
        #expect(SearchTextNormalizer.matches(query: ["Amox"], in: "AMOXICILLIN"))
    }

    @Test("匹配应该要求所有词都命中")
    func matches_multipleTokensAllRequired() {
        #expect(SearchTextNormalizer.matches(query: ["阿莫", "胶囊"], in: "阿莫西林胶囊"))
        #expect(!SearchTextNormalizer.matches(query: ["阿莫", "片剂"], in: "阿莫西林胶囊"))
    }

    @Test("匹配应该支持混合中英文数字")
    func matches_mixedChineseEnglishNumber() {
        let text = "阿莫西林 amoxicillin 500mg 胶囊"
        #expect(SearchTextNormalizer.matches(query: ["阿莫", "500"], in: text))
        #expect(SearchTextNormalizer.matches(query: ["amox", "胶囊"], in: text))
        #expect(SearchTextNormalizer.matches(query: ["500", "mg"], in: text))
    }

    @Test("匹配应该处理空查询（匹配所有）")
    func matches_emptyQueryMatchesAll() {
        #expect(SearchTextNormalizer.matches(query: [], in: "任意文本"))
        #expect(SearchTextNormalizer.matches(query: [], in: ""))
    }

    @Test("规范化应该处理复杂场景")
    func normalize_complexScenario() {
        let input = "  阿莫西林，Amoxicillin！５００ｍｇ。  "
        let result = SearchTextNormalizer.normalize(input)
        #expect(result == "阿莫西林amoxicillin500mg")
    }

    @Test("端到端：规范化查询并匹配")
    func endToEnd_normalizeAndMatch() {
        let searchableText = SearchTextNormalizer.normalize("阿莫西林胶囊 Amoxicillin Capsules 500mg")
        let query = SearchTextNormalizer.tokenize("阿莫 500")
        #expect(SearchTextNormalizer.matches(query: query, in: searchableText))
    }

    @Test("端到端：全角查询匹配半角内容")
    func endToEnd_fullwidthQueryMatchesHalfwidth() {
        let searchableText = SearchTextNormalizer.normalize("500mg")
        let query = SearchTextNormalizer.tokenize("５００")
        #expect(SearchTextNormalizer.matches(query: query, in: searchableText))
    }
}
