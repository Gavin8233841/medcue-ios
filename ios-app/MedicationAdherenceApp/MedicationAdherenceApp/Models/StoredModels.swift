import Foundation
import MedicationAdherenceCore
import SwiftData

enum StoredDoseStatus: String, CaseIterable, Identifiable {
    case pending
    case taken
    case delayed
    case skipped
    case corrected

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .pending:
            "待服用"
        case .taken:
            "已服用"
        case .delayed:
            "稍后提醒"
        case .skipped:
            "已忽略"
        case .corrected:
            "已修正"
        }
    }

    var coreStatus: DoseEventStatus? {
        switch self {
        case .pending:
            nil
        case .taken:
            .taken
        case .delayed:
            .delayed
        case .skipped:
            .skipped
        case .corrected:
            .corrected
        }
    }
}

enum StoredAIChatRole: String, CaseIterable, Identifiable {
    case user
    case assistant
    case system

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .user:
            "用户"
        case .assistant:
            "医疗 AI"
        case .system:
            "系统"
        }
    }
}

enum StoredReminderDeliveryMethod: String, CaseIterable, Identifiable {
    case notification
    case alarm

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .notification:
            "推送通知"
        case .alarm:
            "iPhone 闹钟"
        }
    }

    var detailText: String {
        switch self {
        case .notification:
            "适合普通服药提醒，会受通知权限、勿扰模式和静音设置影响。"
        case .alarm:
            "适合必须按时处理的提醒；闹钟更醒目，可能无视勿扰模式和静音。"
        }
    }
}

enum StoredMedicationLifecycleStatus: String, CaseIterable, Identifiable {
    case active
    case interrupted
    case archived

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .active:
            "正在服用"
        case .interrupted:
            "服用中断"
        case .archived:
            "归档药物"
        }
    }

    var badgeColorName: String {
        switch self {
        case .active:
            "green"
        case .interrupted:
            "orange"
        case .archived:
            "gray"
        }
    }
}

@Model
final class StoredMedication {
    @Attribute(.unique) var id: UUID
    var displayName: String
    var genericName: String
    var kindRaw: String
    var form: String
    var strength: String
    var inputSourceRaw: String
    var photoSymbolName: String
    var photoData: Data?
    var notes: String
    var lifecycleStatusRaw: String = StoredMedicationLifecycleStatus.active.rawValue
    var isDemoContent: Bool = false
    var createdAt: Date

    init(
        id: UUID = UUID(),
        displayName: String,
        genericName: String = "",
        kind: MedicationKind,
        form: String = "",
        strength: String = "",
        inputSource: MedicationInputSource,
        photoSymbolName: String = "pills.fill",
        photoData: Data? = nil,
        notes: String = "",
        lifecycleStatus: StoredMedicationLifecycleStatus = .active,
        isDemoContent: Bool = false,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.displayName = displayName
        self.genericName = genericName
        self.kindRaw = kind.rawValue
        self.form = form
        self.strength = strength
        self.inputSourceRaw = inputSource.rawValue
        self.photoSymbolName = photoSymbolName
        self.photoData = photoData
        self.notes = notes
        self.lifecycleStatusRaw = lifecycleStatus.rawValue
        self.isDemoContent = isDemoContent
        self.createdAt = createdAt
    }

    var coreMedication: Medication {
        Medication(
            id: id,
            displayName: displayName,
            genericName: genericName.isEmpty ? nil : genericName,
            kind: MedicationKind(rawValue: kindRaw) ?? .unknown,
            form: form.isEmpty ? nil : form,
            strength: strength.isEmpty ? nil : strength,
            inputSource: MedicationInputSource(rawValue: inputSourceRaw) ?? .manual,
            notes: notes
        )
    }

    var kindDisplayName: String {
        switch MedicationKind(rawValue: kindRaw) ?? .unknown {
        case .overTheCounter:
            "非处方药"
        case .prescription:
            "处方药"
        case .unknown:
            "待确认"
        }
    }

