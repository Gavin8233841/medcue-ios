import MedicationAdherenceCore
import AVFoundation
import ImageIO
import SwiftUI
import UIKit
#if canImport(AlarmKit)
import AlarmKit
#endif

enum AppPermissionGate: String, Identifiable {
    case notifications
    case alarm
    case camera
    case health
    case location

    var id: String { rawValue }

    var authorizationDefaultsKey: String {
        "appPermissionGate.completedAuthorization.\(rawValue)"
    }

    var title: String {
        switch self {
        case .notifications:
            "开启服药通知"
        case .alarm:
            "开启 iPhone 闹钟"
        case .camera:
            "开启相机"
        case .health:
            "读取 Apple 健康"
        case .location:
            "开启天气提醒"
        }
    }

    var message: String {
        switch self {
        case .notifications:
            "需要通知权限，才能在计划服药时间提醒你。未获得授权时，不会安排普通推送提醒。"
        case .alarm:
            "需要闹钟权限，才能在关键服药提醒中使用更强提醒。未获得授权时，不会启用 iPhone 闹钟提醒。"
        case .camera:
            "需要相机权限，才能拍摄药盒、扫描药名或识别说明书。未获得授权时，不会打开相机。"
        case .health:
            "需要你授权读取 Apple 健康数据，才能把生命体征用于趋势和复诊资料。未获得授权时，不会读取健康数据。"
        case .location:
            "需要定位权限，才能结合当前位置天气生成今日用药关注。未获得授权时，会继续使用本地兜底提示。"
        }
    }

    var continueTitle: String {
        switch self {
        case .notifications:
            "同意并开启通知"
        case .alarm:
            "同意并开启闹钟"
        case .camera:
            "同意并开启相机"
        case .health:
            "同意并授权健康"
        case .location:
            "同意并开启定位"
        }
    }

    static func hasCompletedAuthorization(for gate: AppPermissionGate) -> Bool {
        UserDefaults.standard.bool(forKey: gate.authorizationDefaultsKey)
    }

    static func markAuthorizationCompleted(for gate: AppPermissionGate) {
        UserDefaults.standard.set(true, forKey: gate.authorizationDefaultsKey)
    }

    static func isCameraAvailable() -> Bool {
        UIImagePickerController.isSourceTypeAvailable(.camera) || AVCaptureDevice.default(for: .video) != nil
    }

    static func isCameraAuthorized() -> Bool {
        AVCaptureDevice.authorizationStatus(for: .video) == .authorized
    }

    static func isAlarmAuthorized() -> Bool {
        #if canImport(AlarmKit)
        if #available(iOS 26.0, *) {
            return AlarmManager.shared.authorizationState == .authorized
        }
        #endif
        return false
    }

    @MainActor
    static func requestCameraAccess() async -> Bool {
        guard isCameraAvailable() else {
            return false
        }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            markAuthorizationCompleted(for: .camera)
            return true
        case .notDetermined:
            let granted = await withCheckedContinuation { continuation in
                AVCaptureDevice.requestAccess(for: .video) { granted in
                    continuation.resume(returning: granted)
                }
            }
            if granted {
                markAuthorizationCompleted(for: .camera)
            }
            return granted
        case .denied, .restricted:
            return false
        @unknown default:
            return false
        }
    }

    @MainActor
    static func requestAlarmAccess() async -> Bool {
        #if canImport(AlarmKit)
        if #available(iOS 26.0, *) {
            do {
                let state = try await AlarmManager.shared.requestAuthorization()
                let isAuthorized = state == .authorized
                if isAuthorized {
                    markAuthorizationCompleted(for: .alarm)
                }
                return isAuthorized
            } catch {
                return false
            }
        }
        #endif
        return false
    }
}

