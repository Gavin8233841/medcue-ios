import XCTest

@MainActor
final class MedicationAdherenceAppUITests: XCTestCase {
    private let stableLaunchArgumentsWithoutExperienceMode = [
        "-AppPersistenceCommitter.failureMessage", "",
        "-DoseActionPersistence.failureMessage", ""
    ]

    private var stableLaunchArguments: [String] {
        stableLaunchArgumentsWithoutExperienceMode + ["-appExperienceMode", "complete"]
    }

    func testPrimaryTabsAreReachable() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = stableLaunchArguments + [
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

    func testTodayCanOpenElderMode() {
        continueAfterFailure = false
        let app = XCUIApplication()

        app.launchArguments = stableLaunchArgumentsWithoutExperienceMode + [
            "-appExperienceMode", "elder",
            "-hasCompletedFirstLaunchSetup", "YES",
            "--seed-demo-data"
        ]
        app.launch()

        let switchToComplete = app.buttons["elder.switch-to-complete"]
        XCTAssertTrue(switchToComplete.waitForExistence(timeout: 10))
        switchToComplete.tap()
        app.terminate()

        app.launchArguments = stableLaunchArgumentsWithoutExperienceMode + [
            "-hasCompletedFirstLaunchSetup", "YES"
        ]
        app.launch()

        let elderModeEntry = app.buttons["today.elder-mode-entry"]
        XCTAssertTrue(elderModeEntry.waitForExistence(timeout: 10))
        elderModeEntry.tap()

        XCTAssertTrue(
            app.buttons["elder.switch-to-complete"].waitForExistence(timeout: 5),
            "The elder-mode navigation controls did not appear after selecting the Today entry"
        )
        XCTAssertFalse(app.tabBars.firstMatch.exists)
        XCTAssertFalse(app.staticTexts["现在只需处理一件事"].exists)
        XCTAssertFalse(app.staticTexts["无操作会保持未确认，不会自动记成忽略。"].exists)
        XCTAssertFalse(app.staticTexts["这里不会推断为全部已服用；有新的待确认任务时会显示在这里。"].exists)

        let completionButton = app.buttons["elder.action.taken"]
        let delayButton = app.buttons["elder.action.delay"]
        let helpButton = app.buttons["elder.action.help"]
        XCTAssertTrue(completionButton.waitForExistence(timeout: 5))
        XCTAssertTrue(delayButton.waitForExistence(timeout: 5))
        XCTAssertTrue(helpButton.waitForExistence(timeout: 5))
        XCTAssertGreaterThan(completionButton.frame.height, delayButton.frame.height)
        XCTAssertGreaterThan(delayButton.frame.height, helpButton.frame.height)
        XCTAssertEqual(helpButton.frame.width, delayButton.frame.width, accuracy: 1)
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
        app.launchArguments = stableLaunchArguments + ["-showFirstLaunch"]
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
