import XCTest

@MainActor
final class PlanPermissionPrimerUITests: XCTestCase {
    private enum ReminderPath {
        case notification, alarm, escalation

        var usesAlarmPrimer: Bool { self != .notification }
    }

    func testNotificationPrimerCancellationKeepsDraftAndAllowsRetry() {
        assertCancellationRecovery(path: .notification)
    }

    func testAlarmPrimerCancellationKeepsDraftAndAllowsRetry() {
        assertCancellationRecovery(path: .alarm)
    }

    func testEscalationPrimerCancellationKeepsDraftAndAllowsRetry() {
        assertCancellationRecovery(path: .escalation)
    }

    private func assertCancellationRecovery(path: ReminderPath) {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = [
            "--elder-ui-fixture", "due",
            "--elder-ui-session", UUID().uuidString,
            "--elder-ui-mode", "complete",
            "--plan-permission-primer-ui-test",
            "-hasCompletedFirstLaunchSetup", "YES",
            "-AppleLanguages", "(zh-Hans)",
            "-AppleLocale", "zh_CN",
            "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryL",
            "-AppPersistenceCommitter.failureMessage", "",
            "-DoseActionPersistence.failureMessage", ""
        ]
        if path == .escalation {
            app.launchArguments.append("--plan-permission-primer-notification-authorized")
        }
        app.launch()
        defer { app.terminate() }

        let medication = app.staticTexts["timeline.medication-name"]
        XCTAssertTrue(medication.waitForExistence(timeout: 10))
        scrollToHittable(medication, in: app)
        medication.tap()
        XCTAssertTrue(app.navigationBars["药品详情"].waitForExistence(timeout: 5))

        let editPlan = app.buttons["修改疗程与提醒"]
        scrollToHittable(editPlan, in: app)
        editPlan.tap()
        let save = app.buttons["medication.plan.save"]
        XCTAssertTrue(save.waitForExistence(timeout: 5))

        if path == .alarm {
            let deliveryMethod = app.descendants(matching: .any)
                .matching(identifier: "medication.plan.delivery-method").firstMatch
            scrollToHittable(deliveryMethod, in: app)
            deliveryMethod.tap()
            let option = app.buttons["iPhone 闹钟"]
            XCTAssertTrue(option.waitForExistence(timeout: 5))
            option.tap()
        } else if path == .escalation {
            let escalation = app.switches["medication.plan.escalation"]
            scrollToHittable(escalation, in: app)
            XCTAssertEqual(escalation.value as? String, "0")
            XCTAssertFalse(escalation.frame.isEmpty)
            // Tap the trailing switch track in this fixed Chinese/LTR fixture;
            // the automatic hit point may land on the Toggle's long label.
            escalation.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
            XCTAssertEqual(escalation.value as? String, "1", "Escalation switch frame: \(escalation.frame)")
        }

        let note = app.textViews["medication.plan.source-note"]
        scrollToHittable(note, in: app)
        let originalNote = note.value as? String
        XCTAssertNotNil(originalNote)
        let draft = "2468135790"
        note.tap()
        note.typeText(draft)
        let expectedNote = (originalNote ?? "") + draft
        XCTAssertEqual(note.value as? String, expectedNote)

        for attempt in 1...2 {
            XCTAssertTrue(save.isEnabled, "Save must be available before attempt \(attempt)")
            save.tap()
            let primer = app.alerts[path.usesAlarmPrimer ? "开启 iPhone 闹钟" : "开启服药通知"]
            XCTAssertTrue(primer.waitForExistence(timeout: 5))
            primer.buttons["暂不开启"].tap()
            XCTAssertTrue(primer.waitForNonExistence(timeout: 5))
            let enabled = XCTNSPredicateExpectation(
                predicate: NSPredicate(format: "enabled == true"), object: save
            )
            XCTAssertEqual(XCTWaiter.wait(for: [enabled], timeout: 5), .completed)
            XCTAssertEqual(note.value as? String, expectedNote, "Cancelling must retain the unsaved draft")
        }

        // Continue must still reach the request/denial branch, rather than
        // accidentally calling the cancellation callback when the gate clears.
        save.tap()
        let primer = app.alerts[path.usesAlarmPrimer ? "开启 iPhone 闹钟" : "开启服药通知"]
        XCTAssertTrue(primer.waitForExistence(timeout: 5))
        primer.buttons[path.usesAlarmPrimer ? "同意并开启闹钟" : "同意并开启通知"].tap()
        XCTAssertTrue(primer.waitForNonExistence(timeout: 5))
        let denialMessage = app.staticTexts[path.usesAlarmPrimer
            ? "iPhone 闹钟权限未开启，暂不能保存为闹钟提醒。"
            : "通知权限未开启，暂不能保存为推送提醒。"]
        scrollToHittable(denialMessage, in: app, upward: false)
        XCTAssertTrue(save.isEnabled)
        scrollToHittable(note, in: app)
        XCTAssertEqual(note.value as? String, expectedNote)

        // Ordinary editor Cancel discards the draft; neither primer cancellation
        // may have persisted it or changed the existing medication plan.
        app.navigationBars["疗程与提醒"].buttons["取消"].tap()
        XCTAssertTrue(save.waitForNonExistence(timeout: 5))
        scrollToHittable(editPlan, in: app)
        editPlan.tap()
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        scrollToHittable(note, in: app)
        XCTAssertEqual(note.value as? String, originalNote)
        app.navigationBars["疗程与提醒"].buttons["取消"].tap()
    }

    private func scrollToHittable(_ element: XCUIElement, in app: XCUIApplication, upward: Bool = true) {
        for _ in 0..<10 {
            if element.exists && element.isHittable { return }
            if upward { app.swipeUp() } else { app.swipeDown() }
        }
        XCTAssertTrue(element.waitForExistence(timeout: 5))
        XCTAssertTrue(element.isHittable)
    }
}
