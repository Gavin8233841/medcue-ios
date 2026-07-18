import Foundation
import MedicationAdherenceCore
import SwiftData

struct ExternalRiskSignal {
    var id: String
    var medicationID: UUID
    var sourceKind: StoredRiskSourceKind
    var severity: StoredRiskSeverity
    var kind: RiskAssessmentCardKind
    var displayPriority: Int
    var title: String
    var message: String
    var sourceTitle: String
    var sourceExcerpt: String
    var requiresProfessionalReview: Bool
    var safetyNote: String

    init(
        id: String,
        medicationID: UUID,
        sourceKind: StoredRiskSourceKind,
        severity: StoredRiskSeverity,
        kind: RiskAssessmentCardKind,
        displayPriority: Int,
        title: String,
        message: String,
        sourceTitle: String = "",
        sourceExcerpt: String = "",
        requiresProfessionalReview: Bool,
        safetyNote: String = RiskAssessmentEngine.defaultSafetyNote
    ) {
        self.id = id
        self.medicationID = medicationID
        self.sourceKind = sourceKind
        self.severity = severity
        self.kind = kind
        self.displayPriority = displayPriority
        self.title = title
        self.message = message
        self.sourceTitle = sourceTitle
        self.sourceExcerpt = sourceExcerpt
        self.requiresProfessionalReview = requiresProfessionalReview
        self.safetyNote = safetyNote
    }
}

struct RiskLifecycleSyncResult: Equatable {
    var createdIDs: [String] = []
    var updatedIDs: [String] = []
    var reactivatedIDs: [String] = []
    var resolvedIDs: [String] = []
    var priorityReminderIDs: [String] = []
    var resolvedPriorityReminderIDs: [String] = []

    var hasChanges: Bool {
        !createdIDs.isEmpty
            || !updatedIDs.isEmpty
            || !reactivatedIDs.isEmpty
            || !resolvedIDs.isEmpty
    }

    var hasPriorityReminderChanges: Bool {
        !priorityReminderIDs.isEmpty || !resolvedPriorityReminderIDs.isEmpty
    }

    var userFacingSummary: String {
        if !hasChanges {
            return "风险识别已完成，未发现新的说明书警示变化。"
        }
        var parts: [String] = []
        if !createdIDs.isEmpty {
            parts.append("新增 \(createdIDs.count) 条")
        }
        if !updatedIDs.isEmpty {
            parts.append("更新 \(updatedIDs.count) 条")
        }
        if !reactivatedIDs.isEmpty {
            parts.append("重新打开 \(reactivatedIDs.count) 条")
        }
        if !resolvedIDs.isEmpty {
            parts.append("解除 \(resolvedIDs.count) 条")
        }
        return "风险识别已完成：" + parts.joined(separator: "，") + "。"
    }

    mutating func appendPriorityReminderIDIfNeeded(_ id: String, card: StoredRiskCard) {
        guard card.shouldAnnounceAsPriorityReminder || card.countsForRiskBadge else {
            return
        }
        if !priorityReminderIDs.contains(id) {
            priorityReminderIDs.append(id)
        }
    }

    mutating func appendResolvedPriorityReminderIDIfNeeded(_ id: String, wasPriorityReminder: Bool) {
        guard wasPriorityReminder else {
            return
        }
        if !resolvedPriorityReminderIDs.contains(id) {
            resolvedPriorityReminderIDs.append(id)
        }
    }
}

