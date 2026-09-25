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

    func testPrimaryTabsAreReachable() {
        assertPrimaryTabs(contentSizeArguments: nil)
    }

    func testPrimaryTabsRemainReachableAtMaximumTextSize() {
        assertPrimaryTabs(contentSizeArguments: accessibilityXXXLContentSizeArguments)
    }

    private func assertPrimaryTabs(contentSizeArguments: [String]?) {
        continueAfterFailure = false
        let app = launchElderFixture(mode: "complete", contentSizeArguments: contentSizeArguments)

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
            if contentSizeArguments != nil {
                XCTAssertTrue(tab.isHittable)
                addScreenshot(named: "complete-ax5-\(identifier)", from: app)
            }
        }
    }

    func testTodayCanOpenElderMode() {
        continueAfterFailure = false
        let app = launchElderFixture(mode: "complete")

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

        // The saved mode must survive a real process restart, not only a view update.
        restartElderFixture(app)
        XCTAssertTrue(app.buttons["elder.switch-to-complete"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.tabBars.firstMatch.exists)

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
        let viewport = visibleViewport(in: app, scrollSurface: app.scrollViews["elder.scroll"])
        XCTAssertTrue(viewport.contains(currentTaskText(containing: "布洛芬", in: app).frame))
        assertElderActionsVisible(in: app)

        addScreenshot(named: "elder-default-actions", from: app)

        app.buttons["elder.switch-to-complete"].tap()
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(elderModeEntry.waitForExistence(timeout: 5))
        restartElderFixture(app)
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(elderModeEntry.waitForExistence(timeout: 5))
    }

    func testElderPrimaryActionKeepsFullWidthHitRegion() {
        continueAfterFailure = false
        let app = launchElderFixture(scenario: "future")

        let completionButton = app.buttons["elder.action.taken"]
        scrollToHittable(completionButton, in: app)

        completionButton
            .coordinate(withNormalizedOffset: CGVector(dx: 0.03, dy: 0.5))
            .tap()

        let confirmation = app.buttons["elder.confirmation.confirm"]
        XCTAssertTrue(confirmation.waitForExistence(timeout: 5))
        let cancel = app.buttons["elder.confirmation.cancel"]
        scrollToHittable(cancel, in: app)
        cancel.tap()
        XCTAssertTrue(completionButton.waitForExistence(timeout: 5))
        XCTAssertFalse(app.descendants(matching: .any)["elder.feedback.success"].exists)
        assertStoredState(in: app, statuses: ["pending"], logCount: 0, saveAttempts: 0)
    }

    func testElderAccessibilityXXXLKeepsActionsVisible() {
        continueAfterFailure = false
        let app = launchElderFixture(contentSizeArguments: accessibilityXXXLContentSizeArguments)
        assertElderActionsVisible(in: app)
        let viewport = visibleViewport(in: app, scrollSurface: app.scrollViews["elder.scroll"])
        for text in ["布洛芬", "每次", "11:55"] {
            XCTAssertTrue(viewport.contains(currentTaskText(containing: text, in: app).frame),
                          "Medication identity, dose and time must fit above the action dock")
        }
        addScreenshot(named: "elder-axxxl-no-scroll", from: app)
    }

    func testElderAccessibilityConfirmationAndPhotoRemainReachable() {
        continueAfterFailure = false
        let app = launchElderFixture(scenario: "future", contentSizeArguments: accessibilityXXXLContentSizeArguments)
        assertElderActionsVisible(in: app)
        app.buttons["elder.action.taken"].tap()
        assertElderActionsVisible(in: app, identifiers: ["elder.confirmation.confirm", "elder.confirmation.cancel"])
        addScreenshot(named: "elder-axxxl-confirmation-no-scroll", from: app)
        app.buttons["elder.confirmation.cancel"].tap()
        assertElderActionsVisible(in: app)
        app.buttons["elder.photo.open"].tap()
        XCTAssertTrue(app.buttons["elder.photo.close"].waitForExistence(timeout: 5))
        addScreenshot(named: "elder-photo-expanded", from: app)
        app.buttons["elder.photo.close"].tap()
        assertElderActionsVisible(in: app)
        assertStoredState(in: app, statuses: ["pending"], logCount: 0, saveAttempts: 0)
    }

    func testElderDarkAppearanceKeepsActionsVisible() {
        continueAfterFailure = false
        let app = launchElderFixture(colorScheme: "dark", contentSizeArguments: accessibilityXXXLContentSizeArguments)
        assertElderActionsVisible(in: app)
        addScreenshot(named: "elder-axxxl-dark-no-scroll", from: app)
    }

    func testElderHelpSettingsSaveRemainsVisibleAboveKeyboard() {
        continueAfterFailure = false
        let app = launchElderFixture(contentSizeArguments: accessibilityXXXLContentSizeArguments)
        XCTAssertTrue(app.buttons["elder.settings"].waitForExistence(timeout: 10))
        app.buttons["elder.settings"].tap()
        let phone = app.textFields["settings.elder-help.phone"]
        XCTAssertTrue(phone.waitForExistence(timeout: 5))
        XCTAssertFalse(app.keyboards.firstMatch.exists, "Opening settings should not immediately obscure it with a keyboard")
        XCTAssertTrue(phone.isHittable)
        addScreenshot(named: "elder-help-settings-entry", from: app)
        phone.tap()
        phone.typeText("12025550123")
        XCTAssertFalse(app.buttons["settings.elder-help.remove"].exists, "An unsaved draft is not a saved contact")
        let save = app.buttons["settings.elder-help.save"]
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        addScreenshot(named: "elder-help-settings-keyboard", from: app)
        let keyboard = app.keyboards.firstMatch
        XCTAssertTrue(keyboard.exists)
        XCTAssertTrue(save.isHittable)
        XCTAssertLessThanOrEqual(save.frame.maxY, keyboard.frame.minY)
        save.tap()
        XCTAssertTrue(app.staticTexts["帮助号码已保存。"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.keyboards.firstMatch.exists)
        addScreenshot(named: "elder-help-settings-saved", from: app)
        XCTAssertTrue(app.buttons["settings.elder-help.remove"].exists)
        phone.tap()
        phone.typeText("4")
        XCTAssertFalse(app.staticTexts["帮助号码已保存。"].exists, "Editing must not keep a stale saved notice")
        app.buttons["收起键盘"].tap()
        app.buttons["settings.elder-help.remove"].tap()
        XCTAssertTrue(app.staticTexts["本机帮助号码已移除。"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["settings.elder-help.remove"].exists)
    }

    func testElderScreenPassesAccessibilityAudit() throws {
        continueAfterFailure = false
        let app = launchElderFixture()

        XCTAssertTrue(app.otherElements["elder.current-task"].waitForExistence(timeout: 10))
        waitForMedicationPhoto(in: app)
        // No issue filter or audit-type exclusions. This is not a VoiceOver pass.
        try app.performAccessibilityAudit(for: .all)
        scrollToHittable(app.buttons["elder.action.help"], in: app)
        try app.performAccessibilityAudit(for: .all)
        addScreenshot(named: "elder-accessibility-audit-actions", from: app)
    }

    func testElderBoldTextAndReducedAppMotionKeepActionsVisible() {
        continueAfterFailure = false
        let app = launchElderFixture(
            contentSizeArguments: accessibilityXXXLContentSizeArguments,
            extraArguments: ["--elder-ui-bold-text", "-prefersReducedAppMotion", "YES"]
        )
        assertCurrentTask("布洛芬", status: "未确认", in: app)
        addScreenshot(named: "elder-axxxl-bold-reduced-motion-top", from: app)
        assertElderActionsVisible(in: app)
        addScreenshot(named: "elder-axxxl-bold-reduced-motion-actions", from: app)
        assertStoredState(in: app, statuses: ["pending"], logCount: 0, saveAttempts: 0)
    }

    func testElderIdleClockRefreshDoesNotRecordAnAction() {
        continueAfterFailure = false
        let app = launchElderFixture(scenario: "idle-followup")
        assertCurrentTask("布洛芬", status: "待服用", in: app)
        addScreenshot(named: "elder-idle-before-due", from: app)
        // The production timer must change the presentation, not the stored status.
        XCTAssertTrue(currentTaskText(containing: "未确认", in: app).waitForExistence(timeout: 20))
        XCTAssertFalse(app.descendants(matching: .any)["elder.feedback.success"].exists)
        XCTAssertTrue(app.buttons["elder.action.taken"].exists)
        addScreenshot(named: "elder-idle-after-due", from: app)
        assertStoredState(in: app, statuses: ["pending"], logCount: 0, saveAttempts: 0)
        XCTAssertEqual(app.staticTexts["elder.test.store.schedule-attempts"].label, "0")
    }

    func testElderMidnightRefreshRevealsNewDayWithoutWriting() {
        continueAfterFailure = false
        let app = launchElderFixture(scenario: "midnight")
        XCTAssertTrue(app.staticTexts["今天没有用药任务"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.otherElements["elder.current-task"].exists)
        addScreenshot(named: "elder-midnight-before-rollover", from: app)
        XCTAssertTrue(currentTaskText(containing: "布洛芬", in: app).waitForExistence(timeout: 20))
        assertCurrentTask("布洛芬", status: "待服用", in: app)
        XCTAssertFalse(app.staticTexts["今天没有用药任务"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["elder.feedback.success"].exists)
        addScreenshot(named: "elder-midnight-after-rollover", from: app)
        assertStoredState(in: app, statuses: ["pending"], logCount: 0, saveAttempts: 0)
        XCTAssertEqual(app.staticTexts["elder.test.store.schedule-attempts"].label, "0")
    }

    func testElderSecondaryAndHelpActionsKeepFullWidthHitRegions() {
        continueAfterFailure = false
        let app = launchElderFixture(scenario: "future")

        let delayButton = app.buttons["elder.action.delay"]
        scrollToHittable(delayButton, in: app)
        delayButton.coordinate(withNormalizedOffset: CGVector(dx: 0.03, dy: 0.5)).tap()
        assertCurrentTask("布洛芬", status: "稍后提醒", in: app)
        XCTAssertTrue(delayButton.waitForExistence(timeout: 5))

        let helpButton = app.buttons["elder.action.help"]
        scrollToHittable(helpButton, in: app)
        helpButton.coordinate(withNormalizedOffset: CGVector(dx: 0.03, dy: 0.5)).tap()
        let missingCancel = app.alerts["还没有帮助号码"].buttons["elder.help.missing.cancel"].firstMatch
        XCTAssertTrue(missingCancel.waitForExistence(timeout: 5))
        missingCancel.tap()
        XCTAssertTrue(helpButton.waitForExistence(timeout: 5))
        assertStoredState(in: app, statuses: ["delayed"], logCount: 1, saveAttempts: 1)
        XCTAssertEqual(app.staticTexts["elder.test.store.task.0.due-offset"].label, "1800")
        XCTAssertEqual(app.staticTexts["elder.test.store.schedule-attempts"].label, "1")
    }

    func testElderAdvancesOneTaskAtATimeAndFinishes() {
        continueAfterFailure = false
        let app = launchElderFixture(scenario: "multiple")
        assertCurrentTask("布洛芬", status: "未确认", in: app)
        XCTAssertEqual(app.otherElements.matching(identifier: "elder.current-task").count, 1)
        XCTAssertFalse(currentTaskText(containing: "人工泪液", in: app).exists)
        addScreenshot(named: "elder-flow-first-task", from: app)

        tapElderAction("elder.action.taken", in: app)
        assertCurrentTask("人工泪液", status: "未确认", in: app)
        XCTAssertTrue(app.descendants(matching: .any)["elder.feedback.success"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["elder.action.taken"].label, "已使用")
        XCTAssertFalse(currentTaskText(containing: "布洛芬", in: app).exists)
        addScreenshot(named: "elder-flow-next-task", from: app)

        tapElderAction("elder.action.taken", in: app)
        assertCompleted(in: app)
        addScreenshot(named: "elder-flow-completed", from: app)
        restartElderFixture(app)
        assertCompleted(in: app)
        assertStoredState(in: app, statuses: ["taken", "taken"], logCount: 2, saveAttempts: 2)
    }

    func testElderMaximumTextNextTaskRestoresIdentityAboveActions() {
        continueAfterFailure = false
        let app = launchElderFixture(scenario: "multiple", contentSizeArguments: accessibilityXXXLContentSizeArguments)
        assertCurrentTask("布洛芬", status: "未确认", in: app)
        app.scrollViews["elder.scroll"].swipeUp()
        tapElderAction("elder.action.taken", in: app)
        assertCurrentTask("人工泪液", status: "未确认", in: app)
        assertElderActionsVisible(in: app)
        addScreenshot(named: "elder-axxxl-next-task-identity", from: app)
        let viewport = visibleViewport(in: app, scrollSurface: app.scrollViews["elder.scroll"])
        for text in ["人工泪液", "每次", "11:58"] {
            XCTAssertTrue(viewport.contains(currentTaskText(containing: text, in: app).frame),
                          "The next medication identity must be visible after a task change")
        }
        assertStoredState(in: app, statuses: ["taken", "pending"], logCount: 1, saveAttempts: 1)
    }

    func testElderEarlyConfirmationCanCancelThenCommit() {
        continueAfterFailure = false
        let app = launchElderFixture(scenario: "future")
        assertCurrentTask("布洛芬", status: "待服用", in: app)
        tapElderAction("elder.action.taken", in: app)
        XCTAssertTrue(app.buttons["elder.confirmation.confirm"].waitForExistence(timeout: 5))
        tapElderAction("elder.confirmation.cancel", in: app)
        assertCurrentTask("布洛芬", status: "待服用", in: app)
        XCTAssertFalse(app.descendants(matching: .any)["elder.feedback.success"].exists)

        tapElderAction("elder.action.taken", in: app)
        tapElderAction("elder.confirmation.confirm", in: app)
        assertCompleted(in: app)
        assertStoredState(in: app, statuses: ["taken"], logCount: 1, saveAttempts: 1)
    }

    func testElderSaveFailureKeepsTaskAndRetryPersists() {
        continueAfterFailure = false
        let app = launchElderFixture(extraArguments: ["--elder-ui-fail-first-save"])
        tapElderAction("elder.action.taken", in: app)
        let failureAlert = app.alerts["用药记录未保存"]
        XCTAssertTrue(failureAlert.waitForExistence(timeout: 5))
        XCTAssertFalse(app.descendants(matching: .any)["elder.feedback.success"].exists)
        addScreenshot(named: "elder-save-failure", from: app)
        failureAlert.buttons["好"].tap()
        assertCurrentTask("布洛芬", status: "未确认", in: app)

        tapElderAction("elder.action.taken", in: app)
        assertCompleted(in: app)
        restartElderFixture(app)
        assertCompleted(in: app)
        assertStoredState(in: app, statuses: ["taken"], logCount: 1, saveAttempts: 2)
    }

    func testElderFailedDelayHasNoDurableMutationOrSystemRequest() {
        continueAfterFailure = false
        let app = launchElderFixture(extraArguments: ["--elder-ui-fail-first-save"])
        tapElderAction("elder.action.delay", in: app)
        XCTAssertTrue(app.alerts["用药记录未保存"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.descendants(matching: .any)["elder.feedback.success"].exists)
        restartElderFixture(app)
        assertCurrentTask("布洛芬", status: "未确认", in: app)
        assertStoredState(in: app, statuses: ["pending"], logCount: 0, saveAttempts: 1)
        XCTAssertEqual(app.staticTexts["elder.test.store.task.0.due-offset"].label, "-300")
        XCTAssertEqual(app.staticTexts["elder.test.store.schedule-attempts"].label, "0")
    }

    func testElderDelayPersistsThirtyMinutesAfterRestart() {
        continueAfterFailure = false
        let app = launchElderFixture()
        tapElderAction("elder.action.delay", in: app)
        assertCurrentTask("布洛芬", status: "稍后提醒", in: app)
        XCTAssertTrue(app.descendants(matching: .any)["elder.feedback.success"].waitForExistence(timeout: 5))
        addScreenshot(named: "elder-delayed", from: app)
        restartElderFixture(app)
        assertCurrentTask("布洛芬", status: "稍后提醒", in: app)
        assertStoredState(in: app, statuses: ["delayed"], logCount: 1, saveAttempts: 1)
        XCTAssertEqual(app.staticTexts["elder.test.store.task.0.due-offset"].label, "1800")
        XCTAssertEqual(app.staticTexts["elder.test.store.schedule-attempts"].label, "1")
    }

    func testElderReminderFailureDoesNotClaimReminderSuccess() {
        continueAfterFailure = false
        let app = launchElderFixture(extraArguments: ["--elder-ui-reminder-unavailable"])
        tapElderAction("elder.action.delay", in: app)
        let reminderSettings = app.buttons["elder.reminder.settings"]
        XCTAssertTrue(reminderSettings.waitForExistence(timeout: 5))
        XCTAssertTrue(reminderSettings.label.contains("记录已保存；无法添加系统提醒，请检查通知设置。"))
        XCTAssertTrue(reminderSettings.label.contains("打开系统设置"))
        XCTAssertFalse(app.descendants(matching: .any)["elder.feedback.success"].exists)
        addScreenshot(named: "elder-reminder-unavailable", from: app)
        assertStoredState(in: app, statuses: ["delayed"], logCount: 1, saveAttempts: 1)
        XCTAssertEqual(app.staticTexts["elder.test.store.schedule-attempts"].label, "1")
    }

    func testElderBudgetWarningShowsPartialResultWithoutSettingsAction() {
        continueAfterFailure = false
        let app = launchElderFixture(extraArguments: ["--elder-ui-reminder-budget"])
        tapElderAction("elder.action.delay", in: app)
        let warning = app.descendants(matching: .any)["elder.reminder.warning"]
        XCTAssertTrue(warning.waitForExistence(timeout: 5))
        XCTAssertTrue(warning.label.contains("基础提醒已安排"))
        XCTAssertTrue(warning.label.contains("升级提醒因本机排程预算未安排"))
        XCTAssertFalse(app.buttons["elder.reminder.settings"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["elder.feedback.success"].exists)
    }

    func testElderRapidDoubleTapCommitsOnlyCurrentTask() {
        continueAfterFailure = false
        let app = launchElderFixture(scenario: "multiple")
        let completion = app.buttons["elder.action.taken"]
        scrollToHittable(completion, in: app)
        completion.doubleTap()
        assertCurrentTask("人工泪液", status: "未确认", in: app)
        restartElderFixture(app)
        assertCurrentTask("人工泪液", status: "未确认", in: app)
        assertStoredState(in: app, statuses: ["taken", "pending"], logCount: 1, saveAttempts: 1)
    }

    func testCompleteModeSettingsUsesIsolatedHelpNumber() {
        continueAfterFailure = false
        let app = launchElderFixture(scenario: "help-confirmation", mode: "complete")
        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 10))
        tabBar.buttons.element(boundBy: 4).tap()
        let settingsLink = app.buttons["profile.settings"]
        scrollToHittable(settingsLink, in: app)
        settingsLink.tap()

        let phone = app.textFields["settings.elder-help.phone"]
        XCTAssertTrue(phone.waitForExistence(timeout: 5))
        XCTAssertEqual(phone.value as? String, "+12025550123")
        app.buttons["settings.elder-help.save"].tap()
        XCTAssertTrue(app.staticTexts["帮助号码已保存。"].waitForExistence(timeout: 5))
        app.buttons["settings.elder-help.remove"].tap()
        XCTAssertTrue(app.staticTexts["本机帮助号码已移除。"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["settings.elder-help.remove"].exists)
        assertStoredState(in: app, statuses: ["pending"], logCount: 0, saveAttempts: 0)
    }

    func testCompleteModeLargeTouchSettingChangesActionHeightAndPersists() {
        continueAfterFailure = false
        let app = launchElderFixture(mode: "complete")
        let delay = app.buttons["稍后"].firstMatch
        scrollToHittable(delay, in: app)
        let largeHeight = delay.frame.height
        XCTAssertGreaterThanOrEqual(largeHeight, 48)

        for (valueBeforeTap, expectsLarge) in [("已开启", false), ("已关闭", true)] {
            app.tabBars.firstMatch.buttons.element(boundBy: 4).tap()
            let settingsLink = app.buttons["profile.settings"]
            scrollToHittable(settingsLink, in: app)
            settingsLink.tap()
            let setting = app.buttons["使用更大的触控区域"]
            // List lazily exposes offscreen rows on small phones.
            for _ in 0..<4 {
                if setting.exists { break }
                app.swipeUp()
            }
            scrollToHittable(setting, in: app)
            XCTAssertEqual(setting.value as? String, valueBeforeTap)
            setting.tap()
            restartElderFixture(app)
            scrollToHittable(delay, in: app)
            if expectsLarge {
                XCTAssertEqual(delay.frame.height, largeHeight, accuracy: 1)
            } else {
                XCTAssertGreaterThanOrEqual(delay.frame.height, 44)
                XCTAssertLessThan(delay.frame.height, largeHeight)
            }
        }
        assertStoredState(in: app, statuses: ["pending"], logCount: 0, saveAttempts: 0)
    }

    func testElderNoTasksDoesNotClaimCompletedDoses() {
        continueAfterFailure = false
        let app = launchElderFixture(scenario: "empty")
        XCTAssertTrue(app.staticTexts["今天没有用药任务"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["今日用药已完成"].exists)
        XCTAssertFalse(app.buttons["elder.action.taken"].exists)
        addScreenshot(named: "elder-no-tasks", from: app)
        assertStoredState(in: app, statuses: [], logCount: 0, saveAttempts: 0)
    }

    func testElderMissingHelpNumberCanCancelWithoutCalling() {
        continueAfterFailure = false
        let app = launchElderFixture(scenario: "help-missing")
        tapElderAction("elder.action.help", in: app)
        XCTAssertTrue(app.alerts["还没有帮助号码"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["elder.help.missing.settings"].exists)
        addScreenshot(named: "elder-help-missing", from: app)
        app.alerts["还没有帮助号码"].buttons["elder.help.missing.cancel"].firstMatch.tap()
        assertCurrentTask("布洛芬", status: "未确认", in: app)
        assertStoredState(in: app, statuses: ["pending"], logCount: 0, saveAttempts: 0)
    }

    func testElderUnavailableHelpStoreShowsErrorWithoutCalling() {
        continueAfterFailure = false
        let app = launchElderFixture(scenario: "help-unavailable")
        tapElderAction("elder.action.help", in: app)
        let dismiss = app.alerts["帮助暂不可用"].buttons["elder.help.error.dismiss"].firstMatch
        XCTAssertTrue(dismiss.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["帮助号码暂时无法在本机存取，请稍后重试。"].exists)
        dismiss.tap()
        assertCurrentTask("布洛芬", status: "未确认", in: app)
        assertStoredState(in: app, statuses: ["pending"], logCount: 0, saveAttempts: 0)
    }

    func testElderHelpConfirmationCancelDoesNotOpenPhone() {
        continueAfterFailure = false
        let app = launchElderFixture(scenario: "help-confirmation")
        tapElderAction("elder.action.help", in: app)
        let cancel = app.alerts["联系帮助？"].buttons["elder.help.cancel"].firstMatch
        XCTAssertTrue(cancel.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["拨打 +12025550123"].exists)
        addScreenshot(named: "elder-help-confirmation", from: app)
        cancel.tap()
        assertCurrentTask("布洛芬", status: "未确认", in: app)
        assertStoredState(in: app, statuses: ["pending"], logCount: 0, saveAttempts: 0)
    }

    func testElderHelpOpenerFailureIsHonest() {
        continueAfterFailure = false
        let app = launchElderFixture(scenario: "help-confirmation")
        tapElderAction("elder.action.help", in: app)
        let confirm = app.alerts["联系帮助？"].buttons["拨打 +12025550123"].firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        confirm.tap()
        XCTAssertTrue(app.buttons["elder.help.error.dismiss"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.descendants(matching: .any)["elder.feedback.success"].exists)
        assertStoredState(in: app, statuses: ["pending"], logCount: 0, saveAttempts: 0, helpAttempts: 1)
    }

    private func assertElderActionsVisible(
        in app: XCUIApplication,
        identifiers: [String] = ["elder.action.taken", "elder.action.delay", "elder.action.help"],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let window = app.windows.firstMatch.frame
        let navigationBottom = app.navigationBars.firstMatch.frame.maxY
        let viewport = CGRect(x: window.minX, y: navigationBottom,
                              width: window.width, height: window.maxY - navigationBottom - 8)
        var previousFrame: CGRect?
        for identifier in identifiers {
            let button = app.buttons[identifier]
            XCTAssertTrue(button.waitForExistence(timeout: 10), file: file, line: line)
            XCTAssertTrue(button.isHittable, "\(identifier) must be tappable without scrolling", file: file, line: line)
            XCTAssertTrue(viewport.contains(button.frame), "\(identifier) is outside the visible safe area: \(button.frame)", file: file, line: line)
            XCTAssertGreaterThanOrEqual(button.frame.height, 60, file: file, line: line)
            if let previousFrame {
                XCTAssertFalse(previousFrame.intersects(button.frame), file: file, line: line)
            }
            previousFrame = button.frame
        }
    }

    private func launchElderFixture(
        scenario: String = "due",
        mode: String = "elder",
        colorScheme: String = "light",
        contentSizeArguments: [String]? = nil,
        extraArguments: [String] = []
    ) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = stableLaunchArgumentsWithoutExperienceMode
            + (contentSizeArguments ?? regularContentSizeArguments)
            + [
                "--elder-ui-mode", mode,
                "-hasCompletedFirstLaunchSetup", "YES",
                "-appColorSchemePreference", colorScheme,
                "--elder-ui-fixture", scenario,
                "--elder-ui-session", UUID().uuidString
            ] + extraArguments
        installSystemPermissionHandler(for: app)
        app.launch()
        return app
    }

    private func restartElderFixture(_ app: XCUIApplication, inspectStore: Bool = false) {
        app.terminate()
        app.launchArguments.removeAll {
            $0 == "--elder-ui-fail-first-save" || $0 == "--elder-ui-inspect-store"
        }
        if inspectStore { app.launchArguments.append("--elder-ui-inspect-store") }
        app.launch()
    }

    private func currentTaskText(containing text: String, in app: XCUIApplication) -> XCUIElement {
        app.otherElements["elder.current-task"].staticTexts
            .matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }

    private func assertCurrentTask(
        _ medication: String,
        status: String,
        in app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertTrue(currentTaskText(containing: medication, in: app).waitForExistence(timeout: 10), file: file, line: line)
        XCTAssertTrue(currentTaskText(containing: status, in: app).waitForExistence(timeout: 5), file: file, line: line)
    }

    private func assertCompleted(in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(app.staticTexts["今日用药已完成"].waitForExistence(timeout: 10), file: file, line: line)
        XCTAssertFalse(app.buttons["elder.action.taken"].exists, file: file, line: line)
    }

    private func tapElderAction(_ identifier: String, in app: XCUIApplication) {
        let button = app.buttons[identifier]
        scrollToHittable(button, in: app)
        button.tap()
    }

    private func assertStoredState(
        in app: XCUIApplication,
        statuses: [String],
        logCount: Int,
        saveAttempts: Int,
        helpAttempts: Int = 0,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        restartElderFixture(app, inspectStore: true)
        let count = app.staticTexts["elder.test.store.log-count"]
        XCTAssertTrue(count.waitForExistence(timeout: 10), file: file, line: line)
        XCTAssertEqual(count.label, String(logCount), file: file, line: line)
        XCTAssertEqual(app.staticTexts["elder.test.store.task-count"].label, String(statuses.count), file: file, line: line)
        XCTAssertEqual(app.staticTexts["elder.test.store.help-attempts"].label, String(helpAttempts), file: file, line: line)
        XCTAssertEqual(app.staticTexts["elder.test.store.save-attempts"].label, String(saveAttempts), file: file, line: line)
        for (index, status) in statuses.enumerated() {
            XCTAssertEqual(app.staticTexts["elder.test.store.task.\(index).status"].label, status, file: file, line: line)
        }
    }

    private func addScreenshot(named name: String, from app: XCUIApplication) {
        waitForMedicationPhoto(in: app)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        let geometry = XCTAttachment(string: app.debugDescription)
        geometry.name = "\(name)-accessibility-tree"
        geometry.lifetime = .keepAlways
        add(geometry)
    }

    private func waitForMedicationPhoto(in app: XCUIApplication) {
        let photo = app.images["elder.medication.photo"]
        guard photo.exists else { return }
        let ready = NSPredicate(format: "label ENDSWITH %@", "药品实物照片")
        XCTAssertTrue(app.images.matching(identifier: "elder.medication.photo")
            .matching(ready).firstMatch.waitForExistence(timeout: 10),
            "The real package photo did not finish decoding")
    }

    private func scrollToHittable(
        _ element: XCUIElement,
        in app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertTrue(element.waitForExistence(timeout: 5), file: file, line: line)
        XCTAssertTrue(element.wait(for: \.isEnabled, toEqual: true, timeout: 5), file: file, line: line)
        if element.identifier.hasPrefix("elder.action.") || element.identifier.hasPrefix("elder.confirmation.") {
            assertElderActionsVisible(in: app, identifiers: [element.identifier], file: file, line: line)
            return
        }
        let elderScroll = app.scrollViews["elder.scroll"]
        let scrollSurface: XCUIElement = elderScroll.exists ? elderScroll : app
        for _ in 0..<12 {
            let viewport = visibleViewport(in: app, scrollSurface: scrollSurface)
            if element.isHittable && viewport.contains(element.frame) {
                return
            }
            // Whole-screen flicks can oscillate past tall AX text on short displays.
            // Use a bounded drag towards the measured target without inertial scrolling.
            let travel = max(-viewport.height * 0.4,
                             min(viewport.height * 0.4, viewport.midY - element.frame.midY))
            let origin = app.coordinate(withNormalizedOffset: .zero)
            let start = origin.withOffset(CGVector(dx: viewport.midX, dy: viewport.midY - travel / 2))
            let finish = origin.withOffset(CGVector(dx: viewport.midX, dy: viewport.midY + travel / 2))
            start.press(forDuration: 0.1, thenDragTo: finish)
        }
        XCTAssertTrue(element.isHittable, "Control remained unreachable after scrolling", file: file, line: line)
        XCTAssertTrue(visibleViewport(in: app, scrollSurface: scrollSurface).contains(element.frame),
                      "Control remained clipped by navigation or the visible viewport", file: file, line: line)
    }

    private func visibleViewport(in app: XCUIApplication, scrollSurface: XCUIElement) -> CGRect {
        var viewport = app.frame.intersection(scrollSurface.frame)
        let navigationBar = app.navigationBars.firstMatch
        if navigationBar.exists {
            let top = max(viewport.minY, navigationBar.frame.maxY)
            viewport = CGRect(x: viewport.minX, y: top, width: viewport.width, height: max(0, viewport.maxY - top))
        }
        let tabBar = app.tabBars.firstMatch
        if tabBar.exists {
            viewport.size.height = max(0, min(viewport.maxY, tabBar.frame.minY) - viewport.minY)
        }
        let actionDock = app.otherElements["elder.actions"]
        if actionDock.exists {
            viewport.size.height = max(0, min(viewport.maxY, actionDock.frame.minY) - viewport.minY)
        }
        return viewport
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

    func testFirstLaunchOffersProgressAndSkipActions() {
        continueAfterFailure = false
        let app = launchElderFixture(mode: "complete", extraArguments: ["-showFirstLaunch"])

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
