import Foundation
import MedicationAdherenceCore
import SwiftUI
import UIKit

/// A browsing reference, never a second dose confirmation or a saved model copy.
struct TodayTaskReference: Equatable, Sendable {
    let id: UUID
    let medicationID: UUID
    let doseKey: String
    let isActionable: Bool

    init(id: UUID, medicationID: UUID, doseKey: String, isActionable: Bool = true) {
        self.id = id
        self.medicationID = medicationID
        self.doseKey = doseKey
        self.isActionable = isActionable
    }

    init(_ task: StoredDoseTask, isArchived: Bool = false) {
        self.init(id: task.id, medicationID: task.medicationID, doseKey: DoseLogicalGroup.key(for: task),
                  isActionable: !isArchived && (task.status == .pending || task.status == .delayed))
    }
}

struct TodayTaskSelection: Equatable {
    private(set) var reference: TodayTaskReference?
    private(set) var selectionEvent = 0
    private(set) var confirmationKey: String?
    private(set) var confirmationReference: TodayTaskReference?

    mutating func ensureDefault(_ firstOpen: TodayTaskReference?) {
        guard reference == nil else { return }
        reference = firstOpen
    }

    @discardableResult
    mutating func select(_ target: TodayTaskReference, isLocked: Bool) -> Bool {
        guard !isLocked else { return false }
        reference = target
        selectionEvent += 1
        return true
    }

    /// The existing row action still decides whether to request/commit a dose.
    mutating func rememberActionTarget(_ target: TodayTaskReference) {
        reference = target
    }

    mutating func syncConfirmation(_ key: String?, candidates: [TodayTaskReference]) {
        guard key != confirmationKey else { return }
        confirmationKey = key
        guard let key else { confirmationReference = nil; return }
        if let reference, reference.doseKey == key {
            confirmationReference = reference
        } else {
            let matching = candidates.filter { $0.doseKey == key }
            confirmationReference = matching.count == 1 ? matching.first : nil
        }
    }

    func resolve(
        candidates: [TodayTaskReference], firstOpen: TodayTaskReference?, pendingKey: String?
    ) -> TodayTaskReference? {
        let target: TodayTaskReference?
        if let pendingKey {
            target = confirmationKey == pendingKey ? confirmationReference
                : (reference?.doseKey == pendingKey ? reference : nil)
        } else {
            target = reference ?? firstOpen
        }
        guard let target else { return nil }
        return candidates.first {
            $0.id == target.id && $0.medicationID == target.medicationID
                && (pendingKey == nil || ($0.doseKey == pendingKey && $0.isActionable))
        }
    }

    mutating func returnToList(_ firstOpen: TodayTaskReference?, isLocked: Bool) {
        guard !isLocked else { return }
        reference = firstOpen
        selectionEvent += 1
    }
}

/// Narrow cancellation contract: no task model, context, in-flight state or side effects.
enum TodayPendingConfirmationCancellation {
    static func matches(expectedKey: String, current: PendingDoseConfirmation?) -> Bool {
        current?.doseKey == expectedKey
    }

    static func cancelled(expectedKey: String, current: PendingDoseConfirmation?) -> PendingDoseConfirmation? {
        matches(expectedKey: expectedKey, current: current) ? nil : current
    }
}

enum TodayTaskLoadState: Equatable {
    case loading, failed, ready

    static func resolve(hasFetchError: Bool, isLoading: Bool, hasResults: Bool) -> Self {
        if hasFetchError { return .failed }
        return isLoading && !hasResults ? .loading : .ready
    }
}

enum TodayTaskWorkspaceLayout {
    // Content budgets, not a device posture detector.
    static let minimumWidth: CGFloat = 668
    static let minimumHeight: CGFloat = 360

    static func expands(width: CGFloat, height: CGFloat, isAccessibilitySize: Bool) -> Bool {
        !isAccessibilitySize && width >= minimumWidth && height >= minimumHeight
    }
}

struct TodayTaskLoadStatusView: View {
    let state: TodayTaskLoadState

