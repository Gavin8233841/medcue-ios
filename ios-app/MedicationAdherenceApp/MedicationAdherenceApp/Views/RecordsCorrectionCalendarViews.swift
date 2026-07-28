import MedicationAdherenceCore
import SwiftData
import SwiftUI

struct DoseRecordCorrectionView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    let task: StoredDoseTask
    let medication: StoredMedication?
    @StateObject private var notificationService = NotificationService()
    @StateObject private var liveActivityService = MedicationLiveActivityService()
    @State private var status: StoredDoseStatus
    @State private var plannedAt: Date
    @State private var recordedAt: Date
    @State private var note: String
    @State private var showingEarlyRecordConfirmation = false
    @State private var showingSaveFailure = false
    @State private var isSaveFlowActive = false

    init(task: StoredDoseTask, medication: StoredMedication?) {
        self.task = task
        self.medication = medication
        _status = State(initialValue: task.status)
        _plannedAt = State(initialValue: task.dueAt)
        _recordedAt = State(initialValue: min(task.effectiveAdherenceRecordedAt ?? task.recordedAt ?? task.dueAt, Date()))
        _note = State(initialValue: task.recordDisplayReason ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("记录") {
                    HStack(spacing: 12) {
                        MedicationPhotoView(
                            photoData: medication?.photoData,
                            symbolName: medication?.photoSymbolName ?? "pills.fill",
                            tint: .blue,
                            size: 44
                        )
                        VStack(alignment: .leading, spacing: 4) {
                            Text(medication.map(userFacingMedicationName(for:)) ?? "未知药品")
                                .font(.headline)
                            Text("\(task.doseValue.formatted()) \(localizedMedicationUnit(task.doseUnit))")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Picker("状态", selection: $status) {
                        Text("待处理").tag(StoredDoseStatus.pending)
                        Text("已服用").tag(StoredDoseStatus.taken)
                        Text("稍后提醒").tag(StoredDoseStatus.delayed)
                        Text("已忽略").tag(StoredDoseStatus.skipped)
                        Text("已修正").tag(StoredDoseStatus.corrected)
                    }
                    DatePicker("计划时间", selection: $plannedAt)
                    if status != .pending {
                        DatePicker("实际记录时间", selection: $recordedAt, in: ...Date())
                    }
                }

                Section("备注") {
                    TextEditor(text: $note)
                        .frame(minHeight: 96)
                }
            }
            .navigationTitle("修正记录")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        saveWithEarlyRecordCheck()
                    }
                    .disabled(isSaveFlowActive)
                }
            }
            .alert("确认提前记录？", isPresented: $showingEarlyRecordConfirmation) {
                Button("确认已提前服用") {
                    save(confirmedEarlyRecord: true)
                }
                Button("返回修改", role: .cancel) {}
            } message: {
                Text("实际记录时间距离计划时间较久。请确认这是按医嘱、说明书或医生或药师建议提前服用。")
            }
            .alert("修正未保存", isPresented: $showingSaveFailure) {
                Button("知道了", role: .cancel) {}
            } message: {
                Text("记录仍保持原状，请稍后重试。")
            }
        }
    }

    private func saveWithEarlyRecordCheck() {
        guard !isSaveFlowActive else { return }
        let clampedRecordedAt = min(recordedAt, Date())
        guard shouldConfirmEarlyRecord(recordedAt: clampedRecordedAt) else {
            save(confirmedEarlyRecord: false)
            return
        }
        showingEarlyRecordConfirmation = true
    }

    private func shouldConfirmEarlyRecord(recordedAt: Date) -> Bool {
        guard status == .taken || status == .corrected else {
            return false
        }
        return DoseReminderPolicy.competitionDemo.requiresEarlyTakenConfirmation(
            plannedDueAt: plannedAt,
            now: recordedAt
        )
    }

    private func save(confirmedEarlyRecord: Bool) {
        guard !isSaveFlowActive else { return }
        isSaveFlowActive = true
        let occurredAt = Date()
        let outcome = DoseRecordCorrectionCommand(modelContext: modelContext).perform(
            DoseRecordCorrectionInput(
                taskID: task.id,
                status: status,
                plannedAt: plannedAt,
                recordedAt: min(recordedAt, occurredAt),
                note: note,
                confirmedEarlyRecord: confirmedEarlyRecord,
                occurredAt: occurredAt
            )
        )
        switch outcome {
        case let .committed(commit):
            synchronizeReminderAfterCorrection(taskIDs: commit.taskIDs)
            dismiss()
        case .rejected, .saveFailed:
            isSaveFlowActive = false
            showingSaveFailure = true
        }
    }

    private func synchronizeReminderAfterCorrection(taskIDs: [UUID]) {
        let taskIDSet = Set(taskIDs)
        let group = (try? modelContext.fetch(
            FetchDescriptor<StoredDoseTask>(
                predicate: #Predicate<StoredDoseTask> { storedTask in
                    taskIDSet.contains(storedTask.id)
                }
            )
        )) ?? [task]
        let shouldKeepReminder = (task.status == .pending || task.status == .delayed) && task.dueAt > Date()
        guard shouldKeepReminder, let medication else {
            Task { @MainActor in
                for groupTask in group {
                    notificationService.cancelReminder(for: groupTask.id)
                    await liveActivityService.end(for: groupTask.id)
                }
            }
            return
        }

        let planID = task.planID
        var planDescriptor = FetchDescriptor<StoredMedicationPlan>(
            predicate: #Predicate<StoredMedicationPlan> { plan in
                plan.id == planID
            }
        )
        planDescriptor.fetchLimit = 1
        let deliveryMethod = (try? modelContext.fetch(planDescriptor).first)?.reminderDeliveryMethod ?? .notification
        Task { @MainActor in
            for groupTask in group {
                if groupTask.id == task.id {
                    await notificationService.scheduleReminder(
                        for: groupTask,
                        medication: medication,
                        deliveryMethod: deliveryMethod
                    )
                } else {
                    notificationService.cancelReminder(for: groupTask.id)
                }
                await liveActivityService.end(for: groupTask.id)
            }
            await liveActivityService.startIfNeeded(for: task, medication: medication)
        }
    }
}