extension View {
    func appPermissionPrimer(
        pendingGate: Binding<AppPermissionGate?>,
        onContinue: @escaping (AppPermissionGate) -> Void
    ) -> some View {
        modifier(AppPermissionPrimerModifier(pendingGate: pendingGate, onContinue: onContinue))
    }
}

private struct AppPermissionPrimerModifier: ViewModifier {
    @Binding var pendingGate: AppPermissionGate?
    let onContinue: (AppPermissionGate) -> Void

    func body(content: Content) -> some View {
        content.alert(
            pendingGate?.title ?? "开启权限",
            isPresented: Binding(
                get: { pendingGate != nil },
                set: { isPresented in
                    if !isPresented {
                        pendingGate = nil
                    }
                }
            )
        ) {
            Button("暂不开启", role: .cancel) {
                pendingGate = nil
            }
            Button(pendingGate?.continueTitle ?? "同意并继续") {
                guard let gate = pendingGate else {
                    return
                }
                pendingGate = nil
                onContinue(gate)
            }
        } message: {
            Text(pendingGate?.message ?? "")
        }
    }
}

private struct OpenMedicationAIQuestionKey: EnvironmentKey {
    static let defaultValue: (String) -> Void = { _ in }
}

private struct PendingMedicationAIQuestionKey: EnvironmentKey {
    static let defaultValue = ""
}

private struct ClearPendingMedicationAIQuestionKey: EnvironmentKey {
    static let defaultValue: () -> Void = {}
}

private struct OpenMedicationTodayKey: EnvironmentKey {
    static let defaultValue: () -> Void = {}
}

private struct ActiveAppTabKey: EnvironmentKey {
    static let defaultValue: AppTab? = nil
}

private struct IsBackgroundTabPrewarmKey: EnvironmentKey {
    static let defaultValue = false
}

private struct SetAppTabTopGradientProgressKey: EnvironmentKey {
    static let defaultValue: (AppTab, CGFloat) -> Void = { _, _ in }
}

extension EnvironmentValues {
    var openMedicationAIQuestion: (String) -> Void {
        get { self[OpenMedicationAIQuestionKey.self] }
        set { self[OpenMedicationAIQuestionKey.self] = newValue }
    }

    var pendingMedicationAIQuestion: String {
        get { self[PendingMedicationAIQuestionKey.self] }
        set { self[PendingMedicationAIQuestionKey.self] = newValue }
    }

    var clearPendingMedicationAIQuestion: () -> Void {
        get { self[ClearPendingMedicationAIQuestionKey.self] }
        set { self[ClearPendingMedicationAIQuestionKey.self] = newValue }
    }

    var openMedicationToday: () -> Void {
        get { self[OpenMedicationTodayKey.self] }
        set { self[OpenMedicationTodayKey.self] = newValue }
    }

    var activeAppTab: AppTab? {
        get { self[ActiveAppTabKey.self] }
        set { self[ActiveAppTabKey.self] = newValue }
    }

    var isBackgroundTabPrewarm: Bool {
        get { self[IsBackgroundTabPrewarmKey.self] }
        set { self[IsBackgroundTabPrewarmKey.self] = newValue }
    }

    var setAppTabTopGradientProgress: (AppTab, CGFloat) -> Void {
        get { self[SetAppTabTopGradientProgressKey.self] }
        set { self[SetAppTabTopGradientProgressKey.self] = newValue }
    }
}

private struct AppTopGradientScrollOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

struct AppTopGradientScrollReader: View {
    let tab: AppTab
    let coordinateSpaceName: String
    var fadeDistance: CGFloat = 132
    @Environment(\.setAppTabTopGradientProgress) private var setProgress
    @Environment(\.activeAppTab) private var activeAppTab
    @State private var lastReportedProgress: CGFloat = -1

