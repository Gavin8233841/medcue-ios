import ActivityKit
import SwiftUI
import WidgetKit

struct MedicationReminderLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: MedicationReminderActivityAttributes.self) { context in
            MedicationReminderLockScreenView(context: context)
                .activityBackgroundTint(Color(.systemBackground))
                .activitySystemActionForegroundColor(.blue)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    VStack(alignment: .leading, spacing: 3) {
                        Label("用药提醒", systemImage: "pills.fill")
                            .font(.caption.weight(.semibold))
                        Text(context.attributes.medicationName)
                            .font(.subheadline.weight(.bold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.76)
                    }
                    .padding(.leading, 2)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: 3) {
                        Text(context.state.statusText)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.blue)
                        Text(context.state.dueAt, style: .time)
                            .font(.subheadline.weight(.bold))
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .padding(.trailing, 2)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        Text(context.attributes.doseText)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        Spacer()
                        Text("完成后自动收起")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .padding(.top, 2)
                }
            } compactLeading: {
                Image(systemName: "pills.fill")
                    .foregroundStyle(.blue)
            } compactTrailing: {
                Text(context.state.dueAt, style: .time)
                    .font(.caption2.weight(.bold))
            } minimal: {
                Image(systemName: "pills.fill")
                    .foregroundStyle(.blue)
            }
        }
    }
}

private struct MedicationReminderLockScreenView: View {
    let context: ActivityViewContext<MedicationReminderActivityAttributes>

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "pills.fill")
                .font(.title2.weight(.semibold))
                .foregroundStyle(.blue)
                .frame(width: 44, height: 44)
                .background(Color.blue.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 4) {
                Text(context.state.statusText)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(context.attributes.medicationName)
                    .font(.headline.weight(.bold))
                    .lineLimit(1)
                Text("\(context.attributes.doseText) · \(context.state.dueAt.formatted(date: .omitted, time: .shortened))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(16)
    }
}
