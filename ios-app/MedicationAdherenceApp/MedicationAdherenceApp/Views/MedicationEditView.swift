import Charts
import MedicationAdherenceCore
import PhotosUI
import SwiftData
import SwiftUI
import UIKit

struct EditMedicationView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    let medication: StoredMedication
    private let preservedHiddenNotes: String?
    @State private var displayName: String
    @State private var genericName: String
    @State private var strength: String
    @State private var form: String
    @State private var kind: MedicationKind
    @State private var photoData: Data?
    @State private var photoSymbolName: String
    @State private var selectedMedicationPhotoItem: PhotosPickerItem?
    @State private var colorTagRaw: String
    @State private var boxNumber: String
    @State private var notes: String

    init(medication: StoredMedication) {
        self.medication = medication
        preservedHiddenNotes = MedicationNotesDisplayPolicy.hiddenText(from: medication.notes)
        _displayName = State(initialValue: MedicationNamePolicy.normalizedDisplayName(medication.displayName) ?? "")
        _genericName = State(initialValue: medication.genericName)
        _strength = State(initialValue: medication.strength)
        _form = State(initialValue: medication.form)
        _kind = State(initialValue: MedicationKind(rawValue: medication.kindRaw) ?? .unknown)
        _photoData = State(initialValue: medication.photoData)
        _photoSymbolName = State(initialValue: medication.photoSymbolName)
        _colorTagRaw = State(initialValue: MedicationColorOption.resolved(for: medication).id)
        _boxNumber = State(initialValue: medication.boxNumber)
        _notes = State(initialValue: MedicationNotesDisplayPolicy.visibleText(from: medication.notes) ?? "")
    }

    var body: some View {
        let hasPhoto = photoData != nil

        NavigationStack {
            Form {
                Section("药品信息") {
                    TextField("药品名称", text: $displayName)
                    if displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && medicationNeedsNameReview(medication) {
                        Text("原药名无法核对，请补全真实药品名称。")
                            .font(.footnote)
                            .foregroundStyle(.orange)
                    } else if !displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !hasMeaningfulDisplayName {
                        Text("请输入可核对的药品名称。")
                            .font(.footnote)
                            .foregroundStyle(.orange)
                    }
                    TextField("通用名（可选）", text: $genericName)
                    TextField("规格", text: $strength)
                    TextField("剂型", text: $form)
                    Picker("类型", selection: $kind) {
                        Text("非处方药").tag(MedicationKind.overTheCounter)
                        Text("处方药").tag(MedicationKind.prescription)
                        Text("待确认").tag(MedicationKind.unknown)
                    }
                }

                Section("颜色标识") {
                    MedicationColorSelectionGrid(selection: $colorTagRaw)
                }

                Section("药盒照片与编号") {
                    TextField("药盒编号，例如 A1", text: $boxNumber)
                        .textInputAutocapitalization(.characters)
                    MedicationHeroPhotoView(
                        photoData: photoData,
                        symbolName: photoSymbolName,
                        tint: selectedMedicationColor,
                        title: photoData == nil ? "添加药盒或药品照片" : "药盒或药品照片",
                        subtitle: boxNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "用于提醒和记录核对。" : "药盒编号已记录。",
                        boxNumber: boxNumber
                    )
                    PhotosPicker(selection: $selectedMedicationPhotoItem, matching: .images) {
                        Label(hasPhoto ? "更换照片" : "选择照片", systemImage: "photo")
                    }
                    if hasPhoto {
                        Button("清除当前图片") {
                            photoData = nil
                            selectedMedicationPhotoItem = nil
                        }
                    }
                }

                Section("备注") {
                    TextEditor(text: $notes)
                        .frame(minHeight: 120)
                }
            }
            .navigationTitle("修改药品")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        let outcome = MedicationProfileCommand(modelContext: modelContext).update(
                            MedicationProfileUpdate(
                                medicationID: medication.id,
                                displayName: displayName,
                                genericName: genericName,
                                strength: strength,
                                form: form,
                                kind: kind,
                                photoData: photoData,
                                photoSymbolName: photoSymbolName,
                                colorTagRaw: colorTagRaw,
                                boxNumber: boxNumber,
                                notes: MedicationNotesDisplayPolicy.mergedNotes(
                                    visibleText: notes,
                                    hiddenText: preservedHiddenNotes
                                )
                            )
                        )
                        guard case .committed = outcome else {
                            return
                        }
                        dismiss()
                    }
                    .disabled(!hasMeaningfulDisplayName)
                    .accessibilityIdentifier(AppAccessibilityID.medicationEditSave)
                }
            }
            .onChange(of: selectedMedicationPhotoItem) { _, newItem in
                Task {
                    await loadMedicationPhoto(newItem)
                }
            }
        }
    }

    private func loadMedicationPhoto(_ item: PhotosPickerItem?) async {
        guard let item else {
            return
        }
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                return
            }
            photoData = normalizedPhotoData(data)
        } catch {
            photoData = nil
        }
    }

    private var hasMeaningfulDisplayName: Bool {
        MedicationNamePolicy.normalizedDisplayName(displayName) != nil
    }

    private var selectedMedicationColor: Color {
        MedicationColorOption.option(forRawValue: colorTagRaw)?.color ?? MedicationColorOption.common[0].color
    }
}

