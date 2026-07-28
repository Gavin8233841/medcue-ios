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

    public var kind: ReadableLabelSectionKind {
        ReadableLabelSectionKind(sourceTitle: title)
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

    private struct LineSegment {
        var heading: String?
        var text: String
    }

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
            for segment in lineSegments(from: line) {
                if let heading = segment.heading {
                    if !currentLines.isEmpty {
                        sections.append(DrugLabelSection(title: currentTitle, text: currentLines.joined(separator: "\n")))
                        currentLines = []
                    }
                    currentTitle = heading
                }

                let text = segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty {
                    currentLines.append(text)
                }
            }
        }

        if !currentLines.isEmpty {
            sections.append(DrugLabelSection(title: currentTitle, text: currentLines.joined(separator: "\n")))
        }
        return sections
    }

    private func lineSegments(from line: String) -> [LineSegment] {
        let bracketedSegments = bracketedHeadingSegments(from: line)
        if !bracketedSegments.isEmpty {
            return bracketedSegments
        }

        if let heading = normalizedHeading(from: line) {
            return [LineSegment(heading: heading, text: "")]
        }

        if let headingSegment = colonHeadingSegment(from: line) {
            return [headingSegment]
        }

        return [LineSegment(heading: nil, text: line)]
    }

    private func bracketedHeadingSegments(from line: String) -> [LineSegment] {
        let matches = bracketedHeadingMatches(in: line)
        guard !matches.isEmpty else {
            return []
        }

        var segments: [LineSegment] = []
        var cursor = line.startIndex

        for index in matches.indices {
            let match = matches[index]
            let prefix = line[cursor..<match.range.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
            if !prefix.isEmpty {
                segments.append(LineSegment(heading: nil, text: String(prefix)))
            }

            let contentStart = match.range.upperBound
            let contentEnd = matches.indices.contains(index + 1) ? matches[index + 1].range.lowerBound : line.endIndex
            let content = line[contentStart..<contentEnd].trimmingCharacters(in: .whitespacesAndNewlines)
            segments.append(LineSegment(heading: match.title, text: String(content)))
            cursor = contentEnd
        }

        return segments
    }

    private func bracketedHeadingMatches(in line: String) -> [(range: Range<String.Index>, title: String)] {
        let matches = bracketedHeadingMatches(in: line, opening: "【", closing: "】")
            + bracketedHeadingMatches(in: line, opening: "[", closing: "]")
        return matches.sorted { lhs, rhs in
            line.distance(from: line.startIndex, to: lhs.range.lowerBound) < line.distance(from: line.startIndex, to: rhs.range.lowerBound)
        }
    }

    private func bracketedHeadingMatches(
        in line: String,
        opening: String,
        closing: String
    ) -> [(range: Range<String.Index>, title: String)] {
        var matches: [(range: Range<String.Index>, title: String)] = []
        var searchStart = line.startIndex

        while searchStart < line.endIndex,
              let openingRange = line[searchStart...].range(of: opening),
              let closingRange = line[openingRange.upperBound...].range(of: closing) {
            let rawHeading = String(line[openingRange.upperBound..<closingRange.lowerBound])
            if let heading = normalizedHeading(from: rawHeading) {
                matches.append((range: openingRange.lowerBound..<closingRange.upperBound, title: heading))
            }
            searchStart = closingRange.upperBound
        }

        return matches
    }

    private func colonHeadingSegment(from line: String) -> LineSegment? {
        let separatorRanges = ["：", ":"].compactMap { separator in
            line.range(of: separator)
        }
        guard let separatorRange = separatorRanges.min(by: { lhs, rhs in
            line.distance(from: line.startIndex, to: lhs.lowerBound) < line.distance(from: line.startIndex, to: rhs.lowerBound)
        }) else {
            return nil
        }

        let rawHeading = String(line[line.startIndex..<separatorRange.lowerBound])
        guard let heading = normalizedHeading(from: rawHeading) else {
            return nil
        }

        let text = String(line[separatorRange.upperBound..<line.endIndex])
        return LineSegment(heading: heading, text: text)
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
            ("药品名称", "药品名称"),
            ("成份", "成份"),
            ("成分", "成份"),
            ("性状", "性状"),
            ("适应症", "适应症"),
            ("功能主治", "功能主治"),
            ("规格", "规格"),
            ("用法用量", "用法用量"),
            ("禁忌", "禁忌"),
            ("警示", "警示"),
            ("注意事项", "注意事项"),
            ("特殊人群用药", "特殊人群用药"),
            ("孕妇及哺乳期妇女用药", "孕妇及哺乳期妇女用药"),
            ("孕妇及哺乳期用药", "孕妇及哺乳期妇女用药"),
            ("孕妇用药", "孕妇及哺乳期妇女用药"),
            ("哺乳期妇女用药", "孕妇及哺乳期妇女用药"),
            ("哺乳期用药", "孕妇及哺乳期妇女用药"),
            ("儿童用药", "儿童用药"),
            ("小儿用药", "儿童用药"),
            ("老年用药", "老年用药"),
            ("老年患者用药", "老年用药"),
            ("药物相互作用", "药物相互作用"),
            ("相互作用", "药物相互作用"),
            ("不良反应", "不良反应"),
            ("副作用", "不良反应"),
            ("贮藏", "贮藏"),
            ("有效期", "有效期"),
            ("warnings", "Warnings"),
            ("contraindications", "Contraindications"),
            ("drug interactions", "Drug Interactions"),
            ("interactions", "Interactions"),
            ("adverse reactions", "Adverse Reactions"),
            ("directions", "Directions"),
            ("dosage", "Dosage And Administration"),
            ("pregnancy", "Pregnancy And Lactation"),
            ("pregnancy and lactation", "Pregnancy And Lactation"),
            ("breastfeeding", "Pregnancy And Lactation"),
            ("pediatric use", "Pediatric Use"),
            ("children", "Pediatric Use"),
            ("geriatric use", "Geriatric Use"),
            ("elderly", "Geriatric Use")
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
        if lowerTitle.contains("warning")
            || lowerTitle.contains("警示")
            || lowerTitle.contains("注意事项")
            || lowerTitle.contains("特殊人群")
            || lowerTitle.contains("孕妇")
            || lowerTitle.contains("哺乳")
            || lowerTitle.contains("儿童")
            || lowerTitle.contains("老年")
            || lowerTitle.contains("pregnancy")
            || lowerTitle.contains("lactation")
            || lowerTitle.contains("breastfeeding")
            || lowerTitle.contains("pediatric")
            || lowerTitle.contains("geriatric")
            || lowerText.contains("stop use")
            || lowerText.contains("警示")
            || lowerText.contains("注意事项")
            || lowerText.contains("慎用")
            || lowerText.contains("孕妇")
            || lowerText.contains("哺乳")
            || lowerText.contains("儿童")
            || lowerText.contains("老年")
            || lowerText.contains("pregnant")
            || lowerText.contains("breastfeeding")
            || lowerText.contains("children")
            || lowerText.contains("elderly") {
            notices.append(makeNotice(kind: .generalWarning, title: "警示信息", section: section))
        }

        return notices
    }

    private func makeNotice(kind: RiskNoticeKind, title: String, section: DrugLabelSection) -> RiskNotice {
        let trimmedText = section.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let excerpt = trimmedText.count > maxExcerptLength
            ? String(trimmedText.prefix(maxExcerptLength)).trimmingCharacters(in: .whitespacesAndNewlines)
            : trimmedText
        return RiskNotice(
            kind: kind,
            title: title,
            excerpt: excerpt,
            sourceTitle: section.title
        )
    }
}
