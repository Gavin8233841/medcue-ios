import Foundation

public struct DoseReminderPolicy: Sendable, Equatable {
    public var delayMinutes: Int
    public var alarmEscalationMinutes: Int
    public var autoSkipMinutes: Int
    public var earlyConfirmationHours: Int

    public init(
        delayMinutes: Int = 30,
        alarmEscalationMinutes: Int = 5,
        autoSkipMinutes: Int = 15,
        earlyConfirmationHours: Int = 6
    ) {
        self.delayMinutes = delayMinutes
        self.alarmEscalationMinutes = alarmEscalationMinutes
        self.autoSkipMinutes = autoSkipMinutes
        self.earlyConfirmationHours = earlyConfirmationHours
    }

    public static let competitionDemo = DoseReminderPolicy()

    public var delayInterval: TimeInterval {
        TimeInterval(delayMinutes * 60)
    }

    public var alarmEscalationInterval: TimeInterval {
        TimeInterval(alarmEscalationMinutes * 60)
    }

    public var autoSkipInterval: TimeInterval {
        TimeInterval(autoSkipMinutes * 60)
    }

    public var earlyConfirmationInterval: TimeInterval {
        TimeInterval(earlyConfirmationHours * 60 * 60)
    }

    public func delayedDueAtFromPlannedTime(_ plannedDueAt: Date, calendar: Calendar = .current) -> Date {
        calendar.date(byAdding: .minute, value: delayMinutes, to: plannedDueAt) ?? plannedDueAt.addingTimeInterval(delayInterval)
    }

    public func requiresPlannedTimeDelayConfirmation(plannedDueAt: Date, now: Date) -> Bool {
        plannedDueAt.timeIntervalSince(now) >= earlyConfirmationInterval
    }

    public func escalationDueAt(for plannedDueAt: Date) -> Date {
        plannedDueAt.addingTimeInterval(alarmEscalationInterval)
    }

    public func autoSkipRecordedAt(for plannedDueAt: Date) -> Date {
        plannedDueAt.addingTimeInterval(autoSkipInterval)
    }

    public func shouldAutoSkip(plannedDueAt: Date, now: Date) -> Bool {
        now.timeIntervalSince(plannedDueAt) >= autoSkipInterval
    }

    public func shouldAutoSkipReopenedDose(reopenedAt: Date, now: Date) -> Bool {
        now.timeIntervalSince(reopenedAt) >= autoSkipInterval
    }

    public func requiresEarlyTakenConfirmation(plannedDueAt: Date, now: Date) -> Bool {
        plannedDueAt.timeIntervalSince(now) >= earlyConfirmationInterval
    }
}
