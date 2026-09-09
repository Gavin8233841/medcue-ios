import SwiftData
import SwiftUI
#if (DEBUG || MEDCUE_DEMO) && targetEnvironment(simulator)
import MedicationAdherenceCore
import UIKit
#endif

struct AppRootView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorScheme) private var systemColorScheme
    @AppStorage("appColorSchemePreference") private var appColorSchemePreference = AppColorSchemePreference.system.rawValue
    @AppStorage(AppExperienceMode.storageKey) private var appExperienceModeRaw = AppExperienceMode.complete.rawValue
    @AppStorage("hasCompletedFirstLaunchSetup") private var hasCompletedFirstLaunchSetup = false
    @AppStorage(AppPersistenceCommitter.failureMessageDefaultsKey) private var persistenceFailureMessage = ""
    @StateObject private var notificationService = NotificationService()
    @State private var selectedTab: AppTab = .today
    @State private var loadedTabs: Set<AppTab> = [.today]
    @State private var pendingAIQuestion = ""
    @State private var didSeedStartupData = false
    @State private var didRepairLegacyAutoSkips = false
    @State private var didScheduleStartupReminderReconcile = false
    @State private var isCompletingFirstLaunch = false
    @State private var didDismissForcedFirstLaunch = false
    @State private var isShowingDemoModeError = false
    @State private var isShowingElderSettings = false
    @State private var topGradientState = AppTabTopGradientState()
    @State private var persistenceIntegrityStartupCheck = PersistenceIntegrityStartupCheck()

    private var shouldShowFirstLaunchSetup: Bool {
        (!hasCompletedFirstLaunchSetup || ProcessInfo.processInfo.arguments.contains("-showFirstLaunch")) && !didDismissForcedFirstLaunch
    }

    private var isFirstLaunchOverlayActive: Bool {
        shouldShowFirstLaunchSetup || isCompletingFirstLaunch
    }

    private var preferredAppColorScheme: ColorScheme? {
        AppColorSchemePreference(rawValue: appColorSchemePreference)?.colorScheme
    }

    private var resolvedAppColorScheme: ColorScheme {
        preferredAppColorScheme ?? systemColorScheme
    }

    private var appExperienceMode: AppExperienceMode {
        AppExperienceMode(rawValue: appExperienceModeRaw) ?? .complete
    }

    @ViewBuilder
    var body: some View {
        #if (DEBUG || MEDCUE_DEMO) && targetEnvironment(simulator)
        if let fixture = ElderUITestFixture.active, fixture.inspectsStore {
            ElderUITestStoreInspectionView(fixture: fixture)
        } else {
            applicationContent
        }
        #else
        applicationContent
        #endif
    }

    private var isRunningElderUIFixture: Bool {
        #if (DEBUG || MEDCUE_DEMO) && targetEnvironment(simulator)
        ElderUITestFixture.active != nil
        #else
        false
        #endif
    }

    private var applicationContent: some View {
        ZStack {
            experienceContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .allowsHitTesting(!isFirstLaunchOverlayActive)
                .accessibilityHidden(isFirstLaunchOverlayActive)

            if !isFirstLaunchOverlayActive && appExperienceMode == .complete {
                AppTabTopGradientOverlay(
                    state: topGradientState
                )
                .allowsHitTesting(false)
                .accessibilityHidden(true)
                .transition(.opacity)
                .zIndex(1)
            }

            if shouldShowFirstLaunchSetup && !isCompletingFirstLaunch {
                FirstLaunchSetupView(
                    finish: { shouldOpenAccountSettings in
                        Task {
                            await completeFirstLaunch(shouldOpenAccountSettings: shouldOpenAccountSettings)
                        }
                    },
                    startDemoMode: {
                        Task {
                            await startDemoMode()
                        }
                    }
                )
                .transition(.opacity.combined(with: .scale(scale: 1.02)))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .zIndex(10)
            }

            if isCompletingFirstLaunch {
                FirstLaunchCompletionBridgeView()
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .zIndex(12)
            }

            if !shouldShowFirstLaunchSetup && !isRunningElderUIFixture {
                MedicationWatchSnapshotSyncHost()
                    .frame(width: 1, height: 1)
                    .opacity(0.001)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task {
            await runStartupMaintenance()
        }
        .task(id: shouldShowFirstLaunchSetup) {
            guard !shouldShowFirstLaunchSetup else {
                return
            }
            await consumeCompletedLiveActivityActions()
        }
        .task(id: shouldShowFirstLaunchSetup) {
            guard !shouldShowFirstLaunchSetup else {
                return
            }
            guard repairLegacyAutoSkipsIfNeeded() else {
                return
            }
            await reconcileStartupReminders(after: .milliseconds(700))
        }
        .onOpenURL { url in
            guard !isRunningElderUIFixture else {
                return
            }
            guard let request = MedicationReminderLiveActivityActionURL.request(from: url) else {
                return
            }
            guard repairLegacyAutoSkipsIfNeeded() else {
                return
            }
            activateTab(.today)
            Task {
                await MedicationReminderLiveActivityActionService(notificationService: notificationService)
                    .handle(request, in: modelContext)
                await consumeCompletedLiveActivityActions()
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active, !shouldShowFirstLaunchSetup else {
                return
            }
            Task {
                await consumeCompletedLiveActivityActions()
            }
        }
        .preferredColorScheme(preferredAppColorScheme)
        .environment(\.colorScheme, resolvedAppColorScheme)
        .sheet(isPresented: $isShowingElderSettings) {
            NavigationStack {
                elderSettingsContent
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("完成") {
                                isShowingElderSettings = false
                            }
                        }
                    }
            }
        }
        .alert(
            "更改未能保存",
            isPresented: Binding(
                get: { !persistenceFailureMessage.isEmpty },
                set: { isPresented in
                    if !isPresented {
                        persistenceFailureMessage = ""
                    }
                }
            )
        ) {
            Button("好", role: .cancel) {
                persistenceFailureMessage = ""
            }
        } message: {
            Text(persistenceFailureMessage)
        }
        .alert("演示模式未能启动", isPresented: $isShowingDemoModeError) {
            Button("知道了", role: .cancel) {}
        } message: {
            Text("演示数据未能保存，请重新打开 App 后再试。")
        }
    }

    @ViewBuilder
    private var experienceContent: some View {
        if appExperienceMode == .elder {
            NavigationStack {
                todayContent(presentation: .elder)
            }
            .accessibilityIdentifier(AppAccessibilityID.elderHome)
        } else {
            TabView(selection: selectedTabBinding) {
                ForEach(AppTab.allCases) { tab in
                    NavigationStack {
                        if tab == .today {
                            todayContent(presentation: .complete)
                        } else {
                            AppTabContentView(
                                tab: tab,
                                isLoaded: loadedTabs.contains(tab)
                            )
                            .equatable()
                        }
                    }
                    .tabItem { tab.label }
                    .accessibilityIdentifier(tab.accessibilityIdentifier)
                    .tag(tab)
                }
            }
            .environment(\.openMedicationAIQuestion) { question in
                pendingAIQuestion = question
                activateTab(.assistant)
            }
            .environment(\.openMedicationToday) {
                activateTab(.today)
            }
            .environment(\.pendingMedicationAIQuestion, pendingAIQuestion)
            .environment(\.clearPendingMedicationAIQuestion) {
                pendingAIQuestion = ""
            }
            .environment(\.activeAppTab, selectedTab)
            .environment(\.setAppTabTopGradientProgress) { tab, progress in
                topGradientState.updateProgress(for: tab, progress: progress, activeTab: selectedTab)
            }
        }
    }

    @ViewBuilder
    private func todayContent(presentation: TodayPresentation) -> some View {
        #if (DEBUG || MEDCUE_DEMO) && targetEnvironment(simulator)
        if let fixture = ElderUITestFixture.active {
            TodayView(
                presentation: presentation,
                openElderSettings: { isShowingElderSettings = true },
                switchToCompleteMode: switchToCompleteMode,
                elderHelpContactStore: fixture.helpContactStore,
                elderHelpOpener: fixture.helpOpener,
                now: { fixture.now },
                dosePersistence: fixture.dosePersistence,
                systemSurfaceAdapter: fixture.systemSurfaceAdapter
            )
            .transformEnvironment(\.legibilityWeight) { weight in
                if fixture.usesBoldText { weight = .bold }
            }
        } else {
            standardTodayContent(presentation: presentation)
        }
        #else
        standardTodayContent(presentation: presentation)
        #endif
    }

    private func standardTodayContent(presentation: TodayPresentation) -> some View {
        TodayView(
            presentation: presentation,
            openElderSettings: { isShowingElderSettings = true },
            switchToCompleteMode: switchToCompleteMode
        )
    }

    private func switchToCompleteMode() {
        activateTab(.today)
        appExperienceModeRaw = AppExperienceMode.complete.rawValue
    }

    @ViewBuilder
    private var elderSettingsContent: some View {
        #if (DEBUG || MEDCUE_DEMO) && targetEnvironment(simulator)
        if let fixture = ElderUITestFixture.active {
            SettingsView(focusesElderHelpContact: true, elderHelpContactStore: fixture.helpContactStore)
        } else {
            SettingsView(focusesElderHelpContact: true)
        }
        #else
        SettingsView(focusesElderHelpContact: true)
        #endif
    }

    private var selectedTabBinding: Binding<AppTab> {
        Binding(
            get: { selectedTab },
            set: { activateTab($0) }
        )
    }

    private func activateTab(_ tab: AppTab) {
        loadedTabs.insert(tab)
        selectedTab = tab
        topGradientState.select(tab)
    }

    @MainActor
    private func completeFirstLaunch(shouldOpenAccountSettings: Bool) async {
        guard !isCompletingFirstLaunch else {
            return
        }
        activateTab(shouldOpenAccountSettings ? .profile : .today)
        withAnimation(.smooth(duration: 0.30)) {
            isCompletingFirstLaunch = true
        }
        try? await Task.sleep(for: .milliseconds(260))
        guard !Task.isCancelled else {
            return
        }
        withAnimation(.smooth(duration: 0.24)) {
            hasCompletedFirstLaunchSetup = true
            didDismissForcedFirstLaunch = true
        }
        try? await Task.sleep(for: .milliseconds(840))
        guard !Task.isCancelled else {
            return
        }
        withAnimation(.smooth(duration: 0.55)) {
            isCompletingFirstLaunch = false
        }
    }

    @MainActor
    private func startDemoMode() async {
        #if DEBUG || MEDCUE_DEMO
        guard !isCompletingFirstLaunch else {
            return
        }
        isCompletingFirstLaunch = true
        hasCompletedFirstLaunchSetup = false
        do {
            try await DemoModeLauncher.rebuildAndExit(in: modelContext)
        } catch {
            isCompletingFirstLaunch = false
            isShowingDemoModeError = true
        }
        #endif
    }

    @MainActor
    private func runStartupMaintenance() async {
        #if DEBUG || MEDCUE_DEMO
        if !didSeedStartupData {
            didSeedStartupData = true
            DemoDataSeeder.seedIfNeeded(in: modelContext)
        }
        #endif

        guard !shouldShowFirstLaunchSetup else {
            return
        }
        _ = persistenceIntegrityStartupCheck.run(modelContext: modelContext)
        guard repairLegacyAutoSkipsIfNeeded() else {
            return
        }
        await reconcileStartupReminders(after: .milliseconds(1_400))
    }

    @MainActor
    private func repairLegacyAutoSkipsIfNeeded() -> Bool {
        guard !didRepairLegacyAutoSkips else {
            return true
        }
        do {
            _ = try LegacyAutoSkipRepairCommand().perform(in: modelContext)
            didRepairLegacyAutoSkips = true
            return true
        } catch {
            AppPersistenceCommitter.reportFailure(operation: "legacy-auto-skip-repair")
            return false
        }
    }

    @MainActor
    private func consumeCompletedLiveActivityActions() async {
        guard !isRunningElderUIFixture else { return }
        guard repairLegacyAutoSkipsIfNeeded() else {
            return
        }
        await MedicationReminderLiveActivityActionService(notificationService: notificationService)
            .consumeCompletedLiveActivities(in: modelContext)
    }

    @MainActor
    private func reconcileStartupReminders(after delay: Duration) async {
        guard !isRunningElderUIFixture else { return }
        guard !didScheduleStartupReminderReconcile else {
            return
        }
        didScheduleStartupReminderReconcile = true
        try? await Task.sleep(for: delay)
        guard !Task.isCancelled else {
            return
        }
        await notificationService.reconcileAndScheduleReminders(in: modelContext)
    }

}

