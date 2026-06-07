import Foundation

public struct ReminderScheduleEngine: Sendable {
    public init() {}

    public func scheduledDoses(
        for plan: MedicationPlan,
        calendar baseCalendar: Calendar = Calendar(identifier: .gregorian),
        timeZone: TimeZone
    ) throws -> [ScheduledDose] {
        switch plan.timingRule {
        case .fixedLocalTimes(let times):
            return try fixedLocalTimeDoses(
                plan: plan,
                times: times.sorted(),
                calendar: baseCalendar,
                timeZone: timeZone
            )
        case .fixedInterval(let start, let intervalHours):
            return try fixedIntervalDoses(plan: plan, start: start, intervalHours: intervalHours)
        }
    }

    private func fixedLocalTimeDoses(
        plan: MedicationPlan,
        times: [TimeOfDay],
        calendar baseCalendar: Calendar,
        timeZone: TimeZone
    ) throws -> [ScheduledDose] {
        guard let endDate = plan.endDate else {
            throw MedicationPlanError.missingEndDateForLocalSchedule
        }
        guard plan.startDate <= endDate else {
            throw MedicationPlanError.invalidDateRange
        }

        var calendar = baseCalendar
        calendar.timeZone = timeZone

        var current = plan.startDate
        var doses: [ScheduledDose] = []

        while current <= endDate {
            for time in times {
                var components = DateComponents()
                components.calendar = calendar
                components.timeZone = timeZone
                components.year = current.year
                components.month = current.month
                components.day = current.day
                components.hour = time.hour
                components.minute = time.minute

                if let dueAt = calendar.date(from: components) {
                    doses.append(ScheduledDose(planID: plan.id, dueAt: dueAt, dose: plan.dose))
                }
            }

            guard let nextDate = calendar.date(
                byAdding: .day,
                value: 1,
                to: calendar.date(from: DateComponents(year: current.year, month: current.month, day: current.day))!
            ) else {
                break
            }
            let nextComponents = calendar.dateComponents([.year, .month, .day], from: nextDate)
            current = DateOnly(year: nextComponents.year!, month: nextComponents.month!, day: nextComponents.day!)
        }

        return doses.sorted { $0.dueAt < $1.dueAt }
    }

    private func fixedIntervalDoses(
        plan: MedicationPlan,
        start: Date,
        intervalHours: Int
    ) throws -> [ScheduledDose] {
        guard intervalHours > 0 else {
            throw MedicationPlanError.invalidInterval
        }
        guard let endDate = plan.endDate else {
            throw MedicationPlanError.missingEndDateForLocalSchedule
        }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current

        guard let endOfDay = calendar.date(
            from: DateComponents(
                timeZone: calendar.timeZone,
                year: endDate.year,
                month: endDate.month,
                day: endDate.day,
                hour: 23,
                minute: 59,
                second: 59
            )
        ) else {
            throw MedicationPlanError.invalidDateRange
        }

        var next = start
        var doses: [ScheduledDose] = []
        while next <= endOfDay {
            doses.append(ScheduledDose(planID: plan.id, dueAt: next, dose: plan.dose))
            next = next.addingTimeInterval(TimeInterval(intervalHours * 60 * 60))
        }
        return doses
    }
}

public struct AdherenceSummary: Sendable, Equatable {
    public var scheduledCount: Int
    public var takenCount: Int
    public var skippedCount: Int
    public var delayedCount: Int
    public var completionRate: Double

    public init(scheduledCount: Int, takenCount: Int, skippedCount: Int, delayedCount: Int) {
        self.scheduledCount = scheduledCount
        self.takenCount = takenCount
        self.skippedCount = skippedCount
        self.delayedCount = delayedCount
        self.completionRate = scheduledCount == 0 ? 0 : Double(takenCount) / Double(scheduledCount)
    }
}

public struct AdherenceCalculator: Sendable {
    public init() {}

    public func summarize(scheduledDoses: [ScheduledDose], events: [DoseEvent]) -> AdherenceSummary {
        let scheduledIDs = Set(scheduledDoses.map(\.id))
        let relevantEvents = events.filter { scheduledIDs.contains($0.scheduledDoseID) }
        return AdherenceSummary(
            scheduledCount: scheduledDoses.count,
            takenCount: relevantEvents.filter { $0.status == .taken || $0.status == .corrected }.count,
            skippedCount: relevantEvents.filter { $0.status == .skipped }.count,
            delayedCount: relevantEvents.filter { $0.status == .delayed }.count
        )
    }
}

