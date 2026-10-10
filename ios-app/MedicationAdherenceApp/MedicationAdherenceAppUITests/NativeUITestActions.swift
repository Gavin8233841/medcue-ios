import UIKit
import XCTest

private enum NativeUITestLookupError: Error { case ambiguousElement, missingDismissRegion }

/// Handles the observed parent/child AX duplication inside one system alert.
/// Never chooses between two leaves or between multiple alert owners.
@MainActor
enum NativeAlertTestActions {
    static func alert(in app: XCUIApplication, title: String) throws -> XCUIElement {
        try uniqueAlert(app.alerts.matching(NSPredicate(format: "identifier == %@ OR label == %@", title, title)))
    }

    static func modeAlert(in app: XCUIApplication) throws -> XCUIElement {
        let titles = ["启用适老模式？", "返回完整模式？"]
        return try uniqueAlert(app.alerts.matching(NSPredicate(format: "identifier IN %@ OR label IN %@", titles as NSArray, titles as NSArray)))
    }

    static func waitForDismissal(of alert: XCUIElement) {
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: alert)
        XCTAssertEqual(XCTWaiter.wait(for: [gone], timeout: 5), .completed,
                       "The exact alert must close before querying its underlying owner again")
    }

    static func button(in owner: XCUIElement, label: String, allowsLabelOnlyLeaf: Bool = false) throws -> XCUIElement {
        let candidates = owner.buttons.matching(NSPredicate(format: "label == %@", label))
        let leaves = candidates.allElementsBoundByIndex.filter { candidate in
            if allowsLabelOnlyLeaf {
                // Only the caller's verified unique Sheet opts into native
                // actions without a custom ID. Text children are not actions.
                return candidate.descendants(matching: .button)
                    .matching(NSPredicate(format: "label == %@", label)).count == 0
            }
            guard !candidate.identifier.isEmpty else { return false }
            return candidate.descendants(matching: .any)
                .matching(NSPredicate(format: "identifier == %@", candidate.identifier)).count == 0
        }
        XCTAssertEqual(leaves.count, 1, "Exactly one leaf must own this action within the verified presentation")
        guard leaves.count == 1, let button = leaves.first else { throw NativeUITestLookupError.ambiguousElement }
        XCTAssertTrue(button.isHittable)
        return button
    }

    private static func uniqueAlert(_ alerts: XCUIElementQuery) throws -> XCUIElement {
        XCTAssertTrue(alerts.element(boundBy: 0).waitForExistence(timeout: 5))
        XCTAssertEqual(alerts.count, 1, "The requested native alert title must have one owner")
        guard alerts.count == 1 else { throw NativeUITestLookupError.ambiguousElement }
        return alerts.element(boundBy: 0)
    }
}

