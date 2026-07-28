import Foundation
import MedicationAdherenceCore
import Testing
@testable import MedicationAdherenceApp

struct MedicalAIContextBuilderTests {
    @Test @MainActor
    func todayQuestionIncludesOnlyTodaysLogicalDoses() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        let now = try #require(calendar.date(from: DateComponents(
            year: 2026,
            month: 7,
            day: 27,
            hour: 12
        )))
        let medication = StoredMedication(
            displayName: "测试药",
            kind: .prescription,
            inputSource: .manual
        )
        let plan = StoredMedicationPlan(
            medicationID: medication.id,
            doseValue: 1,
            doseUnit: "片",
            timingSummary: "每日一次",
            timeZonePolicy: .localClock,
            sourceNote: "测试"
        )
        let todayTask = StoredDoseTask(
            medicationID: medication.id,
            planID: plan.id,
            dueAt: now.addingTimeInterval(-3_600),
            doseValue: 1,
            doseUnit: "片"
        )
        let tomorrowTask = StoredDoseTask(
            medicationID: medication.id,
            planID: plan.id,
            dueAt: now.addingTimeInterval(86_400),
            doseValue: 1,
            doseUnit: "片"
        )

        let request = MedicalAIContextBuilder(
            medications: [medication],
            plans: [plan],
            tasks: [todayTask, tomorrowTask],
            riskCards: [],
            labels: []
        ).makeRequest(
            userMessage: "今天还有什么药没有服用？",
            consent: StoredAIConsent(),
            environmentInsights: [],
            localeIdentifier: "zh_CN",
            now: now,
            calendar: calendar
        )

        let snapshot = try #require(request.medicationSnapshots.first)
        #expect(request.medicationSnapshots.count == 1)
        #expect(snapshot.scheduledDoses.map(\.id) == [todayTask.id])
    }

    @Test @MainActor
    func requestOmitsEveryMedicationFieldOutsideGrantedScopes() throws {
        let medication = StoredMedication(
            displayName: "测试药",
            kind: .prescription,
            inputSource: .manual
        )
        let plan = StoredMedicationPlan(
            medicationID: medication.id,
            doseValue: 1,
            doseUnit: "片",
            timingSummary: "每日一次",
            timeZonePolicy: .localClock,
            sourceNote: "测试"
        )
        let task = StoredDoseTask(
            medicationID: medication.id,
            planID: plan.id,
            dueAt: Date(),
            doseValue: 1,
            doseUnit: "片",
            status: .taken,
            recordedAt: Date()
        )
        let risk = StoredRiskCard(
            id: "test-ai-context-risk",
            medicationID: medication.id,
            kindRaw: "labelRisk",
            displayPriority: 1,
            title: "测试风险",
            message: "测试风险正文",
            requiresProfessionalReview: true,
            safetyNote: "测试"
        )
        let label = StoredMedicationLabel(
            medicationID: medication.id,
            medicationName: medication.displayName,
            rawText: "【用法用量】测试说明书正文",
            sourceTitle: "测试说明书"
        )
        let consent = StoredAIConsent(
            sharesMedicationProfile: true,
            sharesMedicationPlans: false,
            sharesDoseEvents: false,
            sharesRiskCards: false,
            sharesDrugLabels: false
        )

        let request = MedicalAIContextBuilder(
            medications: [medication],
            plans: [plan],
            tasks: [task],
            riskCards: [risk],
            labels: [label]
        ).makeRequest(
            userMessage: "介绍我的药品",
            consent: consent,
            environmentInsights: [],
            localeIdentifier: "zh_CN"
        )

        let snapshot = try #require(request.medicationSnapshots.first)
        #expect(snapshot.medication.id == medication.id)
        #expect(snapshot.plans.isEmpty)
        #expect(snapshot.scheduledDoses.isEmpty)
        #expect(snapshot.doseEvents.isEmpty)
        #expect(snapshot.riskCards.isEmpty)
        #expect(snapshot.labelSummary == nil)
    }
}
