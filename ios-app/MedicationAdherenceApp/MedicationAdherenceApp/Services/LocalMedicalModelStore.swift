import Foundation
#if canImport(BackgroundAssets)
import BackgroundAssets
#endif

struct LocalAIModelManifest: Equatable, Sendable {
    var id: String
    var displayName: String
    var fileName: String
    var format: String
    var estimatedSizeMB: Int
    var recommendedFreeSpaceMB: Int
    var runtime: String
    var license: String
    var downloadURL: URL
    var subdirectoryName: String
    var minimumByteCount: Int64
    var maximumByteCount: Int64

    static let miniCPM4 = LocalAIModelManifest(
        id: "minicpm4-0.5b-qat-int4",
        displayName: "MiniCPM4-0.5B 轻量端侧模型",
        fileName: "MiniCPM4-0.5B-QAT-Int4_gptq_aware_q4_0.gguf",
        format: "gguf",
        estimatedSizeMB: 265,
        recommendedFreeSpaceMB: 700,
        runtime: "llama.cpp",
        license: "Apache-2.0",
        downloadURL: URL(string: "https://huggingface.co/openbmb/MiniCPM4-0.5B-QAT-Int4-GGUF/resolve/main/MiniCPM4-0.5B-QAT-Int4_gptq_aware_q4_0.gguf")!,
        subdirectoryName: "MiniCPM4-0.5B",
        minimumByteCount: 200 * 1024 * 1024,
        maximumByteCount: 350 * 1024 * 1024
    )
}

enum LocalAIModelInstallationStatus: Equatable, Sendable {
    case notInstalled
    case installed
    case invalid
    case loading
    case ready
    case failed(String)
}

enum LocalAIModelValidationError: LocalizedError {
    case invalidFileExtension
    case fileTooSmall(Int64)
    case fileTooLarge(Int64)

    var errorDescription: String? {
        switch self {
        case .invalidFileExtension:
            return "离线模型文件格式不正确。"
        case .fileTooSmall:
            return "离线模型文件不完整，请重新下载。"
        case .fileTooLarge:
            return "离线模型文件大小异常，请重新下载。"
        }
    }
}

struct LocalAIModelManager {
    let manifest: LocalAIModelManifest

    static let miniCPM4 = LocalAIModelManager(manifest: .miniCPM4)

    func applicationSupportURL() throws -> URL {
        guard let applicationSupportURL = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            throw CocoaError(.fileNoSuchFile)
        }
        return applicationSupportURL
    }

    func modelDirectoryURL() throws -> URL {
        try applicationSupportURL()
            .appendingPathComponent("Models", isDirectory: true)
            .appendingPathComponent(manifest.subdirectoryName, isDirectory: true)
    }

    func modelURL() throws -> URL {
        try modelDirectoryURL()
            .appendingPathComponent(manifest.fileName)
    }

    func installationStatus() -> LocalAIModelInstallationStatus {
        do {
            let url = try modelURL()
            guard FileManager.default.fileExists(atPath: url.path) else {
                return .notInstalled
            }
            _ = try validatedModelFile(at: url)
            return .installed
        } catch {
            return .invalid
        }
    }

    func installedModelFile() -> LocalMedicalModelFile? {
        guard let url = try? modelURL(),
              FileManager.default.fileExists(atPath: url.path),
              let modelFile = try? validatedModelFile(at: url)
        else {
            return nil
        }
        return modelFile
    }

    func installDownloadedModel(from temporaryURL: URL) throws -> URL {
        let destinationURL = try modelURL()
        try FileManager.default.createDirectory(
            at: destinationURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try FileManager.default.moveItem(at: temporaryURL, to: destinationURL)
        do {
            _ = try validatedModelFile(at: destinationURL)
            return destinationURL
        } catch {
            try? FileManager.default.removeItem(at: destinationURL)
            throw error
        }
    }

    func deleteModel() throws {
        let url = try modelURL()
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }

    private func validatedModelFile(at url: URL) throws -> LocalMedicalModelFile {
        guard url.lastPathComponent == manifest.fileName,
              url.pathExtension.lowercased() == manifest.format
        else {
            throw LocalAIModelValidationError.invalidFileExtension
        }
        guard let modelFile = LocalMedicalModelFile(url: url) else {
            throw CocoaError(.fileReadUnknown)
        }
        if modelFile.byteCount < manifest.minimumByteCount {
            throw LocalAIModelValidationError.fileTooSmall(modelFile.byteCount)
        }
        if modelFile.byteCount > manifest.maximumByteCount {
            throw LocalAIModelValidationError.fileTooLarge(modelFile.byteCount)
        }
        return modelFile
    }
}

