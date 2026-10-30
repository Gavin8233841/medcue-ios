// Adapted from the owner-authorized local CatPawAgent Markdown implementation.
import Foundation

/// 供 SwiftUI `ForEach` 使用的 Markdown 块。
///
/// ID 由「序号 + 块类型 + 内容指纹」组成。序号区分内容相同的重复块，
/// 内容指纹减少流式尾部增长时无关块的重建；本类型只属于渲染适配层。
struct IdentifiedMarkdownBlock: Identifiable {
    let id: String
    let block: MarkdownBlock
}

/// Markdown 渲染适配缓存。
///
/// 块级语法由 `MarkdownParser` 纯解析；本类型只负责复用流式渲染结果，
/// 并为每个块生成 SwiftUI diff 所需的身份。
@MainActor
final class MarkdownRenderCache {
    static let shared = MarkdownRenderCache()

    private var storage: [String: [MarkdownBlock]] = [:]
    private var order: [String] = []
    private let limit = 48

    private init() {}

    func blocks(for source: String) -> [IdentifiedMarkdownBlock] {
        parsedBlocks(for: source).enumerated().map { index, block in
            IdentifiedMarkdownBlock(
                id: "\(index)-\(block.identityFingerprint)",
                block: block
            )
        }
    }

    private func parsedBlocks(for source: String) -> [MarkdownBlock] {
        if let hit = storage[source] {
            return hit
        }

        let parsed = MarkdownParser.parse(source)
        storage[source] = parsed
        order.append(source)

        // 流式过程中每个 token 都会产生一个新 key，必须限制容量。
        if order.count > limit {
            let overflow = order.count - limit
            for key in order.prefix(overflow) {
                storage.removeValue(forKey: key)
            }
            order.removeFirst(overflow)
        }

        return parsed
    }
}

extension MarkdownBlock {
    /// 用于构造渲染身份的内容指纹。
    ///
    /// 只取块类型 + 少量内容特征，避免为长代码块反复计算整串哈希。
    fileprivate var identityFingerprint: String {
        switch self {
        case .heading(let level, let text):
            return "h\(level)-\(text.count)-\(text.prefix(24).hashValue)"
        case .paragraph(let text):
            return "p-\(text.count)-\(text.prefix(24).hashValue)"
        case .unorderedList(let items):
            return "ul-\(items.count)-\(items.first?.prefix(16).hashValue ?? 0)"
        case .orderedList(let start, let items):
            return "ol\(start)-\(items.count)-\(items.first?.prefix(16).hashValue ?? 0)"
        case .quote(let text):
            return "q-\(text.count)-\(text.prefix(24).hashValue)"
        case .code(let language, let text):
            // 语言标识在流式中会逐字符增长（s -> sw -> swift），
            // 不纳入指纹，避免代码块反复换身份。
            _ = language
            return "code-\(text.count)"
        case .table(let table):
            return "tbl-\(table.columnCount)x\(table.rows.count)"
        case .divider:
            return "hr"
        }
    }
}
