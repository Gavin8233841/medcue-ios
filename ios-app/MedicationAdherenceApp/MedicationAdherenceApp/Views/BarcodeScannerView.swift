@preconcurrency import AVFoundation
import SwiftUI

struct BarcodeScannerSheet: View {
    @Environment(\.dismiss) private var dismiss
    let onBarcode: (String, String) -> Void
    @State private var statusMessage = "请把药盒条码放入取景框，识别结果仍需二次确认。"
    @State private var scanHintIndex = 0
    @State private var scanRegion = BarcodeScannerRegion()

    private let scanHints = [
        "对准药盒条码，保持边缘完整",
        "稍微离远一点，避免条码贴边",
        "移动慢一点，让相机完成对焦"
    ]

    var body: some View {
        NavigationStack {
            ZStack {
                BarcodeScannerView(
                    scanRegion: scanRegion,
                    onBarcode: { payload, symbology in
                        onBarcode(payload, symbology)
                        dismiss()
                    },
                    onError: { message in
                        statusMessage = message
                    }
                )
                .ignoresSafeArea()

                BarcodeScannerOverlay(
                    scanRegion: scanRegion,
                    statusMessage: statusMessage,
                    scanHint: scanHints[scanHintIndex]
                )
            }
            .onAppear {
                scanHintIndex = 0
            }
            .task {
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(2.8))
                    await MainActor.run {
                        withAnimation(.snappy(duration: 0.35, extraBounce: 0.02)) {
                            scanHintIndex = (scanHintIndex + 1) % scanHints.count
                        }
                    }
                }
            }
            .navigationTitle("扫码")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") {
                        dismiss()
                    }
                }
            }
        }
    }
}

// One sizing rule for the visible frame; the ROI is measured from its actual view.
enum BarcodeScannerGeometry {
    static func frameSize(in available: CGSize) -> CGSize {
        guard available.width.isFinite, available.height.isFinite,
              available.width > 0, available.height > 0 else { return .zero }
        let scale = min(1, available.width / 286, available.height / 178)
        return CGSize(width: 286 * scale, height: 178 * scale)
    }

    static func normalizedRegion(_ rect: CGRect) -> CGRect {
        clippedRect(rect, in: CGRect(x: 0, y: 0, width: 1, height: 1))
    }

    static func accepts(metadataBounds: CGRect, region: CGRect) -> Bool {
        let validRegion = normalizedRegion(region)
        return !validRegion.isEmpty && !clippedRect(metadataBounds, in: validRegion).isEmpty
    }

    static func clippedRect(_ rect: CGRect, in bounds: CGRect) -> CGRect {
        guard [rect.origin.x, rect.origin.y, rect.width, rect.height,
               bounds.origin.x, bounds.origin.y, bounds.width, bounds.height].allSatisfy({ $0.isFinite }),
              rect.width > 0, rect.height > 0, bounds.width > 0, bounds.height > 0 else { return .zero }
        let clipped = rect.intersection(bounds)
        return clipped.isNull || clipped.isEmpty ? .zero : clipped
    }
}

// A UIKit anchor avoids assuming SwiftUI's safe-area origin matches the full-bleed
// camera view. No screen dimensions, device names, or normalized ROI guesses.
@MainActor
final class BarcodeScannerRegion {
    weak var anchorView: UIView?
    var onChange: (() -> Void)?
    private var updateScheduled = false

    func rect(in previewLayer: CALayer, previewView: UIView) -> CGRect {
        guard let anchorView, let window = previewView.window,
              anchorView.window === window else { return .zero }
        let rect = previewLayer.convert(anchorView.bounds, from: anchorView.layer)
        return BarcodeScannerGeometry.clippedRect(rect, in: previewLayer.bounds)
    }

    func scheduleUpdate() {
        guard !updateScheduled else { return }
        updateScheduled = true
        // Ancestor frames may still be changing during a SwiftUI layout pass.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.updateScheduled = false
            self.onChange?()
        }
    }
}

private struct ScannerRegionAnchor: UIViewRepresentable {
    let region: BarcodeScannerRegion

    func makeUIView(context: Context) -> ScannerRegionAnchorView {
        let view = ScannerRegionAnchorView()
        view.isUserInteractionEnabled = false
        view.isAccessibilityElement = false
        view.region = region
        region.anchorView = view
        return view
    }

    func updateUIView(_ uiView: ScannerRegionAnchorView, context: Context) {
        region.scheduleUpdate()
    }

    static func dismantleUIView(_ uiView: ScannerRegionAnchorView, coordinator: ()) {
        if uiView.region?.anchorView === uiView {
            uiView.region?.anchorView = nil
            uiView.region?.scheduleUpdate()
        }
    }
}

private final class ScannerRegionAnchorView: UIView {
    weak var region: BarcodeScannerRegion?

    override var frame: CGRect {
        didSet { region?.scheduleUpdate() }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        region?.scheduleUpdate()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        region?.scheduleUpdate()
    }

    override func safeAreaInsetsDidChange() {
        super.safeAreaInsetsDidChange()
        region?.scheduleUpdate()
    }
}

