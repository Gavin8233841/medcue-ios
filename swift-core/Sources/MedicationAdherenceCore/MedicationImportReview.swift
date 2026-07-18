import Foundation

public enum MedicationImportField: String, Codable, Sendable, Hashable {
    case displayName
    case genericName
    case kind
    case form
    case strength
    case doseAmount
    case directions
    case barcodeValue
    case prescriptionText
    case photoPath
}

public enum MedicationImportIssueKind: String, Codable, Sendable, Equatable {
    case missingRequiredField
    case lowConfidence
    case sourceNeedsReview
}

public struct MedicationImportIssue: Codable, Sendable, Equatable {
    public var kind: MedicationImportIssueKind
    public var field: MedicationImportField
    public var message: String

    public init(kind: MedicationImportIssueKind, field: MedicationImportField, message: String) {
        self.kind = kind
        self.field = field
        self.message = message
    }
}

public struct MedicationImportDraft: Codable, Identifiable, Sendable, Equatable {
    public let id: UUID
    public var source: MedicationInputSource
    public var displayName: String?
    public var genericName: String?
    public var kind: MedicationKind
    public var form: String?
    public var strength: String?
    public var doseValue: Double?
    public var doseUnit: String?
    public var directionsText: String?
    public var barcodeValue: String?
    public var prescriptionText: String?
    public var photoPath: String?
    public var confidenceByField: [MedicationImportField: Double]
    public var extractedAt: Date
    public var sourceNote: String

    public init(
        id: UUID = UUID(),
        source: MedicationInputSource,
        displayName: String? = nil,
        genericName: String? = nil,
        kind: MedicationKind = .unknown,
        form: String? = nil,
        strength: String? = nil,
        doseValue: Double? = nil,
        doseUnit: String? = nil,
        directionsText: String? = nil,
        barcodeValue: String? = nil,
        prescriptionText: String? = nil,
        photoPath: String? = nil,
        confidenceByField: [MedicationImportField: Double] = [:],
        extractedAt: Date = Date(),
        sourceNote: String = ""
    ) {
        self.id = id
        self.source = source
        self.displayName = displayName
        self.genericName = genericName
        self.kind = kind
        self.form = form
        self.strength = strength
        self.doseValue = doseValue
        self.doseUnit = doseUnit
        self.directionsText = directionsText
        self.barcodeValue = barcodeValue
        self.prescriptionText = prescriptionText
        self.photoPath = photoPath
        self.confidenceByField = confidenceByField
        self.extractedAt = extractedAt
        self.sourceNote = sourceNote
    }
}

public struct MedicationImportReview: Codable, Sendable, Equatable {
    public var draft: MedicationImportDraft
    public var issues: [MedicationImportIssue]
    public var requiresUserConfirmation: Bool
    public var canCreateMedication: Bool

    public init(
        draft: MedicationImportDraft,
        issues: [MedicationImportIssue],
        requiresUserConfirmation: Bool,
        canCreateMedication: Bool
    ) {
        self.draft = draft
        self.issues = issues
        self.requiresUserConfirmation = requiresUserConfirmation
        self.canCreateMedication = canCreateMedication
    }
}

public enum MedicationImportReviewError: Error, Sendable, Equatable {
    case missingDisplayName
}

public struct MedicationImportExtractedFields: Sendable, Equatable {
    public var displayName: String?
    public var genericName: String?
    public var form: String?
    public var strength: String?
    public var doseAmount: DoseAmount?
    public var directionsText: String?

    public init(
        displayName: String? = nil,
        genericName: String? = nil,
        form: String? = nil,
        strength: String? = nil,
        doseAmount: DoseAmount? = nil,
        directionsText: String? = nil
    ) {
        self.displayName = displayName
        self.genericName = genericName
        self.form = form
        self.strength = strength
        self.doseAmount = doseAmount
        self.directionsText = directionsText
    }
}

public enum MedicationImportTextExtractor {
    public static func displayName(fromPrescriptionText text: String) -> String? {
        structuredFields(fromPrescriptionText: text).displayName
    }

