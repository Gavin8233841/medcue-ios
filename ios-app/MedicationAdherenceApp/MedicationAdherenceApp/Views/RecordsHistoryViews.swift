import MedicationAdherenceCore
import SwiftData
import SwiftUI

struct RecordsOverviewDetailPage: View {
    let insight: AdherenceInsight
    let historyCount: Int
    let upcomingCount: Int
    let recentDays: [RecordsAdherenceDay]

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 14) {
                RecordsInsightCard(
                    insight: insight,
                    historyCount: historyCount,
                    upcomingCount: upcomingCount,
                    recentDays: recentDays,
                    tint: RecordsModulePalette.overview
                )
                RecordsOverviewCompletionMixCard(
                    insight: insight,
                    tint: RecordsModulePalette.overview
                )
                RecordsOverviewContinuityCard(
                    insight: insight,
                    historyCount: historyCount,
                    upcomingCount: upcomingCount,
                    tint: RecordsModulePalette.overview
                )
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 28)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("记录概览")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
    }
}

struct RecordsCalendarDetailPage: View {
    @Binding var selectedDate: Date
    @Binding var displayedMonth: Date
    let monthRange: ClosedRange<Date>
    let days: [Date]
    let snapshot: RecordsViewSnapshot
    let doseChanges: [StoredMedicationDoseChange]
    let transitionDirection: Int
    let moveMonth: (Int) -> Void
    let openDay: (Date) -> Void
    let openTask: (StoredDoseTask) -> Void

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 14) {
                RecordsPanelContainer(
                    title: "月历记录",
                    subtitle: "左右切换月份，点日期查看当天详情",
                    tint: RecordsModulePalette.calendar
                ) {
                    MonthDoseCalendarView(
                        selectedDate: $selectedDate,
                        displayedMonth: $displayedMonth,
                        monthRange: monthRange,
                        days: days,
                        tasksForDay: snapshot.tasks(on:),
                        doseChangesForDay: snapshot.doseChanges(on:),
                        openDay: openDay,
                        transitionDirection: transitionDirection,
                        moveMonth: moveMonth,
                        tint: RecordsModulePalette.calendar
                    )
                }

                RecordsPanelContainer(title: AppFormatters.day.string(from: selectedDate), tint: RecordsModulePalette.calendar) {
                    DayDoseListView(
                        date: selectedDate,
                        tasks: snapshot.tasks(on: selectedDate),
                        doseChanges: snapshot.doseChanges(on: selectedDate),
                        allDoseChanges: doseChanges,
                        medication: snapshot.medication(for:),
                        medicationForDoseChange: snapshot.medication(for:),
                        openTask: openTask
                    )
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 28)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("记录日历")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
    }
}

struct RecordsHistoryDetailPage: View {
    let historyTasks: [StoredDoseTask]
    let historyGroups: [HistoryTaskGroup]
    @Binding var expandedHistoryGroupIDs: Set<String>
    let medication: (StoredDoseTask) -> StoredMedication?
    let openTask: (StoredDoseTask) -> Void

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 14) {
                RecordsPanelContainer(
                    title: "服药记录",
                    subtitle: "\(historyTasks.count) 条过去记录",
                    tint: RecordsModulePalette.history
                ) {
                    if historyGroups.isEmpty {
                        RecordsEmptyStateLine(
                            systemImage: "clock.arrow.circlepath",
                            title: "还没有过去的服药记录",
                            message: "完成或修正服药后，会在这里形成可复核的历史。"
                        )
                    } else {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(historyGroups.enumerated()), id: \.element.id) { index, group in
                                HistoryTaskGroupView(
                                    group: group,
                                    medication: medication(group.primaryTask),
                                    isExpanded: expandedHistoryGroupIDs.contains(group.id),
                                    openTask: openTask,
                                    toggleExpanded: {
                                        withAnimation(.snappy(duration: 0.26, extraBounce: 0.015)) {
                                            toggleHistoryGroup(group.id)
                                        }
                                    }
                                )
                                .padding(.vertical, 8)

                                if index < historyGroups.count - 1 {
                                    Divider()
                                        .opacity(0.42)
                                        .padding(.leading, 76)
                                }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 28)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("服药记录")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
    }

    private func toggleHistoryGroup(_ id: String) {
        if expandedHistoryGroupIDs.contains(id) {
            expandedHistoryGroupIDs.remove(id)
        } else {
            expandedHistoryGroupIDs.insert(id)
        }
    }
}

