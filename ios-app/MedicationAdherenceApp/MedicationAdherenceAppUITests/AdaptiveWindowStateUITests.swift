import UIKit
import XCTest

/// Rotation-driven window changes on iPad only. This is not evidence for arbitrary
/// Split View/Stage Manager resizing or a future foldable device.
/// The existing inspection fixture exposes task UUIDs/statuses and total log
/// counts, but not medication/plan IDs or each log's associated task ID.
@MainActor
final class AdaptiveWindowStateUITests: XCTestCase {
    func testEarlyConfirmationSurvivesWindowChangesAndCancelThenCommitKeepsOneTask() throws {
        try requireIPad()
        let originalOrientation = XCUIDevice.shared.orientation
        defer { XCUIDevice.shared.orientation = originalOrientation }
        let app = launchFixture(scenario: "future")
        defer { app.terminate() }
        let taskIDs = try readTaskIDs(in: app, count: 1)
        assertStore(in: app, taskIDs: taskIDs, statuses: ["pending"], logs: 0, attempts: 0)
        relaunch(app, inspecting: false)
        establishRotatingWindow(in: app)

        assertCurrentTask("布洛芬", status: "待服用", in: app)
        tap("elder.action.taken", in: app)
        assertConfirmation(in: app)
        rotateWindow(in: app, to: .landscapeLeft)
        assertCurrentTask("布洛芬", status: "待服用", in: app)
        assertConfirmation(in: app)
        tap("elder.confirmation.cancel", in: app)
        XCTAssertTrue(app.buttons["elder.confirmation.confirm"].waitForNonExistence(timeout: 5))
        XCTAssertFalse(app.descendants(matching: .any)["elder.feedback.success"].exists)
        assertCurrentTask("布洛芬", status: "待服用", in: app)
        relaunch(app, inspecting: true)
        assertStore(in: app, taskIDs: taskIDs, statuses: ["pending"], logs: 0, attempts: 0)

        relaunch(app, inspecting: false)
        assertCurrentTask("布洛芬", status: "待服用", in: app)
        tap("elder.action.taken", in: app)
        assertConfirmation(in: app)
        rotateWindow(in: app, to: .portrait)
        assertCurrentTask("布洛芬", status: "待服用", in: app)
        assertConfirmation(in: app)
        tap("elder.confirmation.confirm", in: app)
        XCTAssertTrue(app.staticTexts["今日用药已完成"].waitForExistence(timeout: 10))
        rotateWindow(in: app, to: .landscapeLeft)
        XCTAssertTrue(app.staticTexts["今日用药已完成"].exists)
        XCTAssertFalse(app.buttons["elder.action.taken"].exists)
        relaunch(app, inspecting: true)
        assertStore(in: app, taskIDs: taskIDs, statuses: ["taken"], logs: 1, attempts: 1)
    }

    func testFailedSaveAndNextTaskSelectionSurviveWindowChanges() throws {
        try requireIPad()
        let originalOrientation = XCUIDevice.shared.orientation
        defer { XCUIDevice.shared.orientation = originalOrientation }
        let app = launchFixture(scenario: "multiple", failsFirstSave: true)
        defer { app.terminate() }
        let taskIDs = try readTaskIDs(in: app, count: 2)
        assertStore(in: app, taskIDs: taskIDs, statuses: ["pending", "pending"], logs: 0, attempts: 0)
        relaunch(app, inspecting: false)
        establishRotatingWindow(in: app)

        assertCurrentTask("布洛芬", status: "未确认", in: app)
        tap("elder.action.taken", in: app)
        let alert = app.alerts["用药记录未保存"]
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        rotateWindow(in: app, to: .landscapeLeft)
        XCTAssertTrue(alert.exists, "A window change must not dismiss the save failure")
        assertReachable(alert.buttons["好"], in: app)
        alert.buttons["好"].tap()
        assertCurrentTask("布洛芬", status: "未确认", in: app)
        XCTAssertFalse(app.descendants(matching: .any)["elder.feedback.success"].exists)
        // Keep the same process and the failure-injection argument: the fixture
        // fails only its first save, so this exercises recovery without a reset.
        rotateWindow(in: app, to: .portrait)
        assertCurrentTask("布洛芬", status: "未确认", in: app)
        tap("elder.action.taken", in: app)
        assertCurrentTask("人工泪液", status: "未确认", in: app)
        rotateWindow(in: app, to: .landscapeLeft)
        assertCurrentTask("人工泪液", status: "未确认", in: app)
        assertReachable("elder.action.taken", in: app)
        relaunch(app, inspecting: true)
        assertStore(in: app, taskIDs: taskIDs, statuses: ["taken", "pending"], logs: 1, attempts: 2)
    }

