import UIKit
import XCTest

/// Real medication-tab journeys on iPhone Simulator; no hosted replacement view.
/// The inspector covers only its existing task/log/counter fields. The cancelled
/// name draft is also checked after relaunch; neither is a full database snapshot.
@MainActor
final class MedicationBrowseNavigationUITests: XCTestCase {
    private var activeFixtureApp: XCUIApplication?
    private var didCaptureFailureEvidence = false

    func testSearchSelectionBackAndClearRestoreCollapsedGroup() throws {
        try exerciseBrowse(category: "UICTContentSizeCategoryL", initiallyExpanded: false)
    }

    func testSearchSelectionBackAndClearRestoreExpandedGroupAtAccessibilitySize() throws {
        try exerciseBrowse(category: "UICTContentSizeCategoryAccessibilityXXXL", initiallyExpanded: true)
    }

    func testSelectingDifferentMedicationsAfterBackUpdatesRealDetailIdentity() throws {
        try requireIPhoneSimulator()
        let app = launchFixture(category: "UICTContentSizeCategoryL", scenario: "multiple")
        defer { finishFixture(app) }
        let initialStore = try readStore(in: app, taskCount: 2)
        relaunch(app, inspecting: false)
        try openMedicationTab(in: app)
        try selectNonemptyLifecycle(in: app, count: 2)
        try search(in: app, text: "布洛芬")
        let firstID = try openSearchResult(in: app)
        try reveal(detail(in: app).staticTexts["布洛芬"], in: app)
        try returnToSearch(in: app, rowID: firstID)

        // Preserve the same app process and browse session. Change the search,
        // then select a different persisted UUID through its actual list row.
        _ = try clearSearchText(in: app, expectedQuery: "布洛芬")
        try search(in: app, text: "人工泪液")
        let secondID = try openSearchResult(in: app)
        XCTAssertNotEqual(secondID, firstID, "The second selection must identify a different medication")
        try reveal(detail(in: app).staticTexts["人工泪液"], in: app)
        XCTAssertFalse(detail(in: app).staticTexts["布洛芬"].exists,
                       "The real detail subtree must not retain the previous medication identity")
        try returnToSearch(in: app, rowID: secondID, query: "人工泪液")
        relaunch(app, inspecting: true)
        XCTAssertEqual(try readStore(in: app, taskCount: 2), initialStore,
                       "Selecting different medications must preserve both tasks and observable store fields")
    }

    func testEditingThenCancelPreservesNameAndObservableStore() throws {
        try requireIPhoneSimulator()
        let app = launchFixture(category: "UICTContentSizeCategoryL")
        defer { finishFixture(app) }
        let initialStore = try readStore(in: app)
        relaunch(app, inspecting: false)
        try openMedicationTab(in: app)
        try selectNonemptyLifecycle(in: app)
        try search(in: app, text: "布洛芬")
        let rowID = try openSearchResult(in: app)
        try openEditor(in: app)
        let name = app.textFields["药品名称"]
        try require(name.waitForExistence(timeout: 5) && name.isHittable, "Name draft field unavailable")
        let initialName = try XCTUnwrap(name.value as? String)
        try require(initialName.contains("布洛芬"), "Expected the synthetic medication name")
        name.tap()
        name.typeText("-CANCELLED-DRAFT")
        try require((name.value as? String)?.contains("CANCELLED-DRAFT") == true,
                    "The test must actually change the draft before cancelling")
        let cancel = app.navigationBars["修改药品"].buttons["取消"]
        try require(cancel.exists && cancel.isHittable, "Editor cancellation unavailable")
        cancel.tap()
        try require(app.navigationBars["修改药品"].waitForNonExistence(timeout: 5), "Editor did not dismiss")
        try require(detail(in: app).exists, "Cancelling lost the real detail route")
        try returnToSearch(in: app, rowID: rowID)

        relaunch(app, inspecting: true)
        XCTAssertEqual(try readStore(in: app), initialStore,
                       "Cancellation must preserve every field exposed by the existing store inspector")
        relaunch(app, inspecting: false)
        try openMedicationTab(in: app)
        try selectNonemptyLifecycle(in: app)
        try search(in: app, text: "布洛芬")
        XCTAssertEqual(try openSearchResult(in: app), rowID, "Relaunch must retain medication identity")
        try openEditor(in: app)
        XCTAssertEqual(app.textFields["药品名称"].value as? String, initialName,
                       "Cancelled draft name must not become persisted medication state")
        app.navigationBars["修改药品"].buttons["取消"].tap()
    }

