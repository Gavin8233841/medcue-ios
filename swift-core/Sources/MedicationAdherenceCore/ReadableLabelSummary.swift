import Foundation

public enum ReadableLabelSectionKind: String, Codable, Sendable, Equatable {
    case warnings
    case directions
    case uses
    case interactions
    case adverseReactions
    case other

    public init(sourceTitle title: String) {
        let lowerTitle = title.lowercased()
        if lowerTitle.contains("warning")
            || lowerTitle.contains("do not use")
            || lowerTitle.contains("警示")
            || lowerTitle.contains("禁忌") {
            self = .warnings
        } else if lowerTitle.contains("dosage")
            || lowerTitle.contains("directions")
            || lowerTitle.contains("用法") {
            self = .directions
        } else if lowerTitle.contains("interaction") || lowerTitle.contains("相互作用") {
            self = .interactions
        } else if lowerTitle.contains("adverse") || lowerTitle.contains("不良反应") {
            self = .adverseReactions
        } else if lowerTitle.contains("use")
            || lowerTitle.contains("用途")
            || lowerTitle.contains("适应症") {
            self = .uses
        } else {
            self = .other
        }
    }
}

public struct ReadableLabelCard: Codable, Identifiable, Sendable, Equatable {
    public var id: String
    public var kind: ReadableLabelSectionKind
    public var heading: String
    public var plainLanguageNote: String
    public var sourceTitle: String
    public var sourceExcerpt: String

    public init(
        id: String,
        kind: ReadableLabelSectionKind,
        heading: String,
        plainLanguageNote: String,
        sourceTitle: String,
        sourceExcerpt: String
    ) {
        self.id = id
        self.kind = kind
        self.heading = heading
        self.plainLanguageNote = plainLanguageNote
        self.sourceTitle = sourceTitle
        self.sourceExcerpt = sourceExcerpt
    }
}

public struct ReadableLabelSummary: Codable, Sendable, Equatable {
    public var medicationName: String
    public var source: DrugLabelSource
    public var sourceURL: URL?
    public var cards: [ReadableLabelCard]
    public var safetyNote: String

    public init(
        medicationName: String,
        source: DrugLabelSource,
        sourceURL: URL? = nil,
        cards: [ReadableLabelCard],
        safetyNote: String = ReadableLabelSummaryBuilder.defaultSafetyNote
    ) {
        self.medicationName = medicationName
        self.source = source
        self.sourceURL = sourceURL
        self.cards = cards
        self.safetyNote = safetyNote
    }
}

public struct ReadableLabelSummaryBuilder: Sendable {
    public static let defaultSafetyNote = "说明书可读化只用于理解来源文本，不能替代医生或药师判断。"

    private let maxExcerptLength: Int

    public init(maxExcerptLength: Int = 280) {
        self.maxExcerptLength = maxExcerptLength
    }

    public func build(from label: MedicationLabel) -> ReadableLabelSummary {
        let cards = label.sections.enumerated().map { index, section in
            let kind = section.kind
            return ReadableLabelCard(
                id: "label-section-\(index)",
                kind: kind,
                heading: heading(for: kind, sourceTitle: section.title),
                plainLanguageNote: note(for: kind),
                sourceTitle: section.title,
                sourceExcerpt: excerpt(from: section.text)
            )
        }

        return ReadableLabelSummary(
            medicationName: label.name,
            source: label.source,
            sourceURL: label.sourceURL,
            cards: cards
        )
    }

    private func heading(for kind: ReadableLabelSectionKind, sourceTitle: String) -> String {
        switch kind {
        case .warnings:
            "需要重点查看"
        case .directions:
            "用法信息"
        case .uses:
            "适用说明"
        case .interactions:
            "相互作用信息"
        case .adverseReactions:
            "不良反应信息"
        case .other:
            sourceTitle
        }
    }

    private func note(for kind: ReadableLabelSectionKind) -> String {
        switch kind {
        case .warnings:
            "这里包含说明书中的警示、禁忌或停止使用提示，请按来源原文核对，并咨询医生或药师。"
        case .directions:
            "这里包含说明书中的用法信息；提醒计划必须由用户按说明书、医生或药师指导确认。"
        case .uses:
            "这里帮助理解说明书描述的用途，不代表 App 判断该药适合你。"
        case .interactions:
            "这里包含说明书中的相互作用相关信息，请带着当前用药清单咨询医生或药师。"
        case .adverseReactions:
            "这里包含说明书中的不良反应描述；若出现不适，应咨询医生或药师。"
        case .other:
            "这里保留说明书原文片段，用于用户自行核对。"
        }
    }

    private func excerpt(from text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > maxExcerptLength else {
            return trimmed
        }
        return String(trimmed.prefix(maxExcerptLength))
    }
}