struct WeekSummaryRow: View {
    let completedCount: Int
    let totalCount: Int
    let skippedCount: Int
    let delayedCount: Int
    let isMonthExpanded: Bool
    var showsMonthToggle = true

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 14) {
                MedicationSymbolView(symbolName: "calendar", tint: .secondary)
                    .frame(width: 52, height: 52)
                VStack(alignment: .leading, spacing: 5) {
                    Text("本周记录")
                        .font(.headline)
                    Text(totalCount == 0 ? "本周暂无任务" : "\(completedCount) / \(totalCount) 项已完成")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    if skippedCount > 0 || delayedCount > 0 {
                        Text("忽略 \(skippedCount) 次，稍后 \(delayedCount) 次")
                            .font(.footnote)
                            .foregroundStyle(.orange)
                    }
                }
                Spacer()
                if showsMonthToggle {
                    HStack(spacing: 5) {
                        Text(isMonthExpanded ? "收起月历" : "展开月历")
                        Image(systemName: isMonthExpanded ? "chevron.up" : "chevron.down")
                            .font(.caption2.weight(.bold))
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(.secondary.opacity(0.09), in: Capsule())
                    .accessibilityLabel(isMonthExpanded ? "收起月历" : "展开月历")
                }
            }

            ProgressView(value: totalCount == 0 ? 0 : Double(completedCount), total: Double(max(totalCount, 1)))
                .tint(progressTint)
        }
        .padding(.vertical, 6)
    }

    private var progressTint: Color {
        if skippedCount > 0 || delayedCount > 0 {
            return .orange
        }
        if completedCount == totalCount && totalCount > 0 {
            return .green
        }
        if totalCount > 0 {
            return .blue
        }
        return .secondary.opacity(0.55)
    }
}

struct MonthNavigationButton: View {
    let systemImage: String
    let accessibilityText: String
    let isEnabled: Bool

    var body: some View {
        Image(systemName: systemImage)
            .font(.caption.weight(.bold))
            .frame(width: 32, height: 32)
            .background(.secondary.opacity(isEnabled ? 0.08 : 0.035), in: Circle())
            .foregroundStyle(.secondary.opacity(isEnabled ? 0.95 : 0.32))
            .accessibilityLabel(accessibilityText)
    }
}

