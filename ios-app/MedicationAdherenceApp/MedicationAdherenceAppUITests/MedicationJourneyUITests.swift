import XCTest

@MainActor
final class MedicationJourneyUITests: XCTestCase {
    private enum AccessibilityID {
        static let tabMedications = "tab.medications"
        static let tabAssistant = "tab.assistant"
        static let tabToday = "tab.today"
        static let tabRecords = "tab.records"
        static let tabProfile = "tab.profile"
        static let medicationAdd = "medication.add"
        static let medicationAddManual = "medication.add.manual"
        static let medicationGroupActive = "medication.group.active"
        static let medicationCellPrefix = "medication.cell."
        static let medicationEditSave = "medication.edit.save"
        static let medicationEditDisplayName = "medication.edit.displayName"
        static let medicationEditStrength = "medication.edit.strength"
        static let medicationPlanSave = "medication.plan.save"
        static let medicationDetailAddPlan = "medication.detail.addPlan"
        static let todayDoseTaskPrefix = "today.doseTask."
        static let todayDoseMarkTaken = "today.dose.markTaken"
        static let todayDoseUndo = "today.dose.undo"
        static let recordsHistory = "records.history"
    }
    private var app: XCUIApplication!
    private let medicationName = "阿司匹林"

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
    }

    func testCreateMedicationPlanDoseCorrectionJourney() {
        app.launchArguments = [
            "-AppPersistenceCommitter.failureMessage", "",
            "-DoseActionPersistence.failureMessage", "",
            "-hasCompletedFirstLaunchSetup", "YES",
            "-UITestDeterministicMode", "YES"
        ]
        app.launch()

        // Create a medication through the same option sheet as the product flow.
        tapTab(AccessibilityID.tabMedications)
        let addMedicationButton = app.buttons[AccessibilityID.medicationAdd]
        XCTAssertTrue(addMedicationButton.waitForExistence(timeout: 10))
        addMedicationButton.tap()

        let manualAddButton = app.buttons[AccessibilityID.medicationAddManual]
        XCTAssertTrue(manualAddButton.waitForExistence(timeout: 5))
        manualAddButton.tap()

        let displayNameField = app.textFields["药品名称"]
        XCTAssertTrue(displayNameField.waitForExistence(timeout: 5))
        displayNameField.tap()
        displayNameField.typeText(medicationName)

        let strengthField = app.textFields["例如 200 mg 或 10 ml"]
        XCTAssertTrue(strengthField.waitForExistence(timeout: 5))
        strengthField.tap()
        strengthField.typeText("100mg")

        let saveMedicationButton = app.buttons["保存"]
        XCTAssertTrue(saveMedicationButton.waitForExistence(timeout: 5))
        saveMedicationButton.tap()
        let confirmMedicationButton = app.buttons["已核对，保存"]
        XCTAssertTrue(confirmMedicationButton.waitForExistence(timeout: 5))
        confirmMedicationButton.tap()

        // The medication list is intentionally collapsed by default.
        let medicationGroup = app.buttons[AccessibilityID.medicationGroupActive]
        XCTAssertTrue(medicationGroup.waitForExistence(timeout: 10))
        medicationGroup.tap()
        let medicationCell = app.buttons[AccessibilityID.medicationCellPrefix + medicationName]
        XCTAssertTrue(medicationCell.waitForExistence(timeout: 5))
        medicationCell.tap()

        // AddMedicationView commits the medication and its default one-reminder
        // plan in one transaction; the generated task proves the plan persisted.
        XCTAssertTrue(app.staticTexts["疗程与提醒"].waitForExistence(timeout: 5))

        // Restart to exercise SwiftData persistence and task projection.
        app.terminate()
        app.launch()
        tapTab(AccessibilityID.tabToday)

        let doseTask = app.descendants(matching: .any).matching(
            identifier: AccessibilityID.todayDoseTaskPrefix + medicationName
        )
        let markTakenButton = app.buttons[AccessibilityID.todayDoseMarkTaken]
        XCTAssertTrue(markTakenButton.waitForExistence(timeout: 15))
        XCTAssertEqual(doseTask.count, 1)
        markTakenButton.tap()
        confirmEarlyDoseIfNeeded()

        // The handled section is collapsed after a transition; expand it for undo.
        let handledSummary = app.buttons["今日已处理"]
        XCTAssertTrue(handledSummary.waitForExistence(timeout: 10))
        handledSummary.tap()
        let undoButton = app.buttons[AccessibilityID.todayDoseUndo]
        XCTAssertTrue(undoButton.waitForExistence(timeout: 5))
        undoButton.tap()

        XCTAssertTrue(markTakenButton.waitForExistence(timeout: 10))
        markTakenButton.tap()
        confirmEarlyDoseIfNeeded()
        XCTAssertTrue(app.staticTexts["已服用"].waitForExistence(timeout: 10))

        // A second restart must retain the final taken state without duplicating tasks.
        app.terminate()
        app.launch()
        tapTab(AccessibilityID.tabToday)
        let finalHandledSummary = app.buttons["今日已处理"]
        XCTAssertTrue(finalHandledSummary.waitForExistence(timeout: 15))
        finalHandledSummary.tap()
        XCTAssertTrue(app.staticTexts["已服用"].waitForExistence(timeout: 10))
        let finalDoseTasks = app.descendants(matching: .any).matching(
            identifier: AccessibilityID.todayDoseTaskPrefix + medicationName
        )
        XCTAssertEqual(finalDoseTasks.count, 1)

        // Records exposes the committed history through its history destination.
        tapTab(AccessibilityID.tabRecords)
        let historyButton = app.descendants(matching: .any).matching(
            identifier: AccessibilityID.recordsHistory
        ).firstMatch
        XCTAssertTrue(historyButton.waitForExistence(timeout: 10))
        historyButton.tap()
        XCTAssertTrue(app.staticTexts[medicationName].waitForExistence(timeout: 10))
    }

    private func tapTab(_ identifier: String) {
        // SwiftUI exposes the tab item's identifier on the tab content rather
        // than on the tab-bar button in this simulator runtime. Keep the
        // navigation assertion stable by using the product's declared order,
        // then verify that the requested content identifier is present.
        let tabOrder = [
            AccessibilityID.tabToday,
            AccessibilityID.tabMedications,
            AccessibilityID.tabAssistant,
            AccessibilityID.tabRecords,
            AccessibilityID.tabProfile
        ]
        guard let tabIndex = tabOrder.firstIndex(of: identifier) else {
            XCTFail("Unknown tab identifier: \(identifier)")
            return
        }
        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 10))
        let tab = tabBar.buttons.element(boundBy: tabIndex)
        XCTAssertTrue(tab.waitForExistence(timeout: 10))
        tab.tap()
        XCTAssertTrue(
            app.descendants(matching: .any)[identifier].waitForExistence(timeout: 5),
            "Missing tab content identifier: \(identifier)"
        )
    }

    private func confirmEarlyDoseIfNeeded() {
        let confirmButton = app.buttons["确认已服用"]
        if confirmButton.waitForExistence(timeout: 3) {
            confirmButton.tap()
        }
    }
}
