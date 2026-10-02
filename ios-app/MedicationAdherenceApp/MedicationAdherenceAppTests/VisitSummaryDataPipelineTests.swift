import Foundation
import MedicationAdherenceCore
import PDFKit
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
            endDateExclusive: fixture.rangeEndExclusive
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
            endDateExclusive: fixture.rangeEndExclusive
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
            endDateExclusive: fixture.rangeEndExclusive,
            generatedAt: fixture.rangeEndExclusive,
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
            endDateExclusive: fixture.rangeEndExclusive
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
            endDateExclusive: fixture.rangeEndExclusive,
            generatedAt: fixture.rangeEndExclusive,
            exportSignature: "pdf-test"
        )
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("visit-summary-test-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let lifecycle = VisitSummaryPDFLifecycle(
            rootDirectory: rootURL,
            expiryInterval: 3600,
            clock: { Date() }
        )

        let completedURL = try await VisitSummaryPDFExporter.export(
            payload: payload,
            lifecycle: lifecycle
        )
        let dataAtURL = try Data(contentsOf: completedURL)

        #expect(dataAtURL.starts(with: Data("%PDF".utf8)))
        #expect(dataAtURL.count > 1_000)
    }

    @Test @MainActor
    func calendarBoundaryFlowsThroughQueriesSnapshotTextAndPDF() async throws {
        let fixture = try VisitSummaryDataFixture()
        let selectedDay = try #require(Calendar.current.date(from:
            DateComponents(year: 2026, month: 10, day: 1, hour: 12)
        ))
        let range = VisitSummaryDateRange.normalized(startDate: selectedDay, endDate: selectedDay)
        let nextDay = try #require(Calendar.current.date(byAdding: .day, value: 1, to: range.start))
        let cases: [(String, Date, Bool)] = [
            ("before", range.start.addingTimeInterval(-0.5), false),
            ("start", range.start, true),
            ("last-whole", nextDay.addingTimeInterval(-1), true),
            ("last-fraction", nextDay.addingTimeInterval(-0.5), true),
            ("next-day", nextDay, false)
        ]
        var expectedTasks: Set<UUID> = []
        var expectedChanges: Set<UUID> = []
        var expectedRisks: Set<String> = []
        var expectedLifecycle: Set<UUID> = []
        var expectedSignals: Set<UUID> = []
        var signals: [HealthSignalSample] = []
        for (index, entry) in cases.enumerated() {
            let (label, instant, included) = entry
            let task = StoredDoseTask(
                medicationID: fixture.relevantMedication.id,
                planID: fixture.inRangeTask.planID,
                dueAt: selectedDay.addingTimeInterval(Double(index) * 60), doseValue: 1, doseUnit: "片",
                status: label == "last-fraction" ? .skipped : .taken,
                recordedAt: instant
            )
            let change = StoredMedicationDoseChange(
                medicationID: fixture.relevantMedication.id,
                planID: fixture.inRangeTask.planID,
                newDoseValue: 1, newDoseUnit: "片", effectiveFrom: instant
            )
            let risk = StoredRiskCard(
                id: "boundary-\(label)", medicationID: fixture.relevantMedication.id,
                kindRaw: RiskAssessmentCardKind.labelRisk.rawValue, displayPriority: 1,
                title: "边界 \(label)", message: "合成边界记录", requiresProfessionalReview: true,
                safetyNote: "", firstDetectedAt: instant, lastDetectedAt: instant
            )
            let lifecycle = StoredMedicationLifecycleEvent(
                medicationID: fixture.relevantMedication.id, status: .active, occurredAt: instant
            )
            let signal = HealthSignalSample(kind: .heartRate, measuredAt: instant, value: 70, unit: "次/分钟")
            fixture.context.insert(task)
            fixture.context.insert(change)
            fixture.context.insert(risk)
            fixture.context.insert(lifecycle)
            signals.append(signal)
            if included {
                expectedTasks.insert(task.id)
                expectedChanges.insert(change.id)
                expectedRisks.insert(risk.id)
                expectedSignals.insert(signal.id)
            }
            // Lifecycle context intentionally includes history before the selected start.
            if label != "next-day" { expectedLifecycle.insert(lifecycle.id) }
        }
        try fixture.context.save()
        let outcome = VisitSummaryDataCommand(modelContext: fixture.context).load(
            startDate: range.start, endDateExclusive: range.endExclusive
        )
        guard case let .loaded(data) = outcome else {
            Issue.record("Expected the selected calendar day to load")
            return
        }
        #expect(Set(data.tasks.map(\.id)) == expectedTasks)
        #expect(Set(data.doseChanges.map(\.id)) == expectedChanges)
        #expect(Set(data.riskCards.map(\.id)) == expectedRisks)
        #expect(Set(data.lifecycleEvents.map(\.id)) == expectedLifecycle)
        let revision = VisitSummarySnapshotRevision(
            startDate: range.start, endDateExclusive: range.endExclusive,
            medicationSignature: 1, taskSignature: 1, doseChangeSignature: 1,
            riskCardSignature: 1, healthSignalSignature: 1, planSignature: 1, lifecycleEventSignature: 1
        )
        let snapshot = VisitSummarySnapshot.build(
            revision: revision, medications: data.medications, tasks: data.tasks,
            doseChanges: data.doseChanges, plans: data.plans, lifecycleEvents: data.lifecycleEvents,
            riskCards: data.riskCards, healthSignals: signals, healthRefreshedAt: nextDay,
            generatedAt: nextDay
        )
        #expect(Set(snapshot.tasks.map(\.id)) == expectedTasks)
        #expect(Set(snapshot.doseChanges.map(\.id)) == expectedChanges)
        #expect(Set(snapshot.riskCards.map(\.id)) == expectedRisks)
        #expect(Set(snapshot.healthSignals.map(\.id)) == expectedSignals)
        #expect(snapshot.healthSummary.sampleCount == 3)
        #expect(snapshot.healthSummary.coveredDayCount == 1)
        #expect(snapshot.completedCount == 2)
        #expect(snapshot.completionRate == 2.0 / 3.0)
        let dayText = AppFormatters.day.string(from: selectedDay)
        let expectedLabel = "\(dayText) - \(dayText)"
        #expect(snapshot.summaryText.contains("日期范围：\(expectedLabel)"))
        #expect(snapshot.summaryText.contains("应服 3 次，已服用 2 次，忽略 1 次"))
        #expect(snapshot.summaryText.contains("23:59：范围内药品 忽略。"))
        let payload = VisitSummaryExportPayload(
            medications: snapshot.medications, tasks: snapshot.tasks, doseChanges: snapshot.doseChanges,
            riskCards: snapshot.riskCards, trendDashboard: snapshot.trendDashboard,
            healthSignals: snapshot.healthSignals, startDate: snapshot.startDate,
            endDateExclusive: snapshot.endDateExclusive, generatedAt: snapshot.generatedAt,
            exportSignature: snapshot.exportSignature
        )
        #expect(Set(payload.healthSignals.map(\.id)) == expectedSignals)
        #expect(payload.tasks.count == 3)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("visit-boundary-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let lifecycle = VisitSummaryPDFLifecycle(rootDirectory: root, expiryInterval: 3600, clock: Date.init)
        let url = try await VisitSummaryPDFExporter.export(payload: payload, lifecycle: lifecycle)
        let pdfText = try #require(PDFDocument(url: url)?.string)
        #expect(pdfText.contains(expectedLabel))
        #expect(!pdfText.contains(AppFormatters.day.string(from: nextDay) + " 期间计划"))
    }

    @Test @MainActor
    func emptyAndReversedExclusiveIntervalsAreRejected() throws {
        let fixture = try VisitSummaryDataFixture()
        for end in [fixture.rangeStart, fixture.rangeStart.addingTimeInterval(-1)] {
            let outcome = VisitSummaryDataCommand(modelContext: fixture.context).load(
                startDate: fixture.rangeStart, endDateExclusive: end
            )
            guard case .rejected = outcome else {
                Issue.record("Expected an empty or reversed interval to be rejected")
                continue
            }
        }
    }
}

@MainActor
private struct VisitSummaryDataFixture {
    let context: ModelContext
    let rangeStart = Date(timeIntervalSince1970: 1_800_000_000)
    let rangeEndExclusive = Date(timeIntervalSince1970: 1_800_086_400)
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
            now: rangeEndExclusive
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
