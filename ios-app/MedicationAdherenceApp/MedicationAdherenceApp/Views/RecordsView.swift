import MedicationAdherenceCore
import SwiftData
import SwiftUI

struct RecordsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \StoredDoseTask.dueAt, order: .reverse) private var tasks: [StoredDoseTask]
    @Query(sort: \StoredMedication.displayName) private var medications: [StoredMedication]
    @Query(sort: \StoredMedicationDoseChange.effectiveFrom, order: .reverse) private var doseChanges: [StoredMedicationDoseChange]
    @State private var showingMonthCalendar = false
    @State private var selectedDate = Date()
    @State private var displayedMonth = Calendar.current.dateInterval(of: .month, for: Date())?.start ?? Date()
    @State private var selectedDateForDetail: DoseDateSelection?
    @State private var selectedTaskForCorrection: StoredDoseTask?

    private var insight: AdherenceInsight {
        AdherenceInsightBuilder().build(
            scheduledDoses: tasks.map(\.coreScheduledDose),
            events: tasks.compactMap(\.coreDoseEvent),
            timeZone: TimeZone.current
        )
    }

    var body: some View {
        List {
            Section("连续记录") {
                HStack {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("\(insight.currentStreakDays) 天")
                            .font(.largeTitle.weight(.bold))
                        Text("当前连续达标")
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 8) {
                        Text("\(Int(insight.completionRate * 100))%")
                            .font(.title.weight(.semibold))
                        Text("总体完成率")
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 8)

                Text(insight.message)
                    .font(.body)
            }

            Section("漏服与延后") {
                InfoRow(title: "已忽略", value: "\(insight.skippedCount) 次")
                InfoRow(title: "稍后提醒", value: "\(insight.delayedCount) 次")
                InfoRow(title: "最长连续达标", value: "\(insight.longestStreakDays) 天")
            }

            Section("记录日历") {
                DisclosureGroup(isExpanded: $showingMonthCalendar) {
                    MonthDoseCalendarView(
                        selectedDate: $selectedDate,
                        displayedMonth: $displayedMonth,
                        monthRange: monthBrowsingRange,
                        days: daysInDisplayedMonth(),
                        tasksForDay: tasks(on:),
                        doseChangesForDay: doseChanges(on:),
                        openDay: openDayDetail,
                        moveMonth: moveDisplayedMonth
                    )

                    DayDoseListView(
                        date: selectedDate,
                        tasks: tasks(on: selectedDate),
                        doseChanges: doseChanges(on: selectedDate),
                        allDoseChanges: doseChanges,
                        medication: medication(for:),
                        medicationForDoseChange: medication(for:),
                        openTask: { selectedTaskForCorrection = $0 }
                    )
                } label: {
                    WeekSummaryRow(
                        completedCount: weekTasks.filter { $0.status == .taken || $0.status == .corrected }.count,
                        totalCount: weekTasks.count,
                        skippedCount: weekTasks.filter { $0.status == .skipped }.count,
                        delayedCount: weekTasks.filter { $0.status == .delayed }.count
                    )
                }

                if !showingMonthCalendar {
                    WeekDoseCalendarView(
                        selectedDate: $selectedDate,
                        days: daysInCurrentWeek(),
                        tasksForDay: tasks(on:),
                        doseChangesForDay: doseChanges(on:),
                        openDay: openDayDetail
                    )
                }
            }

            Section("服药历史") {
                ForEach(tasks) { task in
                    Button {
                        selectedTaskForCorrection = task
                    } label: {
                        RecordHistoryRow(
                            task: task,
                            medication: medication(for: task)
                        )
                    }
                    .buttonStyle(.plain)
                    .padding(.vertical, 6)
                }
            }
        }
        .navigationTitle("记录")
        .onChange(of: selectedDate) { _, newValue in
            syncDisplayedMonth(to: newValue)
        }
        .sheet(item: $selectedTaskForCorrection) { task in
            DoseRecordCorrectionView(
                task: task,
                medication: medication(for: task)
            )
        }
        .sheet(item: $selectedDateForDetail) { selection in
            DayDoseDetailSheet(
                date: selection.date,
                tasks: tasks(on: selection.date),
                doseChanges: doseChanges(on: selection.date),
                allDoseChanges: doseChanges,
                medication: medication(for:),
                medicationForDoseChange: medication(for:),
                openTask: { task in
                    selectedDateForDetail = nil
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                        selectedTaskForCorrection = task
                    }
                }
            )
        }
    }

    private func medication(for task: StoredDoseTask) -> StoredMedication? {
        medications.first { $0.id == task.medicationID }
    }

    private func medication(for change: StoredMedicationDoseChange) -> StoredMedication? {
        medications.first { $0.id == change.medicationID }
    }

    private var weekTasks: [StoredDoseTask] {
        let calendar = Calendar.current
        guard let interval = calendar.dateInterval(of: .weekOfYear, for: Date()) else {
            return []
        }
        return tasks.filter { interval.contains($0.dueAt) }
    }

    private func daysInCurrentWeek() -> [Date] {
        let calendar = Calendar.current
        let weekAnchor = calendar.dateInterval(of: .weekOfYear, for: selectedDate)?.start ?? Date()
        return (0..<7).compactMap { offset in
            calendar.date(byAdding: .day, value: offset, to: weekAnchor)
        }
    }

    private func daysInCurrentMonth() -> [Date] {
        daysInMonth(containing: selectedDate)
    }

    private func daysInDisplayedMonth() -> [Date] {
        daysInMonth(containing: displayedMonth)
    }

    private func daysInMonth(containing date: Date) -> [Date] {
        let calendar = Calendar.current
        let monthAnchor = calendar.dateInterval(of: .month, for: date)?.start ?? Date()
        guard let range = calendar.range(of: .day, in: .month, for: monthAnchor) else {
            return []
        }
        return range.compactMap { day in
            calendar.date(byAdding: .day, value: day - 1, to: monthAnchor)
        }
    }

    private func tasks(on date: Date) -> [StoredDoseTask] {
        tasks
            .filter { Calendar.current.isDate($0.dueAt, inSameDayAs: date) }
            .sorted { $0.dueAt < $1.dueAt }
    }

    private func doseChanges(on date: Date) -> [StoredMedicationDoseChange] {
        doseChanges
            .filter { Calendar.current.isDate($0.effectiveFrom, inSameDayAs: date) }
            .sorted { $0.effectiveFrom < $1.effectiveFrom }
    }

    private func openDayDetail(_ date: Date) {
        selectedDate = date
        selectedDateForDetail = DoseDateSelection(date: date)
    }

    private var monthBrowsingRange: ClosedRange<Date> {
        let calendar = Calendar.current
        let currentMonth = calendar.dateInterval(of: .month, for: Date())?.start ?? Date()
        let earliestMonth = calendar.date(byAdding: .month, value: -23, to: currentMonth) ?? currentMonth
        return earliestMonth...currentMonth
    }

    private func moveDisplayedMonth(by offset: Int) {
        let calendar = Calendar.current
        guard let nextMonth = calendar.date(byAdding: .month, value: offset, to: displayedMonth) else {
            return
        }
        let clampedMonth = clampedMonth(nextMonth)
        displayedMonth = clampedMonth
        if !calendar.isDate(selectedDate, equalTo: clampedMonth, toGranularity: .month) {
            selectedDate = nearestSelectableDay(in: clampedMonth)
        }
    }

    private func syncDisplayedMonth(to date: Date) {
        let calendar = Calendar.current
        let month = calendar.dateInterval(of: .month, for: date)?.start ?? date
        let clamped = clampedMonth(month)
        if !calendar.isDate(displayedMonth, equalTo: clamped, toGranularity: .month) {
            displayedMonth = clamped
        }
    }

    private func clampedMonth(_ date: Date) -> Date {
        let calendar = Calendar.current
        let month = calendar.dateInterval(of: .month, for: date)?.start ?? date
        return min(max(month, monthBrowsingRange.lowerBound), monthBrowsingRange.upperBound)
    }

    private func nearestSelectableDay(in month: Date) -> Date {
        let calendar = Calendar.current
        if calendar.isDate(month, equalTo: Date(), toGranularity: .month) {
            return Date()
        }
        return month
    }
}

