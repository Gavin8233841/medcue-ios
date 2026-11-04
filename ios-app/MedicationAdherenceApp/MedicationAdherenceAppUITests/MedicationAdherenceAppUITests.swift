import XCTest

@MainActor
final class MedicationAdherenceAppUITests: XCTestCase {
    func testTodaySettledRecordsDoNotClaimSkippedDosesWereTaken() {
        let app = launchIsolatedToday()
        for _ in 0..<5 {
            let skip = app.buttons["忽略"].firstMatch
            XCTAssertTrue(skip.waitForExistence(timeout: 5))
            skip.tap()
            // Allow the existing committed row-migration animation to finish.
            RunLoop.current.run(until: Date().addingTimeInterval(0.7))
        }
        XCTAssertTrue(app.staticTexts["今日暂无待处理"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["今日用药已完成"].exists)
        XCTAssertFalse(app.staticTexts["下一次提醒"].exists)
        XCTAssertFalse(app.staticTexts["天气与用药关注"].exists)
        let records = app.buttons["今日记录"]
        XCTAssertTrue(records.exists)
        records.tap()
        XCTAssertTrue((records.value as? String)?.contains("已展开") == true)
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "Today-skipped-records-expanded"
        shot.lifetime = .keepAlways
        add(shot)
        records.tap()
        XCTAssertTrue((records.value as? String)?.contains("已折叠") == true)
    }

    func testElderHoldCancellationAndModeConfirmation() {
        let app = launchIsolatedToday()
        app.buttons["today.enter-elder"].tap()
        app.alerts.buttons["取消"].tap()
        XCTAssertTrue(app.buttons["today.enter-elder"].exists)
        app.buttons["today.enter-elder"].tap()
        app.alerts.buttons["进入适老模式"].tap()
        let taken = app.buttons["elder.action.taken"]
        XCTAssertTrue(taken.waitForExistence(timeout: 5))
        taken.tap()
        XCTAssertFalse(app.alerts["确认已服用或使用？"].exists)
        taken.press(forDuration: 0.35)
        XCTAssertFalse(app.alerts["确认已服用或使用？"].exists)
        taken.press(forDuration: 1.4)
        XCTAssertTrue(app.alerts["确认已服用或使用？"].waitForExistence(timeout: 3))
        app.alerts.buttons["取消"].tap()
        XCTAssertTrue(taken.exists)
        XCTAssertFalse(app.buttons["elder.action.skip"].exists)
        XCTAssertFalse(app.staticTexts["长按确认"].exists)
        app.buttons["elder.action.help"].tap()
        let closeHelp = app.buttons["完成"].firstMatch
        XCTAssertTrue(closeHelp.waitForExistence(timeout: 3))
        closeHelp.tap()
        XCTAssertTrue(app.staticTexts["还有 4 项待处理"].exists)
        app.buttons["elder.switch-to-complete"].tap()
        app.alerts.buttons["取消"].tap()
        XCTAssertTrue(taken.exists)
        app.buttons["elder.switch-to-complete"].tap()
        app.alerts.buttons["返回完整模式"].tap()
        XCTAssertTrue(app.buttons["today.enter-elder"].waitForExistence(timeout: 5))
    }

    private func launchIsolatedToday() -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--medication-gallery-preview", "--seed-demo-data",
            "--recording-hide-reminder-banner", "-hasCompletedFirstLaunchSetup", "YES"]
        app.launch()
        let today = app.tabBars.buttons.element(boundBy: 0)
        XCTAssertTrue(today.waitForExistence(timeout: 15))
        today.tap()
        XCTAssertTrue(app.buttons["today.enter-elder"].waitForExistence(timeout: 8))
        return app
    }

    private let clearedPersistenceFailureArguments = [
        "-AppPersistenceCommitter.failureMessage", "",
        "-DoseActionPersistence.failureMessage", ""
    ]

    func testAssistantComposerAvoidsKeyboardAndRestoresAtBottom() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--assistant-ui-preview", "-appColorSchemePreference", "dark"]
        app.launch()
        // The scroll container's identifier is inherited by the native field on
        // current Simulator runtimes. The fixture contains one actual text field.
        let input = app.textFields.firstMatch
        XCTAssertTrue(input.waitForExistence(timeout: 15))
        input.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        let send = app.buttons.matching(NSPredicate(format: "label == %@ AND identifier != %@", "发送", "Send")).firstMatch
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

    func testAssistantWaitingStateUsesCompactActivity() {
        continueAfterFailure = false
        let app = XCUIApplication()
        for appearance in ["light", "dark"] {
            app.launchArguments = ["--assistant-ui-preview", "--assistant-waiting-preview",
                "-appColorSchemePreference", appearance]
            app.launch()
            let status = app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "正在准备本机回答")).firstMatch
            XCTAssertTrue(status.waitForExistence(timeout: 15))
            XCTAssertTrue(status.isHittable)
            let shot = XCTAttachment(screenshot: app.screenshot())
            shot.name = "Assistant-compact-waiting-\(appearance)"
            shot.lifetime = .keepAlways
            add(shot)
        }
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
