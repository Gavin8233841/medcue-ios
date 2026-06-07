import SwiftUI
import UIKit

private struct OpenMedicationAIQuestionKey: EnvironmentKey {
    static let defaultValue: (String) -> Void = { _ in }
}

private struct PendingMedicationAIQuestionKey: EnvironmentKey {
    static let defaultValue = ""
}

private struct ClearPendingMedicationAIQuestionKey: EnvironmentKey {
    static let defaultValue: () -> Void = {}
}

extension EnvironmentValues {
    var openMedicationAIQuestion: (String) -> Void {
        get { self[OpenMedicationAIQuestionKey.self] }
        set { self[OpenMedicationAIQuestionKey.self] = newValue }
    }

    var pendingMedicationAIQuestion: String {
        get { self[PendingMedicationAIQuestionKey.self] }
        set { self[PendingMedicationAIQuestionKey.self] = newValue }
    }

    var clearPendingMedicationAIQuestion: () -> Void {
        get { self[ClearPendingMedicationAIQuestionKey.self] }
        set { self[ClearPendingMedicationAIQuestionKey.self] = newValue }
    }
}

struct MedicationSymbolView: View {
    let symbolName: String
    let tint: Color

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(tint.opacity(0.14))
            Image(systemName: symbolName)
                .font(.title2.weight(.semibold))
                .foregroundStyle(tint)
        }
        .frame(width: 64, height: 64)
        .accessibilityHidden(true)
    }
}

struct MedicationPhotoView: View {
    let photoData: Data?
    let symbolName: String
    let tint: Color
    var size: CGFloat = 64

    var body: some View {
        Group {
            if let photoData, let image = UIImage(data: photoData) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size, height: size)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(.quaternary, lineWidth: 1)
                    )
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(tint.opacity(0.14))
                    Image(systemName: symbolName)
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(tint)
                }
                .frame(width: size, height: size)
            }
        }
        .accessibilityHidden(true)
    }
}

struct StatusBadge: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(color)
            .lineLimit(1)
            .minimumScaleFactor(0.82)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .fixedSize(horizontal: true, vertical: false)
            .background(color.opacity(0.12), in: Capsule())
    }
}

struct StatusBadgeFlow: Layout {
    var spacing: CGFloat = 7
    var rowSpacing: CGFloat = 7

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        let rows = rows(in: subviews, maxWidth: maxWidth)
        let width = rows.map(\.width).max() ?? 0
        let height = rows.reduce(CGFloat.zero) { result, row in
            result + row.height
        } + CGFloat(max(rows.count - 1, 0)) * rowSpacing
        return CGSize(width: min(width, maxWidth), height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = rows(in: subviews, maxWidth: bounds.width)
        var y = bounds.minY
        for row in rows {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(
                    at: CGPoint(x: x, y: y + (row.height - size.height) / 2),
                    proposal: ProposedViewSize(size)
                )
                x += size.width + spacing
            }
            y += row.height + rowSpacing
        }
    }

    private func rows(in subviews: Subviews, maxWidth: CGFloat) -> [BadgeFlowRow] {
        var rows: [BadgeFlowRow] = []
        var current = BadgeFlowRow()

        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let proposedWidth = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            if proposedWidth > maxWidth, !current.indices.isEmpty {
                rows.append(current)
                current = BadgeFlowRow()
            }
            current.indices.append(index)
            current.width = current.width == 0 ? size.width : current.width + spacing + size.width
            current.height = max(current.height, size.height)
        }

        if !current.indices.isEmpty {
            rows.append(current)
        }
        return rows
    }
}

private struct BadgeFlowRow {
    var indices: [Int] = []
    var width: CGFloat = 0
    var height: CGFloat = 0
}

struct InfoRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer(minLength: 16)
            Text(value)
                .multilineTextAlignment(.trailing)
        }
        .font(.body)
    }
}

enum AppFormatters {
    static let time: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    static let day: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()
}

struct MedicationDoseUnitOption: Identifiable, Hashable {
    let id: String
    let displayName: String

    static let common: [MedicationDoseUnitOption] = [
        .init(id: "片", displayName: "片"),
        .init(id: "粒", displayName: "粒"),
        .init(id: "袋", displayName: "袋"),
        .init(id: "滴", displayName: "滴"),
        .init(id: "喷", displayName: "喷"),
        .init(id: "贴", displayName: "贴"),
        .init(id: "支", displayName: "支"),
        .init(id: "毫升", displayName: "毫升"),
        .init(id: "克", displayName: "克"),
        .init(id: "份", displayName: "份")
    ]
}

struct MedicationIconOption: Identifiable, Hashable {
    let id: String
    let displayName: String
    let symbolName: String

    static let common: [MedicationIconOption] = [
        .init(id: "pill", displayName: "药片", symbolName: "pills.fill"),
        .init(id: "capsule", displayName: "胶囊", symbolName: "capsule.portrait.fill"),
        .init(id: "prescription", displayName: "处方", symbolName: "cross.case.fill"),
        .init(id: "eye", displayName: "滴眼", symbolName: "eye.fill"),
        .init(id: "spray", displayName: "喷雾", symbolName: "wind"),
        .init(id: "patch", displayName: "贴剂", symbolName: "bandage.fill"),
        .init(id: "liquid", displayName: "液体", symbolName: "drop.fill")
    ]
}

func localizedMedicationUnit(_ unit: String) -> String {
    switch unit.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
    case "tablet", "tablets", "tab", "tabs":
        return "片"
    case "capsule", "capsules", "cap", "caps":
        return "粒"
    case "drop", "drops":
        return "滴"
    case "spray", "sprays":
        return "喷"
    case "patch", "patches":
        return "贴"
    case "ml", "milliliter", "milliliters":
        return "毫升"
    case "g", "gram", "grams":
        return "克"
    case "unit", "units":
        return "份"
    default:
        return unit
    }
}

func medicationDemoLabelLookupName(for medication: StoredMedication) -> String {
    switch medication.displayName {
    case "布洛芬":
        return "Ibuprofen"
    case "对乙酰氨基酚":
        return "Acetaminophen"
    case "人工泪液":
        return "Artificial Tears"
    default:
        return medication.displayName
    }
}

struct MedicationUnitPicker: View {
    let title: String
    @Binding var unit: String

    var body: some View {
        Picker(title, selection: $unit) {
            ForEach(MedicationDoseUnitOption.common) { option in
                Text(option.displayName).tag(option.id)
            }
        }
        .pickerStyle(.menu)
    }
}

struct MedicationIconPicker: View {
    @Binding var symbolName: String

    var body: some View {
        Picker("默认图标", selection: $symbolName) {
            ForEach(MedicationIconOption.common) { option in
                Label(option.displayName, systemImage: option.symbolName)
                    .tag(option.symbolName)
            }
        }
        .pickerStyle(.menu)
    }
}