struct WeekDoseCalendarView: View {
    @Binding var selectedDate: Date
    let days: [Date]
    let tasksForDay: (Date) -> [StoredDoseTask]
    let doseChangesForDay: (Date) -> [StoredMedicationDoseChange]
    let openDay: (Date) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("本周日历")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            HStack(spacing: 7) {
                ForEach(days, id: \.self) { day in
                    DoseCalendarDayButton(
                        day: day,
                        tasks: tasksForDay(day),
                        doseChangeCount: doseChangesForDay(day).count,
                        isSelected: Calendar.current.isDate(day, inSameDayAs: selectedDate),
                        showsWeekday: true,
                        action: {
                            selectedDate = day
                            openDay(day)
                        }
                    )
                }
            }
        }
        .padding(.vertical, 8)
    }
}

struct MonthDoseCalendarView: View {
    @Binding var selectedDate: Date
    @Binding var displayedMonth: Date
    let monthRange: ClosedRange<Date>
    let days: [Date]
    let tasksForDay: (Date) -> [StoredDoseTask]
    let doseChangesForDay: (Date) -> [StoredMedicationDoseChange]
    let openDay: (Date) -> Void
    let transitionDirection: Int
    let moveMonth: (Int) -> Void
    let tint: Color

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 7)

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Button {
                    withAnimation(.snappy(duration: 0.24, extraBounce: 0.01)) {
                        moveMonth(-1)
                    }
                } label: {
                    MonthNavigationButton(
                        systemImage: "chevron.left",
                        accessibilityText: "上一月",
                        isEnabled: canMoveBackward
                    )
                }
                .buttonStyle(.plain)
                .disabled(!canMoveBackward)
                .accessibilityLabel("上一月")

                Spacer()
                Text(monthTitle)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Spacer()
                Button {
                    withAnimation(.snappy(duration: 0.24, extraBounce: 0.01)) {
                        moveMonth(1)
                    }
                } label: {
                    MonthNavigationButton(
                        systemImage: "chevron.right",
                        accessibilityText: "下一月",
                        isEnabled: canMoveForward
                    )
                }
                .buttonStyle(.plain)
                .disabled(!canMoveForward)
                .accessibilityLabel("下一月")
            }
            .foregroundStyle(.secondary)

            HStack(spacing: 0) {
                ForEach(weekdaySymbols, id: \.self) { symbol in
                    Text(symbol)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }

            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(Array(monthCells.enumerated()), id: \.offset) { _, cellDate in
                    if let day = cellDate {
                        DoseCalendarDayButton(
                            day: day,
                            tasks: tasksForDay(day),
                            doseChangeCount: doseChangesForDay(day).count,
                            isSelected: Calendar.current.isDate(day, inSameDayAs: selectedDate),
                            showsWeekday: false,
                            tint: tint,
                            action: {
                                selectedDate = day
                                openDay(day)
                            }
                        )
                    } else {
                        Color.clear
                            .frame(maxWidth: .infinity, minHeight: 52)
                    }
                }
            }
            .id(displayedMonth)
            .transition(monthGridTransition)
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 28)
                .onEnded { value in
                    if value.translation.width < -44 {
                        moveMonth(1)
                    } else if value.translation.width > 44 {
                        moveMonth(-1)
                    }
                }
        )
        .animation(.smooth(duration: 0.18), value: displayedMonth)
    }

    private var monthTitle: String {
        AppFormatters.month.string(from: displayedMonth)
    }

    private var weekdaySymbols: [String] {
        ["日", "一", "二", "三", "四", "五", "六"]
    }

    private var monthCells: [Date?] {
        guard let firstDay = days.first else {
            return []
        }
        let leadingCount = Calendar.current.component(.weekday, from: firstDay) - 1
        return Array(repeating: nil, count: max(0, leadingCount)) + days.map(Optional.some)
    }

    private var canMoveBackward: Bool {
        monthRange.contains(previousMonth)
    }

    private var canMoveForward: Bool {
        monthRange.contains(nextMonth)
    }

    private var previousMonth: Date {
        Calendar.current.date(byAdding: .month, value: -1, to: displayedMonth) ?? displayedMonth
    }

    private var nextMonth: Date {
        Calendar.current.date(byAdding: .month, value: 1, to: displayedMonth) ?? displayedMonth
    }

    private var monthGridTransition: AnyTransition {
        .opacity
    }
}