    var body: some View {
        GeometryReader { proxy in
            Color.clear
                .preference(
                    key: AppTopGradientScrollOffsetPreferenceKey.self,
                    value: proxy.frame(in: .named(coordinateSpaceName)).minY
                )
        }
        .frame(height: 0)
        .onPreferenceChange(AppTopGradientScrollOffsetPreferenceKey.self) { minY in
            guard activeAppTab == nil || activeAppTab == tab else {
                return
            }
            let scrolledDistance = max(0, -minY)
            let progress = max(0, min(1, 1 - scrolledDistance / fadeDistance))
            let quantizedProgress = (progress * 6).rounded() / 6
            guard abs(lastReportedProgress - quantizedProgress) > 0.14 else {
                return
            }
            lastReportedProgress = quantizedProgress
            setProgress(tab, quantizedProgress)
        }
        .accessibilityHidden(true)
    }
}

struct AppTopGradientTrackingListRow: View {
    let tab: AppTab
    let coordinateSpaceName: String

    var body: some View {
        AppTopGradientScrollReader(tab: tab, coordinateSpaceName: coordinateSpaceName)
            .frame(height: 0)
            .listRowInsets(EdgeInsets())
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
            .accessibilityHidden(true)
    }
}

extension View {
    func medicationGlassSurface(
        cornerRadius: CGFloat = 16,
        tint: Color = .clear,
        fallbackMaterial: Material = .thinMaterial,
        isInteractive: Bool = false
    ) -> some View {
        modifier(
            MedicationGlassSurfaceModifier(
                cornerRadius: cornerRadius,
                tint: tint,
                fallbackMaterial: fallbackMaterial,
                isInteractive: isInteractive
            )
        )
    }

    func medicationGlassButtonStyle(prominent: Bool = false) -> some View {
        modifier(MedicationGlassButtonStyleModifier(prominent: prominent))
    }
}

private struct MedicationGlassSurfaceModifier: ViewModifier {
    let cornerRadius: CGFloat
    let tint: Color
    let fallbackMaterial: Material
    let isInteractive: Bool

    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            if isInteractive {
                content
                    .background {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(tint.opacity(0.055))
                    }
                    .glassEffect(.regular.tint(tint.opacity(0.10)).interactive(), in: .rect(cornerRadius: cornerRadius))
            } else {
                content
                    .background {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(tint.opacity(0.055))
                    }
                    .glassEffect(.regular.tint(tint.opacity(0.10)), in: .rect(cornerRadius: cornerRadius))
            }
        } else {
            content
                .background(fallbackMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        }
    }
}

private struct MedicationGlassButtonStyleModifier: ViewModifier {
    let prominent: Bool

    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            if prominent {
                content.buttonStyle(.glassProminent)
            } else {
                content.buttonStyle(.glass)
            }
        } else {
            if prominent {
                content.buttonStyle(.borderedProminent)
            } else {
                content.buttonStyle(.bordered)
            }
        }
    }
}

struct MedicationGlassGroup<Content: View>: View {
    let spacing: CGFloat
    private let content: Content

    init(spacing: CGFloat = 16, @ViewBuilder content: () -> Content) {
        self.spacing = spacing
        self.content = content()
    }

    var body: some View {
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) {
                content
            }
        } else {
            content
        }
    }
}

struct AdherenceStreakDisplay {
    let title: String
    let value: String
    let summaryText: String

    init(insight: AdherenceInsight) {
        if insight.currentStreakDays > 0 {
            title = "连续达标"
            value = "\(insight.currentStreakDays) 天"
            summaryText = "\(insight.currentStreakDays) 天连续达标"
        } else if insight.longestStreakDays > 0 {
            title = "最长达标"
            value = "\(insight.longestStreakDays) 天"
            summaryText = "最长达标 \(insight.longestStreakDays) 天"
        } else {
            title = "连续达标"
            value = "待积累"
            summaryText = "连续达标待积累"
        }
    }
}

struct MedicationSymbolView: View {
    let symbolName: String
    let tint: Color

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(tint.opacity(0.14))
            Image(systemName: symbolName)
                .font(.title2.weight(.semibold))
                .foregroundStyle(tint)
        }
        .frame(width: 64, height: 64)
        .accessibilityHidden(true)
    }
}

