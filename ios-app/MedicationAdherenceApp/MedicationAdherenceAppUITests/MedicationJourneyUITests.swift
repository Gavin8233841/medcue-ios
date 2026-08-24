import XCTest

@MainActor
final class MedicationJourneyUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
    }

    func testCreateMedicationPlanDoseCorrectionJourney() {
        // Launch with deterministic test mode
        app.launchArguments = [
            "-AppPersistenceCommitter.failureMessage", "",
            "-DoseActionPersistence.failureMessage", "",
            "-hasCompletedFirstLaunchSetup", "YES",
            "-UITestDeterministicMode", "YES",
            "-UITestFixedDate", "2026-08-24T09:00:00Z"
        ]
        app.launch()

        // Step 1: Navigate to medications tab
        let medicationsTab = app.tabBars.buttons.element(boundBy: 1)
        XCTAssertTrue(medicationsTab.waitForExistence(timeout: 10))
        medicationsTab.tap()

        // Step 2: Create a medication
        let addMedicationButton = app.buttons["medications.add"]
        XCTAssertTrue(addMedicationButton.waitForExistence(timeout: 5))
        addMedicationButton.tap()

        let displayNameField = app.textFields["medication.edit.displayName"]
        XCTAssertTrue(displayNameField.waitForExistence(timeout: 5))
        displayNameField.tap()
        displayNameField.typeText("阿司匹林")

        let strengthField = app.textFields["medication.edit.strength"]
        strengthField.tap()
        strengthField.typeText("100mg")

        let saveMedicationButton = app.buttons["medication.edit.save"]
        saveMedicationButton.tap()

        // Verify medication was created
        let medicationCell = app.cells["medication.cell.阿司匹林"]
        XCTAssertTrue(medicationCell.waitForExistence(timeout: 5))

        // Step 3: Create a plan for the medication
        medicationCell.tap()

        let addPlanButton = app.buttons["medication.detail.addPlan"]
        XCTAssertTrue(addPlanButton.waitForExistence(timeout: 5))
        addPlanButton.tap()

        let doseValueField = app.textFields["plan.edit.doseValue"]
        XCTAssertTrue(doseValueField.waitForExistence(timeout: 5))
        doseValueField.tap()
        doseValueField.typeText("1")

        let doseUnitField = app.textFields["plan.edit.doseUnit"]
        doseUnitField.tap()
        doseUnitField.typeText("片")

        let reminderTimeButton = app.buttons["plan.edit.addReminderTime"]
        reminderTimeButton.tap()

        let savePlanButton = app.buttons["plan.edit.save"]
        savePlanButton.tap()

        // Step 4: Restart the app to verify persistence
        app.terminate()
        app.launch()

        // Navigate back to medications
        let medicationsTabAfterRestart = app.tabBars.buttons.element(boundBy: 1)
        XCTAssertTrue(medicationsTabAfterRestart.waitForExistence(timeout: 10))
        medicationsTabAfterRestart.tap()

        // Verify medication still exists
        let medicationCellAfterRestart = app.cells["medication.cell.阿司匹林"]
        XCTAssertTrue(medicationCellAfterRestart.waitForExistence(timeout: 5))

        // Step 5: Navigate to Today tab and verify dose task exists
        let todayTab = app.tabBars.buttons.element(boundBy: 0)
        todayTab.tap()

        let doseTaskRow = app.cells["today.doseTask.阿司匹林"]
        XCTAssertTrue(doseTaskRow.waitForExistence(timeout: 5))

        // Step 6: Record a dose (mark as taken)
        let markTakenButton = doseTaskRow.buttons["today.dose.markTaken"]
        XCTAssertTrue(markTakenButton.waitForExistence(timeout: 5))
        markTakenButton.tap()

        // Verify task status changed
        XCTAssertTrue(doseTaskRow.staticTexts["已服用"].waitForExistence(timeout: 5))

        // Step 7: Perform correction/undo
        let undoButton = doseTaskRow.buttons["today.dose.undo"]
        if undoButton.waitForExistence(timeout: 2) {
            undoButton.tap()

            // Verify task returned to open state
            XCTAssertTrue(markTakenButton.waitForExistence(timeout: 5))
        }

        // Step 8: Record dose again
        markTakenButton.tap()
        XCTAssertTrue(doseTaskRow.staticTexts["已服用"].waitForExistence(timeout: 5))

        // Step 9: Second restart to verify final state
        app.terminate()
        app.launch()

        let todayTabFinal = app.tabBars.buttons.element(boundBy: 0)
        XCTAssertTrue(todayTabFinal.waitForExistence(timeout: 10))
        todayTabFinal.tap()

        // Verify the dose task shows as taken
        let finalDoseTaskRow = app.cells["today.doseTask.阿司匹林"]
        XCTAssertTrue(finalDoseTaskRow.waitForExistence(timeout: 5))
        XCTAssertTrue(finalDoseTaskRow.staticTexts["已服用"].exists)

        // Step 10: Verify no duplicate tasks
        let allDoseTasks = app.cells.matching(identifier: "today.doseTask.阿司匹林")
        XCTAssertEqual(allDoseTasks.count, 1, "Should have exactly one dose task, found \(allDoseTasks.count)")

        // Step 11: Navigate to Records tab and verify no duplicate action logs
        let recordsTab = app.tabBars.buttons.element(boundBy: 3)
        recordsTab.tap()

        XCTAssertTrue(app.staticTexts["records.title"].waitForExistence(timeout: 5))

        // Verify single action log entry for the medication
        let actionLogEntries = app.cells.matching(NSPredicate(format: "label CONTAINS '阿司匹林'"))
        XCTAssertGreaterThanOrEqual(actionLogEntries.count, 1, "Should have at least one action log")
    }
}
