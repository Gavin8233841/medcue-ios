import MedicationAdherenceCore
import AppIntents
import Darwin
import SwiftData
import SwiftUI
import UserNotifications
#if canImport(ActivityKit)
import ActivityKit
#endif

@main
struct MedicationAdherenceApp: App {
    private let modelContainer: ModelContainer
    private let persistenceStartupFailure: PersistenceStartupFailure?
    private let storeAccess: PersistenceStoreAccess
    @State private var recoveredModelContainer: ModelContainer?
    @AppStorage("appColorSchemePreference") private var appColorSchemePreference = AppColorSchemePreference.system.rawValue

    init() {
        // Recover owned reports left behind when the previous process ended.
        VisitSummaryPDFLifecycle.production().sweepExpiredFiles()

        let storeAccess = PersistenceStoreAccess()
        self.storeAccess = storeAccess
        do {
            #if DEBUG && targetEnvironment(simulator)
            if ProcessInfo.processInfo.arguments.contains("--medcue-simulate-initial-store-open-failure") {
                throw PersistenceStartupTestError.simulatedFailure
            }
            #endif
            #if (DEBUG || MEDCUE_DEMO) && targetEnvironment(simulator)
            let fixture = try ElderUITestFixture.loadIfRequested()
            ElderUITestFixture.active = fixture
            if let fixture {
                modelContainer = fixture.modelContainer
            } else {
                modelContainer = try PersistencePrimaryStoreOpener.make()
            }
            #else
            modelContainer = try PersistencePrimaryStoreOpener.make()
            #endif
            persistenceStartupFailure = nil
            storeAccess.install(modelContainer)
            #if (DEBUG || MEDCUE_DEMO) && targetEnvironment(simulator)
            if fixture == nil {
                MedicationNotificationDelegate.shared.install(modelContainer: modelContainer)
            }
            #else
            MedicationNotificationDelegate.shared.install(modelContainer: modelContainer)
            #endif
        } catch {
            do {
                modelContainer = try MedicationAdherenceModelContainer.make(isStoredInMemoryOnly: true)
                persistenceStartupFailure = PersistenceStartupFailure()
            } catch {
                preconditionFailure("MedicationAdherence schema could not create a recovery container")
            }
        }

        #if (DEBUG || MEDCUE_DEMO) && targetEnvironment(simulator)
        let allowsExternalActions = ElderUITestFixture.active == nil
        #else
        let allowsExternalActions = true
        #endif
        AppDependencyManager.shared.add(
            dependency: MedicationReminderLiveActivityIntentExecutor { request, occurredAt in
                guard let activeContainer = storeAccess.current(), allowsExternalActions else {
                    return .saveFailed
                }
                return await MedicationReminderLiveActivityActionService(
                    notificationService: NotificationService()
                ).executeIntentMarkTaken(
                    request,
                    occurredAt: occurredAt,
                    in: activeContainer.mainContext
                )
            }
        )
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if persistenceStartupFailure != nil && recoveredModelContainer == nil {
                    PersistenceRecoveryView {
                        let reopened = try PersistencePrimaryStoreOpener.make()
                        MedicationNotificationDelegate.shared.install(modelContainer: reopened)
                        storeAccess.install(reopened)
                        recoveredModelContainer = reopened
                    }
                } else {
                    AppRootView()
                        #if (DEBUG || MEDCUE_DEMO) && targetEnvironment(simulator)
                        .defaultAppStorage(ElderUITestFixture.active?.preferences ?? .standard)
                        #endif
                        #if DEBUG
                        .task {
                            await MedicalAISmokeTestRunner.runIfRequested()
                            await ReminderLiveActivitySmokeTestRunner.runIfRequested(modelContainer: modelContainer)
                            await LocalMedicalModelSmokeTestRunner.runIfRequested()
                        }
                        #endif
                }
            }
            .preferredColorScheme(AppColorSchemePreference(rawValue: appColorSchemePreference)?.colorScheme)
        }
        .modelContainer(recoveredModelContainer ?? modelContainer)
    }
}

private struct PersistenceStartupFailure {}

private enum PersistencePrimaryStoreOpener {
    static func make() throws -> ModelContainer {
        #if DEBUG && targetEnvironment(simulator)
        if ProcessInfo.processInfo.arguments.contains("--medcue-simulate-retry-store-open-failure") {
            throw PersistenceStartupTestError.simulatedFailure
        }
        if ProcessInfo.processInfo.arguments.contains("--medcue-recovery-isolated-test-store") {
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("medcue-recovery-ui-synthetic.store")
            return try MedicationAdherenceModelContainer.make(storeURL: url)
        }
        #endif
        return try MedicationAdherenceModelContainer.make()
    }
}

