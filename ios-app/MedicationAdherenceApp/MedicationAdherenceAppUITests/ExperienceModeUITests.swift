import UIKit
import XCTest

/// Every journey owns a writable preference suite and a synthetic on-disk
/// store. No demo rebuild, standard defaults or real phone opener is used.
@MainActor
final class ExperienceModeUITests: XCTestCase {
    private var fixtureArguments: [String] = []

    func testFirstUseCancelCloseBackgroundAndLaterDoNotRepeatOnRestart() throws {
        try requireIPhoneSimulator()
        let app = launchFixture()
        defer { app.terminate() }
        let baseline = readStore(app)
        relaunch(app)
        openFirstChoice(app)
        app.buttons["firstLaunch.mode.elder"].tap()
        try cancelMode(app)
        XCTAssertTrue(app.buttons["firstLaunch.mode.later"].exists)
        app.buttons["firstLaunch.mode.close"].tap()
        XCTAssertTrue(app.buttons["firstLaunch.skip"].waitForExistence(timeout: 5))

        // Closing the choice did not resolve first use or write a mode.
        relaunch(app)
        openFirstChoice(app)
        app.buttons["firstLaunch.mode.elder"].tap()
        XCTAssertTrue(app.alerts["启用适老模式？"].waitForExistence(timeout: 5))
        var transitions: [String] = []
        func record(_ stage: String) {
            transitions.append("\(stage): unix=\(Date().timeIntervalSince1970) "
                + "uptime=\(ProcessInfo.processInfo.systemUptime) state=\(app.state.rawValue)")
        }
        record("before-home")
        XCUIDevice.shared.press(.home)
        // Home is an input event, not proof that the app entered background.
        // Suspension is also a valid background state if it already occurred.
        let backgroundReached = app.wait(for: .runningBackground, timeout: 5)
            || app.wait(for: .runningBackgroundSuspended, timeout: 0)
        let backgroundState = app.state
        let isBackground = backgroundState == .runningBackground || backgroundState == .runningBackgroundSuspended
        record("after-background-wait")
        if !backgroundReached || !isBackground {
            captureBackgroundFailure("background-not-observed", in: app, transitions: transitions)
        }
        XCTAssertTrue(backgroundReached && isBackground, "Observe real background before activating the app")
        app.activate()
        let foregroundReached = app.wait(for: .runningForeground, timeout: 5)
        record("after-foreground-wait")
        if !foregroundReached { captureBackgroundFailure("foreground-not-observed", in: app, transitions: transitions) }
        XCTAssertTrue(foregroundReached)
        let alert = app.alerts["启用适老模式？"]
        let alertGone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: alert)
        let dismissal = XCTWaiter.wait(for: [alertGone], timeout: 5)
        record("after-alert-dismissal-wait")
        if dismissal != .completed { captureBackgroundFailure("confirmation-still-present", in: app, transitions: transitions) }
        XCTAssertEqual(dismissal, .completed, "Real background must invalidate the original confirmation")
        XCTAssertFalse(app.alerts["启用适老模式？"].exists)
        let later = app.buttons["firstLaunch.mode.later"]
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            later.exists && later.isEnabled && later.isHittable
        }, object: nil)
        let readiness = XCTWaiter.wait(for: [ready], timeout: 5)
        record("after-later-readiness-wait")
        if readiness != .completed { captureBackgroundFailure("later-not-interactive", in: app, transitions: transitions) }
        XCTAssertEqual(readiness, .completed, "Later must be actionable after the old confirmation disappears")
        XCTAssertTrue(later.exists)
        XCTAssertTrue(later.isHittable)
        app.buttons["firstLaunch.mode.later"].tap()
        assertComplete(app)
        relaunch(app)
        assertComplete(app)
        XCTAssertFalse(app.buttons["firstLaunch.skip"].exists)
        assertStore(app, equals: baseline)
    }

    func testFirstUseElderRequiresConfirmationAndPersistsAcrossRestart() throws {
        try requireIPhoneSimulator()
        let app = launchFixture()
        defer { app.terminate() }
        let baseline = readStore(app)
        relaunch(app)
        openFirstChoice(app)
        app.buttons["firstLaunch.mode.elder"].tap()
        try cancelMode(app)
        XCTAssertTrue(app.buttons["firstLaunch.mode.elder"].exists)
        app.buttons["firstLaunch.mode.elder"].tap()
        try confirmMode(app, title: "启用适老模式")
        assertElder(app)
        relaunch(app)
        assertElder(app)
        XCTAssertFalse(app.buttons["firstLaunch.skip"].exists)
        XCTAssertFalse(app.buttons["firstLaunch.mode.elder"].exists)
        assertStore(app, equals: baseline)
    }

    func testSettingsEnterAndBothExitPathsConfirmCancelAndPersist() throws {
        try requireIPhoneSimulator()
        let app = launchFixture()
        defer { app.terminate() }
        let baseline = readStore(app)
        relaunch(app)
        openFirstChoice(app)
        app.buttons["firstLaunch.mode.complete"].tap()
        try openCompleteSettings(app)
        try NativeSettingsModeSwitchTestActions.tap(in: app, expectedValue: "0", expectingAlert: "启用适老模式？")
        try cancelMode(app)
        XCTAssertEqual(try modeSwitch(app).value as? String, "0")
        XCTAssertTrue(app.navigationBars["应用设置"].exists)
        try NativeSettingsModeSwitchTestActions.tap(in: app, expectedValue: "0", expectingAlert: "启用适老模式？")
        try confirmMode(app, title: "启用适老模式")
        assertElder(app)
        relaunch(app)
        assertElder(app)

        app.buttons["elder.switch-to-complete"].tap()
        try cancelMode(app)
        assertElder(app)
        app.buttons["elder.settings"].tap()
        try NativeSettingsModeSwitchTestActions.tap(in: app, expectedValue: "1", expectingAlert: "返回完整模式？")
        try cancelMode(app)
        XCTAssertTrue(app.navigationBars["应用设置"].exists)
        XCTAssertEqual(try modeSwitch(app).value as? String, "1")
        try NativeSettingsModeSwitchTestActions.tap(in: app, expectedValue: "1", expectingAlert: "返回完整模式？")
        try confirmMode(app, title: "返回完整模式")
        assertComplete(app)

        try openCompleteSettings(app)
        try NativeSettingsModeSwitchTestActions.tap(in: app, expectedValue: "0", expectingAlert: "启用适老模式？")
        try confirmMode(app, title: "启用适老模式")
        assertElder(app)
        app.buttons["elder.switch-to-complete"].tap()
        try confirmMode(app, title: "返回完整模式")
        assertComplete(app)
        relaunch(app)
        assertComplete(app)
        assertStore(app, equals: baseline)
    }

    func testPendingDoseConfirmationBlocksSettingsAndExitWithoutClearingIt() throws {
        try requireIPhoneSimulator()
        let app = launchFixture(mode: "elder", scenario: "future", completed: true)
        defer { app.terminate() }
        let baseline = readStore(app)
        relaunch(app)
        assertElder(app)
        app.buttons["elder.action.taken"].tap()
        let pending = app.buttons["elder.confirmation.confirm"]
        XCTAssertTrue(pending.waitForExistence(timeout: 5))
        for entry in ["elder.settings", "elder.switch-to-complete"] {
            app.buttons[entry].tap()
            let notice = app.alerts["请先完成当前操作"]
            XCTAssertTrue(notice.waitForExistence(timeout: 5))
            XCTAssertFalse(app.alerts["返回完整模式？"].exists)
            notice.buttons["好"].tap()
            XCTAssertTrue(pending.exists)
            XCTAssertTrue(app.buttons["elder.confirmation.cancel"].exists)
            XCTAssertFalse(app.navigationBars["应用设置"].exists)
        }
        app.buttons["elder.confirmation.cancel"].tap()
        assertStore(app, equals: baseline)
    }

    func testHelpNumberDraftBlocksModeChangeAndRemainsEditable() throws {
        try requireIPhoneSimulator()
        let app = launchFixture(mode: "elder", completed: true)
        defer { app.terminate() }
        let baseline = readStore(app)
        relaunch(app)
        assertElder(app)
        app.buttons["elder.settings"].tap()
        func currentPhone() throws -> XCUIElement {
            try NativeListTestActions.revealSettings(
                identifier: "settings.elder-help.phone", type: .textField, in: app, towardTop: false
            )
        }
        // Each operation verifies the current owner/List and uses an ID-rooted
        // field. Never reuse a field query across focus, typing or dismissal.
        try currentPhone().tap()
        try currentPhone().typeText("12025550123")
        XCTAssertEqual(try currentPhone().value as? String, "12025550123", "The complete draft must exist before testing the guard")
        app.buttons["收起键盘"].tap()
        let keyboardGone = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in app.keyboards.count == 0 }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [keyboardGone], timeout: 5), .completed)
        XCTAssertEqual(try currentPhone().value as? String, "12025550123", "Defocusing must keep the entire draft")
        try NativeSettingsModeSwitchTestActions.tap(in: app, expectedValue: "1", expectingAlert: "请先完成当前操作")
        let notice = app.alerts["请先完成当前操作"]
        XCTAssertTrue(notice.waitForExistence(timeout: 5))
        XCTAssertFalse(app.alerts["返回完整模式？"].exists)
        notice.buttons["好"].tap()
        NativeAlertTestActions.waitForDismissal(of: notice)
        XCTAssertEqual(try currentPhone().value as? String, "12025550123")
        XCTAssertFalse(app.buttons["settings.elder-help.remove"].exists)
        assertStore(app, equals: baseline)
    }

    func testActiveUndoOpportunityBlocksBothNewElderNavigationRequests() throws {
        try requireIPhoneSimulator()
        let app = launchFixture(mode: "elder", completed: true)
        defer { app.terminate() }
        relaunch(app)
        assertElder(app)
        app.buttons["elder.action.taken"].tap()
        let undo = app.buttons["elder.feedback.undo"]
        reveal(undo, in: app)
        for entry in ["elder.settings", "elder.switch-to-complete"] {
            app.buttons[entry].tap()
            let notice = app.alerts["请先完成当前操作"]
            XCTAssertTrue(notice.waitForExistence(timeout: 5))
            notice.buttons["好"].tap()
            XCTAssertTrue(undo.exists, "The active undo opportunity must remain available")
            XCTAssertFalse(app.navigationBars["应用设置"].exists)
            XCTAssertFalse(app.alerts["返回完整模式？"].exists)
        }
        // This journey intentionally committed a medication action. Navigation
        // refusal itself must not create another action or clear the taken task.
        relaunch(app, inspecting: true)
        _ = readStore(app)
        XCTAssertEqual(app.staticTexts["elder.test.store.task.0.status"].label, "taken")
        XCTAssertEqual(app.staticTexts["elder.test.store.log-count"].label, "1")
        XCTAssertEqual(app.staticTexts["elder.test.store.save-attempts"].label, "1")
    }

    func testLocalSkipAndHelpConfirmationsKeepTheirOwnerUntilCancelled() throws {
        try requireIPhoneSimulator()
        let app = launchFixture(mode: "elder", scenario: "help-confirmation", completed: true)
        defer { app.terminate() }
        let baseline = readStore(app)
        relaunch(app)
        assertElder(app)
        app.buttons["elder.moreActions"].tap()
        app.buttons["这次不吃"].tap()
        let skip = app.buttons["确认这次不吃"]
        XCTAssertTrue(skip.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["elder.settings"].isHittable)
        XCTAssertFalse(app.buttons["elder.switch-to-complete"].isHittable)
        try NativeConfirmationDialogTestActions.dismissSkip(in: app)
        app.buttons["elder.action.help"].tap()
        let help = try NativeAlertTestActions.alert(in: app, title: "联系帮助？")
        XCTAssertFalse(app.buttons["elder.settings"].isHittable)
        XCTAssertFalse(app.buttons["elder.switch-to-complete"].isHittable)
        try NativeAlertTestActions.button(in: help, label: "取消").tap()
        assertElder(app)
        app.buttons["elder.switch-to-complete"].tap()
        try cancelMode(app)
        assertStore(app, equals: baseline)
    }

    func testCompletedUsersWithUnknownPreferenceGetCompleteWithoutNewOnboarding() throws {
        try requireIPhoneSimulator()
        let app = launchFixture(completed: true)
        defer { app.terminate() }
        let baseline = readStore(app)
        relaunch(app, extras: ["-appExperienceMode", "future-mode"])
        assertComplete(app)
        XCTAssertFalse(app.buttons["firstLaunch.skip"].exists)
        XCTAssertFalse(app.buttons["firstLaunch.mode.complete"].exists)
        assertStore(app, equals: baseline)
    }

    private func launchFixture(
        mode: String = "complete", scenario: String = "due", completed: Bool = false
    ) -> XCUIApplication {
        continueAfterFailure = false
        fixtureArguments = [
            "--elder-ui-fixture", scenario, "--elder-ui-session", UUID().uuidString,
            "--elder-ui-mode", mode,
            "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryL",
            "-AppPersistenceCommitter.failureMessage", "", "-DoseActionPersistence.failureMessage", ""
        ] + (completed ? ["-hasCompletedFirstLaunchSetup", "YES"] : [])
        let app = XCUIApplication()
        app.launchArguments = fixtureArguments + ["--elder-ui-inspect-store"]
        app.launch()
        return app
    }

    private func relaunch(_ app: XCUIApplication, inspecting: Bool = false, extras: [String] = []) {
        app.terminate()
        app.launchArguments = fixtureArguments + extras + (inspecting ? ["--elder-ui-inspect-store"] : [])
        app.launch()
    }

    private func openFirstChoice(_ app: XCUIApplication) {
        let skip = app.buttons["firstLaunch.skip"]
        XCTAssertTrue(skip.waitForExistence(timeout: 10))
        skip.tap()
        XCTAssertTrue(app.buttons["firstLaunch.mode.complete"].waitForExistence(timeout: 5))
    }

    private func modeSwitch(_ app: XCUIApplication) throws -> XCUIElement {
        try NativeSettingsModeSwitchTestActions.control(in: app)
    }

    private func captureBackgroundFailure(_ reason: String, in app: XCUIApplication, transitions: [String]) {
        // Only this test's exact owned synthetic session may produce an AX dump.
        let arguments = app.launchArguments
        let sessionIndices = arguments.indices.filter { arguments[$0] == "--elder-ui-session" }
        guard arguments == fixtureArguments, arguments.contains("--elder-ui-fixture"),
              sessionIndices.count == 1, let index = sessionIndices.first,
              arguments.indices.contains(index + 1), UUID(uuidString: arguments[index + 1]) != nil else { return }
        let stateBeforeAX = app.state
        // Do not activate a background app just to obtain failure evidence.
        let hierarchy = stateBeforeAX == .runningForeground ? app.debugDescription
            : "AX unavailable: app is not foreground; evidence capture did not activate it"
        let evidence = XCTAttachment(string: (["reason: \(reason)"] + transitions + [
            "capture unix=\(Date().timeIntervalSince1970) uptime=\(ProcessInfo.processInfo.systemUptime)",
            "stateBeforeAX=\(stateBeforeAX.rawValue) stateAfterAX=\(app.state.rawValue)", hierarchy
        ]).joined(separator: "\n\n"))
        evidence.name = "first-use-background-\(reason)"
        evidence.lifetime = .keepAlways
        XCTContext.runActivity(named: "First-use background failure: \(reason)") { $0.add(evidence) }
    }

    private func cancelMode(_ app: XCUIApplication) throws {
        let alert = try NativeAlertTestActions.modeAlert(in: app)
        try NativeAlertTestActions.button(in: alert, label: "取消").tap()
        NativeAlertTestActions.waitForDismissal(of: alert)
    }

    private func confirmMode(_ app: XCUIApplication, title: String) throws {
        let alert = try NativeAlertTestActions.alert(in: app, title: title + "？")
        try NativeAlertTestActions.button(in: alert, label: title).tap()
        NativeAlertTestActions.waitForDismissal(of: alert)
    }

    private func openCompleteSettings(_ app: XCUIApplication) throws {
        assertComplete(app)
        try CompleteModeTestNavigation.openSettings(in: app)
    }

    private func assertComplete(_ app: XCUIApplication) {
        CompleteModeTestNavigation.assertToday(in: app)
        XCTAssertFalse(app.buttons["today.elder-mode-entry"].exists)
        XCTAssertFalse(app.buttons["elder.switch-to-complete"].exists)
    }

    private func assertElder(_ app: XCUIApplication) {
        XCTAssertTrue(app.buttons["elder.switch-to-complete"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.tabBars.firstMatch.exists)
    }

    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<6 {
            if element.exists && element.isHittable { return }
            app.swipeUp()
        }
        for _ in 0..<6 {
            if element.exists && element.isHittable { return }
            app.swipeDown()
        }
        XCTAssertTrue(element.waitForExistence(timeout: 5))
        XCTAssertTrue(element.isHittable)
    }

    private func readStore(_ app: XCUIApplication) -> [String: String] {
        let prefix = "elder.test.store."
        XCTAssertTrue(app.staticTexts[prefix + "task-count"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.staticTexts[prefix + "task-count"].label, "1")
        XCTAssertFalse(app.staticTexts[prefix + "error"].exists)
        let fields = ["task-count", "log-count", "help-attempts", "save-attempts", "schedule-attempts",
                      "task.0.id", "task.0.status", "task.0.due-offset"]
        var result: [String: String] = [:]
        for field in fields {
            XCTAssertTrue(app.staticTexts[prefix + field].exists)
            result[field] = app.staticTexts[prefix + field].label
        }
        return result
    }

    private func assertStore(_ app: XCUIApplication, equals baseline: [String: String]) {
        relaunch(app, inspecting: true)
        XCTAssertEqual(readStore(app), baseline, "Mode navigation must not modify the medication store or action counters")
    }

    private func requireIPhoneSimulator() throws {
        #if targetEnvironment(simulator)
        guard UIDevice.current.userInterfaceIdiom == .phone else {
            throw XCTSkip("This isolated fixture journey targets iPhone; the iPad lane remains paused")
        }
        #else
        throw XCTSkip("Synthetic fixture journeys require simulator-only store isolation")
        #endif
    }
}

