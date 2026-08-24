import Charts
import MedicationAdherenceCore
import PhotosUI
import SwiftData
import SwiftUI
import UIKit

struct AddMedicationView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @StateObject private var notificationService = NotificationService()
    let option: MedicationAddOption
    @State private var displayName = ""
    @State private var genericName = ""
    @State private var strength = ""
    @State private var form = ""
    @State private var doseValue = 1.0
    @State private var doseUnit = "片"
    @State private var initialStockQuantity = 0.0
    @State private var lowStockThreshold = 0.0
    @State private var stockUnit = "片"
    @State private var courseStartDate: Date
    @State private var hasCourseEndDate = false
    @State private var courseEndDate: Date
    @State private var reminderTimes: [Date]
    @State private var reminderDeliveryMethod: StoredReminderDeliveryMethod = .notification
    @State private var escalatesToAlarmWhenUnhandled = true
    @State private var kind: MedicationKind
    @State private var importedText = ""
    @State private var barcodeValue = ""
    @State private var showingReviewAlert = false
    @State private var showingSaveConfirmation = false
    @State private var selectedImageItem: PhotosPickerItem?
    @State private var selectedMedicationPhotoItem: PhotosPickerItem?
    @State private var showingMedicationPhotoSourceDialog = false
    @State private var medicationPhotoData: Data?
    @State private var selectedPhotoSymbolName = "pills.fill"
    @State private var boxNumber = ""
    @State private var isAnalyzingImage = false
    @State private var visionStatusMessage = ""
    @State private var importReview: MedicationImportReview?
    @State private var recognizedBarcodes: [VisionBarcodeRecognitionResult] = []
    @State private var visionAnalysisTask: Task<Void, Never>?
    @State private var visionGenerationGate = VisionImportGenerationGate()
    @State private var showingCameraScanner = false
    @State private var showingPrescriptionImageCamera = false
    @State private var showingNameScanCamera = false
    @State private var showingMedicationPhotoCamera = false
    @State private var pendingPermissionGate: AppPermissionGate?
    @State private var pendingCameraAction: AddMedicationCameraAction?
    @State private var shouldSaveAfterPermissionGrant = false
    @State private var hasShownNameScanSuggestion = false
    @State private var showingNameScanSuggestion = false
    @State private var isSaveFlowActive = false

    private let commonStrengthPresets = ["100 mg", "200 mg", "500 mg", "1 g", "10 ml", "1 滴"]
    private let commonFormPresets = ["片剂", "胶囊", "颗粒剂", "口服液", "滴眼液", "外用", "吸入剂"]

    init(option: MedicationAddOption) {
        self.option = option
        let now = Date()
        _courseStartDate = State(initialValue: now)
        _courseEndDate = State(initialValue: Calendar.current.date(byAdding: .day, value: 30, to: now) ?? now)
        _reminderTimes = State(initialValue: [defaultReminderDate(hour: 21, minute: 0)])
        switch option.id {
        case .manual:
            _kind = State(initialValue: .overTheCounter)
            _selectedPhotoSymbolName = State(initialValue: "pills.fill")
        case .prescriptionDocumentOCR:
            _kind = State(initialValue: .prescription)
            _selectedPhotoSymbolName = State(initialValue: "cross.case.fill")
        case .barcodeScan:
            _kind = State(initialValue: .unknown)
            _selectedPhotoSymbolName = State(initialValue: "pills.fill")
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                if option.id != .manual {
                    Section(option.title) {
                        Text(option.description)
                            .foregroundStyle(.secondary)
                        Text(option.disclaimer)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                if option.id == .prescriptionDocumentOCR {
                    Section("医嘱识别内容") {
                        Button {
                            startCameraFlow(.prescriptionImage)
                        } label: {
                            Label("拍摄医嘱图片识别", systemImage: "camera.viewfinder")
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(!UIImagePickerController.isSourceTypeAvailable(.camera))

                        PhotosPicker(selection: $selectedImageItem, matching: .images) {
                            Label("选择医嘱图片识别", systemImage: "photo.badge.magnifyingglass")
                        }
                        .buttonStyle(.borderedProminent)

                        if isAnalyzingImage {
                            ProgressView("正在识别图片")
                        }
                        if !visionStatusMessage.isEmpty {
                            Text(visionStatusMessage)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }

                        TextEditor(text: $importedText)
                            .frame(minHeight: 96)
                        ImportReviewSummaryView(review: importReview)
                        Label("提取内容必须按原始医嘱二次确认。", systemImage: "doc.text.magnifyingglass")
                            .foregroundStyle(.secondary)
                    }
                }

                if option.id == .barcodeScan {
                    Section("条码待确认信息") {
                        Button {
                            startCameraFlow(.barcodeScanner)
                        } label: {
                            Label("打开相机扫码", systemImage: "camera.viewfinder")
                        }
                        .buttonStyle(.borderedProminent)

                        PhotosPicker(selection: $selectedImageItem, matching: .images) {
                            Label("选择药盒条码图片识别", systemImage: "barcode.viewfinder")
                        }
                        .buttonStyle(.borderedProminent)

                        if isAnalyzingImage {
                            ProgressView("正在识别条码")
                        }
                        if !visionStatusMessage.isEmpty {
                            Text(visionStatusMessage)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        if !recognizedBarcodes.isEmpty {
                            ForEach(recognizedBarcodes) { barcode in
                                Button {
                                    barcodeValue = barcode.payload
                                    importReview = VisionImportService().makeBarcodeReview(barcode: barcode)
                                } label: {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(barcode.payload)
                                            .font(.body.monospaced())
                                        Text("识别结果 · 点击填入")
                                            .font(.footnote)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }

                        TextField("药盒条码或药品追溯码", text: $barcodeValue)
                            .textInputAutocapitalization(.never)
                        Button {
                            makeManualBarcodeReview()
                        } label: {
                            Text("生成待确认信息")
                        }
                        .disabled(barcodeValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        ImportReviewSummaryView(review: importReview)
                        Label("条码结果用于记录药盒来源，保存前请按药盒和说明书核对。", systemImage: "barcode.viewfinder")
                            .foregroundStyle(.secondary)
                    }
                }

                Section("药品信息") {
                    HStack(spacing: 10) {
                        Text("名称")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                            .frame(width: 44, alignment: .leading)
                        TextField("药品名称", text: displayNameBinding)
                            .textInputAutocapitalization(.words)
                            .multilineTextAlignment(.leading)
                        if option.id == .manual {
                            Button {
                                startCameraFlow(.nameScan)
                            } label: {
                                Image(systemName: "camera.viewfinder")
                                    .font(.title3.weight(.semibold))
                                    .foregroundStyle(UIImagePickerController.isSourceTypeAvailable(.camera) ? .blue : .secondary)
                            }
                            .buttonStyle(.plain)
                            .disabled(!UIImagePickerController.isSourceTypeAvailable(.camera))
                            .accessibilityLabel("从 iPhone 扫描药名")
                        }
                    }
                    .padding(.vertical, 2)
                    if isAnalyzingImage {
                        ProgressView("正在扫描药名")
                    }
                    if !visionStatusMessage.isEmpty {
                        Text(visionStatusMessage)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    if !displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !hasMeaningfulDisplayName {
                        Text("请输入可核对的药品名称。")
                            .font(.footnote)
                            .foregroundStyle(.orange)
                    }
                    if option.id != .manual || !genericName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        TextField("通用名（可选）", text: $genericName)
                            .textInputAutocapitalization(.words)
                    }
                    MedicationPresetTextField(
                        title: "规格",
                        placeholder: "例如 200 mg 或 10 ml",
                        presets: commonStrengthPresets,
                        text: $strength
                    )
                    MedicationFormAndUnitRow(
                        title: "形态/单位",
                        placeholder: "例如 片剂、滴眼液",
                        presets: commonFormPresets,
                        form: $form,
                        unit: $doseUnit
                    )
                    Picker("类型", selection: $kind) {
                        Text("非处方药").tag(MedicationKind.overTheCounter)
                        Text("处方药").tag(MedicationKind.prescription)
                        Text("待确认").tag(MedicationKind.unknown)
                    }
                    Stepper(value: $doseValue, in: 0.5...10, step: 0.5) {
                        Text("每次 \(doseValue.formatted())")
                    }
                }

                Section("药盒照片与编号") {
                    TextField("药盒编号，例如 A1", text: $boxNumber)
                        .textInputAutocapitalization(.characters)
                    Button {
                        showingMedicationPhotoSourceDialog = true
                    } label: {
                        MedicationHeroPhotoView(
                            photoData: medicationPhotoData,
                            symbolName: selectedPhotoSymbolName,
                            tint: .blue,
                            title: medicationPhotoData == nil ? "在此处添加照片" : "药盒或药品照片",
                            subtitle: boxNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "用于提醒和记录核对。" : "药盒编号已记录。",
                            boxNumber: boxNumber
                        )
                    }
                    .buttonStyle(.plain)
                    if medicationPhotoData != nil {
                        Button("清除当前图片") {
                            medicationPhotoData = nil
                            selectedMedicationPhotoItem = nil
                        }
                    }
                }

                Section("疗程与提醒") {
                    DatePicker("疗程开始", selection: $courseStartDate, displayedComponents: .date)
                    Toggle("设置疗程结束", isOn: $hasCourseEndDate)
                    if hasCourseEndDate {
                        DatePicker("疗程结束", selection: $courseEndDate, in: courseStartDate..., displayedComponents: .date)
                    }
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
                }

                Section("药盒库存（可选）") {
                    HStack {
                        Text("剩余数量")
                        Spacer()
                        TextField("0", value: $initialStockQuantity, format: .number.precision(.fractionLength(0...1)))
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 92)
                        Text(localizedMedicationUnit(stockUnit))
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("低量提醒")
                        Spacer()
                        TextField("0", value: $lowStockThreshold, format: .number.precision(.fractionLength(0...1)))
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 92)
                        Text(localizedMedicationUnit(stockUnit))
                            .foregroundStyle(.secondary)
                    }
                    MedicationUnitPicker(title: "库存单位", unit: $stockUnit)
                }
            }
            .navigationTitle("添加药品")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        showingSaveConfirmation = true
                    }
                    .disabled(!canSave || isSaveFlowActive)
                }
            }
            .onAppear {
                if option.id != .manual {
                    showingReviewAlert = true
                }
            }
            .alert(option.title, isPresented: $showingReviewAlert) {
                Button("我知道了", role: .cancel) {}
            } message: {
                Text(option.disclaimer)
            }
            .alert("确认保存药品？", isPresented: $showingSaveConfirmation) {
                Button("返回核对", role: .cancel) {}
                Button("已核对，保存") {
                    beginSaveMedicationFlow()
                }
            } message: {
                Text("请确认药品名称、规格、药品形态、每次用量和提醒时间已按药盒、说明书、医生或药师建议核对。")
            }
            .alert("也可以扫描药品名称", isPresented: $showingNameScanSuggestion) {
                Button("继续输入", role: .cancel) {}
                Button("使用扫描") {
                    startCameraFlow(.nameScan)
                }
            } message: {
                Text("你可以点名称右侧的相机图标，扫描药盒上的药品名称。扫描文字仍需按药盒或说明书二次核查。")
            }
            .sheet(isPresented: $showingMedicationPhotoSourceDialog) {
                MedicationPhotoSourceSheet(
                    hasPhoto: medicationPhotoData != nil,
                    canUseCamera: UIImagePickerController.isSourceTypeAvailable(.camera),
                    selectedPhotoItem: $selectedMedicationPhotoItem,
                    takePhoto: {
                        showingMedicationPhotoSourceDialog = false
                        startCameraFlow(.medicationPhoto)
                    },
                    clearPhoto: {
                        medicationPhotoData = nil
                        selectedMedicationPhotoItem = nil
                        showingMedicationPhotoSourceDialog = false
                    }
                )
                .presentationDetents([.height(medicationPhotoData == nil ? 240 : 300)])
                .presentationDragIndicator(.visible)
            }
            .appPermissionPrimer(pendingGate: $pendingPermissionGate) { gate in
                Task {
                    await continueAfterPermissionPrimer(gate)
                }
            }
            .sheet(isPresented: $showingCameraScanner) {
                BarcodeScannerSheet { payload, symbology in
                    cancelVisionAnalysis()
                    let barcode = VisionBarcodeRecognitionResult(
                        payload: payload,
                        symbology: symbology,
                        confidence: 1
                    )
                    barcodeValue = payload
                    recognizedBarcodes = [barcode]
                    importReview = VisionImportService().makeBarcodeReview(barcode: barcode)
                    visionStatusMessage = "已通过相机识别条码，保存前仍需核对药盒与说明书。"
                }
            }
            .sheet(isPresented: $showingPrescriptionImageCamera) {
                CameraPhotoCaptureSheet { image in
                    guard let data = image.jpegData(compressionQuality: 0.9) else {
                        visionStatusMessage = "没有读取到医嘱图片，请重新拍摄。"
                        return
                    }
                    startVisionAnalysis(data, purpose: .prescription)
                }
            }
            .sheet(isPresented: $showingNameScanCamera) {
                CameraPhotoCaptureSheet { image in
                    let data = image.jpegData(compressionQuality: 0.9) ?? Data()
                    startVisionAnalysis(data, purpose: .medicationName)
                }
            }
            .sheet(isPresented: $showingMedicationPhotoCamera) {
                CameraPhotoCaptureSheet { image in
                    medicationPhotoData = normalizedPhotoData(image)
                }
            }
            .onChange(of: selectedImageItem) { _, newItem in
                startSelectedImageAnalysis(newItem)
            }
            .onChange(of: selectedMedicationPhotoItem) { _, newItem in
                Task {
                    await loadMedicationPhoto(newItem)
                }
            }
            .onDisappear {
                cancelVisionAnalysis()
            }
        }
    }

    private var displayNameBinding: Binding<String> {
        Binding(
            get: { displayName },
            set: { newValue in
                if option.id == .manual,
                   !hasShownNameScanSuggestion,
                   displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                   !newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    hasShownNameScanSuggestion = true
                    showingNameScanSuggestion = true
                }
                displayName = newValue
            }
        )
    }

    private var canSave: Bool {
        hasMeaningfulDisplayName
    }

    private var hasMeaningfulDisplayName: Bool {
        MedicationNamePolicy.normalizedDisplayName(displayName) != nil
    }

    private var inputSource: MedicationInputSource {
        switch option.id {
        case .manual:
            .manual
        case .prescriptionDocumentOCR:
            .prescriptionImage
        case .barcodeScan:
            .barcode
        }
    }

    private func makeManualBarcodeReview() {
        cancelVisionAnalysis()
        let trimmedBarcode = barcodeValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedBarcode.isEmpty else {
            return
        }
        let barcode = VisionBarcodeRecognitionResult(
            payload: trimmedBarcode,
            symbology: "manual",
            confidence: 1
        )
        recognizedBarcodes = [barcode]
        importReview = VisionImportService().makeBarcodeReview(barcode: barcode)
        visionStatusMessage = "已生成待确认信息，请核对药盒与说明书。"
    }

    private func startCameraFlow(_ action: AddMedicationCameraAction) {
        guard AppPermissionGate.isCameraAvailable() else {
            visionStatusMessage = "当前设备没有可用相机。"
            return
        }
        if AppPermissionGate.isCameraAuthorized() {
            openCameraAction(action)
            return
        }
        pendingCameraAction = action
        if AppPermissionGate.hasCompletedAuthorization(for: .camera) {
            Task {
                await requestCameraAccessAndOpenPendingAction()
            }
        } else {
            pendingPermissionGate = .camera
        }
    }

    private func openCameraAction(_ action: AddMedicationCameraAction) {
        switch action {
        case .barcodeScanner:
            showingCameraScanner = true
        case .prescriptionImage:
            showingPrescriptionImageCamera = true
        case .nameScan:
            showingNameScanCamera = true
        case .medicationPhoto:
            showingMedicationPhotoCamera = true
        }
    }

    @MainActor
    private func requestCameraAccessAndOpenPendingAction() async {
        guard let action = pendingCameraAction else {
            return
        }
        guard await AppPermissionGate.requestCameraAccess() else {
            visionStatusMessage = "相机权限未开启，无法使用拍摄或扫码。"
            pendingCameraAction = nil
            return
        }
        pendingCameraAction = nil
        openCameraAction(action)
    }

    private func beginSaveMedicationFlow() {
        Task {
            await saveMedicationAfterPermissionCheck()
        }
    }

    @MainActor
    private func saveMedicationAfterPermissionCheck() async {
        shouldSaveAfterPermissionGrant = true
        guard await ensureReminderPermissionForSave() else {
            if pendingPermissionGate == nil {
                shouldSaveAfterPermissionGrant = false
            }
            return
        }
        guard await ensureEscalationAlarmPermissionForSave() else {
            if pendingPermissionGate == nil {
                shouldSaveAfterPermissionGrant = false
            }
            return
        }
        shouldSaveAfterPermissionGrant = false
        saveMedication()
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
                visionStatusMessage = "通知权限未开启，暂不能保存为推送提醒。"
            }
            return granted
        case .alarm:
            let granted = await AppPermissionGate.requestAlarmAccess()
            if granted {
                AppPermissionGate.markAuthorizationCompleted(for: .alarm)
            } else {
                visionStatusMessage = "iPhone 闹钟权限未开启，暂不能保存为闹钟提醒。"
            }
            return granted
        case .camera, .health, .location:
            return false
        }
    }

    @MainActor
    private func continueAfterPermissionPrimer(_ gate: AppPermissionGate) async {
        switch gate {
        case .camera:
            await requestCameraAccessAndOpenPendingAction()
        case .notifications, .alarm:
            guard shouldSaveAfterPermissionGrant else {
                return
            }
            guard await requestReminderPermissionForSave(gate) else {
                shouldSaveAfterPermissionGrant = false
                return
            }
            await saveMedicationAfterPermissionCheck()
        case .health, .location:
            break
        }
    }

    private func saveMedication() {
        guard !isSaveFlowActive else { return }
        isSaveFlowActive = true
        let noteParts = [
            option.disclaimer,
            importedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : "识别文字：\(importedText.trimmingCharacters(in: .whitespacesAndNewlines))",
            barcodeValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : "条码信息：\(barcodeValue.trimmingCharacters(in: .whitespacesAndNewlines))"
        ].compactMap { $0 }

        let occurredAt = Date()
        let outcome = MedicationCreationCommand(modelContext: modelContext).create(
            MedicationCreationInput(
                displayName: displayName,
                genericName: genericName,
                kind: kind,
                form: form,
                strength: strength,
                inputSource: inputSource,
                photoSymbolName: selectedPhotoSymbolName,
                photoData: medicationPhotoData,
                boxNumber: boxNumber,
                notes: noteParts.joined(separator: "\n"),
                doseValue: doseValue,
                doseUnit: doseUnit,
                courseStartAt: courseStartDate,
                courseEndAt: hasCourseEndDate ? courseEndDate : nil,
                reminderTimes: reminderTimes,
                reminderDeliveryMethod: reminderDeliveryMethod,
                escalatesToAlarmWhenUnhandled: escalatesToAlarmWhenUnhandled,
                initialStockQuantity: initialStockQuantity,
                lowStockThreshold: lowStockThreshold,
                stockUnit: stockUnit,
                createdAt: occurredAt
            )
        )
        switch outcome {
        case let .committed(_, _, reminderBatch):
            let schedulingSnapshot = MedicationReminderPostCommitSnapshot(batch: reminderBatch)
            dismiss()
            MedicationReminderPostCommitDispatcher.dispatch(schedulingSnapshot)
        case .rejected:
            visionStatusMessage = "药品未能保存，请检查药品名称后重试。"
            isSaveFlowActive = false
        case .saveFailed:
            visionStatusMessage = AppPersistenceCommitter.failureUserMessage
            isSaveFlowActive = false
        }
    }

    private func startSelectedImageAnalysis(_ item: PhotosPickerItem?) {
        guard let item else {
            cancelVisionAnalysis()
            return
        }
        let purpose: VisionImportPurpose = option.id == .barcodeScan ? .barcode : .prescription
        let requestID = beginVisionAnalysis(purpose: purpose)
        visionAnalysisTask = Task { @MainActor in
            do {
                guard let data = try await item.loadTransferable(type: Data.self) else {
                    throw VisionImportError.imageDataUnavailable
                }
                try await runVisionAnalysis(data, purpose: purpose, requestID: requestID)
            } catch {
                finishVisionAnalysis(requestID: requestID, purpose: purpose, error: error)
            }
        }
    }

    private func startVisionAnalysis(_ data: Data, purpose: VisionImportPurpose) {
        let requestID = beginVisionAnalysis(purpose: purpose)
        visionAnalysisTask = Task { @MainActor in
            do {
                try await runVisionAnalysis(data, purpose: purpose, requestID: requestID)
            } catch {
                finishVisionAnalysis(requestID: requestID, purpose: purpose, error: error)
            }
        }
    }

    private func beginVisionAnalysis(purpose: VisionImportPurpose) -> UUID {
        visionAnalysisTask?.cancel()
        let requestID = visionGenerationGate.begin()
        isAnalyzingImage = true
        visionStatusMessage = ""
        if purpose == .prescription || purpose == .barcode {
            importReview = nil
            recognizedBarcodes = []
        }
        return requestID
    }

    private func runVisionAnalysis(
        _ data: Data,
        purpose: VisionImportPurpose,
        requestID: UUID
    ) async throws {
        let output = try await VisionImportPipeline().analyze(data, purpose: purpose)
        guard visionGenerationGate.finish(requestID) else { return }
        isAnalyzingImage = false
        visionAnalysisTask = nil
        applyVisionOutput(output)
    }

    private func applyVisionOutput(_ output: VisionImportPipelineOutput) {
        switch output {
        case let .prescription(result, review):
            importedText = result.text
            importReview = review
            if let extractedDisplayName = review.draft.displayName,
               !extractedDisplayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               !hasMeaningfulDisplayName {
                displayName = extractedDisplayName
            }
            if genericName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               let extractedGenericName = review.draft.genericName,
               !extractedGenericName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                genericName = extractedGenericName
            }
            if strength.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               let extractedStrength = review.draft.strength,
               !extractedStrength.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                strength = extractedStrength
            }
            if form.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               let extractedForm = review.draft.form,
               !extractedForm.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                form = extractedForm
            }
            if isDefaultDoseInput,
               let extractedDoseValue = review.draft.doseValue,
               let extractedDoseUnit = review.draft.doseUnit,
               !extractedDoseUnit.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                doseValue = extractedDoseValue
                doseUnit = extractedDoseUnit
                stockUnit = extractedDoseUnit
            }
            let extractedFieldTitles = importFieldTitles(from: review.draft)
            visionStatusMessage = extractedFieldTitles.isEmpty
                ? "已识别图片文字，请按原始医嘱核对后保存。"
                : "已提取到\(extractedFieldTitles.joined(separator: "、"))；请按原始医嘱核对。"
        case let .barcodes(barcodes):
            recognizedBarcodes = barcodes
            if let first = barcodes.first {
                barcodeValue = first.payload
                importReview = VisionImportService().makeBarcodeReview(barcode: first)
                visionStatusMessage = "已识别条码并填入待确认信息。"
            }
        case let .medicationName(_, scannedName, structuredFields):
            if let scannedName {
                displayName = scannedName
                if genericName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                   let extractedGenericName = structuredFields.genericName {
                    genericName = extractedGenericName
                }
                visionStatusMessage = "已扫描到药品名称，保存前请按药盒核对。"
            } else {
                visionStatusMessage = "未识别到清晰药名，请手动输入。"
            }
        case .labelText:
            break
        }
    }

    private func finishVisionAnalysis(
        requestID: UUID,
        purpose: VisionImportPurpose,
        error: Error
    ) {
        guard visionGenerationGate.finish(requestID) else { return }
        isAnalyzingImage = false
        visionAnalysisTask = nil
        guard !(error is CancellationError) else { return }
        if purpose == .medicationName {
            visionStatusMessage = "扫描失败，请手动输入药品名称。"
        } else {
            visionStatusMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func cancelVisionAnalysis() {
        visionAnalysisTask?.cancel()
        visionAnalysisTask = nil
        visionGenerationGate.cancel()
        isAnalyzingImage = false
    }

    private var isDefaultDoseInput: Bool {
        abs(doseValue - 1) < 0.0001 && localizedMedicationUnit(doseUnit) == "片"
    }

    private func importFieldTitles(from draft: MedicationImportDraft) -> [String] {
        [
            ("药品名称", draft.displayName),
            ("通用名", draft.genericName),
            ("规格", draft.strength),
            ("剂型", draft.form),
            ("每次剂量", formattedImportedDose(from: draft)),
            ("用法用量", draft.directionsText)
        ].compactMap { title, value in
            guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !value.isEmpty
            else {
                return nil
            }
            return title
        }
    }

    private func formattedImportedDose(from draft: MedicationImportDraft) -> String? {
        guard let doseValue = draft.doseValue,
              let doseUnit = draft.doseUnit?.trimmingCharacters(in: .whitespacesAndNewlines),
              !doseUnit.isEmpty
        else {
            return nil
        }
        return "\(doseValue.formatted()) \(localizedMedicationUnit(doseUnit))"
    }

    private func loadMedicationPhoto(_ item: PhotosPickerItem?) async {
        guard let item else {
            return
        }
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                return
            }
            medicationPhotoData = normalizedPhotoData(data)
        } catch {
            medicationPhotoData = nil
        }
    }
}

