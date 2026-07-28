import Foundation
import MedicationAdherenceCore
import SwiftData
import Testing
@testable import MedicationAdherenceApp

@Suite(.serialized)
struct VisitSummaryDataPipelineTests {
    @Test @MainActor
    func rangeLoadIncludesOnlyRelevantStoredGraph() throws {
        let fixture = try VisitSummaryDataFixture()

        let outcome = VisitSummaryDataCommand(modelContext: fixture.context).load(
            startDate: fixture.rangeStart,
            endDate: fixture.rangeEnd
        )

        guard case let .loaded(data) = outcome else {
            Issue.record("Expected visit summary data to load, got \(String(describing: outcome))")
            return
        }
        #expect(Set(data.tasks.map(\.id)) == [fixture.inRangeTask.id, fixture.earlyRecordedTask.id])
        #expect(data.doseChanges.map(\.id) == [fixture.inRangeDoseChange.id])
        #expect(data.riskCards.map(\.id) == [fixture.inRangeRisk.id])
        #expect(data.medications.map(\.id) == [fixture.relevantMedication.id])
        #expect(data.plans.map(\.medicationID) == [fixture.relevantMedication.id])
        #expect(data.lifecycleEvents.map(\.medicationID) == [fixture.relevantMedication.id])
    }

    @Test @MainActor
    func exportPayloadCopiesValuesBeforeStoredModelsChange() throws {
        let fixture = try VisitSummaryDataFixture()
        let outcome = VisitSummaryDataCommand(modelContext: fixture.context).load(
            startDate: fixture.rangeStart,
            endDate: fixture.rangeEnd
        )
        guard case let .loaded(data) = outcome else {
            Issue.record("Expected visit summary data to load, got \(String(describing: outcome))")
            return
        }

        let payload = VisitSummaryExportPayload(
            data: data,
            trendDashboard: fixture.emptyTrendDashboard,
            healthSignals: [],
            startDate: fixture.rangeStart,
            endDate: fixture.rangeEnd,
            generatedAt: fixture.rangeEnd,
            exportSignature: "stable"
        )
        fixture.relevantMedication.displayName = "已修改药名"
        fixture.inRangeTask.doseValue = 9
        fixture.inRangeRisk.message = "已修改风险"

        #expect(payload.medications.first?.displayName == "范围内药品")
        #expect(payload.tasks.first(where: { $0.id == fixture.inRangeTask.id })?.doseValue == 1)
        #expect(payload.riskCards.first?.message == "范围内风险")
    }

    @Test
    func generationGateRejectsAnOlderCompletion() {
        var gate = VisitSummaryGenerationGate()
        let first = gate.begin()
        let second = gate.begin()

        #expect(!gate.accepts(first))
        #expect(gate.accepts(second))
        gate.cancel()
        #expect(!gate.accepts(second))
    }

    @Test @MainActor
    func pdfExporterWritesAReadablePDF() async throws {
        let fixture = try VisitSummaryDataFixture()
        let outcome = VisitSummaryDataCommand(modelContext: fixture.context).load(
            startDate: fixture.rangeStart,
            endDate: fixture.rangeEnd
        )
        guard case let .loaded(data) = outcome else {
            Issue.record("Expected visit summary data to load")
            return
        }
        let payload = VisitSummaryExportPayload(
            data: data,
            trendDashboard: fixture.emptyTrendDashboard,
            healthSignals: [],
            startDate: fixture.rangeStart,
            endDate: fixture.rangeEnd,
            generatedAt: fixture.rangeEnd,
            exportSignature: "pdf-test"
        )
        let targetURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("visit-summary-test-\(UUID().uuidString).pdf")

        let completedURL = try await VisitSummaryPDFExporter.export(
            payload: payload,
            targetURL: targetURL
        )
        let dataAtURL = try Data(contentsOf: completedURL)

        #expect(dataAtURL.starts(with: Data("%PDF".utf8)))
        #expect(dataAtURL.count > 1_000)
    }
}

@MainActor
private struct VisitSummaryDataFixture {
    let context: ModelContext
    let rangeStart = Date(timeIntervalSince1970: 1_800_000_000)
    let rangeEnd = Date(timeIntervalSince1970: 1_800_086_399)
    let relevantMedication: StoredMedication
    let unrelatedMedication: StoredMedication
    let inRangeTask: StoredDoseTask
    let earlyRecordedTask: StoredDoseTask
    let inRangeDoseChange: StoredMedicationDoseChange
    let inRangeRisk: StoredRiskCard

    var emptyTrendDashboard: MedicationTrendDashboard {
        MedicationTrendDashboardBuilder().build(
            scheduledDoses: [],
            events: [],
            doseChanges: [],
            healthSignals: [],
            timeZone: TimeZone(secondsFromGMT: 0)!,
            now: rangeEnd
        )
    }

