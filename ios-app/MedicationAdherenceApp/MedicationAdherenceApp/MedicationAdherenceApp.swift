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
    @AppStorage("appColorSchemePreference") private var appColorSchemePreference = AppColorSchemePreference.system.rawValue

    init() {
        let isPersistentStoreAvailable: Bool
        do {
            modelContainer = try MedicationAdherenceModelContainer.make()
            persistenceStartupFailure = nil
            isPersistentStoreAvailable = true
            MedicationNotificationDelegate.shared.install(modelContainer: modelContainer)
        } catch {
            do {
                modelContainer = try MedicationAdherenceModelContainer.make(isStoredInMemoryOnly: true)
                persistenceStartupFailure = PersistenceStartupFailure()
                isPersistentStoreAvailable = false
            } catch {
                preconditionFailure("MedicationAdherence schema could not create a recovery container")
            }
        }

        let intentModelContainer = modelContainer
        AppDependencyManager.shared.add(
            dependency: MedicationReminderLiveActivityIntentExecutor { request, occurredAt in
                guard isPersistentStoreAvailable else {
                    return .saveFailed
                }
                return await MedicationReminderLiveActivityActionService(
                    notificationService: NotificationService()
                ).executeIntentMarkTaken(
                    request,
                    occurredAt: occurredAt,
                    in: intentModelContainer.mainContext
                )
            }
        )
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if persistenceStartupFailure != nil {
                    PersistenceRecoveryView()
                } else {
                    AppRootView()
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
        .modelContainer(modelContainer)
    }
}

private struct PersistenceStartupFailure {}

private struct PersistenceRecoveryView: View {
    var body: some View {
        ContentUnavailableView {
            Label("暂时无法读取用药记录", systemImage: "externaldrive.badge.exclamationmark")
        } description: {
            Text("App 没有删除或重建现有数据。请先重新启动 App；如果仍然出现此页面，请保留当前设备数据并联系开发团队协助恢复。")
        }
        .padding(24)
        .accessibilityElement(children: .combine)
    }
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
        let succeeded = await performSmokeRequests(modelURL: modelURL, repeatCount: repeatCount)
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
#endif
