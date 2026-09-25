import Foundation

/// 搜索文本规范化工具，用于统一搜索查询和可搜索内容的格式
enum SearchTextNormalizer {
    /// 规范化单个字符串：统一大小写、全半角、可忽略标点和空白
    static func normalize(_ text: String) -> String {
        var result = text
        result = result.lowercased()
        result = convertFullwidthToHalfwidth(result)
        result = replaceIgnorablePunctuationWithWhitespace(result)
        return result.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }

    /// 将查询字符串按空格分割为非空词
    static func tokenize(_ query: String) -> [String] {
        let normalized = normalize(query)
        return normalized.split(whereSeparator: { $0.isWhitespace }).map(String.init)
    }

    /// 检查所有查询词是否都能在目标文本中找到（子串匹配）
    static func matches(query: [String], in text: String) -> Bool {
        let normalizedQuery = query.flatMap(tokenize)
        guard !normalizedQuery.isEmpty else {
            return true
        }
        let normalizedText = normalize(text)
        let compactText = removingSeparators(from: normalizedText)
        return normalizedQuery.allSatisfy { token in
            normalizedText.contains(token)
                || compactText.contains(removingSeparators(from: token))
        }
    }

    private static func convertFullwidthToHalfwidth(_ text: String) -> String {
        var result = ""
        for char in text {
            let scalar = char.unicodeScalars.first
            if scalar?.value == 0x3000 {
                result.append(" ")
                continue
            }
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

    private static func replaceIgnorablePunctuationWithWhitespace(_ text: String) -> String {
        String(text.map { character in
            character.unicodeScalars.allSatisfy(CharacterSet.punctuationCharacters.contains)
                ? " "
                : character
        })
    }

    private static func removingSeparators(from text: String) -> String {
        text.filter { !$0.isWhitespace }
    }
}