/// Follows PR162's observed native TabBar/Toolbar routes. Exact app labels are
/// scoped to those containers; no device-name branch, positional fifth tab,
/// arbitrary matching button, or guessed Profile toolbar symbol is accepted.
@MainActor
enum CompleteModeTestNavigation {
    static func assertToday(in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        let tab = entry(label: "今日", in: app, file: file, line: line)
        let today = app.descendants(matching: .any).matching(identifier: "tab.today")
        XCTAssertTrue(today.firstMatch.waitForExistence(timeout: 10), file: file, line: line)
        XCTAssertTrue(tab.isSelected, "The native Today entry must be selected", file: file, line: line)
        XCTAssertTrue(app.staticTexts["today.timeline.open"].exists,
                      "Complete mode must display the actual Today timeline", file: file, line: line)
        XCTAssertFalse(app.buttons["elder.switch-to-complete"].exists, file: file, line: line)
    }

    static func openProfile(in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        let tab = entry(label: "个人", in: app, file: file, line: line)
        tab.tap()
        let profile = app.descendants(matching: .any).matching(identifier: "profile.root")
        XCTAssertTrue(profile.firstMatch.waitForExistence(timeout: 10), file: file, line: line)
        XCTAssertEqual(profile.count, 1, "The real Profile page must be unique", file: file, line: line)
        XCTAssertTrue(app.descendants(matching: .any)["tab.profile"].exists, file: file, line: line)
        XCTAssertTrue(tab.isSelected, "The native Profile entry must become selected", file: file, line: line)
    }

