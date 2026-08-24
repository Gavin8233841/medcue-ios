import Charts
import MedicationAdherenceCore
import PhotosUI
import SwiftData
import SwiftUI
import UIKit

struct PlanEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @StateObject private var notificationService = NotificationService()
    let medication: StoredMedication
    let plan: StoredMedicationPlan?
    let tasks: [StoredDoseTask]
    let doseChanges: [StoredMedicationDoseChange]
    @State private var doseValue: Double
    @State private var doseUnit: String
    @State private var doseEffectiveFrom: Date
    @State private var doseChangeNote: String
    @State private var courseStartDate: Date
    @State private var hasCourseEndDate: Bool
    @State private var courseEndDate: Date
    @State private var reminderTimes: [Date]
    @State private var reminderDeliveryMethod: StoredReminderDeliveryMethod
    @State private var escalatesToAlarmWhenUnhandled: Bool
    @State private var sourceNote: String
    @State private var pendingPermissionGate: AppPermissionGate?
    @State private var shouldSaveAfterPermissionGrant = false
    @State private var permissionStatusMessage = ""
    @State private var isSaveFlowActive = false

    init(
        medication: StoredMedication,
        plan: StoredMedicationPlan?,
        tasks: [StoredDoseTask],
        doseChanges: [StoredMedicationDoseChange]
    ) {
        self.medication = medication
        self.plan = plan
        self.tasks = tasks
        self.doseChanges = doseChanges
        let planTasks = plan.map { selectedPlan in tasks.filter { $0.planID == selectedPlan.id } } ?? tasks
        let now = Date()
        let startDate = plan?.courseStartAt ?? planTasks.first?.dueAt ?? now
        let endDate = plan?.courseEndAt ?? Calendar.current.date(byAdding: .day, value: 30, to: startDate) ?? startDate
        _doseValue = State(initialValue: plan?.doseValue ?? planTasks.first?.doseValue ?? 1)
        _doseUnit = State(initialValue: localizedMedicationUnit(plan?.doseUnit ?? planTasks.first?.doseUnit ?? "片"))
        _doseEffectiveFrom = State(initialValue: Calendar.current.startOfDay(for: plan == nil ? startDate : now))
        _doseChangeNote = State(initialValue: "")
        _courseStartDate = State(initialValue: startDate)
        _hasCourseEndDate = State(initialValue: plan?.courseEndAt != nil)
        _courseEndDate = State(initialValue: endDate)
        _reminderTimes = State(initialValue: reminderDates(for: plan, tasks: planTasks))
        _reminderDeliveryMethod = State(initialValue: plan?.reminderDeliveryMethod ?? .notification)
        _escalatesToAlarmWhenUnhandled = State(initialValue: plan?.escalatesToAlarmWhenUnhandled ?? true)
        _sourceNote = State(initialValue: userVisiblePlanSourceNote(plan?.sourceNote ?? "") ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(userFacingMedicationName(for: medication)) {
                    Stepper(value: $doseValue, in: 0.5...20, step: 0.5) {
                        Text("每次 \(doseValue.formatted()) \(localizedMedicationUnit(doseUnit))")
                    }
                    .accessibilityIdentifier(AppAccessibilityID.medicationPlanDoseValue)
                    MedicationUnitPicker(title: "剂量单位", unit: $doseUnit)
                        .accessibilityIdentifier(AppAccessibilityID.medicationPlanDoseUnit)
                    DatePicker("剂量生效日期", selection: $doseEffectiveFrom, displayedComponents: .date)
                    Text("仅记录剂量变化时间，不生成医疗建议。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("疗程") {
                    DatePicker("开始日期", selection: $courseStartDate, displayedComponents: .date)
                    Toggle("设置结束日期", isOn: $hasCourseEndDate)
                    if hasCourseEndDate {
                        DatePicker("结束日期", selection: $courseEndDate, in: courseStartDate..., displayedComponents: .date)
                    }
                }

                Section("提醒时间") {
                    ReminderTimesEditor(reminderTimes: $reminderTimes)
                    Picker("提醒方式", selection: $reminderDeliveryMethod) {
                        ForEach(StoredReminderDeliveryMethod.allCases) { method in
                            Text(method.displayName).tag(method)
                        }
                    }
                    Text(reminderDeliveryMethod.detailText)
                        .font(.footnote)
                        .foregroundStyle(reminderDeliveryMethod == .alarm ? .orange : .secondary)
                    Toggle("未处理时使用 iPhone 闹钟再提醒", isOn: $escalatesToAlarmWhenUnhandled)
                    Text("普通提醒 5 分钟内未处理时，可用 iPhone 闹钟加强提醒；关闭后只保留普通提醒。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    if !permissionStatusMessage.isEmpty {
                        Text(permissionStatusMessage)
                            .font(.footnote)
                            .foregroundStyle(.orange)
                    }
                }

                Section("备注（可选）") {
                    TextEditor(text: $sourceNote)
                        .frame(minHeight: 90)
                    Text("可以记录医生、药师或复诊时调整提醒的原因。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("剂量变化备注") {
                    TextEditor(text: $doseChangeNote)
                        .frame(minHeight: 70)
                    Text("可记录复诊调整或规格变化原因。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("疗程与提醒")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        beginSaveFlow()
                    }
                    .disabled(
                        isSaveFlowActive
                            || doseUnit.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            || reminderTimes.isEmpty
                    )
                    .accessibilityIdentifier(AppAccessibilityID.medicationPlanSave)
                }
            }
            .appPermissionPrimer(pendingGate: $pendingPermissionGate) { gate in
                Task {
                    await continuePlanSaveAfterPermissionPrimer(gate)
                }
            }
        }
    }

    private func beginSaveFlow() {
        guard !isSaveFlowActive else {
            return
        }
        isSaveFlowActive = true
        Task {
            await saveAfterPermissionCheck()
        }
    }

    @MainActor
    private func saveAfterPermissionCheck() async {
        permissionStatusMessage = ""
        shouldSaveAfterPermissionGrant = true
        guard await ensureReminderPermissionForSave() else {
            if pendingPermissionGate == nil {
                shouldSaveAfterPermissionGrant = false
                isSaveFlowActive = false
            }
            return
        }
        guard await ensureEscalationAlarmPermissionForSave() else {
            if pendingPermissionGate == nil {
                shouldSaveAfterPermissionGrant = false
                isSaveFlowActive = false
            }
            return
        }
        shouldSaveAfterPermissionGrant = false
        save()
    }

    @MainActor
    private func ensureReminderPermissionForSave() async -> Bool {
        if AppPermissionGate.isUITestDeterministicMode {
            AppPermissionGate.markAuthorizationCompleted(for: .notifications)
            return true
        }
        switch reminderDeliveryMethod {
        case .notification:
            if await notificationService.hasUsableNotificationAuthorization() {
                AppPermissionGate.markAuthorizationCompleted(for: .notifications)
                return true
            }
            if AppPermissionGate.hasCompletedAuthorization(for: .notifications) {
                return await requestReminderPermissionForSave(.notifications)
            }
            pendingPermissionGate = .notifications
            return false
        case .alarm:
            if AppPermissionGate.isAlarmAuthorized() {
                AppPermissionGate.markAuthorizationCompleted(for: .alarm)
                return true
            }
            if AppPermissionGate.hasCompletedAuthorization(for: .alarm) {
                return await requestReminderPermissionForSave(.alarm)
            }
            pendingPermissionGate = .alarm
            return false
        }
    }

    @MainActor
    private func ensureEscalationAlarmPermissionForSave() async -> Bool {
        if AppPermissionGate.isUITestDeterministicMode {
            AppPermissionGate.markAuthorizationCompleted(for: .alarm)
            return true
        }
        guard escalatesToAlarmWhenUnhandled,
              reminderDeliveryMethod == .notification
        else {
            return true
        }
        if AppPermissionGate.isAlarmAuthorized() {
            AppPermissionGate.markAuthorizationCompleted(for: .alarm)
            return true
        }
        if AppPermissionGate.hasCompletedAuthorization(for: .alarm) {
            return await requestReminderPermissionForSave(.alarm)
        }
        pendingPermissionGate = .alarm
        return false
    }

    @MainActor
    private func requestReminderPermissionForSave(_ gate: AppPermissionGate) async -> Bool {
        switch gate {
        case .notifications:
            let granted = await notificationService.requestAuthorization()
            if granted {
                AppPermissionGate.markAuthorizationCompleted(for: .notifications)
            } else {
                permissionStatusMessage = "通知权限未开启，暂不能保存为推送提醒。"
            }
            return granted
        case .alarm:
            let granted = await AppPermissionGate.requestAlarmAccess()
            if granted {
                AppPermissionGate.markAuthorizationCompleted(for: .alarm)
            } else {
                permissionStatusMessage = "iPhone 闹钟权限未开启，暂不能保存为闹钟提醒。"
            }
            return granted
        case .camera, .health, .location:
            return false
        }
    }

    @MainActor
    private func continuePlanSaveAfterPermissionPrimer(_ gate: AppPermissionGate) async {
        guard gate == .notifications || gate == .alarm,
              shouldSaveAfterPermissionGrant
        else {
            return
        }
        guard await requestReminderPermissionForSave(gate) else {
            shouldSaveAfterPermissionGrant = false
            isSaveFlowActive = false
            return
        }
        await saveAfterPermissionCheck()
    }

    private func save() {
        let outcome = MedicationPlanCommand(modelContext: modelContext).update(
            MedicationPlanUpdate(
                medicationID: medication.id,
                planID: plan?.id,
                doseValue: doseValue,
                doseUnit: localizedMedicationUnit(doseUnit),
                doseEffectiveFrom: doseEffectiveFrom,
                doseChangeNote: doseChangeNote,
                courseStartAt: courseStartDate,
                courseEndAt: hasCourseEndDate ? courseEndDate : nil,
                reminderTimes: reminderTimes,
                reminderDeliveryMethod: reminderDeliveryMethod,
                escalatesToAlarmWhenUnhandled: escalatesToAlarmWhenUnhandled,
                sourceNote: storedPlanSourceNote(from: sourceNote)
            )
        )

        switch outcome {
        case let .committed(_, _, reminderBatch):
            let schedulingSnapshot = MedicationReminderPostCommitSnapshot(batch: reminderBatch)
            dismiss()
            MedicationReminderPostCommitDispatcher.dispatch(schedulingSnapshot)
        case .rejected:
            permissionStatusMessage = "疗程与提醒未能保存，请检查填写内容后重试。"
            isSaveFlowActive = false
        case .saveFailed:
            permissionStatusMessage = AppPersistenceCommitter.failureUserMessage
            isSaveFlowActive = false
        }
    }

}

