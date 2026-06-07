import Foundation

public enum MedicationImportField: String, Codable, Sendable, Hashable {
    case displayName
    case genericName
    case kind
    case form
    case strength
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

public struct MedicationImportReviewEngine: Sendable {
    private let minimumConfidence: Double

    public init(minimumConfidence: Double = 0.85) {
        self.minimumConfidence = minimumConfidence
    }

    public func review(_ draft: MedicationImportDraft) -> MedicationImportReview {
        var issues: [MedicationImportIssue] = []

        if isBlank(draft.displayName) {
            issues.append(MedicationImportIssue(
                kind: .missingRequiredField,
                field: .displayName,
                message: "药品名称缺失，不能直接创建用药记录。"
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
                message: "该字段识别置信度不足，需要用户确认。"
            ))
        }

        let hasName = !isBlank(draft.displayName)
        return MedicationImportReview(
            draft: draft,
            issues: issues,
            requiresUserConfirmation: true,
            canCreateMedication: hasName
        )
    }

    public func makeMedication(fromConfirmed draft: MedicationImportDraft) throws -> Medication {
        guard let displayName = normalized(draft.displayName) else {
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
