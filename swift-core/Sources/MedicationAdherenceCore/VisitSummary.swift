import Foundation

public struct VisitSummaryMedicationLine: Sendable, Equatable {
    public var medicationName: String
    public var scheduledCount: Int
    public var takenCount: Int
    public var skippedCount: Int
    public var delayedCount: Int
    public var notes: [String]

    public init(
        medicationName: String,
        scheduledCount: Int,
        takenCount: Int,
        skippedCount: Int,
        delayedCount: Int,
        notes: [String]
    ) {
        self.medicationName = medicationName
        self.scheduledCount = scheduledCount
        self.takenCount = takenCount
        self.skippedCount = skippedCount
        self.delayedCount = delayedCount
        self.notes = notes
    }
}

public struct VisitSummary: Sendable, Equatable {
    public var generatedAt: Date
    public var lines: [VisitSummaryMedicationLine]
    public var safetyNote: String

    public init(generatedAt: Date, lines: [VisitSummaryMedicationLine], safetyNote: String) {
        self.generatedAt = generatedAt
        self.lines = lines
        self.safetyNote = safetyNote
    }
}

public struct VisitSummaryBuilder: Sendable {
    public init() {}

    public func build(
        generatedAt: Date = Date(),
        medication: Medication,
        scheduledDoses: [ScheduledDose],
        events: [DoseEvent]
    ) -> VisitSummary {
        let summary = AdherenceCalculator().summarize(scheduledDoses: scheduledDoses, events: events)
        let scheduledIDs = Set(scheduledDoses.map(\.id))
        let notes = events
            .filter { scheduledIDs.contains($0.scheduledDoseID) }
            .compactMap(\.reason)
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

        let line = VisitSummaryMedicationLine(
            medicationName: medication.displayName,
            scheduledCount: summary.scheduledCount,
            takenCount: summary.takenCount,
            skippedCount: summary.skippedCount,
            delayedCount: summary.delayedCount,
            notes: notes
        )

        return VisitSummary(
            generatedAt: generatedAt,
            lines: [line],
            safetyNote: "此摘要仅用于复诊沟通，不能替代医生或药师的判断。"
        )
    }
}

