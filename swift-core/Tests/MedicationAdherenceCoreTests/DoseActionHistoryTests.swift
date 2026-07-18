import Foundation
import Testing
@testable import MedicationAdherenceCore

@Test func doseActionHistoryBuildsUndoableTakenRecord() {
    let occurredAt = Date()
    let record = DoseActionHistoryBuilder(undoWindowSeconds: 60).record(
        scheduledDoseID: UUID(),
        action: .markTaken,
        previousStatus: nil,
        occurredAt: occurredAt,
        note: "用户点击已服用"
    )

    #expect(record.newStatus == .taken)
    #expect(record.canUndo(at: occurredAt.addingTimeInterval(30)))
    #expect(!record.canUndo(at: occurredAt.addingTimeInterval(61)))
    #expect(record.note == "用户点击已服用")
}

@Test func doseActionHistoryMapsAllActionsToDoseStatuses() {
    let builder = DoseActionHistoryBuilder()
    let doseID = UUID()

    #expect(builder.record(scheduledDoseID: doseID, action: .delay, previousStatus: nil).newStatus == .delayed)
    #expect(builder.record(scheduledDoseID: doseID, action: .skip, previousStatus: nil).newStatus == .skipped)
    #expect(builder.record(scheduledDoseID: doseID, action: .correct, previousStatus: .skipped).newStatus == .corrected)
    #expect(builder.record(scheduledDoseID: doseID, action: .archiveToday, previousStatus: .taken).newStatus == .taken)
    #expect(builder.record(scheduledDoseID: doseID, action: .restoreArchive, previousStatus: .skipped).newStatus == .skipped)
}
