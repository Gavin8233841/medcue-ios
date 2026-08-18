import Foundation

public enum NotificationAction: String, Codable, Sendable, Equatable {
    case markTaken
    case delay
    case skip
    case viewMedicationPhoto
}

public struct NotificationPayload: Codable, Sendable, Equatable {
    public var scheduledDoseID: UUID
    public var medicationID: UUID
    public var planID: UUID
    public var medicationName: String
    public var doseText: String
    public var photoPath: String?
    public var actions: [NotificationAction]

    public init(
        scheduledDoseID: UUID,
        medicationID: UUID,
        planID: UUID,
        medicationName: String,
        doseText: String,
        photoPath: String? = nil,
        actions: [NotificationAction] = [.markTaken, .delay, .skip, .viewMedicationPhoto]
    ) {
        self.scheduledDoseID = scheduledDoseID
        self.medicationID = medicationID
        self.planID = planID
        self.medicationName = medicationName
        self.doseText = doseText
        self.photoPath = photoPath
        self.actions = photoPath == nil ? actions.filter { $0 != .viewMedicationPhoto } : actions
    }
}

public struct LocalNotificationPlan: Codable, Sendable, Equatable {
    public var identifier: String
    public var title: String
    public var body: String
    public var fireDate: Date
    public var payload: NotificationPayload

    public init(identifier: String, title: String, body: String, fireDate: Date, payload: NotificationPayload) {
        self.identifier = identifier
        self.title = title
        self.body = body
        self.fireDate = fireDate
        self.payload = payload
    }
}

public struct NotificationPlanner: Sendable {
    public init() {}

    public func plans(
        medication: Medication,
        plan: MedicationPlan,
        scheduledDoses: [ScheduledDose]
    ) -> [LocalNotificationPlan] {
        scheduledDoses.map { dose in
            let doseText = "\(dose.dose.value) \(dose.dose.unit)"
            let payload = NotificationPayload(
                scheduledDoseID: dose.id,
                medicationID: medication.id,
                planID: plan.id,
                medicationName: medication.displayName,
                doseText: doseText,
                photoPath: medication.photoPath
            )
            return LocalNotificationPlan(
                identifier: "dose.\(dose.id.uuidString)",
                title: "该服药了",
                body: "\(medication.displayName) · \(doseText)",
                fireDate: dose.dueAt,
                payload: payload
            )
        }
    }
}

public struct TimeZoneReview: Sendable, Equatable {
    public var planID: UUID
    public var oldTimeZoneIdentifier: String
    public var newTimeZoneIdentifier: String
    public var requiresUserReview: Bool
    public var message: String

    public init(
        planID: UUID,
        oldTimeZoneIdentifier: String,
        newTimeZoneIdentifier: String,
        requiresUserReview: Bool,
        message: String
    ) {
        self.planID = planID
        self.oldTimeZoneIdentifier = oldTimeZoneIdentifier
        self.newTimeZoneIdentifier = newTimeZoneIdentifier
        self.requiresUserReview = requiresUserReview
        self.message = message
    }
}

public struct TimeZoneReviewEngine: Sendable {
    public init() {}

    public func review(
        plan: MedicationPlan,
        oldTimeZone: TimeZone,
        newTimeZone: TimeZone
    ) -> TimeZoneReview {
        let changed = oldTimeZone.identifier != newTimeZone.identifier
        let requiresReview = changed
        let message: String
        switch plan.timeZonePolicy {
        case .localClock:
            message = changed
                ? "检测到时区变化。此计划按当地钟点提醒，请确认是否仍按当地时间服药。"
                : "时区未变化。"
        case .fixedInterval:
            message = changed
                ? "检测到时区变化。此计划按固定间隔提醒，请确认跨时区后是否仍符合医嘱。"
                : "时区未变化。"
        }
        return TimeZoneReview(
            planID: plan.id,
            oldTimeZoneIdentifier: oldTimeZone.identifier,
            newTimeZoneIdentifier: newTimeZone.identifier,
            requiresUserReview: requiresReview,
            message: message
        )
    }
}