struct DoseCalendarDayButton: View {
    let day: Date
    let tasks: [StoredDoseTask]
    let doseChangeCount: Int
    let isSelected: Bool
    let showsWeekday: Bool
    var tint: Color = .blue
    let action: () -> Void

    private var completedCount: Int {
        tasks.filter { $0.status == .taken || $0.status == .corrected }.count
    }

    private var isFuturePlanOnly: Bool {
        recordsTasksAreFuturePlanOnly(tasks, on: day, now: Date())
    }

    var body: some View {
        Button(action: action) {
            if showsWeekday {
                weekBody
            } else {
                monthBody
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityText)
    }

    private var weekBody: some View {
        VStack(spacing: 5) {
            Text(weekdayText)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            ZStack(alignment: .center) {
                RecordsCalendarProgressRing(
                    progress: dayProgress,
                    color: indicatorColor.opacity(indicatorOpacity),
                    isEmpty: tasks.isEmpty,
                    size: 34,
                    lineWidth: 4
                )
                Text(dayNumberText)
                    .font(.subheadline.weight(.semibold))
                if doseChangeCount > 0 {
                    Circle()
                        .fill(Color.purple.opacity(0.72))
                        .frame(width: 6, height: 6)
                        .frame(width: 34, height: 34, alignment: .topTrailing)
                        .offset(x: 1.5, y: -1.5)
                }
            }
            if !tasks.isEmpty {
                Text(dayProgressText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 58)
        .background(dayBackground, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(isSelected ? tint.opacity(0.45) : Color.clear, lineWidth: 1)
        }
    }

    private var monthBody: some View {
        VStack(spacing: 4) {
            ZStack(alignment: .center) {
                RecordsCalendarProgressRing(
                    progress: dayProgress,
                    color: indicatorColor.opacity(indicatorOpacity),
                    isEmpty: tasks.isEmpty,
                    size: 32,
                    lineWidth: 3.5
                )
                Text(dayNumberText)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(isSelected ? tint : .primary.opacity(0.82))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                if doseChangeCount > 0 {
                    Circle()
                        .fill(Color.purple.opacity(0.72))
                        .frame(width: 5, height: 5)
                        .frame(width: 32, height: 32, alignment: .topTrailing)
                        .offset(x: 1.5, y: -1.5)
                }
            }
            Text(tasks.isEmpty ? " " : dayProgressText)
                .font(.system(size: 8, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.72)
            .frame(height: 9)
        }
        .padding(.horizontal, 2)
        .frame(maxWidth: .infinity, minHeight: 52)
        .background(dayBackground, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(isSelected ? tint.opacity(0.46) : Color.clear, lineWidth: 1)
        }
    }

    private var dayBackground: Color {
        isSelected ? tint.opacity(0.14) : Color.secondary.opacity(0.032)
    }

    private var dayNumberText: String {
        "\(Calendar.current.component(.day, from: day))"
    }

    private var accessibilityText: String {
        let taskText = tasks.isEmpty ? "没有用药任务" : (isFuturePlanOnly ? "\(tasks.count) 项计划中" : "\(completedCount) / \(tasks.count) 项已完成")
        let doseChangeText = doseChangeCount > 0 ? "，\(doseChangeCount) 条剂量变化" : ""
        return "\(AppFormatters.day.string(from: day))，\(taskText)\(doseChangeText)"
    }

    private var dayProgressText: String {
        isFuturePlanOnly ? "\(tasks.count)项" : "\(completedCount)/\(tasks.count)"
    }

    private var dayProgress: Double {
        guard !tasks.isEmpty else {
            return 0
        }
        return isFuturePlanOnly ? 0 : Double(completedCount) / Double(tasks.count)
    }

    private var weekdayText: String {
        let symbols = ["日", "一", "二", "三", "四", "五", "六"]
        let index = Calendar.current.component(.weekday, from: day) - 1
        return symbols[max(0, min(index, symbols.count - 1))]
    }

    private var indicatorColor: Color {
        guard !tasks.isEmpty else {
            return doseChangeCount > 0 ? .purple : .secondary
        }
        if tasks.contains(where: { $0.status == .skipped }) {
            return .orange
        }
        if tasks.allSatisfy({ $0.status == .taken || $0.status == .corrected }) {
            return .green
        }
        if isFuturePlanOnly {
            return .secondary
        }
        return tint
    }

    private var indicatorOpacity: Double {
        guard !tasks.isEmpty else {
            return doseChangeCount > 0 ? 0.62 : 0
        }
        if tasks.contains(where: { $0.status == .skipped }) {
            return 0.72
        }
        if tasks.allSatisfy({ $0.status == .taken || $0.status == .corrected }) {
            return 0.68
        }
        if isFuturePlanOnly {
            return 0.34
        }
        return 0.56
    }
}

struct DayDoseListView: View {
    let date: Date
    let tasks: [StoredDoseTask]
    let doseChanges: [StoredMedicationDoseChange]
    let allDoseChanges: [StoredMedicationDoseChange]
    let medication: (StoredDoseTask) -> StoredMedication?
    let medicationForDoseChange: (StoredMedicationDoseChange) -> StoredMedication?
    let openTask: (StoredDoseTask) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if tasks.isEmpty {
                Text("这一天没有用药任务。")
                    .foregroundStyle(.secondary)
            } else if isFuturePlanOnly {
                Text("这一天有 \(tasks.count) 项计划提醒，尚未到记录时间。")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(tasks) { task in
                    Button {
                        openTask(task)
                    } label: {
                        DayDoseTaskLine(task: task, medication: medication(task))
                    }
                    .buttonStyle(.plain)
                }
            }

            if !doseChanges.isEmpty {
                Divider()
                Text("剂量变化")
                    .font(.subheadline.weight(.semibold))
                ForEach(doseChanges) { change in
                    DoseChangeLine(
                        change: change,
                        effectiveUntil: doseChangeEffectiveUntil(change, in: allDoseChanges),
                        medication: medicationForDoseChange(change)
                    )
                }
            }
        }
        .padding(.vertical, 8)
    }

    private var isFuturePlanOnly: Bool {
        recordsTasksAreFuturePlanOnly(tasks, on: date, now: Date())
    }
}

struct DayDoseDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    let date: Date
    let tasks: [StoredDoseTask]
    let actionLogs: [StoredDoseActionLog]
    let doseChanges: [StoredMedicationDoseChange]
    let allDoseChanges: [StoredMedicationDoseChange]
    let medication: (StoredDoseTask) -> StoredMedication?
    let medicationForDoseChange: (StoredMedicationDoseChange) -> StoredMedication?
    let medicationForActionLog: (StoredDoseActionLog) -> StoredMedication?
    let isPresentingCorrection: Bool
    let openTask: (StoredDoseTask) -> Void

    private var completedCount: Int {
        tasks.filter { $0.status == .taken || $0.status == .corrected }.count
    }

    private var skippedCount: Int {
        tasks.filter { $0.status == .skipped }.count
    }

    private var delayedCount: Int {
        tasks.filter { $0.status == .delayed }.count
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                DayDoseDetailHeroCard(
                    date: date,
                    totalCount: tasks.count,
                    completedCount: completedCount,
                    skippedCount: skippedCount,
                    delayedCount: delayedCount,
                    doseChangeCount: doseChanges.count,
                    isFuturePlanOnly: isFuturePlanOnly
                )

                RecordsPanelContainer(
                    title: "当天服药详情",
                    subtitle: tasks.isEmpty ? "这一天没有服药记录" : nil
                ) {
                    if tasks.isEmpty {
                        RecordsEmptyStateLine(
                            systemImage: "calendar.badge.clock",
                            title: "这一天没有用药任务",
                            message: "暂无记录。"
                        )
                    } else if isFuturePlanOnly {
                        RecordsEmptyStateLine(
                            systemImage: "calendar.badge.clock",
                            title: "\(tasks.count) 项计划提醒",
                            message: "尚未到记录时间。"
                        )
                    } else {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(tasks.enumerated()), id: \.element.id) { index, task in
                                Button {
                                    openTask(task)
                                } label: {
                                    DayDoseDetailTaskRow(task: task, medication: medication(task))
                                }
                                .buttonStyle(.plain)
                                .padding(.vertical, 10)

                                if index < tasks.count - 1 {
                                    Divider()
                                        .opacity(0.42)
                                        .padding(.leading, 56)
                                }
                            }
                        }
                    }
                }