struct RecordsInsightCard: View {
    let insight: AdherenceInsight
    let historyCount: Int
    let upcomingCount: Int
    let recentDays: [RecordsAdherenceDay]
    let tint: Color

    private var completionPercent: Int {
        Int((insight.completionRate * 100).rounded())
    }

    private var streakDisplay: AdherenceStreakDisplay {
        AdherenceStreakDisplay(insight: insight)
    }

    private var accentColor: Color {
        tint
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(accentColor.opacity(0.12))
                    Image(systemName: "calendar.badge.checkmark")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(accentColor)
                }
                .frame(width: 48, height: 48)

                VStack(alignment: .leading, spacing: 4) {
                    Text("服药记录概览")
                        .font(.title3.weight(.semibold))
                    Text(insight.message)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
            }

            HStack(spacing: 0) {
                RecordsMetricPill(title: streakDisplay.title, value: streakDisplay.value, tint: .green)
                RecordsMetricDivider()
                RecordsMetricPill(title: "完成率", value: "\(completionPercent)%", tint: accentColor)
                RecordsMetricDivider()
                RecordsMetricPill(title: "历史记录", value: "\(historyCount)", tint: accentColor)
            }

            RecordsMiniHeatmap(days: recentDays)

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    RecordsExceptionChip(title: "忽略", value: insight.skippedCount, isEmphasized: insight.skippedCount > 0)
                    RecordsExceptionChip(title: "稍后", value: insight.delayedCount)
                }

                if upcomingCount > 0 {
                    RecordsPlanFoldNote(count: upcomingCount)
                }
            }
        }
        .padding(16)
        .medicationGlassSurface(cornerRadius: 16, tint: accentColor, fallbackMaterial: .thinMaterial)
        .shadow(color: Color.black.opacity(0.035), radius: 10, x: 0, y: 4)
    }
}

struct RecordsOverviewCompletionMixCard: View {
    let insight: AdherenceInsight
    let tint: Color

    private var pendingCount: Int {
        max(0, insight.scheduledCount - insight.takenCount - insight.skippedCount - insight.delayedCount)
    }

    private var segments: [RecordsOverviewMixSegment] {
        [
            RecordsOverviewMixSegment(title: "已完成", count: insight.takenCount, color: tint),
            RecordsOverviewMixSegment(title: "忽略", count: insight.skippedCount, color: .orange),
            RecordsOverviewMixSegment(title: "稍后", count: insight.delayedCount, color: .blue),
            RecordsOverviewMixSegment(title: "待补记", count: pendingCount, color: .secondary)
        ]
    }

    private var visibleSegments: [RecordsOverviewMixSegment] {
        segments.filter { $0.count > 0 }
    }

