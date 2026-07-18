import SwiftUI
import WidgetKit

struct MedicationWatchComplicationEntry: TimelineEntry {
    let date: Date
    let snapshot: MedicationWatchSnapshot
}

struct MedicationWatchComplicationProvider: TimelineProvider {
    func placeholder(in context: Context) -> MedicationWatchComplicationEntry {
        MedicationWatchComplicationEntry(date: Date(), snapshot: .preview)
    }

    func getSnapshot(in context: Context, completion: @escaping (MedicationWatchComplicationEntry) -> Void) {
        completion(MedicationWatchComplicationEntry(date: Date(), snapshot: MedicationWatchSnapshotStore.load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<MedicationWatchComplicationEntry>) -> Void) {
        let snapshot = MedicationWatchSnapshotStore.load()
        let now = Date()
        let entry = MedicationWatchComplicationEntry(date: now, snapshot: snapshot)
        let refreshDate = MedicationWatchComplicationTimelinePolicy.nextRefreshDate(for: snapshot, now: now)
        completion(Timeline(entries: [entry], policy: .after(refreshDate)))
    }
}

struct MedicationAdherenceWatchComplication: Widget {
    let kind = "MedicationAdherenceWatchComplication"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: MedicationWatchComplicationProvider()) { entry in
            MedicationWatchComplicationView(entry: entry)
                .containerBackground(.background, for: .widget)
                .accessibilityLabel(MedicationWatchComplicationStatus(snapshot: entry.snapshot, now: entry.date).accessibilityText)
        }
        .configurationDisplayName("今日用药")
        .description("查看下一次服药时间和今日待处理数量。")
        .supportedFamilies(Self.supportedFamilies)
    }

    private static var supportedFamilies: [WidgetFamily] {
        #if os(watchOS)
        return [
            .accessoryCircular,
            .accessoryRectangular,
            .accessoryInline,
            .accessoryCorner
        ]
        #else
        return [
            .accessoryCircular,
            .accessoryRectangular,
            .accessoryInline
        ]
        #endif
    }
}

