import MedicationAdherenceCore
import SwiftData
import SwiftUI

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
