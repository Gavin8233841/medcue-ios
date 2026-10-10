import UIKit
import XCTest

/// Uses the existing simulator-only session store and preference suite.
/// Expanded-only journeys explicitly need a wide viewport; AX applies to both.
@MainActor
final class TodayTaskWorkspaceUITests: XCTestCase {
    private var arguments: [String] = []
    private enum ScrollLookupError: Error { case invalidOwner }

    func testExpandedSelectionRevealsIdentityAndDoesNotWriteAnotherDrug() throws {
        try requireSimulator()
        let app = launchFixture(scenario: "multiple")
        defer { app.terminate() }
        let baseline = readStore(app, count: 2)
        showToday(app)
        try requireWideViewport(app)
        let firstID = try XCTUnwrap(baseline["task.0.id"])
        let secondID = try XCTUnwrap(baseline["task.1.id"])
        assertIdentity(firstID, name: "布洛芬", unit: "片", time: "11:55", in: app)
        let first = app.buttons["today.workspace.select." + firstID]
        let second = app.buttons["today.workspace.select." + secondID]
        let list = app.descendants(matching: .any).matching(identifier: "today.workspace.list").element(boundBy: 0)
        for id in [firstID, secondID] {
            XCTAssertEqual(app.buttons.matching(identifier: "today.workspace.select." + id).count, 1)
            XCTAssertEqual(list.buttons.matching(identifier: "today.workspace.select." + id).count, 1)
        }
        XCTAssertTrue(first.isSelected)
        let detail = try TodayWorkspaceTestScope.detailScroll(in: app)
        // Move the right pane independently before choosing another list row.
        // A dedicated long-list fixture/native run is still required separately.
        detail.swipeUp()
        XCTAssertTrue(second.isHittable)
        second.tap()
        assertIdentity(secondID, name: "人工泪液", unit: "滴", time: "11:58", in: app)
        XCTAssertTrue(second.isSelected)
        XCTAssertFalse(first.isSelected)
        let taken = app.buttons.matching(identifier: "today.timeline.action.taken")
        XCTAssertEqual(taken.count, 1)
        XCTAssertEqual(taken.firstMatch.label, "已使用")
        XCTAssertTrue(taken.firstMatch.isHittable)
        XCTAssertTrue(first.isEnabled)
        first.tap()
        assertIdentity(firstID, name: "布洛芬", unit: "片", time: "11:55", in: app)
        inspectStore(app)
        XCTAssertEqual(readStore(app, count: 2), baseline,
                       "Browsing must not alter tasks, logs or side-effect counters")
    }