private struct DoseDateSelection: Identifiable {
    let id: String
    let date: Date

    init(date: Date) {
        self.date = date
        id = AppFormatters.day.string(from: date)
    }
}

private struct RecordHistoryRow: View {
    let task: StoredDoseTask
    let medication: StoredMedication?

    private var tint: Color {
        task.status == .taken || task.status == .corrected ? .green : .orange
    }

    var body: some View {
        HStack(spacing: 12) {
            MedicationPhotoView(
                photoData: medication?.photoData,
                symbolName: medication?.photoSymbolName ?? "pills.fill",
                tint: tint
            )
            VStack(alignment: .leading, spacing: 4) {
                Text(medication?.displayName ?? "未知药品")
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text("\(AppFormatters.day.string(from: task.dueAt)) · \(AppFormatters.time.string(from: task.dueAt))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if !task.reason.isEmpty {
                    Text(task.reason)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
            StatusBadge(text: task.status.displayName, color: tint)
        }
        .contentShape(Rectangle())
    }
}

private struct DoseRecordCorrectionView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    let task: StoredDoseTask
    let medication: StoredMedication?
    @State private var status: StoredDoseStatus
    @State private var dueAt: Date
    @State private var note: String

    init(task: StoredDoseTask, medication: StoredMedication?) {
        self.task = task
        self.medication = medication
        _status = State(initialValue: task.status)
        _dueAt = State(initialValue: task.dueAt)
        _note = State(initialValue: task.reason)
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
                            Text(medication?.displayName ?? "未知药品")
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
                    DatePicker("记录时间", selection: $dueAt)
                }

                Section("备注") {
                    TextEditor(text: $note)
                        .frame(minHeight: 96)
                    Text("修正只用于记录真实服药情况，不会给出处方、剂量或停药建议。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
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
                        save()
                    }
                }
            }
        }
    }

    private func save() {
        let occurredAt = Date()
        let previousStatus = task.status
        let previousDueAt = task.dueAt
        let previousRecordedAt = task.recordedAt
        let previousReason = task.reason

        task.status = status
        task.dueAt = dueAt
        task.recordedAt = status == .pending ? nil : dueAt
        task.reason = note.trimmingCharacters(in: .whitespacesAndNewlines)
        modelContext.insert(StoredDoseActionLog(
            taskID: task.id,
            action: .correct,
            previousStatus: previousStatus,
            previousDueAt: previousDueAt,
            previousRecordedAt: previousRecordedAt,
            previousReason: previousReason,
            newStatus: status,
            occurredAt: occurredAt,
            undoExpiresAt: occurredAt.addingTimeInterval(10 * 60),
            note: task.reason
        ))
        try? modelContext.save()
        dismiss()
    }
}