    var body: some View {
        VStack(spacing: 16) {
            if state == .failed {
                Label("用药信息未能加载", systemImage: "exclamationmark.triangle")
                    .font(.title2.weight(.semibold))
                    .accessibilityIdentifier("today.load.error")
                Text("请重新打开应用后再试。当前无法核对任务，请勿依据空白列表判断今天没有用药。")
                    .foregroundStyle(.secondary)
            } else {
                ProgressView("正在加载今日任务")
                    .accessibilityIdentifier("today.load.loading")
            }
        }
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
    }
}

struct TodayTaskWorkspaceView<Supplementary: View>: View {
    @Environment(\.medcueDemoAllowsExternalActions) private var allowsExternalActions
    let snapshot: TodayRenderSnapshot
    let selectedTask: StoredDoseTask?
    let pendingDoseConfirmation: PendingDoseConfirmation?
    let pendingDoseFeedback: PendingDoseFeedback?
    let inFlightDoseKeys: Set<String>
    let closingDoseKeys: Set<String>
    let isSelectionLocked: Bool
    let actions: TodayScreenActions
    @Binding var selection: TodayTaskSelection
    @Binding var showingHandledTasks: Bool
    let archive: (StoredDoseTask) -> Void
    let supplementary: Supplementary
    @AccessibilityFocusState private var identityFocused: Bool

    private struct Reveal: Equatable {
        let taskID: UUID?
        let event: Int
        let confirmationKey: String?
    }

    private var firstOpen: TodayTaskReference? {
        snapshot.visibleOpenTimelineTasks.first { $0.status == .pending || $0.status == .delayed }
            .map { TodayTaskReference($0) }
    }