struct BarcodeScannerOverlay: View {
    let scanRegion: BarcodeScannerRegion
    let statusMessage: String
    let scanHint: String
    @State private var scanLineProgress: CGFloat = -1

    var body: some View {
        GeometryReader { container in
            VStack(spacing: 14) {
                ViewThatFits(in: .vertical) {
                    hint
                    ScrollView { hint }
                }
                .frame(maxHeight: max(0, container.size.height * 0.22))

                GeometryReader { viewport in
                    let size = BarcodeScannerGeometry.frameSize(in: viewport.size)
                    scanFrame(size: size)
                        .position(x: viewport.size.width / 2, y: viewport.size.height / 2)
                }

                ViewThatFits(in: .vertical) {
                    statusCard
                    ScrollView { statusCard }
                }
                .frame(maxHeight: max(0, container.size.height * 0.36))
            }
            .padding(16)
        }
    }

    private var hint: some View {
        Text(scanHint)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.white)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(.black.opacity(0.34), in: Capsule())
            .transition(.opacity)
    }

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("药盒条码扫描", systemImage: "barcode.viewfinder")
                .font(.headline)
                .fixedSize(horizontal: false, vertical: true)
            Text(statusMessage)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(.white.opacity(0.20), lineWidth: 1)
        )
    }

    private func scanFrame(size: CGSize) -> some View {
        let scale = size.width / 286
        return ZStack {
            RoundedRectangle(cornerRadius: 22 * scale, style: .continuous)
                .stroke(.white.opacity(0.82), lineWidth: 2)
                .overlay {
                    ScannerCornerMarks()
                        .stroke(Color(red: 0.98, green: 0.78, blue: 0.30), style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
                }
                .background(.black.opacity(0.08), in: RoundedRectangle(cornerRadius: 22 * scale, style: .continuous))

            RoundedRectangle(cornerRadius: 2)
                .fill(
                    LinearGradient(
                        colors: [.clear, Color(red: 0.98, green: 0.78, blue: 0.30).opacity(0.72), .clear],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(width: 236 * scale, height: min(3, size.height))
                .offset(y: scanLineProgress * 78 * scale)
                .shadow(color: Color(red: 0.98, green: 0.78, blue: 0.30).opacity(0.34), radius: 10, x: 0, y: 0)
        }
        .frame(width: size.width, height: size.height)
        .background(ScannerRegionAnchor(region: scanRegion))
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) {
                scanLineProgress = 1
            }
        }
    }
}

private struct ScannerCornerMarks: Shape {
    func path(in rect: CGRect) -> Path {
        let length = min(30, rect.width / 2, rect.height / 2)
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY + length))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX + length, y: rect.minY))

        path.move(to: CGPoint(x: rect.maxX - length, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + length))

        path.move(to: CGPoint(x: rect.maxX, y: rect.maxY - length))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX - length, y: rect.maxY))

        path.move(to: CGPoint(x: rect.minX + length, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - length))
        return path
    }
}

private struct BarcodeScannerView: UIViewControllerRepresentable {
    let scanRegion: BarcodeScannerRegion
    let onBarcode: (String, String) -> Void
    let onError: (String) -> Void

    func makeUIViewController(context: Context) -> BarcodeScannerViewController {
        BarcodeScannerViewController(scanRegion: scanRegion, onBarcode: onBarcode, onError: onError)
    }

    func updateUIViewController(_ uiViewController: BarcodeScannerViewController, context: Context) {}
}

@MainActor
private final class BarcodeScannerViewController: UIViewController, @preconcurrency AVCaptureMetadataOutputObjectsDelegate {
    private let scanRegion: BarcodeScannerRegion
    private let onBarcode: (String, String) -> Void
    private let onError: (String) -> Void
    private let captureSession = AVCaptureSession()
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var highlightLayer: CAShapeLayer?
    private weak var metadataOutput: AVCaptureMetadataOutput?
    private var hasReportedResult = false

