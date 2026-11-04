import Combine
import ImageIO
import MedicationAdherenceCore
import SwiftUI
import UIKit

// Presentation reused from Issue #46. Actions and data remain owned by TodayView.
struct ElderTaskScreen: View {
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(AppExperienceMode.storageKey) private var experienceMode = AppExperienceMode.elder.rawValue
    @State private var showingHelp = false
    @State private var showingExitConfirmation = false
    @State private var taskPendingTakenConfirmation: StoredDoseTask?
    let screen: TodayScreen
    private let timer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    private var currentTask: StoredDoseTask? {
        screen.snapshot.visibleOpenTimelineTasks.first
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                if let task = currentTask {
                    let medication = screen.actions.medication(task)
                    Text(task.dueAt, style: .time).font(.title2.bold()).foregroundStyle(.secondary)
                    Text(task.status == .delayed ? "稍后提醒" : task.dueAt <= Date() ? "未确认" : "待服用")
                        .font(.title3.weight(.semibold)).foregroundStyle(.blue)
                    ElderMedicationPhotoView(photoData: medication?.photoData,
                        medicationName: medication.map(userFacingMedicationName), width: 180,
                        usesDemoVitaminPhoto: medication?.isDemoContent == true && medication?.displayName == "维生素 D3")
                    Text(medication.map(userFacingMedicationName) ?? "用药任务")
                        .font(.largeTitle.bold()).multilineTextAlignment(.center)
                    Text("\(task.doseValue.formatted()) \(task.doseUnit)").font(.title.bold())
                    if let confirmation = screen.pendingDoseConfirmation,
                       confirmation.doseKey == screen.actions.logicalDoseKey(task) {
                        Text(confirmation.kind.title).font(.title2.bold())
                        Text(confirmation.kind.message(delayDurationText: "\(DoseDelayPolicy.delayMinutes) 分钟")).font(.body)
                        action(confirmation.kind.confirmTitle, icon: "checkmark", tone: .completion, prominence: .primary, id: "elder.confirmation.confirm") { screen.actions.confirm(task) }
                        action("取消", icon: "xmark", tone: .neutral, prominence: .secondary, id: "elder.confirmation.cancel", requiresHold: false) { screen.actions.cancelConfirmation(task) }
                    } else {
                        action(screen.actions.completionVerb(medication), icon: "checkmark.circle.fill", tone: .completion, prominence: .primary, id: "elder.action.taken") { taskPendingTakenConfirmation = task }
                        action("稍后提醒", icon: "clock", tone: .reminder, prominence: .secondary, id: "elder.action.delay") { screen.actions.delay(task) }
                        action("使用帮助", icon: "questionmark.circle", tone: .help, prominence: .tertiary, id: "elder.action.help", requiresHold: false) { showingHelp = true }
                    }
                    Text("还有 \(max(0, screen.snapshot.visibleOpenTimelineTasks.count - 1)) 项待处理")
                        .font(.body).foregroundStyle(.secondary)
                } else {
                    ContentUnavailableView(screen.snapshot.emptyOpenTimelineMessage,
                        systemImage: "checkmark.circle")
                }
                if let banner = screen.doseUndoBanner {
                    DoseUndoBannerView(banner: banner, undoRollback: { screen.actions.rollbackUndo(banner) })
                }
                if let message = screen.notificationUnavailableDetailText {
                    Text(message).font(.footnote).foregroundStyle(.secondary)
                }
            }
            .id(currentTask?.id)
            .padding(24).frame(maxWidth: .infinity)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("用药提醒").navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("elder.home")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("返回完整模式") { showingExitConfirmation = true }
                    .accessibilityIdentifier("elder.switch-to-complete")
            }
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink { SettingsView() } label: { Label("同机设置", systemImage: "gearshape") }
            }
        }
        .sheet(isPresented: $showingHelp) { HelpCenterView() }
        .alert("返回完整模式？", isPresented: $showingExitConfirmation) {
            Button("取消", role: .cancel) {}
            Button("返回完整模式") { experienceMode = AppExperienceMode.complete.rawValue }
        } message: { Text("返回后可查看药品、记录和智能体。") }
        .alert("确认已服用或使用？", isPresented: Binding(
            get: { taskPendingTakenConfirmation != nil },
            set: { if !$0 { taskPendingTakenConfirmation = nil } }
        )) {
            Button("取消", role: .cancel) { taskPendingTakenConfirmation = nil }
            Button("确认记录") {
                if let task = taskPendingTakenConfirmation, task.id == currentTask?.id {
                    screen.actions.markTaken(task)
                }
                taskPendingTakenConfirmation = nil
            }
        } message: {
            Text("请在实际完成本次用药后确认，记录成功后会显示下一项。")
        }
        .alert("用药记录未保存", isPresented: Binding(get: { screen.dosePersistenceErrorMessage != nil }, set: { if !$0 { screen.dosePersistenceErrorMessage = nil } })) {
            Button("好", role: .cancel) { screen.dosePersistenceErrorMessage = nil }
        } message: { Text(screen.dosePersistenceErrorMessage ?? "请重试") }
        .task { await screen.actions.initialLoad() }
        .onReceive(timer) { _ in screen.actions.timerTick() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { screen.actions.becameActive() }
        }
        .onDisappear(perform: screen.actions.cleanup)
    }

    private func action(_ title: String, icon: String, tone: ElderDoseActionTone,
                        prominence: ElderDoseActionProminence, id: String, requiresHold: Bool = true, perform: @escaping () -> Void) -> some View {
        ElderDoseActionButton(title: title, systemImage: icon, tone: tone,
                             prominence: prominence, accessibilityIdentifier: id, requiresHold: requiresHold, action: perform)
            .disabled(screen.pendingDoseFeedback != nil)
    }
}

