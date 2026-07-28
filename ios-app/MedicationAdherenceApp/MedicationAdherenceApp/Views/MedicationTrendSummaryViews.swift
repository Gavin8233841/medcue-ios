import MedicationAdherenceCore
import SwiftUI
import UIKit

struct MedicationTrendDashboardCard: View {
    let dashboard: MedicationTrendDashboard

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: trendDirectionIconName(dashboard.direction))
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(trendDirectionTint(dashboard.direction))
                    .frame(width: 42, height: 42)
                    .background(trendDirectionTint(dashboard.direction).opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                VStack(alignment: .leading, spacing: 4) {
                    Text(dashboard.title)
                        .font(.title3.weight(.semibold))
                    Text(dashboard.summary)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(dashboard.dataQualitySummary)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            ProgressView(value: dashboard.overallScore)
                .tint(trendDirectionTint(dashboard.direction))

            HStack {
                Text(trendDirectionTitle(dashboard.direction))
                Spacer()
                Text("综合 \(percentageText(dashboard.overallScore))%")
                    .monospacedDigit()
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 8)
    }
}

struct MedicationTrendTopicPicker: View {
    @Binding var selectedTopic: MedicationTrendTopic
    let metrics: [MedicationTrendMetric]

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
            ForEach(metrics) { metric in
                Button {
                    selectedTopic = metric.topic
                } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 6) {
                            Image(systemName: trendTopicIconName(metric.topic))
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(trendDirectionTint(metric.direction))
                            Text(metric.title)
                                .font(.caption.weight(.semibold))
                                .lineLimit(1)
                                .minimumScaleFactor(0.82)
                            Spacer(minLength: 0)
                        }
                        HStack(alignment: .firstTextBaseline) {
                            Text(trendMetricValueText(metric))
                                .font(.headline.monospacedDigit().weight(.semibold))
                            Spacer()
                            Text(trendDirectionTitle(metric.direction))
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
                    .background(
                        selectedTopic == metric.topic ? trendDirectionTint(metric.direction).opacity(0.16) : Color(.secondarySystemGroupedBackground),
                        in: RoundedRectangle(cornerRadius: 8)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(selectedTopic == metric.topic ? trendDirectionTint(metric.direction).opacity(0.45) : .clear, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }
}

struct MedicationTrendMetricSummary: View {
    let metric: MedicationTrendMetric

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(metric.title, systemImage: trendTopicIconName(metric.topic))
                    .font(.headline)
                    .foregroundStyle(trendDirectionTint(metric.direction))
                Spacer()
                StatusBadge(text: trendDirectionTitle(metric.direction), color: trendDirectionTint(metric.direction))
            }
            Text(metric.summary)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 6)
    }
}

struct TrendPeriodComparisonPanel: View {
    let metric: MedicationTrendMetric

    private var tint: Color {
        trendDirectionTint(metric.direction)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center, spacing: 10) {
                Label("周期对比", systemImage: "chart.bar.xaxis")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Spacer(minLength: 8)
                TrendDeltaChip(comparison: metric.comparison, tint: tint)
            }

            HStack(alignment: .lastTextBaseline, spacing: 10) {
                Text(trendMetricValueText(metric))
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .foregroundStyle(tint)
                    .monospacedDigit()
                    .contentTransition(.numericText(value: metric.comparison.recentScore))
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
                Text(trendMetricPrimaryValueTitle(metric))
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }

            VStack(spacing: 12) {
                TrendPeriodBar(
                    title: metric.comparison.recentPeriodTitle,
                    value: metric.comparison.recentScore,
                    dayCount: metric.comparison.recentDayCount,
                    scheduledCount: metric.comparison.recentScheduledCount,
                    tint: tint,
                    isPrimary: true
                )

                if let previousScore = metric.comparison.previousScore {
                    TrendPeriodBar(
                        title: metric.comparison.previousPeriodTitle,
                        value: previousScore,
                        dayCount: metric.comparison.previousDayCount,
                        scheduledCount: metric.comparison.previousScheduledCount,
                        tint: .secondary,
                        isPrimary: false
                    )
                } else {
                    TrendPreviousPeriodPlaceholder(title: metric.comparison.previousPeriodTitle)
                }
            }
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(tint.opacity(0.14), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
    }
}

struct TrendDeltaChip: View {
    let comparison: MedicationTrendPeriodComparison
    let tint: Color

    private var title: String {
        guard comparison.previousScore != nil, let delta = comparison.delta else {
            return "等待对比"
        }
        return trendDeltaText(delta)
    }

    private var chipTint: Color {
        guard comparison.previousScore != nil, let delta = comparison.delta else {
            return .secondary
        }
        if abs(delta) < 0.005 {
            return .secondary
        }
        return delta > 0 ? .green : .orange
    }

    var body: some View {
        Label(title, systemImage: comparison.delta.map { $0 >= 0 ? "arrow.up.right" : "arrow.down.right" } ?? "minus")
            .font(.caption.monospacedDigit().weight(.semibold))
            .foregroundStyle(chipTint)
            .lineLimit(1)
            .minimumScaleFactor(0.78)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(chipTint.opacity(0.12), in: Capsule())
            .overlay(
                Capsule()
                    .stroke(chipTint.opacity(0.18), lineWidth: 1)
            )
            .accessibilityLabel("周期对比 \(title)")
    }
}

struct TrendPeriodBar: View {
    let title: String
    let value: Double
    let dayCount: Int
    let scheduledCount: Int
    let tint: Color
    let isPrimary: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(title)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text("\(percentageText(value))%")
                    .font((isPrimary ? Font.headline : Font.subheadline).monospacedDigit().weight(.semibold))
                    .foregroundStyle(isPrimary ? tint : .secondary)
                    .lineLimit(1)
            }
            Text("\(dayCount) 天 · \(scheduledCount) 次计划")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.secondary.opacity(0.12))
                    Capsule()
                        .fill(isPrimary ? tint.opacity(0.82) : Color.secondary.opacity(0.45))
                        .frame(width: max(8, proxy.size.width * normalizedTrendScore(value)))
                }
            }
            .frame(height: isPrimary ? 10 : 8)
        }
    }
}

struct TrendPreviousPeriodPlaceholder: View {
    let title: String

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: "clock.badge.questionmark")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 22, height: 22)
                .background(Color.secondary.opacity(0.10), in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.primary)
                Text("记录不足时不强行生成周期结论。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
