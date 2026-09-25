import Foundation

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
    let dueAt: Date
    let wantsAlarm: Bool
    let wantsEscalation: Bool
}

struct MedicationReminderRequestAssignment: Sendable, Equatable {
    let taskID: UUID
    let kinds: [MedicationReminderRequestKind]
}

struct MedicationReminderRequestPlan: Sendable, Equatable {
    let assignments: [MedicationReminderRequestAssignment]
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
        var remaining = max(0, maximumScheduledRequests - max(0, occupiedRequestCount))
        var assigned: [MedicationReminderRequestAssignment] = []
        var deferred: [UUID] = []
        var unavailable: [UUID] = []
        var seen: Set<UUID> = []
        var reachedCapacity = false
        for candidate in candidates.sorted(by: {
            $0.dueAt == $1.dueAt
                ? $0.taskID.uuidString < $1.taskID.uuidString
                : $0.dueAt < $1.dueAt
        }) where seen.insert(candidate.taskID).inserted {
            var kinds: [MedicationReminderRequestKind] = []
            if notificationAvailable {
                kinds.append(.baseNotification)
            }
            if candidate.wantsAlarm && alarmAvailable {
                kinds.append(.baseAlarm)
            }
            guard !kinds.isEmpty else {
                unavailable.append(candidate.taskID)
                continue
            }
            if candidate.wantsEscalation {
                if alarmAvailable {
                    kinds.append(.escalationAlarm)
                } else if notificationAvailable {
                    kinds.append(.escalationNotification)
                }
            }
            guard !reachedCapacity && remaining > 0 else {
                reachedCapacity = true
                deferred.append(candidate.taskID)
                continue
            }
            if kinds.count > remaining {
                // Preserve the selected base delivery before optional escalation
                // and the second base channel when the request budget is tight.
                var priority: [MedicationReminderRequestKind] = [
                    candidate.wantsAlarm && alarmAvailable ? .baseAlarm : .baseNotification
                ]
                if candidate.wantsEscalation {
                    priority.append(alarmAvailable ? .escalationAlarm : .escalationNotification)
                }
                if candidate.wantsAlarm && notificationAvailable && alarmAvailable {
                    priority.append(.baseNotification)
                }
                let selected = Set(priority.prefix(remaining))
                kinds = kinds.filter { selected.contains($0) }
            }
            remaining -= kinds.count
            reachedCapacity = remaining == 0
            assigned.append(MedicationReminderRequestAssignment(taskID: candidate.taskID, kinds: kinds))
        }
        return MedicationReminderRequestPlan(
            assignments: assigned,
            deferredTaskIDs: deferred,
            unavailableTaskIDs: unavailable
        )
    }
}