    func testFailedSaveAcrossWindowChangeLeavesNoDurableLog() throws {
        try requireIPad()
        let originalOrientation = XCUIDevice.shared.orientation
        defer { XCUIDevice.shared.orientation = originalOrientation }
        let app = launchFixture(scenario: "due", failsFirstSave: true)
        defer { app.terminate() }
        let taskIDs = try readTaskIDs(in: app, count: 1)
        assertStore(in: app, taskIDs: taskIDs, statuses: ["pending"], logs: 0, attempts: 0)
        relaunch(app, inspecting: false)
        establishRotatingWindow(in: app)

        assertCurrentTask("布洛芬", status: "未确认", in: app)
        tap("elder.action.taken", in: app)
        let alert = app.alerts["用药记录未保存"]
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        rotateWindow(in: app, to: .landscapeLeft)
        XCTAssertTrue(alert.exists)
        assertReachable(alert.buttons["好"], in: app)
        alert.buttons["好"].tap()
        assertCurrentTask("布洛芬", status: "未确认", in: app)
        XCTAssertFalse(app.descendants(matching: .any)["elder.feedback.success"].exists)
        // Separate from the same-process retry test: restarting here is necessary
        // to inspect durable rollback using the existing read-only fixture.
        relaunch(app, inspecting: true)
        assertStore(in: app, taskIDs: taskIDs, statuses: ["pending"], logs: 0, attempts: 1)
    }