#if DEBUG && targetEnvironment(simulator)
private enum PersistenceStartupTestError: Error {
    case simulatedFailure
}
#endif

private final class PersistenceStoreAccess: @unchecked Sendable {
    private let lock = NSLock()
    private var container: ModelContainer?

    func install(_ container: ModelContainer) {
        lock.lock()
        self.container = container
        lock.unlock()
    }

    func current() -> ModelContainer? {
        lock.lock()
        defer { lock.unlock() }
        return container
    }
}

private struct PersistenceRecoveryView: View {
    let onRetry: () throws -> Void
    @State private var failureStage = "initial"
    @State private var statusMessage = ""
    @State private var isExporting = false
    @State private var shareURLs: [URL] = []
    @State private var showingShareSheet = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Label("暂时无法打开本机用药记录", systemImage: "externaldrive.badge.exclamationmark")
                    .font(.title2.bold())
                Text("现有记录没有被删除或重建。此页面不能新增或修改用药记录。")
                Button("重试读取原记录") {
                    do {
                        try onRetry()
                    } catch {
                        failureStage = "retry"
                        statusMessage = "仍无法打开原记录。请保留当前设备数据，可再次重试或保存诊断信息。"
                    }
                }
                .buttonStyle(.borderedProminent)

                Button("导出脱敏诊断信息") {
                    exportDiagnostic()
                }
                .disabled(isExporting)

                Button("保存敏感原始副本") {
                    exportSensitiveCopy()
                }
                .disabled(isExporting)

                Text("原始副本包含完整用药等私人数据，仅供后续人工分析。目前没有经过测试的应用内导入恢复功能，副本不保证可恢复。主动分享到其他位置后，该位置的保护不受本 App 控制。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Text("全新开始暂不可用：需要先有经过测试的恢复路径，避免清空唯一记录。")
                    .font(.footnote)

                if isExporting {
                    ProgressView("正在准备文件")
                }
                if !statusMessage.isEmpty {
                    Text(statusMessage)
                        .accessibilityIdentifier("recovery.status")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(24)
        }
        .sheet(isPresented: $showingShareSheet) {
            PersistenceRecoveryShareSheet(urls: shareURLs)
        }
    }

    private func exportDiagnostic() {
        isExporting = true
        statusMessage = ""
        let stage = failureStage
        Task {
            do {
                let output = try await Task.detached {
                    try PersistenceRecoveryExport.production().makeDiagnostic(stage: stage)
                }.value
                shareURLs = [output]
                showingShareSheet = true
                statusMessage = "诊断文件已准备好；只包含版本、系统版本、失败类别与生成时间。"
            } catch {
                statusMessage = "诊断文件未能生成。原始记录保持不变，请稍后重试。"
            }
            isExporting = false
        }
    }

    private func exportSensitiveCopy() {
        isExporting = true
        statusMessage = ""
        Task {
            do {
                let outputs = try await Task.detached {
                    try PersistenceRecoveryExport.production().makeSensitiveCopy()
                }.value
                shareURLs = outputs
                showingShareSheet = true
                statusMessage = "已生成受保护的原始副本；应用内不提供导入恢复。"
            } catch {
                statusMessage = "原始副本未能完成或验证。原始记录保持不变，请稍后重试。"
            }
            isExporting = false
        }
    }
}

private struct PersistenceRecoveryShareSheet: UIViewControllerRepresentable {
    let urls: [URL]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: urls, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

#if DEBUG
private enum MedicalAISmokeTestRunner {
    @MainActor private static var didRun = false

    @MainActor
    static func runIfRequested() async {
        guard ProcessInfo.processInfo.arguments.contains("--medical-ai-smoke-test") else {
            return
        }
        guard !didRun else {
            return
        }
        didRun = true

        let store = SecureAIConfigurationStore()
        let configuration = store.refreshInjectedSecretsIfAvailable()
        let readiness = store.readiness(for: configuration)
        print("[MedicalAI-Smoke] readiness \(configuration.sanitizedDebugSummary) transport=\(readiness.diagnosticSummary)")

        guard readiness.canSend, let apiKey = store.apiKey(for: configuration), !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            print("[MedicalAI-Smoke] failure missing-api-key-or-configuration")
            return
        }

