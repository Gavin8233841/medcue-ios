import MedicationAdherenceCore
import SwiftUI

struct MedicationLifecycleSelector: View {
    @Binding var selectedStatus: StoredMedicationLifecycleStatus
    let count: (StoredMedicationLifecycleStatus) -> Int

    var body: some View {
        HStack(spacing: 8) {
            ForEach(StoredMedicationLifecycleStatus.allCases) { status in
                let isSelected = selectedStatus == status
                Button {
                    withAnimation(.snappy(duration: 0.22)) {
                        selectedStatus = status
                    }
                } label: {
                    VStack(spacing: 5) {
                        Image(systemName: lifecycleIconName(for: status))
                            .font(.subheadline.weight(.semibold))
                            .frame(height: 18)
                        Text("\(count(status))")
                            .font(.title3.weight(.bold))
                            .monospacedDigit()
                            .frame(height: 22)
                        Text(status.displayName)
                            .font(.caption.weight(.semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.72)
                            .allowsTightening(true)
                            .frame(maxWidth: .infinity)
                    }
                    .foregroundStyle(isSelected ? Color.white : badgeColor(for: status))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 7)
                    .frame(maxWidth: .infinity, minHeight: 74)
                    .background(
                        isSelected ? badgeColor(for: status) : badgeColor(for: status).opacity(0.10),
                        in: RoundedRectangle(cornerRadius: 8)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(isSelected ? Color.clear : badgeColor(for: status).opacity(0.22), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(status.displayName)，\(count(status)) 个药品")
            }
        }
        .padding(.vertical, 3)
    }

    private func lifecycleIconName(for status: StoredMedicationLifecycleStatus) -> String {
        switch status {
        case .active:
            "pills.fill"
        case .interrupted:
            "pause.circle.fill"
        case .archived:
            "archivebox.fill"
        }
    }
}

struct MedicationLifecycleGroupSummaryRow: View {
    let status: StoredMedicationLifecycleStatus
    let count: Int
    let firstMedication: StoredMedication?
    let nextTask: StoredDoseTask?

    private var tint: Color {
        badgeColor(for: status)
    }

    private var subtitle: String {
        if let firstMedication {
            let name = userFacingMedicationName(for: firstMedication)
            if let nextTask {
                return "\(name) · 下次 \(AppFormatters.time.string(from: nextTask.dueAt))"
            }
            return "\(name) · 暂无今日待处理"
        }
        return "暂无药品"
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: iconName)
                .font(.title2.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 42, height: 42)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text("\(status.displayName)药品")
                    .font(.headline)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Text("\(count)")
                .font(.system(.headline, design: .rounded).weight(.bold))
                .foregroundStyle(tint)
                .monospacedDigit()
                .contentTransition(.numericText())
        }
        .padding(.vertical, 5)
    }

    private var iconName: String {
        switch status {
        case .active:
            return "pills.fill"
        case .interrupted:
            return "pause.circle.fill"
        case .archived:
            return "archivebox.fill"
        }
    }
}

struct MedicationAddOptionsSheet: View {
    @Environment(\.dismiss) private var dismiss
    let select: (MedicationAddOption) -> Void

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(MedicationAddWorkflow.options) { option in
                        let isEnabled = isMedicationAddOptionEnabled(option)
                        Button {
                            select(option)
                        } label: {
                            HStack(spacing: 14) {
                                Image(systemName: addOptionIconName(option))
                                    .font(.title3.weight(.semibold))
                                    .foregroundStyle(isEnabled ? Color.blue : Color.secondary)
                                    .frame(width: 36, height: 36)
                                    .background(
                                        (isEnabled ? Color.blue : Color.secondary).opacity(isEnabled ? 0.12 : 0.10),
                                        in: RoundedRectangle(cornerRadius: 8)
                                    )
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(option.title)
                                        .font(.headline)
                                        .foregroundStyle(isEnabled ? .primary : .secondary)
                                    Text(addOptionSubtitle(option))
                                        .font(.footnote)
                                        .foregroundStyle(isEnabled ? .secondary : .tertiary)
                                        .lineLimit(2)
                                }
                                Spacer()
                                if isEnabled {
                                    Image(systemName: "chevron.right")
                                        .font(.footnote.weight(.bold))
                                        .foregroundStyle(.secondary)
                                } else {
                                    Text("暂不可用")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.tertiary)
                                }
                            }
                            .padding(.vertical, 4)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(!isEnabled)
                        .accessibilityIdentifier(
                            option.id == .manual
                                ? AppAccessibilityID.medicationAddManual
                                : "medication.add.\(option.id.rawValue)"
                        )
                    }
                }
            }
            .navigationTitle("添加药品")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") {
                        dismiss()
                    }
                }
            }
        }
    }
}

