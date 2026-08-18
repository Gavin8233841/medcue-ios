import Foundation
import Testing
@testable import MedicationAdherenceCore

@Test func doseChangeRequiresConfirmation() async throws {
    let audit = PlanAuditEngine().audit(
        planID: UUID(),
        field: .dose,
        source: .doctor,
        note: "Dose changed after clinic visit"
    )

    #expect(audit.requiresConfirmation)
}

@Test func sourceChangeFromDoctorCanAvoidExtraConfirmation() async throws {
    let audit = PlanAuditEngine().audit(
        planID: UUID(),
        field: .source,
        source: .doctor,
        note: "Doctor confirmed source"
    )

    #expect(!audit.requiresConfirmation)
}
