import MedicationAdherenceCore
import SwiftData
import SwiftUI

struct DoseRecordCorrectionView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    let task: StoredDoseTask
    let medication: StoredMedication?
    @StateObject private var notificationService = NotificationService()
    @StateObject private var liveActivityService = MedicationLiveActivityService()
    @State private var status: StoredDoseStatus
    @State private var plannedAt: Date
    @State private var recordedAt: Date
    @State private var note: String
    @State private var showingEarlyRecordConfirmation = false
    @State private var showingSaveFailure = false
    @State private var isSaveFlowActive = false

    init(task: StoredDoseTask, medication: StoredMedication?) {
        self.task = task
        self.medication = medication
        _status = State(initialValue: task.status)
        _plannedAt = State(initialValue: task.dueAt)
        _recordedAt = State(initialValue: min(task.effectiveAdherenceRecordedAt ?? task.recordedAt ?? task.dueAt, Date()))
        _note = State(initialValue: task.recordDisplayReason ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("记录") {
                    HStack(spacing: 12) {
                        MedicationPhotoView(
                            photoData: medication?.photoData,
                            symbolName: medication?.photoSymbolName ?? "pills.fill",
                            tint: .blue,
                            size: 44
                        )
                        VStack(alignment: .leading, spacing: 4) {
                            Text(medication.map(userFacingMedicationName(for:)) ?? "未知药品")
                                .font(.headline)
                            Text("\(task.doseValue.formatted()) \(localizedMedicationUnit(task.doseUnit))")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Picker("状态", selection: $status) {
                        Text("待处理").tag(StoredDoseStatus.pending)
                        Text("已服用").tag(StoredDoseStatus.taken)
                        Text("稍后提醒").tag(StoredDoseStatus.delayed)
                        Text("已忽略").tag(StoredDoseStatus.skipped)
                        Text("已修正").tag(StoredDoseStatus.corrected)
                    }
                    DatePicker("计划时间", selection: $plannedAt)
                    if status != .pending {
                        DatePicker("实际记录时间", selection: $recordedAt, in: ...Date())
                    }
                }

                Section("备注") {
                    TextEditor(text: $note)
                        .frame(minHeight: 96)
                }
            }
            .navigationTitle("修正记录")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        saveWithEarlyRecordCheck()
                    }
                    .disabled(isSaveFlowActive)
                }
            }
            .alert("确认提前记录？", isPresented: $showingEarlyRecordConfirmation) {
                Button("确认已提前服用") {
                    save(confirmedEarlyRecord: true)
                }
                Button("返回修改", role: .cancel) {}
            } message: {
                Text("实际记录时间距离计划时间较久。请确认这是按医嘱、说明书或医生或药师建议提前服用。")
            }
            .alert("修正未保存", isPresented: $showingSaveFailure) {
                Button("知道了", role: .cancel) {}
            } message: {
                Text("记录仍保持原状，请稍后重试。")
            }
        }
    }

    private func saveWithEarlyRecordCheck() {
        guard !isSaveFlowActive else { return }
        let clampedRecordedAt = min(recordedAt, Date())
        guard shouldConfirmEarlyRecord(recordedAt: clampedRecordedAt) else {
            save(confirmedEarlyRecord: false)
            return
        }
        showingEarlyRecordConfirmation = true
    }

    private func shouldConfirmEarlyRecord(recordedAt: Date) -> Bool {
        guard status == .taken || status == .corrected else {
            return false
        }
        return DoseReminderPolicy.competitionDemo.requiresEarlyTakenConfirmation(
            plannedDueAt: plannedAt,
            now: recordedAt
        )
    }

    private func save(confirmedEarlyRecord: Bool) {
        guard !isSaveFlowActive else { return }
        isSaveFlowActive = true
        let occurredAt = Date()
        let outcome = DoseRecordCorrectionCommand(modelContext: modelContext).perform(
            DoseRecordCorrectionInput(
                taskID: task.id,
                status: status,
                plannedAt: plannedAt,
                recordedAt: min(recordedAt, occurredAt),
                note: note,
                confirmedEarlyRecord: confirmedEarlyRecord,
                occurredAt: occurredAt
            )
        )
        switch outcome {
        case let .committed(commit):
            synchronizeReminderAfterCorrection(taskIDs: commit.taskIDs)
            dismiss()
        case .rejected, .saveFailed:
            isSaveFlowActive = false
            showingSaveFailure = true
        }
    }

    private func synchronizeReminderAfterCorrection(taskIDs: [UUID]) {
        let taskIDSet = Set(taskIDs)
        let group = (try? modelContext.fetch(
            FetchDescriptor<StoredDoseTask>(
                predicate: #Predicate<StoredDoseTask> { storedTask in
                    taskIDSet.contains(storedTask.id)
                }
            )
        )) ?? [task]
        let shouldKeepReminder = (task.status == .pending || task.status == .delayed) && task.dueAt > Date()
        guard shouldKeepReminder, let medication else {
            Task { @MainActor in
                for groupTask in group {
                    notificationService.cancelReminder(for: groupTask.id)
                    await liveActivityService.end(for: groupTask.id)
                }
            }
            return
        }

        let planID = task.planID
        var planDescriptor = FetchDescriptor<StoredMedicationPlan>(
            predicate: #Predicate<StoredMedicationPlan> { plan in
                plan.id == planID
            }
        )
        planDescriptor.fetchLimit = 1
        let deliveryMethod = (try? modelContext.fetch(planDescriptor).first)?.reminderDeliveryMethod ?? .notification
        Task { @MainActor in
            for groupTask in group {
                if groupTask.id == task.id {
                    await notificationService.scheduleReminder(
                        for: groupTask,
                        medication: medication,
                        deliveryMethod: deliveryMethod
                    )
                } else {
                    notificationService.cancelReminder(for: groupTask.id)
                }
                await liveActivityService.end(for: groupTask.id)
            }
            await liveActivityService.startIfNeeded(for: task, medication: medication)
        }
    }
}
