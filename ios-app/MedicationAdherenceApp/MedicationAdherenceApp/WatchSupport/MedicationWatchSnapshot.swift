import Foundation

enum MedicationWatchDoseStatus: String, Codable, Hashable, Sendable {
    case pending
    case taken
    case delayed
    case skipped
    case corrected

    var displayText: String {
        switch self {
        case .pending:
            "待服"
        case .taken:
            "已服"
        case .delayed:
            "稍后"
        case .skipped:
            "忽略"
        case .corrected:
            "修正"
        }
    }

    var isOpen: Bool {
        self == .pending || self == .delayed
    }
}

struct MedicationWatchDoseItem: Codable, Identifiable, Hashable, Sendable {
    var id: UUID
    var medicationName: String
    var doseText: String
    var dueAt: Date
    var status: MedicationWatchDoseStatus

    var timeText: String {
        MedicationWatchSnapshotFormatters.timeString(from: dueAt)
    }
}

enum MedicationWatchDoseTiming: Hashable, Sendable {
    case overdue
    case dueSoon
    case upcoming
}

enum MedicationWatchPresentationState: Equatable, Sendable {
    case awaitingFirstSync
    case stale
    case empty
    case content(isPrivate: Bool)
}

enum MedicationWatchDeliveryAction: Equatable, Sendable {
    case updateApplicationContext(Data)
    case sendMessage(Data)
    case transferUserInfo(Data)
}

struct MedicationWatchDeliveryState: Equatable, Sendable {
    private(set) var latestSnapshotData: Data?
    private(set) var lastQueuedSnapshotData: Data?

    mutating func record(_ data: Data) {
        latestSnapshotData = data
    }

    mutating func actions(isActivated: Bool, isReachable: Bool) -> [MedicationWatchDeliveryAction] {
        guard isActivated, let data = latestSnapshotData else {
            return []
        }
        var actions: [MedicationWatchDeliveryAction] = [.updateApplicationContext(data)]
        if isReachable {
            actions.append(.sendMessage(data))
        } else if lastQueuedSnapshotData != data {
            lastQueuedSnapshotData = data
            actions.append(.transferUserInfo(data))
        }
        return actions
    }
}

struct MedicationWatchSnapshot: Codable, Hashable, Sendable {
    static let storageKey = "MedicationWatchSnapshot.v1"
    static let sharedAppGroupID = "group.com.gwyy.appcontest2026.medicationadherence.watch"

    var generatedAt: Date
    var items: [MedicationWatchDoseItem]
    var privacyMode: Bool

    var openItems: [MedicationWatchDoseItem] {
        items
            .filter { $0.status.isOpen }
            .sorted { lhs, rhs in
                if lhs.dueAt != rhs.dueAt {
                    return lhs.dueAt < rhs.dueAt
                }
                return lhs.id.uuidString < rhs.id.uuidString
            }
    }

    var handledItems: [MedicationWatchDoseItem] {
        items
            .filter { !$0.status.isOpen }
            .sorted { lhs, rhs in
                if lhs.dueAt != rhs.dueAt {
                    return lhs.dueAt > rhs.dueAt
                }
                return lhs.id.uuidString < rhs.id.uuidString
            }
    }

    var nextOpenItem: MedicationWatchDoseItem? {
        openItems.first
    }

    var overdueOpenCount: Int {
        overdueOpenCount(now: Date())
    }

    func overdueOpenCount(now: Date = Date()) -> Int {
        displayOpenItems(now: now).filter { $0.dueAt < now }.count
    }

    var completionText: String {
        guard !items.isEmpty else {
            return "今日暂无计划"
        }
        return "\(handledItems.count)/\(items.count) 已处理"
    }

    var completionCountText: String {
        guard !items.isEmpty else {
            return "无计划"
        }
        return "\(handledItems.count)/\(items.count)"
    }

    var completionProgress: Double {
        guard !items.isEmpty else {
            return 0
        }
        return min(max(Double(handledItems.count) / Double(items.count), 0), 1)
    }

    var isAwaitingFirstSync: Bool {
        generatedAt.timeIntervalSince1970 == 0 && items.isEmpty
    }

    func requiresRefresh(now: Date = Date(), calendar: Calendar = .current) -> Bool {
        generatedAt.timeIntervalSince1970 > 0
            && !calendar.isDate(generatedAt, inSameDayAs: now)
    }

