import Foundation

public enum MedicationKind: String, Codable, Sendable, Equatable {
    case overTheCounter
    case prescription
    case unknown
}

public enum MedicationInputSource: String, Codable, Sendable, Equatable {
    case manual
    case barcode
    case prescriptionImage
    case demoData
}

public struct Medication: Codable, Identifiable, Sendable, Equatable {
    public let id: UUID
    public var displayName: String
    public var genericName: String?
    public var kind: MedicationKind
    public var form: String?
    public var strength: String?
    public var inputSource: MedicationInputSource
    public var photoPath: String?
    public var notes: String

    public init(
        id: UUID = UUID(),
        displayName: String,
        genericName: String? = nil,
        kind: MedicationKind,
        form: String? = nil,
        strength: String? = nil,
        inputSource: MedicationInputSource,
        photoPath: String? = nil,
        notes: String = ""
    ) {
        self.id = id
        self.displayName = displayName
        self.genericName = genericName
        self.kind = kind
        self.form = form
        self.strength = strength
        self.inputSource = inputSource
        self.photoPath = photoPath
        self.notes = notes
    }
}

public enum DoseUnitKind: String, Codable, Sendable, Equatable {
    case tablet
    case capsule
    case bag
    case drop
    case spray
    case patch
    case ampoule
    case pill
    case milliliter
    case unknown
}

public struct NormalizedDoseUnit: Codable, Sendable, Equatable {
    public let kind: DoseUnitKind
    public let canonicalUnit: String
    public let originalUnit: String

    public init(rawUnit: String) {
        originalUnit = rawUnit
        switch rawUnit.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "片", "tablet", "tablets", "tab", "tabs":
            kind = .tablet
            canonicalUnit = "片"
        case "粒", "capsule", "capsules", "cap", "caps":
            kind = .capsule
            canonicalUnit = "粒"
        case "袋", "包":
            kind = .bag
            canonicalUnit = "袋"
        case "滴", "drop", "drops":
            kind = .drop
            canonicalUnit = "滴"
        case "喷", "spray", "sprays":
            kind = .spray
            canonicalUnit = "喷"
        case "贴", "patch", "patches":
            kind = .patch
            canonicalUnit = "贴"
        case "支":
            kind = .ampoule
            canonicalUnit = "支"
        case "丸":
            kind = .pill
            canonicalUnit = "丸"
        case "毫升", "ml", "milliliter", "milliliters":
            kind = .milliliter
            canonicalUnit = "毫升"
        default:
            kind = .unknown
            canonicalUnit = rawUnit.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }
}

public struct DoseAmount: Codable, Sendable, Equatable {
    public var value: Decimal
    public var unit: String

    public init(value: Decimal, unit: String) {
        self.value = value
        self.unit = unit
    }

    public var normalizedUnit: NormalizedDoseUnit {
        NormalizedDoseUnit(rawUnit: unit)
    }
}

public struct MedicationDoseChange: Codable, Identifiable, Sendable, Equatable {
    public let id: UUID
    public var medicationID: UUID
    public var planID: UUID?
    public var previousDose: DoseAmount?
    public var newDose: DoseAmount
    public var effectiveFrom: Date
    public var changedAt: Date
    public var note: String

    public init(
        id: UUID = UUID(),
        medicationID: UUID,
        planID: UUID? = nil,
        previousDose: DoseAmount? = nil,
        newDose: DoseAmount,
        effectiveFrom: Date,
        changedAt: Date = Date(),
        note: String = ""
    ) {
        self.id = id
        self.medicationID = medicationID
        self.planID = planID
        self.previousDose = previousDose
        self.newDose = newDose
        self.effectiveFrom = effectiveFrom
        self.changedAt = changedAt
        self.note = note
    }
}

public struct TimeOfDay: Codable, Sendable, Equatable, Comparable {
    public var hour: Int
    public var minute: Int

    public init(hour: Int, minute: Int) throws {
        guard (0...23).contains(hour), (0...59).contains(minute) else {
            throw MedicationPlanError.invalidTimeOfDay
        }
        self.hour = hour
        self.minute = minute
    }

    public static func < (lhs: TimeOfDay, rhs: TimeOfDay) -> Bool {
        (lhs.hour, lhs.minute) < (rhs.hour, rhs.minute)
    }
}

public struct DateOnly: Codable, Sendable, Equatable, Hashable, Comparable {
    public var year: Int
    public var month: Int
    public var day: Int