        await performSmokeRequest(configuration: configuration, apiKey: apiKey)
    }

    private static func performSmokeRequest(configuration: MedicalAIConfiguration, apiKey: String) async {
        do {
            let response = try await withThrowingTaskGroup(of: MedicalAIResponse.self) { group in
                group.addTask {
                    let client = MedicalAIClientFactory.make(
                        configuration: configuration,
                        credential: apiKey
                    )
                    return try await client.respond(to: MedicalAIRequest(
                        kind: .chat,
                        userMessage: "请用一句话回复医疗智能体连通测试。",
                        authorization: MedicalAIUserAuthorization(
                            grantedScopes: [],
                            note: "Debug 实机连通性自检，不包含个人用药数据。"
                        ),
                        localeIdentifier: "zh_CN"
                    ))
                }
                group.addTask {
                    try await Task.sleep(for: .seconds(20))
                    throw MedicalAISmokeTimeoutError()
                }

                guard let response = try await group.next() else {
                    throw MedicalAISmokeTimeoutError()
                }
                group.cancelAll()
                return response
            }
            print("[MedicalAI-Smoke] success provider=\(response.provider.providerName) model=\(response.provider.modelName) responseLength=\(response.message.count)")
        } catch {
            print("[MedicalAI-Smoke] failure \(diagnosticSummary(for: error))")
        }
    }

    private static func diagnosticSummary(for error: Error) -> String {
        if let error = error as? CloudBaseMedicalAIError {
            return "broker=\(error.diagnosticSummary)"
        }
        if let error = error as? DoubaoMedicalAIError {
            return "doubao=\(error.diagnosticSummary)"
        }
        if let error = error as? BaichuanMedicalAIError {
            return "baichuan=\(error.diagnosticSummary)"
        }
        if let error = error as? URLError {
            return "url-error code=\(error.code.rawValue)"
        }
        if error is MedicalAISmokeTimeoutError {
            return "request-timeout"
        }
        return "type=\(String(describing: Swift.type(of: error)))"
    }
}

private struct MedicalAISmokeTimeoutError: Error {}

enum ReminderLiveActivitySmokeDiagnostic {
    static let setupCompleteLine = "[ReminderLiveActivity-Smoke] setup-complete"

    static func stateLine(
        notificationAuthorized: Bool,
        pendingBaseNotificationCount: Int,
        activeLiveActivityCount: Int
    ) -> String {
        "[ReminderLiveActivity-Smoke] notificationAuthorized=\(notificationAuthorized) "
            + "pendingBaseNotifications=\(bounded(pendingBaseNotificationCount)) "
            + "activeLiveActivities=\(bounded(activeLiveActivityCount))"
    }

    private static func bounded(_ count: Int) -> Int {
        min(max(count, 0), 999)
    }
}

private enum ReminderLiveActivitySmokeTestRunner {
    @MainActor private static var didRun = false

    @MainActor
    static func runIfRequested(modelContainer: ModelContainer) async {
        guard ProcessInfo.processInfo.arguments.contains("--reminder-live-activity-smoke-test") else {
            return
        }
        guard !didRun else {
            return
        }
        didRun = true

        let context = modelContainer.mainContext
        DemoDataSeeder.seedIfNeeded(in: context)

        let medications = (try? context.fetch(FetchDescriptor<StoredMedication>())) ?? []
        let demoMedicationIDs = Set(medications.filter(\.isDemoContent).map(\.id))
        guard let task = smokeTask(in: context, demoMedicationIDs: demoMedicationIDs),
              let medication = medications.first(where: { $0.id == task.medicationID })
        else {
            print("[ReminderLiveActivity-Smoke] failure demo-task-missing")
            finish(1)
        }

        let dueAt = Date().addingTimeInterval(120)
        task.dueAt = dueAt
        task.status = .pending
        task.recordedAt = nil
        task.reason = "Debug 真机提醒与实况活动自检"
        guard AppPersistenceCommitter.save(context, operation: "live-activity-smoke-setup") else {
            print("[ReminderLiveActivity-Smoke] failure persistence-save")
            finish(1)
        }

        let notificationService = NotificationService()
        let hasNotificationAuthorization = await notificationService.hasUsableNotificationAuthorization()
        if hasNotificationAuthorization {
            await notificationService.scheduleReminder(
                for: task,
                medication: medication,
                escalatesToAlarmWhenUnhandled: true
            )
        }

        await MedicationLiveActivityService().startIfNeeded(for: task, medication: medication)
        let pendingNotificationCount = await pendingBaseNotificationCount(prefix: notificationService.notificationIdentifierPrefix)
        let activeActivityCount = activeLiveActivityCount(for: task.id)
        print(ReminderLiveActivitySmokeDiagnostic.setupCompleteLine)
        print(ReminderLiveActivitySmokeDiagnostic.stateLine(
            notificationAuthorized: hasNotificationAuthorization,
            pendingBaseNotificationCount: pendingNotificationCount,
            activeLiveActivityCount: activeActivityCount
        ))
        finish(hasNotificationAuthorization && pendingNotificationCount > 0 && activeActivityCount > 0 ? 0 : 1)
    }