struct StockProjectionView: View {
    let projection: MedicationStockProjection

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(formatDecimal(projection.projectedRemainingQuantity))
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(projection.needsRefillReminder ? .orange : .primary)
                Text(localizedMedicationUnit(projection.unit))
                    .foregroundStyle(.secondary)
                Spacer()
                StatusBadge(
                    text: projection.needsRefillReminder ? "需要核对药盒" : "药盒正常",
                    color: projection.needsRefillReminder ? .orange : .green
                )
            }
            Text(localizedStockProjectionMessage(projection))
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if !projection.issues.isEmpty {
                ForEach(Array(projection.issues.enumerated()), id: \.offset) { _, issue in
                    Text(issue.message)
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }
            }
        }
        .padding(.vertical, 6)
    }
}

struct MedicationDoseChangeRow: View {
    let change: StoredMedicationDoseChange
    let effectiveUntil: Date?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.headline.weight(.semibold))
                .foregroundStyle(.purple)
                .frame(width: 34, height: 34)
                .background(Color.purple.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 5) {
                Text(doseChangeText)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(effectivePeriodText)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                if !change.note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(change.note)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
    }

    private var doseChangeText: String {
        let newDose = "\(change.newDoseValue.formatted()) \(localizedMedicationUnit(change.newDoseUnit))"
        guard let previousDoseValue = change.previousDoseValue else {
            return "初始剂量 \(newDose)"
        }
        let previousDose = "\(previousDoseValue.formatted()) \(localizedMedicationUnit(change.previousDoseUnit))"
        return "\(previousDose) 调整为 \(newDose)"
    }

    private var effectivePeriodText: String {
        medicationDoseChangeEffectivePeriodText(change: change, effectiveUntil: effectiveUntil)
    }
}

