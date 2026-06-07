import Foundation

public enum RiskAssessmentCardKind: String, Codable, Sendable, Equatable {
    case labelRisk
    case healthConditionReview
    case foodReview
    case drugClassContext
    case medicationSourceReview
}

public struct UserRiskContextEntry: Codable, Sendable, Equatable {
    public var name: String
    public var note: String

    public init(name: String, note: String = "") {
        self.name = name
        self.note = note
    }
}

public struct RiskAssessmentEvidence: Codable, Sendable, Equatable {
    public var sourceTitle: String
    public var excerpt: String
    public var source: DrugLabelSource?
    public var sourceURL: URL?

    public init(
        sourceTitle: String,
        excerpt: String,
        source: DrugLabelSource? = nil,
        sourceURL: URL? = nil
    ) {
        self.sourceTitle = sourceTitle
        self.excerpt = excerpt
        self.source = source
        self.sourceURL = sourceURL
    }
}

public struct RiskAssessmentCard: Codable, Identifiable, Sendable, Equatable {
    public var id: String
    public var kind: RiskAssessmentCardKind
    public var displayPriority: Int
    public var title: String
    public var message: String
    public var evidence: RiskAssessmentEvidence?
    public var requiresProfessionalReview: Bool
    public var safetyNote: String

    public init(
        id: String,
        kind: RiskAssessmentCardKind,
        displayPriority: Int,
        title: String,
        message: String,
        evidence: RiskAssessmentEvidence? = nil,
        requiresProfessionalReview: Bool,
        safetyNote: String = RiskAssessmentEngine.defaultSafetyNote
    ) {
        self.id = id
        self.kind = kind
        self.displayPriority = displayPriority
        self.title = title
        self.message = message
        self.evidence = evidence
        self.requiresProfessionalReview = requiresProfessionalReview
        self.safetyNote = safetyNote
    }
}

public struct RiskAssessmentInput: Sendable, Equatable {
    public var medication: Medication
    public var label: MedicationLabel?
    public var drugClasses: [DrugClass]
    public var healthConditionEntries: [UserRiskContextEntry]
    public var dietaryConcernEntries: [UserRiskContextEntry]

    public init(
        medication: Medication,
        label: MedicationLabel? = nil,
        drugClasses: [DrugClass] = [],
        healthConditionEntries: [UserRiskContextEntry] = [],
        dietaryConcernEntries: [UserRiskContextEntry] = []
    ) {
        self.medication = medication
        self.label = label
        self.drugClasses = drugClasses
        self.healthConditionEntries = healthConditionEntries
        self.dietaryConcernEntries = dietaryConcernEntries
    }
}

public struct RiskAssessmentEngine: Sendable {
    public static let defaultSafetyNote = "此提示仅用于用药风险复核，不能替代医生或药师判断。"

    private let riskTextExtractor: RiskTextExtractor

    public init(riskTextExtractor: RiskTextExtractor = RiskTextExtractor()) {
        self.riskTextExtractor = riskTextExtractor
    }

    public func assess(_ input: RiskAssessmentInput) -> [RiskAssessmentCard] {
        var cards: [RiskAssessmentCard] = []

        if let label = input.label {
            cards.append(contentsOf: labelRiskCards(from: label))
            cards.append(contentsOf: reviewCards(
                entries: input.healthConditionEntries,
                label: label,
                kind: .healthConditionReview,
                titlePrefix: "病症相关复核",
                messagePrefix: "你的健康记录中有相关表述，说明书内容也出现相同表述；这只表示需要复核，不代表 App 判断该药不适合你。",
                priority: 15
            ))
            cards.append(contentsOf: reviewCards(
                entries: input.dietaryConcernEntries,
                label: label,
                kind: .foodReview,
                titlePrefix: "饮食相关复核",
                messagePrefix: "你的饮食注意记录中有相关表述，说明书内容也出现相同表述；这只表示需要复核，不代表 App 判断已经发生禁忌。",
                priority: 18
            ))
        }

        cards.append(contentsOf: sourceReviewCards(from: input.medication, label: input.label))
        cards.append(contentsOf: drugClassCards(from: input.drugClasses))

        return cards.sorted { lhs, rhs in
            if lhs.displayPriority != rhs.displayPriority {
                return lhs.displayPriority < rhs.displayPriority
            }
            if lhs.title != rhs.title {
                return lhs.title < rhs.title
            }
            return lhs.id < rhs.id
        }
    }

    private func labelRiskCards(from label: MedicationLabel) -> [RiskAssessmentCard] {
        riskTextExtractor.extract(from: label).enumerated().map { index, notice in
            RiskAssessmentCard(
                id: "label-\(notice.kind.rawValue)-\(index)",
                kind: .labelRisk,
                displayPriority: priority(for: notice.kind),
                title: notice.title,
                message: "说明书“\(notice.sourceTitle)”中提到相关风险，请按原文核对，并向医生或药师确认。",
                evidence: RiskAssessmentEvidence(
                    sourceTitle: notice.sourceTitle,
                    excerpt: notice.excerpt,
                    source: label.source,
                    sourceURL: label.sourceURL
                ),
                requiresProfessionalReview: true
            )
        }
    }

