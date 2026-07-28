import MedicationAdherenceCore
import SwiftUI

struct MedicationCardRow: View {
    let medication: StoredMedication
    let plan: StoredMedicationPlan?
    let taskCount: Int
    let nextTask: StoredDoseTask?
    let stockProjection: MedicationStockProjection?
    let lifecycleClassification: MedicationLifecycleClassification

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 14) {
                MedicationPhotoView(photoData: medication.photoData, symbolName: medication.photoSymbolName, tint: medicationColor(for: medication))
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 7) {
                        MedicationColorMarker(color: medicationColor(for: medication), size: 9)
                        Text(userFacingMedicationName(for: medication))
                            .font(.headline)
                    }
                    if medicationNeedsNameReview(medication) {
                        StatusBadge(text: "药名待补全", color: .orange)
                    }
                    Text([medication.strength, medication.form].filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    StatusBadgeFlow {
                        StatusBadge(text: medication.kindDisplayName, color: .green)
                        if !medication.boxNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            StatusBadge(text: "编号 \(medication.boxNumber)", color: .blue)
                        }
                        if medication.lifecycleStatus != .active || lifecycleClassification.shouldPromptReview {
                            StatusBadge(
                                text: lifecycleClassification.displayStatus.displayName,
                                color: badgeColor(for: lifecycleClassification.displayStatus)
                            )
                        }
                        if let stockProjection, stockProjection.needsRefillReminder {
                            StatusBadge(text: "药盒低量", color: .orange)
                        } else if stockProjection != nil {
                            StatusBadge(text: "药盒已记录", color: .green)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack(spacing: 10) {
                MedicationInlineStat(
                    iconName: "clock",
                    title: "下次",
                    value: nextTask.map { AppFormatters.time.string(from: $0.dueAt) } ?? "暂无"
                )
                MedicationInlineStat(
                    iconName: "list.bullet.clipboard",
                    title: "记录",
                    value: "\(taskCount)"
                )
                MedicationInlineStat(
                    iconName: "shippingbox",
                    title: "药盒",
                    value: stockProjection.map { formatDecimal($0.projectedRemainingQuantity) + " " + localizedMedicationUnit($0.unit) } ?? "未填"
                )
            }

            if let plan {
                Text(plan.timingSummary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            if !medication.boxNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Label("药盒编号 \(medication.boxNumber)", systemImage: "number.square.fill")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            if lifecycleClassification.shouldPromptReview {
                Text(lifecycleClassification.explanation)
                    .font(.footnote)
                    .foregroundStyle(.orange)
                    .lineLimit(2)
            }
            if let stockProjection {
                Text(localizedStockProjectionMessage(stockProjection))
                    .font(.footnote)
                    .foregroundStyle(stockProjection.needsRefillReminder ? .orange : .secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 8)
    }
}

struct MedicationInlineStat: View {
    let iconName: String
    let title: String
    let value: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: iconName)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.blue)
            VStack(alignment: .leading, spacing: 1) {
                Text(value)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(title)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8))
    }
}

struct LifecycleReviewPanel: View {
    let medication: StoredMedication
    let classification: MedicationLifecycleClassification
    let markInterrupted: () -> Void
    let markActive: () -> Void
    let archive: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: iconName)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(tint)
                    .frame(width: 30, height: 30)
                    .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                VStack(alignment: .leading, spacing: 3) {
                    Text(classification.displayStatus.displayName)
                        .font(.headline)
                    Text(classification.explanation)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            if classification.shouldPromptReview {
                Button {
                    markInterrupted()
                } label: {
                    LifecycleActionButton(
                        title: "确认服用中断",
                        subtitle: "停用未来提醒，保留既有记录",
                        systemImage: "pause.circle.fill",
                        tint: .orange
                    )
                }
                .buttonStyle(.plain)
            }

            if medication.lifecycleStatus == .interrupted {
                Button {
                    markActive()
                } label: {
                    LifecycleActionButton(
                        title: "恢复正在服用",
                        subtitle: "重新纳入今日和提醒计划",
                        systemImage: "play.circle.fill",
                        tint: .green
                    )
                }
                .buttonStyle(.plain)
            }

            if medication.lifecycleStatus != .archived {
                Button(role: .destructive) {
                    archive()
                } label: {
                    LifecycleActionButton(
                        title: "归档药物",
                        subtitle: "从今日提醒移出，归档后可删除",
                        systemImage: "archivebox.fill",
                        tint: .orange
                    )
                }
                .buttonStyle(.plain)
            }

            Text("状态用于列表归类和提醒管理，不代表停药、换药或处方建议；有疑问请咨询医生或药师。")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 6)
    }

    private var tint: Color {
        badgeColor(for: classification.displayStatus)
    }

    private var iconName: String {
        switch classification.displayStatus {
        case .active:
            "pills.fill"
        case .interrupted:
            "pause.circle.fill"
        case .archived:
            "archivebox.fill"
        }
    }
}

struct LifecycleActionButton: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let tint: Color

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.headline.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 34, height: 34)
                .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 8)

            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(.tertiary)
        }
        .padding(12)
        .background(tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(tint.opacity(0.12), lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}
