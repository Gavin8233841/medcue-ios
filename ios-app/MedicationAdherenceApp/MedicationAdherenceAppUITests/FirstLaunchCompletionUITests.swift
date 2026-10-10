import UIKit
import XCTest

/// Uses the existing session-owned store and writable preference suite. No
/// launch-argument override masks the first-launch completion preference.
@MainActor
final class FirstLaunchCompletionUITests: XCTestCase {
    private var fixtureArguments: [String] = []

    func testInitialSkipPersistsAndForcedReplayKeepsElderModeAndStore() throws {
        try requireIPhoneSimulator()
        let app = launchFixture(mode: "elder")
        defer { app.terminate() }
        let initialStore = try readStore(in: app)

        relaunch(app)
        let skip = app.buttons["firstLaunch.skip"]
        XCTAssertTrue(skip.waitForExistence(timeout: 10))
        XCTAssertEqual(skip.label, "跳过")
        skip.tap()
        app.buttons["firstLaunch.mode.elder"].tap()
        let enableAlert = try NativeAlertTestActions.alert(in: app, title: "启用适老模式？")
        try NativeAlertTestActions.button(in: enableAlert, label: "启用适老模式").tap()
        XCTAssertTrue(app.buttons["elder.switch-to-complete"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["用药跟踪"].exists)

        // A real process restart must read the stored first-use completion.
        relaunch(app)
        XCTAssertTrue(app.buttons["elder.switch-to-complete"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["firstLaunch.skip"].exists)

        // An already-completed user's forced tour is a replay, including its
        // final CTA, and must not reset their saved experience mode.
        relaunch(app, extras: ["-showFirstLaunch", "-showFirstLaunchPage7"])
        let finish = app.buttons["firstLaunch.next"]
        XCTAssertTrue(finish.waitForExistence(timeout: 10))
        XCTAssertEqual(finish.label, "完成")
        XCTAssertEqual(app.buttons["firstLaunch.skip"].label, "关闭")
        finish.tap()
        XCTAssertTrue(app.buttons["elder.switch-to-complete"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.tabBars.firstMatch.exists)

        relaunch(app)
        XCTAssertTrue(app.buttons["elder.switch-to-complete"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["firstLaunch.next"].exists)
        relaunch(app, inspecting: true)
        XCTAssertEqual(try readStore(in: app), initialStore,
                       "Setup and replay must preserve the fixture task IDs, statuses and action counters")
    }

    func testHelpCenterReplayClosesWithoutResettingCompletedSetupOrStore() throws {
        try requireIPhoneSimulator()
        let app = launchFixture(mode: "complete")
        defer { app.terminate() }
        let initialStore = try readStore(in: app)
        relaunch(app)
        let skip = app.buttons["firstLaunch.skip"]
        XCTAssertTrue(skip.waitForExistence(timeout: 10))
        skip.tap()
        app.buttons["firstLaunch.mode.later"].tap()

        let help = app.buttons["使用帮助"]
        XCTAssertTrue(help.waitForExistence(timeout: 10))
        help.tap()
        let tour = app.buttons["快速上手"]
        XCTAssertTrue(tour.waitForExistence(timeout: 5))
        tour.tap()
        let close = app.buttons["firstLaunch.skip"]
        XCTAssertTrue(close.waitForExistence(timeout: 5))
        XCTAssertEqual(close.label, "关闭")
        close.tap()
        XCTAssertTrue(tour.waitForExistence(timeout: 5), "Closing the replay must return to Help Center")
        app.buttons["完成"].tap()
        XCTAssertTrue(help.waitForExistence(timeout: 5))

        relaunch(app)
        XCTAssertTrue(app.buttons["使用帮助"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["firstLaunch.skip"].exists)
        XCTAssertFalse(app.buttons["elder.switch-to-complete"].exists)
        relaunch(app, inspecting: true)
        XCTAssertEqual(try readStore(in: app), initialStore,
                       "Replaying from Help Center must not create medication actions or reset setup")
    }

    private func launchFixture(mode: String) -> XCUIApplication {
        continueAfterFailure = false
        fixtureArguments = [
            "--elder-ui-fixture", "multiple",
            "--elder-ui-session", UUID().uuidString,
            "--elder-ui-mode", mode,
            "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryL",
            "-AppPersistenceCommitter.failureMessage", "",
            "-DoseActionPersistence.failureMessage", ""
        ]
        let app = XCUIApplication()
        app.launchArguments = fixtureArguments + ["--elder-ui-inspect-store"]
        app.launch()
        return app
    }

    private func relaunch(
        _ app: XCUIApplication,
        inspecting: Bool = false,
        extras: [String] = []
    ) {
        app.terminate()
        app.launchArguments = fixtureArguments + extras
            + (inspecting ? ["--elder-ui-inspect-store"] : [])
        app.launch()
    }

    private func readStore(in app: XCUIApplication) throws -> [String: String] {
        let prefix = "elder.test.store."
        let count = app.staticTexts[prefix + "task-count"]
        XCTAssertTrue(count.waitForExistence(timeout: 10))
        XCTAssertEqual(count.label, "2")
        XCTAssertFalse(app.staticTexts[prefix + "error"].exists)
        let fields = ["task-count", "log-count", "help-attempts", "save-attempts", "schedule-attempts"]
            + (0..<2).flatMap { index in
                ["task.\(index).id", "task.\(index).status", "task.\(index).due-offset"]
            }
        var snapshot: [String: String] = [:]
        for field in fields {
            let label = app.staticTexts[prefix + field]
            XCTAssertTrue(label.exists, "Missing fixture inspection field: \(field)")
            snapshot[field] = label.label
        }
        return snapshot
    }

    private func requireIPhoneSimulator() throws {
        #if targetEnvironment(simulator)
        guard UIDevice.current.userInterfaceIdiom == .phone else {
            throw XCTSkip("This fixture journey targets iPhone; the iPad lane remains paused")
        }
        #else
        throw XCTSkip("Synthetic fixture journeys require the simulator-only store isolation")
        #endif
    }
}