struct MedicationPhotoView: View {
    let photoData: Data?
    let symbolName: String
    let tint: Color
    var size: CGFloat = 64
    @State private var decodedImage: UIImage?
    @State private var decodedImageKey: String?

    private var targetPixelSize: Int {
        max(1, Int((size * UIScreen.main.scale).rounded()))
    }

    private var photoKey: String? {
        photoData.map { MedicationPhotoImageCache.key(for: $0, targetPixelSize: targetPixelSize) }
    }

    var body: some View {
        Group {
            if let image = decodedImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size, height: size)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(.quaternary, lineWidth: 1)
                    )
            } else {
                medicationPhotoPlaceholder(size: size, symbolName: symbolName, tint: tint)
            }
        }
        .task(id: photoKey) {
            await loadImageIfNeeded()
        }
        .accessibilityHidden(true)
    }

    @MainActor
    private func loadImageIfNeeded() async {
        guard let photoData, let photoKey else {
            decodedImage = nil
            decodedImageKey = nil
            return
        }
        if decodedImageKey == photoKey, decodedImage != nil {
            return
        }
        if let cachedImage = MedicationPhotoImageCache.cachedImage(forKey: photoKey) {
            decodedImage = cachedImage
            decodedImageKey = photoKey
            return
        }
        let image = await MedicationPhotoImageCache.image(
            from: photoData,
            key: photoKey,
            targetPixelSize: targetPixelSize
        )
        guard !Task.isCancelled else {
            return
        }
        withAnimation(.easeOut(duration: 0.16)) {
            decodedImage = image
            decodedImageKey = image == nil ? nil : photoKey
        }
    }
}

struct MedicationHeroPhotoView: View {
    let photoData: Data?
    let symbolName: String
    let tint: Color
    let title: String
    var subtitle: String = "拍下药盒或药品实物，提醒时更容易核对。"
    var boxNumber: String = ""
    var showsMemoryGuide: Bool = true
    @State private var decodedImage: UIImage?
    @State private var decodedImageKey: String?

