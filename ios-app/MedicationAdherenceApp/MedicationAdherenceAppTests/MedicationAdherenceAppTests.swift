import Foundation
import MedicationAdherenceCore
import SwiftData
import Testing
@testable import MedicationAdherenceApp

struct MedicationAdherenceAppTests {
    @Test
    func inMemoryContainerPersistsAcrossModelContexts() throws {
        let container = try MedicationAdherenceModelContainer.make(isStoredInMemoryOnly: true)
        let messageID = UUID()
        let writeContext = ModelContext(container)
        writeContext.insert(StoredAIChatMessage(
            id: messageID,
            role: .user,
            text: "SwiftData round-trip",
            providerName: "test-provider",
            modelName: "test-model"
        ))

        try writeContext.save()

        let readContext = ModelContext(container)
        let messages = try readContext.fetch(FetchDescriptor<StoredAIChatMessage>())
        let reloadedMessage = try #require(messages.first { $0.id == messageID })

        #expect(reloadedMessage.text == "SwiftData round-trip")
        #expect(reloadedMessage.role == .user)
        #expect(reloadedMessage.providerName == "test-provider")
        #expect(reloadedMessage.modelName == "test-model")
    }

    @Test
    func schemaSupportsEveryStoredModel() throws {
        let container = try MedicationAdherenceModelContainer.make(isStoredInMemoryOnly: true)
        let context = ModelContext(container)

        #expect(try context.fetch(FetchDescriptor<StoredMedication>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<StoredMedicationLifecycleEvent>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<StoredMedicationPlan>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<StoredMedicationDoseChange>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<StoredDoseTask>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<StoredRiskCard>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<StoredMedicationLabel>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<StoredMedicationStock>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<StoredDoseActionLog>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<StoredAIConsent>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<StoredAIChatMessage>()).isEmpty)
    }

    @Test
    func explicitDemoModeRebuildsStandardDemoContentAndPreservesUserMedication() throws {
        let container = try MedicationAdherenceModelContainer.make(isStoredInMemoryOnly: true)
        let context = ModelContext(container)
        let userMedicationID = UUID()
        context.insert(StoredMedication(
            id: userMedicationID,
            displayName: "用户自建药品",
            kind: .prescription,
            inputSource: .manual,
            notes: "必须保留",
            isDemoContent: false
        ))
        try context.save()

        try DemoDataSeeder.rebuildForExplicitDemoMode(in: context)
        try verifyStandardDemoContent(in: context, preserving: userMedicationID)

        let demoMedications = try context.fetch(FetchDescriptor<StoredMedication>())
            .filter(\.isDemoContent)
        let demoMedicationIDs = Set(demoMedications.map(\.id))
        let demoTasks = try context.fetch(FetchDescriptor<StoredDoseTask>())
            .filter { demoMedicationIDs.contains($0.medicationID) }
        let demoStocks = try context.fetch(FetchDescriptor<StoredMedicationStock>())
            .filter { demoMedicationIDs.contains($0.medicationID) }

        demoMedications[0].displayName = "已被修改的演示药品"
        demoTasks[0].status = .taken
        demoTasks[0].recordedAt = Date()
        demoStocks[0].remainingQuantity = 1
        try context.save()

        try DemoDataSeeder.rebuildForExplicitDemoMode(in: context)
        try verifyStandardDemoContent(in: context, preserving: userMedicationID)

        try DemoDataSeeder.rebuildForExplicitDemoMode(in: context)
        try verifyStandardDemoContent(in: context, preserving: userMedicationID)
    }

