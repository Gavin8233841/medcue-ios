import UIKit
import XCTest

/// Public, out-of-process accessibility observation of the existing real-app fixture.
/// This does not replace the hosted 320/1024/RTL/long-text layout contract.
/// No detail actions are activated. The store check covers only the fields exposed
/// by the existing read-only fixture, not all medication/plan fields or model counts.
@MainActor
final class MedicationDetailAccessibilityUITests: XCTestCase {
    func testRealDetailContentAndControlsAtDefaultTextSize() throws {
        try exerciseDetail(category: "UICTContentSizeCategoryL", name: "default")
    }

    func testRealDetailContentAndControlsAtMaximumTextSize() throws {
        try exerciseDetail(category: "UICTContentSizeCategoryAccessibilityXXXL", name: "AX5")
    }

    private func exerciseDetail(category: String, name: String) throws {
        continueAfterFailure = false
        #if !targetEnvironment(simulator)
        try require(false, "This synthetic fixture must run on Simulator; physical-device execution is not allowed")
        #endif
        let originalOrientation = XCUIDevice.shared.orientation
        defer { XCUIDevice.shared.orientation = originalOrientation }
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = [
            "-AppPersistenceCommitter.failureMessage", "",
            "-DoseActionPersistence.failureMessage", "",
            "-UIPreferredContentSizeCategoryName", category,
            "-hasCompletedFirstLaunchSetup", "YES",
            "-appColorSchemePreference", "light",
            "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN",
            "--elder-ui-mode", "complete", "--elder-ui-fixture", "due",
            "--elder-ui-session", UUID().uuidString,
            "--elder-ui-inspect-store"
        ]
        app.launch()
        defer { app.terminate() }
        let initialStore = try readStore(in: app)
        XCTAssertEqual(initialStore["task-count"], "1")
        XCTAssertEqual(initialStore["task.0.status"], "pending")
        XCTAssertEqual(initialStore["log-count"], "0")
        relaunch(app, inspecting: false)
        try openDetail(in: app)
        try inspectDetail(in: app, name: name + "-portrait-initial")

        if UIDevice.current.userInterfaceIdiom == .pad {
            // Actual iPad window rotation, never a simulated 1024pt iPhone window.
            try rotate(app, to: .landscapeLeft)
            try inspectDetail(in: app, name: name + "-landscape")
            try rotate(app, to: .portrait)
            try inspectDetail(in: app, name: name + "-portrait-restored")
        }
        // The same process/detail route survives every scroll and optional rotation.
        // Relaunch ONLY after those observations, to inspect the same session's store.
        relaunch(app, inspecting: true)
        XCTAssertEqual(try readStore(in: app), initialStore,
                       "Viewing/scrolling/rotation must preserve the fixture's observable persisted state")
    }

    private func openDetail(in app: XCUIApplication) throws {
        let tab = app.tabBars.buttons.element(boundBy: 1)
        try require(tab.waitForExistence(timeout: 10) && tab.isHittable, "Medication tab unavailable")
        tab.tap()
        try require(app.descendants(matching: .any)["tab.medications"].waitForExistence(timeout: 10),
                    "Medication tab did not open")
        // The fixed September 2026 fixture is now classified as interrupted by
        // the real overview clock. Select a nonempty group by its real count,
        // rather than relying on the initial active group or changing app time.
        let selector = app.buttons.matching(NSPredicate(
            format: "label MATCHES %@", "(正在服用|服用中断|归档药物)，1 个药品"
        )).firstMatch
        try reveal(selector, in: app, maxSteps: 15)
        selector.tap()
        let group = app.buttons.matching(NSPredicate(
            format: "label CONTAINS %@ AND label CONTAINS %@", "药品，1 个", "布洛芬"
        )).firstMatch
        try reveal(group, in: app, maxSteps: 15)
        if (group.value as? String) != "已展开" { group.tap() }
        let medication = app.buttons.matching(NSPredicate(
            format: "label CONTAINS %@ AND NOT (label CONTAINS %@)", "布洛芬", "药品，1 个"
        )).firstMatch
        try reveal(medication, in: app, maxSteps: 15)
        medication.tap()
        try require(detail(in: app).waitForExistence(timeout: 10), "Real MedicationDetailView did not open")
    }

    private func inspectDetail(in app: XCUIApplication, name: String) throws {
        let list = detail(in: app)
        try returnToPhotoTop(in: app, list: list)
        let requiredText = ["布洛芬", "药品信息", "疗程与提醒", "暂无剂量变化记录。",
                            "尚未填写药盒剩余量。", "暂无风险提醒。"]
        let requiredButtons = ["更换照片", "修改疗程与提醒", "填写药盒", "修改药品信息"]
        var seenText = Set<String>()
        var seenButtons = Set<String>()
        var reachedLastControl = false
        attach(app, name: name + "-top")
        for _ in 0..<60 {
            let viewport = contentViewport(in: app, list: list)
            try require(!viewport.isEmpty && !viewport.isNull, "Detail has no visible viewport")
            // Public XCTest snapshot, NOT UIKit subview/accessibilityContainer traversal.
            let snapshot = try list.snapshot()
            let nodes = descendants(snapshot)
            for node in nodes where node.elementType == .staticText || node.elementType == .button {
                let frame = node.frame
                guard finite(frame), frame.width > 0, frame.height > 0,
                      viewport.contains(CGPoint(x: frame.midX, y: frame.midY)) else { continue }
                // A button containing a heading's words is not evidence that the
                // actual heading exists. Require the exact real static-text label.
                let matches = node.elementType == .staticText
                    ? requiredText.filter { node.label == $0 } : []
                guard !matches.isEmpty || requiredButtons.contains(node.label) else { continue }
                XCTAssertGreaterThanOrEqual(frame.minX, viewport.minX - 2, "Leading overflow: \(node.label)")
                XCTAssertLessThanOrEqual(frame.maxX, viewport.maxX + 2, "Trailing overflow: \(node.label)")
                seenText.formUnion(matches)
            }
            for label in requiredButtons {
                let button = list.buttons[label].firstMatch
                if button.exists && button.isEnabled && button.isHittable && viewport.contains(button.frame) {
                    seenButtons.insert(label)
                }
            }
            let last = list.buttons["修改药品信息"].firstMatch
            if last.exists && last.isHittable && viewport.contains(last.frame) {
                reachedLastControl = true
                break
            }
            scroll(list, upward: true)
        }
        XCTAssertTrue(reachedLastControl, "Must scroll to the final edit control, without activating it")
        XCTAssertEqual(seenText, Set(requiredText), "Missing visible real detail content")
        XCTAssertEqual(seenButtons, Set(requiredButtons), "Missing enabled, hittable, fully visible real controls")
        // Return in the same live detail route before any rotation or store inspection.
        try returnToPhotoTop(in: app, list: list)
        try require(detail(in: app).exists, "Detail route was lost")
    }

