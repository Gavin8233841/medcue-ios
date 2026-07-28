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
    @State private var selectedTab: AppTab = .today
    @State private var loadedTabs: Set<AppTab> = [.today]
    @State private var pendingAIQuestion = ""
    @State private var didSeedStartupData = false
    @State private var didScheduleStartupReminderReconcile = false
    @State private var isWarmingTabQueries = false
    @State private var isCompletingFirstLaunch = false
    @State private var didDismissForcedFirstLaunch = false
    @State private var isShowingDemoModeError = false
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

    var body: some View {
        ZStack {
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
                    .tag(tab)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
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

            if shouldShowFirstLaunchSetup && !isCompletingFirstLaunch {
                FirstLaunchSetupView(
                    finish: { shouldOpenAccountSettings in
                        Task {
                            await completeFirstLaunch(shouldOpenAccountSettings: shouldOpenAccountSettings)
                        }
                    },
                    startDemoMode: {
                        Task {
                            await startDebugDemoMode()
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

            if isWarmingTabQueries && !shouldShowFirstLaunchSetup {
                StartupQueryWarmupView()
                    .frame(width: 1, height: 1)
                    .opacity(0.001)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }

            if !shouldShowFirstLaunchSetup {
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
            await reconcileStartupReminders(after: .milliseconds(700))
        }
        .task(id: shouldShowFirstLaunchSetup) {
            guard !shouldShowFirstLaunchSetup else {
                return
            }
            await prewarmTabQueriesWhenIdle()
        }
        .onOpenURL { url in
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
    private func startDebugDemoMode() async {
        #if DEBUG
        guard !isCompletingFirstLaunch else {
            return
        }
        isCompletingFirstLaunch = true
        hasCompletedFirstLaunchSetup = false
        do {
            try await DebugDemoModeLauncher.rebuildAndExit(in: modelContext)
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
            DemoDataSeeder.seedIfNeeded(in: modelContext)
        }
        #endif

        guard !shouldShowFirstLaunchSetup else {
            return
        }
        _ = persistenceIntegrityStartupCheck.run(modelContext: modelContext)
        await reconcileStartupReminders(after: .milliseconds(1_400))
    }

    @MainActor
    private func consumeCompletedLiveActivityActions() async {
        await MedicationReminderLiveActivityActionService(notificationService: notificationService)
            .consumeCompletedLiveActivities(in: modelContext)
    }

    @MainActor
    private func reconcileStartupReminders(after delay: Duration) async {
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

    @MainActor
    private func prewarmTabQueriesWhenIdle() async {
        try? await Task.sleep(for: .milliseconds(90))
        guard !Task.isCancelled else {
            return
        }
        isWarmingTabQueries = true
        try? await Task.sleep(for: .milliseconds(1_800))
        guard !Task.isCancelled else {
            isWarmingTabQueries = false
            return
        }
        isWarmingTabQueries = false
    }

}
