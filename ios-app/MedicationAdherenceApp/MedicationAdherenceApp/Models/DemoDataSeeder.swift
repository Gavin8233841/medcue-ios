import Foundation
import MedicationAdherenceCore
import SwiftData

#if DEBUG
import Darwin
#endif

#if DEBUG
@MainActor
enum DebugDemoModeLauncher {
    private static let firstLaunchCompletionKey = "hasCompletedFirstLaunchSetup"

    static func rebuildAndExit(in modelContext: ModelContext) async throws -> Never {
        UserDefaults.standard.set(false, forKey: firstLaunchCompletionKey)
        try DemoDataSeeder.rebuildForExplicitDebugDemoMode(in: modelContext)
        try await Task.sleep(for: .milliseconds(300))
        UserDefaults.standard.set(false, forKey: firstLaunchCompletionKey)
        exit(EXIT_SUCCESS)
    }
}
#endif

enum DemoDataSeeder {
    static func seedIfNeeded(in modelContext: ModelContext) {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        guard arguments.contains("--seed-demo-data")
                || arguments.contains("--reminder-live-activity-smoke-test") else {
            return
        }
        try? seed(in: modelContext)
        #endif
    }

    static func rebuildForExplicitDebugDemoMode(in modelContext: ModelContext) throws {
        #if DEBUG
        try removeExistingDemoContent(in: modelContext)
        try seed(in: modelContext)
        #endif
    }

    private static func seed(in modelContext: ModelContext) throws {
        let existing = try modelContext.fetch(FetchDescriptor<StoredMedication>())
        let demoMedications = resolveDemoMedications(from: existing, context: modelContext)
        migrateUserVisibleSeedText(for: demoMedications, in: modelContext)

        seedMissingPlansAndTodayTasks(for: demoMedications, context: modelContext)
        seedMissingMedicationLabels(for: demoMedications, context: modelContext)
        seedMissingRiskCards(for: demoMedications, context: modelContext)
        seedMissingStocks(for: demoMedications, context: modelContext)
        seedMissingDoseChanges(for: demoMedications, context: modelContext)
        try modelContext.save()
    }

    private static func removeExistingDemoContent(in modelContext: ModelContext) throws {
        let medications = try modelContext.fetch(FetchDescriptor<StoredMedication>())
        let demoMedications = medications.filter(\.isDemoContent)
        let demoMedicationIDs = Set(demoMedications.map(\.id))
        guard !demoMedicationIDs.isEmpty else {
            return
        }

        let tasks = try modelContext.fetch(FetchDescriptor<StoredDoseTask>())
        let demoTasks = tasks.filter { demoMedicationIDs.contains($0.medicationID) }
        let demoTaskIDs = Set(demoTasks.map(\.id))

        let actionLogs = try modelContext.fetch(FetchDescriptor<StoredDoseActionLog>())
        for actionLog in actionLogs where demoTaskIDs.contains(actionLog.taskID) {
            modelContext.delete(actionLog)
        }
        for task in demoTasks {
            modelContext.delete(task)
        }

        let lifecycleEvents = try modelContext.fetch(FetchDescriptor<StoredMedicationLifecycleEvent>())
        for lifecycleEvent in lifecycleEvents where demoMedicationIDs.contains(lifecycleEvent.medicationID) {
            modelContext.delete(lifecycleEvent)
        }

        let plans = try modelContext.fetch(FetchDescriptor<StoredMedicationPlan>())
        for plan in plans where demoMedicationIDs.contains(plan.medicationID) {
            modelContext.delete(plan)
        }

        let doseChanges = try modelContext.fetch(FetchDescriptor<StoredMedicationDoseChange>())
        for doseChange in doseChanges where demoMedicationIDs.contains(doseChange.medicationID) {
            modelContext.delete(doseChange)
        }

        let riskCards = try modelContext.fetch(FetchDescriptor<StoredRiskCard>())
        for riskCard in riskCards where demoMedicationIDs.contains(riskCard.medicationID) {
            modelContext.delete(riskCard)
        }

        let labels = try modelContext.fetch(FetchDescriptor<StoredMedicationLabel>())
        for label in labels where demoMedicationIDs.contains(label.medicationID) {
            modelContext.delete(label)
        }

        let stocks = try modelContext.fetch(FetchDescriptor<StoredMedicationStock>())
        for stock in stocks where demoMedicationIDs.contains(stock.medicationID) {
            modelContext.delete(stock)
        }

        for medication in demoMedications {
            modelContext.delete(medication)
        }
        try modelContext.save()
    }

    private static func demoUUID(_ rawValue: String) -> UUID {
        guard let id = UUID(uuidString: rawValue) else {
            preconditionFailure("A bundled demo-data identifier is invalid")
        }
        return id
    }

