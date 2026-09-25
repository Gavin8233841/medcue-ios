import Foundation
import MedicationAdherenceCore

@MainActor
enum MedicationReminderNotificationReadback {
    static func converge(
        targetedPendingIDs: Set<String>,
        readPendingIDs: @MainActor () async -> Set<String>,
        readDeliveredIDs: @MainActor () async -> Set<String>,
        unwantedDeliveredIDs: @MainActor (Set<String>) -> Set<String>,
        removePendingIDs: @MainActor (Set<String>) -> Void,
        removeDeliveredIDs: @MainActor (Set<String>) -> Void,
        pause: @MainActor () async -> Void
    ) async -> (pendingIDs: Set<String>, remainingDeliveredIDs: Set<String>) {
        var pendingIDs = await readPendingIDs()
        var deliveredIDs = await readDeliveredIDs()
        for _ in 0..<6 {
            let remainingPendingIDs = targetedPendingIDs.intersection(pendingIDs)
            let undesiredDeliveredIDs = unwantedDeliveredIDs(deliveredIDs)
            if remainingPendingIDs.isEmpty && undesiredDeliveredIDs.isEmpty { break }
            if !remainingPendingIDs.isEmpty { removePendingIDs(remainingPendingIDs) }
            if !undesiredDeliveredIDs.isEmpty { removeDeliveredIDs(undesiredDeliveredIDs) }
            await pause()
            pendingIDs = await readPendingIDs()
            deliveredIDs = await readDeliveredIDs()
        }
        // One final read reports any request that changed state during the last await.
        pendingIDs = await readPendingIDs()
        deliveredIDs = await readDeliveredIDs()
        return (pendingIDs, unwantedDeliveredIDs(deliveredIDs))
    }
}

enum MedicationNotificationAuthorizationStatus: Equatable, Sendable {
    case notDetermined
    case denied
    case authorized
    case unknown
}

enum MedicationNotificationAuthorizationDisposition: Equatable, Sendable {
    case notDetermined
    case denied
    case presentationDisabled
    case soundDisabled
    case usable
    case unknown
}

struct MedicationNotificationPolicy: Equatable, Sendable {
    let maximumScheduledRequests: Int

    static let `default` = MedicationNotificationPolicy(maximumScheduledRequests: 60)

    func triggerDateComponents(for date: Date, calendar: Calendar) -> DateComponents {
        var components = calendar.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: date
        )
        components.calendar = calendar
        components.timeZone = calendar.timeZone
        return components
    }

    func authorizationDisposition(
        status: MedicationNotificationAuthorizationStatus,
        hasPresentationSurface: Bool,
        hasSound: Bool
    ) -> MedicationNotificationAuthorizationDisposition {
        switch status {
        case .notDetermined:
            .notDetermined
        case .denied:
            .denied
        case .unknown:
            .unknown
        case .authorized:
            if !hasPresentationSurface {
                .presentationDisabled
            } else if !hasSound {
                .soundDisabled
            } else {
                .usable
            }
        }
    }

    func unavailableMessage(for disposition: MedicationNotificationAuthorizationDisposition) -> String? {
        switch disposition {
        case .notDetermined:
            "普通提醒不可用：尚未获得通知权限，请允许通知后再安排。"
        case .denied:
            "普通提醒不可用：通知权限未开启，请在系统设置中允许通知。"
        case .presentationDisabled:
            "普通提醒不可用：系统通知显示已关闭，请在设置中开启横幅、锁定屏幕或通知中心。"
        case .soundDisabled:
            "普通提醒不可用：系统通知声音已关闭，请在设置中开启声音或改用 iPhone 闹钟提醒。"
        case .usable:
            nil
        case .unknown:
            "普通提醒不可用：通知权限状态未知，请前往系统设置检查。"
        }
    }
}

// The limit is an app scheduling policy, not a claim about an OS delivery limit.
// A dose can occupy multiple system requests: a notification, an optional
// AlarmKit alarm, and an escalation request.
enum MedicationReminderRequestKind: Sendable, Hashable {
    case baseNotification
    case baseAlarm
    case escalationNotification
    case escalationAlarm
}

struct MedicationReminderRequestCandidate: Sendable, Equatable {
    let taskID: UUID
    // The next system request time; this is the escalation time after a base reminder has fired.
    let dueAt: Date
    let wantsAlarm: Bool
    let wantsEscalation: Bool
    let wantsBase: Bool
    let escalationDueAt: Date

    init(
        taskID: UUID,
        dueAt: Date,
        wantsAlarm: Bool,
        wantsEscalation: Bool,
        wantsBase: Bool = true,
        escalationDueAt: Date? = nil
    ) {
        self.taskID = taskID
        self.dueAt = dueAt
        self.wantsAlarm = wantsAlarm
        self.wantsEscalation = wantsEscalation
        self.wantsBase = wantsBase
        self.escalationDueAt = escalationDueAt ?? (wantsBase
            ? DoseReminderPolicy.competitionDemo.escalationDueAt(for: dueAt) : dueAt)
    }
}

struct MedicationReminderRequestAssignment: Sendable, Equatable {
    let taskID: UUID
    let kinds: [MedicationReminderRequestKind]
}

struct MedicationReminderPlannedRequest: Sendable, Equatable {
    let taskID: UUID
    let dueAt: Date
    let kind: MedicationReminderRequestKind
    let isOptional: Bool
}