                if !actionLogs.isEmpty {
                    RecordsPanelContainer(title: "操作记录") {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(actionLogs.enumerated()), id: \.element.id) { index, log in
                                DoseActionLogRow(
                                    log: log,
                                    medication: medicationForActionLog(log)
                                )
                                .padding(.vertical, 9)

                                if index < actionLogs.count - 1 {
                                    Divider()
                                        .opacity(0.42)
                                        .padding(.leading, 46)
                                }
                            }
                        }
                    }
                }

                if !doseChanges.isEmpty {
                    RecordsPanelContainer(title: "剂量变化") {
                        LazyVStack(alignment: .leading, spacing: 8) {
                            ForEach(doseChanges) { change in
                                DoseChangeLine(
                                    change: change,
                                    effectiveUntil: doseChangeEffectiveUntil(change, in: allDoseChanges),
                                    medication: medicationForDoseChange(change)
                                )
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 28)
        }
        .transaction { transaction in
            transaction.animation = nil
        }
        .accessibilityHidden(isPresentingCorrection)
        .background(Color(.systemGroupedBackground))
        .navigationTitle("日期详情")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("完成") {
                    dismiss()
                }
            }
        }
    }

    private var daySummaryText: String {
        var parts: [String] = []
        parts.append(tasks.isEmpty ? "这一天没有用药任务。" : (isFuturePlanOnly ? "\(tasks.count) 项计划提醒，尚未到记录时间。" : "\(tasks.count) 项用药记录。"))
        if !doseChanges.isEmpty {
            parts.append("\(doseChanges.count) 条剂量变化。")
        }
        return parts.joined(separator: " ")
    }

    private var isFuturePlanOnly: Bool {
        recordsTasksAreFuturePlanOnly(tasks, on: date, now: Date())
    }
}