    private static let demoMedicationSeeds = [
        DemoMedicationSeed(
            id: demoUUID("44454D4F-4D45-4443-5545-000000000001"),
            displayName: "布洛芬",
            labelLookupName: "Ibuprofen",
            genericName: "ibuprofen",
            form: "片剂",
            strength: "200 mg",
            photoSymbolName: "pills.fill",
            notes: "按药盒或说明书核对后使用；如有胃部不适、过敏或合并用药疑问，请咨询医生或药师。",
            doseUnit: "片",
            reminderTimeRaw: "08:00",
            reminderHour: 8,
            reminderMinute: 0,
            initialStock: 90,
            lowStockThreshold: 12,
            boxNumber: "A1"
        ),
        DemoMedicationSeed(
            id: demoUUID("44454D4F-4D45-4443-5545-000000000002"),
            displayName: "对乙酰氨基酚",
            labelLookupName: "Acetaminophen",
            genericName: "acetaminophen",
            form: "片剂",
            strength: "500 mg",
            photoSymbolName: "cross.case.fill",
            notes: "按药盒或说明书核对后使用；饮酒、肝功能异常或合并用药时请咨询医生或药师。",
            doseUnit: "片",
            reminderTimeRaw: "13:00",
            reminderHour: 13,
            reminderMinute: 0,
            initialStock: 90,
            lowStockThreshold: 12,
            boxNumber: "A2"
        ),
        DemoMedicationSeed(
            id: demoUUID("44454D4F-4D45-4443-5545-000000000003"),
            displayName: "人工泪液",
            labelLookupName: "Artificial Tears",
            genericName: "",
            form: "滴眼液",
            strength: "1 滴",
            photoSymbolName: "eye.fill",
            notes: "提醒时可通过药品图片辅助识别；请按说明书或医生、药师建议核对使用间隔。",
            doseUnit: "滴",
            reminderTimeRaw: "21:00",
            reminderHour: 21,
            reminderMinute: 0,
            initialStock: 90,
            lowStockThreshold: 10,
            boxNumber: "B1"
        ),
        DemoMedicationSeed(
            id: demoUUID("44454D4F-4D45-4443-5545-000000000004"),
            displayName: "氯雷他定",
            labelLookupName: "Loratadine",
            genericName: "loratadine",
            form: "片剂",
            strength: "10 mg",
            photoSymbolName: "wind",
            notes: "用于长期提醒管理；如症状持续、加重或合并其他药物，请咨询医生或药师。",
            doseUnit: "片",
            reminderTimeRaw: "18:30",
            reminderHour: 18,
            reminderMinute: 30,
            initialStock: 90,
            lowStockThreshold: 10,
            boxNumber: "B2"
        ),
        DemoMedicationSeed(
            id: demoUUID("44454D4F-4D45-4443-5545-000000000005"),
            displayName: "维生素 D3",
            labelLookupName: "Vitamin D3",
            genericName: "cholecalciferol",
            form: "软胶囊",
            strength: "400 IU",
            photoSymbolName: "sun.max.fill",
            notes: "用于长期健康管理提醒；请按说明书、医嘱或药师建议核对剂量和疗程。",
            doseUnit: "粒",
            reminderTimeRaw: "22:00",
            reminderHour: 22,
            reminderMinute: 0,
            initialStock: 90,
            lowStockThreshold: 12,
            boxNumber: "C1"
        )
    ]

    private static func resolveDemoMedications(
        from existing: [StoredMedication],
        context: ModelContext
    ) -> [StoredMedication] {
        var resolved: [StoredMedication] = []
        var claimedMedicationIDs = Set<UUID>()

        for seed in demoMedicationSeeds {
            let stableDemo = existing.first { medication in
                medication.id == seed.id && medication.isDemoContent
            }
            let legacyDemo = existing
                .filter { medication in
                    medication.isDemoContent
                        && !claimedMedicationIDs.contains(medication.id)
                        && seedDefinition(forMedicationName: medication.displayName)?.id == seed.id
                }
                .min { $0.id.uuidString < $1.id.uuidString }

            let medication: StoredMedication
            if let stableDemo {
                medication = stableDemo
            } else if let legacyDemo {
                medication = legacyDemo
            } else {
                guard !existing.contains(where: { $0.id == seed.id }) else {
                    continue
                }
                let newMedication = StoredMedication(
                    id: seed.id,
                    displayName: seed.displayName,
                    genericName: seed.genericName,
                    kind: .overTheCounter,
                    form: seed.form,
                    strength: seed.strength,
                    inputSource: .demoData,
                    photoSymbolName: seed.photoSymbolName,
                    boxNumber: seed.boxNumber,
                    notes: seed.notes,
                    isDemoContent: true
                )
                context.insert(newMedication)
                medication = newMedication
            }

            refreshDemoMedication(medication, from: seed)
            claimedMedicationIDs.insert(medication.id)
            resolved.append(medication)
        }

        return resolved
    }

