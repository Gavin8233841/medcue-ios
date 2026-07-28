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

        _ = try plan.startDate.validatedDate(calendar: calendar, timeZone: timeZone)
        _ = try endDate.validatedDate(calendar: calendar, timeZone: timeZone)

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

            let currentDate = try current.validatedDate(calendar: calendar, timeZone: timeZone)
            guard let nextDate = calendar.date(
                byAdding: .day,
                value: 1,
                to: currentDate
            ) else {
                throw MedicationPlanError.invalidDateRange
            }
            let nextComponents = calendar.dateComponents([.year, .month, .day], from: nextDate)
            guard let year = nextComponents.year,
                  let month = nextComponents.month,
                  let day = nextComponents.day
            else {
                throw MedicationPlanError.invalidDateRange
            }
            current = DateOnly(year: year, month: month, day: day)
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

        _ = try plan.startDate.validatedDate(calendar: calendar, timeZone: calendar.timeZone)
        _ = try endDate.validatedDate(calendar: calendar, timeZone: calendar.timeZone)

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

enum AdherenceMath {
    static func completionRate(scheduledCount: Int, takenCount: Int) -> Double {
        guard scheduledCount > 0 else {
            return 0
        }
        let boundedTakenCount = min(max(takenCount, 0), scheduledCount)
        return Double(boundedTakenCount) / Double(scheduledCount)
    }

    static func clampedRate(_ value: Double) -> Double {
        min(max(value, 0), 1)
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
        self.completionRate = AdherenceMath.completionRate(
            scheduledCount: scheduledCount,
            takenCount: takenCount
        )
    }
}

public struct AdherenceCalculator: Sendable {
    public init() {}

    public func summarize(scheduledDoses: [ScheduledDose], events: [DoseEvent]) -> AdherenceSummary {
        let scheduledIDs = Set(scheduledDoses.map(\.id))
        let latestRelevantEvents = DoseEventTimeline.latestByScheduledDoseID(in: events)
            .filter { scheduledIDs.contains($0.key) }
            .map(\.value)
        return AdherenceSummary(
            scheduledCount: scheduledDoses.count,
            takenCount: latestRelevantEvents.filter { $0.status == .taken || $0.status == .corrected }.count,
            skippedCount: latestRelevantEvents.filter { $0.status == .skipped }.count,
            delayedCount: latestRelevantEvents.filter { $0.status == .delayed }.count
        )
    }
}