    private var totalCount: Int {
        max(1, segments.reduce(0) { $0 + $1.count })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("处理构成", systemImage: "chart.bar.xaxis")
                    .font(.headline)
                Spacer()
                Text("\(insight.scheduledCount) 项")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(tint)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 6)
                    .background(tint.opacity(0.10), in: Capsule())
            }

            GeometryReader { proxy in
                let displayedSegments = visibleSegments.isEmpty ? [RecordsOverviewMixSegment(title: "暂无", count: 1, color: .secondary)] : visibleSegments
                let spacingWidth = CGFloat(max(0, displayedSegments.count - 1)) * 4
                let availableWidth = max(0, proxy.size.width - spacingWidth)
                HStack(spacing: 4) {
                    ForEach(displayedSegments) { segment in
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(segment.color.opacity(segment.title == "暂无" ? 0.18 : 0.68))
                            .frame(width: max(8, availableWidth * CGFloat(segment.count) / CGFloat(totalCount)))
                    }
                }
            }
            .frame(height: 10)
            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))

            HStack(spacing: 8) {
                ForEach(segments) { segment in
                    RecordsOverviewSmallStat(title: segment.title, value: "\(segment.count)", tint: segment.color)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .medicationGlassSurface(cornerRadius: 16, tint: tint, fallbackMaterial: .thinMaterial)
        .shadow(color: Color.black.opacity(0.03), radius: 9, x: 0, y: 4)
    }
}

struct RecordsOverviewContinuityCard: View {
    let insight: AdherenceInsight
    let historyCount: Int
    let upcomingCount: Int
    let tint: Color

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 2)

    private var completionPercent: String {
        "\(Int((insight.completionRate * 100).rounded()))%"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("记录稳定性", systemImage: "waveform.path.ecg")
                .font(.headline)

            LazyVGrid(columns: columns, spacing: 10) {
                RecordsOverviewStatTile(title: "当前连续", value: "\(insight.currentStreakDays) 天", tint: .green)
                RecordsOverviewStatTile(title: "最长连续", value: "\(insight.longestStreakDays) 天", tint: tint)
                RecordsOverviewStatTile(title: "完成率", value: completionPercent, tint: tint)
                RecordsOverviewStatTile(title: "未来计划", value: "\(upcomingCount) 条", tint: .secondary)
            }

            HStack(spacing: 8) {
                Image(systemName: "doc.text.magnifyingglass")
                    .font(.caption.weight(.semibold))
                Text("\(historyCount) 条历史记录可用于复诊回顾")
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 11)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.secondary.opacity(0.055), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .medicationGlassSurface(cornerRadius: 16, tint: tint, fallbackMaterial: .thinMaterial)
        .shadow(color: Color.black.opacity(0.03), radius: 9, x: 0, y: 4)
    }
}

struct RecordsOverviewMixSegment: Identifiable {
    let title: String
    let count: Int
    let color: Color

    var id: String {
        title
    }
}

struct RecordsOverviewSmallStat: View {
    let title: String
    let value: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(.caption.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(tint)
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

struct RecordsOverviewStatTile: View {
    let title: String
    let value: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(value)
                .font(.system(.headline, design: .rounded).weight(.bold))
                .monospacedDigit()
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

struct RecordsMetricPill: View {
    let title: String
    let value: String
    var tint: Color = .primary

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(value)
                .font(.system(.title3, design: .rounded).weight(.bold))
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .contentTransition(.numericText())
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, minHeight: 54, alignment: .leading)
    }
}

struct RecordsMetricDivider: View {
    var body: some View {
        Rectangle()
            .fill(.separator.opacity(0.45))
            .frame(width: 1, height: 34)
            .padding(.horizontal, 12)
    }
}

struct RecordsExceptionChip: View {
    let title: String
    let value: Int
    var isEmphasized = false

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(isEmphasized ? Color.orange : Color.secondary.opacity(0.55))
                .frame(width: 7, height: 7)
            Text(title)
                .font(.caption.weight(.semibold))
            Text("\(value)")
                .font(.caption.monospacedDigit().weight(.semibold))
                .foregroundStyle(isEmphasized ? .orange : .secondary)
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background((isEmphasized ? Color.orange.opacity(0.09) : Color.secondary.opacity(0.08)), in: Capsule())
    }
}

struct RecordsPlanFoldNote: View {
    let count: Int

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "calendar.badge.clock")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text("未来计划 \(count) 条")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.secondary.opacity(0.055), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
    }
}