    func testExpandedFutureDoseKeepsOriginalEarlyConfirmation() throws {
        try requireSimulator()
        let app = launchFixture(scenario: "future")
        defer { app.terminate() }
        let baseline = readStore(app, count: 1)
        showToday(app)
        try requireWideViewport(app)
        let id = try XCTUnwrap(baseline["task.0.id"])
        assertIdentity(id, name: "布洛芬", unit: "片", time: "18:00", in: app)
        app.buttons["today.timeline.action.taken"].tap()
        XCTAssertTrue(app.buttons["today.timeline.confirmation.confirm"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons.matching(identifier: "today.timeline.confirmation.confirm").count, 1)
        XCTAssertEqual(app.buttons.matching(identifier: "today.timeline.confirmation.cancel").count, 1)
        _ = try TodayWorkspaceTestScope.detail(in: app)
        let viewport = try TodayWorkspaceTestScope.viewport(in: app)
        for identifier in ["today.timeline.confirmation.confirm", "today.timeline.confirmation.cancel"] {
            XCTAssertEqual(viewport.buttons.matching(identifier: identifier).count, 1,
                           "The current Today viewport must own both confirmation leaves")
            XCTAssertEqual(viewport.buttons.matching(identifier: identifier).element(boundBy: 0)
                .descendants(matching: .button).count, 0, "Confirmation identifiers belong to the actionable leaf")
        }
        XCTAssertFalse(app.buttons["today.workspace.select." + id].isEnabled)
        assertIdentity(id, name: "布洛芬", unit: "片", time: "18:00", in: app)
        app.buttons["today.timeline.confirmation.cancel"].tap()
        inspectStore(app)
        XCTAssertEqual(readStore(app, count: 1), baseline)
    }

    func testMaximumAccessibilitySizeUsesOriginalRowsAndConfirmationWithoutWrites() throws {
        try requireSimulator()
        let app = launchFixture(scenario: "future", accessibility: true)
        defer { app.terminate() }
        let baseline = readStore(app, count: 1)
        showToday(app)
        try TodayWorkspaceTestScope.assertCompact(in: app)
        let viewport = try TodayWorkspaceTestScope.viewport(in: app)
        TodayWorkspaceTestScope.assertActionIdentifiers(in: viewport, globallyIn: app)
        let first = try revealTodayButton("today.timeline.action.taken", in: app)
        first.tap()
        let cancel = try revealTodayButton("today.timeline.confirmation.cancel", in: app)
        XCTAssertEqual(app.buttons.matching(identifier: "today.timeline.confirmation.confirm").count, 1)
        XCTAssertEqual(app.buttons.matching(identifier: "today.timeline.confirmation.cancel").count, 1)
        for identifier in ["today.timeline.confirmation.confirm", "today.timeline.confirmation.cancel"] {
            XCTAssertEqual(app.buttons.matching(identifier: identifier).element(boundBy: 0)
                .descendants(matching: .button).count, 0, "Compact confirmation identifiers belong to the actionable leaf")
        }
        cancel.tap()
        inspectStore(app)
        XCTAssertEqual(readStore(app, count: 1), baseline)
    }

    private func launchFixture(scenario: String, accessibility: Bool = false) -> XCUIApplication {
        continueAfterFailure = false
        arguments = [
            "--elder-ui-fixture", scenario, "--elder-ui-session", UUID().uuidString,
            "--elder-ui-mode", "complete", "-hasCompletedFirstLaunchSetup", "YES",
            "-UIPreferredContentSizeCategoryName",
            accessibility ? "UICTContentSizeCategoryAccessibilityXXXL" : "UICTContentSizeCategoryL",
            "-AppPersistenceCommitter.failureMessage", "", "-DoseActionPersistence.failureMessage", ""
        ]
        let app = XCUIApplication()
        app.launchArguments = arguments + ["--elder-ui-inspect-store"]
        app.launch()
        return app
    }

    private func showToday(_ app: XCUIApplication) {
        app.terminate()
        app.launchArguments = arguments
        app.launch()
        CompleteModeTestNavigation.assertToday(in: app)
    }

    private func inspectStore(_ app: XCUIApplication) {
        app.terminate()
        app.launchArguments = arguments + ["--elder-ui-inspect-store"]
        app.launch()
    }

    private func requireWideViewport(_ app: XCUIApplication) throws {
        try TodayWorkspaceTestViewport.requireExpandedBudget(in: app)
        _ = try TodayWorkspaceTestScope.detail(in: app)
    }

    private func assertIdentity(_ id: String, name: String, unit: String, time: String, in app: XCUIApplication) {
        let identities = app.descendants(matching: .any).matching(identifier: "today.workspace.identity." + id)
        XCTAssertTrue(identities.firstMatch.waitForExistence(timeout: 5))
        XCTAssertEqual(identities.count, 1)
        let identity = identities.firstMatch
        XCTAssertTrue(identity.label.contains(name))
        XCTAssertTrue(identity.label.contains("本次用量 · 1 " + unit))
        XCTAssertTrue(identity.label.contains("计划时间 · " + time))
        let window = app.windows.firstMatch.frame
        XCTAssertTrue(window.contains(identity.frame), "Identity and dose must be visible after selecting a row")
        XCTAssertTrue(app.buttons["today.timeline.action.taken"].isHittable)
    }

    private func readStore(_ app: XCUIApplication, count: Int) -> [String: String] {
        let prefix = "elder.test.store."
        XCTAssertTrue(app.staticTexts[prefix + "task-count"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.staticTexts[prefix + "task-count"].label, String(count))
        XCTAssertFalse(app.staticTexts[prefix + "error"].exists)
        var fields = ["task-count", "log-count", "help-attempts", "save-attempts", "schedule-attempts"]
        for index in 0..<count {
            fields += ["task.\(index).id", "task.\(index).status", "task.\(index).due-offset"]
        }
        var result: [String: String] = [:]
        for field in fields {
            XCTAssertTrue(app.staticTexts[prefix + field].exists)
            result[field] = app.staticTexts[prefix + field].label
        }
        return result
    }

    private func revealTodayButton(_ identifier: String, in app: XCUIApplication) throws -> XCUIElement {
        var observations: [String] = []
        func fail(_ reason: String) throws -> Never {
            captureTodayScrollFailure(reason, identifier: identifier, app: app, observations: observations)
            XCTFail("The compact Today scroll/leaf owner is invalid: \(reason)")
            throw ScrollLookupError.invalidOwner
        }
        guard ownsFutureFixture(app), ["today.timeline.action.taken", "today.timeline.confirmation.cancel"].contains(identifier)
        else { try fail("unowned-fixture-or-target") }
        func lookup() throws -> (scroll: XCUIElement, target: XCUIElement?) {
            let viewports = app.descendants(matching: .any).matching(identifier: "today.workspace.viewport")
            guard viewports.count == 1, viewports.element(boundBy: 0).exists else { try fail("viewport-count=\(viewports.count)") }
            let viewport = viewports.element(boundBy: 0)
            guard viewport.descendants(matching: .any).matching(identifier: "today.workspace.list").count == 0,
                  viewport.descendants(matching: .any).matching(identifier: "today.workspace.detail").count == 0
            else { try fail("not-compact-today") }
            let scrolls = viewport.elementType == .scrollView ? [viewport] : viewport.scrollViews.allElementsBoundByIndex
            guard scrolls.count == 1, let scroll = scrolls.first else { try fail("owned-scroll-count=\(scrolls.count)") }
            let frame = scroll.frame
            guard scroll.exists, scroll.isEnabled, frame.origin.x.isFinite, frame.origin.y.isFinite,
                  frame.width.isFinite, frame.height.isFinite, frame.width > 0, frame.height > 0,
                  scroll.descendants(matching: .scrollView).count == 0 else { try fail("invalid-owned-scroll") }
            let global = app.buttons.matching(identifier: identifier)
            let owned = viewport.buttons.matching(identifier: identifier)
            let inScroll = scroll.buttons.matching(identifier: identifier)
            observations.append("unix=\(Date().timeIntervalSince1970) state=\(app.state.rawValue) "
                + "scroll=\(frame) scrollHittable=\(scroll.isHittable) "
                + "target counts global/viewport/scroll=\(global.count)/\(owned.count)/\(inScroll.count)")
            guard global.count <= 1, owned.count <= 1, inScroll.count <= 1 else { try fail("ambiguous-leaf") }
            if global.count == 0, owned.count == 0, inScroll.count == 0 { return (scroll, nil) }
            guard global.count == 1, owned.count == 1, inScroll.count == 1 else { try fail("leaf-outside-owned-scroll") }
            let target = inScroll.element(boundBy: 0)
            guard target.descendants(matching: .button).count == 0 else { try fail("target-is-button-ancestor") }
            let exists = target.exists
            let enabled = target.isEnabled
            let hittable = target.isHittable
            let targetFrame = target.frame
            observations.append("leaf exists=\(exists) enabled=\(enabled) hittable=\(hittable) frame=\(targetFrame)")
            let validFrame = targetFrame.origin.x.isFinite && targetFrame.origin.y.isFinite
                && targetFrame.width.isFinite && targetFrame.height.isFinite && targetFrame.width > 0 && targetFrame.height > 0
            return (scroll, exists && enabled && hittable && validFrame && frame.intersects(targetFrame) ? target : nil)
        }
        for up in [true, false] {
            for attempt in 0..<6 {
                let current = try lookup()
                if let target = current.target { return target }
                // Retain pre-gesture state even if XCTest event synthesis aborts
                // before the next lookup. No app-wide gesture or pixel target.
                XCTContext.runActivity(named: "Owned Today \(up ? "swipeUp" : "swipeDown") \(attempt + 1)") { activity in
                    let before = XCTAttachment(string: observations.joined(separator: "\n"))
                    before.name = "today-scroll-before-gesture"
                    before.lifetime = .keepAlways
                    activity.add(before)
                    if up { current.scroll.swipeUp() } else { current.scroll.swipeDown() }
                }
            }
        }
        _ = app.buttons.matching(identifier: identifier).element(boundBy: 0).waitForExistence(timeout: 5)
        if let target = try lookup().target { return target }
        try fail("bounded-scroll-exhausted")
    }

    private func ownsFutureFixture(_ app: XCUIApplication) -> Bool {
        let values = app.launchArguments
        func value(after flag: String) -> String? {
            let indices = values.indices.filter { values[$0] == flag }
            guard indices.count == 1, let index = indices.first, values.indices.contains(index + 1) else { return nil }
            return values[index + 1]
        }
        return values == arguments && value(after: "--elder-ui-fixture") == "future"
            && value(after: "--elder-ui-mode") == "complete"
            && value(after: "--elder-ui-session").flatMap(UUID.init(uuidString:)) != nil
    }

    private func captureTodayScrollFailure(_ reason: String, identifier: String, app: XCUIApplication, observations: [String]) {
        guard ownsFutureFixture(app) else { return }
        XCTContext.runActivity(named: "Compact Today scroll failure: \(reason)") { activity in
            var sections = ["reason=\(reason), target=\(identifier), state=\(app.state.rawValue)",
                            observations.joined(separator: "\n"), "APP\n\(app.debugDescription)",
                            "VIEWPORT\n\(app.descendants(matching: .any).matching(identifier: "today.workspace.viewport").debugDescription)",
                            "TARGET\n\(app.buttons.matching(identifier: identifier).debugDescription)"]
            for (index, scroll) in app.scrollViews.allElementsBoundByIndex.enumerated() {
                let exists = scroll.exists
                let enabled = scroll.isEnabled
                let hittable = scroll.isHittable
                let frame = scroll.frame
                let nested = scroll.descendants(matching: .scrollView).count
                sections.append("scroll[\(index)] exists=\(exists) enabled=\(enabled) hittable=\(hittable) frame=\(frame) nested=\(nested)\n"
                    + scroll.debugDescription)
            }
            let hierarchy = XCTAttachment(string: sections.joined(separator: "\n\n"))
            hierarchy.name = "today-owned-scroll-\(reason)-hierarchy"
            hierarchy.lifetime = .keepAlways
            activity.add(hierarchy)
            let screenshot = XCTAttachment(screenshot: app.screenshot())
            screenshot.name = "today-owned-scroll-\(reason)-screenshot-unvalidated"
            screenshot.lifetime = .keepAlways
            activity.add(screenshot)
        }
    }

    private func requireSimulator() throws {
        #if targetEnvironment(simulator)
        guard UIDevice.current.userInterfaceIdiom == .phone else {
            throw XCTSkip("iPhone/Duo lane; iPad lane remains paused")
        }
        #else
        throw XCTSkip("Existing isolated test fixture is simulator-only")
        #endif
    }
}

/// Explicit container ownership, independent of the AX type SwiftUI chooses
/// for a contain boundary. Scroll only its unique actual native scroll host.
@MainActor
enum TodayWorkspaceTestScope {
    static func viewport(in app: XCUIApplication) throws -> XCUIElement {
        try unique(app.descendants(matching: .any).matching(identifier: "today.workspace.viewport"))
    }

    static func detail(in app: XCUIApplication) throws -> XCUIElement {
        let viewport = try Self.viewport(in: app)
        for identifier in ["today.workspace.list", "today.workspace.detail"] {
            _ = try unique(app.descendants(matching: .any).matching(identifier: identifier))
            _ = try unique(viewport.descendants(matching: .any).matching(identifier: identifier))
        }
        let detail = try unique(viewport.descendants(matching: .any).matching(identifier: "today.workspace.detail"))
        // safeAreaInset actions belong to Today even when AX exposes them as
        // siblings of the detail ScrollView instead of its scroll contents.
        assertActionIdentifiers(in: viewport, globallyIn: app)
        return detail
    }

    static func assertCompact(in app: XCUIApplication) throws {
        let viewport = try Self.viewport(in: app)
        for identifier in ["today.workspace.list", "today.workspace.detail"] {
            XCTAssertEqual(app.descendants(matching: .any).matching(identifier: identifier).count, 0)
            XCTAssertEqual(viewport.descendants(matching: .any).matching(identifier: identifier).count, 0)
        }
    }

    static func detailScroll(in app: XCUIApplication) throws -> XCUIElement {
        let pane = try detail(in: app)
        let scrolls = pane.elementType == .scrollView ? [pane] : pane.scrollViews.allElementsBoundByIndex
        XCTAssertEqual(scrolls.count, 1, "The owned detail pane must contain one actual scroll host")
        return try XCTUnwrap(scrolls.count == 1 ? scrolls.first : nil)
    }

    static func assertActionIdentifiers(in owner: XCUIElement, globallyIn app: XCUIApplication) {
        for identifier in ["today.timeline.action.taken", "today.timeline.action.delay", "today.timeline.action.skip"] {
            XCTAssertEqual(app.buttons.matching(identifier: identifier).count, 1,
                           "Each action must retain its own identifier instead of inheriting a workspace/pane ID")
            let owned = owner.buttons.matching(identifier: identifier)
            XCTAssertEqual(owned.count, 1, "The current Today viewport must own the action")
            XCTAssertEqual(owned.element(boundBy: 0).descendants(matching: .button).count, 0,
                           "The ID must belong to the actual action leaf, not a button ancestor")
            XCTAssertFalse(owned.element(boundBy: 0).label.isEmpty, "Actions retain their spoken labels")
        }
    }

    private static func unique(_ query: XCUIElementQuery) throws -> XCUIElement {
        XCTAssertTrue(query.element(boundBy: 0).waitForExistence(timeout: 5))
        XCTAssertEqual(query.count, 1, "This accessibility container must have exactly one owner")
        return try XCTUnwrap(query.count == 1 ? query.allElementsBoundByIndex.first : nil)
    }
}
