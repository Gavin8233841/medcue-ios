import Foundation
import MedicationAdherenceCore
import Testing
import UIKit
@testable import MedicationAdherenceApp

@Suite(.serialized)
struct ElderModeTests {
    @Test
    func elderSuccessUndoEndsAtPersistedDeadline() {
        let taskID = UUID()
        let deadline = Date(timeIntervalSince1970: 600)
        let feedback = ElderDoseSuccessState(
            message: "已服用",
            taskID: taskID,
            undoExpiresAt: deadline
        )

        #expect(feedback.canUndo(at: deadline))
        #expect(!feedback.canUndo(at: deadline.addingTimeInterval(0.001)))
        #expect(!ElderDoseSuccessState(message: "提醒已设置", taskID: nil, undoExpiresAt: nil).canUndo(at: deadline))
    }

    @Test
    func elderActionsKeepLargeDistinctTouchTargets() {
        #expect(ElderDoseActionProminence.tertiary.minimumHeight >= 60)
        #expect(ElderDoseActionProminence.secondary.minimumHeight > ElderDoseActionProminence.tertiary.minimumHeight)
        #expect(ElderDoseActionProminence.primary.minimumHeight > ElderDoseActionProminence.secondary.minimumHeight)
    }

    @Test @MainActor
    func doseActionStateRejectsDuplicateInFlightActions() {
        let state = TodayDoseInteractionState()

        #expect(state.beginDoseAction(for: "dose-1"))
        #expect(!state.beginDoseAction(for: "dose-1"))
        #expect(state.inFlightDoseKeys == ["dose-1"])

        state.finishDoseAction(for: "dose-1")

        #expect(state.inFlightDoseKeys.isEmpty)
        #expect(state.beginDoseAction(for: "dose-1"))
    }

    @Test
    func elderPhotoWidthsStayInsideTheirActualContainer() {
        let containerWidths: [CGFloat] = [0, 40, 72, 240, 320, 375, 390, 402, 768]
        for width in containerWidths {
            let regularContentWidth = max(0, width - 32 - 2 * ElderTaskLayoutMetrics.regularCardPadding)
            let accessibilityContentWidth = max(0, width - 32 - 2 * ElderTaskLayoutMetrics.accessibilityCardPadding)
            let regularPhotoWidth = ElderTaskLayoutMetrics.regularPhotoWidth(for: width)
            let accessibilityPhotoWidth = ElderTaskLayoutMetrics.accessibilityPhotoWidth(for: width)

            #expect(regularPhotoWidth >= 0 && regularPhotoWidth <= regularContentWidth)
            #expect(accessibilityPhotoWidth >= 0 && accessibilityPhotoWidth <= accessibilityContentWidth)
        }
        #expect(ElderTaskLayoutMetrics.regularPhotoWidth(for: 0) == 0)
        #expect(ElderTaskLayoutMetrics.accessibilityPhotoWidth(for: 0) == 0)
    }

    @Test
    func elderPhotoDecoderRejectsEmptyAndInvalidImages() {
        #expect(ElderMedicationPhotoDecoder.thumbnail(from: Data(), maximumPixelSize: 120) == nil)
        #expect(ElderMedicationPhotoDecoder.thumbnail(from: Data("invalid image".utf8), maximumPixelSize: 120) == nil)
    }

    @Test @MainActor
    func elderPhotoDecoderPreservesPortraitAndLandscapeProportions() throws {
        for size in [CGSize(width: 480, height: 320), CGSize(width: 320, height: 480)] {
            let image = try #require(ElderMedicationPhotoDecoder.thumbnail(
                from: geometricImageData(size: size),
                maximumPixelSize: 120
            ))

            #expect(max(image.width, image.height) == 120)
            #expect(min(image.width, image.height) == 80)
            #expect(CGFloat(image.width) / CGFloat(image.height) == size.width / size.height)
        }
    }

    @Test @MainActor
    func elderPhotoDecoderBoundsItsDecodedPixelDimensions() throws {
        let data = geometricImageData(size: CGSize(width: 2200, height: 1100))
        let boundedImage = try #require(ElderMedicationPhotoDecoder.thumbnail(
            from: data,
            maximumPixelSize: Int.max
        ))
        let smallestImage = try #require(ElderMedicationPhotoDecoder.thumbnail(
            from: data,
            maximumPixelSize: 0
        ))

        #expect(boundedImage.width == 2048)
        #expect(boundedImage.height == 1024)
        #expect(max(smallestImage.width, smallestImage.height) == 1)
    }

    @Test
    func elderEmptyStateKeepsNoTasksAndCompletedDistinct() {
        #expect(ElderTodayEmptyState.noTasks.title == "今天没有用药任务")
        #expect(ElderTodayEmptyState.complete.title == "今日用药已完成")
        #expect(ElderTodayEmptyState.noOpenTasks.title == "没有待处理用药")
        #expect(ElderTodayEmptyState.noTasks != ElderTodayEmptyState.complete)
    }

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

    @Test
    func helpContactUsesTheOwnerApprovedUserDefaultsKey() throws {
        let suiteName = "medcue.elder-help-tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = UserDefaultsElderHelpContactStore(defaults: defaults)
        let phoneNumber = try ElderHelpPhoneNumber(validating: "+86 (138) 0000-0000")

        #expect(try store.load() == nil)
        try store.save(phoneNumber)
        #expect(defaults.string(forKey: UserDefaultsElderHelpContactStore.storageKey) == "+8613800000000")
        #expect(try store.load() == phoneNumber)
        try store.remove()
        #expect(try store.load() == nil)
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

    @Test @MainActor
    func elderProjectionClassifiesEmptyStatesFromPersistedTasks() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let medication = StoredMedication(displayName: "测试药品", kind: .prescription, inputSource: .manual)
        let store = TodayDoseProjectionStore()

        let noTasks = store.projection(
            for: TodayDoseProjectionInput(tasks: [], medications: [medication], now: now, calendar: utcCalendar)
        )
        #expect(noTasks.elderSnapshot(medications: [medication], now: now).emptyState == .noTasks)

        let takenTask = makeTask(medicationID: medication.id, dueAt: now, status: .taken)
        let completed = store.projection(
            for: TodayDoseProjectionInput(tasks: [takenTask], medications: [medication], now: now, calendar: utcCalendar)
        )
        #expect(completed.elderSnapshot(medications: [medication], now: now).emptyState == .complete)

        let skippedTask = makeTask(medicationID: medication.id, dueAt: now, status: .skipped)
        let skipped = store.projection(
            for: TodayDoseProjectionInput(tasks: [skippedTask], medications: [medication], now: now, calendar: utcCalendar)
        )
        #expect(skipped.elderSnapshot(medications: [medication], now: now).emptyState == .noOpenTasks)
    }

    @MainActor
    private func geometricImageData(size: CGSize) -> Data {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).pngData { context in
            UIColor.black.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
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