    private func requireIPad() throws {
        continueAfterFailure = false
        #if targetEnvironment(simulator)
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .pad,
                          "Requires iPad Simulator: the app supports only portrait on iPhone.")
        #else
        throw XCTSkip("The isolated fixture is only exercised on iPad Simulator, not physical devices.")
        #endif
    }

    private func launchFixture(scenario: String, failsFirstSave: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-AppPersistenceCommitter.failureMessage", "",
            "-DoseActionPersistence.failureMessage", "",
            "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryL",
            "-hasCompletedFirstLaunchSetup", "YES",
            "--elder-ui-mode", "elder",
            "--elder-ui-fixture", scenario,
            "--elder-ui-session", UUID().uuidString,
            "--elder-ui-inspect-store"
        ]
        if failsFirstSave { app.launchArguments.append("--elder-ui-fail-first-save") }
        app.launch()
        return app
    }

    private func relaunch(_ app: XCUIApplication, inspecting: Bool) {
        app.terminate()
        app.launchArguments.removeAll { $0 == "--elder-ui-inspect-store" }
        if inspecting { app.launchArguments.append("--elder-ui-inspect-store") }
        app.launch()
    }

    private func establishRotatingWindow(in app: XCUIApplication) {
        XCTAssertTrue(app.buttons["elder.action.taken"].waitForExistence(timeout: 10))
        XCUIDevice.shared.orientation = .portrait
        let portraitReady = waitForWindow(in: app) { $0.height > $0.width }
        XCTAssertTrue(portraitReady, "The supported iPad Simulator must establish portrait geometry")
        let portrait = app.windows.firstMatch.frame
        XCUIDevice.shared.orientation = .landscapeLeft
        let changed = waitForWindow(in: app) {
            $0.width > $0.height && abs($0.width - portrait.width) > 40
                && abs($0.height - portrait.height) > 40
        }
        XCTAssertTrue(changed, "The supported iPad Simulator must resize on rotation; orientation assignment alone is not coverage")
        rotateWindow(in: app, to: .portrait)
    }

    private func rotateWindow(in app: XCUIApplication, to orientation: UIDeviceOrientation) {
        let before = app.windows.firstMatch.frame
        let landscape = orientation.isLandscape
        XCUIDevice.shared.orientation = orientation
        XCTAssertTrue(waitForWindow(in: app) { frame in
            let aspectMatches = landscape ? frame.width > frame.height : frame.height > frame.width
            return aspectMatches && abs(frame.width - before.width) > 40
                && abs(frame.height - before.height) > 40
        }, "The active flow must experience a measured window width and height change")
        let geometry = XCTAttachment(string: "Before: \(before); after: \(app.windows.firstMatch.frame)")
        geometry.name = "measured-window-change"
        geometry.lifetime = .keepAlways
        add(geometry)
    }

    private func waitForWindow(in app: XCUIApplication, matching condition: @escaping (CGRect) -> Bool) -> Bool {
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate { object, _ in
                guard let window = object as? XCUIElement, window.exists else { return false }
                return condition(window.frame)
            },
            object: app.windows.firstMatch
        )
        return XCTWaiter.wait(for: [expectation], timeout: 10) == .completed
    }

    private func assertCurrentTask(_ name: String, status: String, in app: XCUIApplication) {
        let card = app.otherElements["elder.current-task"]
        for text in [name, status] {
            XCTAssertTrue(card.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", text))
                .firstMatch.waitForExistence(timeout: 10), "Current task must retain \(text)")
        }
    }

    private func assertConfirmation(in app: XCUIApplication) {
        assertReachable("elder.confirmation.confirm", in: app)
        assertReachable("elder.confirmation.cancel", in: app)
    }

    private func assertReachable(_ identifier: String, in app: XCUIApplication) {
        assertReachable(app.buttons[identifier], in: app)
    }

    private func assertReachable(_ button: XCUIElement, in app: XCUIApplication) {
        let window = app.windows.firstMatch
        let reachable = XCTNSPredicateExpectation(
            predicate: NSPredicate { object, _ in
                guard let button = object as? XCUIElement else { return false }
                return button.exists && button.isEnabled && button.isHittable
                    && window.frame.contains(button.frame)
            },
            object: button
        )
        XCTAssertEqual(XCTWaiter.wait(for: [reachable], timeout: 5), .completed,
                       "\(button.identifier) must become enabled, hittable and fully inside the window")
    }

    private func tap(_ identifier: String, in app: XCUIApplication) {
        assertReachable(identifier, in: app)
        app.buttons[identifier].tap()
    }

    private func readTaskIDs(in app: XCUIApplication, count: Int) throws -> [UUID] {
        XCTAssertTrue(app.staticTexts["elder.test.store.task-count"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.staticTexts["elder.test.store.task-count"].label, String(count))
        return try (0..<count).map { index in
            try XCTUnwrap(UUID(uuidString: app.staticTexts["elder.test.store.task.\(index).id"].label))
        }
    }

    private func assertStore(in app: XCUIApplication, taskIDs: [UUID], statuses: [String], logs: Int, attempts: Int) {
        XCTAssertTrue(app.staticTexts["elder.test.store.log-count"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["elder.test.store.error"].exists)
        XCTAssertEqual(app.staticTexts["elder.test.store.task-count"].label, String(taskIDs.count))
        XCTAssertEqual(app.staticTexts["elder.test.store.log-count"].label, String(logs))
        XCTAssertEqual(app.staticTexts["elder.test.store.save-attempts"].label, String(attempts))
        XCTAssertEqual(app.staticTexts["elder.test.store.schedule-attempts"].label, "0")
        for (index, id) in taskIDs.enumerated() {
            XCTAssertEqual(app.staticTexts["elder.test.store.task.\(index).id"].label, id.uuidString)
            XCTAssertEqual(app.staticTexts["elder.test.store.task.\(index).status"].label, statuses[index])
        }
    }
}
