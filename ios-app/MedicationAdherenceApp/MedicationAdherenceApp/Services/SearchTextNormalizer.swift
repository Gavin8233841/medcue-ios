import Foundation

/// 搜索文本规范化工具，用于统一搜索查询和可搜索内容的格式
enum SearchTextNormalizer {
    /// 规范化单个字符串：去除前后空白、统一大小写、全角转半角、去除可忽略标点
    static func normalize(_ text: String) -> String {
        var result = text.trimmingCharacters(in: .whitespacesAndNewlines)
        result = result.lowercased()
        result = convertFullwidthToHalfwidth(result)
        result = removeIgnorablePunctuation(result)
        return result
    }

    /// 将查询字符串按空格分割为非空词
    static func tokenize(_ query: String) -> [String] {
        let normalized = normalize(query)
        return normalized.split(separator: " ").map(String.init).filter { !$0.isEmpty }
    }

    /// 检查所有查询词是否都能在目标文本中找到（子串匹配）
    static func matches(query: [String], in text: String) -> Bool {
        guard !query.isEmpty else {
            return true
        }
        return query.allSatisfy { text.contains($0) }
    }

    private static func convertFullwidthToHalfwidth(_ text: String) -> String {
        var result = ""
        for char in text {
            let scalar = char.unicodeScalars.first
            if let scalar = scalar, (0xFF01...0xFF5E).contains(scalar.value) {
                let halfwidthValue = scalar.value - 0xFEE0
                if let halfwidthScalar = UnicodeScalar(halfwidthValue) {
                    result.append(Character(halfwidthScalar))
                    continue
                }
            }
            result.append(char)
        }
        return result
    }

    private static func removeIgnorablePunctuation(_ text: String) -> String {
        let ignorable: Set<Character> = [".", ",", "、", "。", "，", "!", "！", "?", "？", ";", "；", ":", "："]
        return text.filter { !ignorable.contains($0) }
    }
}