    public static func scannedDisplayName(fromText text: String) -> String? {
        if let displayName = structuredFields(fromPrescriptionText: text).displayName {
            return displayName
        }
        for rawLine in text.components(separatedBy: .newlines) {
            let line = normalizedLine(rawLine)
            guard isLikelyScannedNameLine(line),
                  let displayName = MedicationNamePolicy.normalizedDisplayName(line)
            else {
                continue
            }
            return displayName
        }
        return nil
    }

    public static func structuredFields(fromPrescriptionText text: String) -> MedicationImportExtractedFields {
        var fields = MedicationImportExtractedFields()
        for rawLine in text.components(separatedBy: .newlines) {
            if fields.displayName == nil,
               let displayName = displayName(fromLine: rawLine) {
                fields.displayName = displayName
            }
            if fields.genericName == nil,
               let genericName = medicationName(fromLine: rawLine, labels: explicitGenericNameLabels) {
                fields.genericName = genericName
            }
            if fields.strength == nil,
               let strength = textValue(fromLine: rawLine, labels: explicitStrengthLabels) {
                fields.strength = strength
            }
            if fields.form == nil,
               let form = textValue(fromLine: rawLine, labels: explicitFormLabels) {
                fields.form = form
            }
            if fields.directionsText == nil,
               let directionsText = textValue(fromLine: rawLine, labels: explicitDirectionsLabels) {
                fields.directionsText = directionsText
            }
        }
        if let directionsText = fields.directionsText,
           let doseAmount = doseAmount(fromDirectionsText: directionsText) {
            fields.doseAmount = doseAmount
        }
        if fields.displayName == nil {
            fields.displayName = fields.genericName
        }
        return fields
    }

    private static func displayName(fromLine rawLine: String) -> String? {
        medicationName(fromLine: rawLine, labels: explicitDisplayNameLabels)
    }

    private static func medicationName(fromLine rawLine: String, labels: [String]) -> String? {
        let line = normalizedLine(rawLine)
        guard !line.isEmpty else {
            return nil
        }

        if let separatedValue = valueAfterExplicitSeparator(in: line, labels: labels),
           let normalizedName = MedicationNamePolicy.normalizedDisplayName(separatedValue) {
            return normalizedName
        }

        for label in labels where allowsPrefixWithoutSeparator(label) {
            guard line.hasPrefix(label) else {
                continue
            }
            let value = line
                .dropFirst(label.count)
                .trimmingCharacters(in: nameValueTrimCharacters)
            if let normalizedName = MedicationNamePolicy.normalizedDisplayName(String(value)) {
                return normalizedName
            }
        }
        return nil
    }

    private static func textValue(fromLine rawLine: String, labels: [String]) -> String? {
        let line = normalizedLine(rawLine)
        guard !line.isEmpty else {
            return nil
        }

        if let separatedValue = valueAfterExplicitSeparator(in: line, labels: labels) {
            return normalizedTextValue(separatedValue)
        }

        for label in labels where allowsPrefixWithoutSeparator(label) {
            guard line.hasPrefix(label) else {
                continue
            }
            let value = line
                .dropFirst(label.count)
                .trimmingCharacters(in: nameValueTrimCharacters)
            return normalizedTextValue(String(value))
        }
        return nil
    }

    private static func isLikelyScannedNameLine(_ line: String) -> Bool {
        guard line.count >= 2,
              line.rangeOfCharacter(from: CharacterSet(charactersIn: ":：")) == nil
        else {
            return false
        }
        let blockedFragments = [
            "规格",
            "用法",
            "用量",
            "每日",
            "每次",
            "医嘱",
            "处方",
            "说明书",
            "有效期",
            "生产",
            "批号",
            "批准文号",
            "国药准字",
            "条码",
            "注意",
            "禁忌",
            "不良反应",
            "成份",
            "成分",
            "贮藏",
            "storage",
            "warning",
            "directions",
            "instructions",
            "expiry",
            "lot",
            "batch"
        ]
        let normalized = line.lowercased()
        return !blockedFragments.contains { normalized.contains($0.lowercased()) }
    }

