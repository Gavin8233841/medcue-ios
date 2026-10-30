import XCTest

@MainActor
final class MedicationAdherenceAppUITests: XCTestCase {
    private let clearedPersistenceFailureArguments = [
        "-AppPersistenceCommitter.failureMessage", "",
        "-DoseActionPersistence.failureMessage", ""
    ]

    func testAssistantComposerAvoidsKeyboardAndRestoresAtBottom() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--assistant-ui-preview", "-appColorSchemePreference", "dark"]
        app.launch()
        let input = app.descendants(matching: .any).matching(identifier: "assistant.input").firstMatch
        XCTAssertTrue(input.waitForExistence(timeout: 15))
        input.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        let send = app.buttons["assistant.send"]
        XCTAssertLessThanOrEqual(send.frame.maxY, app.keyboards.firstMatch.frame.minY + 2)
        input.typeText("draft preserved")
        // Drag inside the vertical transcript, away from nested shortcut strips.
        let upper = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.28))
        let lower = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.55))
        upper.press(forDuration: 0.05, thenDragTo: lower)
        upper.press(forDuration: 0.05, thenDragTo: lower)
        let historyShot = XCTAttachment(screenshot: app.screenshot())
        historyShot.name = "assistant-history"
        historyShot.lifetime = .keepAlways
        add(historyShot)
        XCTAssertFalse(input.isHittable)
        for _ in 0..<6 { lower.press(forDuration: 0.05, thenDragTo: upper) }
        XCTAssertTrue(input.isHittable)
        XCTAssertEqual(input.value as? String, "draft preserved")
        XCTAssertFalse(app.buttons["展开聊天输入框"].exists)
        input.tap()
        send.tap()
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "draft preserved")).firstMatch.waitForExistence(timeout: 3))
    }

    func testAssistantMessageLongPressOffersTextActions() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--assistant-ui-preview"]
        app.launch()
        let text = app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "仅用于界面验证")).firstMatch
        XCTAssertTrue(text.waitForExistence(timeout: 15))
        text.press(forDuration: 1)
        XCTAssertTrue(app.buttons["复制"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["选取文字"].exists)
        XCTAssertTrue(app.buttons["引用到输入框"].exists)
        app.buttons["选取文字"].tap()
        XCTAssertTrue(app.navigationBars["选取文字"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["复制全部"].exists)
    }

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
}