    private func returnToPhotoTop(in app: XCUIApplication, list: XCUIElement) throws {
        let photo = list.staticTexts["药盒或药品照片"].firstMatch
        var previous: CGRect?
        var stationary = 0
        for _ in 0..<60 {
            if photo.exists && contentViewport(in: app, list: list).contains(photo.frame) {
                let frame = photo.frame
                if let previous, abs(previous.minY - frame.minY) < 1,
                   abs(previous.minX - frame.minX) < 1 {
                    stationary += 1
                } else { stationary = 0 }
                previous = frame
                // Two downward scroll attempts cannot move the visible top-section
                // label further. This is observable return-to-top, not an offset API.
                if stationary >= 2 { return }
            } else {
                previous = nil
                stationary = 0
            }
            scroll(list, upward: false)
        }
        try require(false, "Could not return to the stationary real detail photo section")
    }

    private func rotate(_ app: XCUIApplication, to orientation: UIDeviceOrientation) throws {
        let before = app.windows.firstMatch.frame
        XCUIDevice.shared.orientation = orientation
        let changed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            let after = app.windows.firstMatch.frame
            return (orientation.isLandscape ? after.width > after.height : after.height > after.width)
                && abs(after.width - before.width) > 40 && abs(after.height - before.height) > 40
        }, object: nil)
        try require(XCTWaiter.wait(for: [changed], timeout: 10) == .completed,
                    "iPad rotation did not cause a measured window geometry change")
        try require(detail(in: app).exists, "Rotation lost the real detail route")

    }

    private func readStore(in app: XCUIApplication) throws -> [String: String] {
        try require(app.staticTexts["elder.test.store.task-count"].waitForExistence(timeout: 10),
                    "Existing read-only store inspection unavailable")
        try require(!app.staticTexts["elder.test.store.error"].exists, "Store inspection reported an error")
        var values: [String: String] = [:]
        for key in ["task-count", "task.0.id", "task.0.status", "task.0.due-offset", "log-count", "save-attempts"] {
            let item = app.staticTexts["elder.test.store." + key]
            try require(item.exists, "Missing observable store field: \(key)")
            values[key] = item.label
        }
        try require(UUID(uuidString: values["task.0.id"] ?? "") != nil, "Task identifier is not a UUID")
        return values
    }

    private func relaunch(_ app: XCUIApplication, inspecting: Bool) {
        app.terminate()
        app.launchArguments.removeAll { $0 == "--elder-ui-inspect-store" }
        if inspecting { app.launchArguments.append("--elder-ui-inspect-store") }
        app.launch()
    }

    private func detail(in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)["medicationDetail"].firstMatch
    }

    private func descendants(_ node: any XCUIElementSnapshot) -> [any XCUIElementSnapshot] {
        [node] + node.children.flatMap { descendants($0) }
    }

    private func contentViewport(in app: XCUIApplication, list: XCUIElement) -> CGRect {
        var frame = list.frame.intersection(app.windows.firstMatch.frame)
        let navigation = app.navigationBars.firstMatch
        if navigation.exists, navigation.frame.intersects(frame) {
            let top = max(frame.minY, navigation.frame.maxY)
            frame = CGRect(x: frame.minX, y: top, width: frame.width, height: max(0, frame.maxY - top))
        }
        let tabBar = app.tabBars.firstMatch
        if tabBar.exists, tabBar.frame.intersects(frame) {
            frame.size.height = max(0, min(frame.maxY, tabBar.frame.minY) - frame.minY)
        }
        return frame
    }

    private func reveal(_ element: XCUIElement, in app: XCUIApplication, maxSteps: Int) throws {
        for _ in 0..<maxSteps {
            if element.exists && element.isHittable { return }
            app.swipeUp(velocity: .slow)
        }
        try require(element.exists && element.isHittable, "Could not reach navigation element: \(element)")
    }

    private func scroll(_ list: XCUIElement, upward: Bool) {
        let start = list.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: upward ? 0.72 : 0.32))
        let end = list.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: upward ? 0.32 : 0.72))
        start.press(forDuration: 0.05, thenDragTo: end)
    }

    private func finite(_ frame: CGRect) -> Bool {
        frame.minX.isFinite && frame.minY.isFinite && frame.width.isFinite && frame.height.isFinite
    }

    private func attach(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "MedicationDetailAX-" + name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func require(_ condition: Bool, _ message: String) throws {
        if !condition {
            XCTFail(message)
            throw ObservationFailure.unavailable(message)
        }
    }

    private enum ObservationFailure: Error { case unavailable(String) }
}
