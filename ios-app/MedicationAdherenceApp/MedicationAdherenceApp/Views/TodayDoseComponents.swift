import Combine
import MedicationAdherenceCore
import SwiftData
import SwiftUI
import UIKit

@MainActor
enum TodayPerformanceGate {
    private static var lastOverdueSettlementAt: Date?
    private static let minimumOverdueSettlementInterval: TimeInterval = 45

    static func shouldRunOverdueSettlement(now: Date, force: Bool) -> Bool {
        if force {
            lastOverdueSettlementAt = now
            return true
        }
        guard let lastOverdueSettlementAt else {
            self.lastOverdueSettlementAt = now
            return true
        }
        guard now.timeIntervalSince(lastOverdueSettlementAt) >= minimumOverdueSettlementInterval else {
            return false
        }
        self.lastOverdueSettlementAt = now
        return true
    }
}

struct PendingDoseFeedback: Equatable {
    enum Action: Equatable {
        case taken
        case delay
        case skip

        var movesToHandledSection: Bool {
            switch self {
            case .taken, .skip:
                return true
            case .delay:
                return false
            }
        }

        var targetStatus: StoredDoseStatus {
            switch self {
            case .taken:
                return .taken
            case .delay:
                return .delayed
            case .skip:
                return .skipped
            }
        }
    }

    let doseKey: String
    let action: Action
}

struct PendingDoseConfirmation: Equatable {
    enum Kind: Equatable {
        case earlyTaken
        case plannedDelay

        var iconName: String {
            switch self {
            case .earlyTaken:
                return "exclamationmark.triangle.fill"
            case .plannedDelay:
                return "clock.arrow.circlepath"
            }
        }

        var title: String {
            switch self {
            case .earlyTaken:
                return "确认提前服用？"
            case .plannedDelay:
                return "按原计划顺延？"
            }
        }

        func message(delayDurationText: String) -> String {
            switch self {
            case .earlyTaken:
                return "距离计划时间较久。请确认已按医嘱、说明书或医生或药师建议服用。"
            case .plannedDelay:
                return "当前离计划时间较久。继续稍后会按原计划时间顺延 \(delayDurationText)，避免打乱今日时间线。"
            }
        }

        var confirmTitle: String {
            switch self {
            case .earlyTaken:
                return "确认已服用"
            case .plannedDelay:
                return "确认稍后"
            }
        }

        var tint: Color {
            switch self {
            case .earlyTaken:
                return .orange
            case .plannedDelay:
                return .blue
            }
        }
    }

    let doseKey: String
    let kind: Kind
}

struct DoseMigrationSnapshot: Identifiable, Equatable {
    enum Direction: Equatable {
        case toHandled
        case toOpen
    }

    let id: UUID
    let medicationName: String
    let doseText: String
    let timeText: String
    let symbolName: String
    let statusText: String
    let direction: Direction
}

struct DoseUndoBanner: Identifiable, Equatable {
    let id = UUID()
    let taskID: UUID
    let medicationName: String
    let rollbackToken: DoseReopenRollbackToken
}

struct DoseUndoBannerView: View {
    let banner: DoseUndoBanner
    let undoRollback: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "arrow.uturn.backward.circle.fill")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.blue)
                .frame(width: 32, height: 32)
                .background(.blue.opacity(0.12), in: Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text("已恢复到待处理")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(banner.medicationName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Button(action: undoRollback) {
                Text("撤回")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.blue)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.blue.opacity(0.10), in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .medicationGlassSurface(cornerRadius: 16, tint: .blue, fallbackMaterial: .ultraThinMaterial, isInteractive: true)
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(.blue.opacity(0.18), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.14), radius: 18, x: 0, y: 8)
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .onTapGesture(perform: undoRollback)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel("已恢复到待处理，\(banner.medicationName)，撤回")
        .accessibilityAction(named: Text("撤回"), undoRollback)
    }
}

struct CompletionRateSnapshot: Equatable {
    let completedCount: Int
    let totalCount: Int

    var progressValue: Double {
        guard totalCount > 0 else {
            return 0
        }
        return Double(completedCount) / Double(totalCount)
    }

    var percentValue: Int {
        Int((progressValue * 100).rounded())
    }

    var percentText: String {
        "\(percentValue)%"
    }

    var isComplete: Bool {
        totalCount > 0 && completedCount == totalCount
    }

    func affectsCompletionRate(comparedWith other: CompletionRateSnapshot) -> Bool {
        completedCount != other.completedCount || totalCount != other.totalCount
    }
}

struct CompletionRateFeedback: Identifiable, Equatable {
    let id = UUID()
    let previousSnapshot: CompletionRateSnapshot
    let nextSnapshot: CompletionRateSnapshot

    func title(for snapshot: CompletionRateSnapshot) -> String {
        snapshot.isComplete ? "今日用药已完成" : "今日完成率更新"
    }

    var subtitle: String {
        if nextSnapshot.completedCount > previousSnapshot.completedCount {
            return "刚刚完成 1 项记录"
        }
        if nextSnapshot.completedCount < previousSnapshot.completedCount {
            return "已撤销 1 条完成记录"
        }
        return "今日记录已更新"
    }

    var tint: Color {
        nextSnapshot.isComplete ? .green : .blue
    }
}

