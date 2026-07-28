import Foundation
import SwiftData

struct MedicationLabelReviewInput {
    let medicationID: UUID
    let rawText: String
    let sourceTitle: String
    let averageOCRConfidence: Double
    let reviewedAt: Date
}

struct MedicationLabelReviewCommit {
    let labelID: UUID
    let riskResult: RiskLifecycleSyncResult
}

enum MedicationLabelReviewRejection: Equatable {
    case emptyLabel
    case medicationNotFound
    case readFailed
}

enum MedicationLabelReviewCommandOutcome {
    case committed(MedicationLabelReviewCommit)
    case rejected(MedicationLabelReviewRejection)
    case saveFailed
}

@MainActor
struct MedicationLabelReviewCommand {
    typealias SaveOperation = (ModelContext) throws -> Void

    private let modelContext: ModelContext
    private let saveOperation: SaveOperation

    init(
        modelContext: ModelContext,
        saveOperation: @escaping SaveOperation = { try $0.save() }
    ) {
        self.modelContext = modelContext
        self.saveOperation = saveOperation
    }

    func save(_ input: MedicationLabelReviewInput) -> MedicationLabelReviewCommandOutcome {
        let rawText = input.rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rawText.isEmpty else {
            return .rejected(.emptyLabel)
        }

        let medicationID = input.medicationID
        let medication: StoredMedication
        let existingLabel: StoredMedicationLabel?
        let existingRisks: [StoredRiskCard]
        do {
            var medicationDescriptor = FetchDescriptor<StoredMedication>(
                predicate: #Predicate { $0.id == medicationID }
            )
            medicationDescriptor.fetchLimit = 1
            guard let fetchedMedication = try modelContext.fetch(medicationDescriptor).first else {
                return .rejected(.medicationNotFound)
            }
            medication = fetchedMedication
            var labelDescriptor = FetchDescriptor<StoredMedicationLabel>(
                predicate: #Predicate { $0.medicationID == medicationID },
                sortBy: [SortDescriptor(\.importedAt, order: .reverse)]
            )
            labelDescriptor.fetchLimit = 1
            existingLabel = try modelContext.fetch(labelDescriptor).first
            existingRisks = try modelContext.fetch(FetchDescriptor<StoredRiskCard>(
                predicate: #Predicate { $0.medicationID == medicationID }
            ))
        } catch {
            return .rejected(.readFailed)
        }

        let labelSnapshot = existingLabel.map(MedicationLabelSnapshot.init)
        let riskSnapshots = existingRisks.map(MedicationRiskCardSnapshot.init)
        let label = existingLabel ?? StoredMedicationLabel(
            medicationID: medicationID,
            medicationName: userFacingMedicationName(for: medication),
            rawText: rawText,
            sourceTitle: normalizedSourceTitle(input.sourceTitle),
            averageOCRConfidence: input.averageOCRConfidence,
            importedAt: input.reviewedAt
        )
        label.medicationName = userFacingMedicationName(for: medication)
        label.rawText = rawText
        label.sourceTitle = normalizedSourceTitle(input.sourceTitle)
        label.averageOCRConfidence = input.averageOCRConfidence
        label.importedAt = input.reviewedAt
        if existingLabel == nil {
            modelContext.insert(label)
        }

        let result: RiskLifecycleSyncResult
        do {
            result = try MedicationRiskReviewService.applyUserLabelRisks(
                medication: medication,
                label: label,
                existing: existingRisks,
                reviewedAt: input.reviewedAt,
                in: modelContext
            )
            try saveOperation(modelContext)
        } catch {
            labelSnapshot?.restore()
            riskSnapshots.forEach { $0.restore() }
            modelContext.rollback()
            AppPersistenceCommitter.reportFailure(operation: "medication-label-review")
            return .saveFailed
        }

        return .committed(MedicationLabelReviewCommit(labelID: label.id, riskResult: result))
    }

    private func normalizedSourceTitle(_ title: String) -> String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed == "本地保存说明书摘要" {
            return "用户确认说明书"
        }
        return trimmed
    }
}

private struct MedicationLabelSnapshot {
    let label: StoredMedicationLabel
    let medicationName: String
    let rawText: String
    let sourceTitle: String
    let sourceRaw: String
    let averageOCRConfidence: Double
    let importedAt: Date
    let lastRiskReviewAt: Date?

    init(_ label: StoredMedicationLabel) {
        self.label = label
        medicationName = label.medicationName
        rawText = label.rawText
        sourceTitle = label.sourceTitle
        sourceRaw = label.sourceRaw
        averageOCRConfidence = label.averageOCRConfidence
        importedAt = label.importedAt
        lastRiskReviewAt = label.lastRiskReviewAt
    }

    func restore() {
        label.medicationName = medicationName
        label.rawText = rawText
        label.sourceTitle = sourceTitle
        label.sourceRaw = sourceRaw
        label.averageOCRConfidence = averageOCRConfidence
        label.importedAt = importedAt
        label.lastRiskReviewAt = lastRiskReviewAt
    }
}

private struct MedicationRiskCardSnapshot {
    let card: StoredRiskCard
    let kindRaw: String
    let severityRaw: String
    let sourceKindRaw: String
    let displayPriority: Int
    let title: String
    let message: String
    let sourceTitle: String
    let sourceExcerpt: String
    let detectionSignature: String
    let requiresProfessionalReview: Bool
    let safetyNote: String
    let firstDetectedAt: Date
    let lastDetectedAt: Date
    let readAt: Date?
    let resolvedAt: Date?
    let resolutionNote: String
    let reviewedAt: Date?
    let archivedAt: Date?
    let reviewNote: String

    init(_ card: StoredRiskCard) {
        self.card = card
        kindRaw = card.kindRaw
        severityRaw = card.severityRaw
        sourceKindRaw = card.sourceKindRaw
        displayPriority = card.displayPriority
        title = card.title
        message = card.message
        sourceTitle = card.sourceTitle
        sourceExcerpt = card.sourceExcerpt
        detectionSignature = card.detectionSignature
        requiresProfessionalReview = card.requiresProfessionalReview
        safetyNote = card.safetyNote
        firstDetectedAt = card.firstDetectedAt
        lastDetectedAt = card.lastDetectedAt
        readAt = card.readAt
        resolvedAt = card.resolvedAt
        resolutionNote = card.resolutionNote
        reviewedAt = card.reviewedAt
        archivedAt = card.archivedAt
        reviewNote = card.reviewNote
    }

    func restore() {
        card.kindRaw = kindRaw
        card.severityRaw = severityRaw
        card.sourceKindRaw = sourceKindRaw
        card.displayPriority = displayPriority
        card.title = title
        card.message = message
        card.sourceTitle = sourceTitle
        card.sourceExcerpt = sourceExcerpt
        card.detectionSignature = detectionSignature
        card.requiresProfessionalReview = requiresProfessionalReview
        card.safetyNote = safetyNote
        card.firstDetectedAt = firstDetectedAt
        card.lastDetectedAt = lastDetectedAt
        card.readAt = readAt
        card.resolvedAt = resolvedAt
        card.resolutionNote = resolutionNote
        card.reviewedAt = reviewedAt
        card.archivedAt = archivedAt
        card.reviewNote = reviewNote
    }
}
