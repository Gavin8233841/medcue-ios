import Combine
import MedicationAdherenceCore
import SwiftData
import SwiftUI
import UIKit

struct WeatherMedicationHintCard: View {
    let hint: WeatherMedicationHint

    private var tint: Color {
        switch hint.tintName {
        case "orange":
            .orange
        case "teal":
            .teal
        case "indigo":
            .indigo
        case "yellow":
            .yellow
        case "green":
            .green
        default:
            .blue
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: hint.iconName)
                .font(.title3.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 32, height: 32)
                .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 6) {
                Text(hint.title)
                    .font(.headline)
                Text(hint.message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(hint.sourceSummary)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 6)
    }
}

struct TimelineDoseTaskRow: View {
    let task: StoredDoseTask
    let medication: StoredMedication?
    let completionText: String
    let statusText: String
    let isOpen: Bool
    let feedbackAction: PendingDoseFeedback.Action?
    let isClosing: Bool
    let isRecentlyReopened: Bool
    let confirmationKind: PendingDoseConfirmation.Kind?
    let markTaken: () -> Void
    let delay: () -> Void
    let skip: () -> Void
    let confirm: () -> Void
    let cancelConfirmation: () -> Void

    private var tint: Color {
        switch task.status {
        case .taken, .corrected:
            .green
        case .skipped:
            .orange
        case .delayed:
            .blue
        case .pending:
            .blue
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            timeRail
            VStack(alignment: .leading, spacing: 10) {
                if let medication {
                    NavigationLink {
                        MedicationDetailView(medication: medication)
                    } label: {
                        rowHeader
                    }
                    .buttonStyle(.plain)
                } else {
                    rowHeader
                }

                if isOpen {
                    HStack(spacing: 8) {
                        CompactDoseActionButton(
                            title: completionText,
                            confirmationIconName: "checkmark",
                            tint: TodayDoseActionPalette.primary,
                            isProminent: true,
                            isConfirming: feedbackAction == .taken,
                            action: markTaken
                        )
                        .id("\(task.id.uuidString)-taken")
                        CompactDoseActionButton(
                            title: "稍后",
                            confirmationIconName: "clock",
                            tint: .gray,
                            isProminent: false,
                            isConfirming: feedbackAction == .delay,
                            action: delay
                        )
                        .id("\(task.id.uuidString)-delay")
                        CompactDoseActionButton(
                            title: "忽略",
                            confirmationIconName: "minus.circle",
                            tint: .orange,
                            isProminent: false,
                            isConfirming: feedbackAction == .skip,
                            action: skip
                        )
                        .id("\(task.id.uuidString)-skip")
                    }
                    .padding(.leading, 50)
                    if let confirmationKind {
                        InlineDoseConfirmationCard(
                            kind: confirmationKind,
                            delayDurationText: "\(DoseDelayPolicy.delayMinutes) 分钟",
                            confirm: confirm,
                            cancel: cancelConfirmation
                        )
                        .transition(.asymmetric(
                            insertion: .opacity
                                .combined(with: .move(edge: .top))
                                .combined(with: .scale(scale: 0.98, anchor: .top)),
                            removal: .opacity
                                .combined(with: .scale(scale: 0.98, anchor: .top))
                        ))
                        .padding(.leading, 50)
                    }
                }
            }
            .padding(12)
            .background(rowBackground, in: RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(rowBorder, lineWidth: isRecentlyReopened ? 1.2 : 0.8)
            )
            .shadow(color: Color.black.opacity(isOpen ? 0.045 : 0.025), radius: isOpen ? 7 : 4, x: 0, y: 3)
            .opacity(isClosing ? 0.08 : (isRecentlyReopened ? 0.96 : 1))
            .blur(radius: isClosing ? 4 : 0)
            .scaleEffect(isClosing ? 0.96 : 1)
            .offset(y: isClosing ? 14 : (isRecentlyReopened ? -2 : 0))
            .animation(.snappy(duration: 0.26, extraBounce: 0.03), value: isRecentlyReopened)
            .animation(.easeInOut(duration: 0.18), value: isClosing)
            .animation(.snappy(duration: 0.22, extraBounce: 0.02), value: confirmationKind)
        }
        .padding(.vertical, 4)
        .transition(.asymmetric(
            insertion: .opacity
                .combined(with: .move(edge: .top))
                .combined(with: .scale(scale: 0.985, anchor: .top)),
            removal: .opacity.combined(with: .move(edge: .bottom))
        ))
        .allowsHitTesting(!isClosing)
    }

