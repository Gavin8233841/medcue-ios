import ActivityKit
import AppIntents
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
                DynamicIslandExpandedRegion(.leading, priority: 1) {
                    MedicationReminderIslandHeader(context: context)
                }
                DynamicIslandExpandedRegion(.trailing, priority: 1) {
                    if context.state.isCompleted {
                        VStack(alignment: .trailing, spacing: 4) {
                            Image(systemName: "checkmark.seal.fill")
                                .font(.title2.weight(.semibold))
                                .symbolEffect(.bounce, value: context.state.completedAt)
                                .foregroundStyle(.green)
                            Text("已结束")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.green)
                        }
                        .padding(.trailing, 6)
                        .padding(.top, 4)
                    } else {
                        VStack(alignment: .trailing, spacing: 3) {
                            Text(context.state.statusText)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.blue)
                            Text(context.state.dueAt, style: .time)
                                .font(.headline.weight(.bold))
                                .monospacedDigit()
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                        .padding(.trailing, 6)
                        .padding(.top, 4)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    if context.state.isCompleted {
                        MedicationReminderCompletionStrip(completedAt: context.state.completedAt)
                        .padding(.horizontal, 8)
                        .padding(.top, 4)
                        .padding(.bottom, 4)
                    } else {
                        MedicationReminderIslandActionCard(dueAt: context.state.dueAt)
                        .padding(.horizontal, 8)
                        .padding(.top, 4)
                        .padding(.bottom, 4)
                    }
                }
            } compactLeading: {
                Image(systemName: context.state.isCompleted ? "checkmark.circle.fill" : "pills.fill")
                    .foregroundStyle(context.state.isCompleted ? .green : .blue)
            } compactTrailing: {
                if context.state.isCompleted {
                    Text("结束")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.green)
                } else {
                    Text(context.state.dueAt, style: .time)
                        .font(.caption2.weight(.bold))
                }
            } minimal: {
                Image(systemName: context.state.isCompleted ? "checkmark.circle.fill" : "pills.fill")
                    .foregroundStyle(context.state.isCompleted ? .green : .blue)
            }
            .contentMargins(.horizontal, 6, for: .expanded)
            .contentMargins(.bottom, 12, for: .expanded)
        }
    }
}

private struct MedicationReminderIslandHeader: View {
    let context: ActivityViewContext<MedicationReminderActivityAttributes>

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: context.state.isCompleted ? "checkmark.circle.fill" : "pills.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(context.state.isCompleted ? .green : .blue)
                .frame(width: 28, height: 28)
                .background(
                    (context.state.isCompleted ? Color.green : Color.blue).opacity(0.12),
                    in: RoundedRectangle(cornerRadius: 9, style: .continuous)
                )

            VStack(alignment: .leading, spacing: 3) {
                Text(context.state.isCompleted ? MedicationSystemSurfacePrivacyPolicy.completedTitle : MedicationSystemSurfacePrivacyPolicy.reminderTitle)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(context.state.isCompleted ? .green : .blue)
                Text("打开 App 查看")
                    .font(.headline.weight(.bold))
                    .lineLimit(2)
                    .minimumScaleFactor(0.74)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, 4)
        .padding(.top, 4)
    }
}

private struct MedicationReminderLockScreenView: View {
    let context: ActivityViewContext<MedicationReminderActivityAttributes>

    var body: some View {
        if context.state.isCompleted {
            MedicationReminderCompletedLockScreenView(context: context)
        } else {
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
                    Text(MedicationSystemSurfacePrivacyPolicy.reminderTitle)
                        .font(.headline.weight(.bold))
                        .lineLimit(1)
                    Text(context.state.dueAt, style: .time)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text("打开 App 查看")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.blue)
            }
            .padding(16)
        }
    }
}

private struct MedicationReminderCompletedLockScreenView: View {
    let context: ActivityViewContext<MedicationReminderActivityAttributes>

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.title2.weight(.semibold))
                .foregroundStyle(.green)
                .frame(width: 44, height: 44)
                .background(Color.green.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 4) {
                Text(MedicationSystemSurfacePrivacyPolicy.completedTitle)
                    .font(.headline.weight(.bold))
                Text("打开 App 查看")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(16)
    }
}

private struct MedicationReminderIslandActionCard: View {
    let dueAt: Date

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "clock.fill")
                .foregroundStyle(.blue)
            Text(dueAt, style: .time)
                .font(.caption.weight(.semibold))
            Spacer(minLength: 0)
            Text("打开 App 查看")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.blue)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .background(Color.blue.opacity(0.10), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
    }
}

private struct MedicationReminderCompletionStrip: View {
    let completedAt: Date?

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .font(.title3.weight(.semibold))
                .symbolEffect(.bounce, value: completedAt)
                .foregroundStyle(.green)
            VStack(alignment: .leading, spacing: 2) {
                Text(MedicationSystemSurfacePrivacyPolicy.completedTitle)
                    .font(.subheadline.weight(.bold))
                Text("打开 App 查看")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .background(Color.green.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .transition(.opacity.combined(with: .scale(scale: 0.96)))
    }
}
