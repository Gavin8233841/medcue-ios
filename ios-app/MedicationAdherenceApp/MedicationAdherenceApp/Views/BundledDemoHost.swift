import MedicationAdherenceCore
import SwiftData
import SwiftUI

// Ordinary pages inherit true. Only the simulator DEBUG/MEDCUE_DEMO host
// overrides this capability; no production service or transaction is replaced.
private struct BundledDemoExternalActionsKey: EnvironmentKey {
    static let defaultValue = true
}
private struct BundledDemoTodayGuardKey: EnvironmentKey {
    static let defaultValue: (@MainActor (AppExperienceModeRequestGuard) -> Void)? = nil
}
extension EnvironmentValues {
    var medcueDemoAllowsExternalActions: Bool {
        get { self[BundledDemoExternalActionsKey.self] }
        set { self[BundledDemoExternalActionsKey.self] = newValue }
    }
    var registerBundledDemoTodayGuard: (@MainActor (AppExperienceModeRequestGuard) -> Void)? {
        get { self[BundledDemoTodayGuardKey.self] }
        set { self[BundledDemoTodayGuardKey.self] = newValue }
    }
}

/// All three Today navigation sites share the same read-only demo destination.
struct TodayMedicationDetailDestination: View {
    @Environment(\.medcueDemoAllowsExternalActions) private var allowsExternalActions
    let medication: StoredMedication
    var body: some View {
        if allowsExternalActions {
            MedicationDetailView(medication: medication)
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Label("合成演示数据", systemImage: "testtube.2")
                        .font(.headline)
                    Text(userFacingMedicationName(for: medication)).font(.title2.bold())
                    Text("\(medication.strength) · \(medication.form)")
                    Text("药盒位置：\(medication.boxNumber)")
                    Text(medication.notes)
                    Text("演示药品资料仅供查看，请勿据此决定真实用药。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading).padding(20)
            }
            .navigationTitle("演示药品资料")
            .accessibilityIdentifier("demo.medication.read-only")
        }
    }
}

#if (DEBUG || MEDCUE_DEMO) && targetEnvironment(simulator)
/// A bounded host for the real Today owner; it never loads ordinary tabs or Root maintenance.
struct BundledDemoHost: View {
    let session: BundledDemoSession?
    @Environment(\.scenePhase) private var scenePhase
    @State private var mode: AppExperienceMode
    @State private var transition = AppExperienceModeTransition()
    @State private var navigationGuard = AppExperienceModeRequestGuard(canCommit: { false })
    @State private var pendingGuard = AppExperienceModeRequestGuard(canCommit: { false })
    @State private var showsSettings = false
    @State private var showsExitConfirmation = false
    @State private var isClosed = false
    @State private var isBlocked = false

    init(session: BundledDemoSession?) {
        self.session = session
        _mode = State(initialValue: AppExperienceMode.resolve(
            session?.preferences.string(forKey: AppExperienceMode.storageKey) ?? "complete"
        ))
    }