struct DoseActionLogRow: View {
    let log: StoredDoseActionLog
    let medication: StoredMedication?

    private var isClosed: Bool {
        log.undoneAt != nil
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: iconName)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 30, height: 30)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(log.actionDisplayName)
                        .font(.subheadline.weight(.semibold))
                    if isClosed {
                        Text("已撤销")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.secondary.opacity(0.10), in: Capsule())
                    }
                }
                Text("\(medication.map(userFacingMedicationName(for:)) ?? "未知药品") · \(AppFormatters.time.string(from: log.occurredAt))")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                if let displayNote = log.recordDisplayNote {
                    Text(displayNote)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    private var tint: Color {
        switch DoseActionKind(rawValue: log.actionRaw) {
        case .markTaken:
            .green
        case .delay:
            .blue
        case .skip:
            .orange
        case .archiveToday, .restoreArchive:
            .secondary
        case .correct, nil:
            .blue
        }
    }

    private var iconName: String {
        switch DoseActionKind(rawValue: log.actionRaw) {
        case .markTaken:
            "checkmark.circle.fill"
        case .delay:
            "clock.arrow.circlepath"
        case .skip:
            "forward.circle.fill"
        case .archiveToday:
            "archivebox.fill"
        case .restoreArchive:
            "tray.and.arrow.up.fill"
        case .correct, nil:
            "pencil.circle.fill"
        }
    }
}

struct RecordsLinearProgressBar: View {
    let progress: Double
    let tint: Color

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.secondary.opacity(0.10))
                Capsule()
                    .fill(tint.opacity(0.58))
                    .frame(width: max(0, proxy.size.width * progress))
            }
        }
        .frame(height: 5)
        .accessibilityLabel("当天完成进度")
        .accessibilityValue("\(Int((progress * 100).rounded()))%")
    }
}

struct DayDoseDetailHeroCard: View {
    let date: Date
    let totalCount: Int
    let completedCount: Int
    let skippedCount: Int
    let delayedCount: Int
    let doseChangeCount: Int
    let isFuturePlanOnly: Bool