struct RecordsMiniHeatmap: View {
    let days: [RecordsAdherenceDay]

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 14)

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("近 28 天记录")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                HStack(spacing: 5) {
                    heatmapLegendDot(.secondary.opacity(0.18))
                    heatmapLegendDot(.secondary.opacity(0.34))
                    heatmapLegendDot(.secondary.opacity(0.68))
                }
                .accessibilityHidden(true)
            }

            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(days) { day in
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(color(for: day))
                        .frame(height: 12)
                        .accessibilityLabel("\(AppFormatters.day.string(from: day.date))，\(day.total == 0 ? "没有记录" : "\(day.completed) / \(day.total) 项已完成")")
                }
            }
        }
        .padding(12)
        .background(.secondary.opacity(0.055), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func heatmapLegendDot(_ color: Color) -> some View {
        RoundedRectangle(cornerRadius: 2, style: .continuous)
            .fill(color)
            .frame(width: 12, height: 12)
    }

    private func color(for day: RecordsAdherenceDay) -> Color {
        guard day.total > 0 else {
            return .secondary.opacity(0.16)
        }
        if day.skipped > 0 {
            return .orange.opacity(0.78)
        }
        switch day.completionRate {
        case 0.95...:
            return .green.opacity(0.76)
        case 0.65..<0.95:
            return .blue.opacity(0.58)
        default:
            return .red.opacity(0.36)
        }
    }
}

struct HistorySummaryRow: View {
    let count: Int
    let visibleCount: Int
    let visibleGroupCount: Int
    let latestTask: StoredDoseTask?
    let medication: (StoredDoseTask?) -> StoredMedication?

    var body: some View {
        HStack(spacing: 12) {
            MedicationSymbolView(symbolName: "clock.arrow.circlepath", tint: .secondary)
                .frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 4) {
                Text("\(count) 条过去记录")
                    .font(.headline)
                Text(latestSummary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Text(visibleSummaryText)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 9)
                .padding(.vertical, 6)
                .background(.secondary.opacity(0.09), in: Capsule())
        }
        .padding(.vertical, 4)
    }

    private var visibleSummaryText: String {
        visibleGroupCount == visibleCount ? "显示 \(visibleCount)" : "\(visibleCount) 条 · \(visibleGroupCount) 组"
    }

    private var latestSummary: String {
        guard let latestTask else {
            return "暂无记录"
        }
        let name = medication(latestTask).map(userFacingMedicationName(for:)) ?? "用药记录"
        return "\(AppFormatters.day.string(from: latestTask.effectiveAdherenceDate)) · \(name)"
    }
}

struct RecordHistoryRow: View {
    let task: StoredDoseTask
    let medication: StoredMedication?

    private var tint: Color {
        switch task.status {
        case .taken, .corrected:
            return .green
        case .skipped:
            return .orange
        case .delayed:
            return .blue
        case .pending:
            return .secondary
        }
    }

    private var statusBadgeColor: Color {
        tint
    }