@MainActor
enum NativeListTestActions {
    /// The captured Settings sheet has a non-hittable CollectionView containing
    /// hittable controls. Only this verified owner may use that scroll host.
    static func revealSettings(
        identifier: String, type: XCUIElement.ElementType,
        in app: XCUIApplication, towardTop: Bool
    ) throws -> XCUIElement {
        let diagnosticTarget = app.descendants(matching: type).matching(identifier: identifier).element(boundBy: 0)
        func fail(_ reason: String) throws -> Never {
            captureFailure("settings-\(reason)", target: diagnosticTarget, app: app)
            XCTFail("The foreground Settings owner/List must be unambiguous: \(reason)")
            throw NativeUITestLookupError.ambiguousElement
        }
        guard ["settings.experience-mode", "settings.elder-help.phone"].contains(identifier) else {
            try fail("unsupported-target")
        }
        func context() throws -> (owner: XCUIElement, list: XCUIElement) {
            let navigation = app.navigationBars.matching(identifier: "应用设置")
            guard navigation.count == 1, navigation.element(boundBy: 0).exists, app.alerts.count == 0 else {
                try fail("navigation-owner")
            }
            func qualifies(_ owner: XCUIElement) -> Bool {
                owner.navigationBars.matching(identifier: "应用设置").count == 1
                    && settingsNodes(in: owner).count > 0
                    && !nativeLists(in: owner).isEmpty
            }
            // A SwiftUI sheet may be nested Others without an AX Sheet. Remove
            // every outer wrapper that contains another qualifying owner.
            let owners = app.otherElements.allElementsBoundByIndex.filter { owner in
                qualifies(owner) && !owner.descendants(matching: .other).allElementsBoundByIndex.contains(where: qualifies)
            }
            guard owners.count == 1, let owner = owners.first else { try fail("deepest-owner-count=\(owners.count)") }
            let lists = nativeLists(in: owner)
            guard lists.count == 1, let list = lists.first else { try fail("owned-list-count=\(lists.count)") }
            let frame = list.frame
            guard list.exists, list.isEnabled,
                  frame.origin.x.isFinite, frame.origin.y.isFinite,
                  frame.width.isFinite, frame.height.isFinite, frame.width > 0, frame.height > 0,
                  list.descendants(matching: .table).count == 0,
                  list.descendants(matching: .collectionView).count == 0,
                  settingsNodes(in: list).count > 0 else { try fail("invalid-owned-list") }
            if !list.isHittable {
                let interactiveSetting = settingsNodes(in: list).allElementsBoundByIndex.contains { control in
                    [.switch, .textField, .button].contains(control.elementType)
                        && control.exists && control.isEnabled && control.isHittable
                }
                let done = owner.navigationBars.matching(identifier: "应用设置").element(boundBy: 0)
                    .buttons.matching(NSPredicate(format: "label == %@", "完成"))
                let interactiveDone = done.count == 1 && done.element(boundBy: 0).exists
                    && done.element(boundBy: 0).isEnabled && done.element(boundBy: 0).isHittable
                guard interactiveSetting || interactiveDone else { try fail("no-interactive-owned-control") }
            }
            return (owner, list)
        }
        func visibleTarget(in context: (owner: XCUIElement, list: XCUIElement)) throws -> XCUIElement? {
            // Queries are reconstructed after every gesture; an old global AX
            // handle cannot stand in for membership in the current owned List.
            let global = app.descendants(matching: type).matching(identifier: identifier)
            let owned = context.owner.descendants(matching: type).matching(identifier: identifier)
            let rows = context.list.descendants(matching: type).matching(identifier: identifier)
            guard global.count <= 1, owned.count <= 1, rows.count <= 1 else { try fail("ambiguous-target") }
            guard rows.count == 1 else {
                if global.count > 0 || owned.count > 0 { try fail("target-outside-owned-list") }
                return nil
            }
            guard global.count == 1, owned.count == 1 else { try fail("target-membership") }
            let target = rows.element(boundBy: 0)
            guard target.exists, target.isEnabled, target.isHittable else { return nil }
            guard context.list.frame.intersects(target.frame) else { try fail("target-outside-list-frame") }
            if identifier == "settings.elder-help.phone" {
                // Membership was proved in this current owner/List above. The
                // returned phone query must not retain an Other positional
                // ancestor that keyboard focus/input can replace afterward.
                guard type == .textField else { try fail("unsupported-phone-type") }
                let current = global.element(boundBy: 0)
                guard current.exists, current.isEnabled, current.isHittable,
                      current.frame == target.frame,
                      current.descendants(matching: .textField).count == 0 else {
                    try fail("phone-identity-after-membership-check")
                }
                return current
            }
            return target
        }
        for down in [towardTop, !towardTop] {
            for _ in 0..<6 {
                let current = try context()
                if let target = try visibleTarget(in: current) { return target }
                if down { current.list.swipeDown() } else { current.list.swipeUp() }
            }
        }
        let current = try context()
        if let target = try visibleTarget(in: current) { return target }
        try fail("bounded-scroll-exhausted")
    }

    private static func nativeLists(in owner: XCUIElement) -> [XCUIElement] {
        owner.tables.allElementsBoundByIndex + owner.collectionViews.allElementsBoundByIndex
    }

    private static func settingsNodes(in owner: XCUIElement) -> XCUIElementQuery {
        owner.descendants(matching: .any).matching(NSPredicate(format: "identifier IN %@", [
            "settings.experience-mode", "settings.elder-help.phone", "settings.elder-help.save", "settings.elder-help.remove"
        ] as NSArray))
    }

