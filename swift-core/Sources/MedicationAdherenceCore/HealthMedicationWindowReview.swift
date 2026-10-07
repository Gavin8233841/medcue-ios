import Foundation

/// Raw, read-only values captured by the medication adapter. No event conversion.
public struct HealthMedicationWindowRecord: Equatable, Sendable {
    public let taskID: UUID
    public let medicationID: UUID
    /// Nil when the relationship or its readable name is unavailable.
    public let medicationName: String?
    /// The current saved reminder time, which may have changed after postponement.
    public let dueAt: Date
    public let statusRaw: String
    /// A saved record timestamp, not proof of when medication was actually taken.
    public let recordedAt: Date?

    public init(taskID: UUID, medicationID: UUID, medicationName: String?,
                dueAt: Date, statusRaw: String, recordedAt: Date?) {
        self.taskID = taskID
        self.medicationID = medicationID
        self.medicationName = medicationName
        self.dueAt = dueAt
        self.statusRaw = statusRaw
        self.recordedAt = recordedAt
    }

    /// Exact raw mapping: an unsupported value must not become pending.
    public var status: HealthMedicationWindowRecordStatus {
        HealthMedicationWindowRecordStatus(rawValue: statusRaw) ?? .unknown
    }

    public var isMedicationInformationAvailable: Bool {
        guard let medicationName else { return false }
        return !medicationName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

public enum HealthMedicationWindowRecordStatus: String, Sendable {
    case taken, pending, delayed, skipped, corrected, unknown

    public var displayName: String {
        switch self {
        case .taken: "记录为已服"
        case .pending: "尚未确认"
        case .delayed: "稍后提醒"
        case .skipped: "已忽略"
        case .corrected: "已修正"
        case .unknown: "未知状态"
        }
    }
}

public enum HealthMedicationWindowReadStatus: String, Sendable {
    /// The adapter completed its authorized read without truncation.
    case success
    case failure
    /// The adapter cannot supply a complete read within its allowed budget.
    case budgetExceeded
}

public struct HealthMedicationWindowReviewInput: Equatable, Sendable {
    /// Explicit half-open window. The caller supplies existing health-period bounds.
    public let start: Date
    public let end: Date
    public let timeZoneIdentifier: String
    public let healthGeneratedAt: Date?
    /// Medication capture/read-attempt time, independent of the health snapshot.
    public let medicationSnapshotAt: Date
    public let readStatus: HealthMedicationWindowReadStatus
    public let records: [HealthMedicationWindowRecord]

    public init(start: Date, end: Date, timeZoneIdentifier: String,
                healthGeneratedAt: Date?, medicationSnapshotAt: Date,
                readStatus: HealthMedicationWindowReadStatus,
                records: [HealthMedicationWindowRecord]) {
        self.start = start
        self.end = end
        self.timeZoneIdentifier = timeZoneIdentifier
        self.healthGeneratedAt = healthGeneratedAt
        self.medicationSnapshotAt = medicationSnapshotAt
        self.readStatus = readStatus
        self.records = records
    }
}

public enum HealthMedicationWindowReviewAvailability: String, Sendable {
    case recordsAvailable, empty, readFailed, budgetExceeded, invalidInput
}

public enum HealthMedicationWindowInvalidReason: String, Sendable {
    case nonFiniteWindow, emptyOrReversedWindow, invalidTimeZone
    case nonFiniteSnapshotTime, nonFiniteRecordTime, duplicateTaskID
}

public struct HealthMedicationWindowReviewRow: Equatable, Sendable {
    public let record: HealthMedicationWindowRecord
    /// True only for a present timestamp outside [start, end). Nil remains nil.
    public let isRecordedAtOutsideWindow: Bool
}

public struct HealthMedicationWindowReviewResult: Equatable, Sendable {
    public let start: Date
    public let end: Date
    public let timeZoneIdentifier: String
    public let healthGeneratedAt: Date?
    public let medicationSnapshotAt: Date
    public let readStatus: HealthMedicationWindowReadStatus
    public let availability: HealthMedicationWindowReviewAvailability
    public let rows: [HealthMedicationWindowReviewRow]
    public let invalidReasons: [HealthMedicationWindowInvalidReason]
    /// IDs with duplicate identities or non-finite record dates, in stable order.
    public let invalidTaskIDs: [UUID]

    /// Number of saved task records, never a count of medication taken.
    /// Failure, invalid input and exhausted budgets are unknown, not zero.
    public var recordCount: Int? {
        switch availability {
        case .recordsAvailable, .empty: rows.count
        case .readFailed, .budgetExceeded, .invalidInput: nil
        }
    }

    public var windowMembershipExplanation: String {
        "按当前保存的提醒时间归入此时段；记录时间可能在时段外"
    }
}

/// A pure projection for a future read-only list. It does not read, write, join
/// health samples, infer medication effects, or calculate adherence or doses.
public struct HealthMedicationWindowReview: Sendable {
    public init() {}

    public func build(_ input: HealthMedicationWindowReviewInput) -> HealthMedicationWindowReviewResult {
        var reasons: [HealthMedicationWindowInvalidReason] = []
        var invalidTaskIDs = Set<UUID>()
        func result(_ availability: HealthMedicationWindowReviewAvailability,
                    rows: [HealthMedicationWindowReviewRow] = []) -> HealthMedicationWindowReviewResult {
            HealthMedicationWindowReviewResult(
                start: input.start, end: input.end,
                timeZoneIdentifier: input.timeZoneIdentifier,
                healthGeneratedAt: input.healthGeneratedAt,
                medicationSnapshotAt: input.medicationSnapshotAt,
                readStatus: input.readStatus, availability: availability,
                rows: rows, invalidReasons: reasons,
                invalidTaskIDs: invalidTaskIDs.sorted { $0.uuidString < $1.uuidString })
        }

        // Do not construct DateInterval or perform date ordering before validation.
        if !isFinite(input.start) || !isFinite(input.end) {
            reasons.append(.nonFiniteWindow)
        } else if input.start >= input.end {
            reasons.append(.emptyOrReversedWindow)
        }
        if TimeZone(identifier: input.timeZoneIdentifier) == nil {
            reasons.append(.invalidTimeZone)
        }
        if !isFinite(input.medicationSnapshotAt)
            || input.healthGeneratedAt.map({ !isFinite($0) }) == true {
            reasons.append(.nonFiniteSnapshotTime)
        }

        var seen = Set<UUID>()
        var hasNonFiniteRecordTime = false
        var hasDuplicateTaskID = false
        // Validate all input rows, including those outside the window. Otherwise
        // conflicting copies could be hidden by filtering or arbitrary selection.
        for record in input.records {
            if !isFinite(record.dueAt) || record.recordedAt.map({ !isFinite($0) }) == true {
                hasNonFiniteRecordTime = true
                invalidTaskIDs.insert(record.taskID)
            }
            if !seen.insert(record.taskID).inserted {
                hasDuplicateTaskID = true
                invalidTaskIDs.insert(record.taskID)
            }
        }
        if hasNonFiniteRecordTime { reasons.append(.nonFiniteRecordTime) }
        if hasDuplicateTaskID { reasons.append(.duplicateTaskID) }
        guard reasons.isEmpty else { return result(.invalidInput) }

        switch input.readStatus {
        case .failure: return result(.readFailed)
        case .budgetExceeded: return result(.budgetExceeded)
        case .success: break
        }

        let rows = input.records.filter {
            $0.dueAt >= input.start && $0.dueAt < input.end
        }.sorted {
            if $0.dueAt == $1.dueAt { return $0.taskID.uuidString < $1.taskID.uuidString }
            return $0.dueAt < $1.dueAt
        }.map { record in
            HealthMedicationWindowReviewRow(record: record,
                isRecordedAtOutsideWindow: record.recordedAt.map {
                    $0 < input.start || $0 >= input.end
                } ?? false)
        }
        return result(rows.isEmpty ? .empty : .recordsAvailable, rows: rows)
    }

    private func isFinite(_ date: Date) -> Bool {
        date.timeIntervalSince1970.isFinite
    }
}