    private static func doseAmount(fromDirectionsText text: String) -> DoseAmount? {
        let normalizedText = text
            .replacingOccurrences(of: "　", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedText.isEmpty else {
            return nil
        }

        let patterns = [
            #"(?i)(?:每次|一次|每回|每服)\s*([0-9]+(?:\.[0-9]+)?|半|一|二|两|三|四|五|六|七|八|九|十)\s*(片|粒|袋|包|滴|喷|贴|支|丸|毫升|ml)"#,
            #"(?i)(?:take\s*)?([0-9]+(?:\.[0-9]+)?|half|one|two|three|four|five|six|seven|eight|nine|ten)\s*(tablet|tablets|tab|tabs|capsule|capsules|cap|caps|drop|drops|spray|sprays|patch|patches|ml|milliliter|milliliters)\b"#
        ]

        for pattern in patterns {
            guard let match = firstRegexMatch(pattern: pattern, in: normalizedText),
                  match.indices.contains(1),
                  match.indices.contains(2)
            else {
                continue
            }
            let valueToken = match[1]
            let rawUnit = match[2]
            guard let value = decimalDoseValue(from: valueToken),
                  let unit = normalizedDoseUnit(rawUnit),
                  isSupportedPrefillDose(value)
            else {
                continue
            }
            return DoseAmount(value: value, unit: unit)
        }
        return nil
    }

    private static func firstRegexMatch(pattern: String, in text: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return nil
        }
        let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: nsRange) else {
            return nil
        }
        return (0..<match.numberOfRanges).map { index in
            let range = match.range(at: index)
            guard range.location != NSNotFound,
                  let textRange = Range(range, in: text)
            else {
                return ""
            }
            return String(text[textRange])
        }
    }

    private static func decimalDoseValue(from token: String) -> Decimal? {
        let normalized = token.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let value = Double(normalized) {
            return Decimal(value)
        }
        switch normalized {
        case "半", "half":
            return Decimal(0.5)
        case "一", "one":
            return Decimal(1)
        case "二", "两", "two":
            return Decimal(2)
        case "三", "three":
            return Decimal(3)
        case "四", "four":
            return Decimal(4)
        case "五", "five":
            return Decimal(5)
        case "六", "six":
            return Decimal(6)
        case "七", "seven":
            return Decimal(7)
        case "八", "eight":
            return Decimal(8)
        case "九", "nine":
            return Decimal(9)
        case "十", "ten":
            return Decimal(10)
        default:
            return nil
        }
    }

    private static func normalizedDoseUnit(_ rawUnit: String) -> String? {
        switch rawUnit.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "片", "tablet", "tablets", "tab", "tabs":
            return "片"
        case "粒", "capsule", "capsules", "cap", "caps":
            return "粒"
        case "袋", "包":
            return "袋"
        case "滴", "drop", "drops":
            return "滴"
        case "喷", "spray", "sprays":
            return "喷"
        case "贴", "patch", "patches":
            return "贴"
        case "支":
            return "支"
        case "丸":
            return "丸"
        case "毫升", "ml", "milliliter", "milliliters":
            return "毫升"
        default:
            return nil
        }
    }

    private static func isSupportedPrefillDose(_ value: Decimal) -> Bool {
        value >= Decimal(0.5) && value <= Decimal(10)
    }

    private static func allowsPrefixWithoutSeparator(_ label: String) -> Bool {
        label.range(of: "[A-Za-z]", options: .regularExpression) == nil
    }

    private static func valueAfterExplicitSeparator(in line: String, labels: [String]) -> String? {
        let separators = CharacterSet(charactersIn: ":：")
        guard let separatorIndex = line.unicodeScalars.firstIndex(where: { separators.contains($0) }) else {
            return nil
        }
        let rawLabel = String(line.unicodeScalars[..<separatorIndex])
        let rawValue = String(line.unicodeScalars[line.unicodeScalars.index(after: separatorIndex)...])
        let label = normalizedLabel(rawLabel)
        guard labelKeys(for: labels).contains(label) else {
            return nil
        }
        return rawValue.trimmingCharacters(in: nameValueTrimCharacters)
    }

    private static func normalizedLine(_ line: String) -> String {
        line
            .replacingOccurrences(of: "　", with: " ")
            .trimmingCharacters(in: nameValueTrimCharacters)
    }

    private static func normalizedLabel(_ label: String) -> String {
        label
            .replacingOccurrences(of: "　", with: "")
            .replacingOccurrences(of: " ", with: "")
            .trimmingCharacters(in: nameValueTrimCharacters)
            .lowercased()
    }

    private static func normalizedTextValue(_ value: String) -> String? {
        let normalized = value
            .replacingOccurrences(of: "　", with: " ")
            .trimmingCharacters(in: nameValueTrimCharacters)
        return normalized.isEmpty ? nil : normalized
    }

    private static func labelKeys(for labels: [String]) -> Set<String> {
        Set(labels.map(normalizedLabel))
    }

    private static let explicitDisplayNameLabels = [
        "药品名称",
        "药品名",
        "药名",
        "商品名称",
        "商品名",
        "品名",
        "Medication",
        "Medication Name",
        "MedicationName",
        "Drug Name",
        "DrugName"
    ]

    private static let explicitGenericNameLabels = [
        "通用名称",
        "通用名",
        "Generic Name",
        "GenericName",
        "INN"
    ]

    private static let explicitStrengthLabels = [
        "规格",
        "药品规格",
        "规格型号",
        "含量",
        "Strength"
    ]

    private static let explicitFormLabels = [
        "剂型",
        "药品剂型",
        "Dosage Form",
        "DosageForm",
        "Form"
    ]

    private static let explicitDirectionsLabels = [
        "用法用量",
        "用法",
        "用量",
        "服用方法",
        "Directions",
        "Instructions",
        "Sig"
    ]

    private static let nameValueTrimCharacters = CharacterSet.whitespacesAndNewlines
        .union(CharacterSet(charactersIn: "：:：-—·•*#[]【】()（）"))
}