    private var summaryText: String {
        if totalCount == 0, doseChangeCount == 0 {
            return "没有需要展示的服药记录。"
        }
        if isFuturePlanOnly {
            return "\(totalCount) 项计划提醒，尚未到记录时间。"
        }
        if completedCount == totalCount, totalCount > 0 {
            return doseChangeCount > 0 ? "当天记录已完成，并有剂量变化。" : "当天记录已完成。"
        }
        if skippedCount > 0 || delayedCount > 0 {
            return "有忽略或稍后记录。"
        }
        if doseChangeCount > 0 {
            return "\(doseChangeCount) 条剂量变化。"
        }
        return "\(completedCount) / \(totalCount) 项已完成。"
    }

    private var completionRatio: Double {
        guard totalCount > 0, !isFuturePlanOnly else {
            return 0
        }
        return min(max(Double(completedCount) / Double(totalCount), 0), 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: "calendar")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(progressTint)
                    .frame(width: 46, height: 46)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                VStack(alignment: .leading, spacing: 5) {
                    Text(AppFormatters.day.string(from: date))
                        .font(.title3.weight(.semibold))
                    Text(summaryText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }

            RecordsLinearProgressBar(
                progress: completionRatio,
                tint: progressTint
            )

            HStack(spacing: 0) {
                RecordsMetricPill(title: isFuturePlanOnly ? "计划" : "总记录", value: "\(totalCount)")
                RecordsMetricDivider()
                RecordsMetricPill(title: "已完成", value: "\(completedCount)")
                RecordsMetricDivider()
                RecordsMetricPill(title: "剂量变化", value: "\(doseChangeCount)")
            }
        }
        .padding(18)
        .medicationGlassSurface(cornerRadius: 18, tint: progressTint, fallbackMaterial: .regularMaterial)
        .shadow(color: Color.black.opacity(0.035), radius: 10, x: 0, y: 4)
    }

    private var progressTint: Color {
        if skippedCount > 0 || delayedCount > 0 {
            return .orange
        }
        if completionRatio >= 0.999, totalCount > 0 {
            return .green
        }
        if totalCount > 0, !isFuturePlanOnly {
            return .blue
        }
        if doseChangeCount > 0 {
            return .purple
        }
        return .secondary
    }
}

struct DayDoseDetailTaskRow: View {
    let task: StoredDoseTask
    let medication: StoredMedication?

    private var badgeColor: Color {
        switch task.status {
        case .taken, .corrected:
            return .green
        case .delayed:
            return .blue
        case .skipped:
            return .orange
        case .pending:
            return .secondary
        }
    }

    private var recordTimingTolerance: TimeInterval {
        DoseReminderPolicy.competitionDemo.autoSkipInterval
    }

    private var timeDetailText: String {
        let planned = AppFormatters.time.string(from: task.dueAt)
        guard task.status != .pending, let recordedAt = task.effectiveAdherenceRecordedAt else {
            return "计划 \(planned)"
        }
        let recorded = AppFormatters.time.string(from: recordedAt)
        switch task.status {
        case .delayed:
            return "计划 \(planned) · 稍后操作 \(recorded)"
        case .skipped:
            let actionTitle = task.isAutoSkippedByReminderSettlement ? "自动忽略" : "忽略操作"
            return "计划 \(planned) · \(actionTitle) \(recorded)"
        case .pending, .taken, .corrected:
            break
        }
        if recorded == planned {
            return "计划 \(planned) · 已按时记录"
        }
        if recordedAt < task.dueAt.addingTimeInterval(-recordTimingTolerance) {
            return "计划 \(planned) · 提前记录 \(recorded)"
        }
        if recordedAt > task.dueAt.addingTimeInterval(recordTimingTolerance) {
            return "计划 \(planned) · 延后记录 \(recorded)"
        }
        return "计划 \(planned) · 记录 \(recorded)"
    }