    var lifecycleStatus: StoredMedicationLifecycleStatus {
        get { StoredMedicationLifecycleStatus(rawValue: lifecycleStatusRaw) ?? .active }
        set { lifecycleStatusRaw = newValue.rawValue }
    }
}

@Model
final class StoredMedicationPlan {
    @Attribute(.unique) var id: UUID
    var medicationID: UUID
    var doseValue: Double
    var doseUnit: String
    var timingSummary: String
    var timeZonePolicyRaw: String
    var sourceNote: String
    var requiresUserConfirmation: Bool
    var courseStartAt: Date?
    var courseEndAt: Date?
    var reminderTimesRaw: String?
    var reminderDeliveryRaw: String?
    var createdAt: Date

    init(
        id: UUID = UUID(),
        medicationID: UUID,
        doseValue: Double,
        doseUnit: String,
        timingSummary: String,
        timeZonePolicy: ReminderTimeZonePolicy,
        sourceNote: String,
        requiresUserConfirmation: Bool = true,
        courseStartAt: Date? = nil,
        courseEndAt: Date? = nil,
        reminderTimesRaw: String? = nil,
        reminderDelivery: StoredReminderDeliveryMethod = .notification,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.medicationID = medicationID
        self.doseValue = doseValue
        self.doseUnit = doseUnit
        self.timingSummary = timingSummary
        self.timeZonePolicyRaw = timeZonePolicy.rawValue
        self.sourceNote = sourceNote
        self.requiresUserConfirmation = requiresUserConfirmation
        self.courseStartAt = courseStartAt
        self.courseEndAt = courseEndAt
        self.reminderTimesRaw = reminderTimesRaw
        self.reminderDeliveryRaw = reminderDelivery.rawValue
        self.createdAt = createdAt
    }

    var reminderDeliveryMethod: StoredReminderDeliveryMethod {
        get { StoredReminderDeliveryMethod(rawValue: reminderDeliveryRaw ?? "") ?? .notification }
        set { reminderDeliveryRaw = newValue.rawValue }
    }

    func corePlan(using scheduledDoses: [StoredDoseTask], calendar: Calendar = .current) -> MedicationPlan? {
        guard let firstDose = scheduledDoses.first(where: { $0.planID == id }) else {
            return nil
        }
        let startComponents = calendar.dateComponents([.year, .month, .day], from: courseStartAt ?? firstDose.dueAt)
        guard let year = startComponents.year, let month = startComponents.month, let day = startComponents.day else {
            return nil
        }
        let fallbackComponents = calendar.dateComponents([.hour, .minute], from: firstDose.dueAt)
        let fallbackTime = fallbackComponents.hour.flatMap { hour in
            fallbackComponents.minute.flatMap { minute in
                try? TimeOfDay(hour: hour, minute: minute)
            }
        }
        let storedTimes = reminderTimesRaw?
            .split(separator: ",")
            .compactMap { timeOfDay(from: String($0)) } ?? []
        let timeOfDays = storedTimes.isEmpty ? fallbackTime.map { [$0] } ?? [] : storedTimes
        guard !timeOfDays.isEmpty else {
            return nil
        }
        return MedicationPlan(
            id: id,
            medicationID: medicationID,
            dose: DoseAmount(value: Decimal(doseValue), unit: doseUnit),
            startDate: DateOnly(year: year, month: month, day: day),
            timingRule: .fixedLocalTimes(timeOfDays),
            timeZonePolicy: ReminderTimeZonePolicy(rawValue: timeZonePolicyRaw) ?? .localClock,
            sourceNote: sourceNote,
            requiresUserConfirmation: requiresUserConfirmation
        )
    }

    private func timeOfDay(from rawValue: String) -> TimeOfDay? {
        let parts = rawValue.split(separator: ":")
        guard parts.count == 2, let hour = Int(parts[0]), let minute = Int(parts[1]) else {
            return nil
        }
        return try? TimeOfDay(hour: hour, minute: minute)
    }
}