struct CompletionRateFeedbackPanel: View {
    let feedback: CompletionRateFeedback
    let displayedSnapshot: CompletionRateSnapshot
    let isVisible: Bool
    @State private var sweepOffset: CGFloat = -1

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: displayedSnapshot.isComplete ? "checkmark.seal.fill" : "chart.line.uptrend.xyaxis")
                .font(.headline.weight(.semibold))
                .foregroundStyle(feedback.tint)
                .frame(width: 28, height: 28)
                .background(feedback.tint.opacity(0.14), in: Circle())

            VStack(alignment: .leading, spacing: 7) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(feedback.title(for: displayedSnapshot))
                        .font(.subheadline.weight(.semibold))
                        .contentTransition(.opacity)

                    Text(feedback.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    Spacer(minLength: 8)

                    Text(displayedSnapshot.percentText)
                        .font(.headline.weight(.bold))
                        .monospacedDigit()
                        .foregroundStyle(feedback.tint)
                        .contentTransition(.numericText(value: Double(displayedSnapshot.percentValue)))
                }

                ProgressView(value: displayedSnapshot.progressValue)
                    .tint(feedback.tint)
                    .accessibilityLabel("今日完成率")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .modifier(CompletionRateGlassSurface(tint: feedback.tint))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(feedback.tint.opacity(0.22), lineWidth: 1)
        }
        .overlay(alignment: .leading) {
            GeometryReader { proxy in
                LinearGradient(
                    colors: [.clear, feedback.tint.opacity(0.20), .white.opacity(0.22), .clear],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(width: 72)
                .offset(x: sweepOffset * (proxy.size.width + 72) - 72)
                .blendMode(.plusLighter)
                .allowsHitTesting(false)
            }
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .shadow(color: feedback.tint.opacity(0.14), radius: 16, x: 0, y: 8)
        .offset(y: isVisible ? 0 : -20)
        .scaleEffect(isVisible ? 1 : 0.985, anchor: .top)
        .opacity(isVisible ? 1 : 0)
        .accessibilityElement(children: .combine)
        .onAppear {
            runSweep()
        }
        .onChange(of: displayedSnapshot) { _, _ in
            runSweep()
        }
    }

    private func runSweep() {
        sweepOffset = -1
        withAnimation(.easeOut(duration: 0.42)) {
            sweepOffset = 1
        }
    }
}

struct CompletionRateGlassSurface: ViewModifier {
    let tint: Color

    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
                .background {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(tint.opacity(0.07))
                }
                .glassEffect(.regular.tint(tint.opacity(0.12)), in: .rect(cornerRadius: 18))
        } else {
            content
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
    }
}

struct CompletionCompleteCelebrationCard: View {
    let snapshot: CompletionRateSnapshot
    let reduceMotion: Bool
    @State private var isCelebrating = false
    @State private var sweepOffset: CGFloat = -1

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            ZStack {
                Circle()
                    .fill(.green.opacity(0.14))
                    .frame(width: 48, height: 48)

                if !reduceMotion {
                    Circle()
                        .stroke(.green.opacity(isCelebrating ? 0 : 0.22), lineWidth: 8)
                        .frame(width: isCelebrating ? 72 : 48, height: isCelebrating ? 72 : 48)
                        .opacity(isCelebrating ? 0 : 1)
                }

                Image(systemName: "checkmark.seal.fill")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.green)
                    .scaleEffect(isCelebrating && !reduceMotion ? 1.06 : 1)
            }
            .frame(width: 54, height: 54)

            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("今日用药已完成")
                        .font(.headline.weight(.semibold))
                    Spacer(minLength: 8)
                    Text(snapshot.percentText)
                        .font(.title2.weight(.bold))
                        .monospacedDigit()
                        .foregroundStyle(.green)
                        .contentTransition(.numericText(value: Double(snapshot.percentValue)))
                }

                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(.green.opacity(0.13))
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [.green.opacity(0.78), .mint.opacity(0.88), .green],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: proxy.size.width)
                    }
                }
                .frame(height: 8)
                .accessibilityLabel("今日完成率")
                .accessibilityValue(snapshot.percentText)

                Text("已完成 \(snapshot.completedCount) / \(snapshot.totalCount) 项记录")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.green.opacity(0.16),
                            Color.mint.opacity(0.10),
                            Color(.secondarySystemGroupedBackground)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(.green.opacity(0.20), lineWidth: 1)
        }
        .overlay(alignment: .leading) {
            if !reduceMotion {
                GeometryReader { proxy in
                    LinearGradient(
                        colors: [.clear, .white.opacity(0.38), .green.opacity(0.16), .clear],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: 78)
                    .offset(x: sweepOffset * (proxy.size.width + 78) - 78)
                    .blendMode(.plusLighter)
                    .allowsHitTesting(false)
                }
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
        }
        .shadow(color: .green.opacity(isCelebrating && !reduceMotion ? 0.20 : 0.10), radius: isCelebrating && !reduceMotion ? 18 : 10, x: 0, y: 8)
        .accessibilityElement(children: .combine)
        .onAppear {
            runCelebration()
        }
        .onChange(of: snapshot) { _, _ in
            runCelebration()
        }
    }

    private func runCelebration() {
        guard !reduceMotion else {
            isCelebrating = false
            sweepOffset = 1
            return
        }
        isCelebrating = false
        sweepOffset = -1
        withAnimation(.interpolatingSpring(mass: 0.72, stiffness: 170, damping: 16, initialVelocity: 0.12)) {
            isCelebrating = true
        }
        withAnimation(.easeOut(duration: 0.86).delay(0.10)) {
            sweepOffset = 1
        }
    }
}
