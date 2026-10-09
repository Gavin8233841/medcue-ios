import Charts
import MedicationAdherenceCore
import PhotosUI
import SwiftData
import SwiftUI
import UIKit

struct MedicationDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .body) private var minimumDetailColumnWidth: CGFloat = 260
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

    private var allowsDetailColumns: Bool {
        horizontalSizeClass == .regular && !dynamicTypeSize.isAccessibilitySize
    }

    var body: some View {
        List {
            Section {
                MedicationDetailColumnsLayout(
                    allowsColumns: allowsDetailColumns,
                    minimumColumnWidth: minimumDetailColumnWidth,
                    spacing: 24
                ) {
                    detailPhoto
                    detailIdentity
                }
                .padding(.vertical, 8)
                if !photoStatusMessage.isEmpty {
                    Text(photoStatusMessage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                MedicationDetailColumnsLayout(
                    allowsColumns: allowsDetailColumns,
                    minimumColumnWidth: minimumDetailColumnWidth,
                    spacing: 24
                ) {
                    VStack(alignment: .leading, spacing: 12) {
                        detailSectionHeading("药品信息")
                        medicationInformation
                    }
                    .accessibilityIdentifier("medicationDetail.information")
                    VStack(alignment: .leading, spacing: 12) {
                        detailSectionHeading("疗程与提醒")
                        medicationPlans
                    }
                    .accessibilityIdentifier("medicationDetail.plans")
                }
                .padding(.vertical, 8)
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
                        MedicationDetailFlowLayout(spacing: 12, stacksVertically: dynamicTypeSize.isAccessibilitySize) {
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
                            detailStatusBadge(text: task.status.displayName, color: task.status == .taken ? .green : .orange)
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
        .accessibilityIdentifier("medicationDetail")
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

    private var detailPhoto: some View {
        VStack(alignment: .leading, spacing: 10) {
            MedicationPhotoView(
                photoData: medication.photoData,
                symbolName: medication.photoSymbolName,
                tint: medicationColor(for: medication),
                size: 160,
                usesPhotoAspectRatio: true,
                contentMode: .fit,
                accessibilityLabel: "药盒或药品照片"
            )
            Text(medication.photoData == nil ? "添加药盒或药品照片" : "药盒或药品照片")
                .font(.subheadline.weight(.semibold))
            Text(medication.photoData == nil ? "建议拍药盒正面或药品实物，提醒时便于核对。" : "提醒和记录中会优先显示这张本机照片。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var detailIdentity: some View {
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
            MedicationDetailFlowLayout(spacing: 8, stacksVertically: dynamicTypeSize.isAccessibilitySize) {
                detailStatusBadge(text: medication.kindDisplayName, color: .green)
                detailStatusBadge(
                    text: lifecycleClassification.displayStatus.displayName,
                    color: badgeColor(for: lifecycleClassification.displayStatus)
                )
                if !medication.boxNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    detailStatusBadge(text: "编号 \(medication.boxNumber)", color: .blue)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            detailPhotoActions
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private var detailPhotoActions: some View {
        let hasPhoto = medication.photoData != nil
        return MedicationDetailFlowLayout(spacing: 8, stacksVertically: dynamicTypeSize.isAccessibilitySize) {
            PhotosPicker(selection: $selectedDetailPhotoItem, matching: .images) {
                Label(hasPhoto ? "更换照片" : "选择照片", systemImage: "photo")
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(minHeight: 44)
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)
            Button {
                startDetailPhotoCameraFlow()
            } label: {
                Label("拍照", systemImage: "camera")
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(minHeight: 44)
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)
            .disabled(!UIImagePickerController.isSourceTypeAvailable(.camera))
            if hasPhoto {
                Button(role: .destructive) {
                    saveDetailPhoto(
                        nil,
                        successMessage: "已清除药品照片。",
                        failureMessage: "药品照片未能清除，请重试。"
                    )
                } label: {
                    Label("清除", systemImage: "trash")
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(minHeight: 44)
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
            }
        }
    }

    private func detailStatusBadge(text: String, color: Color) -> some View {
        Text(text)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.primary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
    }

    private func detailSectionHeading(_ title: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            Divider()
        }
    }

    @ViewBuilder
    private var medicationInformation: some View {
        HStack(alignment: .top, spacing: 8) {
            MedicationColorMarker(color: medicationColor(for: medication), size: 12)
                .padding(.top, 4)
            MedicationDetailInfoRow(title: "颜色标识", value: medicationColorOption(for: medication).displayName)
        }
        MedicationDetailInfoRow(title: "通用名", value: medication.genericName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "未填写" : medication.genericName)
        MedicationDetailInfoRow(title: "规格", value: medication.strength.isEmpty ? "未填写" : medication.strength)
        MedicationDetailInfoRow(title: "剂型", value: medication.form.isEmpty ? "未填写" : medication.form)
        MedicationDetailInfoRow(title: "药盒编号", value: medication.boxNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "未填写" : medication.boxNumber)
        MedicationDetailInfoRow(title: "来源", value: sourceDisplayName(medication.inputSourceRaw))
        if let visibleNotes = MedicationNotesDisplayPolicy.visibleText(from: medication.notes) {
            Text(visibleNotes)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var medicationPlans: some View {
        if relatedPlans.isEmpty {
            Text("尚未建立提醒计划。")
                .foregroundStyle(.secondary)
        } else {
            ForEach(relatedPlans) { plan in
                VStack(alignment: .leading, spacing: 8) {
                    MedicationDetailInfoRow(title: "剂量", value: "\(plan.doseValue.formatted()) \(localizedMedicationUnit(plan.doseUnit))")
                    MedicationDetailInfoRow(title: "疗程", value: courseSummary(for: plan))
                    MedicationDetailInfoRow(title: "时间", value: reminderSummary(for: plan, tasks: relatedTasks))
                    MedicationDetailInfoRow(title: "时区规则", value: timeZonePolicyDisplayName(plan.timeZonePolicyRaw))
                    if let visiblePlanNote = userVisiblePlanSourceNote(plan.sourceNote) {
                        MedicationDetailInfoRow(title: "备注", value: visiblePlanNote)
                    }
                }
                .padding(.vertical, 6)
                if plan.id != relatedPlans.last?.id {
                    Divider()
                }
            }
        }
        Button {
            showingPlanEditor = true
        } label: {
            Label(relatedPlans.isEmpty ? "建立疗程与提醒" : "修改疗程与提醒", systemImage: "calendar.badge.clock")
                .fixedSize(horizontal: false, vertical: true)
                .frame(minHeight: 44, alignment: .leading)
        }
        .buttonStyle(.borderless)
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
        if case .scheduleFailed = outcome {
            photoStatusMessage = "提醒时间暂时无法计算，药品状态未更改。请稍后重试。"
            return
        }
        guard case let .committed(commit) = outcome else {
            photoStatusMessage = AppPersistenceCommitter.failureUserMessage
            return
        }
        let notificationService = NotificationService()
        let reminderSync = notificationService.beginApplyCommittedReminderState(in: modelContext)
        Task { @MainActor in
            _ = await reminderSync.value
            let liveActivityService = MedicationLiveActivityService()
            for taskID in commit.disabledTaskIDs {
                await liveActivityService.end(for: taskID)
            }
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
        notificationService.beginApplyCommittedReminderState(in: modelContext)
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

// Keeps the same child identities while available space changes. The minimum is a
// Dynamic Type-scaled reading measure, not a screen/device breakpoint. Measuring
// each proposed column also rejects children that cannot fit that measure.
private struct MedicationDetailColumnsLayout: Layout {
    var allowsColumns: Bool
    var minimumColumnWidth: CGFloat
    var spacing: CGFloat

    private func usesColumns(width: CGFloat, subviews: Subviews) -> Bool {
        guard allowsColumns, subviews.count == 2 else { return false }
        let columnWidth = max(0, (width - spacing) / 2)
        guard columnWidth >= minimumColumnWidth else { return false }
        return subviews.allSatisfy {
            $0.sizeThatFits(ProposedViewSize(width: columnWidth, height: nil)).width <= columnWidth
        }
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width.flatMap { $0.isFinite ? $0 : nil }
            ?? subviews.map { $0.sizeThatFits(.unspecified).width }.max() ?? 0
        let horizontal = usesColumns(width: width, subviews: subviews)
        let childWidth = horizontal ? max(0, (width - spacing) / 2) : width
        let sizes = subviews.map { $0.sizeThatFits(ProposedViewSize(width: childWidth, height: nil)) }
        let height = horizontal ? (sizes.map(\.height).max() ?? 0)
            : sizes.reduce(0) { $0 + $1.height } + spacing * CGFloat(max(0, sizes.count - 1))
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let horizontal = usesColumns(width: bounds.width, subviews: subviews)
        let childWidth = horizontal ? max(0, (bounds.width - spacing) / 2) : bounds.width
        let childProposal = ProposedViewSize(width: childWidth, height: nil)
        var origin = bounds.origin
        for subview in subviews {
            subview.place(at: origin, anchor: .topLeading, proposal: childProposal)
            if horizontal {
                origin.x += childWidth + spacing
            } else {
                origin.y += subview.sizeThatFits(childProposal).height + spacing
            }
        }
    }
}

// Wrap actions and record contents without duplicating controls in fit/fallback
// branches. Accessibility sizes always use the original reading order vertically.
private struct MedicationDetailFlowLayout: Layout {
    var spacing: CGFloat
    var stacksVertically: Bool

    private func arrangement(width: CGFloat, subviews: Subviews) -> (origins: [CGPoint], sizes: [CGSize], height: CGFloat) {
        var origins: [CGPoint] = []
        var sizes: [CGSize] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let idealWidth = subview.sizeThatFits(.unspecified).width
            let size = subview.sizeThatFits(ProposedViewSize(width: min(width, idealWidth), height: nil))
            if x > 0 && (stacksVertically || x + size.width > width) {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            origins.append(CGPoint(x: x, y: y))
            sizes.append(size)
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return (origins, sizes, y + rowHeight)
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width.flatMap { $0.isFinite ? $0 : nil }
            ?? subviews.map { $0.sizeThatFits(.unspecified).width }.reduce(0, +)
                + spacing * CGFloat(max(0, subviews.count - 1))
        return CGSize(width: width, height: arrangement(width: width, subviews: subviews).height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrangement(width: bounds.width, subviews: subviews)
        for index in subviews.indices {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + result.origins[index].x, y: bounds.minY + result.origins[index].y),
                anchor: .topLeading,
                proposal: ProposedViewSize(width: result.sizes[index].width, height: result.sizes[index].height)
            )
        }
    }
}

private struct MedicationDetailInfoRow: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let title: String
    let value: String

    private var stacked: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .foregroundStyle(.secondary)
            Text(value)
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                stacked
            } else {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text(title)
                            .foregroundStyle(.secondary)
                            .fixedSize()
                        Spacer(minLength: 0)
                        Text(value)
                            .fixedSize()
                    }
                    stacked
                }
            }
        }
        .accessibilityElement(children: .combine)
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