enum RiskLifecycleSyncService {
    @MainActor
    @discardableResult
    static func sync(
        namespace: String,
        signals: [ExternalRiskSignal],
        in modelContext: ModelContext,
        resolveMissing: Bool = true
    ) -> RiskLifecycleSyncResult {
        let now = Date()
        var result = RiskLifecycleSyncResult()
        let existing = (try? modelContext.fetch(FetchDescriptor<StoredRiskCard>())) ?? []
        let existingByID = Dictionary(uniqueKeysWithValues: existing.map { ($0.id, $0) })
        let activeIDs = Set(signals.map { storedID(namespace: namespace, signalID: $0.id) })

        for signal in signals {
            let id = storedID(namespace: namespace, signalID: signal.id)
            let detectionSignature = StoredRiskCard.makeDetectionSignature(
                medicationID: signal.medicationID,
                kindRaw: signal.kind.rawValue,
                title: signal.title,
                message: signal.message,
                sourceExcerpt: signal.sourceExcerpt
            )

            if let card = existingByID[id] {
                let wasResolved = card.isResolved || card.isArchived
                let shouldMarkUnread = card.detectionSignature != detectionSignature
                    || card.severityRaw != signal.severity.rawValue
                    || card.displayPriority != signal.displayPriority
                    || card.requiresProfessionalReview != signal.requiresProfessionalReview
                let wasPriorityReminder = card.shouldAnnounceAsPriorityReminder || card.countsForRiskBadge
                card.medicationID = signal.medicationID
                card.kindRaw = signal.kind.rawValue
                card.severityRaw = signal.severity.rawValue
                card.sourceKindRaw = signal.sourceKind.rawValue
                card.displayPriority = signal.displayPriority
                card.title = signal.title
                card.message = signal.message
                card.sourceTitle = signal.sourceTitle
                card.sourceExcerpt = signal.sourceExcerpt
                card.detectionSignature = detectionSignature
                card.requiresProfessionalReview = signal.requiresProfessionalReview
                card.safetyNote = signal.safetyNote
                card.lastDetectedAt = now
                card.resolvedAt = nil
                card.resolutionNote = ""
                card.archivedAt = nil
                card.reviewNote = ""
                if shouldMarkUnread || wasResolved {
                    card.readAt = nil
                }
                if wasResolved {
                    result.reactivatedIDs.append(id)
                } else if shouldMarkUnread {
                    result.updatedIDs.append(id)
                }
                if shouldMarkUnread || wasResolved || !wasPriorityReminder {
                    result.appendPriorityReminderIDIfNeeded(id, card: card)
                }
            } else {
                let card = StoredRiskCard(
                    id: id,
                    medicationID: signal.medicationID,
                    kindRaw: signal.kind.rawValue,
                    severityRaw: signal.severity.rawValue,
                    sourceKindRaw: signal.sourceKind.rawValue,
                    displayPriority: signal.displayPriority,
                    title: signal.title,
                    message: signal.message,
                    sourceTitle: signal.sourceTitle,
                    sourceExcerpt: signal.sourceExcerpt,
                    detectionSignature: detectionSignature,
                    requiresProfessionalReview: signal.requiresProfessionalReview,
                    safetyNote: signal.safetyNote,
                    firstDetectedAt: now,
                    lastDetectedAt: now
                )
                modelContext.insert(card)
                result.createdIDs.append(id)
                result.appendPriorityReminderIDIfNeeded(id, card: card)
            }
        }

        guard resolveMissing else {
            try? modelContext.save()
            return result
        }

        for card in existing where card.id.hasPrefix("\(namespace)-") && !activeIDs.contains(card.id) && !card.isResolved {
            let wasPriorityReminder = card.shouldAnnounceAsPriorityReminder || card.countsForRiskBadge
            card.resolvedAt = now
            card.resolutionNote = "相关外部数据更新后未再触发该提醒。"
            card.archivedAt = now
            card.reviewedAt = card.reviewedAt ?? now
            card.reviewNote = "风险已自动解除。"
            result.resolvedIDs.append(card.id)
            result.appendResolvedPriorityReminderIDIfNeeded(card.id, wasPriorityReminder: wasPriorityReminder)
        }

        try? modelContext.save()
        return result
    }

    private static func storedID(namespace: String, signalID: String) -> String {
        "\(namespace)-\(stableID(signalID))"
    }

    private static func stableID(_ value: String) -> String {
        value
            .lowercased()
            .map { character in
                character.isLetter || character.isNumber ? character : "-"
            }
            .reduce(into: "") { partialResult, character in
                if character == "-", partialResult.last == "-" {
                    return
                }
                partialResult.append(character)
            }
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }
}

extension EnvironmentMedicationInsightSeverity {
    var storedRiskSeverity: StoredRiskSeverity {
        switch self {
        case .info:
            .info
        case .attention:
            .low
        case .caution:
            .medium
        case .priority:
            .high
        }
    }
}
