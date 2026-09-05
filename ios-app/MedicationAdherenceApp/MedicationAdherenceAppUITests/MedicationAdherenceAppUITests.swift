import XCTest

@MainActor
final class MedicationAdherenceAppUITests: XCTestCase {
    private let regularContentSizeArguments = [
        "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryL"
    ]
    private let accessibilityXXXLContentSizeArguments = [
        "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"
    ]
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

        app.launchArguments = stableLaunchArgumentsWithoutExperienceMode + regularContentSizeArguments + [
            "-appExperienceMode", "elder",
            "-hasCompletedFirstLaunchSetup", "YES",
            "--seed-demo-data"
        ]
        installSystemPermissionHandler(for: app)
        app.launch()
        app.tap()

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
        XCTAssertFalse(completionButton.frame.intersects(delayButton.frame))
        XCTAssertFalse(delayButton.frame.intersects(helpButton.frame))
        XCTAssertEqual(helpButton.frame.width, delayButton.frame.width, accuracy: 1)
        XCTAssertEqual(completionButton.frame.width, delayButton.frame.width, accuracy: 1)

        addScreenshot(named: "elder-default-top", from: app)
        app.swipeUp()
        addScreenshot(named: "elder-default-actions", from: app)
    }

    func testElderPrimaryActionKeepsFullWidthHitRegion() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = stableLaunchArgumentsWithoutExperienceMode + regularContentSizeArguments + [
            "-appExperienceMode", "elder",
            "-hasCompletedFirstLaunchSetup", "YES",
            "--seed-demo-data"
        ]
        installSystemPermissionHandler(for: app)
        app.launch()
        app.tap()
        app.swipeUp()

        let completionButton = app.buttons["elder.action.taken"]
        XCTAssertTrue(completionButton.waitForExistence(timeout: 10))
        print("elder action frame=\(completionButton.frame) hittable=\(completionButton.isHittable)")
        XCTAssertTrue(completionButton.isHittable)

        // The visible primary background is inset only for hierarchy; its hit region remains full width.
        completionButton
            .coordinate(withNormalizedOffset: CGVector(dx: 0.03, dy: 0.5))
            .tap()

        let confirmation = app.buttons["elder.confirmation.confirm"]
        if confirmation.waitForExistence(timeout: 3) {
            let cancel = app.buttons["elder.confirmation.cancel"]
            XCTAssertTrue(cancel.waitForExistence(timeout: 3))
            cancel.tap()
            XCTAssertTrue(completionButton.waitForExistence(timeout: 3))
        } else {
            XCTAssertTrue(
                app.descendants(matching: .any)["elder.feedback.success"].waitForExistence(timeout: 5),
                "An edge tap should produce confirmation or committed success feedback"
            )
        }
    }

    func testElderAccessibilityXXXLLayoutRemainsScrollable() {
        continueAfterFailure = false
        let app = XCUIApplication()
        // Pin the launch override so this test always exercises Accessibility XXXL.
        app.launchArguments = stableLaunchArgumentsWithoutExperienceMode + accessibilityXXXLContentSizeArguments + [
            "-appExperienceMode", "elder",
            "-hasCompletedFirstLaunchSetup", "YES",
            "--seed-demo-data"
        ]
        installSystemPermissionHandler(for: app)
        app.launch()
        app.tap()

        let currentTask = app.otherElements["elder.current-task"]
        XCTAssertTrue(currentTask.waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["elder.action.taken"].waitForExistence(timeout: 10))
        addScreenshot(named: "elder-axxxl-top", from: app)

        app.swipeUp()

        let delayButton = app.buttons["elder.action.delay"]
        let helpButton = app.buttons["elder.action.help"]
        XCTAssertTrue(delayButton.waitForExistence(timeout: 5))
        XCTAssertTrue(helpButton.waitForExistence(timeout: 5))
        XCTAssertFalse(delayButton.frame.intersects(helpButton.frame))
        XCTAssertGreaterThan(delayButton.frame.height, 67)
        XCTAssertGreaterThan(helpButton.frame.height, 59)
        addScreenshot(named: "elder-axxxl-actions", from: app)
    }

    func testElderSecondaryAndHelpActionsKeepFullWidthHitRegions() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = stableLaunchArgumentsWithoutExperienceMode + regularContentSizeArguments + [
            "-appExperienceMode", "elder",
            "-hasCompletedFirstLaunchSetup", "YES",
            "--seed-demo-data"
        ]
        installSystemPermissionHandler(for: app)
        app.launch()
        app.tap()
        app.swipeUp()

        let delayButton = app.buttons["elder.action.delay"]
        XCTAssertTrue(delayButton.waitForExistence(timeout: 10))
        XCTAssertTrue(delayButton.isHittable)
        delayButton.coordinate(withNormalizedOffset: CGVector(dx: 0.03, dy: 0.5)).tap()
        XCTAssertTrue(
            dismissElderTransientSurfaceIfPresented(in: app),
            "A delay edge tap should produce confirmation, committed feedback, or an honest error surface"
        )
        XCTAssertTrue(delayButton.waitForExistence(timeout: 5))

        let helpButton = app.buttons["elder.action.help"]
        XCTAssertTrue(helpButton.waitForExistence(timeout: 5))
        XCTAssertTrue(helpButton.isHittable)
        helpButton.coordinate(withNormalizedOffset: CGVector(dx: 0.03, dy: 0.5)).tap()
        XCTAssertTrue(
            dismissElderTransientSurfaceIfPresented(in: app),
            "A help edge tap should produce a confirmation, missing-number, or honest error surface"
        )
        XCTAssertTrue(helpButton.waitForExistence(timeout: 5))
    }

    private func addScreenshot(named name: String, from app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func installSystemPermissionHandler(for app: XCUIApplication) {
        addUIInterruptionMonitor(withDescription: "system permission") { alert in
            if alert.buttons["不允许"].exists {
                alert.buttons["不允许"].tap()
                return true
            }
            if alert.buttons["允许"].exists {
                alert.buttons["允许"].tap()
                return true
            }
            return false
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

    @discardableResult
    private func dismissElderTransientSurfaceIfPresented(in app: XCUIApplication) -> Bool {
        let doseConfirmationCancel = app.buttons["elder.confirmation.cancel"].firstMatch
        if doseConfirmationCancel.waitForExistence(timeout: 2) {
            doseConfirmationCancel.tap()
            return true
        }

        let helpCancel = app.buttons["elder.help.cancel"].firstMatch
        if helpCancel.waitForExistence(timeout: 2) {
            helpCancel.tap()
            return true
        }

        let missingCancel = app.buttons["elder.help.missing.cancel"].firstMatch
        if missingCancel.waitForExistence(timeout: 2) {
            missingCancel.tap()
            return true
        }

        let errorDismiss = app.buttons["elder.help.error.dismiss"].firstMatch
        if errorDismiss.waitForExistence(timeout: 2) {
            errorDismiss.tap()
            return true
        }

        return app.descendants(matching: .any)["elder.feedback.success"].waitForExistence(timeout: 2)
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