    func presentationState(
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> MedicationWatchPresentationState {
        if isAwaitingFirstSync {
            return .awaitingFirstSync
        }
        if requiresRefresh(now: now, calendar: calendar) {
            return .stale
        }
        if items.isEmpty {
            return .empty
        }
        return .content(isPrivate: privacyMode)
    }

    func displayItems(now: Date = Date(), calendar: Calendar = .current) -> [MedicationWatchDoseItem] {
        requiresRefresh(now: now, calendar: calendar) ? [] : items
    }

    func displayOpenItems(now: Date = Date(), calendar: Calendar = .current) -> [MedicationWatchDoseItem] {
        requiresRefresh(now: now, calendar: calendar) ? [] : openItems
    }

    func displayHandledItems(now: Date = Date(), calendar: Calendar = .current) -> [MedicationWatchDoseItem] {
        requiresRefresh(now: now, calendar: calendar) ? [] : handledItems
    }

    func displayNextOpenItem(now: Date = Date(), calendar: Calendar = .current) -> MedicationWatchDoseItem? {
        displayOpenItems(now: now, calendar: calendar).first
    }

    func displayCompletionText(now: Date = Date(), calendar: Calendar = .current) -> String {
        if requiresRefresh(now: now, calendar: calendar) {
            return "计划需刷新"
        }
        return completionText
    }

    func displayCompletionCountText(now: Date = Date(), calendar: Calendar = .current) -> String {
        if requiresRefresh(now: now, calendar: calendar) {
            return "需刷新"
        }
        return completionCountText
    }

    func displayCompletionProgress(now: Date = Date(), calendar: Calendar = .current) -> Double {
        if requiresRefresh(now: now, calendar: calendar) {
            return 0
        }
        return completionProgress
    }

    func timing(for item: MedicationWatchDoseItem, now: Date = Date()) -> MedicationWatchDoseTiming {
        if item.dueAt < now {
            return .overdue
        }
        if item.dueAt.timeIntervalSince(now) <= 1_800 {
            return .dueSoon
        }
        return .upcoming
    }

    static let empty = MedicationWatchSnapshot(
        generatedAt: Date(timeIntervalSince1970: 0),
        items: [],
        privacyMode: true
    )

    static var previewEmptyPlan: MedicationWatchSnapshot {
        MedicationWatchSnapshot(
            generatedAt: Date().addingTimeInterval(-90),
            items: [],
            privacyMode: false
        )
    }

    static var previewStalePlan: MedicationWatchSnapshot {
        let now = Date()
        let calendar = Calendar.current
        let yesterday = calendar.date(byAdding: .day, value: -1, to: now) ?? now.addingTimeInterval(-86_400)
        return MedicationWatchSnapshot(
            generatedAt: yesterday,
            items: [
                MedicationWatchDoseItem(
                    id: UUID(uuidString: "00000000-0000-0000-0000-000000000301") ?? UUID(),
                    medicationName: "昨日维生素",
                    doseText: "1 粒",
                    dueAt: yesterday.addingTimeInterval(-900),
                    status: .pending
                ),
                MedicationWatchDoseItem(
                    id: UUID(uuidString: "00000000-0000-0000-0000-000000000302") ?? UUID(),
                    medicationName: "昨日钙片",
                    doseText: "2 片",
                    dueAt: yesterday.addingTimeInterval(-7_200),
                    status: .taken
                )
            ],
            privacyMode: false
        )
    }

    static var preview: MedicationWatchSnapshot {
        let now = Date()
        return MedicationWatchSnapshot(
            generatedAt: now.addingTimeInterval(-120),
            items: [
                MedicationWatchDoseItem(
                    id: UUID(uuidString: "00000000-0000-0000-0000-000000000101") ?? UUID(),
                    medicationName: "二甲双胍",
                    doseText: "1 片",
                    dueAt: now.addingTimeInterval(-10_800),
                    status: .taken
                ),
                MedicationWatchDoseItem(
                    id: UUID(uuidString: "00000000-0000-0000-0000-000000000102") ?? UUID(),
                    medicationName: "维生素 D",
                    doseText: "1 粒",
                    dueAt: now.addingTimeInterval(-900),
                    status: .delayed
                ),
                MedicationWatchDoseItem(
                    id: UUID(uuidString: "00000000-0000-0000-0000-000000000103") ?? UUID(),
                    medicationName: "阿托伐他汀",
                    doseText: "1 片",
                    dueAt: now.addingTimeInterval(1_200),
                    status: .pending
                ),
                MedicationWatchDoseItem(
                    id: UUID(uuidString: "00000000-0000-0000-0000-000000000104") ?? UUID(),
                    medicationName: "钙片",
                    doseText: "2 片",
                    dueAt: now.addingTimeInterval(14_400),
                    status: .pending
                )
            ],
            privacyMode: false
        )
    }

    static var previewPrivacy: MedicationWatchSnapshot {
        var snapshot = preview
        snapshot.privacyMode = true
        return snapshot
    }

    static var previewLongDay: MedicationWatchSnapshot {
        let now = Date()
        return MedicationWatchSnapshot(
            generatedAt: now.addingTimeInterval(-180),
            items: [
                MedicationWatchDoseItem(
                    id: UUID(uuidString: "00000000-0000-0000-0000-000000000401") ?? UUID(),
                    medicationName: "二甲双胍",
                    doseText: "1 片",
                    dueAt: now.addingTimeInterval(-18_000),
                    status: .taken
                ),
                MedicationWatchDoseItem(
                    id: UUID(uuidString: "00000000-0000-0000-0000-000000000402") ?? UUID(),
                    medicationName: "降压药",
                    doseText: "1 片",
                    dueAt: now.addingTimeInterval(-14_400),
                    status: .corrected
                ),
                MedicationWatchDoseItem(
                    id: UUID(uuidString: "00000000-0000-0000-0000-000000000403") ?? UUID(),
                    medicationName: "维生素 B",
                    doseText: "1 粒",
                    dueAt: now.addingTimeInterval(-10_800),
                    status: .skipped
                ),
                MedicationWatchDoseItem(
                    id: UUID(uuidString: "00000000-0000-0000-0000-000000000404") ?? UUID(),
                    medicationName: "维生素 D",
                    doseText: "1 粒",
                    dueAt: now.addingTimeInterval(-2_400),
                    status: .delayed
                ),
                MedicationWatchDoseItem(
                    id: UUID(uuidString: "00000000-0000-0000-0000-000000000405") ?? UUID(),
                    medicationName: "阿托伐他汀",
                    doseText: "1 片",
                    dueAt: now.addingTimeInterval(-1_200),
                    status: .pending
                ),
                MedicationWatchDoseItem(
                    id: UUID(uuidString: "00000000-0000-0000-0000-000000000406") ?? UUID(),
                    medicationName: "钙片",
                    doseText: "2 片",
                    dueAt: now.addingTimeInterval(1_200),
                    status: .pending
                ),
                MedicationWatchDoseItem(
                    id: UUID(uuidString: "00000000-0000-0000-0000-000000000407") ?? UUID(),
                    medicationName: "益生菌",
                    doseText: "1 包",
                    dueAt: now.addingTimeInterval(3_600),
                    status: .pending
                ),
                MedicationWatchDoseItem(
                    id: UUID(uuidString: "00000000-0000-0000-0000-000000000408") ?? UUID(),
                    medicationName: "鱼油",
                    doseText: "1 粒",
                    dueAt: now.addingTimeInterval(7_200),
                    status: .pending
                ),
                MedicationWatchDoseItem(
                    id: UUID(uuidString: "00000000-0000-0000-0000-000000000409") ?? UUID(),
                    medicationName: "叶酸",
                    doseText: "1 片",
                    dueAt: now.addingTimeInterval(10_800),
                    status: .pending
                ),
                MedicationWatchDoseItem(
                    id: UUID(uuidString: "00000000-0000-0000-0000-000000000410") ?? UUID(),
                    medicationName: "镁片",
                    doseText: "1 片",
                    dueAt: now.addingTimeInterval(14_400),
                    status: .pending
                ),
                MedicationWatchDoseItem(
                    id: UUID(uuidString: "00000000-0000-0000-0000-000000000411") ?? UUID(),
                    medicationName: "褪黑素",
                    doseText: "1 粒",
                    dueAt: now.addingTimeInterval(18_000),
                    status: .pending
                ),
                MedicationWatchDoseItem(
                    id: UUID(uuidString: "00000000-0000-0000-0000-000000000412") ?? UUID(),
                    medicationName: "睡前药",
                    doseText: "1 片",
                    dueAt: now.addingTimeInterval(21_600),
                    status: .pending
                )
            ],
            privacyMode: false
        )
    }

    static var previewOverdueOnly: MedicationWatchSnapshot {
        let now = Date()
        return MedicationWatchSnapshot(
            generatedAt: now.addingTimeInterval(-300),
            items: [
                MedicationWatchDoseItem(
                    id: UUID(uuidString: "00000000-0000-0000-0000-000000000201") ?? UUID(),
                    medicationName: "二甲双胍",
                    doseText: "1 片",
                    dueAt: now.addingTimeInterval(-14_400),
                    status: .taken
                ),
                MedicationWatchDoseItem(
                    id: UUID(uuidString: "00000000-0000-0000-0000-000000000202") ?? UUID(),
                    medicationName: "阿托伐他汀",
                    doseText: "1 片",
                    dueAt: now.addingTimeInterval(-1_800),
                    status: .delayed
                )
            ],
            privacyMode: false
        )
    }
}

enum MedicationWatchSnapshotStore {
    static var defaults: UserDefaults {
        UserDefaults(suiteName: MedicationWatchSnapshot.sharedAppGroupID) ?? .standard
    }

    static func load() -> MedicationWatchSnapshot {
        guard let data = defaults.data(forKey: MedicationWatchSnapshot.storageKey),
              let snapshot = try? JSONDecoder().decode(MedicationWatchSnapshot.self, from: data)
        else {
            return .empty
        }
        return snapshot
    }

    static func save(_ snapshot: MedicationWatchSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else {
            return
        }
        defaults.set(data, forKey: MedicationWatchSnapshot.storageKey)
    }
}

enum MedicationWatchSnapshotFormatters {
    static func timeString(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    static func relativeDateString(for date: Date, relativeTo referenceDate: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: referenceDate)
    }
}
