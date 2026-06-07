import Foundation
import MedicationAdherenceCore
import SwiftData

enum DemoDataSeeder {
    static func seedIfNeeded(in modelContext: ModelContext) {
        let existing = (try? modelContext.fetch(FetchDescriptor<StoredMedication>())) ?? []
        var medicationsByName = Dictionary(uniqueKeysWithValues: existing.map { ($0.displayName, $0) })
        migrateLegacyDemoMedications(existing, medicationsByName: &medicationsByName)
        migrateUserVisibleSeedText(in: modelContext)

        for seed in demoMedicationSeeds where medicationsByName[seed.displayName] == nil {
            let medication = StoredMedication(
                displayName: seed.displayName,
                genericName: seed.genericName,
                kind: .overTheCounter,
                form: seed.form,
                strength: seed.strength,
                inputSource: .demoData,
                photoSymbolName: seed.photoSymbolName,
                notes: seed.notes,
                isDemoContent: true
            )
            modelContext.insert(medication)
            medicationsByName[seed.displayName] = medication
        }

        for medication in medicationsByName.values where demoMedicationSeeds.contains(where: { $0.displayName == medication.displayName }) {
            medication.isDemoContent = true
            medication.notes = userFacingNotes(from: medication.notes, fallback: seed(forMedicationName: medication.displayName)?.notes ?? "")
        }

        seedMissingPlansAndTodayTasks(for: Array(medicationsByName.values), context: modelContext)
        seedMissingRiskCards(for: Array(medicationsByName.values), context: modelContext)
        seedMissingStocks(for: Array(medicationsByName.values), context: modelContext)
        seedMissingDoseChanges(for: Array(medicationsByName.values), context: modelContext)
        try? modelContext.save()
    }

    private static let demoMedicationSeeds = [
        DemoMedicationSeed(
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
            lowStockThreshold: 12
        ),
        DemoMedicationSeed(
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
            lowStockThreshold: 12
        ),
        DemoMedicationSeed(
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
            lowStockThreshold: 10
        ),
        DemoMedicationSeed(
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
            lowStockThreshold: 10
        ),
        DemoMedicationSeed(
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
            lowStockThreshold: 12
        )
    ]

    private static func migrateLegacyDemoMedications(
        _ medications: [StoredMedication],
        medicationsByName: inout [String: StoredMedication]
    ) {
        for medication in medications {
            guard let seed = seed(forMedicationName: medication.displayName) else {
                continue
            }
            if medication.displayName != seed.displayName {
                medicationsByName[medication.displayName] = nil
                medication.displayName = seed.displayName
                medicationsByName[seed.displayName] = medication
            }
            medication.genericName = seed.genericName
            medication.form = seed.form
            medication.strength = seed.strength
            medication.photoSymbolName = seed.photoSymbolName
            medication.isDemoContent = true
        }
    }

    private static func migrateUserVisibleSeedText(in context: ModelContext) {
        let medications = (try? context.fetch(FetchDescriptor<StoredMedication>())) ?? []
        let seedByMedicationID = Dictionary(uniqueKeysWithValues: medications.compactMap { medication in
            seed(forMedicationName: medication.displayName).map { (medication.id, $0) }
        })

        for medication in medications {
            if let seed = seed(forMedicationName: medication.displayName) {
                medication.notes = userFacingNotes(from: medication.notes, fallback: seed.notes)
            }
        }

        let plans = (try? context.fetch(FetchDescriptor<StoredMedicationPlan>())) ?? []
        for plan in plans where plan.sourceNote.contains("演示") {
            plan.sourceNote = "按说明书建议建立，用户确认后提醒；可在详情页继续修改疗程、提醒和库存。"
        }

        let tasks = (try? context.fetch(FetchDescriptor<StoredDoseTask>())) ?? []
        migrateStaleSeedPendingTasks(tasks, seedByMedicationID: seedByMedicationID)
        for task in tasks where task.reason.contains("演示") {
            task.reason = userFacingReason(from: task.reason, status: task.status)
        }

        let riskCards = (try? context.fetch(FetchDescriptor<StoredRiskCard>())) ?? []
        for card in riskCards where card.reviewNote.contains("演示") {
            card.reviewNote = "用户已导入说明书，旧说明书风险已自动归档隐藏。"
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
            let stock = demoStock(for: medication)
            context.insert(stock)
        }

        try? context.save()
    }

    private static func demoStock(for medication: StoredMedication) -> StoredMedicationStock {
        let seed = seed(forMedicationName: medication.displayName)
        return StoredMedicationStock(
            medicationID: medication.id,
            remainingQuantity: seed?.initialStock ?? 0,
            unit: seed?.doseUnit ?? "个",
            lowStockThreshold: seed?.lowStockThreshold ?? 0
        )
    }

    private static func seedMissingPlansAndTodayTasks(for medications: [StoredMedication], context: ModelContext) {
        let today = Date()
        let calendar = Calendar.current
        let existingPlans = (try? context.fetch(FetchDescriptor<StoredMedicationPlan>())) ?? []
        let existingTasks = (try? context.fetch(FetchDescriptor<StoredDoseTask>())) ?? []

        for medication in medications {
            guard let seed = seed(forMedicationName: medication.displayName) else {
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
        guard let medication = medications.first(where: { $0.displayName == "维生素 D3" }),
              let seed = seed(forMedicationName: medication.displayName)
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
        let existingRiskIDs = Set(((try? context.fetch(FetchDescriptor<StoredRiskCard>())) ?? []).map(\.id))
        for medication in medications {
            guard seed(forMedicationName: medication.displayName) != nil else {
                continue
            }
            seedRiskCards(for: medication, existingRiskIDs: existingRiskIDs, context: context)
        }
    }

    private static func seedRiskCards(for medication: StoredMedication, existingRiskIDs: Set<String>, context: ModelContext) {
        let seed = seed(forMedicationName: medication.displayName)
        let label = seed.flatMap { seed in DemoDrugLabels.all.first { $0.name == seed.labelLookupName } }
        let input = RiskAssessmentInput(
            medication: medication.coreMedication,
            label: label,
            drugClasses: seed?.labelLookupName == "Ibuprofen"
                ? [DrugClass(classID: "N0000175722", name: "Analgesics", source: "MEDRT")]
                : [],
            healthConditionEntries: seed?.labelLookupName == "Ibuprofen"
                ? [UserRiskContextEntry(name: "stroke")]
                : [],
            dietaryConcernEntries: [
                UserRiskContextEntry(name: "alcohol")
            ]
        )
        RiskAssessmentEngine().assess(input).forEach { card in
            let storedID = "\(medication.id.uuidString)-\(card.id)"
            guard !existingRiskIDs.contains(storedID) else {
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

    private static func date(on baseDate: Date, hour: Int, minute: Int, calendar: Calendar) -> Date {
        var components = calendar.dateComponents([.year, .month, .day], from: baseDate)
        components.hour = hour
        components.minute = minute
        return calendar.date(from: components) ?? baseDate
    }

    private static func seed(forMedicationName name: String) -> DemoMedicationSeed? {
        demoMedicationSeeds.first { seed in
            seed.displayName == name || seed.labelLookupName == name
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
}

private struct DemoMedicationSeed {
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
}