    static func reveal(_ target: XCUIElement, in app: XCUIApplication, towardTop: Bool) throws {
        if target.exists && target.isHittable { return }
        let candidates = (app.tables.allElementsBoundByIndex + app.collectionViews.allElementsBoundByIndex)
            .filter { list in
                list.isHittable && list.frame.height > 0
                    && list.descendants(matching: .table).count == 0
                    && list.descendants(matching: .collectionView).count == 0
            }
        if candidates.count != 1 {
            captureFailure("foreground-list-count=\(candidates.count)", target: target, app: app)
        }
        XCTAssertEqual(candidates.count, 1, "Only the foreground native List may be scrolled")
        guard candidates.count == 1, let list = candidates.first else { throw NativeUITestLookupError.ambiguousElement }
        for down in [towardTop, !towardTop] {
            for _ in 0..<6 {
                if target.exists && target.isHittable {
                    if !list.frame.intersects(target.frame) {
                        captureFailure("target-outside-selected-list", target: target, app: app)
                    }
                    XCTAssertTrue(list.frame.intersects(target.frame))
                    return
                }
                if down { list.swipeDown() } else { list.swipeUp() }
            }
        }
        let targetExists = target.exists
        let targetHittable = target.isHittable
        let targetIntersectsList = list.frame.intersects(target.frame)
        if !targetExists || !targetHittable || !targetIntersectsList {
            captureFailure("bounded-scroll-exhausted", target: target, app: app)
        }
        XCTAssertTrue(target.exists)
        XCTAssertTrue(target.isHittable)
        XCTAssertTrue(list.frame.intersects(target.frame))
    }

    private static func captureFailure(_ reason: String, target: XCUIElement, app: XCUIApplication) {
        // AX dumps and screenshots are permitted only for a valid synthetic fixture.
        let arguments = app.launchArguments
        func value(after flag: String) -> String? {
            let indices = arguments.indices.filter { arguments[$0] == flag }
            guard indices.count == 1, let index = indices.first, arguments.indices.contains(index + 1) else { return nil }
            return arguments[index + 1]
        }
        let scenarios = Set(["due", "future", "multiple", "future-multiple", "empty", "idle-followup", "midnight",
                             "help-missing", "help-unavailable", "help-confirmation"])
        guard let scenario = value(after: "--elder-ui-fixture"), scenarios.contains(scenario),
              let session = value(after: "--elder-ui-session"), UUID(uuidString: session) != nil,
              let mode = value(after: "--elder-ui-mode"), ["complete", "elder"].contains(mode)
        else { return }
        XCTContext.runActivity(named: "Native List failure evidence: \(reason)") { activity in
            var sections = ["reason: \(reason)", "fixture: \(scenario), initial mode: \(mode)",
                            "APP\n\(app.debugDescription)", "TARGET\n\(target.debugDescription)",
                            "WINDOWS\n\(app.windows.debugDescription)", "SHEETS\n\(app.sheets.debugDescription)",
                            "NAVIGATION BARS\n\(app.navigationBars.debugDescription)"]
            let allLists = app.tables.allElementsBoundByIndex + app.collectionViews.allElementsBoundByIndex
            sections.append("all native list candidates: \(allLists.count)")
            for (index, candidate) in allLists.enumerated() {
                // Read every value independently: no && short-circuit can hide a rejection reason.
                let exists = candidate.exists
                let enabled = candidate.isEnabled
                let hittable = candidate.isHittable
                let frame = candidate.frame
                let directTables = candidate.children(matching: .table).count
                let directCollections = candidate.children(matching: .collectionView).count
                let descendantTables = candidate.descendants(matching: .table).count
                let descendantCollections = candidate.descendants(matching: .collectionView).count
                sections.append("LIST[\(index)] type=\(candidate.elementType) id=\(candidate.identifier) label=\(candidate.label)\n"
                    + "exists=\(exists) enabled=\(enabled) hittable=\(hittable) frame=\(frame)\n"
                    + "direct tables=\(directTables) collections=\(directCollections) "
                    + "descendant tables=\(descendantTables) collections=\(descendantCollections)\n"
                    + candidate.debugDescription)
            }
            let hierarchy = XCTAttachment(string: sections.joined(separator: "\n\n"))
            hierarchy.name = "native-list-\(reason)-hierarchy"
            hierarchy.lifetime = .keepAlways
            activity.add(hierarchy)
            let screenshot = XCTAttachment(screenshot: app.screenshot())
            screenshot.name = "native-list-\(reason)-screenshot-unvalidated"
            screenshot.lifetime = .keepAlways
            activity.add(screenshot)
        }
    }
}

/// The native AX capture exposes an unnamed direct Switch inside the ID row.
/// Its identity comes from that unique parent and verified structure, not labels.
@MainActor
enum NativeSettingsModeSwitchTestActions {
    static func control(in app: XCUIApplication) throws -> XCUIElement {
        try leaf(in: parent(in: app))
    }

