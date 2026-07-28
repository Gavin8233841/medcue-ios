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
}