struct LocalMedicalModelStatus: Equatable, Sendable {
    enum Availability: Equatable, Sendable {
        case notDownloaded
        case downloading
        case ready
        case failed
    }

    var availability: Availability
    var displayName: String
    var detailText: String
    var fileSizeText: String?
    var actionTitle: String?
    var canUseForResponses: Bool
    var downloadProgress: Double?
    var downloadedBytes: Int64?
    var expectedBytes: Int64?

    var canStartDownload: Bool {
        availability == .notDownloaded || availability == .failed
    }

    static let notDownloaded = LocalMedicalModelStatus(
        availability: .notDownloaded,
        displayName: "可选下载离线模型",
        detailText: "下载后可在本机尝试用药说明、记录摘要和复诊沟通整理；不下载也可继续使用在线智能体。",
        fileSizeText: nil,
        actionTitle: "下载离线模型",
        canUseForResponses: false,
        downloadProgress: nil,
        downloadedBytes: nil,
        expectedBytes: nil
    )

    static func downloading(progress: Double? = nil, downloadedBytes: Int64? = nil, expectedBytes: Int64? = nil) -> LocalMedicalModelStatus {
        LocalMedicalModelStatus(
            availability: .downloading,
            displayName: "正在下载离线模型",
            detailText: "下载过程中可以继续使用 App。完成后可在本机尝试离线智能体能力。",
            fileSizeText: downloadSizeText(downloadedBytes: downloadedBytes, expectedBytes: expectedBytes),
            actionTitle: nil,
            canUseForResponses: false,
            downloadProgress: progress,
            downloadedBytes: downloadedBytes,
            expectedBytes: expectedBytes
        )
    }

    static let failed = LocalMedicalModelStatus(
        availability: .failed,
        displayName: "下载未完成",
        detailText: "请检查网络后重试。不下载也可继续使用在线智能体。",
        fileSizeText: nil,
        actionTitle: "重新下载",
        canUseForResponses: false,
        downloadProgress: nil,
        downloadedBytes: nil,
        expectedBytes: nil
    )

    private static func downloadSizeText(downloadedBytes: Int64?, expectedBytes: Int64?) -> String? {
        guard let downloadedBytes else {
            return nil
        }
        let downloadedText = ByteCountFormatter.string(fromByteCount: downloadedBytes, countStyle: .file)
        guard let expectedBytes, expectedBytes > 0 else {
            return downloadedText
        }
        let expectedText = ByteCountFormatter.string(fromByteCount: expectedBytes, countStyle: .file)
        return "\(downloadedText) / \(expectedText)"
    }
}

@MainActor
final class LocalMedicalModelStore: ObservableObject {
    nonisolated static let manifest = LocalAIModelManifest.miniCPM4
    nonisolated static let modelFileName = manifest.fileName
    nonisolated static let modelDisplayName = "MiniCPM4 0.5B 离线模型"
    nonisolated static let backgroundAssetsApplicationGroupIdentifier = "group.com.gwyy.appcontest2026.medicationadherence.watch"
    nonisolated private static let modelManager = LocalAIModelManager.miniCPM4
    nonisolated private static let modelDownloadURL = manifest.downloadURL

    @Published private(set) var status: LocalMedicalModelStatus

    init() {
        status = Self.resolveStatus()
    }

    func refresh() {
        guard status.availability != .downloading else {
            return
        }
        status = Self.resolveStatus()
    }

    var readyModelURL: URL? {
        Self.readyModelURL()
    }

    func downloadModel() async {
        guard status.canStartDownload else {
            return
        }
        status = .downloading()

        do {
            let destinationURL = try Self.modelManager.modelURL()
            if FileManager.default.fileExists(atPath: destinationURL.path) {
                status = Self.resolveStatus()
                return
            }

            let temporaryURL = try await Self.downloadModelFile { [weak self] progress, downloadedBytes, expectedBytes in
                Task { @MainActor in
                    guard let self, self.status.availability == .downloading else {
                        return
                    }
                    self.status = .downloading(
                        progress: progress,
                        downloadedBytes: downloadedBytes,
                        expectedBytes: expectedBytes
                    )
                }
            }
            _ = try Self.modelManager.installDownloadedModel(from: temporaryURL)
            status = Self.resolveStatus()
        } catch {
            status = .failed
        }
    }

