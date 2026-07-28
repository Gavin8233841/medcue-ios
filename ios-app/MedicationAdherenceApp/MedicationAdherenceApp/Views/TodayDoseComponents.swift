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
struct WeatherMedicationHintCard: View {
    let hint: WeatherMedicationHint

    private var tint: Color {
        switch hint.tintName {
        case "orange":
            .orange
        case "teal":
            .teal
        case "indigo":
            .indigo
        case "yellow":
            .yellow
        case "green":
            .green
        default:
            .blue
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: hint.iconName)
                .font(.title3.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 32, height: 32)
                .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 6) {
                Text(hint.title)
                    .font(.headline)
                Text(hint.message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(hint.sourceSummary)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 6)
    }
}

struct TimelineDoseTaskRow: View {
    let task: StoredDoseTask
    let medication: StoredMedication?
    let completionText: String
    let statusText: String
    let isOpen: Bool
    let feedbackAction: PendingDoseFeedback.Action?
    let isClosing: Bool
    let isRecentlyReopened: Bool
    let confirmationKind: PendingDoseConfirmation.Kind?
    let markTaken: () -> Void
    let delay: () -> Void
    let skip: () -> Void
    let confirm: () -> Void
    let cancelConfirmation: () -> Void

    private var tint: Color {
        switch task.status {
        case .taken, .corrected:
            .green
        case .skipped:
            .orange
        case .delayed:
            .blue
        case .pending:
            .blue
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            timeRail
            VStack(alignment: .leading, spacing: 10) {
                if let medication {
                    NavigationLink {
                        MedicationDetailView(medication: medication)
                    } label: {
                        rowHeader
                    }
                    .buttonStyle(.plain)
                } else {
                    rowHeader
                }

                if isOpen {
                    HStack(spacing: 8) {
                        CompactDoseActionButton(
                            title: completionText,
                            confirmationIconName: "checkmark",
                            tint: TodayDoseActionPalette.primary,
                            isProminent: true,
                            isConfirming: feedbackAction == .taken,
                            action: markTaken
                        )
                        .id("\(task.id.uuidString)-taken")
                        CompactDoseActionButton(
                            title: "稍后",
                            confirmationIconName: "clock",
                            tint: .gray,
                            isProminent: false,
                            isConfirming: feedbackAction == .delay,
                            action: delay
                        )
                        .id("\(task.id.uuidString)-delay")
                        CompactDoseActionButton(
                            title: "忽略",
                            confirmationIconName: "minus.circle",
                            tint: .orange,
                            isProminent: false,
                            isConfirming: feedbackAction == .skip,
                            action: skip
                        )
                        .id("\(task.id.uuidString)-skip")
                    }
                    .padding(.leading, 50)
                    if let confirmationKind {
                        InlineDoseConfirmationCard(
                            kind: confirmationKind,
                            delayDurationText: "\(DoseDelayPolicy.delayMinutes) 分钟",
                            confirm: confirm,
                            cancel: cancelConfirmation
                        )
                        .transition(.asymmetric(
                            insertion: .opacity
                                .combined(with: .move(edge: .top))
                                .combined(with: .scale(scale: 0.98, anchor: .top)),
                            removal: .opacity
                                .combined(with: .scale(scale: 0.98, anchor: .top))
                        ))
                        .padding(.leading, 50)
                    }
                }
            }
            .padding(12)
            .background(rowBackground, in: RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(rowBorder, lineWidth: isRecentlyReopened ? 1.2 : 0.8)
            )
            .shadow(color: Color.black.opacity(isOpen ? 0.045 : 0.025), radius: isOpen ? 7 : 4, x: 0, y: 3)
            .opacity(isClosing ? 0.08 : (isRecentlyReopened ? 0.96 : 1))
            .blur(radius: isClosing ? 4 : 0)
            .scaleEffect(isClosing ? 0.96 : 1)
            .offset(y: isClosing ? 14 : (isRecentlyReopened ? -2 : 0))
            .animation(.snappy(duration: 0.26, extraBounce: 0.03), value: isRecentlyReopened)
            .animation(.easeInOut(duration: 0.18), value: isClosing)
            .animation(.snappy(duration: 0.22, extraBounce: 0.02), value: confirmationKind)
        }
        .padding(.vertical, 4)
        .transition(.asymmetric(
            insertion: .opacity
                .combined(with: .move(edge: .top))
                .combined(with: .scale(scale: 0.985, anchor: .top)),
            removal: .opacity.combined(with: .move(edge: .bottom))
        ))
        .allowsHitTesting(!isClosing)
    }

