import Foundation
import MedicationAdherenceCore
import SwiftData

struct MedicationCreationInput {
    let displayName: String
    let genericName: String
    let kind: MedicationKind
    let form: String
    let strength: String
    let inputSource: MedicationInputSource
    let photoSymbolName: String
    let photoData: Data?
    let boxNumber: String
    let notes: String
    let doseValue: Double
    let doseUnit: String
    let courseStartAt: Date
    let courseEndAt: Date?
    let reminderTimes: [Date]
    let reminderDeliveryMethod: StoredReminderDeliveryMethod
    let escalatesToAlarmWhenUnhandled: Bool
    let initialStockQuantity: Double
    let lowStockThreshold: Double
    let stockUnit: String
    let createdAt: Date
}

enum MedicationCreationRejection: Equatable {
    case invalidMedicationName
}

enum MedicationCreationCommandOutcome {
    case committed(
        medicationID: UUID,
        planID: UUID,
        reminderBatch: MedicationReminderScheduleBatch
    )
    case rejected(MedicationCreationRejection)
    case saveFailed
}

@MainActor
struct MedicationCreationCommand {
    typealias SaveOperation = (ModelContext) throws -> Void

    private let modelContext: ModelContext
    private let calendar: Calendar
    private let saveOperation: SaveOperation

    init(
        modelContext: ModelContext,
        calendar: Calendar = .current,
        saveOperation: @escaping SaveOperation = { try $0.save() }
    ) {
        self.modelContext = modelContext
        self.calendar = calendar
        self.saveOperation = saveOperation
    }

    func create(_ input: MedicationCreationInput) -> MedicationCreationCommandOutcome {
        guard let displayName = MedicationNamePolicy.normalizedDisplayName(input.displayName) else {
            return .rejected(.invalidMedicationName)
        }
        let reminderTimes = normalizedReminderTimes(input.reminderTimes)
        let medication = StoredMedication(
            displayName: displayName,
            genericName: input.genericName.trimmingCharacters(in: .whitespacesAndNewlines),
            kind: input.kind,
            form: input.form,
            strength: input.strength,
            inputSource: input.inputSource,
            photoSymbolName: input.photoSymbolName,
            photoData: input.photoData,
            boxNumber: input.boxNumber.trimmingCharacters(in: .whitespacesAndNewlines),
            notes: input.notes,
            createdAt: input.createdAt
        )
        modelContext.insert(medication)

        let plan = StoredMedicationPlan(
            medicationID: medication.id,
            doseValue: input.doseValue,
            doseUnit: input.doseUnit,
            timingSummary: reminderTimes.isEmpty
                ? "未设置提醒时间"
                : "每日 " + reminderTimes.map(\.text).joined(separator: "、"),
            timeZonePolicy: .localClock,
            sourceNote: "",
            requiresUserConfirmation: true,
            courseStartAt: input.courseStartAt,
            courseEndAt: input.courseEndAt,
            reminderTimesRaw: reminderTimes.map(\.text).joined(separator: ","),
            reminderDelivery: input.reminderDeliveryMethod,
            escalatesToAlarmWhenUnhandled: input.escalatesToAlarmWhenUnhandled,
            createdAt: input.createdAt
        )
        modelContext.insert(plan)
        let reminderBatch = MedicationReminderTaskCoordinator(
            calendar: calendar,
            referenceDate: input.createdAt
        ).reconcilePlan(
            plan,
            medication: medication,
            in: modelContext
        )

        if input.initialStockQuantity > 0 || input.lowStockThreshold > 0 {
            let trimmedStockUnit = input.stockUnit.trimmingCharacters(in: .whitespacesAndNewlines)
            modelContext.insert(
                StoredMedicationStock(
                    medicationID: medication.id,
                    remainingQuantity: input.initialStockQuantity,
                    unit: trimmedStockUnit.isEmpty ? input.doseUnit : trimmedStockUnit,
                    lowStockThreshold: input.lowStockThreshold,
                    lastUpdated: input.createdAt
                )
            )
        }

        do {
            try saveOperation(modelContext)
            return .committed(
                medicationID: medication.id,
                planID: plan.id,
                reminderBatch: reminderBatch
            )
        } catch {
            modelContext.rollback()
            AppPersistenceCommitter.reportFailure(operation: "medication-create-with-plan")
            return .saveFailed
        }
    }

    private func normalizedReminderTimes(_ dates: [Date]) -> [(hour: Int, minute: Int, text: String)] {
        var seen = Set<String>()
        return dates
            .map { date in
                let hour = calendar.component(.hour, from: date)
                let minute = calendar.component(.minute, from: date)
                return (hour: hour, minute: minute, text: String(format: "%02d:%02d", hour, minute))
            }
            .sorted { lhs, rhs in
                lhs.hour == rhs.hour ? lhs.minute < rhs.minute : lhs.hour < rhs.hour
            }
            .filter { seen.insert($0.text).inserted }
    }
}
