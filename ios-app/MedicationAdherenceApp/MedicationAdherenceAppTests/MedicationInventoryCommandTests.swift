import Foundation
import SwiftData
import Testing
@testable import MedicationAdherenceApp

@Suite(.serialized)
struct MedicationInventoryCommandTests {
    @Test @MainActor
    func createsStockAndReturnsCommittedIdentifier() throws {
        let fixture = try MedicationInventoryFixture()
        let updatedAt = Date(timeIntervalSince1970: 1_700_000_100)

        let outcome = MedicationInventoryCommand(modelContext: fixture.context).upsert(
            MedicationInventoryUpdate(
                medicationID: fixture.medicationID,
                remainingQuantity: 48,
                unit: " 片 ",
                lowStockThreshold: 8,
                updatedAt: updatedAt
            )
        )

        guard case let .committed(stockID, created) = outcome else {
            Issue.record("Expected inventory creation to commit")
            return
        }
        #expect(created)
        let verificationContext = ModelContext(fixture.container)
        let stock = try #require(verificationContext.fetch(FetchDescriptor<StoredMedicationStock>()).first)
        #expect(stock.id == stockID)
        #expect(stock.medicationID == fixture.medicationID)
        #expect(stock.remainingQuantity == 48)
        #expect(stock.unit == "片")
        #expect(stock.lowStockThreshold == 8)
        #expect(stock.lastUpdated == updatedAt)
    }

    @Test @MainActor
    func updatesExistingStockWithoutCreatingDuplicate() throws {
        let fixture = try MedicationInventoryFixture()
        let stock = StoredMedicationStock(
            medicationID: fixture.medicationID,
            remainingQuantity: 12,
            unit: "盒",
            lowStockThreshold: 2,
            lastUpdated: Date(timeIntervalSince1970: 1_700_000_000)
        )
        fixture.context.insert(stock)
        try fixture.context.save()
        let updatedAt = Date(timeIntervalSince1970: 1_700_000_200)

        let outcome = MedicationInventoryCommand(modelContext: fixture.context).upsert(
            MedicationInventoryUpdate(
                medicationID: fixture.medicationID,
                remainingQuantity: 20,
                unit: "盒",
                lowStockThreshold: 4,
                updatedAt: updatedAt
            )
        )

        #expect(outcome == .committed(stockID: stock.id, created: false))
        let verificationContext = ModelContext(fixture.container)
        let persistedStocks = try verificationContext.fetch(FetchDescriptor<StoredMedicationStock>())
        #expect(persistedStocks.count == 1)
        #expect(persistedStocks.first?.remainingQuantity == 20)
        #expect(persistedStocks.first?.lowStockThreshold == 4)
        #expect(persistedStocks.first?.lastUpdated == updatedAt)
    }

    @Test @MainActor
    func saveFailureRollsBackExistingStock() throws {
        let fixture = try MedicationInventoryFixture()
        let originalUpdatedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let stock = StoredMedicationStock(
            medicationID: fixture.medicationID,
            remainingQuantity: 12,
            unit: "盒",
            lowStockThreshold: 2,
            lastUpdated: originalUpdatedAt
        )
        fixture.context.insert(stock)
        try fixture.context.save()
        let command = MedicationInventoryCommand(modelContext: fixture.context) { _ in
            throw SyntheticInventorySaveError.unavailable
        }

        let outcome = command.upsert(
            MedicationInventoryUpdate(
                medicationID: fixture.medicationID,
                remainingQuantity: 99,
                unit: "片",
                lowStockThreshold: 50,
                updatedAt: originalUpdatedAt.addingTimeInterval(60)
            )
        )

        #expect(outcome == .saveFailed)
        #expect(stock.remainingQuantity == 12)
        #expect(stock.unit == "盒")
        #expect(stock.lowStockThreshold == 2)
        #expect(stock.lastUpdated == originalUpdatedAt)
        #expect(!fixture.context.hasChanges)
        let verificationContext = ModelContext(fixture.container)
        let persistedStock = try #require(verificationContext.fetch(FetchDescriptor<StoredMedicationStock>()).first)
        #expect(persistedStock.remainingQuantity == 12)
        #expect(persistedStock.unit == "盒")
    }

    @Test @MainActor
    func saveFailureDoesNotLeaveNewStock() throws {
        let fixture = try MedicationInventoryFixture()
        let command = MedicationInventoryCommand(modelContext: fixture.context) { _ in
            throw SyntheticInventorySaveError.unavailable
        }

        let outcome = command.upsert(
            MedicationInventoryUpdate(
                medicationID: fixture.medicationID,
                remainingQuantity: 12,
                unit: "片",
                lowStockThreshold: 2,
                updatedAt: Date(timeIntervalSince1970: 1_700_000_000)
            )
        )

        #expect(outcome == .saveFailed)
        #expect(try fixture.context.fetch(FetchDescriptor<StoredMedicationStock>()).isEmpty)
        #expect(!fixture.context.hasChanges)
        let verificationContext = ModelContext(fixture.container)
        #expect(try verificationContext.fetch(FetchDescriptor<StoredMedicationStock>()).isEmpty)
    }

    @Test @MainActor
    func emptyUnitIsRejectedWithoutWriting() throws {
        let fixture = try MedicationInventoryFixture()

        let outcome = MedicationInventoryCommand(modelContext: fixture.context).upsert(
            MedicationInventoryUpdate(
                medicationID: fixture.medicationID,
                remainingQuantity: 12,
                unit: "   ",
                lowStockThreshold: 2,
                updatedAt: Date(timeIntervalSince1970: 1_700_000_000)
            )
        )

        #expect(outcome == .rejected(.emptyUnit))
        #expect(try fixture.context.fetch(FetchDescriptor<StoredMedicationStock>()).isEmpty)
        #expect(!fixture.context.hasChanges)
    }
}

@MainActor
private struct MedicationInventoryFixture {
    let container: ModelContainer
    let context: ModelContext
    let medicationID = UUID()

    init() throws {
        container = try MedicationAdherenceModelContainer.make(isStoredInMemoryOnly: true)
        context = ModelContext(container)
        context.autosaveEnabled = false
    }
}

private enum SyntheticInventorySaveError: Error {
    case unavailable
}
