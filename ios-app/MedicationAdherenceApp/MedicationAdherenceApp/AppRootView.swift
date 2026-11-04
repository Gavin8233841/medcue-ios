import SwiftData
import SwiftUI

struct AppRootView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorScheme) private var systemColorScheme
    @AppStorage("appColorSchemePreference") private var appColorSchemePreference = AppColorSchemePreference.system.rawValue
    @AppStorage("hasCompletedFirstLaunchSetup") private var hasCompletedFirstLaunchSetup = false
    @AppStorage(AppPersistenceCommitter.failureMessageDefaultsKey) private var persistenceFailureMessage = ""
    @StateObject private var notificationService = NotificationService()
    @AppStorage(AppExperienceMode.storageKey) private var experienceMode = AppExperienceMode.complete.rawValue
    @State private var demoExperienceGeneration = 0
    @State private var selectedTab: AppTab = Self.initialTab
    @State private var loadedTabs: Set<AppTab> = [Self.initialTab]
    @State private var pendingAIQuestion = ""
    @State private var didSeedStartupData = false
    @State private var didScheduleStartupReminderReconcile = false
    @State private var isCompletingFirstLaunch = false
    @State private var didDismissForcedFirstLaunch = false
    @State private var isShowingDemoModeError = false
    @State private var topGradientState = AppTabTopGradientState()
    @State private var persistenceIntegrityStartupCheck = PersistenceIntegrityStartupCheck()

    private static var isGalleryPreview: Bool {
        #if DEBUG && targetEnvironment(simulator)
        ProcessInfo.processInfo.arguments.contains("--medication-gallery-preview")
        #else
        false
        #endif
    }

    private static var initialTab: AppTab { isGalleryPreview ? .medications : .today }

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

    var body: some View {
        ZStack {
            Group {
                if experienceMode == AppExperienceMode.elder.rawValue && !Self.isGalleryPreview {
                    NavigationStack { TodayView() }
                } else {
            TabView(selection: selectedTabBinding) {
                ForEach(AppTab.allCases) { tab in
                    NavigationStack {
                        AppTabContentView(
                            tab: tab,
                            isLoaded: loadedTabs.contains(tab)
                        )
                        .equatable()
                    }
                    .tabItem { tab.label }
                    .accessibilityIdentifier(tab.accessibilityIdentifier)
                    .tag(tab)
                }
            }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .id(demoExperienceGeneration)
            .allowsHitTesting(!isFirstLaunchOverlayActive)
            .accessibilityHidden(isFirstLaunchOverlayActive)
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

            if !isFirstLaunchOverlayActive {
                AppTabTopGradientOverlay(
                    state: topGradientState
                )
                .allowsHitTesting(false)
                .accessibilityHidden(true)
                .transition(.opacity)
                .zIndex(1)
            }

            if shouldShowFirstLaunchSetup {
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
                .id(demoExperienceGeneration)
                .disabled(isCompletingFirstLaunch)
                .transition(.opacity)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .zIndex(10)
            }

            if !shouldShowFirstLaunchSetup && !Self.isGalleryPreview {
                MedicationWatchSnapshotSyncHost()
                    .frame(width: 1, height: 1)
                    .opacity(0.001)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .environment(\.prepareNextDemoExperience, startNextDemoExperience)
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
            await reconcileStartupReminders(after: .milliseconds(700))
        }
        .onChange(of: experienceMode) { _, _ in
            activateTab(.today)
        }
        .onOpenURL { url in
            guard !Self.isGalleryPreview else { return }
            guard let request = MedicationReminderLiveActivityActionURL.request(from: url) else {
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
        hasCompletedFirstLaunchSetup = true
        didDismissForcedFirstLaunch = true
        isCompletingFirstLaunch = false
    }

    @MainActor
    private func startNextDemoExperience() async throws {
        #if DEBUG || MEDCUE_DEMO
        do {
            try DemoModeLauncher.prepareNextExperience(in: modelContext)
        } catch {
            modelContext.rollback()
            throw error
        }
        MedicationListSnapshotCache.store(snapshot: .empty, token: "")
        experienceMode = AppExperienceMode.complete.rawValue
        activateTab(.today)
        loadedTabs = [.today]
        pendingAIQuestion = ""
        isCompletingFirstLaunch = false
        didDismissForcedFirstLaunch = false
        hasCompletedFirstLaunchSetup = false
        didScheduleStartupReminderReconcile = false
        demoExperienceGeneration += 1
        #endif
    }

    @MainActor
    private func startDemoMode() async {
        #if DEBUG || MEDCUE_DEMO
        guard !isCompletingFirstLaunch else {
            return
        }
        isCompletingFirstLaunch = true
        do {
            try await startNextDemoExperience()
        } catch {
            isCompletingFirstLaunch = false
            isShowingDemoModeError = true
        }
        #endif
    }

    @MainActor
    private func runStartupMaintenance() async {
        #if DEBUG
        if !didSeedStartupData {
            didSeedStartupData = true
            if Self.isGalleryPreview { experienceMode = AppExperienceMode.complete.rawValue }
            DemoDataSeeder.seedIfNeeded(in: modelContext)
        }
        #endif

        guard !shouldShowFirstLaunchSetup else {
            return
        }
        _ = await persistenceIntegrityStartupCheck.runInBackground(modelContainer: modelContext.container)
        await reconcileStartupReminders(after: .milliseconds(1_400))
    }

    @MainActor
    private func consumeCompletedLiveActivityActions() async {
        guard !Self.isGalleryPreview else { return }
        await MedicationReminderLiveActivityActionService(notificationService: notificationService)
            .consumeCompletedLiveActivities(in: modelContext)
    }

    @MainActor
    private func reconcileStartupReminders(after delay: Duration) async {
        guard !Self.isGalleryPreview else { return }
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