struct MedicationColorSelectionGrid: View {
    @Binding var selection: String

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 10)], spacing: 10) {
            ForEach(MedicationColorOption.common) { option in
                Button {
                    selection = option.id
                } label: {
                    HStack(spacing: 8) {
                        MedicationColorMarker(color: option.color, size: 13)
                        Text(option.displayName)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.primary)
                        Spacer(minLength: 0)
                        if selection == option.id {
                            Image(systemName: "checkmark")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(option.color)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(option.color.opacity(selection == option.id ? 0.15 : 0.08), in: RoundedRectangle(cornerRadius: 8))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(option.color.opacity(selection == option.id ? 0.38 : 0.14), lineWidth: 1)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("颜色标识 \(option.displayName)")
                .accessibilityAddTraits(selection == option.id ? .isSelected : [])
            }
        }
        .padding(.vertical, 4)
    }
}

struct MedicationAddSelection: Identifiable {
    var option: MedicationAddOption
    var id: String { option.id.rawValue }
}

func addOptionTitle(_ option: MedicationAddOption) -> String {
    option.title
}

func addOptionSubtitle(_ option: MedicationAddOption) -> String {
    switch option.id {
    case .manual:
        "逐项填写药名、剂量、疗程和提醒。"
    case .prescriptionDocumentOCR:
        "识别医嘱图片后生成待确认信息。"
    case .barcodeScan:
        "扫描或输入药盒条码，保存前再核对药盒信息。"
    }
}

func addOptionIconName(_ option: MedicationAddOption) -> String {
    switch option.id {
    case .manual:
        "square.and.pencil"
    case .prescriptionDocumentOCR:
        "doc.viewfinder"
    case .barcodeScan:
        "barcode.viewfinder"
    }
}

func badgeColor(for status: StoredMedicationLifecycleStatus) -> Color {
    switch status {
    case .active:
        .green
    case .interrupted:
        .orange
    case .archived:
        .gray
    }
}

func trendStateTitle(_ state: AdherenceTrendState) -> String {
    switch state {
    case .insufficientData:
        "数据不足"
    case .improving:
        "正在改善"
    case .stable:
        "趋势平稳"
    case .declining:
        "需要关注"
    }
}

func trendTint(_ state: AdherenceTrendState) -> Color {
    switch state {
    case .insufficientData:
        .gray
    case .improving:
        .green
    case .stable:
        .blue
    case .declining:
        .orange
    }
}

func trendIconName(_ state: AdherenceTrendState) -> String {
    switch state {
    case .insufficientData:
        "chart.bar.xaxis"
    case .improving:
        "chart.line.uptrend.xyaxis"
    case .stable:
        "equal.circle.fill"
    case .declining:
        "chart.line.downtrend.xyaxis"
    }
}

func percentageText(_ value: Double) -> String {
    "\(Int((value * 100).rounded()))"
}

func trendChangeText(_ value: Double) -> String {
    let points = Int((abs(value) * 100).rounded())
    if value > 0 {
        return "上升 \(points) 个百分点"
    }
    if value < 0 {
        return "下降 \(points) 个百分点"
    }
    return "无明显变化"
}

func stockRemainingText(_ projection: MedicationStockProjection) -> String {
    let remaining = "\(formatDecimal(projection.projectedRemainingQuantity)) \(localizedMedicationUnit(projection.unit))"
    if let days = projection.estimatedDaysRemaining {
        return "估算剩余 \(remaining) · 约 \(days) 天"
    }
    return "估算剩余 \(remaining)"
}

func formatDecimal(_ value: Decimal) -> String {
    let number = NSDecimalNumber(decimal: value)
    let formatter = NumberFormatter()
    formatter.minimumFractionDigits = 0
    formatter.maximumFractionDigits = 2
    return formatter.string(from: number) ?? "\(value)"
}

func courseSummary(for plan: StoredMedicationPlan) -> String {
    let start = plan.courseStartAt.map { AppFormatters.day.string(from: $0) } ?? "未填写开始日期"
    let end = plan.courseEndAt.map { AppFormatters.day.string(from: $0) } ?? "未设置结束日期"
    return "\(start) 至 \(end)"
}

func reminderSummary(for plan: StoredMedicationPlan, tasks: [StoredDoseTask]) -> String {
    reminderSummary(from: reminderDates(for: plan, tasks: tasks.filter { $0.planID == plan.id }))
}