    public init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    public init(date: Date, calendar: Calendar) {
        self.year = calendar.component(.year, from: date)
        self.month = calendar.component(.month, from: date)
        self.day = calendar.component(.day, from: date)
    }

    public static func < (lhs: DateOnly, rhs: DateOnly) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }

    public func validatedDate(
        calendar baseCalendar: Calendar = Calendar(identifier: .gregorian),
        timeZone: TimeZone
    ) throws -> Date {
        var calendar = baseCalendar
        calendar.timeZone = timeZone
        let components = DateComponents(
            calendar: calendar,
            timeZone: timeZone,
            year: year,
            month: month,
            day: day,
            hour: 12
        )
        guard let date = calendar.date(from: components) else {
            throw MedicationPlanError.invalidCalendarDate
        }
        let resolved = calendar.dateComponents([.year, .month, .day], from: date)
        guard resolved.year == year, resolved.month == month, resolved.day == day else {
            throw MedicationPlanError.invalidCalendarDate
        }
        return date
    }
}

public enum ReminderTimingRule: Codable, Sendable, Equatable {
    case fixedLocalTimes([TimeOfDay])
    case fixedInterval(start: Date, intervalHours: Int)
}

public enum ReminderTimeZonePolicy: String, Codable, Sendable, Equatable {
    case localClock
    case fixedInterval
}

public struct MedicationPlan: Codable, Identifiable, Sendable, Equatable {
    public let id: UUID
    public var medicationID: UUID
    public var dose: DoseAmount
    public var startDate: DateOnly
    public var endDate: DateOnly?
    public var timingRule: ReminderTimingRule
    public var timeZonePolicy: ReminderTimeZonePolicy
    public var sourceNote: String
    public var requiresUserConfirmation: Bool

    public init(
        id: UUID = UUID(),
        medicationID: UUID,
        dose: DoseAmount,
        startDate: DateOnly,
        endDate: DateOnly? = nil,
        timingRule: ReminderTimingRule,
        timeZonePolicy: ReminderTimeZonePolicy,
        sourceNote: String,
        requiresUserConfirmation: Bool = true
    ) {
        self.id = id
        self.medicationID = medicationID
        self.dose = dose
        self.startDate = startDate
        self.endDate = endDate
        self.timingRule = timingRule
        self.timeZonePolicy = timeZonePolicy
        self.sourceNote = sourceNote
        self.requiresUserConfirmation = requiresUserConfirmation
    }
}

public struct ScheduledDose: Codable, Identifiable, Sendable, Equatable {
    public let id: UUID
    public var planID: UUID
    public var dueAt: Date
    public var dose: DoseAmount

    public init(id: UUID = UUID(), planID: UUID, dueAt: Date, dose: DoseAmount) {
        self.id = id
        self.planID = planID
        self.dueAt = dueAt
        self.dose = dose
    }
}

public enum DoseEventStatus: String, Codable, Sendable, Equatable {
    case taken
    case skipped
    case delayed
    case corrected
}

public struct DoseEvent: Codable, Identifiable, Sendable, Equatable {
    public let id: UUID
    public var scheduledDoseID: UUID
    public var status: DoseEventStatus
    public var recordedAt: Date
    public var reason: String?

    public init(
        id: UUID = UUID(),
        scheduledDoseID: UUID,
        status: DoseEventStatus,
        recordedAt: Date,
        reason: String? = nil
    ) {
        self.id = id
        self.scheduledDoseID = scheduledDoseID
        self.status = status
        self.recordedAt = recordedAt
        self.reason = reason
    }
}

public enum DoseEventTimeline {
    public static func latestByScheduledDoseID(in events: [DoseEvent]) -> [UUID: DoseEvent] {
        events.reduce(into: [:]) { latestEvents, event in
            guard let current = latestEvents[event.scheduledDoseID] else {
                latestEvents[event.scheduledDoseID] = event
                return
            }
            if event.recordedAt > current.recordedAt
                || (event.recordedAt == current.recordedAt && event.id.uuidString > current.id.uuidString)
            {
                latestEvents[event.scheduledDoseID] = event
            }
        }
    }
}

public enum MedicationPlanError: Error, Sendable, Equatable {
    case invalidTimeOfDay
    case invalidInterval
    case invalidCalendarDate
    case invalidDateRange
    case missingEndDateForLocalSchedule
}
