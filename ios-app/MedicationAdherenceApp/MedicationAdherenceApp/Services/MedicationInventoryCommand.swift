import Foundation
import SwiftData

struct MedicationInventoryUpdate: Equatable, Sendable {
    let medicationID: UUID
    let remainingQuantity: Double
    let unit: String
    let lowStockThreshold: Double
    let updatedAt: Date
}

enum MedicationInventoryRejection: Equatable {
    case emptyUnit
    case readFailed
}

enum MedicationInventoryCommandOutcome: Equatable {
    case committed(stockID: UUID, created: Bool)
    case rejected(MedicationInventoryRejection)
    case saveFailed
}

@MainActor
struct MedicationInventoryCommand {
    typealias SaveOperation = (ModelContext) throws -> Void

    private let modelContext: ModelContext
    private let saveOperation: SaveOperation

    init(
        modelContext: ModelContext,
        saveOperation: @escaping SaveOperation = { try $0.save() }
    ) {
        self.modelContext = modelContext
        self.saveOperation = saveOperation
    }

    func upsert(_ update: MedicationInventoryUpdate) -> MedicationInventoryCommandOutcome {
        let normalizedUnit = update.unit.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedUnit.isEmpty else {
            return .rejected(.emptyUnit)
        }

        let stocks: [StoredMedicationStock]
        do {
            stocks = try modelContext.fetch(
                FetchDescriptor<StoredMedicationStock>(
                    sortBy: [SortDescriptor(\.lastUpdated, order: .reverse)]
                )
            )
        } catch {
            return .rejected(.readFailed)
        }

        let existingStock = stocks.first { $0.medicationID == update.medicationID }
        let existingSnapshot = existingStock.map(MedicationStockSnapshot.init)
        let stock: StoredMedicationStock
        let created: Bool
        if let existingStock {
            stock = existingStock
            created = false
        } else {
            stock = StoredMedicationStock(
                medicationID: update.medicationID,
                remainingQuantity: update.remainingQuantity,
                unit: normalizedUnit,
                lowStockThreshold: update.lowStockThreshold,
                lastUpdated: update.updatedAt
            )
            modelContext.insert(stock)
            created = true
        }

        stock.remainingQuantity = update.remainingQuantity
        stock.unit = normalizedUnit
        stock.lowStockThreshold = update.lowStockThreshold
        stock.lastUpdated = update.updatedAt

        do {
            try saveOperation(modelContext)
            return .committed(stockID: stock.id, created: created)
        } catch {
            if let existingSnapshot {
                existingSnapshot.restore()
            }
            modelContext.rollback()
            AppPersistenceCommitter.reportFailure(operation: "medication-stock-update")
            return .saveFailed
        }
    }
}

private struct MedicationStockSnapshot {
    let stock: StoredMedicationStock
    let remainingQuantity: Double
    let unit: String
    let lowStockThreshold: Double
    let lastUpdated: Date

    init(_ stock: StoredMedicationStock) {
        self.stock = stock
        remainingQuantity = stock.remainingQuantity
        unit = stock.unit
        lowStockThreshold = stock.lowStockThreshold
        lastUpdated = stock.lastUpdated
    }

    func restore() {
        stock.remainingQuantity = remainingQuantity
        stock.unit = unit
        stock.lowStockThreshold = lowStockThreshold
        stock.lastUpdated = lastUpdated
    }
}