    private var trimmedBoxNumber: String {
        boxNumber.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var targetPixelSize: Int {
        max(320, Int((UIScreen.main.bounds.width * UIScreen.main.scale).rounded()))
    }

    private var photoKey: String? {
        photoData.map { MedicationPhotoImageCache.key(for: $0, targetPixelSize: targetPixelSize) }
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            if let image = decodedImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .overlay(alignment: .top) {
                        LinearGradient(
                            colors: [Color.black.opacity(0.26), .clear],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .frame(height: 88)
                    }
            } else {
                LinearGradient(
                    colors: [tint.opacity(0.16), Color(.secondarySystemGroupedBackground)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                VStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(.background.opacity(0.56))
                            .frame(width: 92, height: 70)
                        Image(systemName: symbolName)
                            .font(.system(size: 38, weight: .semibold))
                            .foregroundStyle(tint.opacity(0.8))
                    }
                    VStack(spacing: 3) {
                        Text(title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                            .padding(.horizontal, 18)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            HStack(alignment: .top) {
                if showsMemoryGuide {
                    Label("药盒记忆图", systemImage: "photo.on.rectangle.angled")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(photoData == nil ? tint : Color.white)
                        .lineLimit(1)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(photoData == nil ? Color.white.opacity(0.55) : Color.black.opacity(0.34), in: Capsule())
                }
                Spacer(minLength: 8)
                if !trimmedBoxNumber.isEmpty {
                    Text("编号 \(trimmedBoxNumber)")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(photoData == nil ? tint : Color.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(photoData == nil ? tint.opacity(0.13) : Color.black.opacity(0.38), in: Capsule())
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

            if photoData != nil {
                HStack(alignment: .bottom, spacing: 10) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 7) {
                            Image(systemName: "photo")
                            Text(title)
                        }
                        .font(.subheadline.weight(.semibold))

                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .minimumScaleFactor(0.86)
                    }

                    Spacer(minLength: 8)
                }
                .foregroundStyle(.primary)
                .padding(12)
                .medicationGlassSurface(cornerRadius: 8, tint: tint, fallbackMaterial: .thinMaterial)
                .padding(12)
            }
        }
        .frame(maxWidth: .infinity)
        .aspectRatio(1.55, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(.quaternary, lineWidth: 1)
        )
        .task(id: photoKey) {
            await loadImageIfNeeded()
        }
        .accessibilityElement(children: .combine)
    }

    @MainActor
    private func loadImageIfNeeded() async {
        guard let photoData, let photoKey else {
            decodedImage = nil
            decodedImageKey = nil
            return
        }
        if decodedImageKey == photoKey, decodedImage != nil {
            return
        }
        if let cachedImage = MedicationPhotoImageCache.cachedImage(forKey: photoKey) {
            decodedImage = cachedImage
            decodedImageKey = photoKey
            return
        }
        let image = await MedicationPhotoImageCache.image(
            from: photoData,
            key: photoKey,
            targetPixelSize: targetPixelSize
        )
        guard !Task.isCancelled else {
            return
        }
        withAnimation(.easeOut(duration: 0.18)) {
            decodedImage = image
            decodedImageKey = image == nil ? nil : photoKey
        }
    }
}

@ViewBuilder
private func medicationPhotoPlaceholder(size: CGFloat, symbolName: String, tint: Color) -> some View {
    ZStack {
        RoundedRectangle(cornerRadius: 8)
            .fill(tint.opacity(0.14))
        Image(systemName: symbolName)
            .font(.title2.weight(.semibold))
            .foregroundStyle(tint)
    }
    .frame(width: size, height: size)
}

private enum MedicationPhotoImageCache {
    private static let cache = NSCache<NSString, UIImage>()

    static func key(for data: Data, targetPixelSize: Int) -> String {
        var hasher = Hasher()
        hasher.combine(data.count)
        hasher.combine(targetPixelSize)
        data.withUnsafeBytes { rawBuffer in
            let bytes = rawBuffer.bindMemory(to: UInt8.self)
            let prefixCount = min(bytes.count, 24)
            for index in 0..<prefixCount {
                hasher.combine(bytes[index])
            }
            let suffixStart = max(prefixCount, bytes.count - 24)
            if suffixStart < bytes.count {
                for index in suffixStart..<bytes.count {
                    hasher.combine(bytes[index])
                }
            }
        }
        return "\(data.count)-\(targetPixelSize)-\(hasher.finalize())"
    }

    static func cachedImage(forKey key: String) -> UIImage? {
        cache.object(forKey: key as NSString)
    }

    static func image(from data: Data, key: String, targetPixelSize: Int) async -> UIImage? {
        if let cachedImage = cachedImage(forKey: key) {
            return cachedImage
        }
        return await Task.detached(priority: .utility) {
            let image = downsampledImage(from: data, targetPixelSize: targetPixelSize) ?? UIImage(data: data)
            if let image {
                cache.setObject(image, forKey: key as NSString, cost: imageCost(image))
            }
            return image
        }.value
    }

    private static func downsampledImage(from data: Data, targetPixelSize: Int) -> UIImage? {
        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, options) else {
            return nil
        }
        let downsampleOptions = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: targetPixelSize
        ] as CFDictionary
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, downsampleOptions) else {
            return nil
        }
        return UIImage(cgImage: cgImage)
    }

    private static func imageCost(_ image: UIImage) -> Int {
        guard let cgImage = image.cgImage else {
            return 1
        }
        return cgImage.bytesPerRow * cgImage.height
    }
}

struct StatusBadge: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(color)
            .lineLimit(1)
            .minimumScaleFactor(0.82)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .fixedSize(horizontal: true, vertical: false)
            .background(color.opacity(0.12), in: Capsule())
    }
}

