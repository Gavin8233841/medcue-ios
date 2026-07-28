import Foundation
import MedicationAdherenceCore
import SwiftData
import Testing
@testable import MedicationAdherenceApp

@Suite(.serialized)
struct MedicationProfileCommandTests {
    @Test @MainActor
    func updatesProfileAndPreservesNonProfileFields() throws {
        let fixture = try MedicationProfileFixture()
        let photoData = Data([0x01, 0x02, 0x03])

        let outcome = MedicationProfileCommand(modelContext: fixture.context).update(
            MedicationProfileUpdate(
                medicationID: fixture.medication.id,
                displayName: "  对乙酰氨基酚  ",
                genericName: " acetaminophen ",
                strength: "500 mg",
                form: "片剂",
                kind: .overTheCounter,
                photoData: photoData,
                photoSymbolName: "cross.case.fill",
                colorTagRaw: "orange",
                boxNumber: " B2 ",
                notes: "可见备注\n内部备注"
            )
        )

        #expect(outcome == .committed(medicationID: fixture.medication.id))
        let verificationContext = ModelContext(fixture.container)
        let medication = try #require(verificationContext.fetch(FetchDescriptor<StoredMedication>()).first)
        #expect(medication.displayName == "对乙酰氨基酚")
        #expect(medication.genericName == "acetaminophen")
        #expect(medication.strength == "500 mg")
        #expect(medication.form == "片剂")
        #expect(medication.kindRaw == MedicationKind.overTheCounter.rawValue)
        #expect(medication.photoData == photoData)
        #expect(medication.photoSymbolName == "cross.case.fill")
        #expect(medication.colorTagRaw == "orange")
        #expect(medication.boxNumber == "B2")
        #expect(medication.notes == "可见备注\n内部备注")
        #expect(medication.inputSourceRaw == MedicationInputSource.manual.rawValue)
        #expect(medication.lifecycleStatus == .interrupted)
        #expect(medication.isDemoContent)
        #expect(medication.createdAt == fixture.createdAt)
    }

    @Test @MainActor
    func invalidDisplayNameIsRejectedWithoutMutation() throws {
        let fixture = try MedicationProfileFixture()

        let outcome = MedicationProfileCommand(modelContext: fixture.context).update(
            fixture.update(displayName: "x")
        )

        #expect(outcome == .rejected(.invalidDisplayName))
        #expect(fixture.medication.displayName == "原始药品")
        #expect(!fixture.context.hasChanges)
    }

    @Test @MainActor
    func missingMedicationIsRejectedWithoutWriting() throws {
        let fixture = try MedicationProfileFixture()
        var update = fixture.update()
        update = MedicationProfileUpdate(
            medicationID: UUID(),
            displayName: update.displayName,
            genericName: update.genericName,
            strength: update.strength,
            form: update.form,
            kind: update.kind,
            photoData: update.photoData,
            photoSymbolName: update.photoSymbolName,
            colorTagRaw: update.colorTagRaw,
            boxNumber: update.boxNumber,
            notes: update.notes
        )

        let outcome = MedicationProfileCommand(modelContext: fixture.context).update(update)

        #expect(outcome == .rejected(.medicationNotFound))
        #expect(fixture.medication.displayName == "原始药品")
        #expect(!fixture.context.hasChanges)
    }

    @Test @MainActor
    func saveFailureRestoresEveryProfileField() throws {
        let fixture = try MedicationProfileFixture()
        let command = MedicationProfileCommand(modelContext: fixture.context) { _ in
            throw SyntheticProfileSaveError.unavailable
        }

        let outcome = command.update(fixture.update())

        #expect(outcome == .saveFailed)
        #expect(fixture.medication.displayName == "原始药品")
        #expect(fixture.medication.genericName == "原始通用名")
        #expect(fixture.medication.strength == "10 mg")
        #expect(fixture.medication.form == "胶囊")
        #expect(fixture.medication.kindRaw == MedicationKind.prescription.rawValue)
        #expect(fixture.medication.photoData == Data([0x09]))
        #expect(fixture.medication.photoSymbolName == "pills.fill")
        #expect(fixture.medication.colorTagRaw == "blue")
        #expect(fixture.medication.boxNumber == "A1")
        #expect(fixture.medication.notes == "原始备注")
        #expect(!fixture.context.hasChanges)
    }

    @Test @MainActor
    func photoUpdateChangesOnlyTheRequestedMedication() throws {
        let fixture = try MedicationProfileFixture()
        let otherMedication = StoredMedication(
            displayName: "其他药品",
            kind: .overTheCounter,
            inputSource: .manual,
            photoData: Data([0x88])
        )
        fixture.context.insert(otherMedication)
        try fixture.context.save()
        let newPhoto = Data([0x01, 0x02])

        let outcome = MedicationProfileCommand(modelContext: fixture.context).updatePhoto(
            MedicationPhotoUpdate(medicationID: fixture.medication.id, photoData: newPhoto)
        )

        #expect(outcome == .committed(medicationID: fixture.medication.id))
        #expect(fixture.medication.photoData == newPhoto)
        #expect(otherMedication.photoData == Data([0x88]))
        #expect(fixture.medication.displayName == "原始药品")
        #expect(!fixture.context.hasChanges)
    }

    @Test @MainActor
    func photoSaveFailureRestoresPreviousPhoto() throws {
        let fixture = try MedicationProfileFixture()
        let command = MedicationProfileCommand(modelContext: fixture.context) { _ in
            throw SyntheticProfileSaveError.unavailable
        }

        let outcome = command.updatePhoto(
            MedicationPhotoUpdate(medicationID: fixture.medication.id, photoData: Data([0x01]))
        )

        #expect(outcome == .saveFailed)
        #expect(fixture.medication.photoData == Data([0x09]))
        #expect(!fixture.context.hasChanges)
    }
}

@MainActor
private struct MedicationProfileFixture {
    let container: ModelContainer
    let context: ModelContext
    let medication: StoredMedication
    let createdAt = Date(timeIntervalSince1970: 1_700_000_000)

    init() throws {
        container = try MedicationAdherenceModelContainer.make(isStoredInMemoryOnly: true)
        context = ModelContext(container)
        context.autosaveEnabled = false
        medication = StoredMedication(
            displayName: "原始药品",
            genericName: "原始通用名",
            kind: .prescription,
            form: "胶囊",
            strength: "10 mg",
            inputSource: .manual,
            photoSymbolName: "pills.fill",
            photoData: Data([0x09]),
            colorTagRaw: "blue",
            boxNumber: "A1",
            notes: "原始备注",
            lifecycleStatus: .interrupted,
            isDemoContent: true,
            createdAt: createdAt
        )
        context.insert(medication)
        try context.save()
    }

    func update(displayName: String = "更新药品") -> MedicationProfileUpdate {
        MedicationProfileUpdate(
            medicationID: medication.id,
            displayName: displayName,
            genericName: "更新通用名",
            strength: "20 mg",
            form: "片剂",
            kind: .overTheCounter,
            photoData: Data([0x01]),
            photoSymbolName: "cross.case.fill",
            colorTagRaw: "green",
            boxNumber: "B2",
            notes: "更新备注"
        )
    }
}

private enum SyntheticProfileSaveError: Error {
    case unavailable
}