    @MainActor
    private static func smokeTask(in context: ModelContext, demoMedicationIDs: Set<UUID>) -> StoredDoseTask? {
        let tasks = ((try? context.fetch(FetchDescriptor<StoredDoseTask>())) ?? [])
            .filter { demoMedicationIDs.contains($0.medicationID) }
            .sorted { lhs, rhs in
                if lhs.status == rhs.status {
                    return lhs.dueAt < rhs.dueAt
                }
                return statusRank(lhs.status) < statusRank(rhs.status)
            }
        return tasks.first
    }

    private static func statusRank(_ status: StoredDoseStatus) -> Int {
        switch status {
        case .pending, .delayed:
            return 0
        case .skipped:
            return 1
        case .taken, .corrected:
            return 2
        }
    }

    private static func pendingBaseNotificationCount(prefix: String) async -> Int {
        let requests = await UNUserNotificationCenter.current().pendingNotificationRequests()
        return requests.filter { $0.identifier.hasPrefix(prefix) && !$0.identifier.contains(".escalation.") }.count
    }

    private static func activeLiveActivityCount(for taskID: UUID) -> Int {
        #if canImport(ActivityKit)
        if #available(iOS 16.2, *) {
            return Activity<MedicationReminderActivityAttributes>.activities.filter { $0.attributes.taskID == taskID }.count
        }
        #endif
        return 0
    }

    private static func finish(_ code: Int32) -> Never {
        fflush(stdout)
        fflush(stderr)
        Darwin.exit(code)
    }
}

private enum LocalMedicalModelSmokeTestRunner {
    @MainActor private static var didRun = false

    @MainActor
    static func runIfRequested() async {
        guard ProcessInfo.processInfo.arguments.contains("--local-medical-model-smoke-test") else {
            return
        }
        guard !didRun else {
            return
        }
        didRun = true

        guard LocalMedicalModelRuntime.isAvailable else {
            print("[LocalMedicalModel-Smoke] failure runtime-unavailable")
            finish(1)
        }

        guard let modelURL = LocalMedicalModelStore.readyModelURL() else {
            print("[LocalMedicalModel-Smoke] failure model-missing")
            finish(1)
        }

        let repeatCount = smokeRepeatCount()
        var succeeded = await performSmokeRequests(modelURL: modelURL, repeatCount: repeatCount)
        if succeeded && ProcessInfo.processInfo.environment["LOCAL_MODEL_SMOKE_CANCEL_PROBE"] == "1" {
            if await performCancellationProbe(modelURL: modelURL) {
                succeeded = await performSmokeRequest(modelURL: modelURL, index: repeatCount + 1)
            } else {
                succeeded = false
            }
        }
        finish(succeeded ? 0 : 1)
    }

    private static func smokeRepeatCount() -> Int {
        let value = ProcessInfo.processInfo.environment["LOCAL_MODEL_SMOKE_REPEAT_COUNT"] ?? "1"
        guard let count = Int(value), count > 0 else {
            return 1
        }
        return min(count, 20)
    }

    private static func performSmokeRequests(modelURL: URL, repeatCount: Int) async -> Bool {
        var failureCount = 0
        for index in 1...repeatCount {
            let succeeded = await performSmokeRequest(modelURL: modelURL, index: index)
            if !succeeded {
                failureCount += 1
            }
        }
        print("[LocalMedicalModel-Smoke] summary total=\(repeatCount) failures=\(failureCount)")
        return failureCount == 0
    }