#if (DEBUG || MEDCUE_DEMO) && targetEnvironment(simulator)
// These fixtures never compile into device or Release builds. Each UI test owns a
// separate on-disk store, including when it restarts the app to verify durability.
@MainActor
final class ElderUITestFixture {
    static var active: ElderUITestFixture?

    enum Scenario: String {
        case due
        case future
        case multiple
        case empty
        case idleFollowup = "idle-followup"
        case midnight
        case helpMissing = "help-missing"
        case helpUnavailable = "help-unavailable"
        case helpConfirmation = "help-confirmation"
    }

    enum Failure: Error {
        case invalidArguments
        case missingImage
        case injectedSaveFailure
    }

    let modelContainer: ModelContainer
    private let clockOrigin: Date
    private var clockStartsAtUptime: TimeInterval?
    var now: Date {
        guard let clockStartsAtUptime else { return clockOrigin }
        return clockOrigin.addingTimeInterval(max(0, ProcessInfo.processInfo.systemUptime - clockStartsAtUptime))
    }
    let inspectsStore: Bool
    let usesBoldText: Bool
    let helpContactStore: any ElderHelpContactStoring
    let helpOpener: any ElderHelpOpening
    private let defaults: UserDefaults
    var preferences: UserDefaults { defaults }
    private let failsFirstSave: Bool
    private let reminderUnavailable: Bool
    private var didInjectSaveFailure = false