    private func exerciseBrowse(category: String, initiallyExpanded: Bool) throws {
        try requireIPhoneSimulator()
        let app = launchFixture(category: category)
        defer { finishFixture(app) }
        let initialStore = try readStore(in: app)
        relaunch(app, inspecting: false)
        try openMedicationTab(in: app)
        try selectNonemptyLifecycle(in: app)
        let group = groupContainer(in: app)
        try reveal(group, in: app)
        let desiredValue = initiallyExpanded ? "已展开" : "已折叠"
        if (group.value as? String) != desiredValue {
            let toggle = group.buttons.matching(NSPredicate(format: "label CONTAINS %@", "布洛芬")).firstMatch
            try reveal(toggle, in: app)
            toggle.tap()
        }
        try waitForValue(desiredValue, of: group)
        try search(in: app, text: "布洛芬")
        let rowID = try openSearchResult(in: app)
        try returnToSearch(in: app, rowID: rowID)
        // Re-select the SAME UUID after Back. A stale preferredCompactColumn must
        // not leave the user trapped on the sidebar after the first navigation.
        let selectedRow = app.buttons[rowID]
        selectedRow.tap()
        try require(detail(in: app).waitForExistence(timeout: 10), "Reselecting the same row must reopen detail")
        try returnToSearch(in: app, rowID: rowID)
        try clearSearch(in: app)
        let restoredGroup = groupContainer(in: app)
        try reveal(restoredGroup, in: app)
        try waitForValue(desiredValue, of: restoredGroup)
        if initiallyExpanded {
            try reveal(app.buttons[rowID], in: app)
            XCTAssertTrue(app.buttons[rowID].isSelected, "Clearing search must preserve selected medication identity")
        } else {
            XCTAssertFalse(app.buttons[rowID].exists, "Clearing search must restore the collapsed group")
        }
        relaunch(app, inspecting: true)
        XCTAssertEqual(try readStore(in: app), initialStore,
                       "Search, selection, Back and clearing must preserve observable fixture state")
    }