@Model
final class StoredDoseTask {
    @Attribute(.unique) var id: UUID
    var medicationID: UUID
    var planID: UUID
    var dueAt: Date
    var doseValue: Double
    var doseUnit: String
    var statusRaw: String
    var recordedAt: Date?
    var reason: String

    init(
        id: UUID = UUID(),
        medicationID: UUID,
        planID: UUID = UUID(),
        dueAt: Date,
        doseValue: Double,
        doseUnit: String,
        status: StoredDoseStatus = .pending,
        recordedAt: Date? = nil,
        reason: String = ""
    ) {
        self.id = id
        self.medicationID = medicationID
        self.planID = planID
        self.dueAt = dueAt
        self.doseValue = doseValue
        self.doseUnit = doseUnit
        self.statusRaw = status.rawValue
        self.recordedAt = recordedAt
        self.reason = reason
    }

    var status: StoredDoseStatus {
        get { StoredDoseStatus(rawValue: statusRaw) ?? .pending }
        set { statusRaw = newValue.rawValue }
    }

    var coreScheduledDose: ScheduledDose {
        ScheduledDose(
            id: id,
            planID: planID,
            dueAt: dueAt,
            dose: DoseAmount(value: Decimal(doseValue), unit: doseUnit)
        )
    }

    var coreDoseEvent: DoseEvent? {
        guard let coreStatus = status.coreStatus else {
            return nil
        }
        return DoseEvent(
            scheduledDoseID: id,
            status: coreStatus,
            recordedAt: recordedAt ?? Date(),
            reason: reason.isEmpty ? nil : reason
        )
    }
}

@Model
final class StoredRiskCard {
    @Attribute(.unique) var id: String
    var medicationID: UUID
    var kindRaw: String
    var displayPriority: Int
    var title: String
    var message: String
    var sourceTitle: String
    var sourceExcerpt: String
    var requiresProfessionalReview: Bool
    var safetyNote: String
    var reviewedAt: Date?
    var archivedAt: Date?
    var reviewNote: String = ""

    init(
        id: String,
        medicationID: UUID,
        kindRaw: String,
        displayPriority: Int,
        title: String,
        message: String,
        sourceTitle: String = "",
        sourceExcerpt: String = "",
        requiresProfessionalReview: Bool,
        safetyNote: String,
        reviewedAt: Date? = nil,
        archivedAt: Date? = nil,
        reviewNote: String = ""
    ) {
        self.id = id
        self.medicationID = medicationID
        self.kindRaw = kindRaw
        self.displayPriority = displayPriority
        self.title = title
        self.message = message
        self.sourceTitle = sourceTitle
        self.sourceExcerpt = sourceExcerpt
        self.requiresProfessionalReview = requiresProfessionalReview
        self.safetyNote = safetyNote
        self.reviewedAt = reviewedAt
        self.archivedAt = archivedAt
        self.reviewNote = reviewNote
    }

    var isReviewed: Bool {
        reviewedAt != nil
    }

    var isArchived: Bool {
        archivedAt != nil
    }

    var coreRiskCard: RiskAssessmentCard {
        let evidence: RiskAssessmentEvidence?
        if sourceTitle.isEmpty && sourceExcerpt.isEmpty {
            evidence = nil
        } else {
            evidence = RiskAssessmentEvidence(sourceTitle: sourceTitle, excerpt: sourceExcerpt)
        }
        return RiskAssessmentCard(
            id: id,
            kind: RiskAssessmentCardKind(rawValue: kindRaw) ?? .labelRisk,
            displayPriority: displayPriority,
            title: title,
            message: message,
            evidence: evidence,
            requiresProfessionalReview: requiresProfessionalReview,
            safetyNote: safetyNote
        )
    }
}