    var dosePersistence: DoseActionPersistence {
        DoseActionPersistence { [self] context in
            defaults.set(defaults.integer(forKey: "saveAttempts") + 1, forKey: "saveAttempts")
            if failsFirstSave && !didInjectSaveFailure {
                didInjectSaveFailure = true
                throw Failure.injectedSaveFailure
            }
            try context.save()
        }
    }

    var helpAttemptCount: Int { defaults.integer(forKey: "helpAttempts") }
    var saveAttemptCount: Int { defaults.integer(forKey: "saveAttempts") }
    var scheduleAttemptCount: Int { defaults.integer(forKey: "scheduleAttempts") }

    var systemSurfaceAdapter: TodaySystemSurfaceAdapter {
        TodaySystemSurfaceAdapter(
            cancelReminder: { _ in },
            scheduleReminder: { [self] _, _, _ in
                defaults.set(scheduleAttemptCount + 1, forKey: "scheduleAttempts")
                if reminderUnavailable {
                    return .unavailable(message: "无法添加系统提醒，请检查通知设置。")
                }
                return .scheduled
            },
            endLiveActivity: { _ in },
            startLiveActivity: { _, _ in }
        )
    }

    static func loadIfRequested() throws -> ElderUITestFixture? {
        let arguments = ProcessInfo.processInfo.arguments
        guard arguments.contains("--elder-ui-fixture") else { return nil }
        guard let scenarioValue = argument(after: "--elder-ui-fixture", in: arguments),
              let scenario = Scenario(rawValue: scenarioValue),
              let sessionValue = argument(after: "--elder-ui-session", in: arguments),
              let session = UUID(uuidString: sessionValue),
              let modeValue = argument(after: "--elder-ui-mode", in: arguments),
              let initialExperienceMode = AppExperienceMode(rawValue: modeValue)
        else {
            throw Failure.invalidArguments
        }
        return try ElderUITestFixture(
            scenario: scenario,
            session: session,
            initialExperienceMode: initialExperienceMode,
            failsFirstSave: arguments.contains("--elder-ui-fail-first-save"),
            reminderUnavailable: arguments.contains("--elder-ui-reminder-unavailable"),
            inspectsStore: arguments.contains("--elder-ui-inspect-store"),
            usesBoldText: arguments.contains("--elder-ui-bold-text")
        )
    }