private struct WeekSummaryRow: View {
    let completedCount: Int
    let totalCount: Int
    let skippedCount: Int
    let delayedCount: Int

    var body: some View {
        HStack(spacing: 14) {
            MedicationSymbolView(symbolName: "calendar", tint: .green)
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
        }
        .padding(.vertical, 6)
    }
}

private struct WeekDoseCalendarView: View {
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
            Text("点击日期查看当天服药详情。")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 8)
    }
}

private struct MonthDoseCalendarView: View {
    @Binding var selectedDate: Date
    @Binding var displayedMonth: Date
    let monthRange: ClosedRange<Date>
    let days: [Date]
    let tasksForDay: (Date) -> [StoredDoseTask]
    let doseChangesForDay: (Date) -> [StoredMedicationDoseChange]
    let openDay: (Date) -> Void
    let moveMonth: (Int) -> Void

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 7)

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Button {
                    moveMonth(-1)
                } label: {
                    Image(systemName: "chevron.left")
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
                .disabled(!canMoveBackward)

                Text(monthTitle)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Spacer()
                Button {
                    moveMonth(1)
                } label: {
                    Image(systemName: "chevron.right")
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
                .disabled(!canMoveForward)
            }
            .foregroundStyle(.blue)

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
                            action: {
                                selectedDate = day
                                openDay(day)
                            }
                        )
                    } else {
                        Color.clear
                            .frame(maxWidth: .infinity, minHeight: 48)
                    }
                }
            }
            Text("可查看近 24 个月记录，点按日期查看当天服药详情。")
                .font(.footnote)
                .foregroundStyle(.secondary)
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
        .animation(.snappy(duration: 0.22, extraBounce: 0.01), value: displayedMonth)
    }

    private var monthTitle: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_Hans_CN")
        formatter.dateFormat = "yyyy年M月"
        return formatter.string(from: displayedMonth)
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
}

private struct DoseCalendarDayButton: View {
    let day: Date
    let tasks: [StoredDoseTask]
    let doseChangeCount: Int
    let isSelected: Bool
    let showsWeekday: Bool
    let action: () -> Void