    var body: some View {
        HStack(spacing: 12) {
            MedicationPhotoView(
                photoData: medication?.photoData,
                symbolName: medication?.photoSymbolName ?? "pills.fill",
                tint: tint
            )
            VStack(alignment: .leading, spacing: 4) {
                Text(medication.map(userFacingMedicationName(for:)) ?? "未知药品")
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text("\(timePrefix)：\(AppFormatters.day.string(from: displayDate)) · \(AppFormatters.time.string(from: displayDate))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if let displayReason = task.recordDisplayReason {
                    Text(displayReason)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
            StatusBadge(text: task.status.displayName, color: statusBadgeColor)
        }
        .contentShape(Rectangle())
    }

    private var displayDate: Date {
        task.effectiveAdherenceDate
    }

    private var timePrefix: String {
        if task.status == .pending {
            return "待补记"
        }
        if task.status == .delayed {
            return "稍后"
        }
        return task.effectiveAdherenceRecordedAt == nil ? "计划" : "记录"
    }
}

struct HistoryTaskGroupView: View {
    let group: HistoryTaskGroup
    let medication: StoredMedication?
    let isExpanded: Bool
    let openTask: (StoredDoseTask) -> Void
    let toggleExpanded: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Button {
                if group.isGrouped {
                    toggleExpanded()
                } else {
                    openTask(group.primaryTask)
                }
            } label: {
                if group.isGrouped {
                    GroupedRecordHistoryRow(
                        group: group,
                        medication: medication,
                        isExpanded: isExpanded
                    )
                } else {
                    RecordHistoryRow(
                        task: group.primaryTask,
                        medication: medication
                    )
                }
            }
            .buttonStyle(.plain)

            if group.isGrouped && isExpanded {
                VStack(spacing: 0) {
                    ForEach(Array(group.tasks.enumerated()), id: \.element.id) { index, task in
                        Button {
                            openTask(task)
                        } label: {
                            GroupedRecordChildRow(
                                task: task,
                                sequenceNumber: index + 1,
                                totalCount: group.tasks.count
                            )
                        }
                        .buttonStyle(.plain)
                        .padding(.vertical, 8)

                        if index < group.tasks.count - 1 {
                            Divider()
                                .opacity(0.34)
                                .padding(.leading, 28)
                        }
                    }
                }
                .padding(.leading, 54)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
}

struct GroupedRecordHistoryRow: View {
    let group: HistoryTaskGroup
    let medication: StoredMedication?
    let isExpanded: Bool

    private var task: StoredDoseTask {
        group.primaryTask
    }

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
        HStack(spacing: 12) {
            MedicationPhotoView(
                photoData: medication?.photoData,
                symbolName: medication?.photoSymbolName ?? "pills.fill",
                tint: tint
            )
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(medication.map(userFacingMedicationName(for:)) ?? "未知药品")
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text("合并 \(group.tasks.count) 条")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(tint)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(tint.opacity(0.10), in: Capsule())
                }

                Text(timeRangeText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                if let displayReason = task.recordDisplayReason {
                    Text(displayReason)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 7) {
                StatusBadge(text: task.status.displayName, color: tint)
                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .contentShape(Rectangle())
    }

    private var timeRangeText: String {
        guard let latest = group.tasks.first, let earliest = group.tasks.last else {
            return "记录时间待核对"
        }
        let latestDate = latest.effectiveAdherenceDate
        let earliestDate = earliest.effectiveAdherenceDate
        let dayText = AppFormatters.day.string(from: latestDate)
        let earliestTime = AppFormatters.time.string(from: earliestDate)
        let latestTime = AppFormatters.time.string(from: latestDate)
        if earliestTime == latestTime {
            return "\(dayText) · \(latestTime) 同一时段"
        }
        return "\(dayText) · \(earliestTime)-\(latestTime)"
    }
}

struct GroupedRecordChildRow: View {
    let task: StoredDoseTask
    let sequenceNumber: Int
    let totalCount: Int

    private var displayDate: Date {
        task.effectiveAdherenceDate
    }

    var body: some View {
        HStack(spacing: 10) {
            Capsule()
                .fill(statusAccentColor)
                .frame(width: 3, height: 22)
                .opacity(statusAccentOpacity)
            Text(AppFormatters.time.string(from: displayDate))
                .font(.subheadline.monospacedDigit().weight(.semibold))
                .foregroundStyle(.primary.opacity(0.82))
            VStack(alignment: .leading, spacing: 2) {
                Text(task.status.displayName)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(detailText)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
    }

    private var detailText: String {
        "第 \(sequenceNumber)/\(totalCount) 条 · \(task.doseValue.formatted()) \(localizedMedicationUnit(task.doseUnit))"
    }

    private var statusAccentColor: Color {
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

    private var statusAccentOpacity: Double {
        task.status == .pending ? 0.46 : 0.66
    }
}

