import Charts
import MedicationAdherenceCore
import PhotosUI
import SwiftData
import SwiftUI
import UIKit

struct MedicationDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    let medication: StoredMedication
    @Query(sort: \StoredMedicationPlan.createdAt) private var plans: [StoredMedicationPlan]
    @Query(sort: \StoredDoseTask.dueAt, order: .reverse) private var tasks: [StoredDoseTask]
    @Query(sort: \StoredRiskCard.displayPriority) private var riskCards: [StoredRiskCard]
    @Query(sort: \StoredMedicationStock.lastUpdated, order: .reverse) private var stocks: [StoredMedicationStock]
    @Query(sort: \StoredMedicationLabel.importedAt, order: .reverse) private var labels: [StoredMedicationLabel]
    @Query(sort: \StoredMedicationDoseChange.effectiveFrom, order: .reverse) private var doseChanges: [StoredMedicationDoseChange]
    @State private var showingEditor = false
    @State private var showingStockEditor = false
    @State private var showingPlanEditor = false
    @State private var showingLabelImporter = false
    @State private var showingCameraPhotoCapture = false
    @State private var selectedDetailPhotoItem: PhotosPickerItem?
    @State private var photoStatusMessage = ""
    @State private var riskReviewStatusMessage = ""
    @State private var showingDeleteConfirmation = false
    @State private var pendingPermissionGate: AppPermissionGate?

    init(medication: StoredMedication) {
        self.medication = medication
        let medicationID = medication.id
        _plans = Query(
            filter: #Predicate<StoredMedicationPlan> { $0.medicationID == medicationID },
            sort: \StoredMedicationPlan.createdAt
        )
        _tasks = Query(
            filter: #Predicate<StoredDoseTask> { $0.medicationID == medicationID },
            sort: \StoredDoseTask.dueAt,
            order: .reverse
        )
        _riskCards = Query(
            filter: #Predicate<StoredRiskCard> { $0.medicationID == medicationID },
            sort: \StoredRiskCard.displayPriority
        )
        _stocks = Query(
            filter: #Predicate<StoredMedicationStock> { $0.medicationID == medicationID },
            sort: \StoredMedicationStock.lastUpdated,
            order: .reverse
        )
        _labels = Query(
            filter: #Predicate<StoredMedicationLabel> { $0.medicationID == medicationID },
            sort: \StoredMedicationLabel.importedAt,
            order: .reverse
        )
        _doseChanges = Query(
            filter: #Predicate<StoredMedicationDoseChange> { $0.medicationID == medicationID },
            sort: \StoredMedicationDoseChange.effectiveFrom,
            order: .reverse
        )
    }

    private var relatedPlans: [StoredMedicationPlan] {
        plans.filter { $0.medicationID == medication.id }
    }

    private var relatedTasks: [StoredDoseTask] {
        tasks.filter { $0.medicationID == medication.id }
    }

    private var relatedMeasurableTasks: [StoredDoseTask] {
        relatedTasks.adherenceMeasurableTasks
    }

    private var relatedDoseChanges: [StoredMedicationDoseChange] {
        doseChanges.filter { $0.medicationID == medication.id }
    }

    private var relatedRiskCards: [StoredRiskCard] {
        riskCards.filter { $0.medicationID == medication.id }
    }

    private var activeRelatedRiskCards: [StoredRiskCard] {
        relatedRiskCards.filter(\.isActive).sorted(by: riskCardSort)
    }

    private var archivedRelatedRiskCards: [StoredRiskCard] {
        relatedRiskCards.filter { $0.isArchived || $0.isResolved }.sorted(by: riskCardSort)
    }

    private var relatedStock: StoredMedicationStock? {
        stocks.first { $0.medicationID == medication.id }
    }

    private var relatedLabel: StoredMedicationLabel? {
        labels.first { $0.medicationID == medication.id }
    }

    private var stockProjection: MedicationStockProjection? {
        guard let relatedStock else {
            return nil
        }
        return MedicationStockEstimator().project(
            stock: relatedStock.coreStock,
            scheduledDoses: relatedMeasurableTasks.map(\.coreScheduledDose),
            events: relatedMeasurableTasks.compactMap(\.coreDoseEventUsingEffectiveAdherenceDate)
        )
    }

    private var effectiveLabel: MedicationLabel? {
        relatedLabel?.coreLabel
    }

    private var labelSummary: ReadableLabelSummary? {
        effectiveLabel.map { ReadableLabelSummaryBuilder().build(from: $0) }
    }

    private var lifecycleClassification: MedicationLifecycleClassification {
        MedicationLifecycleClassifier().classify(
            medication: medication,
            plans: plans,
            tasks: tasks
        )
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 14) {
                    MedicationHeroPhotoView(
                        photoData: medication.photoData,
                        symbolName: medication.photoSymbolName,
                        tint: medicationColor(for: medication),
                        title: medication.photoData == nil ? "添加药盒或药品照片" : "药盒或药品照片",
                        subtitle: medication.photoData == nil ? "建议拍药盒正面或药品实物，提醒时便于核对。" : "提醒和记录中会优先显示这张本机照片。",
                        boxNumber: medication.boxNumber
                    )
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            MedicationColorMarker(color: medicationColor(for: medication), size: 11)
                            Text(userFacingMedicationName(for: medication))
                                .font(.title2.weight(.semibold))
                        }
                        if !medication.genericName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                           medication.genericName != medication.displayName {
                            Text("通用名 \(medication.genericName)")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        if medicationNeedsNameReview(medication) {
                            Label(medicationNameReviewHint(for: medication), systemImage: "exclamationmark.triangle")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.orange)
                        }
                        Text([medication.strength, medication.form].filter { !$0.isEmpty }.joined(separator: " · "))
                            .foregroundStyle(.secondary)
                        StatusBadgeFlow {
                            StatusBadge(text: medication.kindDisplayName, color: .green)
                            StatusBadge(
                                text: lifecycleClassification.displayStatus.displayName,
                                color: badgeColor(for: lifecycleClassification.displayStatus)
                            )
                            if !medication.boxNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                StatusBadge(text: "编号 \(medication.boxNumber)", color: .blue)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        HStack {
                            PhotosPicker(selection: $selectedDetailPhotoItem, matching: .images) {
                                Label(medication.photoData == nil ? "选择照片" : "更换照片", systemImage: "photo")
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            Button {
                                startDetailPhotoCameraFlow()
                            } label: {
                                Label("拍照", systemImage: "camera")
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .disabled(!UIImagePickerController.isSourceTypeAvailable(.camera))
                            if medication.photoData != nil {
                                Button(role: .destructive) {
                                    saveDetailPhoto(
                                        nil,
                                        successMessage: "已清除药品照片。",
                                        failureMessage: "药品照片未能清除，请重试。"
                                    )
                                } label: {
                                    Label("清除", systemImage: "trash")
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }
                        }
                    }
                }
                .padding(.vertical, 8)
                if !photoStatusMessage.isEmpty {
                    Text(photoStatusMessage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            Section("药品信息") {
                HStack {
                    Text("颜色标识")
                    Spacer()
                    HStack(spacing: 8) {
                        MedicationColorMarker(color: medicationColor(for: medication), size: 12)
                        Text(medicationColorOption(for: medication).displayName)
                            .foregroundStyle(.secondary)
                    }
                }
                InfoRow(title: "通用名", value: medication.genericName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "未填写" : medication.genericName)
                InfoRow(title: "规格", value: medication.strength.isEmpty ? "未填写" : medication.strength)
                InfoRow(title: "剂型", value: medication.form.isEmpty ? "未填写" : medication.form)
                InfoRow(title: "药盒编号", value: medication.boxNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "未填写" : medication.boxNumber)
                InfoRow(title: "来源", value: sourceDisplayName(medication.inputSourceRaw))
                if let visibleNotes = MedicationNotesDisplayPolicy.visibleText(from: medication.notes) {
                    Text(visibleNotes)
                        .foregroundStyle(.secondary)
                }
            }

            Section("疗程与提醒") {
                if relatedPlans.isEmpty {
                    Text("尚未建立提醒计划。")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(relatedPlans) { plan in
                        VStack(alignment: .leading, spacing: 8) {
                            InfoRow(title: "剂量", value: "\(plan.doseValue.formatted()) \(localizedMedicationUnit(plan.doseUnit))")
                            InfoRow(title: "疗程", value: courseSummary(for: plan))
                            InfoRow(title: "时间", value: reminderSummary(for: plan, tasks: relatedTasks))
                            InfoRow(title: "时区规则", value: timeZonePolicyDisplayName(plan.timeZonePolicyRaw))
                            if let visiblePlanNote = userVisiblePlanSourceNote(plan.sourceNote) {
                                InfoRow(title: "备注", value: visiblePlanNote)
                            }
                        }
                        .padding(.vertical, 6)
                    }
                }
                Button {
                    showingPlanEditor = true
                } label: {
                    Label(relatedPlans.isEmpty ? "建立疗程与提醒" : "修改疗程与提醒", systemImage: "calendar.badge.clock")
                }
            }

            Section("剂量变化记录") {
                if relatedDoseChanges.isEmpty {
                    Text("暂无剂量变化记录。")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(Array(relatedDoseChanges.prefix(5))) { change in
                        MedicationDoseChangeRow(
                            change: change,
                            effectiveUntil: medicationDoseChangeEffectiveUntil(change, in: relatedDoseChanges)
                        )
                            .padding(.vertical, 5)
                    }
                }
            }

            Section("药盒库存") {
                if let stockProjection {
                    StockProjectionView(projection: stockProjection)
                } else {
                    Text("尚未填写药盒剩余量。")
                        .foregroundStyle(.secondary)
                }
                Button {
                    showingStockEditor = true
                } label: {
                    Label(relatedStock == nil ? "填写药盒" : "更新药盒", systemImage: "shippingbox")
                }
            }

            Section("近期记录") {
                if relatedMeasurableTasks.isEmpty {
                    Text("暂无服药记录。")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(Array(relatedMeasurableTasks.prefix(5))) { task in
                        HStack(spacing: 12) {
                            MedicationPhotoView(
                                photoData: medication.photoData,
                                symbolName: medication.photoSymbolName,
                                tint: task.status == .taken ? .green : .orange,
                                size: 44
                            )
                            VStack(alignment: .leading, spacing: 4) {
                                Text("\(task.doseValue.formatted()) \(localizedMedicationUnit(task.doseUnit))")
                                    .font(.headline)
                                Text("\(AppFormatters.day.string(from: task.dueAt)) · \(AppFormatters.time.string(from: task.dueAt))")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            StatusBadge(text: task.status.displayName, color: task.status == .taken ? .green : .orange)
                        }
                        .padding(.vertical, 6)
                    }
                }
            }

            Section("说明书与风险识别") {
                if let relatedLabel {
                    VStack(alignment: .leading, spacing: 8) {
                        Label(labelStatusTitle(for: relatedLabel), systemImage: "doc.text.magnifyingglass")
                            .font(.headline)
                        Text(relatedLabel.sourceTitle)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text(labelTimestampText(for: relatedLabel))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        if let reviewedAt = relatedLabel.lastRiskReviewAt {
                            Text("风险识别：\(AppFormatters.day.string(from: reviewedAt)) \(AppFormatters.time.string(from: reviewedAt)) 已更新")
                                .font(.footnote)
                                .foregroundStyle(.green)
                        }
                        StatusBadge(
                            text: activeRelatedRiskCards.isEmpty ? "暂无活跃警示" : "\(activeRelatedRiskCards.count) 条活跃警示",
                            color: activeRelatedRiskCards.isEmpty ? .blue : .orange
                        )
                        if !archivedRelatedRiskCards.isEmpty {
                            StatusBadge(text: "\(archivedRelatedRiskCards.count) 条已归档", color: .secondary)
                        }
                    }
                    .padding(.vertical, 6)
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("建议导入说明书", systemImage: "doc.badge.plus")
                            .font(.headline)
                        StatusBadge(text: "未导入", color: .secondary)
                    }
                    .padding(.vertical, 6)
                }

                Button {
                    showingLabelImporter = true
                } label: {
                    Label(relatedLabel == nil ? "导入说明书" : "重新导入说明书", systemImage: "camera.viewfinder")
                }

                if relatedLabel != nil {
                    Button {
                        rebuildLabelRisks()
                    } label: {
                        Label("重新识别风险", systemImage: "arrow.triangle.2.circlepath")
                    }
                }

                if !riskReviewStatusMessage.isEmpty {
                    Text(riskReviewStatusMessage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

            }

            Section("风险与副作用") {
                if activeRelatedRiskCards.isEmpty {
                    Text("暂无风险提醒。")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(Array(activeRelatedRiskCards.prefix(4))) { card in
                        NavigationLink {
                            RiskCardDetailView(card: card, medicationName: userFacingMedicationName(for: medication))
                        } label: {
                            MedicationRiskCardRow(card: card)
                        }
                    }
                }

                if activeRelatedRiskCards.count > 4 {
                    NavigationLink {
                        RisksView()
                    } label: {
                        Label("查看全部风险提醒", systemImage: "exclamationmark.triangle")
                    }
                }

                if let labelSummary {
                    ForEach(labelSummary.cards.filter { $0.kind == .adverseReactions || $0.kind == .warnings }) { card in
                        VStack(alignment: .leading, spacing: 7) {
                            Text(card.heading)
                                .font(.headline)
                            Text(card.plainLanguageNote)
                                .font(.subheadline)
                            Text(card.sourceExcerpt)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 6)
                    }
                }
            }

            if let labelSummary {
                Section("说明书可读化") {
                    ForEach(labelSummary.cards) { card in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(card.heading)
                                .font(.headline)
                            Text(card.plainLanguageNote)
                                .font(.subheadline)
                            Text(card.sourceExcerpt)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 6)
                    }
                    Text(labelSummary.safetyNote)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            Section("高级操作") {
                LifecycleReviewPanel(
                    medication: medication,
                    classification: lifecycleClassification,
                    markInterrupted: {
                        updateLifecycleStatus(.interrupted, note: "用户在药品详情标记服用中断")
                    },
                    markActive: {
                        updateLifecycleStatus(.active, note: "用户在药品详情恢复正在服用")
                    },
                    archive: {
                        updateLifecycleStatus(.archived, note: "用户在药品详情归档药物")
                    }
                )
                Picker("药品状态", selection: Binding(
                    get: { medication.lifecycleStatus },
                    set: { newValue in
                        updateLifecycleStatus(newValue, note: "用户在药品详情修改药品状态")
                    }
                )) {
                    ForEach(StoredMedicationLifecycleStatus.allCases) { status in
                        Text(status.displayName).tag(status)
                    }
                }
                Button {
                    showingEditor = true
                } label: {
                    Label("修改药品信息", systemImage: "pencil")
                }
                if medication.lifecycleStatus == .archived {
                    Button(role: .destructive) {
                        showingDeleteConfirmation = true
                    } label: {
                        Label("删除归档药物", systemImage: "trash")
                    }
                }
            }
        }
        .navigationTitle("药品详情")
        .sheet(isPresented: $showingEditor) {
            EditMedicationView(medication: medication)
        }
        .sheet(isPresented: $showingStockEditor) {
            StockEditorView(medication: medication, stock: relatedStock)
        }
        .sheet(isPresented: $showingPlanEditor) {
            PlanEditorView(
                medication: medication,
                plan: relatedPlans.first,
                tasks: relatedTasks,
                doseChanges: relatedDoseChanges
            )
        }
        .sheet(isPresented: $showingLabelImporter) {
            MedicationLabelImporterView(
                medication: medication,
                existingLabel: relatedLabel,
                save: saveUserProvidedLabel
            )
        }
        .onChange(of: selectedDetailPhotoItem) { _, newItem in
            Task {
                await loadDetailPhoto(newItem)
            }
        }
        .sheet(isPresented: $showingCameraPhotoCapture) {
            CameraPhotoCaptureSheet { image in
                saveDetailPhoto(
                    normalizedPhotoData(image),
                    successMessage: "药品照片已通过相机更新。",
                    failureMessage: "药品照片未能保存，请重试。"
                )
            }
        }
        .appPermissionPrimer(pendingGate: $pendingPermissionGate) { gate in
            guard gate == .camera else {
                return
            }
            Task {
                await requestDetailPhotoCameraAccess()
            }
        }
        .confirmationDialog("删除归档药物？", isPresented: $showingDeleteConfirmation, titleVisibility: .visible) {
            Button("删除药物和相关记录", role: .destructive) {
                deleteArchivedMedication()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("会删除该药物的提醒、记录、说明书、风险提醒、库存和剂量变化。")
        }
    }

    private func startDetailPhotoCameraFlow() {
        guard AppPermissionGate.isCameraAvailable() else {
            photoStatusMessage = "当前设备没有可用相机。"
            return
        }
        if AppPermissionGate.isCameraAuthorized() {
            showingCameraPhotoCapture = true
            return
        }
        if AppPermissionGate.hasCompletedAuthorization(for: .camera) {
            Task {
                await requestDetailPhotoCameraAccess()
            }
        } else {
            pendingPermissionGate = .camera
        }
    }

    @MainActor
    private func requestDetailPhotoCameraAccess() async {
        guard await AppPermissionGate.requestCameraAccess() else {
            photoStatusMessage = "相机权限未开启，无法拍摄药盒或药品照片。"
            return
        }
        showingCameraPhotoCapture = true
    }

    private func updateLifecycleStatus(_ status: StoredMedicationLifecycleStatus, note: String) {
        guard medication.lifecycleStatus != status else {
            return
        }
        let outcome = MedicationLifecycleCommand(modelContext: modelContext).update(
            MedicationLifecycleUpdate(
                medicationID: medication.id,
                status: status,
                note: note,
                occurredAt: Date()
            )
        )
        guard case let .committed(commit) = outcome else {
            photoStatusMessage = AppPersistenceCommitter.failureUserMessage
            return
        }
        let notificationService = NotificationService()
        for taskID in commit.disabledTaskIDs {
            notificationService.cancelReminder(for: taskID)
        }
        let cancelledTaskIDs = commit.reminderBatches.flatMap(\.cancelledTaskIDs)
        notificationService.cancelReminders(for: cancelledTaskIDs)
        Task { @MainActor in
            let liveActivityService = MedicationLiveActivityService()
            for taskID in commit.disabledTaskIDs {
                await liveActivityService.end(for: taskID)
            }
            for batch in commit.reminderBatches {
                for task in batch.tasks {
                    await notificationService.scheduleReminder(
                        for: task,
                        medication: batch.medication,
                        deliveryMethod: batch.deliveryMethod
                    )
                }
            }
            await notificationService.refreshPendingReminderCount()
        }
    }

    private func deleteArchivedMedication() {
        let outcome = MedicationDeletionCommand(modelContext: modelContext).delete(
            medicationID: medication.id
        )
        guard case let .committed(commit) = outcome else {
            photoStatusMessage = AppPersistenceCommitter.failureUserMessage
            return
        }
        let notificationService = NotificationService()
        for taskID in commit.taskIDs {
            notificationService.cancelReminder(for: taskID)
        }
        Task {
            let liveActivityService = MedicationLiveActivityService()
            for taskID in commit.taskIDs {
                await liveActivityService.end(for: taskID)
            }
        }
        dismiss()
    }

    private func saveUserProvidedLabel(rawText: String, sourceTitle: String, confidence: Double) {
        let outcome = MedicationLabelReviewCommand(modelContext: modelContext).save(
            MedicationLabelReviewInput(
                medicationID: medication.id,
                rawText: rawText,
                sourceTitle: sourceTitle,
                averageOCRConfidence: confidence,
                reviewedAt: Date()
            )
        )
        guard case let .committed(commit) = outcome else {
            riskReviewStatusMessage = AppPersistenceCommitter.failureUserMessage
            return
        }
        riskReviewStatusMessage = commit.riskResult.userFacingSummary
    }

    private func rebuildLabelRisks() {
        guard let relatedLabel else {
            return
        }
        let outcome = MedicationLabelReviewCommand(modelContext: modelContext).save(
            MedicationLabelReviewInput(
                medicationID: medication.id,
                rawText: relatedLabel.rawText,
                sourceTitle: relatedLabel.sourceTitle,
                averageOCRConfidence: relatedLabel.averageOCRConfidence,
                reviewedAt: Date()
            )
        )
        guard case let .committed(commit) = outcome else {
            riskReviewStatusMessage = AppPersistenceCommitter.failureUserMessage
            return
        }
        riskReviewStatusMessage = commit.riskResult.userFacingSummary
    }

    private func sourceDisplayName(_ rawValue: String) -> String {
        switch MedicationInputSource(rawValue: rawValue) {
        case .manual:
            "手动添加"
        case .barcode:
            "药盒条码"
        case .prescriptionImage:
            "医嘱图片导入"
        case .demoData:
            "已保存记录"
        case nil:
            rawValue
        }
    }

    private func timeZonePolicyDisplayName(_ rawValue: String) -> String {
        switch ReminderTimeZonePolicy(rawValue: rawValue) {
        case .localClock:
            "按当地时间提醒"
        case .fixedInterval:
            "按固定间隔提醒"
        case nil:
            "需核对提醒规则"
        }
    }

    private func labelStatusTitle(for label: StoredMedicationLabel) -> String {
        label.sourceTitle == "本地保存说明书摘要" ? "已保存说明书摘要" : "已导入说明书"
    }

    private func labelTimestampText(for label: StoredMedicationLabel) -> String {
        let timestamp = "\(AppFormatters.day.string(from: label.importedAt)) \(AppFormatters.time.string(from: label.importedAt))"
        return label.sourceTitle == "本地保存说明书摘要" ? "保存时间：\(timestamp)" : "导入时间：\(timestamp)"
    }

    private func loadDetailPhoto(_ item: PhotosPickerItem?) async {
        guard let item else {
            return
        }
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                await MainActor.run {
                    photoStatusMessage = "没有读取到图片数据。"
                }
                return
            }
            let normalizedData = normalizedPhotoData(data)
            await MainActor.run {
                saveDetailPhoto(
                    normalizedData,
                    successMessage: "药品照片已更新。",
                    failureMessage: "药品照片未能保存，请重试。"
                )
            }
        } catch {
            await MainActor.run {
                photoStatusMessage = "图片读取失败，请稍后重试。"
            }
        }
    }

    private func saveDetailPhoto(
        _ photoData: Data?,
        successMessage: String,
        failureMessage: String
    ) {
        let outcome = MedicationProfileCommand(modelContext: modelContext).updatePhoto(
            MedicationPhotoUpdate(medicationID: medication.id, photoData: photoData)
        )
        switch outcome {
        case .committed:
            photoStatusMessage = successMessage
        case .rejected, .saveFailed:
            photoStatusMessage = failureMessage
        }
    }
}

func userVisiblePlanSourceNote(_ note: String) -> String? {
    let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedNote.isEmpty else {
        return nil
    }

    let hiddenFragments = [
        "用户二次确认后建立",
        "可在详情页继续修改疗程、提醒和库存",
        "按说明书建议建立，用户确认后提醒"
    ]
    guard !hiddenFragments.contains(where: { trimmedNote.contains($0) }) else {
        return nil
    }
    return trimmedNote
}

func storedPlanSourceNote(from visibleNote: String) -> String {
    visibleNote.trimmingCharacters(in: .whitespacesAndNewlines)
}

struct CameraPhotoCaptureSheet: UIViewControllerRepresentable {
    @Environment(\.dismiss) private var dismiss
    let onImage: (UIImage) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onImage: onImage, dismiss: dismiss)
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.cameraCaptureMode = .photo
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        let onImage: (UIImage) -> Void
        let dismiss: DismissAction

        init(onImage: @escaping (UIImage) -> Void, dismiss: DismissAction) {
            self.onImage = onImage
            self.dismiss = dismiss
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            if let image = info[.originalImage] as? UIImage {
                onImage(image)
            }
            dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            dismiss()
        }
    }
}

enum AddMedicationCameraAction {
    case barcodeScanner
    case prescriptionImage
    case nameScan
    case medicationPhoto
}

struct MedicationPhotoSourceSheet: View {
    let hasPhoto: Bool
    let canUseCamera: Bool
    @Binding var selectedPhotoItem: PhotosPickerItem?
    let takePhoto: () -> Void
    let clearPhoto: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 14) {
                Button(action: takePhoto) {
                    MedicationPhotoSourceButtonLabel(
                        title: "拍照",
                        subtitle: canUseCamera ? "拍摄药盒正面或药品实物" : "当前设备没有可用相机",
                        systemImage: "camera.fill",
                        tint: .blue
                    )
                }
                .buttonStyle(.plain)
                .disabled(!canUseCamera)
                .opacity(canUseCamera ? 1 : 0.5)

                PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                    MedicationPhotoSourceButtonLabel(
                        title: hasPhoto ? "更换照片" : "选择照片",
                        subtitle: "从相册选择一张用于提醒核对",
                        systemImage: "photo.fill.on.rectangle.fill",
                        tint: .blue
                    )
                }
                .buttonStyle(.plain)

                if hasPhoto {
                    Button(role: .destructive, action: clearPhoto) {
                        MedicationPhotoSourceButtonLabel(
                            title: "清除当前照片",
                            subtitle: "保留药品资料，只移除照片",
                            systemImage: "trash.fill",
                            tint: .red
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 24)
            .navigationTitle("添加药品照片")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        dismiss()
                    }
                }
            }
            .onChange(of: selectedPhotoItem) { _, newItem in
                if newItem != nil {
                    dismiss()
                }
            }
        }
    }
}

struct MedicationPhotoSourceButtonLabel: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let tint: Color

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.headline.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 36, height: 36)
                .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

