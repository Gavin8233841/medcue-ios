import Foundation
import Observation
import SwiftUI

@MainActor
@Observable
final class TodayDoseInteractionState {
    var pendingDoseFeedback: PendingDoseFeedback?
    /// A synchronous commit still needs a visible guard so repeated taps cannot
    /// enqueue another action before SwiftData refreshes the query-backed view.
    var inFlightDoseKeys: Set<String> = []
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

    func beginDoseAction(for doseKey: String) -> Bool {
        inFlightDoseKeys.insert(doseKey).inserted
    }

    func finishDoseAction(for doseKey: String) {
        inFlightDoseKeys.remove(doseKey)
    }
}

// MARK: - Committed action feedback policy

/// Presentation-only feedback. It never writes medication data or schedules reminders.
enum TodayDoseFeedbackAction: Equatable, Sendable {
    case taken
    case delayed
    case skipped
    case reopened
    case rollback
}

enum TodayDoseFeedbackKind: Equatable, Sendable {
    case success
    case acknowledgement
}

struct TodayDoseFeedbackRequest: Equatable, Sendable {
    let id: UUID
    let action: TodayDoseFeedbackAction
}

struct TodayDoseFeedbackPulse: Equatable, Sendable {
    let id = UUID()
    let kind: TodayDoseFeedbackKind
}

/// Only the latest explicit action can produce feedback. A delayed reminder may
/// finish after a newer action or after the screen disappears; neither is a new
/// user interaction. Reduce Motion does not change these commit/outcome rules.
struct TodayDoseFeedbackState {
    private enum Phase {
        case saving
        case awaitingReminder
    }

    private var request: TodayDoseFeedbackRequest?
    private var phase: Phase?

    mutating func begin(_ action: TodayDoseFeedbackAction) -> TodayDoseFeedbackRequest {
        let request = TodayDoseFeedbackRequest(id: UUID(), action: action)
        self.request = request
        phase = .saving
        return request
    }

    mutating func finishCommit(
        _ request: TodayDoseFeedbackRequest,
        succeeded: Bool
    ) -> TodayDoseFeedbackKind? {
        guard self.request == request, phase == .saving else { return nil }
        guard succeeded else {
            cancel()
            return nil
        }
        if request.action == .delayed {
            phase = .awaitingReminder
            return nil
        }
        cancel()
        switch request.action {
        case .taken:
            return .success
        case .skipped, .reopened, .rollback:
            return .acknowledgement
        case .delayed:
            return nil
        }
    }

    mutating func finishReminder(
        _ request: TodayDoseFeedbackRequest,
        scheduled: Bool,
        recordIsCurrent: Bool
    ) -> TodayDoseFeedbackKind? {
        guard self.request == request, phase == .awaitingReminder else { return nil }
        cancel()
        return scheduled && recordIsCurrent ? .success : nil
    }

    mutating func cancel() {
        request = nil
        phase = nil
    }
}

// MARK: - Native sensory feedback

/// The native API honors the system Haptics setting and hardware availability.
/// Existing text, status changes and VoiceOver announcements remain the primary
/// feedback. Reduce Motion affects animation, not this discrete saved-action cue.
struct TodayDoseFeedbackModifier: ViewModifier {
    @Environment(\.scenePhase) private var scenePhase
    let pulse: TodayDoseFeedbackPulse?
    let cancelPendingFeedback: () -> Void

    func body(content: Content) -> some View {
        content.sensoryFeedback(trigger: pulse) { previous, current in
            guard let current, current.id != previous?.id else { return nil }
            switch current.kind {
            case .success:
                return .success
            case .acknowledgement:
                // A light cue accompanies the saved row/status transition; it
                // does not celebrate skipping or undoing a medication record.
                return .impact(weight: .light, intensity: 0.5)
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active {
                cancelPendingFeedback()
            }
        }
    }
}