    init(scanRegion: BarcodeScannerRegion, onBarcode: @escaping (String, String) -> Void, onError: @escaping (String) -> Void) {
        self.scanRegion = scanRegion
        self.onBarcode = onBarcode
        self.onError = onError
        super.init(nibName: nil, bundle: nil)
        scanRegion.onChange = { [weak self] in
            self?.updateScanRectOfInterest()
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        prepareCameraAccess()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
        highlightLayer?.frame = view.bounds
        updateScanRectOfInterest()
        scanRegion.scheduleUpdate()
    }

    override func viewSafeAreaInsetsDidChange() {
        super.viewSafeAreaInsetsDidChange()
        scanRegion.scheduleUpdate()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        stopSession()
    }

    private func prepareCameraAccess() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            configureSession()
        case .notDetermined:
            onError("打开扫码前需要先允许相机权限。")
        case .denied, .restricted:
            onError("相机权限不可用，请在系统设置中允许后再扫码。")
        @unknown default:
            onError("无法确认相机权限状态。")
        }
    }

    private func configureSession() {
        guard let device = AVCaptureDevice.default(for: .video) else {
            onError("当前设备没有可用相机。模拟器通常无法进行真机扫码。")
            return
        }

        do {
            let input = try AVCaptureDeviceInput(device: device)
            if captureSession.canAddInput(input) {
                captureSession.addInput(input)
                for port in input.ports where port.mediaType == .video {
                    NotificationCenter.default.addObserver(
                        self,
                        selector: #selector(inputFormatDidChange(_:)),
                        name: AVCaptureInput.Port.formatDescriptionDidChangeNotification,
                        object: port
                    )
                }
            } else {
                onError("无法添加相机输入。")
                return
            }

            let output = AVCaptureMetadataOutput()
            if captureSession.canAddOutput(output) {
                captureSession.addOutput(output)
                output.setMetadataObjectsDelegate(self, queue: .main)
                output.metadataObjectTypes = supportedMetadataTypes(from: output.availableMetadataObjectTypes)
                metadataOutput = output
            } else {
                onError("无法添加条码识别输出。")
                return
            }

            let layer = AVCaptureVideoPreviewLayer(session: captureSession)
            layer.videoGravity = .resizeAspectFill
            layer.frame = view.bounds
            view.layer.insertSublayer(layer, at: 0)
            previewLayer = layer
            installHighlightLayer()
            updateScanRectOfInterest()

            DispatchQueue.global(qos: .userInitiated).async { [captureSession] in
                captureSession.startRunning()
            }
        } catch {
            onError("相机初始化失败：\(error.localizedDescription)")
        }
    }

    private func supportedMetadataTypes(from available: [AVMetadataObject.ObjectType]) -> [AVMetadataObject.ObjectType] {
        let preferred: [AVMetadataObject.ObjectType] = [
            .ean8,
            .ean13,
            .upce,
            .code39,
            .code93,
            .code128,
            .itf14,
            .qr,
            .dataMatrix,
            .pdf417,
            .aztec
        ]
        return preferred.filter { available.contains($0) }
    }

    private func stopSession() {
        guard captureSession.isRunning else {
            return
        }
        DispatchQueue.global(qos: .userInitiated).async { [captureSession] in
            captureSession.stopRunning()
        }
    }

    private func installHighlightLayer() {
        let layer = CAShapeLayer()
        layer.frame = view.bounds
        layer.strokeColor = UIColor.systemYellow.withAlphaComponent(0.92).cgColor
        layer.fillColor = UIColor.systemYellow.withAlphaComponent(0.10).cgColor
        layer.lineWidth = 3
        layer.lineJoin = .round
        layer.opacity = 0
        view.layer.addSublayer(layer)
        highlightLayer = layer
    }

    // Capture notifications can arrive off the main thread. Observe only this
    // session's video input ports and recalculate after their format is ready.
    @objc nonisolated private func inputFormatDidChange(_ notification: Notification) {
        Task { @MainActor [weak self] in
            self?.scanRegion.scheduleUpdate()
        }
    }

    private func updateScanRectOfInterest() {
        guard let previewLayer, let metadataOutput else {
            return
        }
        metadataOutput.rectOfInterest = currentMetadataRegion(in: previewLayer)
    }

    private func currentMetadataRegion(in previewLayer: AVCaptureVideoPreviewLayer) -> CGRect {
        let scanRect = scanRegion.rect(in: previewLayer, previewView: view)
        // Before layout/format readiness, never expand to full-frame scanning.
        guard !scanRect.isEmpty else { return .zero }
        return BarcodeScannerGeometry.normalizedRegion(
            previewLayer.metadataOutputRectConverted(fromLayerRect: scanRect)
        )
    }

    private func showTrackingFrame(for object: AVMetadataMachineReadableCodeObject) {
        guard let previewLayer,
              let transformedObject = previewLayer.transformedMetadataObject(for: object) as? AVMetadataMachineReadableCodeObject else {
            return
        }
        let bounds = transformedObject.bounds.insetBy(dx: -8, dy: -8)
        let path = UIBezierPath(roundedRect: bounds, cornerRadius: 10)
        highlightLayer?.path = path.cgPath
        highlightLayer?.removeAllAnimations()
        highlightLayer?.opacity = 1
        let animation = CABasicAnimation(keyPath: "opacity")
        animation.fromValue = 0.2
        animation.toValue = 1
        animation.duration = 0.12
        highlightLayer?.add(animation, forKey: "barcode-highlight")
    }

    func metadataOutput(
        _ output: AVCaptureMetadataOutput,
        didOutput metadataObjects: [AVMetadataObject],
        from connection: AVCaptureConnection
    ) {
        guard !hasReportedResult,
              let previewLayer,
              let object = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
              BarcodeScannerGeometry.accepts(
                metadataBounds: object.bounds,
                region: currentMetadataRegion(in: previewLayer)
              ),
              let payload = object.stringValue,
              !payload.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            return
        }
        hasReportedResult = true
        showTrackingFrame(for: object)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) { [weak self] in
            guard let self else {
                return
            }
            self.stopSession()
            self.onBarcode(payload, object.type.rawValue)
        }
    }
}
