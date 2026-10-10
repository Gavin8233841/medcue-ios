import UIKit
import XCTest

/// Explicit simulator synthetic sessions only. These journeys are not native passes until executed.
#if (DEBUG || MEDCUE_DEMO) && targetEnvironment(simulator)
@MainActor
final class BundledDemoUITests: XCTestCase {
    func testMalformedOrConflictingDemoRequestCannotExposePrimaryRecovery() throws {
        try requireSimulator()
        continueAfterFailure = false
        for arguments in [["--bundled-demo-session", "invalid"],
                          ["--bundled-demo-session", UUID().uuidString, "--seed-demo-data"],
                          ["--bundled-demo-session", UUID().uuidString, "--medical-ai-smoke-test"]] {
            let app = XCUIApplication()
            app.launchArguments = arguments
            app.launch()
            defer { app.terminate() }
            XCTAssertTrue(app.staticTexts["demo.startup.error"].waitForExistence(timeout: 5))
            XCTAssertFalse(app.buttons["重试读取原记录"].exists)
            XCTAssertFalse(app.buttons["保存敏感原始副本"].exists)
            XCTAssertFalse(app.buttons["导出脱敏诊断信息"].exists)
            XCTAssertFalse(app.buttons["demo.settings.open"].exists)
            XCTAssertFalse(app.otherElements["profile.root"].exists)
        }
    }

    func testDemoModeNeedsConfirmationAndPersistsInItsOwnSession() throws {
        try requireSimulator()
        let app = launch()
        defer { app.terminate() }
        assertFiveTodayTasks(app)
        try assertHeaderEnabled(true, in: app)
        openSettings(app)
        try toggleMode(app, before: "0")
        let enable = try NativeAlertTestActions.alert(in: app, title: "启用适老模式？")
        try NativeAlertTestActions.button(in: enable, label: "取消", diagnosticApp: app).tap()
        XCTAssertEqual(try modeSwitch(app).value as? String, "0")
        try toggleMode(app, before: "0")
        let confirmed = try NativeAlertTestActions.alert(in: app, title: "启用适老模式？")
        try NativeAlertTestActions.button(in: confirmed, label: "启用适老模式", diagnosticApp: app).tap()
        XCTAssertTrue(app.buttons["elder.action.taken"].waitForExistence(timeout: 5))
        try assertHeaderEnabled(true, in: app)
        let arguments = app.launchArguments
        app.terminate()
        app.launchArguments = arguments
        app.launch()
        XCTAssertTrue(app.buttons["elder.action.taken"].waitForExistence(timeout: 5))
        assertFiveTodayTasks(app)
        try assertHeaderEnabled(true, in: app)
        openSettings(app)
        try toggleMode(app, before: "1")
        let exit = try NativeAlertTestActions.alert(in: app, title: "返回完整模式？")
        try NativeAlertTestActions.button(in: exit, label: "返回完整模式", diagnosticApp: app).tap()
        XCTAssertFalse(app.buttons["elder.action.taken"].exists)
        XCTAssertTrue(app.staticTexts["demo.synthetic-marker"].exists)
        try assertHeaderEnabled(true, in: app)
    }

