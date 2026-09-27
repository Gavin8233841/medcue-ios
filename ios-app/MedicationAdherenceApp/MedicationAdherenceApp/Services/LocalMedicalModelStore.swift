import Foundation
import CryptoKit
import os
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
    var exactByteCount: Int64
    var expectedSHA256: String

    static let miniCPM4 = LocalAIModelManifest(
        id: "minicpm4-0.5b-qat-int4",
        displayName: "MiniCPM4-0.5B 轻量端侧模型",
        fileName: "MiniCPM4-0.5B-QAT-Int4_gptq_aware_q4_0.gguf",
        format: "gguf",
        estimatedSizeMB: 265,
        recommendedFreeSpaceMB: 700,
        runtime: "llama.cpp",
        license: "Apache-2.0",
        downloadURL: {
            guard let url = URL(string: "https://huggingface.co/openbmb/MiniCPM4-0.5B-QAT-Int4-GGUF/resolve/4d70679dbea99c0dfa7bef0c6fa1bffc25997246/MiniCPM4-0.5B-QAT-Int4_gptq_aware_q4_0.gguf") else {
                preconditionFailure("The bundled local-model endpoint is invalid")
            }
            return url
        }(),
        subdirectoryName: "MiniCPM4-0.5B",
        minimumByteCount: 200 * 1024 * 1024,
        maximumByteCount: 350 * 1024 * 1024,
        exactByteCount: 265_307_040,
        expectedSHA256: "fa4ad3f448355578ce5e4021204be319e5a3cb665fb173607f92bc139c96a290"
    )
}

enum LocalMedicalModelDownloadSource {
    static let acceleratedURL = URL(string: "https://medcue-model-delivery.guo8233841.workers.dev/v1/model/minicpm4-0.5b")!

    static func isValidAccessCode(_ code: String) -> Bool {
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.count == 32 && trimmed.utf8.allSatisfy { byte in
            (48...57).contains(byte) || (97...102).contains(byte)
        }
    }

    static func request(accessCode: String?) throws -> URLRequest {
        guard let accessCode else {
            return URLRequest(url: LocalAIModelManifest.miniCPM4.downloadURL)
        }
        let trimmed = accessCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isValidAccessCode(trimmed) else {
            throw URLError(.userAuthenticationRequired)
        }
        var request = URLRequest(url: acceleratedURL)
        request.setValue("Bearer \(trimmed)", forHTTPHeaderField: "Authorization")
        return request
    }

    static func allowsRedirect(from sourceRequest: URLRequest, to destinationURL: URL?) -> Bool {
        guard let destinationURL, destinationURL.scheme?.lowercased() == "https" else {
            return false
        }
        if sourceRequest.value(forHTTPHeaderField: "Authorization") != nil {
            return destinationURL.host == sourceRequest.url?.host
        }
        return true
    }

    static func failureDetail(for error: Error, accelerated: Bool) -> String {
        if accelerated, let downloadError = error as? LocalMedicalModelDownloadError {
            switch downloadError {
            case .httpStatus(404):
                return "下载码无效或已停用，请重新获取后重试。"
            case .httpStatus(429):
                return "下载请求过于频繁，请稍后重试。"
            case .httpStatus(_):
                return "加速下载服务暂不可用，请稍后重试或选择标准下载。"
            }
        }
        return "下载未完成，请检查网络后重试。"
    }
}

enum LocalMedicalModelDownloadError: Error {
    case httpStatus(Int)
}

enum LocalAIModelInstallationStatus: Equatable, Sendable {
    case notInstalled
    case installed
    case invalid
    case loading
    case ready
    case failed(String)
}

enum LocalAIModelValidationError: LocalizedError, Equatable {
    case invalidFileExtension
    case fileTooSmall(Int64)
    case fileTooLarge(Int64)
    case unexpectedByteCount(expected: Int64, actual: Int64)
    case checksumMismatch

    var errorDescription: String? {
        switch self {
        case .invalidFileExtension:
            return "离线模型文件格式不正确。"
        case .fileTooSmall:
            return "离线模型文件不完整，请重新下载。"
        case .fileTooLarge:
            return "离线模型文件大小异常，请重新下载。"
        case .unexpectedByteCount:
            return "离线模型文件大小与官方版本不一致，请重新下载。"
        case .checksumMismatch:
            return "离线模型完整性校验未通过，请重新下载。"
        }
    }
}

