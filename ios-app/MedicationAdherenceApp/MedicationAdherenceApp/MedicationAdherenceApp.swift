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
            #if DEBUG
            #if targetEnvironment(simulator)
            let isGalleryPreview = ProcessInfo.processInfo.arguments.contains("--medication-gallery-preview")
            #else
            let isGalleryPreview = false
            #endif
            let isUIFixture = isGalleryPreview || ProcessInfo.processInfo.arguments.contains("--assistant-ui-preview")
            #else
            let isUIFixture = false
            #endif
            modelContainer = try MedicationAdherenceModelContainer.make(isStoredInMemoryOnly: isUIFixture)
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
                #if DEBUG
                if ProcessInfo.processInfo.arguments.contains("--assistant-ui-preview") {
                    AssistantUIFixture()
                } else {
                    mainContent
                }
                #else
                mainContent
                #endif
            }
            .preferredColorScheme(AppColorSchemePreference(rawValue: appColorSchemePreference)?.colorScheme)
        }
        .modelContainer(modelContainer)
    }

    private var mainContent: some View {
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
    private struct GeneratedOutput: Sendable {
        var answer = ""
        var thinking = ""
    }

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

        let candidateURL = try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: false)
            .appendingPathComponent("Models/Qwen2.5-1.5B/qwen2.5-1.5b-instruct-q4_k_m.gguf")
        let miniCPM5URL = try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: false)
            .appendingPathComponent("Models/MiniCPM5-2B/MiniCPM5-2B-Q4_K_M.gguf")
        let selectedURL = ProcessInfo.processInfo.arguments.contains("--local-medical-model-smoke-minicpm5")
            ? miniCPM5URL
            : (ProcessInfo.processInfo.arguments.contains("--local-medical-model-smoke-qwen")
                ? candidateURL : LocalMedicalModelStore.readyModelURL())
        guard let modelURL = selectedURL, FileManager.default.fileExists(atPath: modelURL.path) else {
            print("[LocalMedicalModel-Smoke] failure model-missing")
            finish(1)
        }

        print("[LocalMedicalModel-Smoke] candidate=\(modelURL.lastPathComponent)")
        let repeatCount = smokeRepeatCount()
        let succeeded = await performSmokeRequests(modelURL: modelURL, repeatCount: repeatCount)
        finish(succeeded ? 0 : 1)
    }

    private static func smokeRepeatCount() -> Int {
        let value = ProcessInfo.processInfo.environment["LOCAL_MODEL_SMOKE_REPEAT_COUNT"] ?? "1"
        guard let count = Int(value), count > 0 else {
            return 1
        }
        return min(count, 35)
    }

    private static func performSmokeRequests(modelURL: URL, repeatCount: Int) async -> Bool {
        var failureCount = 0
        let startIndex = max(1, min(53, Int(ProcessInfo.processInfo.environment["LOCAL_MODEL_SMOKE_START_INDEX"] ?? "1") ?? 1))
        for offset in 0..<repeatCount {
            let index = startIndex + offset
            let succeeded = await performSmokeRequest(modelURL: modelURL, index: index)
            if !succeeded {
                failureCount += 1
            }
        }
        print("[LocalMedicalModel-Smoke] summary total=\(repeatCount) failures=\(failureCount)")
        return failureCount == 0
    }

    private static func performSmokeRequest(modelURL: URL, index: Int) async -> Bool {
        let startedAt = ContinuousClock.now
        do {
            let output = try await withThrowingTaskGroup(of: GeneratedOutput.self) { group in
                group.addTask {
                    let client = LocalMedicalAIClient(modelURL: modelURL, runtime: LocalMedicalModelRuntime(thinkingEnabled: ProcessInfo.processInfo.arguments.contains("--local-medical-model-smoke-thinking")), diagnosticSink: { text in
                        print("[LocalMedicalModel-Raw] index=\(index) \(text)")
                    })
                    var request = MedicalAIRequest(
                        kind: .chat,
                        userMessage: smokePrompt(for: index),
                        authorization: MedicalAIUserAuthorization(
                            grantedScopes: index > 20 ? [.medicationProfile, .doseEvents] : [],
                            note: "Debug 本机推理自检，不包含个人用药数据。"
                        ),
                        medicationSnapshots: ((21...35).contains(index) || index >= 40) ? syntheticMedicationSnapshots() : [],
                        localeIdentifier: "zh_CN"
                    )
                    if index >= 45 {
                        request.medicationSnapshots = [
                            MedicalAIMedicationSnapshot(medication: Medication(displayName: "ibuprofen", kind: .overTheCounter, inputSource: .manual), doseEvents: [DoseEvent(scheduledDoseID: UUID(), status: .taken, recordedAt: Date())]),
                            MedicalAIMedicationSnapshot(medication: Medication(displayName: "loratadine", kind: .overTheCounter, inputSource: .manual), doseEvents: [DoseEvent(scheduledDoseID: UUID(), status: .delayed, recordedAt: Date())])]
                        if index == 45 {
                            request.conversation = [MedicalAIConversationTurn(role: "user", text: "记录里的英文药名有哪些？"), MedicalAIConversationTurn(role: "assistant", text: "记录里有 ibuprofen 和 loratadine。")]
                        }
                    }
                    if index >= 52 {
                        request.conversation = [
                            MedicalAIConversationTurn(role: "user", text: "well i feel illness"),
                            MedicalAIConversationTurn(role: "assistant", text: "您好！很高兴为您服务。如果您有关于健康或用药的问题，欢迎随时交流。以上内容仅用于用药风险提示和复诊沟通，不能替代医生或药师判断。"),
                            MedicalAIConversationTurn(role: "user", text: "晚上好"),
                            MedicalAIConversationTurn(role: "assistant", text: "您好！很高兴为您服务。如果您有关于健康或用药的问题，欢迎随时交流。")
                        ]
                    }
                    var output = GeneratedOutput()
                    for try await event in client.streamResponse(to: request) {
                        if case let .generationCompleted(completedAnswer, thinking) = event {
                            output.answer = completedAnswer
                            output.thinking = thinking
                        }
                    }
                    return output
                }
                group.addTask {
                    try await Task.sleep(for: .seconds(60))
                    throw LocalMedicalModelSmokeTimeoutError()
                }
                guard let output = try await group.next() else {
                    throw LocalMedicalModelSmokeTimeoutError()
                }
                group.cancelAll()
                return output
            }
            let answer = output.answer
            let finalized = try MedicalAIResponseFinalizer().finalize(answer: answer, thinking: output.thinking)
            guard !answer.isEmpty, !finalized.boundaryBlockedAction else {
                print("[LocalMedicalModel-Smoke] failure index=\(index) boundary-or-empty")
                return false
            }
            print("[LocalMedicalModel-Raw] index=\(index) final=\(answer.debugDescription) thinking=\(output.thinking.debugDescription)")
            print("[LocalMedicalModel-Smoke] success index=\(index) responseLength=\(finalized.displayMessage.count) thinkingLength=\(output.thinking.count) elapsed=\(startedAt.duration(to: .now))")
            return true
        } catch {
            print("[LocalMedicalModel-Smoke] failure index=\(index) \(diagnosticSummary(for: error))")
            return false
        }
    }

    // In-memory synthetic fixtures only: never read the device's user database.
    private static func syntheticMedicationSnapshots() -> [MedicalAIMedicationSnapshot] {
        ["ibuprofen", "loratadine", "acetaminophen"].enumerated().map { index, name in
            MedicalAIMedicationSnapshot(
                medication: Medication(displayName: name, kind: .overTheCounter, inputSource: .manual),
                doseEvents: index == 0 ? [DoseEvent(scheduledDoseID: UUID(), status: .delayed, recordedAt: Date())] : []
            )
        }
    }

    private static func smokePrompt(for index: Int) -> String {
        if index == 52 { return "晚上好" }
        if index == 53 { return "well i feel illness" }
        if (48...51).contains(index) {
            return ["lets speak English", "我不舒服", "我不好", "看看今天环境变化需要注意什么"][index - 48]
        }
        if (45...47).contains(index) {
            return ["把上一个回答整理成 Markdown 表格", "我今天吃了什么？", "把近14天各药品的服用次数列成 Markdown 表格"][index - 45]
        }
        if (40...44).contains(index) {
            return ["你能干些什么", "你能帮我做什么？", "hi", "睡眠对健康有什么作用？", "我的药品有哪些？"][index - 40]
        }
        if (36...39).contains(index) {
            return ["hi", "你好", "睡眠对健康有什么作用？", "我今日的心率"][index - 36]
        }
        let prompts = [
            "请用一句话回复离线智能体本机推理测试。",
            "请用一句话说明按时记录用药的意义。",
            "请用两句话说明为什么要复诊时带上用药记录。",
            "请用一句话提醒用户核对药盒和说明书。",
            "请用两句话说明漏服记录为什么需要及时补充。",
            "今天需要注意什么？",
            "看看最近忽略或稍后的趋势。",
            "复诊时要带哪些用药记录？",
            "帮我整理说明书里需要向药师复核的内容。",
            "今天没有用药记录，可以怎么开始记录？",
            "请只基于 App 内授权共享的服药记录，说明近期忽略或稍后趋势，并给出提醒建议。",
            "请只基于 App 内授权共享的今日天气或环境提示，以及今天服药记录，用两三句说明环境变化下记录用药时应留意什么。若没有天气或环境事实，请直接说明本地记录不足。",
            "请只基于 App 内授权共享的药品信息、药盒编号、库存和提醒计划，说明药盒与库存管理上需要注意的事项。",
            "请只基于 App 内授权共享的服药记录、剂量变化、风险提醒和药品信息，整理复诊时可以说明的重点。",
            "请只基于 App 内授权共享的今日提醒药品、今日记录状态和风险提醒，用两三句说明今天应该先核对什么。不要诊断，不要建议停药、暂停使用、换药或调整剂量。",
            "请只基于 App 内授权共享的说明书摘要卡片，用两三句整理今天需要复核的说明书栏目。不要推断最终风险结论，不要建议停药、暂停使用、换药或调整剂量。",
            "请只基于 App 内授权共享的风险提醒、药品信息和说明书摘要，整理目前最需要复核的用药风险。",
            "请只基于 App 内授权共享的药品、服药记录和风险提醒，生成一段适合复诊沟通的简短服药记录摘要。",
            "请只基于 App 内授权共享的剂量变化和服药记录，回顾近期剂量调整前后的记录变化。",
            "我准备上传药盒、药品或说明书图片。请只回答如何在本 App 内识别、录入、核对或整理这些信息。"
        ]
        if index > 30 {
            let englishQuestions = [
                "请用中文说明如何在记录里保留英文药名 ibuprofen，不提供用法用量。",
                "帮我整理 ibuprofen、loratadine 和 acetaminophen 的药盒核对清单，不要给服药建议。",
                "请复述本次资料中的药品名称，保留英文拼写。",
                "过去14天哪些药品有稍后记录？",
                "没有共享天气资料时，应该怎么记录今天的情况？"
            ]
            return englishQuestions[(index - 31) % englishQuestions.count]
        }
        if index > 20 { return prompts[10 + (index - 21) % 10] }
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