struct StatusBadgeFlow: Layout {
    var spacing: CGFloat = 7
    var rowSpacing: CGFloat = 7

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        let rows = rows(in: subviews, maxWidth: maxWidth)
        let width = rows.map(\.width).max() ?? 0
        let height = rows.reduce(CGFloat.zero) { result, row in
            result + row.height
        } + CGFloat(max(rows.count - 1, 0)) * rowSpacing
        return CGSize(width: min(width, maxWidth), height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = rows(in: subviews, maxWidth: bounds.width)
        var y = bounds.minY
        for row in rows {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(
                    at: CGPoint(x: x, y: y + (row.height - size.height) / 2),
                    proposal: ProposedViewSize(size)
                )
                x += size.width + spacing
            }
            y += row.height + rowSpacing
        }
    }

    private func rows(in subviews: Subviews, maxWidth: CGFloat) -> [BadgeFlowRow] {
        var rows: [BadgeFlowRow] = []
        var current = BadgeFlowRow()

        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let proposedWidth = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            if proposedWidth > maxWidth, !current.indices.isEmpty {
                rows.append(current)
                current = BadgeFlowRow()
            }
            current.indices.append(index)
            current.width = current.width == 0 ? size.width : current.width + spacing + size.width
            current.height = max(current.height, size.height)
        }

        if !current.indices.isEmpty {
            rows.append(current)
        }
        return rows
    }
}

private struct BadgeFlowRow {
    var indices: [Int] = []
    var width: CGFloat = 0
    var height: CGFloat = 0
}

struct InfoRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer(minLength: 16)
            Text(value)
                .multilineTextAlignment(.trailing)
        }
        .font(.body)
    }
}

enum AppFormatters {
    static let time: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    static let day: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()

    static let month: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_Hans_CN")
        formatter.dateFormat = "yyyy年M月"
        return formatter
    }()
}

struct MedicationDoseUnitOption: Identifiable, Hashable {
    let id: String
    let displayName: String

    static let common: [MedicationDoseUnitOption] = [
        .init(id: "片", displayName: "片"),
        .init(id: "粒", displayName: "粒"),
        .init(id: "袋", displayName: "袋"),
        .init(id: "滴", displayName: "滴"),
        .init(id: "喷", displayName: "喷"),
        .init(id: "贴", displayName: "贴"),
        .init(id: "支", displayName: "支"),
        .init(id: "毫升", displayName: "毫升"),
        .init(id: "克", displayName: "克"),
        .init(id: "份", displayName: "份")
    ]
}

struct MedicationIconOption: Identifiable, Hashable {
    let id: String
    let displayName: String
    let symbolName: String

    static let common: [MedicationIconOption] = [
        .init(id: "pill", displayName: "药片", symbolName: "pills.fill"),
        .init(id: "capsule", displayName: "胶囊", symbolName: "capsule.portrait.fill"),
        .init(id: "prescription", displayName: "处方", symbolName: "cross.case.fill"),
        .init(id: "eye", displayName: "滴眼", symbolName: "eye.fill"),
        .init(id: "spray", displayName: "喷雾", symbolName: "wind"),
        .init(id: "patch", displayName: "贴剂", symbolName: "bandage.fill"),
        .init(id: "liquid", displayName: "液体", symbolName: "drop.fill")
    ]
}

struct MedicationColorOption: Identifiable, Hashable {
    let id: String
    let displayName: String
    let color: Color

