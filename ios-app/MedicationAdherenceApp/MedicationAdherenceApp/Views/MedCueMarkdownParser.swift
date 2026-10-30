// Adapted from the owner-authorized local CatPawAgent Markdown implementation.
//
//  MarkdownParser.swift
//  CatPawAgent
//
//  纯块级 Markdown 解析。行内格式（粗体/斜体/链接/行内代码）不在这里处理，
//  由 Foundation 的 AttributedString(markdown:) 在渲染层完成。
//

import Foundation

enum MarkdownBlock {
    case heading(level: Int, text: String)
    case paragraph(String)
    case unorderedList([String])
    case orderedList(start: Int, items: [String])
    case quote(String)
    case code(language: String?, text: String)
    case table(MarkdownTable)
    case divider
}

struct MarkdownTable {
    let headers: [String]
    let rows: [[String]]

    var columnCount: Int {
        max(headers.count, rows.map(\.count).max() ?? 0, 1)
    }

    func cell(row: Int, column: Int) -> String {
        if row == -1 {
            return column < headers.count ? headers[column] : ""
        }
        guard row < rows.count, column < rows[row].count else {
            return ""
        }
        return rows[row][column]
    }
}

struct ListMarker {
    let ordered: Bool
    let number: Int
    let text: String
    let indent: Int
}

enum MarkdownParser {
    static func parse(_ source: String) -> [MarkdownBlock] {
        let lines = source
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")
        var index = 0
        var blocks: [MarkdownBlock] = []

        while index < lines.count {
            let line = lines[index]
            let trimmed = line.markdownTrimmed

            if trimmed.isEmpty {
                index += 1
                continue
            }

            if let marker = fenceMarker(in: line) {
                blocks.append(parseCodeBlock(lines: lines, index: &index, marker: marker))
                continue
            }

            if let heading = heading(in: line) {
                blocks.append(.heading(level: heading.level, text: heading.text))
                index += 1
                continue
            }

            if isDivider(line) {
                blocks.append(.divider)
                index += 1
                continue
            }

            if isTableStart(lines: lines, index: index) {
                blocks.append(parseTable(lines: lines, index: &index))
                continue
            }

            if trimmed.hasPrefix(">") {
                blocks.append(parseQuote(lines: lines, index: &index))
                continue
            }

            if let marker = listMarker(in: line) {
                blocks.append(parseList(lines: lines, index: &index, firstMarker: marker))
                continue
            }

            blocks.append(parseParagraph(lines: lines, index: &index))
        }

        return blocks
    }

    private static func parseCodeBlock(lines: [String], index: inout Int, marker: String) -> MarkdownBlock {
        let opening = lines[index].markdownTrimmed
        let language = String(opening.dropFirst(marker.count)).markdownTrimmed.nilIfEmpty
        index += 1

        var codeLines: [String] = []
        while index < lines.count {
            let line = lines[index]
            if line.markdownTrimmed.hasPrefix(marker) {
                index += 1
                break
            }
            codeLines.append(line)
            index += 1
        }

        return .code(language: language, text: codeLines.joined(separator: "\n"))
    }

    private static func parseQuote(lines: [String], index: inout Int) -> MarkdownBlock {
        var quoteLines: [String] = []

        while index < lines.count {
            let trimmed = lines[index].markdownTrimmed
            guard trimmed.hasPrefix(">") else {
                break
            }
            var text = String(trimmed.dropFirst())
            if text.first?.isWhitespace == true {
                text.removeFirst()
            }
            quoteLines.append(text)
            index += 1
        }

        return .quote(quoteLines.joined(separator: "\n"))
    }

    private static func parseList(lines: [String], index: inout Int, firstMarker: ListMarker) -> MarkdownBlock {
        var items: [String] = []
        var current: String?
        let ordered = firstMarker.ordered
        let start = firstMarker.number
        let baseIndent = firstMarker.indent

        while index < lines.count {
            let line = lines[index]
            if line.markdownTrimmed.isEmpty {
                index += 1
                break
            }

            if let marker = listMarker(in: line), marker.ordered == ordered {
                if let current {
                    items.append(current)
                }
                current = marker.text
                index += 1
                continue
            }

            if current != nil, leadingWhitespaceCount(in: line) > baseIndent {
                current?.append("\n")
                current?.append(line.markdownTrimmed)
                index += 1
                continue
            }

            break
        }

        if let current {
            items.append(current)
        }

        if ordered {
            return .orderedList(start: start, items: items)
        }
        return .unorderedList(items)
    }

    private static func parseTable(lines: [String], index: inout Int) -> MarkdownBlock {
        let headers = splitTableRow(lines[index])
        index += 2

        var rows: [[String]] = []
        while index < lines.count {
            let line = lines[index]
            guard line.contains("|"), !line.markdownTrimmed.isEmpty else {
                break
            }
            rows.append(splitTableRow(line))
            index += 1
        }

        return .table(MarkdownTable(headers: headers, rows: rows))
    }

