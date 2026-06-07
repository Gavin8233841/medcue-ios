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

public struct DoseAmount: Codable, Sendable, Equatable {
    public var value: Decimal
    public var unit: String

    public init(value: Decimal, unit: String) {
        self.value = value
        self.unit = unit
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

    public static func < (lhs: DateOnly, rhs: DateOnly) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
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

public enum MedicationPlanError: Error, Sendable, Equatable {
    case invalidTimeOfDay
    case invalidInterval
    case invalidDateRange
    case missingEndDateForLocalSchedule
}
