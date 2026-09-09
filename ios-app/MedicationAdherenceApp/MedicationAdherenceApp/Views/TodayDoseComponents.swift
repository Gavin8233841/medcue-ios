import Combine
import ImageIO
import MedicationAdherenceCore
import SwiftData
import SwiftUI
import UIKit

struct ElderMedicationPhotoView: View {
    @Environment(\.displayScale) private var displayScale
    let photoData: Data?
    let medicationName: String?
    let width: CGFloat
    @State private var decodedPhoto: DecodedPhoto?

    private struct PhotoRequest: Equatable, Sendable {
        let data: Data?
        let maximumPixelSize: Int
    }

    private struct DecodedPhoto {
        let request: PhotoRequest
        let image: UIImage?
    }

    private var height: CGFloat {
        width / ElderTaskLayoutMetrics.photoContainerAspectRatio
    }

    private var request: PhotoRequest {
        PhotoRequest(
            data: photoData,
            maximumPixelSize: max(1, min(2048, Int((max(width, height) * displayScale).rounded(.up))))
        )
    }

    private var currentImage: UIImage? {
        guard decodedPhoto?.request == request else { return nil }
        return decodedPhoto?.image
    }

    private var photoAccessibilityLabel: String {
        let description: String
        if currentImage != nil {
            description = "药品实物照片"
        } else if photoData == nil {
            description = "未添加药品照片，药品图示"
        } else if decodedPhoto?.request == request {
            description = "药品照片无法加载，药品图示"
        } else {
            description = "药品照片加载中，药品图示"
        }
        return medicationName.map { "\($0)，\(description)" } ?? description
    }

    var body: some View {
        ZStack {
            Color(.tertiarySystemGroupedBackground)
            if let image = currentImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .padding(8)
            } else {
                Image(systemName: "pills.fill")
                    .font(.system(size: 48, weight: .regular))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color(.separator), lineWidth: 1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(photoAccessibilityLabel)
        .accessibilityAddTraits(.isImage)
        .accessibilityIdentifier("elder.medication.photo")
        .task(id: request) {
            await loadPhoto(request)
        }
    }

    @MainActor
    private func loadPhoto(_ request: PhotoRequest) async {
        guard decodedPhoto?.request != request else { return }
        guard let data = request.data else {
            decodedPhoto = nil
            return
        }
        let image = await Task.detached(priority: .utility) {
            ElderMedicationPhotoDecoder.thumbnail(from: data, maximumPixelSize: request.maximumPixelSize)
        }.value
        guard !Task.isCancelled else { return }
        decodedPhoto = DecodedPhoto(request: request, image: image.map(UIImage.init(cgImage:)))
    }
}

enum ElderMedicationPhotoDecoder {
    nonisolated static func thumbnail(from data: Data, maximumPixelSize: Int) -> CGImage? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else {
            return nil
        }
        let options = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: max(1, min(2048, maximumPixelSize))
        ] as CFDictionary
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options)
    }
}

enum ElderDoseActionTone {
    case completion, reminder, help, neutral

    // Solid fills provide at least 4.5:1 contrast with white in sRGB.
    var solidColor: Color {
        switch self {
        case .completion: Self.color(0x237D42)
        case .reminder: Self.color(0x2B6AC1)
        case .help: Self.color(0xA65300)
        case .neutral: Self.color(0x737373)
        }
    }

    func foregroundColor(for scheme: ColorScheme) -> Color {
        switch self {
        case .completion: Self.color(scheme == .dark ? 0xA0DEB2 : 0x166534)
        case .reminder: Self.color(scheme == .dark ? 0x8FC3FF : 0x164C96)
        case .help: Self.color(scheme == .dark ? 0xFFCA83 : 0x964600)
        case .neutral: Self.color(scheme == .dark ? 0xDEDEDE : 0x4A4A4A)
        }
    }

    private static func color(_ hex: UInt32) -> Color {
        Color(.sRGB, red: Double((hex >> 16) & 0xFF) / 255,
              green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
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

        func elderTitle(completionVerb: String) -> String {
            switch self {
            case .earlyTaken:
                completionVerb == "已使用" ? "确认提前使用？" : "确认提前服用？"
            case .plannedDelay:
                "按原计划延后提醒？"
            }
        }

        func elderConfirmTitle(completionVerb: String) -> String {
            switch self {
            case .earlyTaken: "确认\(completionVerb)"
            case .plannedDelay: "确认延后"
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
    @Environment(\.medcueReduceMotionEnabled) private var reduceMotionEnabled
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
            if !reduceMotionEnabled {
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
        guard !reduceMotionEnabled else {
            sweepOffset = 1
            return
        }
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
