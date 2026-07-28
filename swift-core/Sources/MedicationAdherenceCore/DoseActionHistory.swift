import Foundation

public enum DoseActionKind: String, Codable, Sendable, Equatable {
    case markTaken
    case delay
    case skip
    case correct
    case archiveToday
    case restoreArchive
}

public struct DoseActionRecord: Codable, Identifiable, Sendable, Equatable {
    public let id: UUID
    public var scheduledDoseID: UUID
    public var action: DoseActionKind
    public var previousStatus: DoseEventStatus?
    public var newStatus: DoseEventStatus
    public var occurredAt: Date
    public var undoExpiresAt: Date?
    public var note: String

    public init(
        id: UUID = UUID(),
        scheduledDoseID: UUID,
        action: DoseActionKind,
        previousStatus: DoseEventStatus?,
        newStatus: DoseEventStatus,
        occurredAt: Date = Date(),
        undoExpiresAt: Date? = nil,
        note: String = ""
    ) {
        self.id = id
        self.scheduledDoseID = scheduledDoseID
        self.action = action
        self.previousStatus = previousStatus
        self.newStatus = newStatus
        self.occurredAt = occurredAt
        self.undoExpiresAt = undoExpiresAt
        self.note = note
    }

    public func canUndo(at date: Date = Date()) -> Bool {
        guard let undoExpiresAt else {
            return true
        }
        return date <= undoExpiresAt
    }
}

public struct DoseActionHistoryBuilder: Sendable {
    private let undoWindowSeconds: TimeInterval

    public init(undoWindowSeconds: TimeInterval = 300) {
        self.undoWindowSeconds = undoWindowSeconds
    }

    public func record(
        scheduledDoseID: UUID,
        action: DoseActionKind,
        previousStatus: DoseEventStatus?,
        occurredAt: Date = Date(),
        note: String = ""
    ) -> DoseActionRecord {
        DoseActionRecord(
            scheduledDoseID: scheduledDoseID,
            action: action,
            previousStatus: previousStatus,
            newStatus: status(for: action, previousStatus: previousStatus),
            occurredAt: occurredAt,
            undoExpiresAt: occurredAt.addingTimeInterval(undoWindowSeconds),
            note: note
        )
    }

    private func status(for action: DoseActionKind, previousStatus: DoseEventStatus?) -> DoseEventStatus {
        switch action {
        case .markTaken:
            .taken
        case .delay:
            .delayed
        case .skip:
            .skipped
        case .correct:
            .corrected
        case .archiveToday, .restoreArchive:
            previousStatus ?? .corrected
        }
    }
}
