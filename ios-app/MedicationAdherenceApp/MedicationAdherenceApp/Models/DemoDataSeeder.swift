import Foundation
import MedicationAdherenceCore
import SwiftData

enum DemoDataSeeder {
    static func seedIfNeeded(in modelContext: ModelContext) {
        let existing = (try? modelContext.fetch(FetchDescriptor<StoredMedication>())) ?? []
        var medicationsByName = Dictionary(uniqueKeysWithValues: existing.map { ($0.displayName, $0) })
        migrateLegacyDemoMedications(existing, medicationsByName: &medicationsByName)

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
            if !medication.notes.contains("演示数据") {
                medication.notes = [medication.notes, "演示数据：用于比赛演示，正式上线前可移除。"]
                    .filter { !$0.isEmpty }
                    .joined(separator: "\n")
            }
        }

        seedMissingPlansAndTodayTasks(for: Array(medicationsByName.values), context: modelContext)
        seedMissingRiskCards(for: Array(medicationsByName.values), context: modelContext)
        seedMissingStocks(for: Array(medicationsByName.values), context: modelContext)
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
            notes: "演示数据：仅用于说明首版流程。",
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
            notes: "演示数据：饮酒相关风险提示。",
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
            notes: "演示数据：提醒时突出药品图像。",
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
            notes: "演示数据：用于展示季节过敏场景的长期提醒。",
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
            notes: "演示数据：用于展示长期健康管理提醒。",
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
                    sourceNote: "演示说明书建议，用户确认后提醒。",
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
            let recordedAt: Date?
            switch status {
            case .pending:
                recordedAt = nil
            case .taken:
                recordedAt = calendar.date(byAdding: .minute, value: dayOffset % 2 == 0 ? 4 : -3, to: dueAt)
            case .delayed:
                recordedAt = calendar.date(byAdding: .minute, value: 42, to: dueAt)
            case .skipped:
                recordedAt = calendar.date(byAdding: .hour, value: 2, to: dueAt)
            case .corrected:
                recordedAt = calendar.date(byAdding: .minute, value: 15, to: dueAt)
            }

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

    private static func demoReason(for status: StoredDoseStatus) -> String {
        switch status {
        case .pending:
            ""
        case .taken:
            "演示记录：按时完成。"
        case .delayed:
            "演示记录：当日延后服用。"
        case .skipped:
            "演示记录：当日未服用。"
        case .corrected:
            "演示记录：用户修正为已完成。"
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