    private static func argument(after flag: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1) else {
            return nil
        }
        return arguments[index + 1]
    }

    private init(
        scenario: Scenario,
        session: UUID,
        initialExperienceMode: AppExperienceMode,
        failsFirstSave: Bool,
        reminderUnavailable: Bool,
        inspectsStore: Bool,
        usesBoldText: Bool
    ) throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let components = scenario == .midnight
            ? DateComponents(year: 2026, month: 9, day: 5, hour: 23, minute: 59, second: 58)
            : DateComponents(year: 2026, month: 9, day: 5, hour: 12)
        guard let date = calendar.date(from: components),
              let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first,
              let fixtureDefaults = UserDefaults(suiteName: "medcue.elder-ui.\(session.uuidString)")
        else {
            throw Failure.invalidArguments
        }
        if let savedScenario = fixtureDefaults.string(forKey: "scenario"), savedScenario != scenario.rawValue {
            throw Failure.invalidArguments
        }
        let directory = support
            .appendingPathComponent("ElderUITestStores", isDirectory: true)
            .appendingPathComponent(session.uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        modelContainer = try MedicationAdherenceModelContainer.make(
            storeURL: directory.appendingPathComponent("fixture.store")
        )
        defaults = fixtureDefaults
        // Seed a writable, test-owned preference domain. A launch-argument
        // override would mask subsequent mode changes and defeat this UI test.
        if fixtureDefaults.object(forKey: AppExperienceMode.storageKey) == nil {
            fixtureDefaults.set(initialExperienceMode.rawValue, forKey: AppExperienceMode.storageKey)
        }
        clockOrigin = date
        self.failsFirstSave = failsFirstSave
        self.reminderUnavailable = reminderUnavailable
        self.inspectsStore = inspectsStore
        self.usesBoldText = usesBoldText
        helpContactStore = try ElderUITestHelpContactStore(scenario: scenario)
        helpOpener = ElderUITestHelpOpener(defaults: fixtureDefaults)

        let context = modelContainer.mainContext
        // Even the no-task fixture contains a medication, so an empty task list
        // after completion cannot be mistaken for a request to reseed on restart.
        if try context.fetchCount(FetchDescriptor<StoredMedication>()) == 0 {
            try seed(scenario: scenario, in: context)
            fixtureDefaults.set(scenario.rawValue, forKey: "scenario")
        }
        if scenario == .idleFollowup || scenario == .midnight {
            // Allow the test to observe the initial frame, then advance at 1x
            // using monotonic uptime. No medication action is driven by this clock.
            clockStartsAtUptime = ProcessInfo.processInfo.systemUptime + 8
        }
    }

    private func seed(scenario: Scenario, in context: ModelContext) throws {
        let offset: TimeInterval = switch scenario {
        case .future: 6 * 3_600
        case .idleFollowup: 2
        case .midnight: 62
        default: -300
        }
        let definitions: [(name: String, form: String, unit: String, offset: TimeInterval)] =
            scenario == .multiple
                ? [("布洛芬", "片剂", "片", -300), ("人工泪液", "滴眼液", "滴", -120)]
                : [("布洛芬", "片剂", "片", offset)]
        for definition in definitions {
            guard let photo = Self.syntheticPackageImage(
                medicationName: definition.name,
                form: definition.form
            ).jpegData(compressionQuality: 0.88) else {
                throw Failure.missingImage
            }
            let medication = StoredMedication(
                displayName: definition.name,
                kind: .overTheCounter,
                form: definition.form,
                inputSource: .demoData,
                photoData: photo,
                isDemoContent: true,
                createdAt: now
            )
            context.insert(medication)
            guard scenario != .empty else { continue }
            let dueAt = now.addingTimeInterval(definition.offset)
            let plan = StoredMedicationPlan(
                medicationID: medication.id,
                doseValue: 1,
                doseUnit: definition.unit,
                timingSummary: AppFormatters.time.string(from: dueAt),
                timeZonePolicy: .localClock,
                sourceNote: "",
                courseStartAt: Calendar.current.startOfDay(for: dueAt),
                courseEndAt: Calendar.current.startOfDay(for: dueAt),
                reminderTimesRaw: AppFormatters.time.string(from: dueAt),
                escalatesToAlarmWhenUnhandled: false,
                createdAt: now
            )
            context.insert(plan)
            context.insert(StoredDoseTask(
                medicationID: medication.id,
                planID: plan.id,
                dueAt: dueAt,
                doseValue: 1,
                doseUnit: definition.unit
            ))
        }
        try context.save()
    }

    private static func syntheticPackageImage(medicationName: String, form: String) -> UIImage {
        let size = CGSize(width: 760, height: 1_000)
        return UIGraphicsImageRenderer(size: size).image { context in
            let bounds = CGRect(origin: .zero, size: size)
            UIColor.systemGroupedBackground.setFill()
            context.fill(bounds)

            let package = bounds.insetBy(dx: 76, dy: 66)
            let packagePath = UIBezierPath(roundedRect: package, cornerRadius: 54)
            UIColor.white.setFill()
            packagePath.fill()
            UIColor.systemBlue.withAlphaComponent(0.24).setStroke()
            packagePath.lineWidth = 8
            packagePath.stroke()

            UIColor.systemBlue.setFill()
            UIBezierPath(
                roundedRect: CGRect(x: package.minX, y: package.minY, width: package.width, height: 174),
                byRoundingCorners: [.topLeft, .topRight],
                cornerRadii: CGSize(width: 54, height: 54)
            ).fill()

            let centered = NSMutableParagraphStyle()
            centered.alignment = .center
            let headerAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 62, weight: .bold),
                .foregroundColor: UIColor.white,
                .paragraphStyle: centered
            ]
            ("合成演示药品" as NSString).draw(
                in: CGRect(x: package.minX + 20, y: package.minY + 50, width: package.width - 40, height: 82),
                withAttributes: headerAttributes
            )

            let symbolConfig = UIImage.SymbolConfiguration(pointSize: 170, weight: .regular)
            let symbol = UIImage(systemName: form == "滴眼液" ? "drop.fill" : "pills.fill", withConfiguration: symbolConfig)?
                .withTintColor(.systemBlue, renderingMode: .alwaysOriginal)
            symbol?.draw(in: CGRect(x: 250, y: 305, width: 260, height: 210))

            let nameAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 76, weight: .bold),
                .foregroundColor: UIColor.label,
                .paragraphStyle: centered
            ]
            (medicationName as NSString).draw(
                in: CGRect(x: package.minX + 30, y: 570, width: package.width - 60, height: 104),
                withAttributes: nameAttributes
            )

            let detailAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 42, weight: .semibold),
                .foregroundColor: UIColor.secondaryLabel,
                .paragraphStyle: centered
            ]
            ("\(form) · 仅用于测试" as NSString).draw(
                in: CGRect(x: package.minX + 30, y: 700, width: package.width - 60, height: 70),
                withAttributes: detailAttributes
            )
            ("无真实患者资料" as NSString).draw(
                in: CGRect(x: package.minX + 30, y: 790, width: package.width - 60, height: 70),
                withAttributes: detailAttributes
            )
        }
    }
}