    private var timeRail: some View {
        VStack(spacing: 6) {
            Text(AppFormatters.time.string(from: task.dueAt))
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 50, height: 26)
                .background(Color(.secondarySystemGroupedBackground), in: Capsule())
            Capsule()
                .fill(tint.opacity(isOpen ? 0.22 : 0.14))
                .frame(width: 2)
                .frame(maxHeight: .infinity)
        }
        .frame(width: 52)
        .frame(minHeight: isOpen ? (confirmationKind == nil ? 106 : 172) : 84, alignment: .top)
    }

    private var rowBackground: Color {
        if isRecentlyReopened {
            return Color.blue.opacity(0.12)
        }
        return Color(.secondarySystemGroupedBackground)
    }

    private var rowBorder: Color {
        if isRecentlyReopened {
            return Color.blue.opacity(0.34)
        }
        return Color.primary.opacity(0.045)
    }

    private var rowHeader: some View {
        HStack(alignment: .center, spacing: 10) {
            MedicationPhotoView(
                photoData: medication?.photoData,
                symbolName: medication?.photoSymbolName ?? "pills.fill",
                tint: medication.map(medicationColor(for:)) ?? tint,
                size: 40
            )
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 7) {
                    if let medication {
                        MedicationColorMarker(color: medicationColor(for: medication), size: 8)
                    }
                    Text(medication.map(userFacingMedicationName(for:)) ?? "未知药品")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.86)
                }
                Text("\(task.doseValue.formatted()) \(localizedMedicationUnit(task.doseUnit))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            StatusBadge(text: statusText, color: tint)
        }
    }
}

struct InlineDoseConfirmationCard: View {
    let kind: PendingDoseConfirmation.Kind
    let delayDurationText: String
    let confirm: () -> Void
    let cancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 9) {
                Image(systemName: kind.iconName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(kind.tint)
                    .frame(width: 24, height: 24)
                    .background(kind.tint.opacity(0.12), in: Circle())

                VStack(alignment: .leading, spacing: 3) {
                    Text(kind.title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(kind.message(delayDurationText: delayDurationText))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            HStack(spacing: 8) {
                Button("取消", action: cancel)
                    .font(.caption.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 30)
                    .foregroundStyle(.secondary)
                    .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8))

                Button(kind.confirmTitle, action: confirm)
                    .font(.caption.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 30)
                    .foregroundStyle(.white)
                    .background(kind.tint, in: RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
        }
        .padding(10)
        .background(kind.tint.opacity(0.07), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(kind.tint.opacity(0.16), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
    }
}

struct OpenDoseSummaryRow: View {
    let count: Int
    let latestText: String
    let isReceiving: Bool
    let migrationSnapshot: DoseMigrationSnapshot?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Image(systemName: "tray.and.arrow.up.fill")
                    .font(.title3)
                    .foregroundStyle(.blue)
                    .frame(width: 30, height: 30)
                    .background(Color.blue.opacity(isReceiving ? 0.18 : 0.12), in: Circle())
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(count) 条待处理")
                        .font(.headline)
                    Text(latestText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
            }
            if let migrationSnapshot {
                DoseMigrationPill(snapshot: migrationSnapshot, tint: .blue)
                    .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .leading)))
            }
        }
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.blue.opacity(isReceiving ? 0.08 : 0))
        )
        .scaleEffect(isReceiving ? 1.01 : 1)
        .animation(.easeInOut(duration: 0.18), value: isReceiving)
        .accessibilityElement(children: .combine)
    }
}

struct HandledDoseSummaryRow: View {
    let count: Int
    let latestText: String
    let isReceiving: Bool
    let migrationSnapshot: DoseMigrationSnapshot?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.green)
                    .frame(width: 30, height: 30)
                    .background(Color.green.opacity(isReceiving ? 0.18 : 0.12), in: Circle())
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(count) 条已处理")
                        .font(.headline)
                    Text(latestText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
            }
            if let migrationSnapshot {
                DoseMigrationPill(snapshot: migrationSnapshot, tint: .green)
                    .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .leading)))
            }
        }
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.green.opacity(isReceiving ? 0.08 : 0))
        )
        .scaleEffect(isReceiving ? 1.01 : 1)
        .animation(.easeInOut(duration: 0.18), value: isReceiving)
        .accessibilityElement(children: .combine)
    }
}

