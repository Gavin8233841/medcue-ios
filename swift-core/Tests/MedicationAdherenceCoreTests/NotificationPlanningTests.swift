import Foundation
import Testing
@testable import MedicationAdherenceCore

@Test func notificationPlannerIncludesPhotoActionOnlyWhenPhotoExists() async throws {
    let medication = Medication(
        displayName: "Artificial Tears",
        kind: .overTheCounter,
        inputSource: .manual,
        photoPath: "photos/tears.jpg"
    )
    let plan = MedicationPlan(
        medicationID: medication.id,
        dose: DoseAmount(value: 1, unit: "drop"),
        startDate: DateOnly(year: 2026, month: 6, day: 3),
        endDate: DateOnly(year: 2026, month: 6, day: 3),
        timingRule: .fixedInterval(start: Date(), intervalHours: 8),
        timeZonePolicy: .fixedInterval,
        sourceNote: "User-confirmed"
    )
    let scheduled = ScheduledDose(planID: plan.id, dueAt: Date(), dose: plan.dose)

    let notification = NotificationPlanner().plans(
        medication: medication,
        plan: plan,
        scheduledDoses: [scheduled]
    )[0]

    #expect(notification.identifier == "dose.\(scheduled.id.uuidString)")
    #expect(notification.payload.actions.contains(.viewMedicationPhoto))
}

@Test func timeZoneReviewRequiresReviewWhenZoneChanges() async throws {
    let plan = MedicationPlan(
        medicationID: UUID(),
        dose: DoseAmount(value: 1, unit: "tablet"),
        startDate: DateOnly(year: 2026, month: 6, day: 3),
        endDate: DateOnly(year: 2026, month: 6, day: 3),
        timingRule: .fixedInterval(start: Date(), intervalHours: 8),
        timeZonePolicy: .fixedInterval,
        sourceNote: "Doctor instruction"
    )

    let review = TimeZoneReviewEngine().review(
        plan: plan,
        oldTimeZone: TimeZone(identifier: "Asia/Shanghai")!,
        newTimeZone: TimeZone(identifier: "America/Los_Angeles")!
    )

    #expect(review.requiresUserReview)
}

