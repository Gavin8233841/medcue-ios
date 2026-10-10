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
            "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN",
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
        try reveal(taken, in: app, accessibility: accessibility)
        taken.tap()
        let cancel = app.buttons["today.workspace.cancel-unavailable-confirmation"]
        try reveal(cancel, in: app, accessibility: accessibility)
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
        // Store inspection can outlive the earlier hit-test snapshot. Resolve
        // the same owned cancellation leaf again immediately before tapping.
        let cancelForTap = try unavailableCancelButton(in: app, accessibility: accessibility)
        try reveal(cancelForTap, in: app, accessibility: accessibility)
        let freshCancel = try unavailableCancelButton(in: app, accessibility: accessibility)
        XCTAssertTrue(try isVisible(freshCancel, in: app, accessibility: accessibility))
        freshCancel.tap()
        let disappeared = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: cancel)
        XCTAssertEqual(XCTWaiter.wait(for: [disappeared], timeout: 5), .completed)
        XCTAssertEqual(liveStore(app), before,
                       "Cancelling the original pending must leave tasks/logs/save/schedule evidence unchanged")
        if accessibility {
            let actionable = app.buttons.matching(identifier: "today.timeline.action.taken").firstMatch
            try reveal(actionable, in: app, accessibility: accessibility)
            XCTAssertTrue(actionable.isEnabled)
        } else if mutation == "missing" || mutation == "replacement" {
            let returnButton = app.buttons["today.workspace.return-to-list"]
            try reveal(returnButton, in: app, accessibility: accessibility)
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

    private func ownedPane(in app: XCUIApplication, accessibility: Bool) throws -> XCUIElement {
        let viewport = try TodayWorkspaceTestScope.viewport(in: app)
        let pane: XCUIElement
        if accessibility {
            try TodayWorkspaceTestScope.assertCompact(in: app)
            pane = viewport
        } else {
            // MissingSelection owns cancellation, not the usual dose actions.
            // Verify the detail structure without requiring those actions.
            for identifier in ["today.workspace.list", "today.workspace.detail"] {
                XCTAssertEqual(app.descendants(matching: .any).matching(identifier: identifier).count, 1)
                XCTAssertEqual(viewport.descendants(matching: .any).matching(identifier: identifier).count, 1)
            }
            let details = viewport.descendants(matching: .any).matching(identifier: "today.workspace.detail")
            pane = try XCTUnwrap(details.count == 1 ? details.allElementsBoundByIndex.first : nil)
        }
        return pane
    }

    private func ownedScroll(in app: XCUIApplication, accessibility: Bool) throws -> XCUIElement {
        let pane = try ownedPane(in: app, accessibility: accessibility)
        let scrolls = pane.elementType == .scrollView ? [pane] : pane.scrollViews.allElementsBoundByIndex
        XCTAssertEqual(scrolls.count, 1, "The owned Today pane must have one actual scroll host")
        let scroll = try XCTUnwrap(scrolls.count == 1 ? scrolls.first : nil)
        XCTAssertEqual(scroll.descendants(matching: .scrollView).count, 0)
        XCTAssertTrue(scroll.exists)
        XCTAssertTrue(scroll.isEnabled)
        return scroll
    }

    private func unavailableCancelButton(in app: XCUIApplication, accessibility: Bool) throws -> XCUIElement {
        let identifier = "today.workspace.cancel-unavailable-confirmation"
        let viewport = try TodayWorkspaceTestScope.viewport(in: app)
        let scroll = try ownedScroll(in: app, accessibility: accessibility)
        let global = app.buttons.matching(identifier: identifier)
        let owned = viewport.buttons.matching(identifier: identifier)
        let inScroll = scroll.buttons.matching(identifier: identifier)
        XCTAssertEqual(global.count, 1)
        XCTAssertEqual(owned.count, 1)
        XCTAssertEqual(inScroll.count, 1)
        let button = try XCTUnwrap(inScroll.count == 1 ? inScroll.allElementsBoundByIndex.first : nil)
        XCTAssertEqual(button.descendants(matching: .button).count, 0)
        XCTAssertEqual(button.label, "取消原来的用药确认")
        XCTAssertTrue(button.isEnabled)
        return button
    }

    private func isVisible(_ element: XCUIElement, in app: XCUIApplication, accessibility: Bool) throws -> Bool {
        guard element.exists else { return false }
        let viewport = try TodayWorkspaceTestScope.viewport(in: app)
        let identifier = element.identifier
        let owner: XCUIElement
        if !accessibility && identifier == "today.timeline.action.taken" {
            // Wide dose actions can be safeAreaInset siblings of the scroll
            // contents. Their owner is the strict detail pane, not its scroll.
            owner = try ownedPane(in: app, accessibility: accessibility)
            XCTAssertEqual(app.buttons.matching(identifier: identifier).count, 1)
            XCTAssertEqual(owner.buttons.matching(identifier: identifier).count, 1)
            XCTAssertEqual(element.descendants(matching: .button).count, 0)
        } else {
            owner = try ownedScroll(in: app, accessibility: accessibility)
            if ["today.workspace.cancel-unavailable-confirmation", "today.workspace.return-to-list"].contains(identifier) {
                XCTAssertEqual(app.buttons.matching(identifier: identifier).count, 1)
                XCTAssertEqual(viewport.buttons.matching(identifier: identifier).count, 1)
                XCTAssertEqual(owner.buttons.matching(identifier: identifier).count, 1)
                XCTAssertEqual(element.descendants(matching: .button).count, 0)
            }
        }
        let visibleFrame = owner.frame.intersection(viewport.frame)
        let frame = element.frame
        let validFrame = frame.origin.x.isFinite && frame.origin.y.isFinite
            && frame.width.isFinite && frame.height.isFinite && frame.width > 0 && frame.height > 0
        return element.isEnabled && element.isHittable && validFrame
            && !visibleFrame.isNull && !visibleFrame.isEmpty && visibleFrame.intersects(frame)
    }

    private func reveal(_ element: XCUIElement, in app: XCUIApplication, accessibility: Bool) throws {
        for _ in 0..<6 {
            if try isVisible(element, in: app, accessibility: accessibility) { return }
            try ownedScroll(in: app, accessibility: accessibility).swipeUp()
        }
        for _ in 0..<6 {
            if try isVisible(element, in: app, accessibility: accessibility) { return }
            try ownedScroll(in: app, accessibility: accessibility).swipeDown()
        }
        XCTAssertTrue(element.waitForExistence(timeout: 5))
        XCTAssertTrue(try isVisible(element, in: app, accessibility: accessibility))
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