    var body: some View {
        Group {
            if let session, !isClosed {
                NavigationStack {
                    TodayView(
                        presentation: mode == .elder ? .elder : .complete,
                        openElderSettings: { requestGuard in openSettings(guard: requestGuard) },
                        switchToCompleteMode: { requestGuard in requestMode(.complete, guard: requestGuard) },
                        elderHelpContactStore: UserDefaultsElderHelpContactStore(defaults: session.preferences),
                        elderHelpOpener: BundledDemoHelpOpener(),
                        now: { session.referenceDate },
                        dosePersistence: DoseActionPersistence { context in
                            // The existing transaction rolls back a failed save; no standard reporter here.
                            guard context === session.modelContainer.mainContext else {
                                throw BundledDemoSession.Failure.incompatibleSession
                            }
                            try context.save()
                        },
                        systemSurfaceAdapter: Self.fakeSystemSurfaces
                    )
                    .safeAreaInset(edge: .top, spacing: 0) {
                        demoHeader(session)
                    }
                    .sheet(isPresented: $showsSettings) {
                        NavigationStack {
                            Form {
                                Section {
                                    Toggle("适老模式", isOn: Binding(
                                        get: { mode == .elder },
                                        set: { requestMode($0 ? .elder : .complete, guard: navigationGuard) }
                                    ))
                                    .accessibilityIdentifier("demo.settings.elder")
                                } footer: {
                                    Text("仅切换合成演示的首页展示。进入和退出均需确认。")
                                }
                                Text("此演示不开放撤销、归档、药品编辑和系统设置。")
                            }
                            .navigationTitle("演示设置")
                            .toolbar {
                                ToolbarItem(placement: .confirmationAction) {
                                    Button("完成") { transition.cancel(); showsSettings = false }
                                        .accessibilityIdentifier("demo.settings.done")
                                }
                            }
                            .alert(transition.pending?.title ?? "切换演示模式？", isPresented: modeConfirmationPresented,
                                   presenting: transition.pending) { request in
                                Button(request.confirmationTitle) { confirmMode(request.id) }
                                    .accessibilityIdentifier("demo.mode.confirm")
                                Button("取消", role: .cancel) { transition.cancel(request.id) }
                                    .accessibilityIdentifier("demo.mode.cancel")
                            } message: { _ in Text("仅更改这份合成演示的展示，原有用药记录和使用偏好不变。") }
                        }
                        .onDisappear { transition.cancel() }
                    }
                    .alert("请先完成当前操作", isPresented: $isBlocked) {
                        Button("好", role: .cancel) {}
                    } message: { Text("请完成或取消当前确认，并等待保存和提醒演示结束，再切换或退出。") }
                    .alert("退出合成演示？", isPresented: $showsExitConfirmation) {
                        Button("退出演示") {
                            guard navigationGuard.canCommit() else { isBlocked = true; return }
                            transition.cancel()
                            navigationGuard = .init(canCommit: { false })
                            pendingGuard = .init(canCommit: { false })
                            isClosed = true
                        }
                        .accessibilityIdentifier("demo.exit.confirm")
                        Button("取消", role: .cancel) {}
                    } message: { Text("演示记录会保留。退出后不会打开原记录；以普通方式重新启动 App 可返回原有记录。") }
                }
                .defaultAppStorage(session.preferences)
                .environment(\.medcueDemoAllowsExternalActions, false)
                .environment(\.registerBundledDemoTodayGuard, { navigationGuard = $0 })
            } else {
                demoLanding
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { transition.cancel(); showsExitConfirmation = false }
        }
    }

    private var modeConfirmationPresented: Binding<Bool> {
        Binding(get: { transition.pending != nil }, set: { _ in })
    }

    private func demoHeader(_ session: BundledDemoSession) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("合成演示数据", systemImage: "testtube.2").font(.headline)
                .accessibilityIdentifier("demo.synthetic-marker")
            Text("演示日期：\(session.referenceDate.formatted(date: .numeric, time: .shortened))")
                .font(.caption).foregroundStyle(.secondary)
            Text("可演示完成、稍后和忽略；撤销与归档停用，系统提醒和电话仅模拟。")
                .font(.caption).fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("演示设置") { openSettings(guard: navigationGuard) }
                    .disabled(!navigationGuard.canCommit())
                    .accessibilityIdentifier("demo.settings.open")
                Spacer()
                Button("退出演示") {
                    guard navigationGuard.canCommit() else { isBlocked = true; return }
                    showsExitConfirmation = true
                }
                .disabled(!navigationGuard.canCommit())
                .accessibilityIdentifier("demo.exit.open")
            }
            if ProcessInfo.processInfo.arguments.contains("--bundled-demo-inspect-store") {
                BundledDemoInspectionView(session: session)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 8).background(.bar)
    }

    private var demoLanding: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Label("合成演示入口", systemImage: "testtube.2").font(.title2.bold())
                Text(session == nil ? "演示未能打开。原有用药记录未读取，未删除或重建。" : "已退出演示，演示记录已保留。")
                    .accessibilityIdentifier(session == nil ? "demo.startup.error" : "demo.closed")
                Text("以普通方式重新启动 App，可返回原有用药记录。失败的演示会话不会自动重新导入；需要新的演示会话再试。")
                if session != nil {
                    Button("重新打开此演示") { navigationGuard = .init(canCommit: { false }); isClosed = false }
                        .buttonStyle(.borderedProminent).accessibilityIdentifier("demo.reopen")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading).padding(24)
        }
    }

    private func openSettings(guard requestGuard: AppExperienceModeRequestGuard) {
        guard requestGuard.canCommit(), navigationGuard.canCommit() else { isBlocked = true; return }
        showsSettings = true
    }

    private func requestMode(_ target: AppExperienceMode, guard requestGuard: AppExperienceModeRequestGuard) {
        guard requestGuard.canCommit(), navigationGuard.canCommit() else { isBlocked = true; return }
        pendingGuard = requestGuard
        if transition.request(target, current: mode, source: .settings) != nil { showsSettings = true }
    }

    private func confirmMode(_ id: UUID) {
        let allowed = navigationGuard.canCommit() && pendingGuard.canCommit()
        guard let request = transition.confirm(id, current: mode, canCommit: allowed) else {
            if !allowed { isBlocked = true }
            return
        }
        session?.preferences.set(request.target.rawValue, forKey: AppExperienceMode.storageKey)
        mode = request.target
        showsSettings = false
    }

    private static var fakeSystemSurfaces: TodaySystemSurfaceAdapter {
        TodaySystemSurfaceAdapter(
            applyReminderSnapshot: { snapshot in
                Task { @MainActor in
                    var results: [UUID: MedicationReminderSchedulingResult] = [:]
                    for entry in snapshot.entries { results[entry.taskID] = .scheduled }
                    return results
                }
            },
            endLiveActivity: { _ in }, startLiveActivity: { _, _ in }
        )
    }
}

private struct BundledDemoHelpOpener: ElderHelpOpening {
    func openConfirmation(for phoneNumber: ElderHelpPhoneNumber, completion: @escaping @MainActor (Bool) -> Void) {
        completion(false)
    }
}

private struct BundledDemoInspectionView: View {
    let session: BundledDemoSession
    @Query private var medications: [StoredMedication]
    @Query private var tasks: [StoredDoseTask]
    @Query private var logs: [StoredDoseActionLog]
    var body: some View {
        let today = tasks.filter { session.calendar.isDate($0.dueAt, inSameDayAs: session.referenceDate) }
        Text("演示调试记录")
            .font(.caption2)
            .accessibilityIdentifier("demo.store.inspection")
            .accessibilityLabel("演示调试记录")
            .accessibilityValue("medications=\(medications.count);tasks=\(tasks.count);today=\(today.count);"
                + "pending=\(today.filter { $0.status == .pending }.count);taken=\(today.filter { $0.status == .taken }.count);"
                + "delayed=\(today.filter { $0.status == .delayed }.count);skipped=\(today.filter { $0.status == .skipped }.count);"
                + "logs=\(logs.count);external=disabled")
    }
}
#endif
