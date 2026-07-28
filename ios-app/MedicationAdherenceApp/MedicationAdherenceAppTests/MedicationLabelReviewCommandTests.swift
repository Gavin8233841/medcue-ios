import Foundation
import MedicationAdherenceCore
import SwiftData
import Testing
@testable import MedicationAdherenceApp

@Suite(.serialized)
struct MedicationLabelReviewCommandTests {
    @Test @MainActor
    func confirmedLabelAndDerivedRisksCommitTogether() throws {
        let fixture = try MedicationLabelReviewFixture()
        let input = fixture.input(rawText: Self.riskLabelText)

        let outcome = MedicationLabelReviewCommand(modelContext: fixture.context).save(input)

        guard case let .committed(commit) = outcome else {
            Issue.record("Expected label review to commit")
            return
        }
        let labels = try fixture.labels()
        #expect(labels.count == 1)
        #expect(labels[0].rawText == Self.riskLabelText)
        #expect(labels[0].sourceTitle == "用户确认说明书")
        #expect(labels[0].lastRiskReviewAt != nil)
        #expect(!commit.riskResult.createdIDs.isEmpty)
        #expect(try fixture.risks().allSatisfy { $0.medicationID == fixture.medication.id })
        #expect(!fixture.context.hasChanges)
    }

    @Test @MainActor
    func saveFailureRestoresExistingLabelAndLeavesNoDerivedRisks() throws {
        let fixture = try MedicationLabelReviewFixture(existingLabelText: "原说明书")

        let outcome = MedicationLabelReviewCommand(
            modelContext: fixture.context,
            saveOperation: { _ in throw SyntheticMedicationLabelSaveError.unavailable }
        ).save(fixture.input(rawText: Self.riskLabelText))

        guard case .saveFailed = outcome else {
            Issue.record("Expected label review save failure")
            return
        }
        let label = try #require(try fixture.labels().first)
        #expect(label.rawText == "原说明书")
        #expect(label.sourceTitle == "原来源")
        #expect(label.averageOCRConfidence == 0.5)
        #expect(label.lastRiskReviewAt == nil)
        #expect(try fixture.risks().isEmpty)
        #expect(!fixture.context.hasChanges)
    }

    @Test @MainActor
    func blankLabelIsRejectedWithoutWriting() throws {
        let fixture = try MedicationLabelReviewFixture()

        let outcome = MedicationLabelReviewCommand(modelContext: fixture.context).save(
            fixture.input(rawText: " \n ")
        )

        guard case .rejected(.emptyLabel) = outcome else {
            Issue.record("Expected empty label rejection")
            return
        }
        #expect(try fixture.labels().isEmpty)
        #expect(try fixture.risks().isEmpty)
        #expect(!fixture.context.hasChanges)
    }

    private static let riskLabelText = "【禁忌】对本品及其成分过敏者禁用。【药物相互作用】与酮康唑、红霉素、西咪替丁等合用时应咨询医生或药师。"
}

private enum SyntheticMedicationLabelSaveError: Error {
    case unavailable
}

@MainActor
private struct MedicationLabelReviewFixture {
    let context: ModelContext
    let medication: StoredMedication
    let now = Date(timeIntervalSince1970: 1_785_030_000)

    init(existingLabelText: String? = nil) throws {
        let container = try ModelContainer(
            for: StoredMedication.self,
            StoredMedicationLabel.self,
            StoredRiskCard.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        context = ModelContext(container)
        medication = StoredMedication(
            displayName: "氯雷他定片",
            kind: .overTheCounter,
            inputSource: .manual,
            createdAt: now
        )
        context.insert(medication)
        if let existingLabelText {
            context.insert(StoredMedicationLabel(
                medicationID: medication.id,
                medicationName: medication.displayName,
                rawText: existingLabelText,
                sourceTitle: "原来源",
                averageOCRConfidence: 0.5,
                importedAt: now.addingTimeInterval(-100)
            ))
        }
        try context.save()
    }

    func input(rawText: String) -> MedicationLabelReviewInput {
        MedicationLabelReviewInput(
            medicationID: medication.id,
            rawText: rawText,
            sourceTitle: "本地保存说明书摘要",
            averageOCRConfidence: 0.9,
            reviewedAt: now
        )
    }

    func labels() throws -> [StoredMedicationLabel] {
        let medicationID = medication.id
        return try context.fetch(FetchDescriptor<StoredMedicationLabel>(
            predicate: #Predicate { $0.medicationID == medicationID }
        ))
    }

    func risks() throws -> [StoredRiskCard] {
        let medicationID = medication.id
        return try context.fetch(FetchDescriptor<StoredRiskCard>(
            predicate: #Predicate { $0.medicationID == medicationID }
        ))
    }
}