    func testEachAllowedElderActionCommitsOnceAndUndoRemainsDisabled() throws {
        try requireSimulator()
        for action in ["taken", "delay", "skip"] {
            let app = launch()
            defer { app.terminate() }
            try enterElder(app)
            if action == "skip" {
                let menu = app.buttons["elder.moreActions"]
                XCTAssertTrue(menu.isHittable)
                menu.tap()
                try uniqueLeaf(label: "这次不吃", in: app, diagnosticApp: app).tap()
                try uniqueLeaf(label: "确认这次不吃", in: app, diagnosticApp: app).tap()
            } else {
                let button = app.buttons["elder.action." + (action == "taken" ? "taken" : "delay")]
                XCTAssertTrue(button.isHittable)
                button.tap()
                let confirmation = app.buttons["elder.confirmation.confirm"]
                let result = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                    let committed = (app.staticTexts["demo.store.inspection"].value as? String)?
                        .components(separatedBy: ";").contains("logs=1") == true
                    return committed || confirmation.exists
                }, object: app)
                XCTAssertEqual(XCTWaiter.wait(for: [result], timeout: 5), .completed)
                if confirmation.exists {
                    XCTAssertTrue(confirmation.isHittable)
                    confirmation.tap()
                }
            }
            waitStore("logs=1", app: app)
            waitStore((action == "delay" ? "delayed" : action == "skip" ? "skipped" : "taken") + "=1", app: app)
            XCTAssertTrue(app.staticTexts["demo.synthetic-marker"].exists)
            let undo = app.buttons["elder.feedback.undo"]
            if undo.exists { XCTAssertFalse(undo.isEnabled) }
            let before = app.staticTexts["demo.store.inspection"].value as? String
            openSettings(app)
            app.buttons["demo.settings.done"].tap()
            XCTAssertEqual(app.staticTexts["demo.store.inspection"].value as? String, before)
        }
    }

    func testExitIsConfirmedAndReopenRetainsTheOwnedStore() throws {
        try requireSimulator()
        let app = launch()
        defer { app.terminate() }
        assertFiveTodayTasks(app)
        try enterElder(app)
        let baseline = app.staticTexts["demo.store.inspection"].value as? String
        XCTAssertNotNil(baseline)
        try assertHeaderEnabled(true, in: app)
        app.buttons["elder.moreActions"].tap()
        try uniqueLeaf(label: "这次不吃", in: app, diagnosticApp: app).tap()
        XCTAssertTrue(app.buttons["确认这次不吃"].waitForExistence(timeout: 5))
        // Covered controls are not sufficient evidence: require the actual
        // header controls to be present and explicitly disabled by their guard.
        try assertHeaderEnabled(false, in: app)
        XCTAssertFalse(app.navigationBars["演示设置"].exists)
        XCTAssertFalse(app.alerts["退出合成演示？"].exists)
        try NativeConfirmationDialogTestActions.dismissSkip(in: app)
        try assertHeaderEnabled(true, in: app)
        XCTAssertEqual(app.staticTexts["demo.store.inspection"].value as? String, baseline)
        openSettings(app)
        XCTAssertEqual(try modeSwitch(app).value as? String, "1")
        app.buttons["demo.settings.done"].tap()
        XCTAssertEqual(app.staticTexts["demo.store.inspection"].value as? String, baseline)
        app.buttons["demo.exit.open"].tap()
        let cancel = try NativeAlertTestActions.alert(in: app, title: "退出合成演示？")
        try uniqueLeaf(label: "取消", in: cancel, diagnosticApp: app).tap()
        XCTAssertFalse(app.staticTexts["demo.closed"].exists)
        app.buttons["demo.exit.open"].tap()
        let exit = try NativeAlertTestActions.alert(in: app, title: "退出合成演示？")
        try uniqueLeaf(label: "退出演示", in: exit, diagnosticApp: app).tap()
        XCTAssertTrue(app.staticTexts["demo.closed"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["demo.settings.open"].exists)
        XCTAssertFalse(app.buttons["重试读取原记录"].exists)
        app.buttons["demo.reopen"].tap()
        assertFiveTodayTasks(app)
        XCTAssertTrue(app.buttons["elder.action.taken"].waitForExistence(timeout: 5))
        try assertHeaderEnabled(true, in: app)
        XCTAssertEqual(app.staticTexts["demo.store.inspection"].value as? String, baseline)
    }

    private func assertHeaderEnabled(_ enabled: Bool, in app: XCUIApplication) throws {
        for identifier in ["demo.settings.open", "demo.exit.open"] {
            let matches = app.buttons.matching(identifier: identifier)
            XCTAssertEqual(matches.count, 1, "Header AX owner must remain observable; absence is not guard evidence")
            guard matches.count == 1 else { throw LookupFailure.ambiguous }
            let button = matches.element(boundBy: 0)
            XCTAssertEqual(button.descendants(matching: .button).count, 0)
            let expected = XCTNSPredicateExpectation(
                predicate: NSPredicate(format: "enabled == %@", NSNumber(value: enabled)), object: button
            )
            XCTAssertEqual(XCTWaiter.wait(for: [expected], timeout: 5), .completed)
            XCTAssertEqual(button.isEnabled, enabled)
        }
    }

    private func launch() -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--bundled-demo-session", UUID().uuidString, "--bundled-demo-inspect-store"]
        app.launch()
        XCTAssertTrue(app.staticTexts["demo.synthetic-marker"].waitForExistence(timeout: 5))
        return app
    }

    private func assertFiveTodayTasks(_ app: XCUIApplication) {
        waitStore("medications=5", app: app)
        waitStore("tasks=305", app: app)
        waitStore("today=5", app: app)
        waitStore("pending=5", app: app)
        waitStore("logs=0", app: app)
    }

    private func waitStore(_ value: String, app: XCUIApplication) {
        let element = app.staticTexts["demo.store.inspection"]
        XCTAssertTrue(element.waitForExistence(timeout: 5))
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate { object, _ in
            (object as? XCUIElement)?.value as? String != nil
                && ((object as? XCUIElement)?.value as? String)?.components(separatedBy: ";").contains(value) == true
        }, object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 5), .completed)
    }

    private func openSettings(_ app: XCUIApplication) {
        let button = app.buttons["demo.settings.open"]
        XCTAssertTrue(button.isEnabled, "A hittable disabled header is not usable Settings")
        XCTAssertTrue(button.isHittable)
        button.tap()
        let settingsReady = app.navigationBars["演示设置"].waitForExistence(timeout: 5)
        if !settingsReady { SyntheticCompatibilityDiagnostics.demoSettings(app: app) }
        XCTAssertTrue(settingsReady)
    }

    private func enterElder(_ app: XCUIApplication) throws {
        openSettings(app)
        try toggleMode(app, before: "0")
        let alert = try NativeAlertTestActions.alert(in: app, title: "启用适老模式？")
        try NativeAlertTestActions.button(in: alert, label: "启用适老模式", diagnosticApp: app).tap()
        XCTAssertTrue(app.buttons["elder.action.taken"].waitForExistence(timeout: 5))
    }

    private func toggleMode(_ app: XCUIApplication, before value: String) throws {
        let control = try modeSwitch(app)
        XCTAssertEqual(control.value as? String, value)
        XCTAssertTrue(control.isHittable)
        control.tap()
    }

    private func modeSwitch(_ app: XCUIApplication) throws -> XCUIElement {
        let rows = app.switches.matching(identifier: "demo.settings.elder")
        XCTAssertEqual(rows.count, 1)
        guard rows.count == 1 else { throw LookupFailure.ambiguous }
        let row = rows.element(boundBy: 0)
        let direct = row.children(matching: .switch)
        XCTAssertLessThanOrEqual(direct.count, 1)
        if direct.count == 1 {
            XCTAssertEqual(row.descendants(matching: .switch).count, 1)
            return direct.element(boundBy: 0)
        }
        XCTAssertEqual(row.descendants(matching: .switch).count, 0)
        return row
    }

    private func uniqueLeaf(label: String, in owner: XCUIElement, diagnosticApp app: XCUIApplication) throws -> XCUIElement {
        let leaves = owner.buttons.matching(NSPredicate(format: "label == %@", label)).allElementsBoundByIndex.filter {
            $0.descendants(matching: .button).matching(NSPredicate(format: "label == %@", label)).count == 0
        }
        if leaves.count != 1 {
            SyntheticCompatibilityDiagnostics.action(owner: owner, label: label, leaves: leaves.count,
                                                     app: app, nativeIdentifierRule: false)
        }
        XCTAssertEqual(leaves.count, 1)
        guard leaves.count == 1, let leaf = leaves.first else { throw LookupFailure.ambiguous }
        XCTAssertTrue(leaf.isHittable)
        return leaf
    }

    private func requireSimulator() throws {
        #if !targetEnvironment(simulator)
        throw XCTSkip("Bundled demo is a simulator-only debug boundary")
        #endif
    }
    private enum LookupFailure: Error { case ambiguous }
}
#endif