    private static func refreshDemoMedication(_ medication: StoredMedication, from seed: DemoMedicationSeed) {
        guard medication.isDemoContent else {
            return
        }
        if medication.displayName == seed.labelLookupName {
            medication.displayName = seed.displayName
        }
        medication.genericName = seed.genericName
        medication.form = seed.form
        medication.strength = seed.strength
        medication.photoSymbolName = seed.photoSymbolName
        if medication.boxNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            medication.boxNumber = seed.boxNumber
        }
        medication.notes = userFacingNotes(from: medication.notes, fallback: seed.notes)
    }

    private static func migrateUserVisibleSeedText(
        for medications: [StoredMedication],
        in context: ModelContext
    ) {
        let demoMedicationIDs = Set(medications.map(\.id))
        var seedByMedicationID: [UUID: DemoMedicationSeed] = [:]
        for medication in medications {
            guard let seed = seed(for: medication) else {
                continue
            }
            seedByMedicationID[medication.id] = seed
            medication.notes = userFacingNotes(from: medication.notes, fallback: seed.notes)
        }

        let plans = (try? context.fetch(FetchDescriptor<StoredMedicationPlan>())) ?? []
        for plan in plans where demoMedicationIDs.contains(plan.medicationID) && plan.sourceNote.contains("演示") {
            plan.sourceNote = "按说明书建议建立，用户确认后提醒；可在详情页继续修改疗程、提醒和库存。"
        }

        let tasks = (try? context.fetch(FetchDescriptor<StoredDoseTask>())) ?? []
        migrateStaleSeedPendingTasks(tasks, seedByMedicationID: seedByMedicationID)
        for task in tasks where demoMedicationIDs.contains(task.medicationID) && task.reason.contains("演示") {
            task.reason = userFacingReason(from: task.reason, status: task.status)
        }

        let riskCards = (try? context.fetch(FetchDescriptor<StoredRiskCard>())) ?? []
        for card in riskCards where demoMedicationIDs.contains(card.medicationID) {
            migrateUserVisibleRiskCardText(card)
        }
    }

    private static func migrateStaleSeedPendingTasks(
        _ tasks: [StoredDoseTask],
        seedByMedicationID: [UUID: DemoMedicationSeed]
    ) {
        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: Date())

        for task in tasks where task.status == .pending && task.dueAt < todayStart {
            guard let seed = seedByMedicationID[task.medicationID] else {
                continue
            }
            let dueDayStart = calendar.startOfDay(for: task.dueAt)
            guard let dayOffset = calendar.dateComponents([.day], from: dueDayStart, to: todayStart).day, dayOffset > 0 else {
                continue
            }
            let status = demoStatus(for: seed, dayOffset: dayOffset)
            task.status = status
            task.recordedAt = recordedAt(for: status, dueAt: task.dueAt, dayOffset: dayOffset, calendar: calendar)
            task.reason = demoReason(for: status)
        }
    }

    private static func seedMissingStocks(for medications: [StoredMedication], context: ModelContext) {
        let existingStocks = (try? context.fetch(FetchDescriptor<StoredMedicationStock>())) ?? []
        let stockedMedicationIDs = Set(existingStocks.map(\.medicationID))

        for medication in medications where !stockedMedicationIDs.contains(medication.id) {
            guard let stock = demoStock(for: medication) else {
                continue
            }
            context.insert(stock)
        }
    }

    private static func seedMissingMedicationLabels(for medications: [StoredMedication], context: ModelContext) {
        let existingLabels = (try? context.fetch(FetchDescriptor<StoredMedicationLabel>())) ?? []
        let labeledMedicationIDs = Set(existingLabels.map(\.medicationID))
        let demoMedicationIDs = Set(medications.filter(\.isDemoContent).map(\.id))
        let now = Date()

        for label in existingLabels where demoMedicationIDs.contains(label.medicationID) && label.sourceTitle == "本地保存说明书摘要" {
            label.sourceRaw = DrugLabelSource.demo.rawValue
        }

        for medication in medications where !labeledMedicationIDs.contains(medication.id) {
            guard let seed = seed(for: medication),
                  let rawText = savedLabelText(for: seed)
            else {
                continue
            }
            context.insert(StoredMedicationLabel(
                medicationID: medication.id,
                medicationName: medication.displayName,
                rawText: rawText,
                sourceTitle: "本地保存说明书摘要",
                source: .demo,
                averageOCRConfidence: 1,
                importedAt: now,
                lastRiskReviewAt: now
            ))
        }

        archiveDemoSourceReviewCards(for: demoMedicationIDs, context: context)
    }

    private static func archiveDemoSourceReviewCards(for demoMedicationIDs: Set<UUID>, context: ModelContext) {
        guard !demoMedicationIDs.isEmpty else {
            return
        }
        let now = Date()
        let riskCards = (try? context.fetch(FetchDescriptor<StoredRiskCard>())) ?? []
        for card in riskCards where demoMedicationIDs.contains(card.medicationID) && isDemoSourceReviewCard(card) && card.isActive {
            card.resolvedAt = now
            card.archivedAt = now
            card.reviewedAt = card.reviewedAt ?? now
            card.resolutionNote = "内置说明书样本已确认来源，来源核对提醒已自动解除。"
            card.reviewNote = "内置说明书样本已确认来源，来源核对提醒已自动归档隐藏。"
        }
    }

    private static func isDemoSourceReviewCard(_ card: StoredRiskCard) -> Bool {
        guard card.kindRaw == RiskAssessmentCardKind.medicationSourceReview.rawValue else {
            return false
        }
        return card.id.contains("source-user-provided-label") || card.title == "说明书来源待核对"
    }

    private static func demoStock(for medication: StoredMedication) -> StoredMedicationStock? {
        guard let seed = seed(for: medication) else {
            return nil
        }
        return StoredMedicationStock(
            medicationID: medication.id,
            remainingQuantity: seed.initialStock,
            unit: seed.doseUnit,
            lowStockThreshold: seed.lowStockThreshold
        )
    }

    private static func seedMissingPlansAndTodayTasks(for medications: [StoredMedication], context: ModelContext) {
        let today = Date()
        let calendar = Calendar.current
        let existingPlans = (try? context.fetch(FetchDescriptor<StoredMedicationPlan>())) ?? []
        let existingTasks = (try? context.fetch(FetchDescriptor<StoredDoseTask>())) ?? []

        for medication in medications {
            guard let seed = seed(for: medication) else {
                continue
            }

            let plan: StoredMedicationPlan
            if let existingPlan = existingPlans.first(where: { $0.medicationID == medication.id }) {
                existingPlan.courseStartAt = existingPlan.courseStartAt ?? today
                existingPlan.courseEndAt = nil
                existingPlan.doseUnit = seed.doseUnit
                existingPlan.reminderTimesRaw = seed.reminderTimeRaw
                existingPlan.timingSummary = "每日 \(seed.reminderTimeRaw)"
                plan = existingPlan
            } else {
                let newPlan = StoredMedicationPlan(
                    medicationID: medication.id,
                    doseValue: 1,
                    doseUnit: seed.doseUnit,
                    timingSummary: "每日 \(seed.reminderTimeRaw)",
                    timeZonePolicy: .localClock,
                    sourceNote: "按说明书建议建立，用户确认后提醒；可在详情页继续修改疗程、提醒和库存。",
                    courseStartAt: today,
                    courseEndAt: nil,
                    reminderTimesRaw: seed.reminderTimeRaw,
                    reminderDelivery: .notification
                )
                context.insert(newPlan)
                plan = newPlan
            }

            seedMissingDemoHistory(
                for: medication,
                plan: plan,
                seed: seed,
                today: today,
                existingTasks: existingTasks,
                calendar: calendar,
                context: context
            )

            let hasTaskTodayForMedication = existingTasks.contains { task in
                task.medicationID == medication.id
                    && calendar.isDateInToday(task.dueAt)
            }
            guard !hasTaskTodayForMedication else {
                continue
            }
            context.insert(StoredDoseTask(
                medicationID: medication.id,
                planID: plan.id,
                dueAt: date(on: today, hour: seed.reminderHour, minute: seed.reminderMinute, calendar: calendar),
                doseValue: 1,
                doseUnit: seed.doseUnit
            ))
        }
    }

    private static func seedMissingDemoHistory(
        for medication: StoredMedication,
        plan: StoredMedicationPlan,
        seed: DemoMedicationSeed,
        today: Date,
        existingTasks: [StoredDoseTask],
        calendar: Calendar,
        context: ModelContext
    ) {
        for dayOffset in 1...60 {
            guard let day = calendar.date(byAdding: .day, value: -dayOffset, to: today) else {
                continue
            }
            let alreadyHasTask = existingTasks.contains { task in
                task.planID == plan.id && calendar.isDate(task.dueAt, inSameDayAs: day)
            }
            guard !alreadyHasTask else {
                continue
            }

            let status = demoStatus(for: seed, dayOffset: dayOffset)
            let dueAt = date(on: day, hour: seed.reminderHour, minute: seed.reminderMinute, calendar: calendar)
            let recordedAt = recordedAt(for: status, dueAt: dueAt, dayOffset: dayOffset, calendar: calendar)

            context.insert(StoredDoseTask(
                medicationID: medication.id,
                planID: plan.id,
                dueAt: dueAt,
                doseValue: 1,
                doseUnit: seed.doseUnit,
                status: status,
                recordedAt: recordedAt,
                reason: demoReason(for: status)
            ))
        }
    }

    private static func seedMissingDoseChanges(for medications: [StoredMedication], context: ModelContext) {
        let calendar = Calendar.current
        guard let medication = medications.first(where: { seed(for: $0)?.labelLookupName == "Vitamin D3" }),
              let seed = seed(for: medication)
        else {
            return
        }

        let plans = (try? context.fetch(FetchDescriptor<StoredMedicationPlan>())) ?? []
        guard let plan = plans.first(where: { $0.medicationID == medication.id }) else {
            return
        }

        let existingChanges = (try? context.fetch(FetchDescriptor<StoredMedicationDoseChange>())) ?? []
        let alreadySeeded = existingChanges.contains { change in
            change.medicationID == medication.id
                && change.planID == plan.id
                && change.previousDoseValue == 1
                && change.newDoseValue == 2
                && change.newDoseUnit == seed.doseUnit
        }
        let effectiveFrom = calendar.startOfDay(
            for: calendar.date(byAdding: .day, value: -14, to: Date()) ?? Date()
        )

        guard !alreadySeeded else {
            return
        }

        context.insert(StoredMedicationDoseChange(
            medicationID: medication.id,
            planID: plan.id,
            previousDoseValue: 1,
            previousDoseUnit: seed.doseUnit,
            newDoseValue: 2,
            newDoseUnit: seed.doseUnit,
            effectiveFrom: effectiveFrom,
            note: "复诊沟通后记录为新的每日剂量；请按医嘱、说明书或药师建议核对。"
        ))

        plan.doseValue = 2
        plan.doseUnit = seed.doseUnit

        let tasks = (try? context.fetch(FetchDescriptor<StoredDoseTask>())) ?? []
        for task in tasks where task.planID == plan.id {
            if task.dueAt >= effectiveFrom {
                task.doseValue = 2
                task.doseUnit = seed.doseUnit
            } else {
                task.doseValue = 1
                task.doseUnit = seed.doseUnit
            }
        }
    }

    private static func demoStatus(for seed: DemoMedicationSeed, dayOffset: Int) -> StoredDoseStatus {
        if seed.labelLookupName == "Ibuprofen", dayOffset % 11 == 0 {
            return .skipped
        }
        if seed.labelLookupName == "Acetaminophen", dayOffset % 13 == 0 {
            return .delayed
        }
        if seed.labelLookupName == "Artificial Tears", dayOffset % 17 == 0 {
            return .skipped
        }
        if dayOffset % 29 == 0 {
            return .corrected
        }
        return .taken
    }

    private static func recordedAt(
        for status: StoredDoseStatus,
        dueAt: Date,
        dayOffset: Int,
        calendar: Calendar
    ) -> Date? {
        switch status {
        case .pending:
            nil
        case .taken:
            calendar.date(byAdding: .minute, value: dayOffset % 2 == 0 ? 4 : -3, to: dueAt)
        case .delayed:
            calendar.date(byAdding: .minute, value: 42, to: dueAt)
        case .skipped:
            calendar.date(byAdding: .hour, value: 2, to: dueAt)
        case .corrected:
            calendar.date(byAdding: .minute, value: 15, to: dueAt)
        }
    }

    private static func demoReason(for status: StoredDoseStatus) -> String {
        switch status {
        case .pending:
            ""
        case .taken:
            "按时完成。"
        case .delayed:
            "当日延后处理。"
        case .skipped:
            "当日已忽略。"
        case .corrected:
            "用户修正为已完成。"
        }
    }

    private static func seedMissingRiskCards(for medications: [StoredMedication], context: ModelContext) {
        let existingRiskCards = (try? context.fetch(FetchDescriptor<StoredRiskCard>())) ?? []
        var existingRiskCardsByID: [String: StoredRiskCard] = [:]
        for riskCard in existingRiskCards where existingRiskCardsByID[riskCard.id] == nil {
            existingRiskCardsByID[riskCard.id] = riskCard
        }
        for medication in medications {
            guard seed(for: medication) != nil else {
                continue
            }
            seedRiskCards(for: medication, existingRiskCardsByID: existingRiskCardsByID, context: context)
        }
    }

    private static func seedRiskCards(for medication: StoredMedication, existingRiskCardsByID: [String: StoredRiskCard], context: ModelContext) {
        let seed = seed(for: medication)
        let storedLabel = ((try? context.fetch(FetchDescriptor<StoredMedicationLabel>())) ?? [])
            .first { $0.medicationID == medication.id }
        let label = storedLabel?.coreLabel
        let input = RiskAssessmentInput(
            medication: medication.coreMedication,
            label: label,
            drugClasses: seed?.labelLookupName == "Ibuprofen"
                ? [DrugClass(classID: "N0000175722", name: "Analgesics", source: "MEDRT")]
                : []
        )
        RiskAssessmentEngine().assess(input).forEach { card in
            let storedID = "\(medication.id.uuidString)-\(card.id)"
            if let existingCard = existingRiskCardsByID[storedID] {
                updateDemoRiskCard(existingCard, from: card, medicationID: medication.id)
                return
            }
            context.insert(StoredRiskCard(
                id: storedID,
                medicationID: medication.id,
                kindRaw: card.kind.rawValue,
                displayPriority: card.displayPriority,
                title: card.title,
                message: card.message,
                sourceTitle: card.evidence?.sourceTitle ?? "",
                sourceExcerpt: card.evidence?.excerpt ?? "",
                requiresProfessionalReview: card.requiresProfessionalReview,
                safetyNote: card.safetyNote
            ))
        }
    }

    private static func updateDemoRiskCard(_ storedCard: StoredRiskCard, from card: RiskAssessmentCard, medicationID: UUID) {
        storedCard.kindRaw = card.kind.rawValue
        storedCard.displayPriority = card.displayPriority
        storedCard.title = card.title
        storedCard.message = card.message
        storedCard.sourceTitle = card.evidence?.sourceTitle ?? ""
        storedCard.sourceExcerpt = card.evidence?.excerpt ?? ""
        storedCard.requiresProfessionalReview = card.requiresProfessionalReview
        storedCard.safetyNote = card.safetyNote
        storedCard.detectionSignature = StoredRiskCard.makeDetectionSignature(
            medicationID: medicationID,
            kindRaw: card.kind.rawValue,
            title: card.title,
            message: card.message,
            sourceExcerpt: card.evidence?.excerpt ?? ""
        )
        storedCard.severityRaw = StoredRiskCard.inferredSeverityRaw(
            kindRaw: card.kind.rawValue,
            displayPriority: card.displayPriority,
            title: card.title,
            message: card.message,
            sourceExcerpt: card.evidence?.excerpt ?? "",
            requiresProfessionalReview: card.requiresProfessionalReview
        )
        storedCard.sourceKindRaw = StoredRiskCard.inferredSourceKindRaw(
            kindRaw: card.kind.rawValue,
            sourceTitle: card.evidence?.sourceTitle ?? "",
            sourceExcerpt: card.evidence?.excerpt ?? ""
        )
    }

    private static func date(on baseDate: Date, hour: Int, minute: Int, calendar: Calendar) -> Date {
        var components = calendar.dateComponents([.year, .month, .day], from: baseDate)
        components.hour = hour
        components.minute = minute
        return calendar.date(from: components) ?? baseDate
    }

    private static func seedDefinition(forMedicationName name: String) -> DemoMedicationSeed? {
        demoMedicationSeeds.first { seed in
            seed.displayName == name || seed.labelLookupName == name
        }
    }

    private static func seed(for medication: StoredMedication) -> DemoMedicationSeed? {
        guard medication.isDemoContent else {
            return nil
        }
        return demoMedicationSeeds.first(where: { $0.id == medication.id })
            ?? seedDefinition(forMedicationName: medication.displayName)
    }

    private static func savedLabelText(for seed: DemoMedicationSeed) -> String? {
        switch seed.labelLookupName {
        case "Ibuprofen":
            return """
            禁忌或不得使用
            曾对布洛芬、阿司匹林或其他止痛退热药发生过敏反应者不应使用；冠状动脉搭桥手术前后不应使用。
            警示
            布洛芬属于 NSAID，可能导致严重胃出血。60 岁及以上、既往胃溃疡或出血、每日饮酒 3 杯以上、超过说明书用量或时间时风险更高。
            药物相互作用
            正在使用阿司匹林预防心梗或卒中、抗凝药、激素类药物，或其他含 NSAID 药物时，使用前应咨询医生或药师。
            不良反应
            若出现胃痛、呕血、黑便、持续胃部不适、胸痛、呼吸困难、皮疹或面部肿胀等，应停止使用并尽快寻求医疗帮助。
            用法用量
            请按药盒或说明书方向使用；如医生另有医嘱，应以医嘱为准。App 只记录提醒，不自动改变剂量。
            """
        case "Acetaminophen":
            return """
            警示
            对乙酰氨基酚可能导致严重肝损伤，尤其是 24 小时内超过 4000 mg、同时使用其他含对乙酰氨基酚药物，或每日饮酒 3 杯以上时。
            禁忌或不得使用
            正在使用其他含对乙酰氨基酚的处方或非处方药时，使用前必须核对成分，避免重复用药。
            不良反应
            可能出现严重皮肤反应，如皮肤发红、水疱、皮疹；若出现应停止使用并尽快寻求医疗帮助。
            用法用量
            请按药盒、说明书或医嘱确认剂量和间隔；App 只提供提醒和记录。
            """
        case "Artificial Tears":
            return """
            适应症
            用于暂时缓解眼睛干涩、灼热或刺激感。
            警示
            仅供外用。为避免污染，不要让瓶口接触任何表面；溶液变色或浑浊时不要使用。
            不良反应
            若出现眼痛、视力变化、持续红肿或刺激，或症状加重、持续超过 72 小时，应停止使用并咨询医生。
            用法用量
            可按需向受影响眼睛滴入 1 到 2 滴；具体频次以说明书、医生或药师建议为准。
            """
        case "Loratadine":
            return """
            适应症
            用于暂时缓解花粉症或其他上呼吸道过敏相关的流涕、眼痒流泪、打喷嚏、鼻或咽喉发痒。
            禁忌或不得使用
            曾对氯雷他定或本品任何成分发生过敏反应者不应使用。
            注意事项
            有肝病或肾病者使用前应咨询医生，由医生判断是否需要不同剂量；妊娠期或哺乳期使用前应咨询专业人员。
            不良反应
            不要超过说明书用量；超过用量可能导致嗜睡。若发生过敏反应，应停止使用并尽快寻求医疗帮助。
            用法用量
            按说明书或医生、药师建议使用；App 只记录提醒，不自动改变剂量。
            """
        case "Vitamin D3":
            return """
            注意事项
            维生素 D 过量可能导致血钙升高。已有高钙血症、高磷血症、肾功能不全或正在接受相关治疗者，使用前应咨询医生或药师。
            药物相互作用
            与高剂量含钙制剂、其他维生素 D 制剂、噻嗪类利尿药或洋地黄类药物合用时，需咨询医生或药师并关注血钙风险。
            不良反应
            若出现明显乏力、食欲下降、恶心、便秘、口渴或尿量增多等疑似高钙相关表现，应记录并咨询医生或药师。
            儿童用药
            儿童应在成人监护下使用，并按说明书或医生、药师建议核对剂量。
            老年用药
            老年人长期使用前请咨询医生或药师。
            """
        default:
            return nil
        }
    }

    private static func userFacingNotes(from notes: String, fallback: String) -> String {
        let visibleText = notes
            .split(whereSeparator: \.isNewline)
            .map(String.init)
            .filter { !$0.contains("演示") }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return visibleText.isEmpty ? fallback : visibleText
    }

    private static func userFacingReason(from reason: String, status: StoredDoseStatus) -> String {
        let cleaned = reason
            .replacingOccurrences(of: "演示记录：", with: "")
            .replacingOccurrences(of: "演示数据：", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !cleaned.contains("演示"), !cleaned.isEmpty {
            return cleaned
        }
        return demoReason(for: status)
    }

    private static func migrateUserVisibleRiskCardText(_ card: StoredRiskCard) {
        let defaultSafetyNote = "以上内容仅用于风险提示和复诊沟通，不能替代医生或药师判断。"
        let genericSourceExcerpt = "说明书提示禁忌、慎用或相互作用信息，需要结合个人情况由医生或药师复核。"

        card.title = sanitizedRequiredRiskText(
            card.title,
            fallback: card.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "用药风险提醒" : card.title
        )
        card.message = sanitizedRequiredRiskText(
            card.message,
            fallback: "已根据药品资料生成用药风险提醒，请结合说明书并咨询医生或药师。"
        )
        card.sourceTitle = sanitizedOptionalRiskText(
            card.sourceTitle,
            fallback: ""
        )
        card.sourceExcerpt = sanitizedOptionalRiskText(
            card.sourceExcerpt,
            fallback: genericSourceExcerpt
        )
        if card.sourceTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && card.sourceExcerpt == genericSourceExcerpt {
            card.sourceExcerpt = ""
        }
        migrateConcreteLabelRiskMessageIfNeeded(card)
        card.safetyNote = sanitizedRequiredRiskText(card.safetyNote, fallback: defaultSafetyNote)
        card.reviewNote = sanitizedOptionalRiskText(card.reviewNote, fallback: "用户已复核并归档。")
        card.resolutionNote = sanitizedOptionalRiskText(card.resolutionNote, fallback: "相关风险已更新，请以当前说明书和医生或药师意见为准。")
        card.detectionSignature = StoredRiskCard.makeDetectionSignature(
            medicationID: card.medicationID,
            kindRaw: card.kindRaw,
            title: card.title,
            message: card.message,
            sourceExcerpt: card.sourceExcerpt
        )
        card.severityRaw = StoredRiskCard.inferredSeverityRaw(
            kindRaw: card.kindRaw,
            displayPriority: card.displayPriority,
            title: card.title,
            message: card.message,
            sourceExcerpt: card.sourceExcerpt,
            requiresProfessionalReview: card.requiresProfessionalReview
        )
        card.sourceKindRaw = StoredRiskCard.inferredSourceKindRaw(
            kindRaw: card.kindRaw,
            sourceTitle: card.sourceTitle,
            sourceExcerpt: card.sourceExcerpt
        )
    }

    private static func migrateConcreteLabelRiskMessageIfNeeded(_ card: StoredRiskCard) {
        guard RiskAssessmentCardKind(rawValue: card.kindRaw) == .labelRisk,
              !card.sourceExcerpt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            return
        }

        let currentText = "\(card.title) \(card.message)".folding(
            options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
            locale: .current
        )
        let shouldRefresh = currentText.contains("相关风险")
            || currentText.contains("相关警示")
            || currentText.contains("相关提醒")
            || currentText.contains("说明书提示需要复核")
            || currentText.contains("已根据药品资料和用户记录生成用药风险提醒")
            || currentText.contains("已根据药品资料生成用药风险提醒")
        guard shouldRefresh else {
            return
        }

        let sourceTitle = card.sourceTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "相关章节"
            : card.sourceTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let excerpt = normalizedRiskExcerpt(card.sourceExcerpt)
        let sourceText = "说明书“\(sourceTitle)”指出：\(excerpt)"
        let lowerText = "\(card.title) \(sourceTitle) \(card.sourceExcerpt)"
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
            .lowercased()

        if lowerText.contains("禁忌")
            || lowerText.contains("禁用")
            || lowerText.contains("不得使用")
            || lowerText.contains("contraindication")
            || lowerText.contains("do not use") {
            card.message = "\(sourceText) 请核对你是否属于上述人群、成分过敏或用药条件，并向医生或药师确认。"
        } else if lowerText.contains("相互作用")
            || lowerText.contains("合用")
            || lowerText.contains("同用")
            || lowerText.contains("interaction")
            || lowerText.contains("ask a doctor or pharmacist") {
            card.message = "\(sourceText) 请带着当前正在使用的药品、保健品和外用药清单咨询医生或药师。"
        } else if lowerText.contains("饮酒")
            || lowerText.contains("酒精")
            || lowerText.contains("葡萄柚")
            || lowerText.contains("食物")
            || lowerText.contains("饮食")
            || lowerText.contains("alcohol")
            || lowerText.contains("grapefruit")
            || lowerText.contains("food") {
            card.message = "\(sourceText) 请核对近期饮食、饮酒或生活方式记录，并向医生或药师确认是否需要调整安排。"
        } else if lowerText.contains("不良反应")
            || lowerText.contains("副作用")
            || lowerText.contains("adverse")
            || lowerText.contains("side effect") {
            card.message = "\(sourceText) 若出现相似不适，请记录时间、症状和正在使用的药品，并咨询医生或药师。"
        } else {
            card.message = "\(sourceText) 请按原文核对适用条件，并在不确定时咨询医生或药师。"
        }
    }

    private static func normalizedRiskExcerpt(_ excerpt: String) -> String {
        let normalized = excerpt
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            return "该章节含有需要复核的用药提醒。"
        }
        let finalPunctuation: Set<Character> = ["。", "！", "？", ".", "!", "?"]
        return finalPunctuation.contains(normalized.last ?? "。") ? normalized : "\(normalized)。"
    }

    private static func sanitizedRequiredRiskText(_ text: String, fallback: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return fallback
        }
        if containsSeedTrace(trimmed) {
            return fallback
        }
        return trimmed
    }

    private static func sanitizedOptionalRiskText(_ text: String, fallback: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return ""
        }
        if containsSeedTrace(trimmed) {
            return fallback
        }
        return trimmed
    }

    private static func containsSeedTrace(_ text: String) -> Bool {
        [
            "验证用",
            "验证提醒",
            "此验证提醒",
            "确认风险生命周期链路",
            "风险生命周期",
            "生命周期验证",
            "验证说明书",
            "演示",
            "开发",
            "调试"
        ].contains { text.contains($0) }
    }
}

private struct DemoMedicationSeed {
    let id: UUID
    let displayName: String
    let labelLookupName: String
    let genericName: String
    let form: String
    let strength: String
    let photoSymbolName: String
    let notes: String
    let doseUnit: String
    let reminderTimeRaw: String
    let reminderHour: Int
    let reminderMinute: Int
    let initialStock: Double
    let lowStockThreshold: Double
    let boxNumber: String
}
