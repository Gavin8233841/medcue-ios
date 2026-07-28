import Combine
import MedicationAdherenceCore
import SwiftData
import SwiftUI
import UIKit

enum TodayDoseActionPalette {
    static let primary = Color(red: 0.82, green: 0.94, blue: 0.99)
    static let primaryText = Color(red: 0.12, green: 0.38, blue: 0.56)
}

struct ArchivedDoseTaskRow: View {
    let task: StoredDoseTask
    let medication: StoredMedication?
    let statusText: String
    let restore: () -> Void
    let reopen: () -> Void

    private var tint: Color {
        switch task.status {
        case .taken, .corrected:
            .green
        case .skipped:
            .orange
        case .pending, .delayed:
            .blue
        }
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            MedicationPhotoView(
                photoData: medication?.photoData,
                symbolName: medication?.photoSymbolName ?? "pills.fill",
                tint: medication.map(medicationColor(for:)) ?? tint,
                size: 40
            )
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 7) {
                    if let medication {
                        MedicationColorMarker(color: medicationColor(for: medication), size: 8)
                    }
                    Text(medication.map(userFacingMedicationName(for:)) ?? "未知药品")
                        .font(.subheadline.weight(.semibold))
                }
                Text("\(AppFormatters.time.string(from: task.dueAt)) · \(task.doseValue.formatted()) \(localizedMedicationUnit(task.doseUnit))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                StatusBadge(text: statusText, color: tint)
            }
            Spacer()
            Button("恢复") {
                restore()
            }
            .font(.caption.weight(.semibold))
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(.vertical, 6)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button {
                restore()
            } label: {
                Label("恢复", systemImage: "tray.and.arrow.up")
            }
            .tint(.blue)

            Button {
                reopen()
            } label: {
                Label("撤销", systemImage: "arrow.uturn.backward")
            }
            .tint(.orange)
        }
    }
}

struct DoseTaskRow: View {
    let task: StoredDoseTask
    let medication: StoredMedication?
    let completionText: String
    let markTaken: () -> Void
    let delay: () -> Void
    let skip: () -> Void
    let undo: () -> Void
    let undoLog: StoredDoseActionLog?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let medication {
                NavigationLink {
                    MedicationDetailView(medication: medication)
                } label: {
                    DoseTaskHeader(task: task, medication: medication)
                }
            } else {
                HStack(alignment: .top, spacing: 14) {
                    MedicationPhotoView(photoData: nil, symbolName: "pills.fill", tint: .blue)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("未知药品")
                            .font(.headline)
                        Text("\(task.doseValue.formatted()) \(localizedMedicationUnit(task.doseUnit)) · \(AppFormatters.time.string(from: task.dueAt))")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        StatusBadge(text: task.status.displayName, color: .orange)
                    }
                    Spacer()
                }
            }

            HStack(spacing: 10) {
                Button(action: markTaken) {
                    Label(completionText, systemImage: "checkmark")
                }
                .buttonStyle(.borderedProminent)
                .tint(TodayDoseActionPalette.primary)
                Button(action: delay) {
                    Label("稍后", systemImage: "clock")
                }
                .buttonStyle(.bordered)
                Button(action: skip) {
                    Label("忽略", systemImage: "minus.circle")
                }
                .buttonStyle(.bordered)
                .tint(.orange)
                if undoLog != nil {
                    Button(action: undo) {
                        Label("撤销", systemImage: "arrow.uturn.backward")
                    }
                    .buttonStyle(.bordered)
                }
            }
            .controlSize(.large)
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
    }
}

struct DoseTaskHeader: View {
    let task: StoredDoseTask
    let medication: StoredMedication

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            MedicationPhotoView(photoData: medication.photoData, symbolName: medication.photoSymbolName, tint: medicationColor(for: medication))
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    MedicationColorMarker(color: medicationColor(for: medication), size: 9)
                    Text(userFacingMedicationName(for: medication))
                        .font(.headline)
                }
                if medicationNeedsNameReview(medication) {
                    Text("药名待补全")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.orange)
                }
                Text("\(task.doseValue.formatted()) \(localizedMedicationUnit(task.doseUnit)) · \(AppFormatters.time.string(from: task.dueAt))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                StatusBadge(text: task.status.displayName, color: task.status == .taken ? .green : .orange)
            }
            Spacer()
        }
    }
}

struct ResolvedDoseTaskRow: View {
    let task: StoredDoseTask
    let medication: StoredMedication?
    let undoLog: StoredDoseActionLog?
    let statusText: String
    let reopen: () -> Void
    let archive: () -> Void
    let showDetail: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            MedicationPhotoView(
                photoData: medication?.photoData,
                symbolName: medication?.photoSymbolName ?? "pills.fill",
                tint: medication.map(medicationColor(for:)) ?? (task.status == .taken || task.status == .corrected ? .green : .orange),
                size: 44
            )
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    if let medication {
                        MedicationColorMarker(color: medicationColor(for: medication), size: 9)
                    }
                    Text(medication.map(userFacingMedicationName(for:)) ?? "未知药品")
                        .font(.headline)
                }
                Text("\(task.doseValue.formatted()) \(localizedMedicationUnit(task.doseUnit)) · \(AppFormatters.time.string(from: task.dueAt))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            StatusBadge(text: statusText, color: task.status == .taken || task.status == .corrected ? .green : .orange)
        }
        .padding(.vertical, 6)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(action: reopen) {
                Label("撤销", systemImage: "arrow.uturn.backward")
            }
            .tint(.orange)

            Button(action: archive) {
                Label("归档", systemImage: "archivebox")
            }
            .tint(.gray)

            Button(action: showDetail) {
                Label("详情", systemImage: "info.circle")
            }
            .tint(.blue)
        }
    }
}
