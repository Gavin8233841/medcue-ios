import Foundation
import MedicationAdherenceCore
import Testing
@testable import MedicationAdherenceApp

@Suite(.serialized)
struct ElderModeTests {
    @Test
    func helpPhoneNumberNormalizesOnlySupportedDisplaySeparators() throws {
        let phoneNumber = try ElderHelpPhoneNumber(validating: "+86 (138) 0000-0000")

        #expect(phoneNumber.storageValue == "+8613800000000")
        #expect(phoneNumber.callURL?.absoluteString == "tel:+8613800000000")
    }

    @Test
    func helpPhoneNumberRejectsEmptyLettersAndMisplacedPlus() {
        #expect(throws: ElderHelpContactError.invalidPhoneNumber) {
            try ElderHelpPhoneNumber(validating: "   ")
        }
        #expect(throws: ElderHelpContactError.invalidPhoneNumber) {
            try ElderHelpPhoneNumber(validating: "138 HELP")
        }
        #expect(throws: ElderHelpContactError.invalidPhoneNumber) {
            try ElderHelpPhoneNumber(validating: "138+0000")
        }
    }

    @Test @MainActor
    func helpRequestWithoutNumberRequiresSettingsAndNeverOpensPhone() {
        let store = ElderHelpContactStoreFake(phoneNumber: nil)
        let opener = ElderHelpOpenerFake(result: true)
        var outcome: ElderHelpRequestOutcome?

        ElderHelpRequestCoordinator(contactStore: store, opener: opener).request {
            outcome = $0
        }

        #expect(outcome == .requiresSettings)
        #expect(opener.openCount == 0)
    }

    @Test @MainActor
    func helpRequestReportsOnlyWhetherSystemAcceptedThePhoneConfirmation() throws {
        let phoneNumber = try ElderHelpPhoneNumber(validating: "13800000000")
        let store = ElderHelpContactStoreFake(phoneNumber: phoneNumber)
        let opener = ElderHelpOpenerFake(result: true)
        var outcome: ElderHelpRequestOutcome?

        ElderHelpRequestCoordinator(contactStore: store, opener: opener).request {
            outcome = $0
        }

        #expect(outcome == .openedConfirmation)
        #expect(opener.openCount == 1)
        #expect(opener.lastPhoneNumber == phoneNumber)
    }

    @Test @MainActor
    func helpRequestFailureDoesNotClaimThatAHelpCallStarted() throws {
        let phoneNumber = try ElderHelpPhoneNumber(validating: "13800000000")
        let store = ElderHelpContactStoreFake(phoneNumber: phoneNumber)
        let opener = ElderHelpOpenerFake(result: false)
        var outcome: ElderHelpRequestOutcome?

        ElderHelpRequestCoordinator(contactStore: store, opener: opener).request {
            outcome = $0
        }

        #expect(outcome == .failed)
        #expect(opener.openCount == 1)
    }

    @Test
    func elderStatusKeepsDueAndExpiredTasksUnconfirmed() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let medicationID = UUID()
        let futurePending = makeTask(medicationID: medicationID, dueAt: now.addingTimeInterval(60), status: .pending)
        let duePending = makeTask(medicationID: medicationID, dueAt: now, status: .pending)
        let futureDelayed = makeTask(medicationID: medicationID, dueAt: now.addingTimeInterval(60), status: .delayed)
        let dueDelayed = makeTask(medicationID: medicationID, dueAt: now, status: .delayed)

        #expect(ElderDoseDisplayStatus.resolve(for: futurePending, now: now) == .pendingBeforeDue)
        #expect(ElderDoseDisplayStatus.resolve(for: duePending, now: now) == .pendingAtOrAfterDue)
        #expect(ElderDoseDisplayStatus.resolve(for: futureDelayed, now: now) == .delayedBeforeDue)
        #expect(ElderDoseDisplayStatus.resolve(for: dueDelayed, now: now) == .delayedAtOrAfterDue)
        #expect(ElderDoseDisplayStatus.resolve(for: dueDelayed, now: now)?.displayName == "仍未确认")
    }

    @Test @MainActor
    func elderProjectionUsesOnlyFirstSortedOpenTaskAndCountsTheRest() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let firstMedication = StoredMedication(displayName: "第一项", kind: .prescription, inputSource: .manual)
        let secondMedication = StoredMedication(displayName: "第二项", kind: .prescription, inputSource: .manual)
        let firstTask = makeTask(
            medicationID: firstMedication.id,
            dueAt: now.addingTimeInterval(-300),
            status: .pending
        )
        let secondTask = makeTask(
            medicationID: secondMedication.id,
            dueAt: now.addingTimeInterval(300),
            status: .pending
        )

        let projection = TodayDoseProjectionStore().projection(
            for: TodayDoseProjectionInput(
                tasks: [secondTask, firstTask],
                medications: [secondMedication, firstMedication],
                now: now,
                calendar: utcCalendar
            )
        )
        let elder = projection.elderSnapshot(
            medications: [secondMedication, firstMedication],
            now: now
        )

        #expect(elder.currentTask?.id == firstTask.id)
        #expect(elder.currentMedication?.id == firstMedication.id)
        #expect(elder.currentStatus == .pendingAtOrAfterDue)
        #expect(elder.remainingOpenTaskCount == 1)
    }

    @Test @MainActor
    func elderProjectionDoesNotExposeHandledTaskKeptOnlyForAnimation() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let medication = StoredMedication(displayName: "测试药品", kind: .prescription, inputSource: .manual)
        let handledTask = makeTask(
            medicationID: medication.id,
            dueAt: now.addingTimeInterval(-600),
            status: .taken
        )
        let openTask = makeTask(
            medicationID: medication.id,
            dueAt: now.addingTimeInterval(600),
            status: .pending
        )
        let handledKey = DoseLogicalGroup.key(for: handledTask)

        let projection = TodayDoseProjectionStore().projection(
            for: TodayDoseProjectionInput(
                tasks: [handledTask, openTask],
                medications: [medication],
                now: now,
                calendar: utcCalendar,
                transition: TodayDoseProjectionTransition(
                    pendingDoseFeedback: nil,
                    closingOpenDoseKeys: [handledKey]
                )
            )
        )
        let elder = projection.elderSnapshot(medications: [medication], now: now)

        #expect(elder.currentTask?.id == openTask.id)
        #expect(elder.remainingOpenTaskCount == 0)
    }

    private var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func makeTask(
        medicationID: UUID,
        dueAt: Date,
        status: StoredDoseStatus
    ) -> StoredDoseTask {
        StoredDoseTask(
            medicationID: medicationID,
            dueAt: dueAt,
            doseValue: 1,
            doseUnit: "片",
            status: status,
            recordedAt: status == .pending || status == .delayed ? nil : dueAt
        )
    }
}

private final class ElderHelpContactStoreFake: ElderHelpContactStoring {
    private var phoneNumber: ElderHelpPhoneNumber?

    init(phoneNumber: ElderHelpPhoneNumber?) {
        self.phoneNumber = phoneNumber
    }

    func load() throws -> ElderHelpPhoneNumber? {
        phoneNumber
    }

    func save(_ phoneNumber: ElderHelpPhoneNumber) throws {
        self.phoneNumber = phoneNumber
    }

    func remove() throws {
        phoneNumber = nil
    }
}

@MainActor
private final class ElderHelpOpenerFake: ElderHelpOpening {
    private let result: Bool
    private(set) var openCount = 0
    private(set) var lastPhoneNumber: ElderHelpPhoneNumber?

    init(result: Bool) {
        self.result = result
    }

    func openConfirmation(
        for phoneNumber: ElderHelpPhoneNumber,
        completion: @escaping @MainActor (Bool) -> Void
    ) {
        openCount += 1
        lastPhoneNumber = phoneNumber
        completion(result)
    }
}