    private var timeRail: some View {
        VStack(spacing: 6) {
            Text(AppFormatters.time.string(from: task.dueAt))
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 50, height: 26)
                .background(Color(.secondarySystemGroupedBackground), in: Capsule())
            Capsule()
                .fill(tint.opacity(isOpen ? 0.22 : 0.14))
                .frame(width: 2)
                .frame(maxHeight: .infinity)
        }
        .frame(width: 52)
        .frame(minHeight: isOpen ? (confirmationKind == nil ? 106 : 172) : 84, alignment: .top)
    }

    private var rowBackground: Color {
        if isRecentlyReopened {
            return Color.blue.opacity(0.12)
        }
        return Color(.secondarySystemGroupedBackground)
    }

    private var rowBorder: Color {
        if isRecentlyReopened {
            return Color.blue.opacity(0.34)
        }
        return Color.primary.opacity(0.045)
    }

    private var rowHeader: some View {
        HStack(alignment: .center, spacing: 10) {
            MedicationPhotoView(
                photoData: medication?.photoData,
                symbolName: medication?.photoSymbolName ?? "pills.fill",
                tint: medication.map(medicationColor(for:)) ?? tint,
                size: 40
            )
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 7) {
                    if let medication {
                        MedicationColorMarker(color: medicationColor(for: medication), size: 8)
                    }
                    Text(medication.map(userFacingMedicationName(for:)) ?? "未知药品")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.86)
                }
                Text("\(task.doseValue.formatted()) \(localizedMedicationUnit(task.doseUnit))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            StatusBadge(text: statusText, color: tint)
        }
    }
}

struct InlineDoseConfirmationCard: View {
    let kind: PendingDoseConfirmation.Kind
    let delayDurationText: String
    let confirm: () -> Void
    let cancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 9) {
                Image(systemName: kind.iconName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(kind.tint)
                    .frame(width: 24, height: 24)
                    .background(kind.tint.opacity(0.12), in: Circle())

                VStack(alignment: .leading, spacing: 3) {
                    Text(kind.title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(kind.message(delayDurationText: delayDurationText))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            HStack(spacing: 8) {
                Button("取消", action: cancel)
                    .font(.caption.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 30)
                    .foregroundStyle(.secondary)
                    .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8))

                Button(kind.confirmTitle, action: confirm)
                    .font(.caption.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 30)
                    .foregroundStyle(.white)
                    .background(kind.tint, in: RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
        }
        .padding(10)
        .background(kind.tint.opacity(0.07), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(kind.tint.opacity(0.16), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
    }
}

struct OpenDoseSummaryRow: View {
    let count: Int
    let latestText: String
    let isReceiving: Bool
    let migrationSnapshot: DoseMigrationSnapshot?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Image(systemName: "tray.and.arrow.up.fill")
                    .font(.title3)
                    .foregroundStyle(.blue)
                    .frame(width: 30, height: 30)
                    .background(Color.blue.opacity(isReceiving ? 0.18 : 0.12), in: Circle())
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(count) 条待处理")
                        .font(.headline)
                    Text(latestText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
            }
            if let migrationSnapshot {
                DoseMigrationPill(snapshot: migrationSnapshot, tint: .blue)
                    .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .leading)))
            }
        }
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.blue.opacity(isReceiving ? 0.08 : 0))
        )
        .scaleEffect(isReceiving ? 1.01 : 1)
        .animation(.easeInOut(duration: 0.18), value: isReceiving)
        .accessibilityElement(children: .combine)
    }
}

