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
    let maximumScheduledEntries: Int

    static let `default` = MedicationNotificationPolicy(maximumScheduledEntries: 60)

    func nearTermEntries<Element>(from entries: [Element]) -> ArraySlice<Element> {
        entries.prefix(max(0, maximumScheduledEntries))
    }

    func boundedUniqueEntries<Element, ID: Hashable>(
        from entries: [Element],
        identifiedBy keyPath: KeyPath<Element, ID>
    ) -> [Element] {
        var seen: Set<ID> = []
        let uniqueEntries = entries.filter { entry in
            seen.insert(entry[keyPath: keyPath]).inserted
        }
        return Array(nearTermEntries(from: uniqueEntries))
    }

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