struct MedicationPresetTextField: View {
    let title: String
    let placeholder: String
    let presets: [String]
    let accessibilityIdentifier: String
    @Binding var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 44, alignment: .leading)

                TextField(placeholder, text: $text)
                    .textInputAutocapitalization(.never)
                    .multilineTextAlignment(.leading)
                    .accessibilityIdentifier(accessibilityIdentifier)

                Menu {
                    Button("清空") {
                        text = ""
                    }
                    ForEach(presets, id: \.self) { preset in
                        Button(preset) {
                            text = preset
                        }
                    }
                } label: {
                    Image(systemName: "chevron.down.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("选择\(title)")
                }
            }
        }
        .padding(.vertical, 2)
    }
}

struct MedicationFormAndUnitRow: View {
    let title: String
    let placeholder: String
    let presets: [String]
    @Binding var form: String
    @Binding var unit: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 72, alignment: .leading)

                TextField(placeholder, text: $form)
                    .textInputAutocapitalization(.never)
                    .multilineTextAlignment(.leading)

                Menu {
                    Button("清空形态") {
                        form = ""
                    }
                    ForEach(presets, id: \.self) { preset in
                        Button(preset) {
                            form = preset
                        }
                    }
                } label: {
                    Image(systemName: "chevron.down.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("选择药品形态")
                }

                Divider()
                    .frame(height: 22)

                Menu {
                    ForEach(MedicationDoseUnitOption.common) { option in
                        Button(option.displayName) {
                            unit = option.id
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(localizedMedicationUnit(unit))
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.blue)
                            .lineLimit(1)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.blue)
                    }
                    .accessibilityLabel("选择剂量单位，当前为\(localizedMedicationUnit(unit))")
                }
            }
        }
        .padding(.vertical, 2)
    }
}