    var body: some View {
        GeometryReader { geometry in
            HStack(alignment: .top, spacing: 16) {
                ScrollView {
                    taskList
                        .padding(16)
                }
                .frame(width: min(340, max(280, geometry.size.width * 0.4)))
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("today.workspace.list")

                ScrollViewReader { detailScroll in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 18) {
                            if let selectedTask {
                                TodayTaskIdentityView(
                                    task: selectedTask, medication: actions.medication(selectedTask),
                                    status: actions.statusText(selectedTask)
                                )
                                .accessibilityFocused($identityFocused)
                                .id("today.workspace.detail.top")
                                taskMetadata(selectedTask)
                                if let medication = actions.medication(selectedTask) {
                                    NavigationLink {
                                        TodayMedicationDetailDestination(medication: medication)
                                    } label: {
                                        Label("查看药品资料", systemImage: "info.circle")
                                    }
                                    .disabled(isSelectionLocked)
                                }
                            } else {
                                TodayTaskMissingSelectionView(
                                    isLocked: isSelectionLocked, pendingKey: pendingDoseConfirmation?.doseKey,
                                    savingKeys: inFlightDoseKeys,
                                    cancelPending: actions.cancelPendingConfirmation,
                                    returnToList: { selection.returnToList(firstOpen, isLocked: isSelectionLocked) }
                                )
                                .id("today.workspace.detail.top")
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(20)
                    }
                    .safeAreaInset(edge: .bottom, spacing: 0) {
                        if let selectedTask { taskActions(selectedTask) }
                    }
                    .task(id: Reveal(taskID: selectedTask?.id, event: selection.selectionEvent,
                                     confirmationKey: pendingDoseConfirmation?.doseKey)) {
                        // Only this pane scrolls. Selecting a low list row must
                        // expose the new identity/dose without moving the list.
                        detailScroll.scrollTo("today.workspace.detail.top", anchor: .top)
                        guard selection.selectionEvent > 0, pendingDoseConfirmation == nil else { return }
                        await Task.yield()
                        guard !Task.isCancelled else { return }
                        identityFocused = true
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20))
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("today.workspace.detail")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(Color(.systemGroupedBackground))
        .accessibilityElement(children: .contain)
    }

    private var taskList: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("今日待处理")
                .font(.headline)
                .accessibilityIdentifier(AppAccessibilityID.todayOpenTimeline)
            if isSelectionLocked {
                Text("请先完成当前用药确认或等待当前操作结束，再选择其他任务。")
                    .font(.footnote).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if snapshot.visibleOpenTimelineTasks.isEmpty {
                Text(snapshot.emptyOpenTimelineMessage).foregroundStyle(.secondary)
            }
            ForEach(snapshot.visibleOpenTimelineTasks) { task in selector(task) }
            if snapshot.shouldShowHandledSection {
                Button {
                    showingHandledTasks.toggle()
                } label: {
                    Label("今日已处理 · \(snapshot.displayedHandledCount) 条",
                          systemImage: showingHandledTasks ? "chevron.up" : "chevron.down")
                }
                .accessibilityValue(showingHandledTasks ? "已展开" : "已折叠")
                .accessibilityIdentifier(AppAccessibilityID.todayHandledTimeline)
                if showingHandledTasks {
                    ForEach(snapshot.handledTodayTasks.filter { task in
                        !snapshot.visibleOpenTimelineTasks.contains { $0.id == task.id }
                    }) { task in selector(task) }
                }
            }
            if !snapshot.archivedTodayTasks.isEmpty {
                Text("今日已归档").font(.headline)
                ForEach(snapshot.archivedTodayTasks) { task in selector(task) }
            }
            if (snapshot.nextReminderTask != nil && snapshot.nextReminderTask?.id != selectedTask?.id)
                || snapshot.overdueOpenTaskCount > 0 || snapshot.shouldShowSkippedMedicationSummary {
                TodayNextReminderContents(snapshot: snapshot, actions: actions,
                                          showsReminder: snapshot.nextReminderTask?.id != selectedTask?.id)
            }
            supplementary
        }
    }

    private func selector(_ task: StoredDoseTask) -> some View {
        TodayTaskSelectorRow(
            task: task, medication: actions.medication(task), status: actions.statusText(task),
            isSelected: selectedTask?.id == task.id
        ) {
            _ = selection.select(TodayTaskReference(task), isLocked: isSelectionLocked)
        }
        .disabled(isSelectionLocked)
        .opacity(closingDoseKeys.contains(actions.logicalDoseKey(task)) ? 0.35 : 1)
    }

    private func taskMetadata(_ task: StoredDoseTask) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if let medication = actions.medication(task) {
                let specification = [medication.form, medication.strength].filter { !$0.isEmpty }.joined(separator: " · ")
                if !specification.isEmpty { LabeledContent("剂型与规格", value: specification) }
                if !medication.boxNumber.isEmpty { LabeledContent("药盒编号", value: medication.boxNumber) }
            }
            if snapshot.archivedTodayTasks.contains(where: { $0.id == task.id }) {
                Label("这条今日记录已归档", systemImage: "archivebox")
            }
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private func taskActions(_ task: StoredDoseTask) -> some View {
        let key = actions.logicalDoseKey(task)
        let accessibilityContext = todayDoseAccessibilityContext(task: task, medication: actions.medication(task))
        let isArchived = snapshot.archivedTodayTasks.contains { $0.id == task.id }
        let isOpen = !isArchived && (task.status == .pending || task.status == .delayed
            || closingDoseKeys.contains(key) || pendingDoseFeedback?.doseKey == key)
        VStack(spacing: 12) {
            if isOpen {
                TodayDoseActionsView(
                    taskID: task.id, completionText: actions.completionVerb(actions.medication(task)),
                    accessibilityContext: accessibilityContext,
                    feedbackAction: pendingDoseFeedback?.doseKey == key ? pendingDoseFeedback?.action : nil,
                    confirmationKind: pendingDoseConfirmation?.doseKey == key ? pendingDoseConfirmation?.kind : nil,
                    isActionInFlight: inFlightDoseKeys.contains(key), isTaskPanel: true,
                    markTaken: { perform(task, action: actions.markTaken) },
                    delay: { perform(task, action: actions.delay) },
                    skip: { perform(task, action: actions.skip) },
                    confirm: { actions.confirm(task) }, cancel: { actions.cancelConfirmation(task) }
                )
                .allowsHitTesting(!closingDoseKeys.contains(key))
            } else {
                HStack(spacing: 12) {
                    if snapshot.archivedTodayTasks.contains(where: { $0.id == task.id }) {
                        Button("恢复记录") { actions.unarchive(task) }
                            .accessibilityLabel(accessibilityContext.label(for: "恢复记录"))
                    } else {
                        Button("归档记录") { archive(task) }
                            .accessibilityLabel(accessibilityContext.label(for: "归档记录"))
                    }
                    Button("撤销") { perform(task, action: actions.undoOrReopen) }
                        .accessibilityLabel(accessibilityContext.label(for: "撤销"))
                }
                .buttonStyle(.bordered)
                .disabled(isSelectionLocked || !allowsExternalActions)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(16)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }

    private func perform(_ task: StoredDoseTask, action: (StoredDoseTask) -> Void) {
        selection.rememberActionTarget(TodayTaskReference(task))
        action(task)
    }
}

struct TodayTaskIdentityView: View {
    let task: StoredDoseTask
    let medication: StoredMedication?
    let status: String

    private var statusTint: Color {
        switch task.status {
        case .taken, .corrected: .green
        case .skipped: .orange
        case .pending, .delayed: .blue
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 16) {
                MedicationPhotoView(
                    photoData: medication?.photoData, symbolName: medication?.photoSymbolName ?? "pills.fill",
                    tint: medication.map(medicationColor(for:)) ?? .blue, size: 72
                )
                .accessibilityHidden(true)
                Text(medication.map(userFacingMedicationName(for:)) ?? "未知药品")
                    .font(.title2.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text("本次用量 · \(task.doseValue.formatted()) \(localizedMedicationUnit(task.doseUnit))")
                .font(.title3.weight(.semibold))
            Text("计划时间 · \(AppFormatters.time.string(from: task.dueAt))")
                .font(.headline).foregroundStyle(.secondary)
            StatusBadge(text: status, color: statusTint)
        }
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
        .accessibilityIdentifier("today.workspace.identity.\(task.id.uuidString)")
    }
}

private struct TodayTaskSelectorRow: View {
    let task: StoredDoseTask
    let medication: StoredMedication?
    let status: String
    let isSelected: Bool
    let select: () -> Void

    var body: some View {
        Button(action: select) {
            HStack(alignment: .top, spacing: 10) {
                MedicationPhotoView(
                    photoData: medication?.photoData, symbolName: medication?.photoSymbolName ?? "pills.fill",
                    tint: medication.map(medicationColor(for:)) ?? .blue, size: 36
                )
                .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 6) {
                    Text(AppFormatters.time.string(from: task.dueAt)).font(.caption.weight(.semibold))
                    Text(medication.map(userFacingMedicationName(for:)) ?? "未知药品")
                        .font(.headline)
                    Text("\(task.doseValue.formatted()) \(localizedMedicationUnit(task.doseUnit)) · \(status)")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                if isSelected { Image(systemName: "checkmark.circle.fill").foregroundStyle(.blue) }
            }
            .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
            .padding(12)
            .background(isSelected ? Color.blue.opacity(0.1) : Color(.secondarySystemGroupedBackground),
                        in: RoundedRectangle(cornerRadius: 14))
            .overlay {
                RoundedRectangle(cornerRadius: 14).stroke(isSelected ? Color.blue : Color.clear, lineWidth: 1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityHint("核对这次用药详情，不会记录服用")
        .accessibilityIdentifier("today.workspace.select.\(task.id.uuidString)")
    }
}

struct TodayTaskMissingSelectionView: View {
    let isLocked: Bool
    let pendingKey: String?
    let savingKeys: Set<String>
    let cancelPending: (String) -> Void
    let returnToList: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("这次任务已变化", systemImage: "list.bullet.rectangle")
                .font(.headline)
            Text("任务可能已处理、归档或不在当前列表。原来的确认不会被移到另一药品。")
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("today.workspace.unavailable")
            if let pendingKey {
                Button("取消原来的用药确认") { cancelPending(pendingKey) }
                    .disabled(savingKeys.contains(pendingKey))
                    .accessibilityIdentifier("today.workspace.cancel-unavailable-confirmation")
            } else {
                Button("返回任务列表", action: returnToList).disabled(isLocked)
                    .accessibilityIdentifier("today.workspace.return-to-list")
            }
            if !savingKeys.isEmpty {
                Text("当前保存仍在进行，请等待完成；取消确认不会取消保存。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

struct TodayNextReminderContents: View {
    let snapshot: TodayRenderSnapshot
    let actions: TodayScreenActions
    var showsReminder = true

    var body: some View {
        if showsReminder, let nextTask = snapshot.nextReminderTask {
                HStack {
                    Image(systemName: "bell.badge").foregroundStyle(.blue)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(actions.medication(nextTask).map(userFacingMedicationName(for:)) ?? "用药提醒")
                            .font(.headline)
                        Text(AppFormatters.time.string(from: nextTask.dueAt)).font(.subheadline).foregroundStyle(.secondary)
                    }
                }.padding(.vertical, 6)
        } else if snapshot.overdueOpenTaskCount > 0 {
                Label("还有 \(snapshot.overdueOpenTaskCount) 项待确认", systemImage: "clock.badge.exclamationmark")
                    .font(.headline).foregroundStyle(.orange).padding(.vertical, 6)
        } else if showsReminder {
            Text("今天没有待提醒任务。").foregroundStyle(.secondary)
        }
        if snapshot.shouldShowSkippedMedicationSummary {
            VStack(alignment: .leading, spacing: 8) {
                Label("今日忽略记录", systemImage: "exclamationmark.circle").font(.headline).foregroundStyle(.orange)
                Text(snapshot.skippedMedicationSummary).font(.subheadline).foregroundStyle(.secondary)
            }.padding(.vertical, 6)
        }
    }
}

func todayDoseStatusText(
    for task: StoredDoseTask,
    medication: StoredMedication?,
    delayDurationText: String
) -> String {
    switch task.status {
    case .taken, .corrected:
        todayCompletionVerb(for: medication)
    case .skipped:
        "已忽略"
    case .pending:
        task.status.displayName
    case .delayed:
        "\(delayDurationText)后"
    }
}

struct TodayCompactTaskReveal: Equatable {
    let taskID: UUID?
    let event: Int
    let confirmationKey: String?
}

// Read-only migration display snapshots, shared with the Today owner.
func todayClosingMigrationSnapshot(task: StoredDoseTask, medication: StoredMedication?, action: PendingDoseFeedback.Action, delayDurationText: @autoclosure () -> String) -> DoseMigrationSnapshot {
    let statusText: String
    switch action {
    case .taken:
        statusText = todayCompletionVerb(for: medication)
    case .skip:
        statusText = "已忽略"
    case .delay:
        statusText = "\(delayDurationText())后"
    }
    return DoseMigrationSnapshot(
        id: task.id,
        medicationName: medication.map(userFacingMedicationName(for:)) ?? "未知药品",
        doseText: "\(task.doseValue.formatted()) \(localizedMedicationUnit(task.doseUnit))",
        timeText: AppFormatters.time.string(from: task.dueAt),
        symbolName: medication?.photoSymbolName ?? "pills.fill",
        statusText: statusText,
        direction: .toHandled
    )
}

func todayReopeningMigrationSnapshot(task: StoredDoseTask, medication: StoredMedication?) -> DoseMigrationSnapshot {
    return DoseMigrationSnapshot(
        id: task.id,
        medicationName: medication.map(userFacingMedicationName(for:)) ?? "未知药品",
        doseText: "\(task.doseValue.formatted()) \(localizedMedicationUnit(task.doseUnit))",
        timeText: AppFormatters.time.string(from: task.dueAt),
        symbolName: medication?.photoSymbolName ?? "pills.fill",
        statusText: "待处理",
        direction: .toOpen
    )
}

#if DEBUG && targetEnvironment(simulator)
/// Scalar observations only: never stores a task, dose key or user value.
struct TodayCancellationProbeState {
    static let limit = 4
    enum Outcome: Equatable { case unknown, notEntered, keyRejected, notCleared, ownerChanged, reRequested, pendingReappeared, renderStateMismatch, clearedWithAXResidue, cleared }
    private(set) var ownerCount = 0
    private(set) var entryCount = 0
    private(set) var entryOwner = 0
    private(set) var keyMatches = false
    private(set) var pendingCleared = false
    private(set) var clearOwner = 0
    private(set) var requestCount = 0
    private(set) var requestsAfterClear = 0
    private(set) var observedOwner = 0
    private(set) var observedPending = false
    private(set) var reappearedAfterClear = false
    private(set) var overflow = false

    mutating func registerOwner() -> Int {
        guard ownerCount < Self.limit else { overflow = true; return 0 }
        ownerCount += 1
        return ownerCount
    }

    mutating func recordRequest(owner: Int) {
        guard (1...Self.limit).contains(owner) else { overflow = true; return }
        if requestCount < Self.limit { requestCount += 1 } else { overflow = true }
        if pendingCleared {
            if requestsAfterClear < Self.limit { requestsAfterClear += 1 } else { overflow = true }
        }
    }

    mutating func recordEntry(owner: Int, keyMatches: Bool) {
        guard (1...Self.limit).contains(owner) else { overflow = true; return }
        if entryCount < Self.limit { entryCount += 1 } else { overflow = true }
        entryOwner = owner
        self.keyMatches = keyMatches
    }

    mutating func recordClear(owner: Int, isNil: Bool) {
        guard (1...Self.limit).contains(owner) else { overflow = true; return }
        if isNil { pendingCleared = true; clearOwner = owner }
        observe(owner: owner, pending: !isNil)
    }

    mutating func observe(owner: Int, pending: Bool) {
        guard (1...Self.limit).contains(owner) else { overflow = true; return }
        observedOwner = owner
        observedPending = pending
        if pendingCleared && pending { reappearedAfterClear = true }
    }

    /// Version plus fixed bounded integer/boolean fields; no free-form values.
    var scalarValue: String {
        [2, ownerCount, entryCount, entryOwner, keyMatches ? 1 : 0,
         pendingCleared ? 1 : 0, clearOwner, requestCount, requestsAfterClear,
         observedOwner, observedPending ? 1 : 0, reappearedAfterClear ? 1 : 0,
         overflow ? 1 : 0].map(String.init).joined(separator: ",")
    }

    func outcome(renderedOwner: Int, renderedPending: Bool, cancelAXExists: Bool, sampleIsFresh: Bool) -> Outcome {
        guard sampleIsFresh, !overflow, (1...Self.limit).contains(renderedOwner),
              (1...Self.limit).contains(ownerCount), (1...Self.limit).contains(observedOwner),
              entryCount == 0 || (1...Self.limit).contains(entryOwner),
              !pendingCleared || (1...Self.limit).contains(clearOwner) else { return .unknown }
        guard entryCount > 0 else { return .notEntered }
        guard keyMatches else { return .keyRejected }
        guard pendingCleared else { return .notCleared }
        guard entryOwner == renderedOwner && clearOwner == renderedOwner && observedOwner == renderedOwner else { return .ownerChanged }
        if requestsAfterClear > 0 { return .reRequested }
        if reappearedAfterClear { return .pendingReappeared }
        if renderedPending || observedPending { return .renderStateMismatch }
        return cancelAXExists ? .clearedWithAXResidue : .cleared
    }
}

/// Not Observable/Published: observations cannot drive the production layout.
@MainActor
final class TodayCancellationProbe {
    var state = TodayCancellationProbeState()
    private var sampleGeneration = 0
    private var sampleOverflow = false

    /// Existing Timeline samples only; no timer, publisher or business state.
    /// Same simulator boot clock as XCTest; bounded stamps are never logged.
    func sampledScalarValue() -> String {
        if sampleGeneration < 65_535 { sampleGeneration += 1 } else { sampleOverflow = true }
        let milliseconds = ProcessInfo.processInfo.systemUptime * 1_000
        let clockValid = milliseconds.isFinite && milliseconds >= 0 && milliseconds <= 9_007_199_254_740_991
        if !clockValid { sampleOverflow = true }
        let tick = clockValid ? Int(milliseconds) : 0
        return state.scalarValue + ",\(sampleGeneration),\(tick),\(sampleOverflow ? 1 : 0)"
    }
}
#endif