public struct MedicationImportReviewEngine: Sendable {
    private let minimumConfidence: Double

    public init(minimumConfidence: Double = 0.85) {
        self.minimumConfidence = minimumConfidence
    }

    public func review(_ draft: MedicationImportDraft) -> MedicationImportReview {
        var issues: [MedicationImportIssue] = []

        let normalizedDisplayName = MedicationNamePolicy.normalizedDisplayName(draft.displayName)
        if isBlank(draft.displayName) {
            issues.append(MedicationImportIssue(
                kind: .missingRequiredField,
                field: .displayName,
                message: "药品名称缺失，不能直接创建用药记录。"
            ))
        } else if normalizedDisplayName == nil {
            issues.append(MedicationImportIssue(
                kind: .missingRequiredField,
                field: .displayName,
                message: "药品名称需要填写清晰可核对的药名，不要只填编号、剂量或规格。"
            ))
        }

        if draft.source == .barcode && isBlank(draft.barcodeValue) {
            issues.append(MedicationImportIssue(
                kind: .missingRequiredField,
                field: .barcodeValue,
                message: "条码来源缺少条码值，需要重新扫描或手动输入。"
            ))
        }

        if draft.source == .prescriptionImage && !isBlank(draft.prescriptionText) {
            issues.append(MedicationImportIssue(
                kind: .sourceNeedsReview,
                field: .prescriptionText,
                message: "处方或医嘱识别结果必须由用户按原件核对。"
            ))
        }

        for (field, confidence) in draft.confidenceByField where confidence < minimumConfidence {
            issues.append(MedicationImportIssue(
                kind: .lowConfidence,
                field: field,
                message: "这一项文字不够清晰，请按原件确认。"
            ))
        }

        return MedicationImportReview(
            draft: draft,
            issues: issues,
            requiresUserConfirmation: true,
            canCreateMedication: normalizedDisplayName != nil
        )
    }

    public func makeMedication(fromConfirmed draft: MedicationImportDraft) throws -> Medication {
        guard let displayName = MedicationNamePolicy.normalizedDisplayName(draft.displayName) else {
            throw MedicationImportReviewError.missingDisplayName
        }

        return Medication(
            displayName: displayName,
            genericName: normalized(draft.genericName),
            kind: draft.kind,
            form: normalized(draft.form),
            strength: normalized(draft.strength),
            inputSource: draft.source,
            photoPath: normalized(draft.photoPath),
            notes: normalized(draft.directionsText) ?? draft.sourceNote
        )
    }

    private func isBlank(_ value: String?) -> Bool {
        normalized(value) == nil
    }

    private func normalized(_ value: String?) -> String? {
        guard let value else {
            return nil
        }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