    var body: some View {
        HStack(spacing: 12) {
            MedicationPhotoView(
                photoData: medication?.photoData,
                symbolName: medication?.photoSymbolName ?? "pills.fill",
                tint: badgeColor,
                size: 42
            )

            VStack(alignment: .leading, spacing: 4) {
                Text(medication.map(userFacingMedicationName(for:)) ?? "未知药品")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(timeDetailText)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.84)
                Text("\(task.doseValue.formatted()) \(localizedMedicationUnit(task.doseUnit))")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                if let displayReason = task.recordDisplayReason {
                    Text(displayReason)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 6) {
                StatusBadge(text: task.status.displayName, color: badgeColor)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .contentShape(Rectangle())
    }
}

struct DoseChangeLine: View {
    let change: StoredMedicationDoseChange
    let effectiveUntil: Date?
    let medication: StoredMedication?

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.purple)
                .frame(width: 30, height: 30)
                .background(Color.purple.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 3) {
                Text(medication.map(userFacingMedicationName(for:)) ?? "未知药品")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(doseChangeText)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Text(doseChangeEffectivePeriodText(change: change, effectiveUntil: effectiveUntil))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                if !change.note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(change.note)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
    }

    private var doseChangeText: String {
        let newDose = "\(change.newDoseValue.formatted()) \(localizedMedicationUnit(change.newDoseUnit))"
        guard let previousDoseValue = change.previousDoseValue else {
            return "初始剂量 \(newDose)"
        }
        let previousDose = "\(previousDoseValue.formatted()) \(localizedMedicationUnit(change.previousDoseUnit))"
        return "\(previousDose) 调整为 \(newDose)"
    }
}

struct DayDoseTaskLine: View {
    let task: StoredDoseTask
    let medication: StoredMedication?

    private var tint: Color {
        switch task.status {
        case .taken, .corrected:
            return .green
        case .delayed:
            return .blue
        case .skipped:
            return .orange
        case .pending:
            return .secondary
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            MedicationPhotoView(
                photoData: medication?.photoData,
                symbolName: medication?.photoSymbolName ?? "pills.fill",
                tint: tint,
                size: 40
            )
            VStack(alignment: .leading, spacing: 3) {
                Text(medication.map(userFacingMedicationName(for:)) ?? "未知药品")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Text("\(AppFormatters.time.string(from: task.dueAt)) · \(task.doseValue.formatted()) \(localizedMedicationUnit(task.doseUnit))")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            StatusBadge(text: task.status.displayName, color: tint)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}

private func doseChangeEffectiveUntil(
    _ change: StoredMedicationDoseChange,
    in changes: [StoredMedicationDoseChange]
) -> Date? {
    let calendar = Calendar.current
    let currentStart = calendar.startOfDay(for: change.effectiveFrom)
    let nextChange = changes
        .filter {
            $0.id != change.id
                && $0.medicationID == change.medicationID
                && doseChangePlanMatches($0, change)
                && $0.effectiveFrom > change.effectiveFrom
        }
        .min { $0.effectiveFrom < $1.effectiveFrom }

    guard let nextStart = nextChange.map({ calendar.startOfDay(for: $0.effectiveFrom) }) else {
        return nil
    }
    guard nextStart > currentStart else {
        return currentStart
    }
    return calendar.date(byAdding: .day, value: -1, to: nextStart)
}

private func doseChangePlanMatches(_ first: StoredMedicationDoseChange, _ second: StoredMedicationDoseChange) -> Bool {
    guard let firstPlanID = first.planID, let secondPlanID = second.planID else {
        return true
    }
    return firstPlanID == secondPlanID
}

private func doseChangeEffectivePeriodText(change: StoredMedicationDoseChange, effectiveUntil: Date?) -> String {
    let startText = AppFormatters.day.string(from: change.effectiveFrom)
    guard let effectiveUntil else {
        return "生效阶段：\(startText) 至今"
    }
    if Calendar.current.isDate(effectiveUntil, inSameDayAs: change.effectiveFrom) {
        return "生效阶段：\(startText) 当天，之后有新的剂量记录"
    }
    return "生效阶段：\(startText) 至 \(AppFormatters.day.string(from: effectiveUntil))"
}

private func recordsTasksAreFuturePlanOnly(_ tasks: [StoredDoseTask], on date: Date, now: Date) -> Bool {
    let calendar = Calendar.current
    return calendar.startOfDay(for: date) > calendar.startOfDay(for: now)
        && !tasks.isEmpty
        && tasks.allSatisfy { task in
            (task.status == .pending || task.status == .delayed) && task.dueAt > now
        }
}
