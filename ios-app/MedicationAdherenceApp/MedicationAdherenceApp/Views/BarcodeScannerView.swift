import AVFoundation
import SwiftUI

struct BarcodeScannerSheet: View {
    @Environment(\.dismiss) private var dismiss
    let onBarcode: (String, String) -> Void
    @State private var statusMessage = "请把药盒条码放入取景框，识别结果仍需二次确认。"

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
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

                VStack(alignment: .leading, spacing: 10) {
                    Label("药盒条码扫描", systemImage: "barcode.viewfinder")
                        .font(.headline)
                    Text(statusMessage)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                .padding()
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
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    if granted {
                        self?.configureSession()
                    } else {
                        self?.onError("未获得相机权限，无法扫码。")
                    }
                }
            }
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
            } else {
                onError("无法添加条码识别输出。")
                return
            }

            let layer = AVCaptureVideoPreviewLayer(session: captureSession)
            layer.videoGravity = .resizeAspectFill
            layer.frame = view.bounds
            view.layer.insertSublayer(layer, at: 0)
            previewLayer = layer

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
        stopSession()
        onBarcode(payload, object.type.rawValue)
    }
}