@Model
final class StoredMedicationLabel {
    @Attribute(.unique) var id: UUID
    var medicationID: UUID
    var medicationName: String
    var rawText: String
    var sourceTitle: String
    var sourceRaw: String
    var averageOCRConfidence: Double
    var importedAt: Date
    var lastRiskReviewAt: Date?

    init(
        id: UUID = UUID(),
        medicationID: UUID,
        medicationName: String,
        rawText: String,
        sourceTitle: String,
        source: DrugLabelSource = .userProvided,
        averageOCRConfidence: Double = 1,
        importedAt: Date = Date(),
        lastRiskReviewAt: Date? = nil
    ) {
        self.id = id
        self.medicationID = medicationID
        self.medicationName = medicationName
        self.rawText = rawText
        self.sourceTitle = sourceTitle
        self.sourceRaw = source.rawValue
        self.averageOCRConfidence = averageOCRConfidence
        self.importedAt = importedAt
        self.lastRiskReviewAt = lastRiskReviewAt
    }

    var coreLabel: MedicationLabel? {
        UserProvidedLabelBuilder().build(
            medicationName: medicationName,
            rawText: rawText,
            reviewedAt: importedAt
        )
    }

    var source: DrugLabelSource {
        DrugLabelSource(rawValue: sourceRaw) ?? .userProvided
    }
}

@Model
final class StoredMedicationStock {
    @Attribute(.unique) var id: UUID
    var medicationID: UUID
    var remainingQuantity: Double
    var unit: String
    var lowStockThreshold: Double
    var lastUpdated: Date

    init(
        id: UUID = UUID(),
        medicationID: UUID,
        remainingQuantity: Double,
        unit: String,
        lowStockThreshold: Double,
        lastUpdated: Date = Date()
    ) {
        self.id = id
        self.medicationID = medicationID
        self.remainingQuantity = remainingQuantity
        self.unit = unit
        self.lowStockThreshold = lowStockThreshold
        self.lastUpdated = lastUpdated
    }

    var coreStock: MedicationStock {
        MedicationStock(
            medicationID: medicationID,
            remainingQuantity: Decimal(remainingQuantity),
            unit: unit,
            lowStockThreshold: Decimal(lowStockThreshold),
            lastUpdated: lastUpdated
        )
    }
}

@Model
final class StoredDoseActionLog {
    @Attribute(.unique) var id: UUID
    var taskID: UUID
    var actionRaw: String
    var previousStatusRaw: String
    var previousDueAt: Date
    var previousRecordedAt: Date?
    var previousReason: String
    var newStatusRaw: String
    var occurredAt: Date
    var undoExpiresAt: Date
    var note: String
    var undoneAt: Date?

    init(
        id: UUID = UUID(),
        taskID: UUID,
        action: DoseActionKind,
        previousStatus: StoredDoseStatus,
        previousDueAt: Date,
        previousRecordedAt: Date?,
        previousReason: String,
        newStatus: StoredDoseStatus,
        occurredAt: Date = Date(),
        undoExpiresAt: Date,
        note: String = "",
        undoneAt: Date? = nil
    ) {
        self.id = id
        self.taskID = taskID
        self.actionRaw = action.rawValue
        self.previousStatusRaw = previousStatus.rawValue
        self.previousDueAt = previousDueAt
        self.previousRecordedAt = previousRecordedAt
        self.previousReason = previousReason
        self.newStatusRaw = newStatus.rawValue
        self.occurredAt = occurredAt
        self.undoExpiresAt = undoExpiresAt
        self.note = note
        self.undoneAt = undoneAt
    }

    var canUndo: Bool {
        undoneAt == nil && Date() <= undoExpiresAt
    }

    var previousStatus: StoredDoseStatus {
        StoredDoseStatus(rawValue: previousStatusRaw) ?? .pending
    }