struct HandledDoseSummaryRow: View {
    let count: Int
    let latestText: String
    let isReceiving: Bool
    let migrationSnapshot: DoseMigrationSnapshot?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.green)
                    .frame(width: 30, height: 30)
                    .background(Color.green.opacity(isReceiving ? 0.18 : 0.12), in: Circle())
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(count) 条已处理")
                        .font(.headline)
                    Text(latestText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
            }
            if let migrationSnapshot {
                DoseMigrationPill(snapshot: migrationSnapshot, tint: .green)
                    .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .leading)))
            }
        }
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.green.opacity(isReceiving ? 0.08 : 0))
        )
        .scaleEffect(isReceiving ? 1.01 : 1)
        .animation(.easeInOut(duration: 0.18), value: isReceiving)
        .accessibilityElement(children: .combine)
    }
}

struct DoseMigrationPill: View {
    let snapshot: DoseMigrationSnapshot
    let tint: Color

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: snapshot.symbolName)
                .font(.caption.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 22, height: 22)
                .background(tint.opacity(0.14), in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(snapshot.medicationName)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
                Text("\(snapshot.timeText) · \(snapshot.doseText)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Text(snapshot.statusText)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(tint)
                .lineLimit(1)
        }
        .frame(height: 40)
        .padding(.horizontal, 8)
        .background(tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(tint.opacity(0.12), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
    }
}

struct HandledDoseTaskRow: View {
    let task: StoredDoseTask
    let medication: StoredMedication?
    let statusText: String
    let undo: () -> Void
    let archive: () -> Void

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
        HStack(alignment: .center, spacing: 10) {
            Text(AppFormatters.time.string(from: task.dueAt))
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 46, height: 26)
                .background(Color(.tertiarySystemGroupedBackground), in: Capsule())
            MedicationPhotoView(
                photoData: medication?.photoData,
                symbolName: medication?.photoSymbolName ?? "pills.fill",
                tint: medication.map(medicationColor(for:)) ?? tint,
                size: 34
            )
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 7) {
                    if let medication {
                        MedicationColorMarker(color: medicationColor(for: medication), size: 8)
                    }
                    Text(medication.map(userFacingMedicationName(for:)) ?? "未知药品")
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                }
                Text("\(task.doseValue.formatted()) \(localizedMedicationUnit(task.doseUnit))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            StatusBadge(text: statusText, color: tint)
            Button("撤销") {
                undo()
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.orange)
            .buttonStyle(.borderless)
            .accessibilityLabel("撤销\(medication.map(userFacingMedicationName(for:)) ?? "这条记录")")
        }
        .padding(.vertical, 7)
        .contentShape(Rectangle())
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button {
                undo()
            } label: {
                Label("撤销", systemImage: "arrow.uturn.backward")
            }
            .tint(.orange)

            Button {
                archive()
            } label: {
                Label("归档", systemImage: "archivebox")
            }
            .tint(.gray)
        }
    }
}

struct CompactDoseActionButton: View {
    let title: String
    let confirmationIconName: String
    let tint: Color
    let isProminent: Bool
    let isConfirming: Bool
    let action: () -> Void

    var body: some View {
        Button {
            action()
        } label: {
            ZStack {
                Text(title)
                    .opacity(isConfirming ? 0 : 1)
                    .blur(radius: isConfirming ? 3 : 0)
                    .scaleEffect(isConfirming ? 0.94 : 1)
                Image(systemName: confirmationIconName)
                    .font(.caption.weight(.bold))
                    .opacity(isConfirming ? 1 : 0)
                    .blur(radius: isConfirming ? 0 : 2)
                    .scaleEffect(isConfirming ? 1 : 0.86)
            }
            .font(.caption.weight(.semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.9)
            .frame(maxWidth: .infinity)
            .frame(height: 36)
            .foregroundStyle(isProminent ? TodayDoseActionPalette.primaryText : tint)
            .background(background, in: RoundedRectangle(cornerRadius: 8))
            .animation(.easeInOut(duration: 0.16), value: isConfirming)
        }
        .buttonStyle(CompactDoseActionButtonStyle())
        .disabled(isConfirming)
        .accessibilityLabel(title)
    }

    private var background: Color {
        if isProminent {
            return tint
        }
        return tint.opacity(tint == .gray ? 0.14 : 0.16)
    }
}

struct CompactDoseActionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.78 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