    private static func resolveStatus() -> LocalMedicalModelStatus {
        guard let modelFile = availableModelFiles().first else {
            return .notDownloaded
        }
        let canUseForResponses = LocalMedicalModelRuntime.isAvailable
        return LocalMedicalModelStatus(
            availability: .ready,
            displayName: Self.modelDisplayName,
            detailText: canUseForResponses
                ? "离线模型已准备好。你可以在希望数据留在本机或网络不稳定时使用离线能力。"
                : "离线模型已下载。离线智能体准备好前，仍可继续使用在线智能体。",
            fileSizeText: ByteCountFormatter.string(fromByteCount: modelFile.byteCount, countStyle: .file),
            actionTitle: nil,
            canUseForResponses: canUseForResponses,
            downloadProgress: nil,
            downloadedBytes: nil,
            expectedBytes: nil
        )
    }

    static func readyModelURL() -> URL? {
        modelManager.installedModelFile()?.url
    }

    private static func availableModelFiles() -> [LocalMedicalModelFile] {
        guard let modelFile = modelManager.installedModelFile() else {
            return []
        }
        return [modelFile]
    }

    private static func downloadModelFile(
        progressHandler: @escaping @Sendable (_ progress: Double?, _ downloadedBytes: Int64, _ expectedBytes: Int64?) -> Void
    ) async throws -> URL {
        try await LocalMedicalModelURLSessionDownloader(
            sourceURL: modelDownloadURL,
            progressHandler: progressHandler
        ).download()
    }

    private static func remoteModelFileSize() async throws -> Int {
        var request = URLRequest(url: modelDownloadURL)
        request.httpMethod = "HEAD"
        request.timeoutInterval = 12
        let (_, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<400).contains(httpResponse.statusCode),
              let contentLength = httpResponse.value(forHTTPHeaderField: "Content-Length"),
              let fileSize = Int(contentLength),
              fileSize > 0
        else {
            throw URLError(.badServerResponse)
        }
        return fileSize
    }

}

struct LocalMedicalModelFile {
    var url: URL
    var byteCount: Int64

    init?(url: URL) {
        guard let resourceValues = try? url.resourceValues(forKeys: [.fileSizeKey]),
              let fileSize = resourceValues.fileSize
        else {
            return nil
        }
        self.url = url
        self.byteCount = Int64(fileSize)
    }
}

private final class LocalMedicalModelURLSessionDownloader: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let sourceURL: URL
    private let progressHandler: @Sendable (_ progress: Double?, _ downloadedBytes: Int64, _ expectedBytes: Int64?) -> Void
    private var continuation: CheckedContinuation<URL, Error>?
    private var session: URLSession?

    init(
        sourceURL: URL,
        progressHandler: @escaping @Sendable (_ progress: Double?, _ downloadedBytes: Int64, _ expectedBytes: Int64?) -> Void
    ) {
        self.sourceURL = sourceURL
        self.progressHandler = progressHandler
    }

    func download() async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            let configuration = URLSessionConfiguration.default
            configuration.timeoutIntervalForRequest = 30
            configuration.timeoutIntervalForResource = 30 * 60
            let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
            self.session = session
            session.downloadTask(with: sourceURL).resume()
        }
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        let expectedBytes = totalBytesExpectedToWrite > 0 ? totalBytesExpectedToWrite : nil
        let progress = expectedBytes.map { min(max(Double(totalBytesWritten) / Double($0), 0), 1) }
        progressHandler(progress, totalBytesWritten, expectedBytes)
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        do {
            let temporaryDirectory = FileManager.default.temporaryDirectory
                .appendingPathComponent("LocalMedicalModelDownloads", isDirectory: true)
            try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
            let temporaryURL = temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension(LocalMedicalModelStore.manifest.format)
            if FileManager.default.fileExists(atPath: temporaryURL.path) {
                try FileManager.default.removeItem(at: temporaryURL)
            }
            try FileManager.default.moveItem(at: location, to: temporaryURL)
            resume(returning: temporaryURL)
        } catch {
            resume(throwing: error)
        }
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        if let error {
            resume(throwing: error)
        }
    }

    private func resume(returning url: URL) {
        let continuation = continuation
        self.continuation = nil
        session?.invalidateAndCancel()
        session = nil
        continuation?.resume(returning: url)
    }

    private func resume(throwing error: Error) {
        let continuation = continuation
        self.continuation = nil
        session?.invalidateAndCancel()
        session = nil
        continuation?.resume(throwing: error)
    }
}