    static func openSettings(in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) throws {
        openProfile(in: app, file: file, line: line)
        let entries = app.buttons.matching(identifier: "profile.settings")
        let settings = entries.element(boundBy: 0)
        try NativeListTestActions.reveal(settings, in: app, towardTop: false)
        XCTAssertEqual(entries.count, 1, "The real settings route must be unique", file: file, line: line)
        XCTAssertTrue(settings.isHittable, file: file, line: line)
        settings.tap()
        XCTAssertTrue(app.navigationBars["应用设置"].waitForExistence(timeout: 5), file: file, line: line)
        XCTAssertTrue(app.switches["settings.experience-mode"].waitForExistence(timeout: 5), file: file, line: line)
    }

    private static func entry(
        label: String, in app: XCUIApplication, file: StaticString, line: UInt
    ) -> XCUIElement {
        let predicate = NSPredicate(format: "label == %@", label)
        let bottom = app.tabBars.buttons.matching(predicate)
        let side = app.toolbars.buttons.matching(predicate)
        let available = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            guard bottom.count <= 1 && side.count <= 1 else { return false }
            let bottomHittable = bottom.count == 1 && bottom.firstMatch.isHittable
            let sideHittable = side.count == 1 && side.firstMatch.isHittable
            return bottomHittable != sideHittable
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [available], timeout: 10), .completed,
                       "Exactly one hittable native \(label) entry must exist in TabBar or Toolbar",
                       file: file, line: line)
        let entries = bottom.count == 1 && bottom.firstMatch.isHittable ? bottom : side
        XCTAssertLessThanOrEqual(bottom.count, 1, file: file, line: line)
        XCTAssertLessThanOrEqual(side.count, 1, file: file, line: line)
        XCTAssertEqual(entries.count, 1, file: file, line: line)
        XCTAssertTrue(entries.firstMatch.isHittable, file: file, line: line)
        let hittableCount = (bottom.count == 1 && bottom.firstMatch.isHittable ? 1 : 0)
            + (side.count == 1 && side.firstMatch.isHittable ? 1 : 0)
        XCTAssertEqual(hittableCount, 1, "Do not choose between ambiguous native entries", file: file, line: line)
        return entries.firstMatch
    }
}