struct LocalAIModelManager: Sendable {
    let manifest: LocalAIModelManifest
    var applicationSupportOverrideURL: URL?

    static let miniCPM4 = LocalAIModelManager(
        manifest: .miniCPM4,
        applicationSupportOverrideURL: nil
    )

    func applicationSupportURL() throws -> URL {
        if let applicationSupportOverrideURL {
            return applicationSupportOverrideURL
        }
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
            _ = try validatedModelFile(at: url, requiresCanonicalName: true)
            return .installed
        } catch {
            return .invalid
        }
    }

    func installedModelFile() -> LocalMedicalModelFile? {
        guard let url = try? modelURL(),
              FileManager.default.fileExists(atPath: url.path),
              let modelFile = try? validatedModelFile(at: url, requiresCanonicalName: true)
        else {
            return nil
        }
        return modelFile
    }

    func installDownloadedModel(from temporaryURL: URL) throws -> URL {
        defer {
            if FileManager.default.fileExists(atPath: temporaryURL.path) {
                try? FileManager.default.removeItem(at: temporaryURL)
            }
        }
        _ = try validatedModelFile(at: temporaryURL, requiresCanonicalName: false)
        let digest = try sha256HexDigest(of: temporaryURL)
        guard digest == manifest.expectedSHA256.lowercased() else {
            throw LocalAIModelValidationError.checksumMismatch
        }

        let destinationURL = try modelURL()
        let destinationDirectoryURL = destinationURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: destinationDirectoryURL,
            withIntermediateDirectories: true
        )
        try setExcludedFromBackup(destinationDirectoryURL)

        let stagedURL = destinationDirectoryURL
            .appendingPathComponent(".\(UUID().uuidString).installing")
            .appendingPathExtension(manifest.format)
        defer {
            if FileManager.default.fileExists(atPath: stagedURL.path) {
                try? FileManager.default.removeItem(at: stagedURL)
            }
        }
        try FileManager.default.moveItem(at: temporaryURL, to: stagedURL)
        try setExcludedFromBackup(stagedURL)

        if FileManager.default.fileExists(atPath: destinationURL.path) {
            _ = try FileManager.default.replaceItemAt(
                destinationURL,
                withItemAt: stagedURL,
                backupItemName: nil,
                options: []
            )
        } else {
            try FileManager.default.moveItem(at: stagedURL, to: destinationURL)
        }
        try setExcludedFromBackup(destinationURL)
        _ = try validatedModelFile(at: destinationURL, requiresCanonicalName: true)
        return destinationURL
    }

    func deleteModel() throws {
        let url = try modelURL()
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }

    private func validatedModelFile(
        at url: URL,
        requiresCanonicalName: Bool
    ) throws -> LocalMedicalModelFile {
        guard (!requiresCanonicalName || url.lastPathComponent == manifest.fileName),
              url.pathExtension.lowercased() == manifest.format.lowercased()
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
        if modelFile.byteCount != manifest.exactByteCount {
            throw LocalAIModelValidationError.unexpectedByteCount(
                expected: manifest.exactByteCount,
                actual: modelFile.byteCount
            )
        }
        return modelFile
    }

    private func sha256HexDigest(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer {
            try? handle.close()
        }
        var hasher = SHA256()
        while let data = try handle.read(upToCount: 1_048_576), !data.isEmpty {
            hasher.update(data: data)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private func setExcludedFromBackup(_ url: URL) throws {
        var resourceValues = URLResourceValues()
        resourceValues.isExcludedFromBackup = true
        var mutableURL = url
        try mutableURL.setResourceValues(resourceValues)
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

    static func failed(detailText: String) -> LocalMedicalModelStatus {
        LocalMedicalModelStatus(
            availability: .failed,
            displayName: "下载未完成",
            detailText: detailText,
            fileSizeText: nil,
            actionTitle: "重新下载",
            canUseForResponses: false,
            downloadProgress: nil,
            downloadedBytes: nil,
            expectedBytes: nil
        )
    }

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

    func downloadModel(accessCode: String? = nil) async {
        guard status.canStartDownload else {
            return
        }
        status = .downloading()

        do {
            let destinationURL = try Self.modelManager.modelURL()
            if Self.modelManager.installedModelFile() != nil {
                status = Self.resolveStatus()
                return
            }
            if FileManager.default.fileExists(atPath: destinationURL.path) {
                try Self.modelManager.deleteModel()
            }

            let temporaryURL = try await Self.downloadModelFile(accessCode: accessCode) { [weak self] progress, downloadedBytes, expectedBytes in
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
            _ = try await Task.detached(priority: .utility) {
                try Self.modelManager.installDownloadedModel(from: temporaryURL)
            }.value
            status = Self.resolveStatus()
        } catch {
            status = .failed(detailText: LocalMedicalModelDownloadSource.failureDetail(
                for: error,
                accelerated: accessCode != nil
            ))
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
        accessCode: String?,
        progressHandler: @escaping @Sendable (_ progress: Double?, _ downloadedBytes: Int64, _ expectedBytes: Int64?) -> Void
    ) async throws -> URL {
        try await LocalMedicalModelURLSessionDownloader(
            sourceRequest: try LocalMedicalModelDownloadSource.request(accessCode: accessCode),
            progressHandler: progressHandler
        ).download()
    }

    private static func remoteModelFileSize() async throws -> Int {
        var request = URLRequest(url: manifest.downloadURL)
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

private final class LocalMedicalModelURLSessionDownloader: NSObject, URLSessionDownloadDelegate, Sendable {
    private struct DownloadState {
        var continuation: CheckedContinuation<URL, Error>?
        var session: URLSession?
        var isCancelled = false
    }

    private let sourceRequest: URLRequest
    private let progressHandler: @Sendable (_ progress: Double?, _ downloadedBytes: Int64, _ expectedBytes: Int64?) -> Void
    private let stateLock = OSAllocatedUnfairLock(initialState: DownloadState())

    init(
        sourceRequest: URLRequest,
        progressHandler: @escaping @Sendable (_ progress: Double?, _ downloadedBytes: Int64, _ expectedBytes: Int64?) -> Void
    ) {
        self.sourceRequest = sourceRequest
        self.progressHandler = progressHandler
    }

    func download() async throws -> URL {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let configuration = URLSessionConfiguration.default
                configuration.timeoutIntervalForRequest = 30
                configuration.timeoutIntervalForResource = 30 * 60
                let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
                let shouldStart = stateLock.withLock { state in
                    guard !state.isCancelled, state.continuation == nil else {
                        return false
                    }
                    state.continuation = continuation
                    state.session = session
                    return true
                }
                guard shouldStart else {
                    session.invalidateAndCancel()
                    continuation.resume(throwing: CancellationError())
                    return
                }
                session.downloadTask(with: sourceRequest).resume()
            }
        } onCancel: {
            cancelDownload()
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
            guard let response = downloadTask.response as? HTTPURLResponse else {
                throw URLError(.badServerResponse)
            }
            guard (200..<300).contains(response.statusCode) else {
                throw LocalMedicalModelDownloadError.httpStatus(response.statusCode)
            }
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
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        guard LocalMedicalModelDownloadSource.allowsRedirect(from: sourceRequest, to: request.url) else {
            completionHandler(nil)
            return
        }
        completionHandler(request)
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
        let completion = takeCompletion()
        completion?.session.invalidateAndCancel()
        completion?.continuation.resume(returning: url)
    }

    private func resume(throwing error: Error) {
        let completion = takeCompletion()
        completion?.session.invalidateAndCancel()
        completion?.continuation.resume(throwing: error)
    }

    private func cancelDownload() {
        let completion = stateLock.withLock { state -> (CheckedContinuation<URL, Error>, URLSession)? in
            state.isCancelled = true
            guard let continuation = state.continuation, let session = state.session else {
                return nil
            }
            state.continuation = nil
            state.session = nil
            return (continuation, session)
        }
        completion?.1.invalidateAndCancel()
        completion?.0.resume(throwing: CancellationError())
    }

    private func takeCompletion() -> (continuation: CheckedContinuation<URL, Error>, session: URLSession)? {
        stateLock.withLock { state in
            guard let continuation = state.continuation, let session = state.session else {
                return nil
            }
            state.continuation = nil
            state.session = nil
            return (continuation, session)
        }
    }
}
