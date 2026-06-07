import Foundation

public enum DrugLabelSource: String, Codable, Sendable, Equatable {
    case demo
    case openFDA
    case rxNorm
    case rxClass
    case dailyMed
    case userProvided
}

public struct DrugLabelSection: Codable, Sendable, Equatable {
    public var title: String
    public var text: String

    public init(title: String, text: String) {
        self.title = title
        self.text = text
    }
}

public struct MedicationLabel: Codable, Sendable, Equatable {
    public var name: String
    public var source: DrugLabelSource
    public var sourceURL: URL?
    public var lastReviewed: Date?
    public var sections: [DrugLabelSection]

    public init(
        name: String,
        source: DrugLabelSource,
        sourceURL: URL? = nil,
        lastReviewed: Date? = nil,
        sections: [DrugLabelSection]
    ) {
        self.name = name
        self.source = source
        self.sourceURL = sourceURL
        self.lastReviewed = lastReviewed
        self.sections = sections
    }
}

public struct UserProvidedLabelBuilder: Sendable {
    public init() {}

    public func build(
        medicationName: String,
        rawText: String,
        reviewedAt: Date = Date()
    ) -> MedicationLabel? {
        let normalizedLines = rawText
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        let meaningfulLines = normalizedLines.filter { !$0.isEmpty }
        guard !meaningfulLines.isEmpty else {
            return nil
        }

        let sections = splitSections(from: meaningfulLines)
        return MedicationLabel(
            name: medicationName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "用户导入说明书" : medicationName,
            source: .userProvided,
            lastReviewed: reviewedAt,
            sections: sections.isEmpty ? [DrugLabelSection(title: "用户导入说明书", text: meaningfulLines.joined(separator: "\n"))] : sections
        )
    }

    private func splitSections(from lines: [String]) -> [DrugLabelSection] {
        var sections: [DrugLabelSection] = []
        var currentTitle = "用户导入说明书"
        var currentLines: [String] = []

        for line in lines {
            if let heading = normalizedHeading(from: line) {
                if !currentLines.isEmpty {
                    sections.append(DrugLabelSection(title: currentTitle, text: currentLines.joined(separator: "\n")))
                    currentLines = []
                }
                currentTitle = heading
            } else {
                currentLines.append(line)
            }
        }

        if !currentLines.isEmpty {
            sections.append(DrugLabelSection(title: currentTitle, text: currentLines.joined(separator: "\n")))
        }
        return sections
    }

    private func normalizedHeading(from line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count <= 30 else {
            return nil
        }
        let normalized = trimmed
            .trimmingCharacters(in: CharacterSet(charactersIn: "【】[]（）():： "))
            .lowercased()
        let headings: [(String, String)] = [
            ("禁忌", "禁忌"),
            ("警示", "警示"),
            ("注意事项", "注意事项"),
            ("相互作用", "药物相互作用"),
            ("药物相互作用", "药物相互作用"),
            ("不良反应", "不良反应"),
            ("用法用量", "用法用量"),
            ("适应症", "适应症"),
            ("warnings", "Warnings"),
            ("contraindications", "Contraindications"),
            ("drug interactions", "Drug Interactions"),
            ("interactions", "Interactions"),
            ("adverse reactions", "Adverse Reactions"),
            ("directions", "Directions"),
            ("dosage", "Dosage And Administration")
        ]
        return headings.first { key, _ in normalized == key || normalized.contains(key) }?.1
    }
}

public enum RiskNoticeKind: String, Codable, Sendable, Equatable {
    case contraindication
    case interaction
    case foodWarning
    case adverseReaction
    case generalWarning
}

public struct RiskNotice: Codable, Sendable, Equatable {
    public var kind: RiskNoticeKind
    public var title: String
    public var excerpt: String
    public var sourceTitle: String

    public init(kind: RiskNoticeKind, title: String, excerpt: String, sourceTitle: String) {
        self.kind = kind
        self.title = title
        self.excerpt = excerpt
        self.sourceTitle = sourceTitle
    }
}

public struct RiskTextExtractor: Sendable {
    private let maxExcerptLength: Int

    public init(maxExcerptLength: Int = 240) {
        self.maxExcerptLength = maxExcerptLength
    }

    public func extract(from label: MedicationLabel) -> [RiskNotice] {
        label.sections.flatMap { section in
            notices(from: section)
        }
    }

    private func notices(from section: DrugLabelSection) -> [RiskNotice] {
        let lowerTitle = section.title.lowercased()
        let lowerText = section.text.lowercased()
        var notices: [RiskNotice] = []

        if lowerTitle.contains("contraindication") || lowerTitle.contains("禁忌") || lowerText.contains("do not use") || lowerText.contains("禁忌") || lowerText.contains("禁用") {
            notices.append(makeNotice(kind: .contraindication, title: "禁忌或不得使用", section: section))
        }
        if lowerTitle.contains("interaction") || lowerTitle.contains("相互作用") || lowerText.contains("ask a doctor or pharmacist") || lowerText.contains("相互作用") || lowerText.contains("合用") || lowerText.contains("同用") {
            notices.append(makeNotice(kind: .interaction, title: "相互作用或需咨询药师", section: section))
        }
        if lowerText.contains("alcohol") || lowerText.contains("grapefruit") || lowerText.contains("food") || lowerText.contains("饮酒") || lowerText.contains("酒精") || lowerText.contains("葡萄柚") || lowerText.contains("食物") || lowerText.contains("饮食") {
            notices.append(makeNotice(kind: .foodWarning, title: "饮食注意", section: section))
        }
        if lowerTitle.contains("adverse") || lowerTitle.contains("不良反应") || lowerTitle.contains("副作用") || lowerText.contains("side effect") || lowerText.contains("不良反应") || lowerText.contains("副作用") {
            notices.append(makeNotice(kind: .adverseReaction, title: "不良反应", section: section))
        }
        if lowerTitle.contains("warning") || lowerTitle.contains("警示") || lowerTitle.contains("注意事项") || lowerText.contains("stop use") || lowerText.contains("警示") || lowerText.contains("注意事项") || lowerText.contains("慎用") {
            notices.append(makeNotice(kind: .generalWarning, title: "警示信息", section: section))
        }

        return notices
    }

    private func makeNotice(kind: RiskNoticeKind, title: String, section: DrugLabelSection) -> RiskNotice {
        RiskNotice(
            kind: kind,
            title: title,
            excerpt: String(section.text.prefix(maxExcerptLength)),
            sourceTitle: section.title
        )
    }
}