struct DoseMigrationPill: View {
    let snapshot: DoseMigrationSnapshot
    let tint: Color

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: snapshot.symbolName)
                .font(.caption.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 22, height: 22)
                .background(tint.opacity(0.14), in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(snapshot.medicationName)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
                Text("\(snapshot.timeText) · \(snapshot.doseText)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Text(snapshot.statusText)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(tint)
                .lineLimit(1)
        }
        .frame(height: 40)
        .padding(.horizontal, 8)
        .background(tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(tint.opacity(0.12), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
    }
}

struct HandledDoseTaskRow: View {
    let task: StoredDoseTask
    let medication: StoredMedication?
    let statusText: String
    let undo: () -> Void
    let archive: () -> Void

    private var tint: Color {
        switch task.status {
        case .taken, .corrected:
            .green
        case .skipped:
            .orange
        case .pending, .delayed:
            .blue
        }
    }

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Text(AppFormatters.time.string(from: task.dueAt))
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 46, height: 26)
                .background(Color(.tertiarySystemGroupedBackground), in: Capsule())
            MedicationPhotoView(
                photoData: medication?.photoData,
                symbolName: medication?.photoSymbolName ?? "pills.fill",
                tint: medication.map(medicationColor(for:)) ?? tint,
                size: 34
            )
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 7) {
                    if let medication {
                        MedicationColorMarker(color: medicationColor(for: medication), size: 8)
                    }
                    Text(medication.map(userFacingMedicationName(for:)) ?? "未知药品")
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                }
                Text("\(task.doseValue.formatted()) \(localizedMedicationUnit(task.doseUnit))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            StatusBadge(text: statusText, color: tint)
            Button("撤销") {
                undo()
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.orange)
            .buttonStyle(.borderless)
            .accessibilityLabel("撤销\(medication.map(userFacingMedicationName(for:)) ?? "这条记录")")
        }
        .padding(.vertical, 7)
        .contentShape(Rectangle())
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button {
                undo()
            } label: {
                Label("撤销", systemImage: "arrow.uturn.backward")
            }
            .tint(.orange)

            Button {
                archive()
            } label: {
                Label("归档", systemImage: "archivebox")
            }
            .tint(.gray)
        }
    }
}

struct CompactDoseActionButton: View {
    let title: String
    let confirmationIconName: String
    let tint: Color
    let isProminent: Bool
    let isConfirming: Bool
    let action: () -> Void

    var body: some View {
        Button {
            action()
        } label: {
            ZStack {
                Text(title)
                    .opacity(isConfirming ? 0 : 1)
                    .blur(radius: isConfirming ? 3 : 0)
                    .scaleEffect(isConfirming ? 0.94 : 1)
                Image(systemName: confirmationIconName)
                    .font(.caption.weight(.bold))
                    .opacity(isConfirming ? 1 : 0)
                    .blur(radius: isConfirming ? 0 : 2)
                    .scaleEffect(isConfirming ? 1 : 0.86)
            }
            .font(.caption.weight(.semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.9)
            .frame(maxWidth: .infinity)
            .frame(height: 36)
            .foregroundStyle(isProminent ? TodayDoseActionPalette.primaryText : tint)
            .background(background, in: RoundedRectangle(cornerRadius: 8))
            .animation(.easeInOut(duration: 0.16), value: isConfirming)
        }
        .buttonStyle(CompactDoseActionButtonStyle())
        .disabled(isConfirming)
        .accessibilityLabel(title)
    }

    private var background: Color {
        if isProminent {
            return tint
        }
        return tint.opacity(tint == .gray ? 0.14 : 0.16)
    }
}

struct CompactDoseActionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.78 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

enum TodayDoseActionPalette {
    static let primary = Color(red: 0.82, green: 0.94, blue: 0.99)
    static let primaryText = Color(red: 0.12, green: 0.38, blue: 0.56)
}

struct ArchivedDoseTaskRow: View {
    let task: StoredDoseTask
    let medication: StoredMedication?
    let statusText: String
    let restore: () -> Void
    let reopen: () -> Void

    private var tint: Color {
        switch task.status {
        case .taken, .corrected:
            .green
        case .skipped:
            .orange
        case .pending, .delayed:
            .blue
        }
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            MedicationPhotoView(
                photoData: medication?.photoData,
                symbolName: medication?.photoSymbolName ?? "pills.fill",
                tint: medication.map(medicationColor(for:)) ?? tint,
                size: 40
            )
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 7) {
                    if let medication {
                        MedicationColorMarker(color: medicationColor(for: medication), size: 8)
                    }
                    Text(medication.map(userFacingMedicationName(for:)) ?? "未知药品")
                        .font(.subheadline.weight(.semibold))
                }
                Text("\(AppFormatters.time.string(from: task.dueAt)) · \(task.doseValue.formatted()) \(localizedMedicationUnit(task.doseUnit))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                StatusBadge(text: statusText, color: tint)
            }
            Spacer()
            Button("恢复") {
                restore()
            }
            .font(.caption.weight(.semibold))
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(.vertical, 6)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button {
                restore()
            } label: {
                Label("恢复", systemImage: "tray.and.arrow.up")
            }
            .tint(.blue)

