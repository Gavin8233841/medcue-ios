import AVFoundation
import SwiftUI

struct BarcodeScannerSheet: View {
    @Environment(\.dismiss) private var dismiss
    let onBarcode: (String, String) -> Void
    @State private var statusMessage = "请把药盒条码放入取景框，识别结果仍需二次确认。"
    @State private var scanHintIndex = 0

    private let scanHints = [
        "对准药盒条码，保持边缘完整",
        "稍微离远一点，避免条码贴边",
        "移动慢一点，让相机完成对焦"
    ]

    var body: some View {
        NavigationStack {
            ZStack {
                BarcodeScannerView(
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

private struct BarcodeScannerOverlay: View {
    let statusMessage: String
    let scanHint: String
    @State private var scanLineOffset: CGFloat = -78

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 78)

            VStack(spacing: 14) {
                Text(scanHint)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(.black.opacity(0.34), in: Capsule())
                    .transition(.opacity.combined(with: .move(edge: .top)))

                ZStack {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(.white.opacity(0.82), lineWidth: 2)
                        .frame(width: 286, height: 178)
                        .overlay {
                            ScannerCornerMarks()
                                .stroke(Color(red: 0.98, green: 0.78, blue: 0.30), style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
                                .frame(width: 286, height: 178)
                        }
                        .background(.black.opacity(0.08), in: RoundedRectangle(cornerRadius: 22, style: .continuous))

                    RoundedRectangle(cornerRadius: 2)
                        .fill(
                            LinearGradient(
                                colors: [.clear, Color(red: 0.98, green: 0.78, blue: 0.30).opacity(0.72), .clear],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: 236, height: 3)
                        .offset(y: scanLineOffset)
                        .shadow(color: Color(red: 0.98, green: 0.78, blue: 0.30).opacity(0.34), radius: 10, x: 0, y: 0)
                }
                .onAppear {
                    withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) {
                        scanLineOffset = 78
                    }
                }
            }

            Spacer()

            VStack(alignment: .leading, spacing: 10) {
                Label("药盒条码扫描", systemImage: "barcode.viewfinder")
                    .font(.headline)
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
            .padding()
        }
        .allowsHitTesting(false)
    }
}

private struct ScannerCornerMarks: Shape {
    func path(in rect: CGRect) -> Path {
        let length: CGFloat = 30
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
    let onBarcode: (String, String) -> Void
    let onError: (String) -> Void

    func makeUIViewController(context: Context) -> BarcodeScannerViewController {
        BarcodeScannerViewController(onBarcode: onBarcode, onError: onError)
    }

    func updateUIViewController(_ uiViewController: BarcodeScannerViewController, context: Context) {}
}

private final class BarcodeScannerViewController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    private let onBarcode: (String, String) -> Void
    private let onError: (String) -> Void
    private let captureSession = AVCaptureSession()
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var highlightLayer: CAShapeLayer?
    private weak var metadataOutput: AVCaptureMetadataOutput?
    private var hasReportedResult = false

    init(onBarcode: @escaping (String, String) -> Void, onError: @escaping (String) -> Void) {
        self.onBarcode = onBarcode
        self.onError = onError
        super.init(nibName: nil, bundle: nil)
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

            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                self?.captureSession.startRunning()
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

    private func updateScanRectOfInterest() {
        guard let previewLayer, let metadataOutput else {
            return
        }
        let width = min(view.bounds.width - 48, 286)
        let height: CGFloat = 178
        let scanRect = CGRect(
            x: (view.bounds.width - width) / 2,
            y: max(view.safeAreaInsets.top + 96, (view.bounds.height - height) / 2 - 64),
            width: width,
            height: height
        )
        metadataOutput.rectOfInterest = previewLayer.metadataOutputRectConverted(fromLayerRect: scanRect)
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
              let object = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
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
