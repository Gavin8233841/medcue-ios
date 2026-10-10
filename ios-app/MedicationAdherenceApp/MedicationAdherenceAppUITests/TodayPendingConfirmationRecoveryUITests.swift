import UIKit
import XCTest

@MainActor
final class TodayPendingConfirmationRecoveryUITests: XCTestCase {
    func testWideRecoveryForMissingChangedHandledArchivedAndReplacement() throws {
        try requireSimulator()
        for mutation in ["missing", "key-changed", "handled", "archived", "replacement"] {
            try verifyCancellation(mutation: mutation, accessibility: false)
        }
    }

    func testAXRecoveryNeverAttachesOldConfirmationToAReplacementRow() throws {
        try requireSimulator()
        for mutation in ["missing", "key-changed", "handled", "archived", "replacement"] {
            try verifyCancellation(mutation: mutation, accessibility: true)
        }
    }

    private func verifyCancellation(mutation: String, accessibility: Bool) throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = [
            "--elder-ui-fixture", "future-multiple", "--elder-ui-session", UUID().uuidString,
            "--elder-ui-mode", "complete", "-hasCompletedFirstLaunchSetup", "YES",
            "--elder-ui-invalidate-confirmation", mutation,
            "-UIPreferredContentSizeCategoryName",
            accessibility ? "UICTContentSizeCategoryAccessibilityXXXL" : "UICTContentSizeCategoryL",
            "-AppPersistenceCommitter.failureMessage", "", "-DoseActionPersistence.failureMessage", ""
        ]
        app.launch()
        defer { app.terminate() }
        CompleteModeTestNavigation.assertToday(in: app)
        if !accessibility {
            try TodayWorkspaceTestViewport.requireExpandedBudget(in: app)
            _ = try TodayWorkspaceTestScope.detail(in: app)
        } else {
            try TodayWorkspaceTestScope.assertCompact(in: app)
        }
        let taken = app.buttons.matching(identifier: "today.timeline.action.taken").firstMatch
        reveal(taken, in: app)
        taken.tap()
        let cancel = app.buttons["today.workspace.cancel-unavailable-confirmation"]
        reveal(cancel, in: app)
        let viewport = try TodayWorkspaceTestScope.viewport(in: app)
        let state = app.staticTexts.matching(identifier: "today.workspace.unavailable")
        XCTAssertEqual(state.count, 1, "The unavailable state belongs to one visible explanation, not its button ancestor")
        XCTAssertEqual(viewport.staticTexts.matching(identifier: "today.workspace.unavailable").count, 1)
        XCTAssertEqual(state.element(boundBy: 0).label,
                       "任务可能已处理、归档或不在当前列表。原来的确认不会被移到另一药品。")
        XCTAssertEqual(app.buttons.matching(identifier: "today.workspace.cancel-unavailable-confirmation").count, 1)
        XCTAssertEqual(viewport.buttons.matching(identifier: "today.workspace.cancel-unavailable-confirmation").count, 1)
        XCTAssertEqual(cancel.descendants(matching: .button).count, 0)
        XCTAssertEqual(cancel.label, "取消原来的用药确认")
        XCTAssertTrue(cancel.isEnabled)
        XCTAssertFalse(app.buttons["today.timeline.confirmation.confirm"].exists,
                       "An invalid old confirmation must not move to an existing or replacement row")
        let before = liveStore(app)
        XCTAssertEqual(before["logs"], "0")
        XCTAssertEqual(before["saves"], "0")
        XCTAssertEqual(before["schedules"], "0")
        cancel.tap()
        let disappeared = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: cancel)
        XCTAssertEqual(XCTWaiter.wait(for: [disappeared], timeout: 5), .completed)
        XCTAssertEqual(liveStore(app), before,
                       "Cancelling the original pending must leave tasks/logs/save/schedule evidence unchanged")
        if accessibility {
            let actionable = app.buttons.matching(identifier: "today.timeline.action.taken").firstMatch
            reveal(actionable, in: app)
            XCTAssertTrue(actionable.isEnabled)
        } else if mutation == "missing" || mutation == "replacement" {
            let returnButton = app.buttons["today.workspace.return-to-list"]
            reveal(returnButton, in: app)
            XCTAssertEqual(app.buttons.matching(identifier: "today.workspace.return-to-list").count, 1)
            XCTAssertEqual(try TodayWorkspaceTestScope.viewport(in: app)
                .buttons.matching(identifier: "today.workspace.return-to-list").count, 1)
            XCTAssertEqual(returnButton.descendants(matching: .button).count, 0)
            XCTAssertEqual(returnButton.label, "返回任务列表")
            XCTAssertTrue(returnButton.isEnabled)
            returnButton.tap()
            XCTAssertTrue(app.buttons["today.timeline.action.taken"].isEnabled)
        } else {
            let selectors = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "today.workspace.select."))
            XCTAssertGreaterThan(selectors.count, 0)
            for selector in selectors.allElementsBoundByIndex { XCTAssertTrue(selector.isEnabled) }
            XCTAssertTrue(selectors.firstMatch.isHittable)
            selectors.firstMatch.tap()
            XCTAssertTrue(app.buttons["today.timeline.action.taken"].isEnabled)
        }
    }

    private func liveStore(_ app: XCUIApplication) -> [String: String] {
        var result: [String: String] = [:]
        for field in ["tasks", "logs", "saves", "schedules"] {
            let element = app.staticTexts["elder.test.live." + field]
            XCTAssertTrue(element.waitForExistence(timeout: 5))
            result[field] = element.label
        }
        return result
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

    private func requireSimulator() throws {
        #if targetEnvironment(simulator)
        guard UIDevice.current.userInterfaceIdiom == .phone else { throw XCTSkip("iPhone/Duo lane") }
        #else
        throw XCTSkip("Explicit invalidation is only available in simulator-owned fixtures")
        #endif
    }
}

@MainActor
enum TodayWorkspaceTestViewport {
    static func requireExpandedBudget(in app: XCUIApplication) throws {
        let viewport = app.descendants(matching: .any).matching(identifier: "today.workspace.viewport")
        XCTAssertTrue(viewport.element(boundBy: 0).waitForExistence(timeout: 5))
        XCTAssertEqual(viewport.count, 1)
        let measured = try XCTUnwrap(viewport.element(boundBy: 0).value as? String).split(separator: ",")
        XCTAssertEqual(measured.count, 2, "The owned fixture must expose the actual GeometryReader budget")
        let width = try XCTUnwrap(measured.first.flatMap { Int($0) })
        let height = try XCTUnwrap(measured.last.flatMap { Int($0) })
        guard width >= 668 && height >= 360 else {
            throw XCTSkip("Expanded-only journey requires actual Today content budget 668×360; AX journey covers compact layout")
        }
    }
}
