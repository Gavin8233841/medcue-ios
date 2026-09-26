import Foundation

#if canImport(ActivityKit)
import ActivityKit
#endif

struct MedicationLiveActivityPolicy: Equatable, Sendable {
    let activationWindow: TimeInterval
    let staleWindow: TimeInterval

    static let `default` = MedicationLiveActivityPolicy(activationWindow: 5 * 60, staleWindow: 10 * 60)
}

@MainActor
final class MedicationLiveActivityService: ObservableObject {
    private let policy = MedicationLiveActivityPolicy.default

    func startIfNeeded(for task: StoredDoseTask, medication: StoredMedication?) async {
        #if canImport(ActivityKit)
        guard #available(iOS 16.2, *) else {
            return
        }
        guard medication?.lifecycleStatus == .active else {
            await end(for: task.id)
            return
        }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            return
        }
        guard task.status == .pending || task.status == .delayed else {
            await end(for: task.id)
            return
        }
        guard abs(task.dueAt.timeIntervalSinceNow) <= policy.activationWindow else {
            return
        }
        for activity in Activity<MedicationReminderActivityAttributes>.activities where activity.attributes.taskID == task.id {
            if activity.attributes.medicationName == MedicationSystemSurfacePrivacyPolicy.reminderTitle,
               activity.attributes.doseText.isEmpty {
                return
            }
            // Replace an activity created by an older build that stored details.
            await activity.end(activity.content, dismissalPolicy: .immediate)
        }

        let attributes = MedicationSystemSurfacePrivacyPolicy.activityAttributes(taskID: task.id)
        let state = MedicationReminderActivityAttributes.ContentState(
            dueAt: task.dueAt,
            statusText: task.status == .delayed ? "稍后提醒" : "该服药了",
            completedAt: nil
        )
        do {
            _ = try Activity.request(
                attributes: attributes,
                content: ActivityContent(state: state, staleDate: task.dueAt.addingTimeInterval(policy.staleWindow)),
                pushType: nil
            )
        } catch {
            return
        }
        #endif
    }

    func end(for taskID: UUID) async {
        #if canImport(ActivityKit)
        guard #available(iOS 16.2, *) else {
            return
        }
        for activity in Activity<MedicationReminderActivityAttributes>.activities where activity.attributes.taskID == taskID {
            let state = MedicationReminderActivityAttributes.ContentState(
                dueAt: Date(),
                statusText: MedicationSystemSurfacePrivacyPolicy.completedTitle,
                completedAt: Date()
            )
            await activity.end(
                ActivityContent(state: state, staleDate: nil),
                dismissalPolicy: .immediate
            )
        }
        #endif
    }
}