    static func tap(in app: XCUIApplication, expectedValue: String, expectingAlert title: String) throws {
        let row = try parent(in: app)
        let control = try leaf(in: row)
        XCTAssertEqual(control.value as? String, expectedValue)
        control.tap()
        _ = try NativeAlertTestActions.alert(in: app, title: title)
        // The modal may remove the underlying Switch from AX. Its old handle
        // is valid only before tap; callers requery after exact-alert dismissal.
        XCTAssertTrue(app.navigationBars["应用设置"].exists, "The original Settings owner must remain until confirmation")
    }

    private static func parent(in app: XCUIApplication) throws -> XCUIElement {
        XCTAssertTrue(app.navigationBars["应用设置"].exists)
        let rows = app.switches.matching(identifier: "settings.experience-mode")
        let row = try NativeListTestActions.revealSettings(
            identifier: "settings.experience-mode", type: .switch, in: app, towardTop: true
        )
        XCTAssertEqual(rows.count, 1, "The mode Switch ID must identify exactly one parent")
        guard rows.count == 1 else { throw NativeUITestLookupError.ambiguousElement }
        XCTAssertTrue(row.exists)
        XCTAssertTrue(row.isEnabled)
        XCTAssertTrue(row.isHittable)
        return row
    }

    private static func leaf(in parent: XCUIElement) throws -> XCUIElement {
        let direct = parent.children(matching: .switch)
        XCTAssertLessThanOrEqual(direct.count, 1, "Multiple direct Switch children are ambiguous")
        guard direct.count <= 1 else { throw NativeUITestLookupError.ambiguousElement }
        let control: XCUIElement
        if direct.count == 1 {
            control = direct.element(boundBy: 0)
            let descendants = parent.descendants(matching: .switch).count
            XCTAssertEqual(descendants, 1,
                           "The parent must contain only this direct Switch")
            guard descendants == 1 else { throw NativeUITestLookupError.ambiguousElement }
        } else {
            let descendants = parent.descendants(matching: .switch).count
            XCTAssertEqual(descendants, 0,
                           "Use the parent only when it is structurally a leaf")
            guard descendants == 0 else { throw NativeUITestLookupError.ambiguousElement }
            control = parent
        }
        XCTAssertEqual(control.descendants(matching: .switch).count, 0)
        XCTAssertTrue(control.exists)
        XCTAssertTrue(control.isEnabled)
        XCTAssertTrue(control.isHittable)
        return control
    }
}

@MainActor
enum NativeConfirmationDialogTestActions {
    static func dismissSkip(in app: XCUIApplication) throws {
        let sheets = app.sheets.allElementsBoundByIndex.filter {
            $0.buttons.matching(NSPredicate(format: "label == %@", "确认这次不吃")).count > 0
        }
        XCTAssertEqual(sheets.count, 1, "The actual skip presentation must have one owner")
        guard sheets.count == 1, let sheet = sheets.first else { throw NativeUITestLookupError.ambiguousElement }
        let cancel = sheet.buttons.matching(NSPredicate(format: "label == %@", "取消"))
        if cancel.count > 0 {
            try NativeAlertTestActions.button(in: sheet, label: "取消", allowsLabelOnlyLeaf: true).tap()
        } else {
            // SwiftUI documents outside-tap dismissal for regular popovers.
            // The observed Duo Sheet exposes no named cancel; require an
            // actual outside region, then verify dismissal and store invariants.
            let windows = app.windows.allElementsBoundByIndex.filter { $0.isHittable }
            XCTAssertEqual(windows.count, 1)
            guard windows.count == 1, let window = windows.first else { throw NativeUITestLookupError.ambiguousElement }
            let bounds = window.frame
            let points = [CGPoint(x: bounds.minX + 24, y: bounds.midY),
                          CGPoint(x: bounds.maxX - 24, y: bounds.midY),
                          CGPoint(x: bounds.midX, y: bounds.minY + 100)]
            guard let point = points.first(where: { bounds.contains($0) && !sheet.frame.insetBy(dx: -8, dy: -8).contains($0) }) else {
                XCTFail("This native presentation has no verified outside dismissal region")
                throw NativeUITestLookupError.missingDismissRegion
            }
            window.coordinate(withNormalizedOffset: .zero)
                .withOffset(CGVector(dx: point.x - bounds.minX, dy: point.y - bounds.minY)).tap()
        }
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: sheet)
        XCTAssertEqual(XCTWaiter.wait(for: [gone], timeout: 5), .completed)
        XCTAssertFalse(app.buttons["确认这次不吃"].exists)
        XCTAssertTrue(app.buttons["elder.settings"].isHittable)
        XCTAssertTrue(app.buttons["elder.switch-to-complete"].isHittable)
    }
}
