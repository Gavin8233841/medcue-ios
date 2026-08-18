import Foundation
import Testing
@testable import MedicationAdherenceCore

@Test func visitSummaryCollectsAdherenceAndNotes() async throws {
    let medication = Medication(
        displayName: "Ibuprofen",
        kind: .overTheCounter,
        inputSource: .demoData
    )
    let scheduled = [
        ScheduledDose(planID: UUID(), dueAt: Date(), dose: DoseAmount(value: 1, unit: "tablet")),
        ScheduledDose(planID: UUID(), dueAt: Date(), dose: DoseAmount(value: 1, unit: "tablet"))
    ]
    let events = [
        DoseEvent(scheduledDoseID: scheduled[0].id, status: .taken, recordedAt: Date()),
        DoseEvent(scheduledDoseID: scheduled[1].id, status: .skipped, recordedAt: Date(), reason: "Forgot while outside")
    ]

    let summary = VisitSummaryBuilder().build(
        medication: medication,
        scheduledDoses: scheduled,
        events: events
    )

    #expect(summary.lines[0].takenCount == 1)
    #expect(summary.lines[0].skippedCount == 1)
    #expect(summary.lines[0].notes == ["Forgot while outside"])
    #expect(summary.safetyNote.contains("不能替代"))
}
