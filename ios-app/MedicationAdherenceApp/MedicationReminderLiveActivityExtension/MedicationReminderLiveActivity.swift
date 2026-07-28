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
                            Text("已记录")
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
                        MedicationReminderCompletionStrip(
                            doseText: context.attributes.doseText,
                            completedAt: context.state.completedAt
                        )
                        .padding(.horizontal, 8)
                        .padding(.top, 4)
                        .padding(.bottom, 4)
                    } else {
                        MedicationReminderIslandActionCard(
                            taskID: context.attributes.taskID,
                            operationID: context.attributes.actionOperationID ?? context.attributes.taskID,
                            doseText: context.attributes.doseText,
                            dueAt: context.state.dueAt
                        )
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
                    Text("完成")
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
                Text(context.state.isCompleted ? "已完成" : "用药提醒")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(context.state.isCompleted ? .green : .blue)
                Text(context.attributes.medicationName)
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
                    Text(context.attributes.medicationName)
                        .font(.headline.weight(.bold))
                        .lineLimit(1)
                    Text("\(context.attributes.doseText) · \(context.state.dueAt.formatted(date: .omitted, time: .shortened))")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                MedicationReminderLiveActivityActions(
                    taskID: context.attributes.taskID,
                    operationID: context.attributes.actionOperationID ?? context.attributes.taskID,
                    expiresAt: context.state.dueAt.addingTimeInterval(10 * 60),
                    compact: false
                )
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
                Text("已完成本次提醒")
                    .font(.headline.weight(.bold))
                Text(context.attributes.medicationName)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text("\(context.attributes.doseText) · \(context.state.completedAt?.formatted(date: .omitted, time: .shortened) ?? "刚刚")")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(16)
    }
}

private struct MedicationReminderLiveActivityActions: View {
    let taskID: UUID
    let operationID: UUID
    let expiresAt: Date
    let compact: Bool

    var body: some View {
        if compact {
            VStack(alignment: .leading, spacing: 6) {
                actionButtons
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            VStack(alignment: .trailing, spacing: 7) {
                actionButtons
            }
        }
    }

    private var actionButtons: some View {
        HStack(spacing: 7) {
            markTakenButton
            actionLink(title: "稍后", action: .delay, tint: .blue, compactWidth: 62, regularWidth: 66)
        }
        .frame(maxWidth: .infinity, alignment: compact ? .center : .trailing)
    }

    @ViewBuilder
    private var markTakenButton: some View {
        if #available(iOSApplicationExtension 17.0, *) {
            Button(intent: MarkMedicationReminderTakenIntent(
                taskID: taskID,
                operationID: operationID,
                expiresAt: expiresAt
            )) {
                actionButtonLabel(title: "已服用", tint: .green, width: compact ? 82 : 70)
            }
            .buttonStyle(.plain)
        } else {
            actionLink(title: "已服用", action: .markTaken, tint: .green, compactWidth: 74, regularWidth: 70)
        }
    }

    private func actionLink(
        title: String,
        action: MedicationReminderLiveActivityAction,
        tint: Color,
        compactWidth: CGFloat,
        regularWidth: CGFloat
    ) -> some View {
        Link(destination: MedicationReminderLiveActivityActionURL.url(
            for: taskID,
            action: action,
            operationID: operationID,
            expiresAt: expiresAt
        )) {
            actionButtonLabel(title: title, tint: tint, width: compact ? compactWidth : regularWidth)
        }
        .buttonStyle(.plain)
    }

    private func actionButtonLabel(title: String, tint: Color, width: CGFloat) -> some View {
        Text(title)
            .font((compact ? Font.caption2 : Font.caption).weight(.bold))
            .lineLimit(1)
            .minimumScaleFactor(0.78)
            .foregroundStyle(tint)
            .frame(minWidth: width, minHeight: compact ? 28 : 30)
            .padding(.horizontal, compact ? 8 : 10)
            .background(tint.opacity(compact ? 0.20 : 0.14), in: Capsule())
    }
}

private struct MedicationReminderIslandActionCard: View {
    let taskID: UUID
    let operationID: UUID
    let doseText: String
    let dueAt: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                MedicationReminderIslandDetailPill(
                    title: "剂量",
                    value: doseText,
                    symbolName: "pills.fill",
                    tint: .blue
                )
                MedicationReminderIslandDetailPill(
                    title: "计划",
                    value: dueAt.formatted(date: .omitted, time: .shortened),
                    symbolName: "clock.fill",
                    tint: .cyan
                )
            }

            MedicationReminderLiveActivityActions(
                taskID: taskID,
                operationID: operationID,
                expiresAt: dueAt.addingTimeInterval(10 * 60),
                compact: true
            )
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Color.blue.opacity(0.10), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
    }
}

private struct MedicationReminderIslandDetailPill: View {
    let title: String
    let value: String
    let symbolName: String
    let tint: Color

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: symbolName)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 20, height: 20)
                .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 6, style: .continuous))

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.caption2.weight(.bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.76)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, minHeight: 30, alignment: .leading)
        .background(Color.primary.opacity(0.052), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

private struct MedicationReminderCompletionStrip: View {
    let doseText: String
    let completedAt: Date?

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .font(.title3.weight(.semibold))
                .symbolEffect(.bounce, value: completedAt)
                .foregroundStyle(.green)
            VStack(alignment: .leading, spacing: 2) {
                Text("本次提醒已完成")
                    .font(.subheadline.weight(.bold))
                Text("\(doseText) · \(completedAt?.formatted(date: .omitted, time: .shortened) ?? "刚刚")")
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