struct ElderMedicationPhotoView: View {
    @Environment(\.displayScale) private var displayScale
    let photoData: Data?
    let medicationName: String?
    let width: CGFloat
    var usesDemoVitaminPhoto = false
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
        width / 1.25
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
        } else if photoData == nil && usesDemoVitaminPhoto {
            description = "演示药品实物照片"
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
            } else if photoData == nil && usesDemoVitaminPhoto {
                Image("DemoVitaminD3")
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

enum ElderDoseActionProminence: Equatable {
    case primary
    case secondary
    case tertiary

    var font: Font {
        switch self {
        case .primary:
            return .title2.bold()
        case .secondary:
            return .title3.bold()
        case .tertiary:
            return .title3.weight(.semibold)
        }
    }

    var minimumHeight: CGFloat {
        switch self {
        case .primary:
            return 76
        case .secondary:
            return 68
        case .tertiary:
            return 60
        }
    }

    var visibleWidthRatio: CGFloat {
        switch self {
        case .primary:
            return 1
        case .secondary:
            return 0.92
        case .tertiary:
            return 0.80
        }
    }

    func contentWidth(availableWidth: CGFloat) -> CGFloat {
        max(0, availableWidth * visibleWidthRatio)
    }
}

private struct ElderDoseActionButton: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("prefersReducedAppMotion") private var prefersReducedAppMotion = false
    @GestureState private var isHolding = false
    @State private var showingAccessibleConfirmation = false
    @State private var holdFeedback = UIImpactFeedbackGenerator(style: .light)

    let title: String
    let systemImage: String
    let tone: ElderDoseActionTone
    let prominence: ElderDoseActionProminence
    let accessibilityIdentifier: String
    let requiresHold: Bool
    let action: () -> Void

    var body: some View {
        Button {
            if !requiresHold { action() }
        } label: {
            ElderDoseActionLabelLayout(
                visibleWidthRatio: dynamicTypeSize.isAccessibilitySize ? 1 : prominence.visibleWidthRatio,
                minimumHeight: prominence.minimumHeight
            ) {
                actionLabel
                    .font(prominence.font)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, dynamicTypeSize.isAccessibilitySize ? 16 : 10)
                    .padding(.vertical, 16)
                    .frame(minHeight: prominence.minimumHeight)
                    .foregroundStyle(prominence == .primary ? Color.white : tone.foregroundColor(for: colorScheme))
                    .background(actionBackground)
            }
            .frame(maxWidth: .infinity, minHeight: prominence.minimumHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 1.2, maximumDistance: 36)
                .updating($isHolding) { pressing, state, _ in state = pressing }
                .onEnded { _ in
                    guard requiresHold, isEnabled, scenePhase == .active else { return }
                    holdFeedback.impactOccurred(intensity: 0.85)
                    action()
                },
            isEnabled: requiresHold && isEnabled
        )
        .onChange(of: isHolding) { _, holding in
            guard holding, isEnabled, scenePhase == .active else { return }
            holdFeedback.impactOccurred(intensity: 0.4)
            holdFeedback.prepare()
        }
        .scaleEffect(isHolding && !reduceMotion && !prefersReducedAppMotion ? 1.025 : 1)
        .animation(.easeOut(duration: 0.16), value: isHolding)
        .frame(maxWidth: .infinity, minHeight: prominence.minimumHeight)
        .contentShape(Rectangle())
        .accessibilityLabel(title)
        .accessibilityHint(requiresHold ? "长按至进度填满后执行，松手取消" : "")
        .accessibilityAction {
            if requiresHold { showingAccessibleConfirmation = true } else { action() }
        }
        .accessibilityIdentifier(accessibilityIdentifier)
        .alert("确认\(title)？", isPresented: $showingAccessibleConfirmation) {
            Button("取消", role: .cancel) {}
            Button("确认") { if isEnabled { action() } }
        }
    }

    private var actionBackground: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                (prominence == .primary ? tone.solidColor : tone.foregroundColor(for: colorScheme).opacity(0.12))
                Rectangle()
                    .fill(prominence == .primary ? Color.white.opacity(0.25) : tone.foregroundColor(for: colorScheme).opacity(0.22))
                    .frame(width: isHolding ? geometry.size.width : 0)
                    .animation(isHolding ? .linear(duration: 1.2) : .easeOut(duration: 0.12), value: isHolding)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var actionLabel: some View {
        VStack(spacing: 6) {
            if dynamicTypeSize.isAccessibilitySize {
                Image(systemName: systemImage)
                    .imageScale(.large)
                    .accessibilityHidden(true)
                Text(title).fixedSize(horizontal: false, vertical: true)
            } else {
                Label(title, systemImage: systemImage)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if requiresHold && isHolding {
                Text("保持按住，松手取消")
                    .font(.caption)
                    .opacity(0.85)
                    .accessibilityHidden(true)
            }
        }
    }
}

private struct ElderDoseActionLabelLayout: Layout {
    let visibleWidthRatio: CGFloat
    let minimumHeight: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let label = subviews.first else { return .zero }
        let intrinsicWidth = label.sizeThatFits(.unspecified).width
        let proposedWidth = proposal.width ?? intrinsicWidth
        let availableWidth = proposedWidth.isFinite ? max(0, proposedWidth) : intrinsicWidth
        let visibleWidth = availableWidth * visibleWidthRatio
        let labelSize = label.sizeThatFits(ProposedViewSize(width: visibleWidth, height: nil))
        // Text may wrap before Accessibility sizes too; its measured height defines the full-row hit region.
        return CGSize(width: availableWidth, height: max(minimumHeight, labelSize.height))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard let label = subviews.first else { return }
        label.place(
            at: CGPoint(x: bounds.midX, y: bounds.midY),
            anchor: .center,
            proposal: ProposedViewSize(width: bounds.width * visibleWidthRatio, height: bounds.height)
        )
    }
}
