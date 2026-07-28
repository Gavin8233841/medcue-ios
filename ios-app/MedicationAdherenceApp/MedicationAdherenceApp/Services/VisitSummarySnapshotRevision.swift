import Foundation

struct VisitSummarySnapshotRevision: Sendable, Equatable {
    let startDate: Date
    let endDate: Date
    let medicationSignature: Int
    let taskSignature: Int
    let doseChangeSignature: Int
    let riskCardSignature: Int
    let healthSignalSignature: Int
    let planSignature: Int
    let lifecycleEventSignature: Int

    var id: String {
        [
            String(startDate.timeIntervalSinceReferenceDate.bitPattern),
            String(endDate.timeIntervalSinceReferenceDate.bitPattern),
            String(medicationSignature),
            String(taskSignature),
            String(doseChangeSignature),
            String(riskCardSignature),
            String(healthSignalSignature),
            String(planSignature),
            String(lifecycleEventSignature)
        ].joined(separator: "|")
    }
}