    @Test
    func legacySchemaKeepsEntityNamesAndOnlyOmitsTheTwoNewFields() throws {
        let legacySchema = Schema(MedicationAdherenceSchemaV1.models)
        let currentSchema = Schema(versionedSchema: MedicationAdherenceSchemaV2.self)

        #expect(legacySchema.entities.map(\.name).sorted() == currentSchema.entities.map(\.name).sorted())

        let legacyMedication = try #require(legacySchema.entitiesByName["StoredMedication"])
        let currentMedication = try #require(currentSchema.entitiesByName["StoredMedication"])
        #expect(legacyMedication.storedPropertiesByName["colorTagRaw"] == nil)
        #expect(currentMedication.storedPropertiesByName["colorTagRaw"] != nil)

        let legacyPlan = try #require(legacySchema.entitiesByName["StoredMedicationPlan"])
        let currentPlan = try #require(currentSchema.entitiesByName["StoredMedicationPlan"])
        #expect(legacyPlan.storedPropertiesByName["escalatesToAlarmWhenUnhandledRaw"] == nil)
        #expect(currentPlan.storedPropertiesByName["escalatesToAlarmWhenUnhandledRaw"] != nil)
    }

    private func verifyStandardDemoContent(in context: ModelContext, preserving userMedicationID: UUID) throws {
        let medications = try context.fetch(FetchDescriptor<StoredMedication>())
        let demoMedications = medications.filter(\.isDemoContent)
        let demoMedicationIDs = Set(demoMedications.map(\.id))
        let tasks = try context.fetch(FetchDescriptor<StoredDoseTask>())
            .filter { demoMedicationIDs.contains($0.medicationID) }
        let todayTasks = tasks.filter { Calendar.current.isDateInToday($0.dueAt) }
        let plans = try context.fetch(FetchDescriptor<StoredMedicationPlan>())
            .filter { demoMedicationIDs.contains($0.medicationID) }
        let stocks = try context.fetch(FetchDescriptor<StoredMedicationStock>())
            .filter { demoMedicationIDs.contains($0.medicationID) }
        let labels = try context.fetch(FetchDescriptor<StoredMedicationLabel>())
            .filter { demoMedicationIDs.contains($0.medicationID) }
        let doseChanges = try context.fetch(FetchDescriptor<StoredMedicationDoseChange>())
            .filter { demoMedicationIDs.contains($0.medicationID) }

        #expect(medications.contains { $0.id == userMedicationID && !$0.isDemoContent && $0.notes == "必须保留" })
        #expect(Set(demoMedications.map(\.displayName)) == Set([
            "布洛芬",
            "对乙酰氨基酚",
            "人工泪液",
            "氯雷他定",
            "维生素 D3"
        ]))
        #expect(demoMedications.allSatisfy { $0.lifecycleStatus == .active })
        #expect(plans.count == 5)
        #expect(tasks.count == 305)
        #expect(todayTasks.count == 5)
        #expect(todayTasks.allSatisfy { $0.status == .pending && $0.recordedAt == nil })
        #expect(stocks.count == 5)
        #expect(stocks.allSatisfy { $0.remainingQuantity == 90 })
        #expect(labels.count == 5)
        #expect(doseChanges.count == 1)
    }

    @Test
    func legacyStoreMigratesEveryModelAndReopensIdempotently() throws {
        let fixture = LegacyMigrationFixture()
        let storeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("MedicationAdherenceMigration-\(UUID().uuidString)")
            .appendingPathExtension("store")

        try createLegacyStore(at: storeURL, fixture: fixture)
        try verifyMigratedStore(at: storeURL, fixture: fixture)
        try verifyMigratedStore(at: storeURL, fixture: fixture)
    }

    private func createLegacyStore(at storeURL: URL, fixture: LegacyMigrationFixture) throws {
        let schema = Schema(MedicationAdherenceSchemaV1.models)
        let configuration = ModelConfiguration(
            "MedicationAdherence",
            schema: schema,
            url: storeURL,
            cloudKitDatabase: .none
        )
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = ModelContext(container)

        context.insert(MedicationAdherenceSchemaV1.StoredMedication(
            id: fixture.medicationID,
            displayName: "Migration Medication",
            genericName: "migration-generic",
            kindRaw: MedicationKind.prescription.rawValue,
            form: "tablet",
            strength: "10 mg",
            inputSourceRaw: MedicationInputSource.prescriptionImage.rawValue,
            photoSymbolName: "cross.case.fill",
            photoData: Data([0x01, 0x02, 0x03]),
            boxNumber: "BOX-17",
            notes: "preserve medication notes",
            lifecycleStatusRaw: StoredMedicationLifecycleStatus.interrupted.rawValue,
            isDemoContent: true,
            createdAt: fixture.baseDate
        ))
        context.insert(StoredMedicationLifecycleEvent(
            id: fixture.lifecycleEventID,
            medicationID: fixture.medicationID,
            status: .interrupted,
            occurredAt: fixture.baseDate.addingTimeInterval(60),
            note: "preserve lifecycle note"
        ))
        context.insert(MedicationAdherenceSchemaV1.StoredMedicationPlan(
            id: fixture.planID,
            medicationID: fixture.medicationID,
            doseValue: 1.5,
            doseUnit: "tablet",
            timingSummary: "Every 8 hours",
            timeZonePolicyRaw: ReminderTimeZonePolicy.fixedInterval.rawValue,
            sourceNote: "preserve plan source",
            requiresUserConfirmation: false,
            courseStartAt: fixture.baseDate.addingTimeInterval(-86_400),
            courseEndAt: fixture.baseDate.addingTimeInterval(604_800),
            reminderTimesRaw: "08:15,16:15",
            reminderDeliveryRaw: StoredReminderDeliveryMethod.alarm.rawValue,
            createdAt: fixture.baseDate.addingTimeInterval(120)
        ))
        context.insert(StoredMedicationDoseChange(
            id: fixture.doseChangeID,
            medicationID: fixture.medicationID,
            planID: fixture.planID,
            previousDoseValue: 1,
            previousDoseUnit: "tablet",
            newDoseValue: 1.5,
            newDoseUnit: "tablet",
            effectiveFrom: fixture.baseDate.addingTimeInterval(180),
            changedAt: fixture.baseDate.addingTimeInterval(150),
            note: "preserve dose change"
        ))
        context.insert(StoredDoseTask(
            id: fixture.taskID,
            medicationID: fixture.medicationID,
            planID: fixture.planID,
            dueAt: fixture.baseDate.addingTimeInterval(240),
            doseValue: 1.5,
            doseUnit: "tablet",
            status: .corrected,
            recordedAt: fixture.baseDate.addingTimeInterval(300),
            reason: "preserve task reason"
        ))
        context.insert(StoredRiskCard(
            id: fixture.riskID,
            medicationID: fixture.medicationID,
            kindRaw: "migration-risk",
            severityRaw: StoredRiskSeverity.high.rawValue,
            sourceKindRaw: StoredRiskSourceKind.drugLabel.rawValue,
            displayPriority: 2,
            title: "Migration risk",
            message: "Preserve this risk",
            sourceTitle: "Synthetic label",
            sourceExcerpt: "Synthetic evidence",
            detectionSignature: "migration-signature",
            requiresProfessionalReview: true,
            safetyNote: "Review with a professional.",
            firstDetectedAt: fixture.baseDate.addingTimeInterval(360),
            lastDetectedAt: fixture.baseDate.addingTimeInterval(420),
            readAt: fixture.baseDate.addingTimeInterval(480),
            resolvedAt: nil,
            resolutionNote: "",
            reviewedAt: fixture.baseDate.addingTimeInterval(540),
            archivedAt: nil,
            reviewNote: "preserve review note"
        ))
        context.insert(StoredMedicationLabel(
            id: fixture.labelID,
            medicationID: fixture.medicationID,
            medicationName: "Migration Medication",
            rawText: "Synthetic label text",
            sourceTitle: "Synthetic source",
            source: .dailyMed,
            averageOCRConfidence: 0.87,
            importedAt: fixture.baseDate.addingTimeInterval(600),
            lastRiskReviewAt: fixture.baseDate.addingTimeInterval(660)
        ))
        context.insert(StoredMedicationStock(
            id: fixture.stockID,
            medicationID: fixture.medicationID,
            remainingQuantity: 17.5,
            unit: "tablet",
            lowStockThreshold: 4,
            lastUpdated: fixture.baseDate.addingTimeInterval(720)
        ))
        context.insert(StoredDoseActionLog(
            id: fixture.actionLogID,
            taskID: fixture.taskID,
            action: .correct,
            previousStatus: .delayed,
            previousDueAt: fixture.baseDate.addingTimeInterval(180),
            previousRecordedAt: fixture.baseDate.addingTimeInterval(210),
            previousReason: "preserve previous reason",
            newStatus: .corrected,
            occurredAt: fixture.baseDate.addingTimeInterval(780),
            undoExpiresAt: fixture.baseDate.addingTimeInterval(1_380),
            note: "preserve action note",
            undoneAt: fixture.baseDate.addingTimeInterval(840)
        ))
        context.insert(StoredAIConsent(
            id: fixture.consentID,
            sharesMedicationProfile: true,
            sharesMedicationPlans: false,
            sharesDoseEvents: true,
            sharesRiskCards: false,
            sharesDrugLabels: true,
            sharesImportDraft: true,
            grantedAt: fixture.baseDate.addingTimeInterval(900),
            revokedAt: fixture.baseDate.addingTimeInterval(960),
            note: "preserve consent note"
        ))
        context.insert(StoredAIChatMessage(
            id: fixture.chatMessageID,
            role: .system,
            text: "Preserve migrated chat",
            createdAt: fixture.baseDate.addingTimeInterval(1_020),
            providerName: "migration-provider",
            modelName: "migration-model",
            requestKind: .riskOptimization,
            sharedScopesSummary: "medication,risk"
        ))

        try context.save()
    }

    private func verifyMigratedStore(at storeURL: URL, fixture: LegacyMigrationFixture) throws {
        let container = try MedicationAdherenceModelContainer.make(storeURL: storeURL)
        let context = ModelContext(container)

        let medications = try context.fetch(FetchDescriptor<StoredMedication>())
        let lifecycleEvents = try context.fetch(FetchDescriptor<StoredMedicationLifecycleEvent>())
        let plans = try context.fetch(FetchDescriptor<StoredMedicationPlan>())
        let doseChanges = try context.fetch(FetchDescriptor<StoredMedicationDoseChange>())
        let tasks = try context.fetch(FetchDescriptor<StoredDoseTask>())
        let risks = try context.fetch(FetchDescriptor<StoredRiskCard>())
        let labels = try context.fetch(FetchDescriptor<StoredMedicationLabel>())
        let stocks = try context.fetch(FetchDescriptor<StoredMedicationStock>())
        let actionLogs = try context.fetch(FetchDescriptor<StoredDoseActionLog>())
        let consents = try context.fetch(FetchDescriptor<StoredAIConsent>())
        let chatMessages = try context.fetch(FetchDescriptor<StoredAIChatMessage>())

        #expect(medications.count == 1)
        #expect(lifecycleEvents.count == 1)
        #expect(plans.count == 1)
        #expect(doseChanges.count == 1)
        #expect(tasks.count == 1)
        #expect(risks.count == 1)
        #expect(labels.count == 1)
        #expect(stocks.count == 1)
        #expect(actionLogs.count == 1)
        #expect(consents.count == 1)
        #expect(chatMessages.count == 1)

        let medication = try #require(medications.first)
        #expect(medication.id == fixture.medicationID)
        #expect(medication.displayName == "Migration Medication")
        #expect(medication.genericName == "migration-generic")
        #expect(medication.kindRaw == MedicationKind.prescription.rawValue)
        #expect(medication.inputSourceRaw == MedicationInputSource.prescriptionImage.rawValue)
        #expect(medication.photoData == Data([0x01, 0x02, 0x03]))
        #expect(medication.boxNumber == "BOX-17")
        #expect(medication.lifecycleStatus == .interrupted)
        #expect(medication.isDemoContent)
        #expect(medication.colorTagRaw.isEmpty)

        let lifecycleEvent = try #require(lifecycleEvents.first)
        #expect(lifecycleEvent.id == fixture.lifecycleEventID)
        #expect(lifecycleEvent.medicationID == fixture.medicationID)
        #expect(lifecycleEvent.status == .interrupted)
        #expect(lifecycleEvent.note == "preserve lifecycle note")

        let plan = try #require(plans.first)
        #expect(plan.id == fixture.planID)
        #expect(plan.medicationID == fixture.medicationID)
        #expect(plan.doseValue == 1.5)
        #expect(plan.reminderTimesRaw == "08:15,16:15")
        #expect(plan.reminderDeliveryMethod == .alarm)
        #expect(plan.escalatesToAlarmWhenUnhandledRaw == nil)
        #expect(plan.escalatesToAlarmWhenUnhandled)

        let doseChange = try #require(doseChanges.first)
        #expect(doseChange.id == fixture.doseChangeID)
        #expect(doseChange.medicationID == fixture.medicationID)
        #expect(doseChange.planID == fixture.planID)
        #expect(doseChange.previousDoseValue == 1)
        #expect(doseChange.newDoseValue == 1.5)
        #expect(doseChange.note == "preserve dose change")

        let task = try #require(tasks.first)
        #expect(task.id == fixture.taskID)
        #expect(task.medicationID == fixture.medicationID)
        #expect(task.planID == fixture.planID)
        #expect(task.status == .corrected)
        #expect(task.reason == "preserve task reason")

        let risk = try #require(risks.first)
        #expect(risk.id == fixture.riskID)
        #expect(risk.medicationID == fixture.medicationID)
        #expect(risk.severityRaw == StoredRiskSeverity.high.rawValue)
        #expect(risk.sourceKindRaw == StoredRiskSourceKind.drugLabel.rawValue)
        #expect(risk.detectionSignature == "migration-signature")
        #expect(risk.readAt == fixture.baseDate.addingTimeInterval(480))
        #expect(risk.reviewNote == "preserve review note")

        let label = try #require(labels.first)
        #expect(label.id == fixture.labelID)
        #expect(label.medicationID == fixture.medicationID)
        #expect(label.source == .dailyMed)
        #expect(label.lastRiskReviewAt == fixture.baseDate.addingTimeInterval(660))

        let stock = try #require(stocks.first)
        #expect(stock.id == fixture.stockID)
        #expect(stock.medicationID == fixture.medicationID)
        #expect(stock.remainingQuantity == 17.5)
        #expect(stock.lowStockThreshold == 4)

        let actionLog = try #require(actionLogs.first)
        #expect(actionLog.id == fixture.actionLogID)
        #expect(actionLog.taskID == fixture.taskID)
        #expect(actionLog.actionRaw == DoseActionKind.correct.rawValue)
        #expect(actionLog.previousStatus == .delayed)
        #expect(actionLog.newStatusRaw == StoredDoseStatus.corrected.rawValue)
        #expect(actionLog.undoneAt == fixture.baseDate.addingTimeInterval(840))

        let consent = try #require(consents.first)
        #expect(consent.id == fixture.consentID)
        #expect(consent.sharesMedicationProfile)
        #expect(!consent.sharesMedicationPlans)
        #expect(consent.sharesImportDraft)
        #expect(consent.revokedAt == fixture.baseDate.addingTimeInterval(960))

        let chatMessage = try #require(chatMessages.first)
        #expect(chatMessage.id == fixture.chatMessageID)
        #expect(chatMessage.role == .system)
        #expect(chatMessage.requestKindRaw == MedicalAIRequestKind.riskOptimization.rawValue)
        #expect(chatMessage.text == "Preserve migrated chat")
    }
}

private struct LegacyMigrationFixture {
    let medicationID = UUID()
    let lifecycleEventID = UUID()
    let planID = UUID()
    let doseChangeID = UUID()
    let taskID = UUID()
    let riskID = "migration-risk-card"
    let labelID = UUID()
    let stockID = UUID()
    let actionLogID = UUID()
    let consentID = "migration-consent"
    let chatMessageID = UUID()
    let baseDate = Date(timeIntervalSince1970: 1_700_000_000)
}