    static let common: [MedicationColorOption] = [
        .init(id: "blue", displayName: "海蓝", color: Color(red: 0.26, green: 0.49, blue: 0.72)),
        .init(id: "teal", displayName: "青绿", color: Color(red: 0.12, green: 0.56, blue: 0.58)),
        .init(id: "green", displayName: "叶绿", color: Color(red: 0.26, green: 0.56, blue: 0.32)),
        .init(id: "orange", displayName: "暖橙", color: Color(red: 0.78, green: 0.45, blue: 0.18)),
        .init(id: "pink", displayName: "莓红", color: Color(red: 0.72, green: 0.30, blue: 0.46)),
        .init(id: "indigo", displayName: "靛蓝", color: Color(red: 0.38, green: 0.42, blue: 0.70))
    ]

    static func option(forRawValue rawValue: String) -> MedicationColorOption? {
        let normalizedRawValue = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return common.first { $0.id == normalizedRawValue }
    }

    static func resolved(for medication: StoredMedication) -> MedicationColorOption {
        if let storedOption = option(forRawValue: medication.colorTagRaw) {
            return storedOption
        }
        let scalarTotal = medication.id.uuidString.unicodeScalars.reduce(0) { partialResult, scalar in
            partialResult + Int(scalar.value)
        }
        return common[scalarTotal % common.count]
    }
}

struct MedicationColorMarker: View {
    let color: Color
    var size: CGFloat = 10

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
            .overlay {
                Circle()
                    .stroke(Color.white.opacity(0.7), lineWidth: max(1, size * 0.12))
            }
            .shadow(color: color.opacity(0.22), radius: 2, x: 0, y: 1)
            .accessibilityHidden(true)
    }
}

func localizedMedicationUnit(_ unit: String) -> String {
    switch unit.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
    case "tablet", "tablets", "tab", "tabs":
        return "片"
    case "capsule", "capsules", "cap", "caps":
        return "粒"
    case "drop", "drops":
        return "滴"
    case "spray", "sprays":
        return "喷"
    case "patch", "patches":
        return "贴"
    case "ml", "milliliter", "milliliters":
        return "毫升"
    case "g", "gram", "grams":
        return "克"
    case "unit", "units":
        return "份"
    default:
        return unit
    }
}

func medicationDemoLabelLookupName(for medication: StoredMedication) -> String {
    switch medication.displayName {
    case "布洛芬":
        return "Ibuprofen"
    case "对乙酰氨基酚":
        return "Acetaminophen"
    case "人工泪液":
        return "Artificial Tears"
    default:
        return medication.displayName
    }
}

func userFacingMedicationName(for medication: StoredMedication) -> String {
    MedicationNamePolicy.normalizedDisplayName(medication.displayName) ?? "待核对药品名称"
}

func medicationColorOption(for medication: StoredMedication) -> MedicationColorOption {
    MedicationColorOption.resolved(for: medication)
}

func medicationColor(for medication: StoredMedication) -> Color {
    medicationColorOption(for: medication).color
}

func medicationNeedsNameReview(_ medication: StoredMedication) -> Bool {
    MedicationNamePolicy.normalizedDisplayName(medication.displayName) == nil
}

func medicationNameReviewHint(for medication: StoredMedication) -> String {
    let descriptors = [medication.strength, medication.form]
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
    if descriptors.isEmpty {
        return "请编辑并补全真实药品名称。"
    }
    return "请编辑并补全真实药品名称，当前仅能按\(descriptors.joined(separator: " · "))核对。"
}

struct MedicationUnitPicker: View {
    let title: String
    @Binding var unit: String

    var body: some View {
        Picker(title, selection: $unit) {
            ForEach(MedicationDoseUnitOption.common) { option in
                Text(option.displayName).tag(option.id)
            }
        }
        .pickerStyle(.menu)
    }
}

struct MedicationIconPicker: View {
    @Binding var symbolName: String

    var body: some View {
        Picker("默认图标", selection: $symbolName) {
            ForEach(MedicationIconOption.common) { option in
                Label(option.displayName, systemImage: option.symbolName)
                    .tag(option.symbolName)
            }
        }
        .pickerStyle(.menu)
    }
}
