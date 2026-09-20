import CoreGraphics
import XCTest

@MainActor
final class MedicationAdherenceAppUITests: XCTestCase {
    private let clearedPersistenceFailureArguments = [
        "-AppPersistenceCommitter.failureMessage", "",
        "-DoseActionPersistence.failureMessage", ""
    ]

    func testPrimaryTabsAreReachable() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = clearedPersistenceFailureArguments + [
            "-hasCompletedFirstLaunchSetup", "YES"
        ]
        app.launch()

        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 10))

        let identifiers = [
            "tab.today",
            "tab.medications",
            "tab.assistant",
            "tab.records",
            "tab.profile"
        ]
        XCTAssertEqual(tabBar.buttons.count, identifiers.count)
        for (index, identifier) in identifiers.enumerated() {
            let tab = tabBar.buttons.element(boundBy: index)
            XCTAssertTrue(tab.waitForExistence(timeout: 5), "Missing tab at index: \(index)")
            tab.tap()
            XCTAssertTrue(tab.isSelected, "Tab did not become selected: \(identifier)")
            XCTAssertTrue(
                app.descendants(matching: .any)[identifier].waitForExistence(timeout: 5),
                "Missing content identifier: \(identifier)"
            )
            if identifier == "tab.assistant" {
                dismissAssistantGatesIfPresented(in: app)
            }
        }
    }

    private func dismissAssistantGatesIfPresented(in app: XCUIApplication) {
        let noticeAcceptButton = app.buttons["assistant.thirdPartyNotice.accept"]
        if noticeAcceptButton.waitForExistence(timeout: 5) {
            noticeAcceptButton.tap()
            XCTAssertTrue(
                noticeAcceptButton.waitForNonExistence(timeout: 5),
                "Third-party notice did not dismiss"
            )
        }

        let consentCancelButton = app.buttons["assistant.consent.cancel"]
        if consentCancelButton.waitForExistence(timeout: 5) {
            consentCancelButton.tap()
            XCTAssertTrue(
                consentCancelButton.waitForNonExistence(timeout: 5),
                "AI consent sheet did not dismiss"
            )
        }
    }

    func testFirstLaunchOffersProgressAndSkipActions() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = clearedPersistenceFailureArguments + ["-showFirstLaunch"]
        app.launch()

        let nextButton = app.buttons["firstLaunch.next"]
        let skipButton = app.buttons["firstLaunch.skip"]
        XCTAssertTrue(nextButton.waitForExistence(timeout: 10))
        XCTAssertTrue(skipButton.waitForExistence(timeout: 5))
        XCTAssertFalse(app.alerts["更改未能保存"].exists)

        nextButton.tap()
        XCTAssertTrue(nextButton.waitForExistence(timeout: 5))
        XCTAssertTrue(skipButton.exists)
    }

    func testMedicationAndRiskSearchFlows() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = clearedPersistenceFailureArguments + [
            "-hasCompletedFirstLaunchSetup", "YES",
            "--seed-demo-data"
        ]
        app.launch()

        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 10))
        tabBar.buttons.element(boundBy: 1).tap()

        let medicationSearch = app.searchFields.firstMatch
        XCTAssertTrue(medicationSearch.waitForExistence(timeout: 10))
        XCTAssertFalse(medicationSearch.label.isEmpty)
        medicationSearch.tap()
        medicationSearch.typeText("Ibuprofen")

        let medicationResult = app.staticTexts["布洛芬"].firstMatch
        XCTAssertTrue(medicationResult.waitForExistence(timeout: 10))
        medicationResult.tap()
        XCTAssertTrue(app.navigationBars["布洛芬"].waitForExistence(timeout: 5))
        app.navigationBars["布洛芬"].buttons.element(boundBy: 0).tap()

        let restoredMedicationSearch = app.searchFields.firstMatch
        XCTAssertTrue(restoredMedicationSearch.waitForExistence(timeout: 5))
        clearSearchField(restoredMedicationSearch)
        restoredMedicationSearch.tap()
        restoredMedicationSearch.typeText("synthetic-no-result-query")
        XCTAssertTrue(
            app.staticTexts.matching(
                NSPredicate(format: "label CONTAINS %@", "synthetic-no-result-query")
            ).firstMatch.waitForExistence(timeout: 5)
        )
        clearSearchField(restoredMedicationSearch)

        app.swipeDown()
        app.swipeDown()
        let riskReview = app.staticTexts["风险复核"].firstMatch
        XCTAssertTrue(riskReview.waitForExistence(timeout: 5))
        XCTAssertTrue(riskReview.isHittable)
        riskReview.tap()

        let riskSearch = app.searchFields.firstMatch
        XCTAssertTrue(riskSearch.waitForExistence(timeout: 10))
        XCTAssertFalse(riskSearch.label.isEmpty)
        riskSearch.tap()
        riskSearch.typeText("ibuprofen")
        XCTAssertTrue(app.staticTexts["布洛芬"].firstMatch.waitForExistence(timeout: 10))
    }

    private func clearSearchField(_ searchField: XCUIElement) {
        searchField.tap()
        let clearButton = searchField.buttons.firstMatch
        if clearButton.waitForExistence(timeout: 2) {
            clearButton.tap()
        } else {
            searchField.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
        }
    }
}
