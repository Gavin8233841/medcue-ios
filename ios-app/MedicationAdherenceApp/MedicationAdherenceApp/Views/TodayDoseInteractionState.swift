import Observation

@MainActor
@Observable
final class TodayDoseInteractionState {
    var pendingDoseFeedback: PendingDoseFeedback?
    var isOpenTimelineTemporarilyCollapsed = false
    var isHandledTimelineTemporarilyCollapsed = false
    var pendingHandledArrivalCount = 0
    var closingOpenDoseKeys: Set<String> = []
    var reopeningHandledDoseKeys: Set<String> = []
    var handledDropTargetPulse = false
    var doseMigrationSnapshot: DoseMigrationSnapshot?
    var recentlyReopenedDoseKeys: Set<String> = []
    var pendingDoseFeedbackTask: Task<Void, Never>?
    var doseLayoutTransitionTask: Task<Void, Never>?

    var isAnimationActive: Bool {
        pendingDoseFeedback != nil
            || pendingDoseFeedbackTask != nil
            || doseLayoutTransitionTask != nil
            || isOpenTimelineTemporarilyCollapsed
            || isHandledTimelineTemporarilyCollapsed
            || handledDropTargetPulse
            || !closingOpenDoseKeys.isEmpty
            || !reopeningHandledDoseKeys.isEmpty
            || doseMigrationSnapshot != nil
    }

    var projectionTransition: TodayDoseProjectionTransition {
        TodayDoseProjectionTransition(
            pendingDoseFeedback: pendingDoseFeedback,
            closingOpenDoseKeys: closingOpenDoseKeys,
            reopeningHandledDoseKeys: reopeningHandledDoseKeys,
            recentlyReopenedDoseKeys: recentlyReopenedDoseKeys,
            isHandledTimelineTemporarilyCollapsed: isHandledTimelineTemporarilyCollapsed,
            handledDropTargetPulse: handledDropTargetPulse,
            pendingHandledArrivalCount: pendingHandledArrivalCount
        )
    }

    func resetTransientVisuals() {
        pendingDoseFeedback = nil
        isOpenTimelineTemporarilyCollapsed = false
        isHandledTimelineTemporarilyCollapsed = false
        handledDropTargetPulse = false
        pendingHandledArrivalCount = 0
        closingOpenDoseKeys = []
        reopeningHandledDoseKeys = []
        doseMigrationSnapshot = nil
    }

    func cancelScheduledTransitions() {
        pendingDoseFeedbackTask?.cancel()
        pendingDoseFeedbackTask = nil
        doseLayoutTransitionTask?.cancel()
        doseLayoutTransitionTask = nil
    }
}