private struct MedicationWatchComplicationView: View {
    let entry: MedicationWatchComplicationEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .accessoryInline:
            inlineView
        case .accessoryCircular:
            circularView
        #if os(watchOS)
        case .accessoryCorner:
            cornerView
        #endif
        default:
            rectangularView
        }
    }

    private var inlineView: some View {
        Text(inlineText)
    }

    private var circularView: some View {
        ZStack {
            AccessoryWidgetBackground()
            Circle()
                .trim(from: 0, to: complicationProgress)
                .stroke(complicationStatus.tint.color, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .padding(2)
            VStack(spacing: 1) {
                Image(systemName: complicationStatus.symbolName)
                    .font(.caption2)
                    .foregroundStyle(complicationStatus.tint.color)
                Text(complicationStatus.primaryText)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
    }

    private var cornerView: some View {
        VStack(spacing: 0) {
            Image(systemName: complicationStatus.symbolName)
                .foregroundStyle(complicationStatus.tint.color)
            Text(complicationStatus.primaryText)
                .monospacedDigit()
                .minimumScaleFactor(0.7)
        }
        .widgetLabel {
            Text(inlineText)
        }
    }

    private var rectangularView: some View {
        HStack(spacing: 8) {
            Image(systemName: complicationStatus.symbolName)
                .font(.headline)
                .foregroundStyle(complicationStatus.tint.color)
            VStack(alignment: .leading, spacing: 2) {
                Text(complicationStatus.primaryText)
                    .font(.headline)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Text(rectangularDetailText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    private var inlineText: String {
        complicationStatus.inlineText
    }

    private var rectangularDetailText: String {
        complicationStatus.detailText
    }

    private var complicationProgress: Double {
        entry.snapshot.displayCompletionProgress(now: entry.date)
    }

    private var complicationStatus: MedicationWatchComplicationStatus {
        MedicationWatchComplicationStatus(snapshot: entry.snapshot, now: entry.date)
    }
}

private extension MedicationWatchComplicationTint {
    var color: Color {
        switch self {
        case .blue:
            .blue
        case .orange:
            .orange
        case .purple:
            .purple
        case .green:
            .green
        }
    }
}

#if DEBUG
private enum MedicationWatchComplicationPreviewData {
    static let now = Date(timeIntervalSinceReferenceDate: 805_550_400)

    static let firstSync = entry(snapshot: .empty)
    static let stale = entry(
        snapshot: MedicationWatchSnapshot(
            generatedAt: Calendar.current.date(byAdding: .day, value: -1, to: now) ?? now.addingTimeInterval(-86_400),
            items: [item(dueOffset: -600)],
            privacyMode: false
        )
    )
    static let empty = entry(
        snapshot: MedicationWatchSnapshot(generatedAt: now, items: [], privacyMode: false)
    )
    static let completed = entry(
        snapshot: MedicationWatchSnapshot(
            generatedAt: now,
            items: [item(dueOffset: -3_600, status: .taken)],
            privacyMode: false
        )
    )
    static let upcoming = entry(snapshot: snapshot(dueOffset: 7_200))
    static let dueSoon = entry(snapshot: snapshot(dueOffset: 1_200))
    static let overdue = entry(snapshot: snapshot(dueOffset: -600))
    static let privacy = entry(snapshot: snapshot(dueOffset: 7_200, privacyMode: true))

    private static func entry(snapshot: MedicationWatchSnapshot) -> MedicationWatchComplicationEntry {
        MedicationWatchComplicationEntry(date: now, snapshot: snapshot)
    }

    private static func snapshot(dueOffset: TimeInterval, privacyMode: Bool = false) -> MedicationWatchSnapshot {
        MedicationWatchSnapshot(
            generatedAt: now,
            items: [item(dueOffset: dueOffset)],
            privacyMode: privacyMode
        )
    }

    private static func item(
        dueOffset: TimeInterval,
        status: MedicationWatchDoseStatus = .pending
    ) -> MedicationWatchDoseItem {
        MedicationWatchDoseItem(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000501") ?? UUID(),
            medicationName: "二甲双胍",
            doseText: "1 片",
            dueAt: now.addingTimeInterval(dueOffset),
            status: status
        )
    }
}

#Preview(as: .accessoryRectangular) {
    MedicationAdherenceWatchComplication()
} timeline: {
    MedicationWatchComplicationPreviewData.firstSync
    MedicationWatchComplicationPreviewData.stale
    MedicationWatchComplicationPreviewData.empty
    MedicationWatchComplicationPreviewData.completed
    MedicationWatchComplicationPreviewData.upcoming
    MedicationWatchComplicationPreviewData.dueSoon
    MedicationWatchComplicationPreviewData.overdue
    MedicationWatchComplicationPreviewData.privacy
}

#Preview(as: .accessoryCircular) {
    MedicationAdherenceWatchComplication()
} timeline: {
    MedicationWatchComplicationPreviewData.firstSync
    MedicationWatchComplicationPreviewData.stale
    MedicationWatchComplicationPreviewData.empty
    MedicationWatchComplicationPreviewData.completed
    MedicationWatchComplicationPreviewData.upcoming
    MedicationWatchComplicationPreviewData.dueSoon
    MedicationWatchComplicationPreviewData.overdue
    MedicationWatchComplicationPreviewData.privacy
}

#Preview(as: .accessoryInline) {
    MedicationAdherenceWatchComplication()
} timeline: {
    MedicationWatchComplicationPreviewData.firstSync
    MedicationWatchComplicationPreviewData.stale
    MedicationWatchComplicationPreviewData.empty
    MedicationWatchComplicationPreviewData.completed
    MedicationWatchComplicationPreviewData.upcoming
    MedicationWatchComplicationPreviewData.dueSoon
    MedicationWatchComplicationPreviewData.overdue
    MedicationWatchComplicationPreviewData.privacy
}

#if os(watchOS)
#Preview(as: .accessoryCorner) {
    MedicationAdherenceWatchComplication()
} timeline: {
    MedicationWatchComplicationPreviewData.firstSync
    MedicationWatchComplicationPreviewData.stale
    MedicationWatchComplicationPreviewData.empty
    MedicationWatchComplicationPreviewData.completed
    MedicationWatchComplicationPreviewData.upcoming
    MedicationWatchComplicationPreviewData.dueSoon
    MedicationWatchComplicationPreviewData.overdue
    MedicationWatchComplicationPreviewData.privacy
}
#endif
#endif