            Button {
                reopen()
            } label: {
                Label("撤销", systemImage: "arrow.uturn.backward")
            }
            .tint(.orange)
        }
    }
}

struct DoseTaskRow: View {
    let task: StoredDoseTask
    let medication: StoredMedication?
    let completionText: String
    let markTaken: () -> Void
    let delay: () -> Void
    let skip: () -> Void
    let undo: () -> Void
    let undoLog: StoredDoseActionLog?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let medication {
                NavigationLink {
                    MedicationDetailView(medication: medication)
                } label: {
                    DoseTaskHeader(task: task, medication: medication)
                }
            } else {
                HStack(alignment: .top, spacing: 14) {
                    MedicationPhotoView(photoData: nil, symbolName: "pills.fill", tint: .blue)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("未知药品")
                            .font(.headline)
                        Text("\(task.doseValue.formatted()) \(localizedMedicationUnit(task.doseUnit)) · \(AppFormatters.time.string(from: task.dueAt))")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        StatusBadge(text: task.status.displayName, color: .orange)
                    }
                    Spacer()
                }
            }

            HStack(spacing: 10) {
                Button(action: markTaken) {
                    Label(completionText, systemImage: "checkmark")
                }
                .buttonStyle(.borderedProminent)
                .tint(TodayDoseActionPalette.primary)
                Button(action: delay) {
                    Label("稍后", systemImage: "clock")
                }
                .buttonStyle(.bordered)
                Button(action: skip) {
                    Label("忽略", systemImage: "minus.circle")
                }
                .buttonStyle(.bordered)
                .tint(.orange)
                if undoLog != nil {
                    Button(action: undo) {
                        Label("撤销", systemImage: "arrow.uturn.backward")
                    }
                    .buttonStyle(.bordered)
                }
            }
            .controlSize(.large)
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
    }
}

struct DoseTaskHeader: View {
    let task: StoredDoseTask
    let medication: StoredMedication

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            MedicationPhotoView(photoData: medication.photoData, symbolName: medication.photoSymbolName, tint: medicationColor(for: medication))
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    MedicationColorMarker(color: medicationColor(for: medication), size: 9)
                    Text(userFacingMedicationName(for: medication))
                        .font(.headline)
                }
                if medicationNeedsNameReview(medication) {
                    Text("药名待补全")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.orange)
                }
                Text("\(task.doseValue.formatted()) \(localizedMedicationUnit(task.doseUnit)) · \(AppFormatters.time.string(from: task.dueAt))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                StatusBadge(text: task.status.displayName, color: task.status == .taken ? .green : .orange)
            }
            Spacer()
        }
    }
}

struct ResolvedDoseTaskRow: View {
    let task: StoredDoseTask
    let medication: StoredMedication?
    let undoLog: StoredDoseActionLog?
    let statusText: String
    let reopen: () -> Void
    let archive: () -> Void
    let showDetail: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            MedicationPhotoView(
                photoData: medication?.photoData,
                symbolName: medication?.photoSymbolName ?? "pills.fill",
                tint: medication.map(medicationColor(for:)) ?? (task.status == .taken || task.status == .corrected ? .green : .orange),
                size: 44
            )
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    if let medication {
                        MedicationColorMarker(color: medicationColor(for: medication), size: 9)
                    }
                    Text(medication.map(userFacingMedicationName(for:)) ?? "未知药品")
                        .font(.headline)
                }
                Text("\(task.doseValue.formatted()) \(localizedMedicationUnit(task.doseUnit)) · \(AppFormatters.time.string(from: task.dueAt))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            StatusBadge(text: statusText, color: task.status == .taken || task.status == .corrected ? .green : .orange)
        }
        .padding(.vertical, 6)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(action: reopen) {
                Label("撤销", systemImage: "arrow.uturn.backward")
            }
            .tint(.orange)

            Button(action: archive) {
                Label("归档", systemImage: "archivebox")
            }
            .tint(.gray)

            Button(action: showDetail) {
                Label("详情", systemImage: "info.circle")
            }
            .tint(.blue)
        }
    }
}
