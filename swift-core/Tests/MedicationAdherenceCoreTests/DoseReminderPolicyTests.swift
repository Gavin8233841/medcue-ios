import Foundation
import Testing
@testable import MedicationAdherenceCore

@Test func doseReminderPolicyDelaysFromOriginalPlannedTime() {
    let policy = DoseReminderPolicy.competitionDemo
    let calendar = Calendar(identifier: .gregorian)
    let plannedTime = calendar.date(from: DateComponents(year: 2026, month: 6, day: 8, hour: 8, minute: 0))!

    let delayedAt = policy.delayedDueAtFromPlannedTime(plannedTime, calendar: calendar)

    #expect(delayedAt == calendar.date(from: DateComponents(year: 2026, month: 6, day: 8, hour: 8, minute: 30))!)
}

@Test func doseReminderPolicyRequiresDelayConfirmationWhenFarBeforePlan() {
    let policy = DoseReminderPolicy.competitionDemo
    let now = Date(timeIntervalSince1970: 1_000)

    #expect(policy.requiresPlannedTimeDelayConfirmation(plannedDueAt: Date(timeIntervalSince1970: 22_599), now: now) == false)
    #expect(policy.requiresPlannedTimeDelayConfirmation(plannedDueAt: Date(timeIntervalSince1970: 22_600), now: now) == true)
}

@Test func doseReminderPolicyEscalatesFiveMinutesAfterPlan() {
    let policy = DoseReminderPolicy.competitionDemo
    let plannedAt = Date(timeIntervalSince1970: 1_000)

    #expect(policy.escalationDueAt(for: plannedAt) == Date(timeIntervalSince1970: 1_300))
}

@Test func doseReminderPolicyAutoSkipsAtFifteenMinutesAfterPlan() {
    let policy = DoseReminderPolicy.competitionDemo
    let plannedAt = Date(timeIntervalSince1970: 1_000)

    #expect(policy.shouldAutoSkip(plannedDueAt: plannedAt, now: Date(timeIntervalSince1970: 1_899)) == false)
    #expect(policy.shouldAutoSkip(plannedDueAt: plannedAt, now: Date(timeIntervalSince1970: 1_900)) == true)
    #expect(policy.autoSkipRecordedAt(for: plannedAt) == Date(timeIntervalSince1970: 1_900))
}

@Test func doseReminderPolicyGivesReopenedDoseANewConfirmationWindow() {
    let policy = DoseReminderPolicy.competitionDemo
    let reopenedAt = Date(timeIntervalSince1970: 2_000)

    #expect(policy.shouldAutoSkipReopenedDose(reopenedAt: reopenedAt, now: Date(timeIntervalSince1970: 2_899)) == false)
    #expect(policy.shouldAutoSkipReopenedDose(reopenedAt: reopenedAt, now: Date(timeIntervalSince1970: 2_900)) == true)
}

@Test func doseReminderPolicyRequiresConfirmationSixHoursEarly() {
    let policy = DoseReminderPolicy.competitionDemo
    let now = Date(timeIntervalSince1970: 1_000)

    #expect(policy.requiresEarlyTakenConfirmation(plannedDueAt: Date(timeIntervalSince1970: 22_599), now: now) == false)
    #expect(policy.requiresEarlyTakenConfirmation(plannedDueAt: Date(timeIntervalSince1970: 22_600), now: now) == true)
}