struct MedicationReminderRequestExecutionQueue {
    private var requests: [MedicationReminderPlannedRequest]

    init(_ requests: [MedicationReminderPlannedRequest]) {
        self.requests = requests
    }

    mutating func next() -> MedicationReminderPlannedRequest? {
        guard !requests.isEmpty else { return nil }
        return requests.removeFirst()
    }

    mutating func insertEscalation(_ request: MedicationReminderPlannedRequest) {
        let insertionIndex = requests.firstIndex {
            $0.isOptional || $0.dueAt > request.dueAt
                || ($0.dueAt == request.dueAt && $0.taskID.uuidString > request.taskID.uuidString)
        } ?? requests.endIndex
        requests.insert(request, at: insertionIndex)
    }
}

struct MedicationReminderRequestPlan: Sendable, Equatable {
    let assignments: [MedicationReminderRequestAssignment]
    let orderedRequests: [MedicationReminderPlannedRequest]
    let deferredTaskIDs: [UUID]
    let unavailableTaskIDs: [UUID]
}

extension MedicationNotificationPolicy {
    func requestPlan(
        candidates: [MedicationReminderRequestCandidate],
        occupiedRequestCount: Int,
        notificationAvailable: Bool,
        alarmAvailable: Bool
    ) -> MedicationReminderRequestPlan {
        struct Event {
            let taskID: UUID
            let dueAt: Date
            let kind: MedicationReminderRequestKind
            let priority: Int
        }
        func eventOrder(_ lhs: Event, _ rhs: Event) -> Bool {
            if lhs.dueAt != rhs.dueAt { return lhs.dueAt < rhs.dueAt }
            if lhs.priority != rhs.priority { return lhs.priority < rhs.priority }
            return lhs.taskID.uuidString < rhs.taskID.uuidString
        }

        var seenTaskIDs: Set<UUID> = []
        let uniqueCandidates = candidates.sorted {
            $0.dueAt == $1.dueAt
                ? $0.taskID.uuidString < $1.taskID.uuidString
                : $0.dueAt < $1.dueAt
        }
            .filter { seenTaskIDs.insert($0.taskID).inserted }
        var requiredEvents: [Event] = []
        var optionalEvents: [Event] = []
        var unavailable: [UUID] = []
        for candidate in uniqueCandidates {
            if !candidate.wantsBase && !candidate.wantsEscalation {
                unavailable.append(candidate.taskID)
                continue
            }
            let baseKind: MedicationReminderRequestKind?
            if candidate.wantsBase {
                if candidate.wantsAlarm && alarmAvailable {
                    baseKind = .baseAlarm
                } else if notificationAvailable {
                    baseKind = .baseNotification
                } else {
                    baseKind = nil
                }
                guard let baseKind else {
                    unavailable.append(candidate.taskID)
                    continue
                }
                requiredEvents.append(Event(
                    taskID: candidate.taskID, dueAt: candidate.dueAt,
                    kind: baseKind, priority: 0
                ))
                if baseKind == .baseAlarm && notificationAvailable {
                    optionalEvents.append(Event(
                        taskID: candidate.taskID, dueAt: candidate.dueAt,
                        kind: .baseNotification, priority: 2
                    ))
                }
            }
            if candidate.wantsEscalation {
                let escalationKind: MedicationReminderRequestKind?
                if alarmAvailable {
                    escalationKind = .escalationAlarm
                } else if notificationAvailable {
                    escalationKind = .escalationNotification
                } else {
                    escalationKind = nil
                }
                if let escalationKind {
                    requiredEvents.append(Event(
                        taskID: candidate.taskID, dueAt: candidate.escalationDueAt,
                        kind: escalationKind, priority: 1
                    ))
                } else if !candidate.wantsBase {
                    unavailable.append(candidate.taskID)
                }
            }
        }
        let availableSlots = max(0, maximumScheduledRequests - max(0, occupiedRequestCount))
        let selectedEvents = Array((requiredEvents.sorted(by: eventOrder)
            + optionalEvents.sorted(by: eventOrder)).prefix(availableSlots))
        let kindsByTaskID = Dictionary(grouping: selectedEvents, by: \.taskID)
            .mapValues { Set($0.map(\.kind)) }
        let kindOrder: [MedicationReminderRequestKind] = [
            .baseNotification, .baseAlarm, .escalationNotification, .escalationAlarm
        ]
        let assigned = uniqueCandidates.compactMap { candidate -> MedicationReminderRequestAssignment? in
            guard let selected = kindsByTaskID[candidate.taskID] else { return nil }
            return MedicationReminderRequestAssignment(
                taskID: candidate.taskID,
                kinds: kindOrder.filter { selected.contains($0) }
            )
        }
        let unavailableIDs = Set(unavailable)
        let deferred = uniqueCandidates.map(\.taskID).filter {
            !unavailableIDs.contains($0) && kindsByTaskID[$0] == nil
        }
        return MedicationReminderRequestPlan(
            assignments: assigned,
            orderedRequests: selectedEvents.map {
                MedicationReminderPlannedRequest(
                    taskID: $0.taskID, dueAt: $0.dueAt, kind: $0.kind,
                    isOptional: $0.priority == 2
                )
            },
            deferredTaskIDs: deferred,
            unavailableTaskIDs: unavailable
        )
    }
}