    private static func performSmokeRequest(modelURL: URL, index: Int) async -> Bool {
        do {
            let response = try await withThrowingTaskGroup(of: MedicalAIResponse.self) { group in
                group.addTask {
                    let client = LocalMedicalAIClient(modelURL: modelURL)
                    return try await client.respond(to: MedicalAIRequest(
                        kind: .chat,
                        userMessage: smokePrompt(for: index),
                        authorization: MedicalAIUserAuthorization(
                            grantedScopes: [],
                            note: "Debug 本机推理自检，不包含个人用药数据。"
                        ),
                        localeIdentifier: "zh_CN"
                    ))
                }
                group.addTask {
                    try await Task.sleep(for: .seconds(60))
                    throw LocalMedicalModelSmokeTimeoutError()
                }

                guard let response = try await group.next() else {
                    throw LocalMedicalModelSmokeTimeoutError()
                }
                group.cancelAll()
                return response
            }
            print("[LocalMedicalModel-Smoke] success index=\(index) provider=\(response.provider.providerName) model=\(response.provider.modelName) responseLength=\(response.message.count)")
            return true
        } catch {
            print("[LocalMedicalModel-Smoke] failure index=\(index) \(diagnosticSummary(for: error))")
            return false
        }
    }

    @MainActor
    private static func performCancellationProbe(modelURL: URL) async -> Bool {
        let runtime = LocalMedicalModelRuntime.shared
        let generation = runtime.generateResponseStream(
            prompt: "请写一段至少一千字的合成文字，用于验证本机推理取消，不涉及个人用药信息。",
            modelURL: modelURL,
            maxTokens: 512
        )
        let firstToken = AsyncStream<Void>.makeStream()
        let state = LocalModelCancellationProbeState()
        let collector = Task {
            do {
                for try await delta in generation.stream where !delta.isEmpty {
                    firstToken.continuation.yield(())
                }
            } catch {
                // Cancellation is the expected end of this probe.
            }
            await state.markFinished()
            firstToken.continuation.finish()
        }
        let firstTokenTimeout = Task {
            do {
                try await Task.sleep(for: .seconds(45))
            } catch {
                return
            }
            generation.cancel()
            firstToken.continuation.finish()
        }
        var tokenIterator = firstToken.stream.makeAsyncIterator()
        let observedToken = await tokenIterator.next() != nil
        firstTokenTimeout.cancel()
        let completedBeforeCancel = await state.isFinished
        let cancellationStartedAt = Date()
        generation.cancel()

        // The runtime actor is occupied by synchronous native generation. This
        // read can return only after its native context has exited and freed.
        let cancellationTimeout = Task.detached {
            do {
                try await Task.sleep(for: .seconds(15))
            } catch {
                return
            }
            print("[LocalMedicalModel-Smoke] failure cancellation-stalled")
            fflush(stdout)
            Darwin.exit(1)
        }
        _ = await runtime.isReady
        cancellationTimeout.cancel()
        await collector.value
        let elapsed = Date().timeIntervalSince(cancellationStartedAt)
        let passed = observedToken && !completedBeforeCancel && elapsed <= 5
        print("[LocalMedicalModel-Smoke] cancellation observedToken=\(observedToken) activeBeforeCancel=\(!completedBeforeCancel) releaseSeconds=\(String(format: "%.3f", elapsed)) passed=\(passed)")
        return passed
    }

    private static func smokePrompt(for index: Int) -> String {
        let prompts = [
            "请用一句话回复离线智能体本机推理测试。",
            "请用一句话说明按时记录用药的意义。",
            "请用两句话说明为什么要复诊时带上用药记录。",
            "请用一句话提醒用户核对药盒和说明书。",
            "请用两句话说明漏服记录为什么需要及时补充。"
        ]
        return prompts[(index - 1) % prompts.count]
    }

    private static func finish(_ code: Int32) -> Never {
        fflush(stdout)
        fflush(stderr)
        Darwin.exit(code)
    }

    private static func diagnosticSummary(for error: Error) -> String {
        if let error = error as? LocalMedicalAIError {
            return "local=\(error.diagnosticSummary)"
        }
        if error is LocalMedicalModelSmokeTimeoutError {
            return "request-timeout"
        }
        return "type=\(String(describing: Swift.type(of: error)))"
    }
}

private struct LocalMedicalModelSmokeTimeoutError: Error {}

private actor LocalModelCancellationProbeState {
    private(set) var isFinished = false

    func markFinished() {
        isFinished = true
    }
}
#endif