func reminderDates(for plan: StoredMedicationPlan?, tasks: [StoredDoseTask]) -> [Date] {
    let storedDates = plan?.reminderTimesRaw?
        .split(separator: ",")
        .compactMap { reminderDate(from: String($0)) } ?? []
    if !storedDates.isEmpty {
        return normalizedReminderDates(storedDates)
    }
    let taskDates = tasks.map(\.dueAt)
    if !taskDates.isEmpty {
        return normalizedReminderDates(taskDates)
    }
    return [defaultReminderDate(hour: 21, minute: 0)]
}

func reminderSummary(from dates: [Date]) -> String {
    let times = normalizedReminderDates(dates).map { AppFormatters.time.string(from: $0) }
    guard !times.isEmpty else {
        return "未设置提醒时间"
    }
    return "每日 " + times.joined(separator: "、")
}

func encodedReminderTimes(_ dates: [Date]) -> String {
    normalizedReminderDates(dates)
        .map { AppFormatters.time.string(from: $0) }
        .joined(separator: ",")
}

func normalizedReminderDates(_ dates: [Date]) -> [Date] {
    var seen: Set<String> = []
    return dates
        .map { defaultReminderDate(hour: Calendar.current.component(.hour, from: $0), minute: Calendar.current.component(.minute, from: $0)) }
        .sorted { $0 < $1 }
        .filter { date in
            let key = AppFormatters.time.string(from: date)
            if seen.contains(key) {
                return false
            }
            seen.insert(key)
            return true
        }
}

func reminderDate(from rawValue: String) -> Date? {
    let parts = rawValue.split(separator: ":")
    guard parts.count == 2, let hour = Int(parts[0]), let minute = Int(parts[1]) else {
        return nil
    }
    return defaultReminderDate(hour: hour, minute: minute)
}

func defaultReminderDate(hour: Int, minute: Int) -> Date {
    Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: Date()) ?? Date()
}

func medicationDoseChangeEffectiveUntil(
    _ change: StoredMedicationDoseChange,
    in changes: [StoredMedicationDoseChange]
) -> Date? {
    let calendar = Calendar.current
    let currentStart = calendar.startOfDay(for: change.effectiveFrom)
    let nextChange = changes
        .filter {
            $0.id != change.id
                && $0.medicationID == change.medicationID
                && medicationDoseChangePlanMatches($0, change)
                && $0.effectiveFrom > change.effectiveFrom
        }
        .min { $0.effectiveFrom < $1.effectiveFrom }

    guard let nextStart = nextChange.map({ calendar.startOfDay(for: $0.effectiveFrom) }) else {
        return nil
    }
    guard nextStart > currentStart else {
        return currentStart
    }
    return calendar.date(byAdding: .day, value: -1, to: nextStart)
}

func medicationDoseChangePlanMatches(_ first: StoredMedicationDoseChange, _ second: StoredMedicationDoseChange) -> Bool {
    guard let firstPlanID = first.planID, let secondPlanID = second.planID else {
        return true
    }
    return firstPlanID == secondPlanID
}

func medicationDoseChangeEffectivePeriodText(change: StoredMedicationDoseChange, effectiveUntil: Date?) -> String {
    let startText = AppFormatters.day.string(from: change.effectiveFrom)
    guard let effectiveUntil else {
        return "生效阶段：\(startText) 至今"
    }
    if Calendar.current.isDate(effectiveUntil, inSameDayAs: change.effectiveFrom) {
        return "生效阶段：\(startText) 当天，之后有新的剂量记录"
    }
    return "生效阶段：\(startText) 至 \(AppFormatters.day.string(from: effectiveUntil))"
}

func scheduledDate(on day: Date, matching time: Date) -> Date {
    let calendar = Calendar.current
    let dateComponents = calendar.dateComponents([.year, .month, .day], from: day)
    let timeComponents = calendar.dateComponents([.hour, .minute], from: time)
    var merged = DateComponents()
    merged.year = dateComponents.year
    merged.month = dateComponents.month
    merged.day = dateComponents.day
    merged.hour = timeComponents.hour
    merged.minute = timeComponents.minute
    merged.second = 0
    return calendar.date(from: merged) ?? time
}

func normalizedPhotoData(_ data: Data) -> Data {
    guard let image = UIImage(data: data) else {
        return data
    }
    return normalizedPhotoData(image) ?? data
}

func normalizedPhotoData(_ image: UIImage) -> Data? {
    let maxSide: CGFloat = 900
    let width = image.size.width
    let height = image.size.height
    let scale = min(1, maxSide / max(width, height))
    let outputImage: UIImage
    if scale < 1 {
        let size = CGSize(width: width * scale, height: height * scale)
        outputImage = UIGraphicsImageRenderer(size: size).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    } else {
        outputImage = image
    }
    return outputImage.jpegData(compressionQuality: 0.82)
}
