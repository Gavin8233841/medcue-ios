import Foundation

struct MedicationLifecycleClassification: Equatable {
    enum Reason: Equatable {
        case explicitStatus
        case courseEnded(daysAgo: Int)
        case noRecentCompletion(days: Int)
        case skippedRecentSchedule(days: Int)
        case ongoing
        case archived
    }

    let displayStatus: StoredMedicationLifecycleStatus
    let reason: Reason
    let shouldPromptReview: Bool

    var explanation: String {
        switch reason {
        case .explicitStatus:
            return "用户已手动设置当前状态。"
        case let .courseEnded(daysAgo):
            return "疗程结束已超过 \(daysAgo) 天，建议复核是否继续展示为正在服用。"
        case let .noRecentCompletion(days):
            return "近 \(days) 天没有已服用或已修正记录，建议复核是否已中断。"
        case let .skippedRecentSchedule(days):
            return "近 \(days) 天内排期记录均未完成，建议复核是否已中断。"
        case .ongoing:
            return "近期仍有计划或记录，保持正在服用。"
        case .archived:
            return "已归档，不参与当前用药提醒。"
        }
    }
}

struct MedicationLifecycleClassifier {
    var interruptionWindowDays = 14
    var courseEndGraceDays = 1
    var calendar = Calendar.current

    func classify(
        medication: StoredMedication,
        plans: [StoredMedicationPlan],
        tasks: [StoredDoseTask],
        now: Date = Date()
    ) -> MedicationLifecycleClassification {
        switch medication.lifecycleStatus {
        case .interrupted:
            return MedicationLifecycleClassification(displayStatus: .interrupted, reason: .explicitStatus, shouldPromptReview: false)
        case .archived:
            return MedicationLifecycleClassification(displayStatus: .archived, reason: .archived, shouldPromptReview: false)
        case .active:
            break
        }

        let relatedPlans = plans.filter { $0.medicationID == medication.id }
        let relatedTasks = tasks
            .filter { $0.medicationID == medication.id }
            .filter(\.isAdherenceMeasurable)

        if let daysAgo = daysSinceMostRecentCourseEnd(relatedPlans, now: now), daysAgo >= courseEndGraceDays {
            return MedicationLifecycleClassification(displayStatus: .interrupted, reason: .courseEnded(daysAgo: daysAgo), shouldPromptReview: true)
        }

        let todayStart = calendar.startOfDay(for: now)
        guard let windowStart = calendar.date(byAdding: .day, value: -interruptionWindowDays, to: todayStart) else {
            return MedicationLifecycleClassification(displayStatus: .active, reason: .ongoing, shouldPromptReview: false)
        }

        let historicalTasks = relatedTasks.filter { $0.dueAt >= windowStart && $0.dueAt < todayStart }
        if !historicalTasks.isEmpty {
            let completedCount = historicalTasks.filter { $0.status == .taken || $0.status == .corrected }.count
            if completedCount == 0 {
                let skippedOrDelayedCount = historicalTasks.filter { $0.status == .skipped || $0.status == .delayed }.count
                if skippedOrDelayedCount > 0 {
                    return MedicationLifecycleClassification(displayStatus: .interrupted, reason: .skippedRecentSchedule(days: interruptionWindowDays), shouldPromptReview: true)
                }
                return MedicationLifecycleClassification(displayStatus: .interrupted, reason: .noRecentCompletion(days: interruptionWindowDays), shouldPromptReview: true)
            }
        } else if hasOngoingPlanOlderThanWindow(relatedPlans, now: now) {
            return MedicationLifecycleClassification(displayStatus: .interrupted, reason: .noRecentCompletion(days: interruptionWindowDays), shouldPromptReview: true)
        }

        return MedicationLifecycleClassification(displayStatus: .active, reason: .ongoing, shouldPromptReview: false)
    }

    private func daysSinceMostRecentCourseEnd(_ plans: [StoredMedicationPlan], now: Date) -> Int? {
        plans
            .compactMap(\.courseEndAt)
            .filter { $0 < calendar.startOfDay(for: now) }
            .map { endDate in
                calendar.dateComponents([.day], from: calendar.startOfDay(for: endDate), to: calendar.startOfDay(for: now)).day ?? 0
            }
            .max()
    }

    private func hasOngoingPlan(_ plans: [StoredMedicationPlan], now: Date) -> Bool {
        plans.contains { plan in
            guard let start = plan.courseStartAt else {
                return true
            }
            guard start <= now else {
                return false
            }
            guard let end = plan.courseEndAt else {
                return true
            }
            return end >= calendar.startOfDay(for: now)
        }
    }

    private func hasOngoingPlanOlderThanWindow(_ plans: [StoredMedicationPlan], now: Date) -> Bool {
        plans.contains { plan in
            guard hasOngoingPlan([plan], now: now) else {
                return false
            }
            let start = plan.courseStartAt ?? plan.createdAt
            let elapsedDays = calendar.dateComponents(
                [.day],
                from: calendar.startOfDay(for: start),
                to: calendar.startOfDay(for: now)
            ).day ?? 0
            return elapsedDays >= interruptionWindowDays
        }
    }
}