private final class ElderUITestHelpContactStore: ElderHelpContactStoring {
    private var phone: ElderHelpPhoneNumber?
    private let isUnavailable: Bool

    init(scenario: ElderUITestFixture.Scenario) throws {
        isUnavailable = scenario == .helpUnavailable
        // Reserved fictional NANP number; the fixture opener never calls the system.
        phone = scenario == .helpConfirmation ? try ElderHelpPhoneNumber(validating: "+12025550123") : nil
    }

    func load() throws -> ElderHelpPhoneNumber? {
        if isUnavailable { throw ElderHelpContactError.localStorageUnavailable }
        return phone
    }

    func save(_ phoneNumber: ElderHelpPhoneNumber) throws { phone = phoneNumber }
    func remove() throws { phone = nil }
}

@MainActor
private struct ElderUITestHelpOpener: ElderHelpOpening {
    let defaults: UserDefaults

    func openConfirmation(for phoneNumber: ElderHelpPhoneNumber, completion: @escaping @MainActor (Bool) -> Void) {
        defaults.set(defaults.integer(forKey: "helpAttempts") + 1, forKey: "helpAttempts")
        completion(false)
    }
}

private struct ElderUITestStoreInspectionView: View {
    let fixture: ElderUITestFixture

    var body: some View {
        let context = fixture.modelContainer.mainContext
        let tasks = try? context.fetch(FetchDescriptor<StoredDoseTask>(sortBy: [SortDescriptor(\.dueAt)]))
        let logs = try? context.fetch(FetchDescriptor<StoredDoseActionLog>())
        VStack {
            if let tasks, let logs {
                Text(String(tasks.count)).accessibilityIdentifier("elder.test.store.task-count")
                Text(String(logs.count)).accessibilityIdentifier("elder.test.store.log-count")
                Text(String(fixture.helpAttemptCount)).accessibilityIdentifier("elder.test.store.help-attempts")
                Text(String(fixture.saveAttemptCount)).accessibilityIdentifier("elder.test.store.save-attempts")
                Text(String(fixture.scheduleAttemptCount)).accessibilityIdentifier("elder.test.store.schedule-attempts")
                ForEach(Array(tasks.enumerated()), id: \.element.id) { index, task in
                    Text(task.statusRaw).accessibilityIdentifier("elder.test.store.task.\(index).status")
                    Text(String(Int(task.dueAt.timeIntervalSince(fixture.now))))
                        .accessibilityIdentifier("elder.test.store.task.\(index).due-offset")
                }
            } else {
                Text("Store inspection failed").accessibilityIdentifier("elder.test.store.error")
            }
        }
    }
}
#endif