func isMedicationAddOptionEnabled(_ option: MedicationAddOption) -> Bool {
    option.id == .manual
}

struct MedicationDashboardSummary: View {
    let medicationCount: Int
    let activeTaskCount: Int
    let stockCount: Int
    let lowStockCount: Int
    let activeRiskCount: Int
    let priorityRiskCount: Int
    @State private var selectedDestination: MedicationDashboardDestination?
    private let columns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("用药概览")
                        .font(.title2.weight(.semibold))
                    Text("药品、提醒、药盒和风险复核")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "heart.text.square.fill")
                    .font(.title)
                    .foregroundStyle(.blue)
            }

            LazyVGrid(columns: columns, spacing: 10) {
                Button {
                    selectedDestination = .overview
                } label: {
                    MedicationMetricTile(
                        title: "药品",
                        value: "\(medicationCount)",
                        subtitle: medicationCount == 0 ? "等待添加" : "查看详情",
                        iconName: "pills.fill",
                        tint: .blue
                    )
                }
                .buttonStyle(.plain)

                Button {
                    selectedDestination = .pendingTasks
                } label: {
                    MedicationMetricTile(
                        title: "待处理",
                        value: "\(activeTaskCount)",
                        subtitle: activeTaskCount == 0 ? "今日清空" : "去今日页",
                        iconName: "bell.badge.fill",
                        tint: activeTaskCount > 0 ? .orange : .green
                    )
                }
                .buttonStyle(.plain)

                Button {
                    selectedDestination = .stock
                } label: {
                    MedicationMetricTile(
                        title: "药盒",
                        value: "\(stockCount)",
                        subtitle: lowStockCount > 0 ? "\(lowStockCount) 项需核对" : "均正常",
                        iconName: "shippingbox.fill",
                        tint: lowStockCount > 0 ? .orange : .green
                    )
                }
                .buttonStyle(.plain)

                Button {
                    selectedDestination = .risk
                } label: {
                    MedicationMetricTile(
                        title: "风险复核",
                        value: "\(priorityRiskCount > 0 ? priorityRiskCount : activeRiskCount)",
                        subtitle: priorityRiskCount > 0 ? "需重点查看" : (activeRiskCount > 0 ? "可查看" : "暂无活跃"),
                        iconName: "shield.lefthalf.filled",
                        tint: priorityRiskCount > 0 ? .orange : (activeRiskCount > 0 ? .indigo : .secondary)
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 8)
        .navigationDestination(item: $selectedDestination) { destination in
            switch destination {
            case .overview:
                MedicationOverviewDetailView()
            case .pendingTasks:
                MedicationPendingTasksDetailView()
            case .stock:
                MedicationStockOverviewView()
            case .risk:
                RisksView()
            }
        }
    }
}

enum MedicationDashboardDestination: Hashable, Identifiable {
    case overview
    case pendingTasks
    case stock
    case risk

    var id: Self { self }
}

struct MedicationMetricTile: View {
    let title: String
    let value: String
    var subtitle: String? = nil
    let iconName: String
    let tint: Color
    var compact = false

    var body: some View {
        let iconSize: CGFloat = compact ? 24 : 28
        let minHeight: CGFloat = compact ? 66 : 76
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: compact ? 5 : 7) {
                HStack(spacing: 8) {
                    Image(systemName: iconName)
                        .font(compact ? .subheadline.weight(.semibold) : .headline)
                        .foregroundStyle(tint)
                        .frame(width: iconSize, height: iconSize)
                        .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                    Text(title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                }
                if let subtitle, !compact {
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(value)
                .font((compact ? Font.title2 : Font.title).weight(.bold))
                .monospacedDigit()
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.68)
                .frame(minWidth: 36, alignment: .trailing)
        }
        .padding(compact ? 9 : 12)
        .frame(maxWidth: .infinity, minHeight: minHeight, alignment: .leading)
        .background(tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
    }
}