struct ImportReviewSummaryView: View {
    let review: MedicationImportReview?

    var body: some View {
        if let review {
            VStack(alignment: .leading, spacing: 8) {
                Label(review.canCreateMedication ? "信息可继续补全" : "信息仍需补全", systemImage: review.canCreateMedication ? "checkmark.circle" : "exclamationmark.triangle")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(review.canCreateMedication ? .green : .orange)
                let recognizedFields = recognizedFieldRows(for: review.draft)
                if !recognizedFields.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(recognizedFields) { field in
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text(field.title)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 56, alignment: .leading)
                                Text(field.value)
                                    .font(.caption)
                                    .foregroundStyle(.primary)
                                    .lineLimit(2)
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }
                ForEach(Array(review.issues.enumerated()), id: \.offset) { _, issue in
                    Text(issue.message)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Text("保存前请核对药盒、说明书或医嘱原件。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 6)
        }
    }

    private func recognizedFieldRows(for draft: MedicationImportDraft) -> [ImportReviewFieldRow] {
        [
            ("药名", draft.displayName),
            ("通用名", draft.genericName),
            ("规格", draft.strength),
            ("剂型", draft.form),
            ("剂量", formattedDoseAmount(from: draft)),
            ("用法", draft.directionsText)
        ].compactMap { title, value in
            guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !value.isEmpty
            else {
                return nil
            }
            return ImportReviewFieldRow(title: title, value: value)
        }
    }

    private func formattedDoseAmount(from draft: MedicationImportDraft) -> String? {
        guard let doseValue = draft.doseValue,
              let doseUnit = draft.doseUnit?.trimmingCharacters(in: .whitespacesAndNewlines),
              !doseUnit.isEmpty
        else {
            return nil
        }
        return "\(doseValue.formatted()) \(localizedMedicationUnit(doseUnit))"
    }
}

struct ImportReviewFieldRow: Identifiable {
    var title: String
    var value: String
    var id: String { title }
}

struct ReminderTimesEditor: View {
    @Binding var reminderTimes: [Date]

    private let preferredReminderTimes: [(hour: Int, minute: Int)] = [
        (8, 0),
        (13, 0),
        (18, 0),
        (21, 0)
    ]

    var body: some View {
        ForEach(Array(reminderTimes.indices), id: \.self) { index in
            DatePicker(
                "提醒 \(index + 1)",
                selection: Binding(
                    get: {
                        guard reminderTimes.indices.contains(index) else {
                            return defaultReminderDate(hour: 21, minute: 0)
                        }
                        return reminderTimes[index]
                    },
                    set: { newValue in
                        guard reminderTimes.indices.contains(index) else {
                            return
                        }
                        reminderTimes[index] = newValue
                    }
                ),
                displayedComponents: .hourAndMinute
            )
            .id("reminder-\(index)-\(reminderTimes.count)")
        }

        Button {
            addReminder()
        } label: {
            ReminderActionRow(
                title: "添加提醒",
                detail: "已设置 \(reminderTimes.count) 条",
                systemImage: "plus.circle.fill",
                tint: .blue,
                isDisabled: false
            )
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())

        Button {
            removeReminder()
        } label: {
            ReminderActionRow(
                title: "减少提醒",
                detail: reminderTimes.count > 1 ? "删除最后一条" : "至少保留一条",
                systemImage: "minus.circle.fill",
                tint: .red,
                isDisabled: reminderTimes.count <= 1
            )
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .disabled(reminderTimes.count <= 1)
    }

    private func addReminder() {
        let nextReminder = nextAvailableReminderTime()
        withAnimation(.snappy(duration: 0.2, extraBounce: 0.02)) {
            reminderTimes.append(nextReminder)
            reminderTimes = normalizedReminderDates(reminderTimes)
        }
    }

    private func removeReminder() {
        guard reminderTimes.count > 1 else {
            return
        }
        withAnimation(.snappy(duration: 0.2, extraBounce: 0.02)) {
            _ = reminderTimes.removeLast()
            reminderTimes = normalizedReminderDates(reminderTimes)
        }
    }

    private func nextAvailableReminderTime() -> Date {
        let occupiedTimes = Set(normalizedReminderDates(reminderTimes).map(AppFormatters.time.string(from:)))
        for preferredTime in preferredReminderTimes {
            let date = defaultReminderDate(hour: preferredTime.hour, minute: preferredTime.minute)
            if !occupiedTimes.contains(AppFormatters.time.string(from: date)) {
                return date
            }
        }

        let calendar = Calendar.current
        let normalizedDates = normalizedReminderDates(reminderTimes)
        var proposedDate = calendar.date(
            byAdding: .hour,
            value: 2,
            to: normalizedDates.last ?? defaultReminderDate(hour: 21, minute: 0)
        ) ?? defaultReminderDate(hour: 23, minute: 0)

        for _ in 0..<24 {
            let components = calendar.dateComponents([.hour, .minute], from: proposedDate)
            let date = defaultReminderDate(
                hour: components.hour ?? 21,
                minute: components.minute ?? 0
            )
            if !occupiedTimes.contains(AppFormatters.time.string(from: date)) {
                return date
            }
            proposedDate = calendar.date(byAdding: .minute, value: 30, to: proposedDate) ?? date
        }

        let fallbackMinute = min(59, reminderTimes.count)
        return defaultReminderDate(hour: 23, minute: fallbackMinute)
    }
}

struct ReminderActionRow: View {
    let title: String
    let detail: String
    let systemImage: String
    let tint: Color
    let isDisabled: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.headline.weight(.semibold))
                .foregroundStyle(isDisabled ? .secondary : tint)
                .frame(width: 22)
            Text(title)
                .font(.body.weight(.semibold))
                .foregroundStyle(isDisabled ? .secondary : .primary)
            Spacer()
            Text(detail)
                .font(.footnote.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 5)
    }
}

enum MedicationNotesDisplayPolicy {
    static func visibleText(from notes: String) -> String? {
        let visibleLines = noteLines(from: notes).filter(isUserVisibleLine)
        return normalizedText(from: visibleLines)
    }

    static func hiddenText(from notes: String) -> String? {
        let hiddenLines = noteLines(from: notes).filter { !isUserVisibleLine($0) }
        return normalizedText(from: hiddenLines)
    }

    static func mergedNotes(visibleText: String, hiddenText: String?) -> String {
        [
            normalizedText(from: [visibleText]),
            hiddenText?.trimmingCharacters(in: .whitespacesAndNewlines)
        ]
            .compactMap { text in
                guard let text, !text.isEmpty else {
                    return nil
                }
                return text
            }
            .joined(separator: "\n")
    }

    private static func noteLines(from notes: String) -> [String] {
        notes
            .split(whereSeparator: \.isNewline)
            .map(String.init)
    }

    private static func normalizedText(from lines: [String]) -> String? {
        let text = lines
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    private static func isUserVisibleLine(_ line: String) -> Bool {
        let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedLine.isEmpty else {
            return false
        }
        let hiddenFragments = [
            "演示",
            "手动录入内容需要按药品包装、说明书或医嘱核对",
            "识别结果仅用于辅助录入",
            "条码结果只用于辅助核对药盒来源",
            "识别文字：",
            "条码信息："
        ]
        return !hiddenFragments.contains { trimmedLine.contains($0) }
    }
}
