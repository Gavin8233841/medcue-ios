import Foundation
import SwiftData
import UserNotifications

#if canImport(AlarmKit)
import AlarmKit
import SwiftUI
#endif

@MainActor
struct NotificationDoseActionEffects {
    let scheduleReminder: @MainActor (StoredDoseTask, StoredMedication, StoredReminderDeliveryMethod) async -> Void
    let cancelReminder: @MainActor (UUID) -> Void
    let endLiveActivity: @MainActor (UUID) async -> Void
    let startNextLiveActivity: @MainActor (ModelContext) async -> Void
}

@MainActor
final class MedicationNotificationDelegate: NSObject, @preconcurrency UNUserNotificationCenterDelegate {
    static let shared = MedicationNotificationDelegate()
    nonisolated static let categoryIdentifier = "MEDICATION_DOSE_REMINDER"

    private static let markTakenActionIdentifier = "MEDICATION_MARK_TAKEN"
    private static let delayActionIdentifier = "MEDICATION_DELAY_30_MINUTES"
    private static let skipActionIdentifier = "MEDICATION_SKIP"
    private var delayActionTitle: String {
        "\(DoseDelayPolicy.delayMinutes) 分钟后"
    }

    private var modelContainer: ModelContainer?

    private override init() {
        super.init()
    }