    init() throws {
        let rangeStartValue = Date(timeIntervalSince1970: 1_800_000_000)
        let container = try ModelContainer(
            for: StoredMedication.self,
            StoredMedicationPlan.self,
            StoredMedicationDoseChange.self,
            StoredDoseTask.self,
            StoredRiskCard.self,
            StoredMedicationLifecycleEvent.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let localContext = ModelContext(container)
        let localRelevantMedication = StoredMedication(
            displayName: "范围内药品",
            kind: .prescription,
            inputSource: .manual,
            createdAt: rangeStartValue
        )
        let localUnrelatedMedication = StoredMedication(
            displayName: "无关药品",
            kind: .overTheCounter,
            inputSource: .manual,
            createdAt: rangeStartValue
        )
        localContext.insert(localRelevantMedication)
        localContext.insert(localUnrelatedMedication)

        let relevantPlan = Self.makePlan(medicationID: localRelevantMedication.id, createdAt: rangeStartValue)
        let unrelatedPlan = Self.makePlan(medicationID: localUnrelatedMedication.id, createdAt: rangeStartValue)
        localContext.insert(relevantPlan)
        localContext.insert(unrelatedPlan)
        let localInRangeTask = StoredDoseTask(
            medicationID: localRelevantMedication.id,
            planID: relevantPlan.id,
            dueAt: rangeStartValue.addingTimeInterval(3_600),
            doseValue: 1,
            doseUnit: "片",
            status: .taken,
            recordedAt: rangeStartValue.addingTimeInterval(3_900)
        )
        let localEarlyRecordedTask = StoredDoseTask(
            medicationID: localRelevantMedication.id,
            planID: relevantPlan.id,
            dueAt: rangeStartValue.addingTimeInterval(172_799),
            doseValue: 2,
            doseUnit: "片",
            status: .taken,
            recordedAt: rangeStartValue.addingTimeInterval(7_200)
        )
        let oldTask = StoredDoseTask(
            medicationID: localRelevantMedication.id,
            planID: relevantPlan.id,
            dueAt: rangeStartValue.addingTimeInterval(-172_800),
            doseValue: 1,
            doseUnit: "片",
            status: .taken,
            recordedAt: rangeStartValue.addingTimeInterval(-172_000)
        )
        let unrelatedTask = StoredDoseTask(
            medicationID: localUnrelatedMedication.id,
            planID: unrelatedPlan.id,
            dueAt: rangeStartValue.addingTimeInterval(-172_800),
            doseValue: 1,
            doseUnit: "片",
            status: .taken,
            recordedAt: rangeStartValue.addingTimeInterval(-172_000)
        )
        [localInRangeTask, localEarlyRecordedTask, oldTask, unrelatedTask].forEach(localContext.insert)

        let localInRangeDoseChange = StoredMedicationDoseChange(
            medicationID: localRelevantMedication.id,
            planID: relevantPlan.id,
            newDoseValue: 1,
            newDoseUnit: "片",
            effectiveFrom: rangeStartValue.addingTimeInterval(1_800)
        )
        localContext.insert(localInRangeDoseChange)
        localContext.insert(StoredMedicationDoseChange(
            medicationID: localUnrelatedMedication.id,
            planID: unrelatedPlan.id,
            newDoseValue: 1,
            newDoseUnit: "片",
            effectiveFrom: rangeStartValue.addingTimeInterval(-172_800)
        ))

        let localInRangeRisk = StoredRiskCard(
            id: "range-risk",
            medicationID: localRelevantMedication.id,
            kindRaw: RiskAssessmentCardKind.labelRisk.rawValue,
            displayPriority: 1,
            title: "范围内",
            message: "范围内风险",
            requiresProfessionalReview: true,
            safetyNote: "",
            firstDetectedAt: rangeStartValue,
            lastDetectedAt: rangeStartValue.addingTimeInterval(2_400)
        )
        localContext.insert(localInRangeRisk)
        localContext.insert(StoredRiskCard(
            id: "old-risk",
            medicationID: localUnrelatedMedication.id,
            kindRaw: RiskAssessmentCardKind.labelRisk.rawValue,
            displayPriority: 1,
            title: "范围外",
            message: "范围外风险",
            requiresProfessionalReview: true,
            safetyNote: "",
            firstDetectedAt: rangeStartValue.addingTimeInterval(-172_800),
            lastDetectedAt: rangeStartValue.addingTimeInterval(-172_800)
        ))
        localContext.insert(StoredMedicationLifecycleEvent(
            medicationID: localRelevantMedication.id,
            status: .active,
            occurredAt: rangeStartValue.addingTimeInterval(-86_400)
        ))
        localContext.insert(StoredMedicationLifecycleEvent(
            medicationID: localUnrelatedMedication.id,
            status: .active,
            occurredAt: rangeStartValue.addingTimeInterval(-86_400)
        ))
        try localContext.save()

        context = localContext
        relevantMedication = localRelevantMedication
        unrelatedMedication = localUnrelatedMedication
        inRangeTask = localInRangeTask
        earlyRecordedTask = localEarlyRecordedTask
        inRangeDoseChange = localInRangeDoseChange
        inRangeRisk = localInRangeRisk
    }

    private static func makePlan(medicationID: UUID, createdAt: Date) -> StoredMedicationPlan {
        StoredMedicationPlan(
            medicationID: medicationID,
            doseValue: 1,
            doseUnit: "片",
            timingSummary: "每日一次",
            timeZonePolicy: .localClock,
            sourceNote: "",
            createdAt: createdAt
        )
    }
}
