import Foundation
import MedicationAdherenceCore

enum DoseDelayPolicy {
    private static let policy = DoseReminderPolicy.competitionDemo
    static let delayMinutes = policy.delayMinutes

    static func delayedDueAtFromPlannedTime(_ plannedDueAt: Date) -> Date {
        policy.delayedDueAtFromPlannedTime(plannedDueAt, calendar: .current)
    }

    static func requiresPlannedTimeDelayConfirmation(plannedDueAt: Date, now: Date = Date()) -> Bool {
        policy.requiresPlannedTimeDelayConfirmation(plannedDueAt: plannedDueAt, now: now)
    }
}