struct MedicationLabelImporterView: View {
    @Environment(\.dismiss) private var dismiss
    let medication: StoredMedication
    let existingLabel: StoredMedicationLabel?
    let save: (String, String, Double) -> Void
    @State private var rawText: String
    @State private var sourceTitle: String
    @State private var confidence: Double
    @State private var selectedImageItem: PhotosPickerItem?
    @State private var isRecognizing = false
    @State private var statusMessage = ""
    @State private var recognitionTask: Task<Void, Never>?
    @State private var recognitionGate = VisionImportGenerationGate()
    @State private var showingCameraCapture = false
    @State private var showingSaveConfirmation = false
    @State private var pendingPermissionGate: AppPermissionGate?

    init(
        medication: StoredMedication,
        existingLabel: StoredMedicationLabel?,
        save: @escaping (String, String, Double) -> Void
    ) {
        self.medication = medication
        self.existingLabel = existingLabel
        self.save = save
        _rawText = State(initialValue: existingLabel?.rawText ?? "")
        _sourceTitle = State(initialValue: Self.initialSourceTitle(for: existingLabel))
        _confidence = State(initialValue: existingLabel?.averageOCRConfidence ?? 1)
    }

    private var canSave: Bool {
        !rawText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private static func initialSourceTitle(for label: StoredMedicationLabel?) -> String {
        guard let sourceTitle = label?.sourceTitle.trimmingCharacters(in: .whitespacesAndNewlines), !sourceTitle.isEmpty else {
            return "用户导入说明书"
        }
        return sourceTitle == "本地保存说明书摘要" ? "用户确认说明书" : sourceTitle
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("导入方式") {
                    Button {
                        startCameraCaptureFlow()
                    } label: {
                        Label("拍摄说明书", systemImage: "camera")
                    }
                    .disabled(!UIImagePickerController.isSourceTypeAvailable(.camera))

                    PhotosPicker(selection: $selectedImageItem, matching: .images) {
                        Label("选择说明书图片", systemImage: "photo.on.rectangle")
                    }

                    TextField("来源标题", text: $sourceTitle)
                    if isRecognizing {
                        ProgressView("正在识别说明书文字")
                    }
                    if !statusMessage.isEmpty {
                        Text(statusMessage)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("说明书内容") {
                    TextEditor(text: $rawText)
                        .frame(minHeight: 220)
                        .onChange(of: rawText) { _, _ in
                            if isRecognizing {
                                cancelLabelRecognition()
                            }
                        }
                    Text("请先按药盒或说明书原件核对文字。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("保存后用于") {
                    Text("App 会根据说明书内容生成风险提醒；不会自动诊断、处方或调整剂量。如有禁忌、相互作用或不适，请咨询医生或药师。")
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("导入说明书")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存并识别") {
                        showingSaveConfirmation = true
                    }
                    .disabled(!canSave)
                }
            }
            .alert("确认保存说明书？", isPresented: $showingSaveConfirmation) {
                Button("取消", role: .cancel) {}
                Button("已核对，保存") {
                    save(rawText, sourceTitle, confidence)
                    dismiss()
                }
            } message: {
                Text("请确认已按药盒或说明书原件核对文字。保存后会更新本药品的说明书摘要，并重新生成风险提醒。")
            }
            .onChange(of: selectedImageItem) { _, newItem in
                startSelectedLabelRecognition(newItem)
            }
            .sheet(isPresented: $showingCameraCapture) {
                CameraPhotoCaptureSheet { image in
                    let data = image.jpegData(compressionQuality: 0.9) ?? Data()
                    startLabelRecognition(data)
                }
            }
            .appPermissionPrimer(pendingGate: $pendingPermissionGate) { gate in
                guard gate == .camera else {
                    return
                }
                Task {
                    await requestCameraCaptureAccess()
                }
            }
            .onDisappear {
                cancelLabelRecognition()
            }
        }
    }

    private func startCameraCaptureFlow() {
        guard AppPermissionGate.isCameraAvailable() else {
            statusMessage = "当前设备没有可用相机。"
            return
        }
        if AppPermissionGate.isCameraAuthorized() {
            showingCameraCapture = true
            return
        }
        if AppPermissionGate.hasCompletedAuthorization(for: .camera) {
            Task {
                await requestCameraCaptureAccess()
            }
        } else {
            pendingPermissionGate = .camera
        }
    }

    @MainActor
    private func requestCameraCaptureAccess() async {
        guard await AppPermissionGate.requestCameraAccess() else {
            statusMessage = "相机权限未开启，无法拍摄说明书。"
            return
        }
        showingCameraCapture = true
    }

    private func startSelectedLabelRecognition(_ item: PhotosPickerItem?) {
        guard let item else {
            cancelLabelRecognition()
            return
        }
        let requestID = beginLabelRecognition()
        recognitionTask = Task { @MainActor in
            do {
                guard let data = try await item.loadTransferable(type: Data.self) else {
                    throw VisionImportError.imageDataUnavailable
                }
                try await runLabelRecognition(data, requestID: requestID)
            } catch {
                finishLabelRecognition(requestID: requestID, error: error)
            }
        }
    }

    private func startLabelRecognition(_ data: Data) {
        let requestID = beginLabelRecognition()
        recognitionTask = Task { @MainActor in
            do {
                try await runLabelRecognition(data, requestID: requestID)
            } catch {
                finishLabelRecognition(requestID: requestID, error: error)
            }
        }
    }

    private func beginLabelRecognition() -> UUID {
        recognitionTask?.cancel()
        let requestID = recognitionGate.begin()
        isRecognizing = true
        statusMessage = ""
        return requestID
    }

    private func runLabelRecognition(_ data: Data, requestID: UUID) async throws {
        let output = try await VisionImportPipeline().analyze(data, purpose: .labelText)
        guard recognitionGate.finish(requestID) else { return }
        isRecognizing = false
        recognitionTask = nil
        guard case let .labelText(result) = output else { return }
        rawText = result.text
        confidence = result.averageConfidence
        sourceTitle = sourceTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "说明书图片导入"
            : sourceTitle
        statusMessage = "已识别说明书文字，请按原文核对后保存。"
    }

    private func finishLabelRecognition(requestID: UUID, error: Error) {
        guard recognitionGate.finish(requestID) else { return }
        isRecognizing = false
        recognitionTask = nil
        guard !(error is CancellationError) else { return }
        statusMessage = (error as? LocalizedError)?.errorDescription ?? "未识别到清晰文字，请重试或直接粘贴。"
    }

    private func cancelLabelRecognition() {
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionGate.cancel()
        isRecognizing = false
    }
}

func localizedStockProjectionMessage(_ projection: MedicationStockProjection) -> String {
    let remaining = formatDecimal(projection.projectedRemainingQuantity)
    let unit = localizedMedicationUnit(projection.unit)
    if projection.needsRefillReminder {
        return "库存已达到低库存阈值，估算剩余 \(remaining) \(unit)，请及时核对实物库存。"
    }
    return "库存暂未达到低库存阈值，估算剩余 \(remaining) \(unit)。"
}

struct StockEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    let medication: StoredMedication
    let stock: StoredMedicationStock?
    @State private var remainingQuantity: Double
    @State private var lowStockThreshold: Double
    @State private var unit: String