    private func reviewCards(
        entries: [UserRiskContextEntry],
        label: MedicationLabel,
        kind: RiskAssessmentCardKind,
        titlePrefix: String,
        messagePrefix: String,
        priority: Int
    ) -> [RiskAssessmentCard] {
        entries.compactMap { entry in
            guard let match = matchingSection(for: entry.name, in: label) else {
                return nil
            }
            let normalizedName = normalized(entry.name) ?? entry.name
            return RiskAssessmentCard(
                id: "\(kind.rawValue)-\(normalizedName.lowercased())",
                kind: kind,
                displayPriority: priority,
                title: "\(titlePrefix)：\(normalizedName)",
                message: "\(messagePrefix) 请带着该信息咨询医生或药师。",
                evidence: RiskAssessmentEvidence(
                    sourceTitle: match.title,
                    excerpt: excerpt(around: normalizedName, in: match.text),
                    source: label.source,
                    sourceURL: label.sourceURL
                ),
                requiresProfessionalReview: true
            )
        }
    }

    private func sourceReviewCards(from medication: Medication, label: MedicationLabel?) -> [RiskAssessmentCard] {
        var cards: [RiskAssessmentCard] = []

        switch medication.kind {
        case .prescription:
            cards.append(RiskAssessmentCard(
                id: "source-prescription",
                kind: .medicationSourceReview,
                displayPriority: 25,
                title: "处方药来源复核",
                message: "处方药应按医生处方或药师指导使用；App 只记录和提醒，不自动改变剂量、频次或疗程。",
                requiresProfessionalReview: true
            ))
        case .unknown:
            cards.append(RiskAssessmentCard(
                id: "source-unknown-kind",
                kind: .medicationSourceReview,
                displayPriority: 28,
                title: "药品类型待确认",
                message: "当前药品类型尚未确认，请先核对它是处方药、非处方药还是其他来源，再建立用药计划。",
                requiresProfessionalReview: true
            ))
        case .overTheCounter:
            break
        }

        if medication.inputSource == .prescriptionImage {
            cards.append(RiskAssessmentCard(
                id: "source-prescription-image",
                kind: .medicationSourceReview,
                displayPriority: 26,
                title: "处方识别结果待核对",
                message: "拍照或 OCR 识别结果必须按原始处方或医嘱逐项核对，确认后才能作为提醒计划依据。",
                requiresProfessionalReview: true
            ))
        }

        if label?.source == .userProvided {
            cards.append(RiskAssessmentCard(
                id: "source-user-provided-label",
                kind: .medicationSourceReview,
                displayPriority: 30,
                title: "说明书来源待核对",
                message: "当前说明书内容来自用户提供文本，请核对药品包装、说明书原件或权威来源后再用于复核。",
                requiresProfessionalReview: true
            ))
        }

        return cards
    }

    private func drugClassCards(from drugClasses: [DrugClass]) -> [RiskAssessmentCard] {
        drugClasses.compactMap { drugClass in
            guard let className = normalized(drugClass.name) else {
                return nil
            }
            let sourceText = normalized(drugClass.source).map { "，来源：\($0)" } ?? ""
            return RiskAssessmentCard(
                id: "class-\(drugClass.classID)",
                kind: .drugClassContext,
                displayPriority: 80,
                title: "药品类别信息：\(className)",
                message: "药品类别可帮助理解药品背景\(sourceText)，但本 App 不用类别信息自动判断相互作用或个体用药风险。",
                requiresProfessionalReview: false
            )
        }
    }

    private func priority(for kind: RiskNoticeKind) -> Int {
        switch kind {
        case .contraindication:
            10
        case .interaction:
            12
        case .foodWarning:
            14
        case .adverseReaction:
            20
        case .generalWarning:
            22
        }
    }

    private func matchingSection(for entryName: String, in label: MedicationLabel) -> DrugLabelSection? {
        guard let name = normalized(entryName)?.lowercased() else {
            return nil
        }
        return label.sections.first { section in
            section.text.lowercased().contains(name) || section.title.lowercased().contains(name)
        }
    }

    private func excerpt(around needle: String, in text: String, maxLength: Int = 240) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > maxLength else {
            return trimmed
        }
        guard let range = trimmed.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive]) else {
            return String(trimmed.prefix(maxLength))
        }

        let halfLength = maxLength / 2
        let distanceToMatch = trimmed.distance(from: trimmed.startIndex, to: range.lowerBound)
        let startOffset = max(0, distanceToMatch - halfLength)
        let start = trimmed.index(trimmed.startIndex, offsetBy: startOffset)
        let end = trimmed.index(start, offsetBy: maxLength, limitedBy: trimmed.endIndex) ?? trimmed.endIndex
        return String(trimmed[start..<end])
    }

    private func normalized(_ value: String?) -> String? {
        guard let value else {
            return nil
        }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

public enum DemoRiskAssessmentData {
    public static var ibuprofenReview: RiskAssessmentInput {
        RiskAssessmentInput(
            medication: Medication(
                displayName: "Ibuprofen",
                genericName: "ibuprofen",
                kind: .overTheCounter,
                form: "tablet",
                strength: "200 mg",
                inputSource: .demoData
            ),
            label: DemoDrugLabels.all.first { $0.name == "Ibuprofen" },
            drugClasses: [
                DrugClass(classID: "N0000175722", name: "Analgesics", source: "MEDRT")
            ],
            healthConditionEntries: [
                UserRiskContextEntry(name: "stroke", note: "用户记录：既往卒中相关病史，需要复核。")
            ],
            dietaryConcernEntries: [
                UserRiskContextEntry(name: "alcohol", note: "用户记录：近期饮酒，需要复核。")
            ]
        )
    }
}
