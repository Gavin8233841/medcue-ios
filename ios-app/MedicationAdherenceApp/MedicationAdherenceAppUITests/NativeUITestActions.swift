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

    static func button(in owner: XCUIElement, label: String, allowsLabelOnlyLeaf: Bool = false,
                       diagnosticApp: XCUIApplication? = nil) throws -> XCUIElement {
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
        if leaves.count != 1, let app = diagnosticApp {
            SyntheticCompatibilityDiagnostics.action(owner: owner, label: label, leaves: leaves.count,
                                                     app: app, nativeIdentifierRule: !allowsLabelOnlyLeaf)
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

/// Failure-only console metadata for explicit owned synthetic simulator sessions.
/// Unknown text is redacted; no values, frames, paths, screenshots or AX trees.
@MainActor
enum SyntheticCompatibilityDiagnostics {
    private static let textAllowlist: Set<String> = [
        "", "取消", "Cancel", "启用适老模式", "启用适老模式？", "返回完整模式", "返回完整模式？",
        "联系帮助？", "退出合成演示？", "退出演示", "请先完成当前操作", "好",
        "今日", "药品", "智能体", "记录", "个人", "Today", "Profile", "Settings", "完成",
        "演示设置", "应用设置", "这次不吃", "确认这次不吃", "联系帮助",
        "experience-mode.confirm", "experience-mode.cancel", "elder.help.confirm", "elder.help.cancel",
        "demo.mode.confirm", "demo.mode.cancel", "demo.exit.confirm", "demo.settings.open",
        "demo.exit.open", "demo.settings.done", "demo.settings.elder", "tab.today", "tab.profile"
    ]
    private static var events = 0
    private static var lines = 0
    private static var bytes = 0
    private static let kinds = ["native-alert-action", "demo-owned-action", "native-navigation", "demo-settings-after-tap"]
    private static var seen: Set<String> = []
    private static var activeKind = ""
    private static var categoryLines: [String: Int] = [:]
    private static var categoryBytes: [String: Int] = [:]
    private static var detailLines: [String: Int] = [:]
    private static var detailBytes: [String: Int] = [:]
    private static var limitsReported: Set<String> = []
    private static var inDetail = false

    private static func begin(_ kind: String, app: XCUIApplication, summary: @autoclosure () -> String) -> Bool {
        #if targetEnvironment(simulator)
        let args = app.launchArguments
        func uniqueValue(_ flag: String) -> String? {
            let indexes = args.indices.filter { args[$0] == flag }
            guard indexes.count == 1, let index = indexes.first, index + 1 < args.count else { return nil }
            return args[index + 1]
        }
        let elder = uniqueValue("--elder-ui-session").flatMap { UUID(uuidString: $0) } != nil
            && ["due", "future", "help-confirmation"].contains(uniqueValue("--elder-ui-fixture") ?? "")
            && !args.contains("--bundled-demo-session")
        let demo = uniqueValue("--bundled-demo-session").flatMap { UUID(uuidString: $0) } != nil
            && args.contains("--bundled-demo-inspect-store") && !args.contains("--elder-ui-session")
        guard elder || demo, kinds.contains(kind) else { return false }
        activeKind = kind
        inDetail = false
        let first = !seen.contains(kind)
        let reservedFirstEvents = kinds.count - seen.count - (first ? 1 : 0)
        // Repeated categories cannot consume any unseen category's first event.
        guard events < 12 - reservedFirstEvents else {
            reportLimit("repeatEventBudgetReached=true furtherSummariesSuppressed=true", total: true)
            return false
        }
        events += 1
        seen.insert(kind)
        emit("event=\(kind) eventCount=\(events) first=\(first) detailsDeduplicated=\(!first) " + summary())
        inDetail = first
        return first
        #else
        return false
        #endif
    }

    private static func emit(_ fields: String) {
        let output = "[MedCueSyntheticDiagnostic] " + fields
        let size = output.utf8.count + 1
        if inDetail && ((detailLines[activeKind] ?? 0) >= 28 || (detailBytes[activeKind] ?? 0) + size > 3_000) {
            reportLimit("detailBudgetReached=true detailsTruncated=true lineLimit=28 byteLimit=3000", total: false)
            return
        }
        // Four independent 40-line/5KB quotas reserve space for every category.
        // One line and 256 bytes per category are kept for an explicit limit marker.
        guard (categoryLines[activeKind] ?? 0) < 39,
              (categoryBytes[activeKind] ?? 0) + size <= 4_744 else {
            reportLimit("categoryBudgetReached=true furtherOutputSuppressed=true lineLimit=40 byteLimit=5000", total: true)
            return
        }
        write(output)
        if inDetail {
            detailLines[activeKind, default: 0] += 1
            detailBytes[activeKind, default: 0] += size
        }
    }

    private static func reportLimit(_ fields: String, total: Bool) {
        let key = activeKind + (total ? ".total" : ".detail")
        guard !limitsReported.contains(key) else { return }
        limitsReported.insert(key)
        let output = "[MedCueSyntheticDiagnostic] category=\(activeKind) " + fields
        if !total && ((categoryLines[activeKind] ?? 0) >= 39
                     || (categoryBytes[activeKind] ?? 0) + output.utf8.count + 1 > 4_744) {
            reportLimit("categoryBudgetReached=true furtherOutputSuppressed=true", total: true)
            return
        }
        write(output)
    }

    private static func write(_ output: String) {
        let size = output.utf8.count + 1
        guard lines < 160, bytes + size <= 20_000,
              (categoryLines[activeKind] ?? 0) < 40,
              (categoryBytes[activeKind] ?? 0) + size <= 5_000 else { return }
        lines += 1
        bytes += size
        categoryLines[activeKind, default: 0] += 1
        categoryBytes[activeKind, default: 0] += size
        print(output)
    }

    private static func safe(_ text: String) -> String {
        textAllowlist.contains(text) ? text : "<redacted>"
    }

    private static func typeName(_ element: XCUIElement) -> String {
        switch element.elementType {
        case .button: "Button"
        case .staticText: "StaticText"
        case .alert: "Alert"
        case .sheet: "Sheet"
        case .menu: "Menu"
        case .tabBar: "TabBar"
        case .toolbar: "Toolbar"
        case .navigationBar: "NavigationBar"
        case .application: "Application"
        default: "Type\(element.elementType.rawValue)"
        }
    }

    private static func metadata(_ element: XCUIElement, requested: String) -> String {
        let label = element.label
        let identifier = element.identifier
        return "type=\(typeName(element)) label=\(safe(label)) id=\(safe(identifier))"
            + " labelIsRequested=\(label == requested) idIsRequested=\(identifier == requested)"
            + " labelContainsRequested=\(!requested.isEmpty && label.contains(requested)) idIsEmpty=\(identifier.isEmpty)"
            + " enabled=\(element.isEnabled) hittable=\(element.isHittable) selected=\(element.isSelected)"
    }

    static func action(owner: XCUIElement, label: String, leaves: Int,
                       app: XCUIApplication, nativeIdentifierRule: Bool) {
        let kind = nativeIdentifierRule ? "native-alert-action" : "demo-owned-action"
        guard begin(kind, app: app, summary: actionSummary(owner: owner, label: label, leaves: leaves, app: app)) else { return }
        if owner.elementType == .application {
            appMenu(owner: owner, label: label, leaves: leaves, app: app)
            return
        }
        emit("owner \(metadata(owner, requested: label)) leaves=\(leaves)"
             + " alertCount=\(app.alerts.count) nativeIdentifierRule=\(nativeIdentifierRule)")
        let buttons = owner.buttons
        emit("source=owner.buttons buttonCount=\(buttons.count) buttonLimit=6")
        guard owner.elementType == .alert || owner.elementType == .sheet,
              textAllowlist.contains(label) else { return }
        for index in 0..<min(buttons.count, 6) {
            let button = buttons.element(boundBy: index)
            emit("ownedButton index=\(index) \(metadata(button, requested: label))")
            let sameLabel = button.descendants(matching: .button)
                .matching(NSPredicate(format: "label == %@", label)).count
            let identifier = button.identifier
            let inspectID = !identifier.isEmpty && textAllowlist.contains(identifier)
            emit("ownedButton index=\(index) sameLabelButtonDescendants=\(sameLabel) sameIDInspectable=\(inspectID)")
            guard inspectID else { continue }
            let descendants = button.descendants(matching: .any)
                .matching(NSPredicate(format: "identifier == %@", identifier))
            var types: [String: Int] = [:]
            for child in 0..<min(descendants.count, 16) {
                types[typeName(descendants.element(boundBy: child)), default: 0] += 1
            }
            let histogram = types.keys.sorted().map { "\($0):\(types[$0] ?? 0)" }.joined(separator: ",")
            emit("ownedButton index=\(index) sameIDDescendantCount=\(descendants.count)"
                 + " typeLimit=16 typesTruncated=\(descendants.count > 16) sameIDTypes=\(histogram)")
        }
        emit("buttonsTruncated=\(buttons.count > 6)")
    }

    private static func actionSummary(owner: XCUIElement, label: String, leaves: Int, app: XCUIApplication) -> String {
        let base = "ownerType=\(typeName(owner)) requested=\(safe(label)) leaves=\(leaves)"
        guard textAllowlist.contains(label) else { return base + " targetInspectable=false" }
        let predicate = NSPredicate(format: "label == %@", label)
        let result = base + " requestedButtonCount=\(owner.buttons.matching(predicate).count)"
        if owner.elementType == .application {
            return result + " sheetTargetCount=\(app.sheets.buttons.matching(predicate).count)"
                + " menuTargetCount=\(app.descendants(matching: .menu).buttons.matching(predicate).count)"
                + " sheetCount=\(app.sheets.count) menuCount=\(app.descendants(matching: .menu).count)"
        }
        return result + " ownerLabel=\(safe(owner.label)) ownerID=\(safe(owner.identifier))"
    }

    private static func appMenu(owner: XCUIElement, label: String, leaves: Int, app: XCUIApplication) {
        guard ["这次不吃", "确认这次不吃"].contains(label) else {
            emit("ownerType=Application requested=\(safe(label)) menuTargetInspectable=false")
            return
        }
        let predicate = NSPredicate(format: "label == %@", label)
        let targets = owner.buttons.matching(predicate)
        emit("ownerType=Application requested=\(label) leaves=\(leaves)"
             + " requestedButtonCount=\(targets.count) buttonLimit=6")
        for index in 0..<min(targets.count, 6) {
            let target = targets.element(boundBy: index)
            emit("requestedMenuButton index=\(index) \(metadata(target, requested: label))"
                 + " sameLabelButtonDescendants=\(target.descendants(matching: .button).matching(predicate).count)")
        }
        emit("requestedButtonsTruncated=\(targets.count > 6)")
        // Observe possible ownership without choosing a presentation or inspecting its other buttons.
        for (kind, containers) in [("Sheet", app.sheets), ("Menu", app.descendants(matching: .menu))] {
            emit("presentation=\(kind) count=\(containers.count) containerLimit=2")
            for index in 0..<min(containers.count, 2) {
                let container = containers.element(boundBy: index)
                emit("presentation=\(kind) index=\(index) type=\(typeName(container))"
                     + " requestedButtonCount=\(container.buttons.matching(predicate).count)"
                     + " enabled=\(container.isEnabled) hittable=\(container.isHittable)")
            }
            emit("presentation=\(kind) containersTruncated=\(containers.count > 2)")
        }
    }

    static func navigation(label: String, app: XCUIApplication) {
        guard begin("native-navigation", app: app,
                    summary: "requested=\(safe(label)) tabBarCount=\(app.tabBars.count) toolbarCount=\(app.toolbars.count)"
                    + " todayContentCount=\(app.descendants(matching: .any).matching(identifier: "tab.today").count)"
                    + " alertCount=\(app.alerts.count) sheetCount=\(app.sheets.count)") else { return }
        emit("requested=\(safe(label)) tabBarCount=\(app.tabBars.count) toolbarCount=\(app.toolbars.count)"
             + " todayContentCount=\(app.descendants(matching: .any).matching(identifier: "tab.today").count)"
             + " timelineCount=\(app.staticTexts.matching(identifier: "today.timeline.open").count)"
             + " alertCount=\(app.alerts.count) sheetCount=\(app.sheets.count)")
        for (kind, containers) in [("TabBar", app.tabBars), ("Toolbar", app.toolbars)] {
            for index in 0..<min(containers.count, 2) {
                let owner = containers.element(boundBy: index)
                let buttons = owner.buttons
                let matches = buttons.matching(NSPredicate(format: "label == %@", label)).count
                emit("container=\(kind) index=\(index) buttonCount=\(buttons.count) exactLabelCount=\(matches)")
                for child in 0..<min(buttons.count, 6) {
                    emit("container=\(kind) index=\(index) buttonIndex=\(child)"
                         + " \(metadata(buttons.element(boundBy: child), requested: label))")
                }
                emit("container=\(kind) buttonsTruncated=\(buttons.count > 6)")
            }
            emit("container=\(kind) containersTruncated=\(containers.count > 2)")
        }
        presentations(app)
    }

    static func demoSettings(app: XCUIApplication) {
        guard begin("demo-settings-after-tap", app: app,
                    summary: "demoNavigationCount=\(app.navigationBars.matching(identifier: "演示设置").count)"
                    + " sheetCount=\(app.sheets.count) alertCount=\(app.alerts.count)") else { return }
        // These are observed header states, not evidence of the internal canCommit closure.
        for identifier in ["demo.settings.open", "demo.exit.open"] {
            let buttons = app.buttons.matching(identifier: identifier)
            emit("header id=\(identifier) count=\(buttons.count)")
            if buttons.count == 1 {
                emit("header \(metadata(buttons.element(boundBy: 0), requested: identifier))")
            }
        }
        emit("sheetCount=\(app.sheets.count) demoModeSwitchCount="
             + "\(app.switches.matching(identifier: "demo.settings.elder").count)"
             + " doneButtonCount=\(app.buttons.matching(identifier: "demo.settings.done").count)")
        presentations(app)
    }

    private static func presentations(_ app: XCUIApplication) {
        for title in ["请先完成当前操作", "启用适老模式？", "返回完整模式？", "联系帮助？", "退出合成演示？"] {
            let alerts = app.alerts.matching(NSPredicate(format: "identifier == %@ OR label == %@", title, title))
            emit("knownAlert title=\(title) count=\(alerts.count)")
        }
        emit("navigationBarCount=\(app.navigationBars.count) demoNavigationCount="
             + "\(app.navigationBars.matching(identifier: "演示设置").count)")
        for index in 0..<min(app.navigationBars.count, 4) {
            emit("navigationBar index=\(index) \(metadata(app.navigationBars.element(boundBy: index), requested: "演示设置"))")
        }
        emit("navigationBarsTruncated=\(app.navigationBars.count > 4)")
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
            // Containment is only a necessary-condition prefilter. Keep the
            // complete qualification and deepest-owner ambiguity checks below.
            let candidates = app.otherElements.containing(.navigationBar, identifier: "应用设置")
            let owners = candidates.allElementsBoundByIndex.filter { owner in
                qualifies(owner) && !owner.descendants(matching: .other)
                    .containing(.navigationBar, identifier: "应用设置")
                    .allElementsBoundByIndex.contains(where: qualifies)
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
            // Counts belong only to this mutation-free validation call. Query
            // again on the next operation, never across gestures or focus.
            let globalCount = global.count
            guard globalCount <= 1 else { try fail("ambiguous-target") }
            let ownedCount = owned.count
            guard ownedCount <= 1 else { try fail("ambiguous-target") }
            let rowCount = rows.count
            guard rowCount <= 1 else { try fail("ambiguous-target") }
            guard rowCount == 1 else {
                if globalCount > 0 || ownedCount > 0 { try fail("target-outside-owned-list") }
                return nil
            }
            guard globalCount == 1, ownedCount == 1 else { try fail("target-membership") }
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
private enum SyntheticSkipDismissDiagnostics {
    private static var seen: Set<String> = []

    /// Observe named surfaces only. Window membership is not presentation ownership.
    /// Never use these candidates to select or perform a cancellation action.
    static func record(in app: XCUIApplication, sheet: XCUIElement, stage: String) {
        #if targetEnvironment(simulator)
        guard ["before-outside-tap", "after-dismiss-timeout"].contains(stage) else { return }
        let args = app.launchArguments
        func uniqueValue(_ flag: String) -> String? {
            let indexes = args.indices.filter { args[$0] == flag }
            guard indexes.count == 1, let index = indexes.first, index + 1 < args.count else { return nil }
            return args[index + 1]
        }
        let demo = uniqueValue("--bundled-demo-session").flatMap { UUID(uuidString: $0) } != nil
            && args.contains("--bundled-demo-inspect-store") && !args.contains("--elder-ui-session")
        let elder = uniqueValue("--elder-ui-session").flatMap { UUID(uuidString: $0) } != nil
            && ["due", "future", "help-confirmation"].contains(uniqueValue("--elder-ui-fixture") ?? "")
            && ["complete", "elder"].contains(uniqueValue("--elder-ui-mode") ?? "")
            && !args.contains("--bundled-demo-session")
        guard demo || elder else { return }
        let host = demo ? "demo" : "elder"
        guard seen.insert(host + "." + stage).inserted else { return }

        // Four possible host/stage events, each at most seven bounded lines.
        // No values, identifiers, frames, arbitrary strings or hierarchy dumps.
        let names = ["取消", "Cancel", "关闭", "Close", "Dismiss"]
        let named = NSPredicate(format: "label IN %@", names as NSArray)
        let skip = NSPredicate(format: "label == %@", "确认这次不吃")
        func emit(_ fields: String) {
            print("[MedCueSkipDismissDiagnostic] host=\(host) stage=\(stage) " + fields)
        }
        let windows = app.windows
        let buttons = app.buttons.matching(named)
        let windowCount = windows.count
        let buttonCount = buttons.count
        emit("sheetExists=\(sheet.exists) windowCount=\(windowCount) namedButtonCount=\(buttonCount)"
             + " windowsTruncated=\(windowCount > 2) buttonsTruncated=\(buttonCount > 3)")
        if sheet.exists {
            emit("sheetEnabled=\(sheet.isEnabled) sheetHittable=\(sheet.isHittable)"
                 + " sheetSkipCount=\(sheet.buttons.matching(skip).count) sheetNamedCount=\(sheet.buttons.matching(named).count)")
        }
        for index in 0..<min(windowCount, 2) {
            let window = windows.element(boundBy: index)
            emit("windowIndex=\(index) enabled=\(window.isEnabled) hittable=\(window.isHittable)"
                 + " scopedSkipCount=\(window.buttons.matching(skip).count) scopedNamedCount=\(window.buttons.matching(named).count)")
        }
        for index in 0..<min(buttonCount, 3) {
            let button = buttons.element(boundBy: index)
            let label = button.label
            // Re-resolution may change a label. Never print a non-allowlisted result.
            let safeLabel = names.contains(label) ? label : "<redacted>"
            emit("buttonIndex=\(index) label=\(safeLabel) identifierEmpty=\(button.identifier.isEmpty)"
                 + " enabled=\(button.isEnabled) hittable=\(button.isHittable) childButtonCount=\(button.descendants(matching: .button).count)")
        }
        #endif
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
            SyntheticSkipDismissDiagnostics.record(in: app, sheet: sheet, stage: "before-outside-tap")
            // This point is geometrically outside the Sheet. Geometry alone
            // does not establish a dismiss surface; keep the dismissal and
            // caller's store invariants as the required evidence.
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
        let result = XCTWaiter.wait(for: [gone], timeout: 5)
        if result != .completed {
            SyntheticSkipDismissDiagnostics.record(in: app, sheet: sheet, stage: "after-dismiss-timeout")
        }
        XCTAssertEqual(result, .completed)
        XCTAssertFalse(app.buttons["确认这次不吃"].exists)
        XCTAssertTrue(app.buttons["elder.settings"].isHittable)
        XCTAssertTrue(app.buttons["elder.switch-to-complete"].isHittable)
    }
}