    init(medication: StoredMedication, stock: StoredMedicationStock?) {
        self.medication = medication
        self.stock = stock
        _remainingQuantity = State(initialValue: stock?.remainingQuantity ?? 0)
        _lowStockThreshold = State(initialValue: stock?.lowStockThreshold ?? 0)
        _unit = State(initialValue: localizedMedicationUnit(stock?.unit ?? "片"))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(userFacingMedicationName(for: medication)) {
                    Stepper(value: $remainingQuantity, in: 0...9999, step: 1) {
                        Text("药盒剩余 \(remainingQuantity.formatted()) \(localizedMedicationUnit(unit))")
                    }
                    Stepper(value: $lowStockThreshold, in: 0...9999, step: 1) {
                        Text("低库存阈值 \(lowStockThreshold.formatted()) \(localizedMedicationUnit(unit))")
                    }
                    MedicationUnitPicker(title: "单位", unit: $unit)
                }

            }
            .navigationTitle("药盒库存")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        save()
                    }
                    .disabled(unit.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private func save() {
        let outcome = MedicationInventoryCommand(modelContext: modelContext).upsert(
            MedicationInventoryUpdate(
                medicationID: medication.id,
                remainingQuantity: remainingQuantity,
                unit: unit,
                lowStockThreshold: lowStockThreshold,
                updatedAt: Date()
            )
        )
        guard case .committed = outcome else {
            return
        }
        dismiss()
    }
}