    private var completedCount: Int {
        tasks.filter { $0.status == .taken || $0.status == .corrected }.count
    }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 5) {
                if showsWeekday {
                    Text(weekdayText)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                Text("\(Calendar.current.component(.day, from: day))")
                    .font(.subheadline.weight(.semibold))
                HStack(spacing: 3) {
                    Circle()
                        .fill(indicatorColor)
                        .frame(width: 6, height: 6)
                    if doseChangeCount > 0 {
                        Circle()
                            .fill(Color.purple)
                            .frame(width: 6, height: 6)
                    }
                    if !tasks.isEmpty {
                        Text("\(completedCount)/\(tasks.count)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity, minHeight: showsWeekday ? 58 : 48)
            .background(
                isSelected ? Color.blue.opacity(0.14) : Color(.secondarySystemGroupedBackground),
                in: RoundedRectangle(cornerRadius: 8)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.blue.opacity(0.45) : Color.clear, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        let taskText = tasks.isEmpty ? "没有用药任务" : "\(completedCount) / \(tasks.count) 项已完成"
        let doseChangeText = doseChangeCount > 0 ? "，\(doseChangeCount) 条剂量变化" : ""
        return "\(AppFormatters.day.string(from: day))，\(taskText)\(doseChangeText)"
    }

    private var weekdayText: String {
        let symbols = ["日", "一", "二", "三", "四", "五", "六"]
        let index = Calendar.current.component(.weekday, from: day) - 1
        return symbols[max(0, min(index, symbols.count - 1))]
    }

    private var indicatorColor: Color {
        guard !tasks.isEmpty else {
            return .clear
        }
        if tasks.contains(where: { $0.status == .skipped }) {
            return .orange
        }
        if tasks.allSatisfy({ $0.status == .taken || $0.status == .corrected }) {
            return .green
        }
        return .blue
    }
}

private struct DayDoseListView: View {
    let date: Date
    let tasks: [StoredDoseTask]
    let doseChanges: [StoredMedicationDoseChange]
    let allDoseChanges: [StoredMedicationDoseChange]
    let medication: (StoredDoseTask) -> StoredMedication?
    let medicationForDoseChange: (StoredMedicationDoseChange) -> StoredMedication?
    let openTask: (StoredDoseTask) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(AppFormatters.day.string(from: date))
                .font(.headline)

            if tasks.isEmpty {
                Text("这一天没有用药任务。")
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
}

private struct DayDoseDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    let date: Date
    let tasks: [StoredDoseTask]
    let doseChanges: [StoredMedicationDoseChange]
    let allDoseChanges: [StoredMedicationDoseChange]
    let medication: (StoredDoseTask) -> StoredMedication?
    let medicationForDoseChange: (StoredMedicationDoseChange) -> StoredMedication?
    let openTask: (StoredDoseTask) -> Void

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(AppFormatters.day.string(from: date))
                        .font(.title3.weight(.semibold))
                    Text(daySummaryText)
                        .foregroundStyle(.secondary)
                }

                Section("当天服药详情") {
                    if tasks.isEmpty {
                        Text("这一天没有用药任务。")
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
                }

                if !doseChanges.isEmpty {
                    Section("剂量变化") {
                        ForEach(doseChanges) { change in
                            DoseChangeLine(
                                change: change,
                                effectiveUntil: doseChangeEffectiveUntil(change, in: allDoseChanges),
                                medication: medicationForDoseChange(change)
                            )
                        }
                        Text("此处记录从当天开始生效的剂量变化，便于回看用药方案调整时间段；不代表诊断、处方、剂量建议或疗效判断。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("日期详情")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") {
                        dismiss()
                    }
                }
            }
        }
    }

    private var daySummaryText: String {
        var parts: [String] = []
        parts.append(tasks.isEmpty ? "这一天没有用药任务。" : "\(tasks.count) 项用药记录，可点开修正。")
        if !doseChanges.isEmpty {
            parts.append("\(doseChanges.count) 条剂量变化。")
        }
        return parts.joined(separator: " ")
    }
}

private struct DoseChangeLine: View {
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
                Text(medication?.displayName ?? "未知药品")
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

private struct DayDoseTaskLine: View {
    let task: StoredDoseTask
    let medication: StoredMedication?

    private var tint: Color {
        task.status == .taken || task.status == .corrected ? .green : .orange
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
                Text(medication?.displayName ?? "未知药品")
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