    func install(modelContainer: ModelContainer? = nil) {
        if let modelContainer {
            self.modelContainer = modelContainer
        }
        registerNotificationCategories()
        UNUserNotificationCenter.current().delegate = self
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound, .badge]
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        await handleNotificationResponse(response)
    }

    private func registerNotificationCategories() {
        let markTakenAction = UNNotificationAction(
            identifier: Self.markTakenActionIdentifier,
            title: "已服用",
            options: []
        )
        let delayAction = UNNotificationAction(
            identifier: Self.delayActionIdentifier,
            title: delayActionTitle,
            options: []
        )
        let skipAction = UNNotificationAction(
            identifier: Self.skipActionIdentifier,
            title: "忽略",
            options: [.destructive]
        )
        let category = UNNotificationCategory(
            identifier: Self.categoryIdentifier,
            actions: [markTakenAction, delayAction, skipAction],
            intentIdentifiers: [],
            options: [.customDismissAction]
        )
        UNUserNotificationCenter.current().setNotificationCategories([category])
    }

    @MainActor
    private func handleNotificationResponse(_ response: UNNotificationResponse) async {
        guard response.actionIdentifier == Self.markTakenActionIdentifier
            || response.actionIdentifier == Self.delayActionIdentifier
            || response.actionIdentifier == Self.skipActionIdentifier
        else {
            return
        }
        guard let modelContainer,
              let taskID = uuidValue(for: "scheduledDoseID", in: response.notification.request.content.userInfo)
        else {
            return
        }

        let context = ModelContext(modelContainer)
        let effects = NotificationDoseActionEffects(
            scheduleReminder: { task, medication, deliveryMethod in
                await NotificationService().scheduleReminder(
                    for: task,
                    medication: medication,
                    deliveryMethod: deliveryMethod
                )
            },
            cancelReminder: { NotificationService().cancelReminder(for: $0) },
            endLiveActivity: { await MedicationLiveActivityService().end(for: $0) },
            startNextLiveActivity: { [self] in await startNextLiveActivityIfNeeded(in: $0) }
        )
        await handleNotificationAction(
            response.actionIdentifier,
            taskID: taskID,
            in: context,
            occurredAt: Date(),
            effects: effects
        )
    }

    @discardableResult
    func handleNotificationAction(
        _ actionIdentifier: String,
        taskID: UUID,
        in context: ModelContext,
        occurredAt: Date,
        effects: NotificationDoseActionEffects,
        persistence: DoseActionPersistence = DoseActionPersistence()
    ) async -> Bool {
        guard actionIdentifier == Self.markTakenActionIdentifier
            || actionIdentifier == Self.delayActionIdentifier
            || actionIdentifier == Self.skipActionIdentifier else {
            return false
        }
        let tasks = (try? context.fetch(FetchDescriptor<StoredDoseTask>())) ?? []
        guard let task = tasks.first(where: { $0.id == taskID }) else {
            return false
        }
        let taskGroup = DoseLogicalGroup.group(containing: task, in: tasks)
        let openTaskGroup = taskGroup.filter { $0.status == .pending || $0.status == .delayed }
        guard !openTaskGroup.isEmpty else {
            effects.cancelReminder(task.id)
            await effects.endLiveActivity(task.id)
            return false
        }
        let medications = (try? context.fetch(FetchDescriptor<StoredMedication>())) ?? []
        let medication = medications.first { $0.id == task.medicationID }
        let plans = (try? context.fetch(FetchDescriptor<StoredMedicationPlan>())) ?? []
        let plan = plans.first { $0.id == task.planID }
        guard medication?.lifecycleStatus == .active else {
            for groupTask in openTaskGroup {
                effects.cancelReminder(groupTask.id)
                await effects.endLiveActivity(groupTask.id)
            }
            return false
        }

        switch actionIdentifier {
        case Self.markTakenActionIdentifier:
            guard applyNotificationAction(
                mutation: .markTaken,
                to: openTaskGroup,
                primaryTask: task,
                recordedAt: occurredAt,
                reason: "通过通知标记已服用",
                context: context,
                persistence: persistence
            ) else { return false }
            for groupTask in openTaskGroup {
                effects.cancelReminder(groupTask.id)
                await effects.endLiveActivity(groupTask.id)
            }
        case Self.delayActionIdentifier:
            guard applyNotificationAction(
                mutation: .delay,
                to: openTaskGroup,
                primaryTask: task,
                recordedAt: occurredAt,
                reason: "通过通知选择 \(DoseDelayPolicy.delayMinutes) 分钟后提醒",
                context: context,
                persistence: persistence,
                delayedDueAt: occurredAt.addingTimeInterval(TimeInterval(DoseDelayPolicy.delayMinutes * 60))
            ) else { return false }
            if let medication {
                for groupTask in openTaskGroup {
                    if groupTask.id == task.id {
                        await effects.scheduleReminder(groupTask, medication, plan?.reminderDeliveryMethod ?? .notification)
                    } else {
                        effects.cancelReminder(groupTask.id)
                    }
                }
            }
            for groupTask in openTaskGroup {
                await effects.endLiveActivity(groupTask.id)
            }
        case Self.skipActionIdentifier:
            guard applyNotificationAction(
                mutation: .skip,
                to: openTaskGroup,
                primaryTask: task,
                recordedAt: occurredAt,
                reason: "通过通知忽略",
                context: context,
                persistence: persistence
            ) else { return false }
            for groupTask in openTaskGroup {
                effects.cancelReminder(groupTask.id)
                await effects.endLiveActivity(groupTask.id)
            }
        default:
            return false
        }

        await effects.startNextLiveActivity(context)
        return true
    }

    @MainActor
    private func applyNotificationAction(
        mutation: DoseActionMutation,
        to tasks: [StoredDoseTask],
        primaryTask: StoredDoseTask,
        recordedAt: Date,
        reason: String,
        context: ModelContext,
        persistence: DoseActionPersistence,
        delayedDueAt: Date? = nil
    ) -> Bool {
        let transitions = DoseActionTransitionPlanner().makeTransitions(
            mutation: mutation,
            taskGroup: tasks,
            primaryTask: primaryTask,
            occurredAt: recordedAt,
            primaryReason: reason,
            mergedReason: "同一剂量重复提醒已随本次通知操作合并。",
            delayedDueAt: delayedDueAt
        )
        do {
            try persistence.commit(transitions, in: context)
            return true
        } catch {
            AppPersistenceCommitter.reportFailure(operation: "notification-dose-action")
            return false
        }
    }

    @MainActor
    private func startNextLiveActivityIfNeeded(in context: ModelContext) async {
        let tasks = ((try? context.fetch(FetchDescriptor<StoredDoseTask>())) ?? [])
            .filter { $0.status == .pending || $0.status == .delayed }
            .sorted { $0.dueAt < $1.dueAt }
        let medications = (try? context.fetch(FetchDescriptor<StoredMedication>())) ?? []
        let liveActivityService = MedicationLiveActivityService()
        for task in tasks {
            guard let medication = medications.first(where: { $0.id == task.medicationID }),
                  medication.lifecycleStatus == .active
            else {
                await liveActivityService.end(for: task.id)
                continue
            }
            await liveActivityService.startIfNeeded(for: task, medication: medication)
        }
    }

    private func uuidValue(for key: String, in userInfo: [AnyHashable: Any]) -> UUID? {
        guard let rawValue = userInfo[key] as? String else {
            return nil
        }
        return UUID(uuidString: rawValue)
    }
}

#if canImport(AlarmKit)
@available(iOS 26.0, *)
struct MedicationAlarmMetadata: AlarmMetadata {
    let scheduledDoseID: UUID
    let medicationID: UUID
    let planID: UUID
}
#endif