    var actionDisplayName: String {
        switch DoseActionKind(rawValue: actionRaw) {
        case .markTaken:
            "标记已服用"
        case .delay:
            "稍后提醒"
        case .skip:
            "忽略"
        case .correct:
            "修正记录"
        case nil:
            "用药记录操作"
        }
    }
}

@Model
final class StoredAIConsent {
    @Attribute(.unique) var id: String
    var sharesMedicationProfile: Bool
    var sharesMedicationPlans: Bool
    var sharesDoseEvents: Bool
    var sharesRiskCards: Bool
    var sharesDrugLabels: Bool
    var sharesImportDraft: Bool
    var grantedAt: Date
    var revokedAt: Date?
    var note: String

    init(
        id: String = "medical-ai-consent",
        sharesMedicationProfile: Bool = true,
        sharesMedicationPlans: Bool = true,
        sharesDoseEvents: Bool = true,
        sharesRiskCards: Bool = true,
        sharesDrugLabels: Bool = true,
        sharesImportDraft: Bool = false,
        grantedAt: Date = Date(),
        revokedAt: Date? = nil,
        note: String = "用户授权医疗 AI 助手读取选定范围的数据。"
    ) {
        self.id = id
        self.sharesMedicationProfile = sharesMedicationProfile
        self.sharesMedicationPlans = sharesMedicationPlans
        self.sharesDoseEvents = sharesDoseEvents
        self.sharesRiskCards = sharesRiskCards
        self.sharesDrugLabels = sharesDrugLabels
        self.sharesImportDraft = sharesImportDraft
        self.grantedAt = grantedAt
        self.revokedAt = revokedAt
        self.note = note
    }

    var isActive: Bool {
        revokedAt == nil
    }

    var authorization: MedicalAIUserAuthorization {
        var scopes: Set<MedicalAIDataScope> = []
        if sharesMedicationProfile {
            scopes.insert(.medicationProfile)
        }
        if sharesMedicationPlans {
            scopes.insert(.medicationPlans)
        }
        if sharesDoseEvents {
            scopes.insert(.doseEvents)
        }
        if sharesRiskCards {
            scopes.insert(.riskCards)
        }
        if sharesDrugLabels {
            scopes.insert(.drugLabels)
        }
        if sharesImportDraft {
            scopes.insert(.importDraft)
        }
        return MedicalAIUserAuthorization(grantedScopes: scopes, grantedAt: grantedAt, note: note)
    }

    var scopeSummary: String {
        var names: [String] = []
        if sharesMedicationProfile {
            names.append("药品信息")
        }
        if sharesMedicationPlans {
            names.append("提醒计划")
        }
        if sharesDoseEvents {
            names.append("服药记录")
        }
        if sharesRiskCards {
            names.append("风险卡片")
        }
        if sharesDrugLabels {
            names.append("说明书摘要")
        }
        if sharesImportDraft {
            names.append("导入草稿")
        }
        return names.isEmpty ? "未共享任何数据" : names.joined(separator: "、")
    }
}

@Model
final class StoredAIChatMessage {
    @Attribute(.unique) var id: UUID
    var roleRaw: String
    var text: String
    var createdAt: Date
    var providerName: String
    var modelName: String
    var requestKindRaw: String
    var sharedScopesSummary: String

    init(
        id: UUID = UUID(),
        role: StoredAIChatRole,
        text: String,
        createdAt: Date = Date(),
        providerName: String = "",
        modelName: String = "",
        requestKind: MedicalAIRequestKind = .chat,
        sharedScopesSummary: String = ""
    ) {
        self.id = id
        self.roleRaw = role.rawValue
        self.text = text
        self.createdAt = createdAt
        self.providerName = providerName
        self.modelName = modelName
        self.requestKindRaw = requestKind.rawValue
        self.sharedScopesSummary = sharedScopesSummary
    }

    var role: StoredAIChatRole {
        StoredAIChatRole(rawValue: roleRaw) ?? .assistant
    }
}
