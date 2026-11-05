import Foundation

public struct DoseReminderPolicy: Sendable, Equatable {
    public var delayMinutes: Int
    public var alarmEscalationMinutes: Int
    public var earlyConfirmationHours: Int

    public init(
        delayMinutes: Int = 30,
        alarmEscalationMinutes: Int = 5,
        earlyConfirmationHours: Int = 6
    ) {
        self.delayMinutes = delayMinutes
        self.alarmEscalationMinutes = alarmEscalationMinutes
        self.earlyConfirmationHours = earlyConfirmationHours
    }

    public static let competitionDemo = DoseReminderPolicy()

    public var delayInterval: TimeInterval {
        TimeInterval(delayMinutes * 60)
    }

    public var alarmEscalationInterval: TimeInterval {
        TimeInterval(alarmEscalationMinutes * 60)
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

    public func requiresEarlyTakenConfirmation(plannedDueAt: Date, now: Date) -> Bool {
        plannedDueAt.timeIntervalSince(now) >= earlyConfirmationInterval
    }
}
