import Foundation
import SwiftData
import SwiftUI
import WatchConnectivity
import WidgetKit

struct MedicationWatchSnapshotPublisher {
    func publish(tasks: [StoredDoseTask], medications: [StoredMedication], privacyMode: Bool = true) {
        let snapshot = makeSnapshot(tasks: tasks, medications: medications, privacyMode: privacyMode)
        MedicationWatchSnapshotStore.save(snapshot)
        WidgetCenter.shared.reloadAllTimelines()
        MedicationWatchConnectivityBridge.shared.send(snapshot)
    }

    private func makeSnapshot(tasks: [StoredDoseTask], medications: [StoredMedication], privacyMode: Bool) -> MedicationWatchSnapshot {
        let calendar = Calendar.current
        let activeMedicationIDs = Set(
            medications
                .filter { $0.lifecycleStatus == .active }
                .map(\.id)
        )
        let medicationNames = Dictionary(
            uniqueKeysWithValues: medications.map { medication in
                (medication.id, userFacingMedicationName(for: medication))
            }
        )
        let deduplicatedTasks = tasks
            .filter { task in
                guard task.isAdherenceMeasurable else {
                    return false
                }
                guard activeMedicationIDs.contains(task.medicationID) else {
                    return false
                }
                if calendar.isDateInToday(task.dueAt) {
                    return true
                }
                return task.status == .delayed
                    && task.recordedAt.map(calendar.isDateInToday) == true
            }
            .adherenceMeasurableTasks

        let items = deduplicatedTasks.map { task in
            MedicationWatchDoseItem(
                id: task.id,
                medicationName: medicationNames[task.medicationID] ?? "用药提醒",
                doseText: doseText(for: task),
                dueAt: task.dueAt,
                status: MedicationWatchDoseStatus(storedStatus: task.status)
            )
        }

        return MedicationWatchSnapshot(
            generatedAt: Date(),
            items: items,
            privacyMode: privacyMode
        )
    }

    private func doseText(for task: StoredDoseTask) -> String {
        let value = task.doseValue
        let valueText = value.rounded(.towardZero) == value
            ? String(Int(value))
            : value.formatted(.number.precision(.fractionLength(0...2)))
        return "\(valueText) \(task.doseUnit)"
    }
}

private extension MedicationWatchDoseStatus {
    init(storedStatus: StoredDoseStatus) {
        switch storedStatus {
        case .pending:
            self = .pending
        case .taken:
            self = .taken
        case .delayed:
            self = .delayed
        case .skipped:
            self = .skipped
        case .corrected:
            self = .corrected
        }
    }
}

final class MedicationWatchConnectivityBridge: NSObject, WCSessionDelegate {
    static let shared = MedicationWatchConnectivityBridge()

    private let pendingSnapshotLock = NSLock()
    private var pendingSnapshotData: Data?

    private override init() {
        super.init()
    }

    func activateIfNeeded() {
        guard WCSession.isSupported() else {
            return
        }
        let session = WCSession.default
        if session.delegate == nil {
            session.delegate = self
        }
        if session.activationState == .notActivated {
            session.activate()
        }
    }

    func send(_ snapshot: MedicationWatchSnapshot) {
        guard WCSession.isSupported(), let data = try? JSONEncoder().encode(snapshot) else {
            return
        }

        storePendingSnapshotData(data)
        activateIfNeeded()
        flushPendingSnapshot(using: WCSession.default)
    }

    private func storePendingSnapshotData(_ data: Data) {
        pendingSnapshotLock.lock()
        pendingSnapshotData = data
        pendingSnapshotLock.unlock()
    }

    private func currentPendingSnapshotData() -> Data? {
        pendingSnapshotLock.lock()
        defer { pendingSnapshotLock.unlock() }
        return pendingSnapshotData
    }

    private func clearPendingSnapshotData(ifMatching deliveredData: Data) {
        pendingSnapshotLock.lock()
        defer { pendingSnapshotLock.unlock() }
        if pendingSnapshotData == deliveredData {
            pendingSnapshotData = nil
        }
    }

    private func flushPendingSnapshot(using session: WCSession) {
        guard session.activationState == .activated,
              let data = currentPendingSnapshotData()
        else {
            return
        }

        let payload = ["snapshot": data]
        do {
            try session.updateApplicationContext(payload)
        } catch {
            return
        }
        clearPendingSnapshotData(ifMatching: data)

        if session.isReachable {
            session.sendMessage(payload, replyHandler: nil)
        } else {
            session.transferUserInfo(payload)
        }
    }

    func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        if activationState == .activated {
            flushPendingSnapshot(using: session)
        }
    }

    func sessionReachabilityDidChange(_ session: WCSession) {
        flushPendingSnapshot(using: session)
    }

    func sessionDidBecomeInactive(_ session: WCSession) {}

    func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }
}

private struct MedicationWatchSnapshotRefreshKey: Hashable {
    struct Task: Hashable {
        var id: UUID
        var medicationID: UUID
        var dueAt: Date
        var doseValue: Double
        var doseUnit: String
        var statusRaw: String
        var recordedAt: Date?
        var reason: String
    }

    struct Medication: Hashable {
        var id: UUID
        var displayName: String
        var lifecycleStatusRaw: String
    }

    var tasks: [Task]
    var medications: [Medication]
}

struct MedicationWatchSnapshotSyncHost: View {
    @Environment(\.scenePhase) private var scenePhase
    @Query private var tasks: [StoredDoseTask]
    @Query(sort: \StoredMedication.displayName) private var medications: [StoredMedication]

    private let publisher = MedicationWatchSnapshotPublisher()

    init() {
        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: Date())
        let queryStart = calendar.date(byAdding: .day, value: -1, to: todayStart) ?? todayStart.addingTimeInterval(-86_400)
        let queryEnd = calendar.date(byAdding: .day, value: 2, to: todayStart) ?? todayStart.addingTimeInterval(172_800)
        _tasks = Query(
            filter: #Predicate<StoredDoseTask> { task in
                task.dueAt >= queryStart && task.dueAt < queryEnd
            },
            sort: \StoredDoseTask.dueAt
        )
    }

    private var refreshKey: MedicationWatchSnapshotRefreshKey {
        MedicationWatchSnapshotRefreshKey(
            tasks: tasks.map { task in
                MedicationWatchSnapshotRefreshKey.Task(
                    id: task.id,
                    medicationID: task.medicationID,
                    dueAt: task.dueAt,
                    doseValue: task.doseValue,
                    doseUnit: task.doseUnit,
                    statusRaw: task.statusRaw,
                    recordedAt: task.recordedAt,
                    reason: task.reason
                )
            },
            medications: medications.map { medication in
                MedicationWatchSnapshotRefreshKey.Medication(
                    id: medication.id,
                    displayName: userFacingMedicationName(for: medication),
                    lifecycleStatusRaw: medication.lifecycleStatusRaw
                )
            }
        )
    }

    var body: some View {
        Color.clear
            .task {
                MedicationWatchConnectivityBridge.shared.activateIfNeeded()
            }
            .task(id: refreshKey) {
                publisher.publish(tasks: tasks, medications: medications)
            }
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .active {
                    MedicationWatchConnectivityBridge.shared.activateIfNeeded()
                    publisher.publish(tasks: tasks, medications: medications)
                }
            }
    }
}