    private static func parseParagraph(lines: [String], index: inout Int) -> MarkdownBlock {
        var paragraphLines: [String] = []

        while index < lines.count {
            let line = lines[index]
            guard !line.markdownTrimmed.isEmpty else {
                break
            }
            guard !isSpecialBlockStart(lines: lines, index: index) else {
                break
            }
            paragraphLines.append(line.markdownTrimmed)
            index += 1
        }

        return .paragraph(paragraphLines.joined(separator: " "))
    }

    private static func isSpecialBlockStart(lines: [String], index: Int) -> Bool {
        let line = lines[index]
        let trimmed = line.markdownTrimmed
        return fenceMarker(in: line) != nil
            || heading(in: line) != nil
            || isDivider(line)
            || trimmed.hasPrefix(">")
            || listMarker(in: line) != nil
            || isTableStart(lines: lines, index: index)
    }

    private static func fenceMarker(in line: String) -> String? {
        let trimmed = line.markdownTrimmed
        if trimmed.hasPrefix("```") {
            return "```"
        }
        if trimmed.hasPrefix("~~~") {
            return "~~~"
        }
        return nil
    }

    private static func heading(in line: String) -> (level: Int, text: String)? {
        let trimmed = line.markdownTrimmed
        let level = trimmed.prefix { $0 == "#" }.count
        guard (1...6).contains(level) else {
            return nil
        }
        let rest = trimmed.dropFirst(level)
        guard rest.first?.isWhitespace == true else {
            return nil
        }
        return (level, String(rest).markdownTrimmed)
    }

    private static func isDivider(_ line: String) -> Bool {
        let trimmed = line.markdownTrimmed
        guard trimmed.count >= 3 else {
            return false
        }
        let characters = Set(trimmed)
        return characters == ["-"] || characters == ["*"] || characters == ["_"]
    }

    private static func isTableStart(lines: [String], index: Int) -> Bool {
        guard index + 1 < lines.count, lines[index].contains("|") else {
            return false
        }
        let headers = splitTableRow(lines[index])
        return headers.count >= 2 && isTableSeparator(lines[index + 1])
    }

    private static func isTableSeparator(_ line: String) -> Bool {
        let cells = splitTableRow(line)
        guard cells.count >= 2 else {
            return false
        }
        return cells.allSatisfy { cell in
            let trimmed = cell.markdownTrimmed
            let hyphenCount = trimmed.filter { $0 == "-" }.count
            guard hyphenCount >= 3 else {
                return false
            }
            return trimmed.allSatisfy { $0 == "-" || $0 == ":" }
        }
    }

    private static func splitTableRow(_ line: String) -> [String] {
        var trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("|") {
            trimmed.removeFirst()
        }
        if trimmed.hasSuffix("|") {
            trimmed.removeLast()
        }
        return trimmed.split(separator: "|", omittingEmptySubsequences: false).map {
            String($0).markdownTrimmed
        }
    }

    private static func listMarker(in line: String) -> ListMarker? {
        let indent = leadingWhitespaceCount(in: line)
        let trimmed = String(line.dropFirst(min(indent, line.count)))
        guard !trimmed.isEmpty else {
            return nil
        }

        if let first = trimmed.first, ["-", "*", "+"].contains(first) {
            let rest = trimmed.dropFirst()
            guard rest.first?.isWhitespace == true else {
                return nil
            }
            return ListMarker(ordered: false, number: 1, text: String(rest).markdownTrimmed, indent: indent)
        }

        var digits = ""
        var cursor = trimmed.startIndex
        while cursor < trimmed.endIndex, trimmed[cursor].isNumber {
            digits.append(trimmed[cursor])
            cursor = trimmed.index(after: cursor)
        }

        guard !digits.isEmpty, cursor < trimmed.endIndex, trimmed[cursor] == "." || trimmed[cursor] == ")" else {
            return nil
        }

        let punctuation = cursor
        cursor = trimmed.index(after: cursor)
        guard cursor < trimmed.endIndex, trimmed[cursor].isWhitespace else {
            return nil
        }

        let number = Int(digits) ?? 1
        let textStart = trimmed.index(after: punctuation)
        return ListMarker(ordered: true, number: number, text: String(trimmed[textStart...]).markdownTrimmed, indent: indent)
    }

    private static func leadingWhitespaceCount(in line: String) -> Int {
        var count = 0
        for character in line {
            if character == " " {
                count += 1
            } else if character == "\t" {
                count += 4
            } else {
                break
            }
        }
        return count
    }
}

extension String {
    var markdownTrimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
