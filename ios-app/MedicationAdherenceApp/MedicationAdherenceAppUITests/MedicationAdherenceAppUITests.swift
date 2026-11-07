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
        let app = launchElderFixture(scenario: "future", mode: "complete")
        app.buttons["today.enter-elder"].tap()
        app.alerts.buttons["取消"].tap()
        XCTAssertTrue(app.buttons["today.enter-elder"].exists)
        app.buttons["today.enter-elder"].tap()
        app.alerts.buttons["进入适老模式"].tap()
        let taken = app.buttons["elder.action.taken"]
        XCTAssertTrue(taken.waitForExistence(timeout: 5))
        taken.tap()
        XCTAssertFalse(app.buttons["elder.confirmation.confirm"].exists)
        taken.press(forDuration: 0.35)
        XCTAssertFalse(app.buttons["elder.confirmation.confirm"].exists)
        taken.press(forDuration: 1.4)
        XCTAssertTrue(app.buttons["elder.confirmation.confirm"].waitForExistence(timeout: 3))
        app.buttons["elder.confirmation.cancel"].tap()
        XCTAssertTrue(taken.exists)
        XCTAssertFalse(app.buttons["elder.action.skip"].exists)
        XCTAssertFalse(app.staticTexts["长按确认"].exists)
        app.buttons["elder.action.help"].tap()
        let closeHelp = app.buttons["完成"].firstMatch
        XCTAssertTrue(closeHelp.waitForExistence(timeout: 3))
        closeHelp.tap()
        assertCurrentTask("布洛芬", status: "待服用", in: app)
        app.buttons["elder.switch-to-complete"].tap()
        app.alerts.buttons["取消"].tap()
        XCTAssertTrue(taken.exists)
        app.buttons["elder.switch-to-complete"].tap()
        app.alerts.buttons["退出"].tap()
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

    func testRecoveryRetryResumesOriginalPersistentStore() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = [
            "--medcue-simulate-initial-store-open-failure",
            "--medcue-recovery-isolated-test-store"
        ]
        app.launch()

        let retry = app.buttons["重试读取原记录"]
        XCTAssertTrue(retry.waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["现有记录没有被删除或重建。此页面不能新增或修改用药记录。"].exists)
        retry.tap()
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: retry)
        XCTAssertEqual(XCTWaiter.wait(for: [gone], timeout: 15), .completed)
    }

    func testRecoveryRetryFailureStaysOnReadOnlyPage() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = [
            "--medcue-simulate-initial-store-open-failure",
            "--medcue-simulate-retry-store-open-failure"
        ]
        app.launch()

        let retry = app.buttons["重试读取原记录"]
        XCTAssertTrue(retry.waitForExistence(timeout: 10))
        retry.tap()
        XCTAssertTrue(app.staticTexts["recovery.status"].waitForExistence(timeout: 5))
        XCTAssertTrue(retry.exists)
        XCTAssertFalse(app.tabBars.firstMatch.exists)
        XCTAssertTrue(app.buttons["导出脱敏诊断信息"].exists)
    }

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

    func testLegacyLiveActivityURLsCannotChangeDoseOrSchedule() throws {
        continueAfterFailure = false
        let app = launchElderFixture(mode: "complete", extraArguments: ["--elder-ui-inspect-store"])
        let taskIDLabel = app.staticTexts["elder.test.store.task.0.id"]
        XCTAssertTrue(taskIDLabel.waitForExistence(timeout: 10))
        let taskID = try XCTUnwrap(UUID(uuidString: taskIDLabel.label))
        let initialScheduleAttempts = app.staticTexts["elder.test.store.schedule-attempts"].label

        restartElderFixture(app)

        let forgedURLs = [
            legacyLiveActivityURL(taskID: taskID, action: "markTaken"),
            legacyLiveActivityURL(taskID: taskID, action: "markTaken", operationID: nil),
            legacyLiveActivityURL(taskID: taskID, action: "delay"),
            legacyLiveActivityURL(taskID: taskID, action: "skip"),
            legacyLiveActivityURL(
                taskID: taskID,
                action: "markTaken",
                operationID: UUID(),
                expiresAt: Date().addingTimeInterval(86_400)
            ),
            legacyLiveActivityURL(taskID: UUID(), action: "markTaken"),
            legacyLiveActivityURL(taskID: taskID, action: "markTaken", host: "other-action")
        ]
        for url in forgedURLs {
            app.open(url)
        }

        restartElderFixture(app, inspectStore: true)
        XCTAssertEqual(app.staticTexts["elder.test.store.task.0.status"].label, "pending")
        XCTAssertEqual(app.staticTexts["elder.test.store.log-count"].label, "0")
        XCTAssertEqual(app.staticTexts["elder.test.store.save-attempts"].label, "0")
        XCTAssertEqual(
            app.staticTexts["elder.test.store.schedule-attempts"].label,
            initialScheduleAttempts
        )
    }

    private func legacyLiveActivityURL(
        taskID: UUID,
        action: String,
        operationID: UUID? = UUID(),
        expiresAt: Date? = Date().addingTimeInterval(3_600),
        host: String = "live-activity-dose-action"
    ) -> URL {
        var components = URLComponents()
        components.scheme = "medicationadherence"
        components.host = host
        var queryItems = [
            URLQueryItem(name: "taskID", value: taskID.uuidString),
            URLQueryItem(name: "action", value: action)
        ]
        if let operationID {
            queryItems.append(URLQueryItem(name: "operationID", value: operationID.uuidString))
        }
        if let expiresAt {
            queryItems.append(URLQueryItem(name: "expiresAt", value: String(expiresAt.timeIntervalSince1970)))
        }
        components.queryItems = queryItems
        guard let url = components.url else {
            preconditionFailure("Synthetic Live Activity URL must be valid")
        }
        return url
    }

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
            }
            addScreenshot(named: "complete-\(contentSizeArguments == nil ? "default" : "ax5")-\(identifier)", from: app)
        }
    }

    func testCompleteMaximumTextContentAndNavigation() {
        continueAfterFailure = false
        let app = launchElderFixture(scenario: "future", mode: "complete", contentSizeArguments: accessibilityXXXLContentSizeArguments)
        let name = app.staticTexts["timeline.medication-name"]
        scrollToHittable(name, in: app)
        XCTAssertEqual(name.label, "布洛芬")
        XCTAssertGreaterThan(name.frame.width, 120, "The medication name must retain its full AX font width")
        let dose = app.staticTexts["timeline.dose"]
        scrollToHittable(dose, in: app)
        XCTAssertEqual(dose.label, "1 片")
        XCTAssertGreaterThanOrEqual(dose.frame.minY, name.frame.maxY)
        addScreenshot(named: "complete-ax5-today-dose", from: app)

        let delay = app.buttons["today.timeline.action.delay"]
        scrollToHittable(delay, in: app)
        delay.tap()
        let cancel = app.buttons["today.timeline.confirmation.cancel"]
        scrollToHittable(cancel, in: app)
        XCTAssertGreaterThanOrEqual(cancel.frame.height, 60)
        addScreenshot(named: "complete-ax5-today-confirmation", from: app)
        cancel.tap()
        XCTAssertFalse(cancel.exists)

        app.tabBars.buttons.element(boundBy: 1).tap()
        // This fixture's course is fixed in September. The gallery correctly
        // uses today's real date and groups its ended course under interrupted.
        let interrupted = app.segmentedControls.buttons["服用中断 1"]
        scrollToHittable(interrupted, in: app)
        interrupted.tap()
        let medicationCard = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "布洛芬")).firstMatch
        scrollToHittable(medicationCard, in: app)
        XCTAssertGreaterThanOrEqual(medicationCard.frame.width, 300, "AX medication gallery must use one full-width column")
        XCTAssertTrue(medicationCard.label.contains("布洛芬"))
        addScreenshot(named: "complete-ax5-medication-gallery", from: app)
        medicationCard.tap()
        XCTAssertTrue(app.navigationBars["药品详情"].waitForExistence(timeout: 5))
        app.navigationBars.buttons.firstMatch.tap()
        let moreInformation = app.buttons["更多用药信息"]
        scrollToHittable(moreInformation, in: app)
        moreInformation.tap()
        app.buttons["用药概览"].tap()
        XCTAssertTrue(app.navigationBars["药品总览"].waitForExistence(timeout: 5))
        app.navigationBars.buttons.firstMatch.tap()
        let risk = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "风险复核")).firstMatch
        scrollToHittable(risk, in: app)
        XCTAssertGreaterThanOrEqual(risk.frame.width, 300)
        addScreenshot(named: "complete-ax5-medication-risk-entry", from: app)
        risk.tap()
        XCTAssertTrue(app.navigationBars["风险复核"].waitForExistence(timeout: 5))
        app.navigationBars.buttons.firstMatch.tap()

        app.tabBars.buttons.element(boundBy: 2).tap()
        dismissAssistantGatesIfPresented(in: app)
        let runtime = app.buttons["切换智能体模式"]
        XCTAssertTrue(runtime.waitForExistence(timeout: 5))
        runtime.tap()
        let cloudDescription = app.staticTexts["联网回答 · 授权后使用"]
        scrollToHittable(cloudDescription, in: app)
        XCTAssertGreaterThan(cloudDescription.frame.width, 240)
        addScreenshot(named: "complete-ax5-runtime-expanded", from: app)
        // Inspect the selector without starting a download, consent change or AI request.
        scrollToHittable(runtime, in: app)
        runtime.tap()
        XCTAssertTrue(cloudDescription.waitForNonExistence(timeout: 5))

        app.tabBars.buttons.element(boundBy: 3).tap()
        let days = app.staticTexts.matching(NSPredicate(format: "identifier BEGINSWITH %@", "records.week.day."))
        XCTAssertEqual(days.count, 7, "The accessible calendar must retain all seven dates")
        let firstDay = days.element(boundBy: 0)
        let lastDay = days.element(boundBy: 6)
        XCTAssertLessThan(firstDay.frame.maxY, days.element(boundBy: 1).frame.minY)
        scrollToHittable(firstDay, in: app)
        XCTAssertGreaterThanOrEqual(firstDay.frame.width, 280)
        addScreenshot(named: "complete-ax5-calendar-first-dates", from: app)
        scrollToHittable(lastDay, in: app)
        addScreenshot(named: "complete-ax5-calendar-last-dates", from: app)
        lastDay.tap()
        XCTAssertTrue(app.navigationBars.buttons.firstMatch.waitForExistence(timeout: 5))
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(firstDay.exists)

        assertStoredState(in: app, statuses: ["pending"], logCount: 0, saveAttempts: 0)
    }

    func testProfileMaximumTextSettingsRemainReadableAndReachable() {
        continueAfterFailure = false
        let app = launchElderFixture(mode: "complete", contentSizeArguments: accessibilityXXXLContentSizeArguments)
        app.tabBars.buttons.element(boundBy: 4).tap()
        let profileRoot = app.descendants(matching: .any)["profile.root"]
        XCTAssertTrue(profileRoot.waitForExistence(timeout: 5))
        let summary = app.staticTexts["profile.local-data.summary"]
        scrollToHittable(summary, in: app)
        XCTAssertEqual(summary.label, "提醒、记录和药品资料保存在这台 iPhone")
        XCTAssertGreaterThan(summary.frame.width, 220)
        addScreenshot(named: "complete-ax5-local-data", from: app)
        let settings = app.buttons["profile.settings"]
        for _ in 0..<12 {
            if settings.exists { break }
            app.swipeUp()
        }
        scrollToHittable(settings, in: app)
        let settingsSummary = settings.staticTexts["外观、提醒、触控和系统设置"]
        XCTAssertTrue(settingsSummary.exists)
        XCTAssertGreaterThan(settingsSummary.frame.width, 220)
        addScreenshot(named: "complete-ax5-profile-settings-entry", from: app)
        settings.tap()
        XCTAssertTrue(app.navigationBars["应用设置"].waitForExistence(timeout: 5))
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(profileRoot.waitForExistence(timeout: 5))
        XCTAssertTrue(settings.waitForExistence(timeout: 5))
    }

    func testTodayCanOpenElderMode() {
        continueAfterFailure = false
        let app = launchElderFixture(mode: "complete")

        let elderModeEntry = app.buttons["today.enter-elder"]
        XCTAssertTrue(elderModeEntry.waitForExistence(timeout: 10))
        elderModeEntry.tap()
        app.alerts.buttons["进入适老模式"].tap()

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
        app.alerts.buttons["退出"].tap()
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
            .press(forDuration: 1.4)

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
        app.buttons["elder.action.taken"].press(forDuration: 1.4)
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
        delayButton.coordinate(withNormalizedOffset: CGVector(dx: 0.03, dy: 0.5)).press(forDuration: 1.4)
        assertCurrentTask("布洛芬", status: "稍后提醒", in: app)
        XCTAssertTrue(delayButton.waitForExistence(timeout: 5))

        let helpButton = app.buttons["elder.action.help"]
        scrollToHittable(helpButton, in: app)
        helpButton.coordinate(withNormalizedOffset: CGVector(dx: 0.03, dy: 0.5)).tap()
        let closeHelp = app.buttons["完成"].firstMatch
        XCTAssertTrue(closeHelp.waitForExistence(timeout: 5))
        closeHelp.tap()
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

    func testElderHasNoSkipAndCompletedActionCanUndo() {
        continueAfterFailure = false
        let app = launchElderFixture()
        XCTAssertFalse(app.buttons["elder.moreActions"].exists)
        XCTAssertFalse(app.buttons["elder.action.skip"].exists)
        tapElderAction("elder.action.taken", in: app)
        assertCompleted(in: app)
        let undo = app.buttons["elder.feedback.undo"]
        XCTAssertTrue(undo.waitForExistence(timeout: 5))
        undo.tap()
        assertCurrentTask("布洛芬", status: "未确认", in: app)
        assertStoredState(in: app, statuses: ["pending"], logCount: 1, saveAttempts: 1)
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
        tapElderAction("elder.action.taken", in: app, confirmCompletion: false)
        XCTAssertTrue(app.buttons["elder.confirmation.confirm"].waitForExistence(timeout: 5))
        tapElderAction("elder.confirmation.cancel", in: app)
        assertCurrentTask("布洛芬", status: "待服用", in: app)
        XCTAssertFalse(app.descendants(matching: .any)["elder.feedback.success"].exists)

        tapElderAction("elder.action.taken", in: app, confirmCompletion: false)
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

    func testElderScheduledDelayCanUndoToOriginalPendingTime() {
        continueAfterFailure = false
        let app = launchElderFixture()
        tapElderAction("elder.action.delay", in: app)
        assertCurrentTask("布洛芬", status: "稍后提醒", in: app)

        let undo = app.buttons["elder.feedback.undo"]
        XCTAssertTrue(undo.waitForExistence(timeout: 5))
        undo.tap()

        assertCurrentTask("布洛芬", status: "未确认", in: app)
        XCTAssertFalse(app.descendants(matching: .any)["elder.feedback.success"].exists)
        let warning = app.descendants(matching: .any)["elder.reminder.warning"]
        XCTAssertTrue(warning.waitForExistence(timeout: 5))
        XCTAssertTrue(warning.label.contains("原提醒时间已过"))
        assertStoredState(in: app, statuses: ["pending"], logCount: 1, saveAttempts: 1)
        XCTAssertEqual(app.staticTexts["elder.test.store.task.0.due-offset"].label, "-300")
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

    func testElderRapidDoubleTapDoesNotCommitAndHoldCommitsOnlyCurrentTask() {
        continueAfterFailure = false
        let app = launchElderFixture(scenario: "multiple")
        let completion = app.buttons["elder.action.taken"]
        scrollToHittable(completion, in: app)
        completion.doubleTap()
        assertStoredState(in: app, statuses: ["pending", "pending"], logCount: 0, saveAttempts: 0)
        restartElderFixture(app)
        scrollToHittable(completion, in: app)
        completion.press(forDuration: 1.4)
        XCTAssertTrue(app.buttons["elder.confirmation.confirm"].waitForExistence(timeout: 5))
        assertStoredState(in: app, statuses: ["pending", "pending"], logCount: 0, saveAttempts: 0)
        restartElderFixture(app)
        scrollToHittable(completion, in: app)
        completion.press(forDuration: 1.4)
        tapElderAction("elder.confirmation.confirm", in: app)
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









    func testElderUsageHelpOpensWithSingleTapWithoutChangingRecordsOrCalling() {
        continueAfterFailure = false
        for scenario in ["help-missing", "help-unavailable", "help-confirmation"] {
            let app = launchElderFixture(scenario: scenario)
            tapElderAction("elder.action.help", in: app)
            let close = app.buttons["完成"].firstMatch
            XCTAssertTrue(close.waitForExistence(timeout: 5))
            close.tap()
            assertCurrentTask("布洛芬", status: "未确认", in: app)
            assertStoredState(in: app, statuses: ["pending"], logCount: 0, saveAttempts: 0, helpAttempts: 0)
        }
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
            XCTAssertTrue(button.exists || button.waitForExistence(timeout: 10), file: file, line: line)
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

    private func tapElderAction(_ identifier: String, in app: XCUIApplication, confirmCompletion: Bool = true) {
        let button = app.buttons[identifier]
        scrollToHittable(button, in: app)
        if identifier == "elder.action.taken" || identifier == "elder.action.delay" {
            button.press(forDuration: 1.4)
            if identifier == "elder.action.taken" && confirmCompletion {
                let confirm = app.buttons["elder.confirmation.confirm"]
                XCTAssertTrue(confirm.waitForExistence(timeout: 5))
                scrollToHittable(confirm, in: app)
                confirm.tap()
            }
        } else {
            button.tap()
        }
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
        XCTAssertTrue(element.exists || element.waitForExistence(timeout: 5), file: file, line: line)
        XCTAssertTrue(element.isEnabled || element.wait(for: \.isEnabled, toEqual: true, timeout: 5), file: file, line: line)
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
                      "Control remained clipped: \(element.frame); viewport: \(visibleViewport(in: app, scrollSurface: scrollSurface))", file: file, line: line)
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