    private func requireIPhoneSimulator() throws {
        continueAfterFailure = false
        #if targetEnvironment(simulator)
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .phone,
                          "This lane exercises actual compact iPhone navigation, not iPad")
        #else
        throw XCTSkip("The synthetic fixture must run on Simulator, never a physical device")
        #endif
    }

    private func launchFixture(category: String, scenario: String = "due") -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-AppPersistenceCommitter.failureMessage", "",
            "-DoseActionPersistence.failureMessage", "",
            "-UIPreferredContentSizeCategoryName", category,
            "-hasCompletedFirstLaunchSetup", "YES",
            "-appColorSchemePreference", "light",
            "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN",
            "--elder-ui-mode", "complete", "--elder-ui-fixture", scenario,
            "--elder-ui-session", UUID().uuidString, "--elder-ui-inspect-store"
        ]
        activeFixtureApp = app
        didCaptureFailureEvidence = false
        app.launch()
        return app
    }

    private func relaunch(_ app: XCUIApplication, inspecting: Bool) {
        app.terminate()
        app.launchArguments.removeAll { $0 == "--elder-ui-inspect-store" }
        if inspecting { app.launchArguments.append("--elder-ui-inspect-store") }
        app.launch()
    }

    private func openMedicationTab(in app: XCUIApplication) throws {
        let bottomEntries = app.tabBars.buttons.matching(NSPredicate(format: "label == %@", "药品"))
        // Duo's native hierarchy exposes the same app tab in a side toolbar,
        // outside TabBar. Match its observed identity, never arbitrary drug text.
        let sideEntries = app.toolbars.buttons.matching(NSPredicate(
            format: "identifier == %@ AND label == %@", "pills", "药品"
        ))
        let available = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            guard bottomEntries.count <= 1 && sideEntries.count <= 1 else { return false }
            return (bottomEntries.count == 1 && bottomEntries.firstMatch.isHittable)
                || (sideEntries.count == 1 && sideEntries.firstMatch.isHittable)
        }, object: nil)
        try require(XCTWaiter.wait(for: [available], timeout: 10) == .completed,
                    "A unique hittable medication tab must exist in the bottom bar or native side toolbar")
        let entries = bottomEntries.count == 1 && bottomEntries.firstMatch.isHittable
            ? bottomEntries : sideEntries
        try require(entries.count == 1 && entries.firstMatch.isHittable,
                    "Medication entry must remain unique and hittable at activation")
        let tab = entries.firstMatch
        tab.tap()
        try require(app.descendants(matching: .any)["tab.medications"].waitForExistence(timeout: 10)
                    && app.navigationBars["药品"].exists && tab.isSelected,
                    "Actual medication tab and its navigation content must become selected")
    }

    private func selectNonemptyLifecycle(in app: XCUIApplication, count: Int = 1) throws {
        // The fixed-date fixture can move from active to interrupted as real time
        // passes. Resolve its observed count instead of changing the app clock.
        let selector = app.buttons.matching(NSPredicate(
            format: "label MATCHES %@", "(正在服用|服用中断|归档药物)，\(count) 个药品"
        )).firstMatch
        try reveal(selector, in: app)
        selector.tap()
    }

    private func groupContainer(in app: XCUIApplication) -> XCUIElement {
        // Existing native AX evidence puts the value on an Other container and
        // the actionable toggle on its child Button, not the container itself.
        app.descendants(matching: .any)["tab.medications"].otherElements.matching(NSPredicate(
            format: "label CONTAINS %@ AND label CONTAINS %@ AND (value == %@ OR value == %@)",
            "药品，1 个", "布洛芬", "已折叠", "已展开"
        )).firstMatch
    }

    private func searchField(in app: XCUIApplication) throws -> XCUIElement {
        let field = app.searchFields.firstMatch
        // A scrolled list can hide the navigation drawer. Restore its visibility
        // only when entering/clearing search, never before the return-anchor check.
        for _ in 0..<15 {
            if field.exists && field.isHittable { return field }
            app.swipeDown(velocity: .slow)
        }
        try require(field.exists && field.isHittable, "Native medication search bar unavailable")
        return field
    }

    private func search(in app: XCUIApplication, text: String) throws {
        let field = try searchField(in: app)
        field.tap()
        field.typeText(text + "\n")
        try waitForValue(text, of: field)
    }

    private func clearSearch(in app: XCUIApplication) throws {
        _ = try clearSearchText(in: app, expectedQuery: "布洛芬")
        // Exact CI AX evidence: an empty search disables the keyboard Search key.
        // End editing with the native Close control AFTER proving the query empty.
        let closeButtons = app.navigationBars["药品"].buttons.matching(NSPredicate(format: "label == %@", "关闭"))
        let close = closeButtons.firstMatch
        try require(close.waitForExistence(timeout: 5) && closeButtons.count == 1 && close.isHittable,
                    "Exactly one native medication-search Close control must be available")
        close.tap()
        // The return anchor can leave the group above the visible row.
        try revealRestoredGroup(in: app)
        // exerciseBrowse still asserts the ORIGINAL expansion value and UUID.
    }

    private func revealRestoredGroup(in app: XCUIApplication) throws {
        let group = groupContainer(in: app)
        // Keep the existing 20-gesture budget, but inspect both directions.
        // This observes the group without changing its expansion or selection.
        for towardStart in [true, false] {
            for _ in 0..<10 {
                if group.exists && group.isHittable { return }
                if towardStart { app.swipeDown(velocity: .slow) }
                else { app.swipeUp(velocity: .slow) }
            }
        }
        try require(group.exists && group.isHittable,
                    "Ordinary lifecycle group must be reachable after clearing search")
    }

    @discardableResult
    private func clearSearchText(in app: XCUIApplication, expectedQuery: String) throws -> XCUIElement {
        let field = try searchField(in: app)
        try require((field.value as? String) == expectedQuery,
                    "Search must retain the exact query before clearing")
        field.tap()
        // Native clear avoids assuming where a tap placed the insertion caret.
        // Limit the lookup to this search field; never substitute Cancel or Back.
        let clearButtons = field.buttons.matching(NSPredicate(
            format: "label == %@ OR label == %@ OR label == %@ OR identifier == %@",
            "Clear text", "清除文本", "清除", "Clear text"
        ))
        let clear = clearButtons.firstMatch
        try require(clear.waitForExistence(timeout: 5) && clearButtons.count == 1 && clear.isHittable,
                    "Exactly one native search-field clear button must be available")
        clear.tap()
        let empty = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            guard let value = field.value as? String else { return false }
            return value.isEmpty || (field.placeholderValue != nil && value == field.placeholderValue)
        }, object: nil)
        try require(XCTWaiter.wait(for: [empty], timeout: 5) == .completed,
                    "Native clear must leave an empty query (or its exact placeholder value)")
        return field
    }

    private func openSearchResult(in app: XCUIApplication) throws -> String {
        let rows = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "medication.browse.row."))
        let row = rows.firstMatch
        try reveal(row, in: app)
        try require(rows.count == 1, "The synthetic search must resolve to exactly one real medication row")
        let id = row.identifier
        try require(UUID(uuidString: String(id.dropFirst("medication.browse.row.".count))) != nil,
                    "Browse row identifier must carry a medication UUID")
        row.tap()
        try require(detail(in: app).waitForExistence(timeout: 10), "Real MedicationDetailView was not reached")
        try require(app.navigationBars["药品详情"].exists, "Detail navigation title unavailable")
        return id
    }

    private func returnToSearch(in app: XCUIApplication, rowID: String, query: String = "布洛芬") throws {
        let navigationBack = app.navigationBars["药品详情"].buttons.matching(NSPredicate(
            format: "identifier == %@ OR label == %@ OR label == %@ OR label == %@",
            "BackButton", "药品", "返回", "Back"
        ))
        // Native Duo AX places its BackButton in Toolbar, outside NavigationBar.
        // Both routes must identify exactly one control; never reselect the tab.
        let toolbarBack = app.toolbars.matching(identifier: "Toolbar").buttons.matching(identifier: "BackButton")
        let available = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            guard navigationBack.count <= 1 && toolbarBack.count <= 1 else { return false }
            return (navigationBack.count == 1 && navigationBack.firstMatch.isHittable)
                || (toolbarBack.count == 1 && toolbarBack.firstMatch.isHittable)
        }, object: nil)
        try require(XCTWaiter.wait(for: [available], timeout: 5) == .completed,
                    "A unique hittable native Back control must exist in the detail navigation bar or toolbar")
        let candidates = navigationBack.count == 1 && navigationBack.firstMatch.isHittable
            ? navigationBack : toolbarBack
        try require(candidates.count == 1 && candidates.firstMatch.isHittable,
                    "Native Back must remain unique and hittable at activation")
        let back = candidates.firstMatch
        back.tap()
        let row = app.buttons[rowID]
        let returned = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            row.exists && row.isHittable && row.isSelected
                && app.windows.firstMatch.frame.intersects(row.frame)
        }, object: nil)
        try require(XCTWaiter.wait(for: [returned], timeout: 10) == .completed,
                    "Back must restore the selected UUID row visibly without a test scroll")
        XCTAssertEqual(app.searchFields.firstMatch.value as? String, query, "Back must preserve the search query")
        XCTAssertFalse(detail(in: app).isHittable, "Compact Back must reveal the list rather than leave detail active")
    }

    private func openEditor(in app: XCUIApplication) throws {
        let edit = detail(in: app).buttons["修改药品信息"]
        try reveal(edit, in: app, maxSteps: 45)
        edit.tap()
        try require(app.navigationBars["修改药品"].waitForExistence(timeout: 5), "Real medication editor did not open")
    }

    private func detail(in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)["medicationDetail"].firstMatch
    }

    private func readStore(in app: XCUIApplication, taskCount: Int = 1) throws -> [String: String] {
        try require(app.staticTexts["elder.test.store.task-count"].waitForExistence(timeout: 10), "Store inspector unavailable")
        try require(!app.staticTexts["elder.test.store.error"].exists, "Store inspector failed")
        var values: [String: String] = [:]
        let taskKeys = (0..<taskCount).flatMap { index in
            ["task.\(index).id", "task.\(index).status", "task.\(index).due-offset"]
        }
        for key in ["task-count", "log-count", "save-attempts", "schedule-attempts"] + taskKeys {
            let item = app.staticTexts["elder.test.store." + key]
            try require(item.exists, "Missing observable store field: \(key)")
            values[key] = item.label
        }
        XCTAssertEqual(values["task-count"], String(taskCount))
        for index in 0..<taskCount {
            XCTAssertEqual(values["task.\(index).status"], "pending")
            try require(UUID(uuidString: values["task.\(index).id"] ?? "") != nil,
                        "Observable task identifier must be a UUID")
        }
        XCTAssertEqual(values["log-count"], "0")
        return values
    }

    private func waitForValue(_ value: String, of element: XCUIElement) throws {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", value), object: element)
        try require(XCTWaiter.wait(for: [expectation], timeout: 5) == .completed, "Expected accessibility value \(value)")
    }

    private func reveal(_ element: XCUIElement, in app: XCUIApplication, maxSteps: Int = 20) throws {
        for _ in 0..<maxSteps {
            if element.exists && element.isHittable { return }
            app.swipeUp(velocity: .slow)
        }
        try require(element.exists && element.isHittable, "Synthetic journey element unavailable: \(element.identifier)")
    }

    private func require(_ condition: Bool, _ message: String) throws {
        if !condition {
            if let app = activeFixtureApp { captureFailureEvidence(in: app, reason: message) }
            XCTFail(message)
            throw ObservationFailure.unavailable(message)
        }
    }

    private func finishFixture(_ app: XCUIApplication) {
        if (testRun?.failureCount ?? 0) > 0 {
            captureFailureEvidence(in: app, reason: "Assertion failed in synthetic browse journey")
        }
        app.terminate()
        activeFixtureApp = nil
    }

    private func captureFailureEvidence(in app: XCUIApplication, reason: String) {
        guard !didCaptureFailureEvidence,
              app.launchArguments.contains("--elder-ui-fixture"),
              app.launchArguments.contains("--elder-ui-session"),
              app.state != .notRunning else { return }
        didCaptureFailureEvidence = true
        let field = app.searchFields.firstMatch
        let group = groupContainer(in: app)
        let fieldState = field.exists
            ? "value=\(String(describing: field.value)); placeholder=\(String(describing: field.placeholderValue)); frame=\(field.frame); hittable=\(field.isHittable)"
            : "search field absent"
        let groupState = group.exists
            ? "value=\(String(describing: group.value)); frame=\(group.frame); hittable=\(group.isHittable)"
            : "matching ordinary group absent from current AX tree"
        let summary = "SYNTHETIC BROWSE FAILURE: \(reason)\nSearch: \(fieldState)\nKeyboard exists: \(app.keyboards.firstMatch.exists)\nGroup: \(groupState)"
        let tree = app.debugDescription
        // Console survives even when the unchanged CI lane doesn't upload xcresult.
        // These tests only launch their isolated synthetic fixture, never user data.
        print(summary)
        print("SYNTHETIC BROWSE AX TREE (first 24000 characters):\n" + String(tree.prefix(24_000)))
        let text = XCTAttachment(string: summary + "\n" + tree)
        text.name = "Synthetic browse failure state and accessibility tree"
        text.lifetime = .keepAlways
        add(text)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Synthetic browse failure screen"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    private enum ObservationFailure: Error { case unavailable(String) }
}
