// Adapted from the owner-authorized local CatPawAgent Markdown implementation.
import SwiftUI

// MARK: - Markdown 渲染（纯展示）

/// Markdown 正文块：通过渲染适配层复用解析结果和稳定身份。
/// 流式输出时 body 在每个 token 到达时重新求值，
/// 而解析结果只取决于文本本身，同一份文本没必要重复解析。
struct MarkdownContent: View {
    let markdown: String

    private var blocks: [IdentifiedMarkdownBlock] {
        MarkdownRenderCache.shared.blocks(for: markdown)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // 序号区分重复块，内容指纹减少流式更新中的无关重建。
            ForEach(blocks) { item in
                MarkdownBlockView(block: item.block)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .textSelection(.enabled)
    }
}

/// 单个 Markdown 块的类型分发（视觉部分）。
struct MarkdownBlockView: View {
    let block: MarkdownBlock

    var body: some View {
        switch block {
        case .heading(let level, let text):
            MarkdownInlineText(text: text, font: headingFont(for: level), color: MedCueMarkdownTheme.primaryText, lineSpacing: 6)
                .padding(.top, level <= 2 ? 4 : 0)
        case .paragraph(let text):
            MarkdownInlineText(text: text, font: .system(size: 19, weight: .regular), color: MedCueMarkdownTheme.primaryText, lineSpacing: 6)
        case .unorderedList(let items):
            MarkdownListView(items: items, ordered: false, start: 1)
        case .orderedList(let start, let items):
            MarkdownListView(items: items, ordered: true, start: start)
        case .quote(let text):
            MarkdownQuoteView(text: text)
        case .code(let language, let text):
            MarkdownCodeBlockView(language: language, code: text)
        case .table(let table):
            MarkdownTableView(table: table)
        case .divider:
            Rectangle()
                .fill(MedCueMarkdownTheme.timeline)
                .frame(height: 1)
                .padding(.vertical, 8)
        }
    }

    private func headingFont(for level: Int) -> Font {
        switch level {
        case 1:
            return .system(size: 25, weight: .semibold)
        case 2:
            return .system(size: 23, weight: .semibold)
        case 3:
            return .system(size: 21, weight: .semibold)
        default:
            return .system(size: 19, weight: .semibold)
        }
    }
}

/// 行内富文本：inline Markdown 解析失败时回退纯文本。
struct MarkdownInlineText: View {
    let text: String
    let font: Font
    let color: Color
    let lineSpacing: CGFloat
    var preservesHorizontalSpace = false

    var body: some View {
        Text(attributedText)
            .font(font)
            .foregroundStyle(color)
            .lineSpacing(lineSpacing)
            .fixedSize(horizontal: preservesHorizontalSpace, vertical: true)
    }

    private var attributedText: AttributedString {
        if let attributed = try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
            return attributed
        }
        return AttributedString(text)
    }
}

/// 有序/无序列表。
struct MarkdownListView: View {
    let items: [String]
    let ordered: Bool
    let start: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(items.indices, id: \.self) { index in
                HStack(alignment: .top, spacing: 10) {
                    Text(marker(for: index))
                        .font(.system(size: 18, weight: .regular))
                        .foregroundStyle(MedCueMarkdownTheme.primaryText.opacity(0.86))
                        .frame(width: ordered ? 42 : 22, alignment: .trailing)
                        .padding(.top, 2)

                    MarkdownInlineText(text: items[index], font: .system(size: 19, weight: .regular), color: MedCueMarkdownTheme.primaryText, lineSpacing: 6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func marker(for index: Int) -> String {
        ordered ? "\(start + index)." : "•"
    }
}

/// 引用块。
struct MarkdownQuoteView: View {
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                .fill(MedCueMarkdownTheme.timeline)
                .frame(width: 3)

            MarkdownInlineText(text: text, font: .system(size: 18, weight: .regular), color: MedCueMarkdownTheme.primaryText.opacity(0.74), lineSpacing: 6)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 2)
    }
}

/// 代码块：横向滚动的等宽文本 + 语言标签。
struct MarkdownCodeBlockView: View {
    let language: String?
    let code: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let language, !language.isEmpty {
                Text(language)
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .foregroundStyle(MedCueMarkdownTheme.tertiaryText)
                    .textCase(.uppercase)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                Text(code.isEmpty ? " " : code)
                    .font(.system(size: 16, weight: .regular, design: .monospaced))
                    .foregroundStyle(MedCueMarkdownTheme.primaryText.opacity(0.88))
                    .lineSpacing(5)
                    .fixedSize(horizontal: true, vertical: false)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(MedCueMarkdownTheme.chipFill)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(MedCueMarkdownTheme.inputStroke, lineWidth: 1)
        }
    }
}

/// 表格块：横向滚动的 Grid。
struct MarkdownTableView: View {
    let table: MarkdownTable

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 10) {
                GridRow {
                    ForEach(0..<table.columnCount, id: \.self) { column in
                        tableCell(table.cell(row: -1, column: column), isHeader: true, column: column)
                    }
                }

                Divider()
                    .overlay(MedCueMarkdownTheme.timeline)
                    .gridCellColumns(table.columnCount)

                ForEach(table.rows.indices, id: \.self) { row in
                    GridRow {
                        ForEach(0..<table.columnCount, id: \.self) { column in
                            tableCell(table.cell(row: row, column: column), isHeader: false, column: column)
                        }
                    }

                    if row < table.rows.count - 1 {
                        Divider()
                            .opacity(0.22)
                            .gridCellColumns(table.columnCount)
                    }
                }
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 1)
            .fixedSize(horizontal: true, vertical: false)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func tableCell(_ text: String, isHeader: Bool, column: Int) -> some View {
        MarkdownInlineText(
            text: text,
            font: .system(size: 19, weight: isHeader ? .semibold : .regular),
            color: isHeader ? MedCueMarkdownTheme.primaryText : MedCueMarkdownTheme.primaryText.opacity(0.86),
            lineSpacing: 6,
            preservesHorizontalSpace: true
        )
        .frame(minWidth: column == 0 ? 86 : 170, alignment: .leading)
    }
}

private enum MedCueMarkdownTheme {
    static let primaryText = Color.primary
    static let secondaryText = Color.secondary
    static let tertiaryText = Color.secondary
    static let timeline = Color.primary.opacity(0.12)
    static let chipFill = Color.primary.opacity(0.04)
    static let inputStroke = Color.primary.opacity(0.10)
}
