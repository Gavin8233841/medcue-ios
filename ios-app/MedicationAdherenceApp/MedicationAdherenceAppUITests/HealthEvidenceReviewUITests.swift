import XCTest

@MainActor
final class HealthEvidenceReviewUITests: XCTestCase {
    func testHealthReviewNavigationRangesRefreshAndReentry() {
        let app = launch(scenario: "populated")
        defer { app.terminate() }
        openHealth(in: app)
        openReview(in: app)
        assertRestingHeartRate("44 次/分", coverage: "7/7", in: app)
        for (days, median) in [(30, "55.5 次/分"), (56, "68.5 次/分"), (7, "44 次/分")] {
            selectRange(days, in: app)
            assertRestingHeartRate(median, coverage: "\(days)/\(days)", in: app)
        }
        for _ in 0..<2 {
            let refresh = app.buttons["health.review.refresh"]
            scrollTo(refresh, in: app, upward: false)
            refresh.tap()
            assertRestingHeartRate("44 次/分", coverage: "7/7", in: app)
        }
        app.navigationBars["健康回顾"].buttons.firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Apple 健康"].waitForExistence(timeout: 5))
        openReview(in: app)
        assertRestingHeartRate("44 次/分", coverage: "7/7", in: app)
        screenshot("health-review-seven-days", in: app)
    }

    func testSleepOnlyReviewKeepsMissingMetricsHonestAtMaximumTextSize() {
        let app = launch(scenario: "sleep-only", accessibilitySize: true, dark: true)
        defer { app.terminate() }
        openHealth(in: app)
        let overview = app.staticTexts["已读取健康回顾记录"]
        scrollTo(overview, in: app)
        XCTAssertFalse(overview.frame.isEmpty)
        let vitalExplanation = app.staticTexts["健康回顾记录已读取；此处仅列心率、血压、血氧、体温和血糖"]
        scrollTo(vitalExplanation, in: app)
        XCTAssertFalse(vitalExplanation.frame.isEmpty)
        openReview(in: app)
        let sleep = app.staticTexts["health.review.sleep.value"]
        scrollTo(sleep, in: app)
        XCTAssertEqual(sleep.label, "8 小时")
        let coverage = app.staticTexts["health.review.sleep.coverage"]
        scrollTo(coverage, in: app)
        XCTAssertTrue(coverage.label.contains("3/7"))
        let source = app.staticTexts["health.review.sleep.source"]
        scrollTo(source, in: app)
        XCTAssertTrue(source.label.contains("UI Fixture"))
        screenshot("health-review-sleep-only-ax5-dark", in: app)
        for metric in ["restingHeartRate", "hrvSDNN", "respiratoryRate"] {
            assertMissing(metric, in: app)
        }
        let question = element("health.review.question.metric", in: app)
        scrollTo(question, in: app)
        question.tap()
        let option = app.buttons["静息心率"]
        XCTAssertTrue(option.waitForExistence(timeout: 5))
        option.tap()
        let answer = app.staticTexts["health.review.answer"]
        scrollTo(answer, in: app)
        XCTAssertTrue(answer.label.contains("静息心率"))
        XCTAssertTrue(answer.label.contains("可读取") || answer.label.contains("没有"))
        screenshot("health-review-missing-answer-ax5-dark", in: app)
    }

    func testConnectedEmptyReviewStaysEmptyAcrossRefreshAndRangeChanges() {
        let app = launch(scenario: "empty")
        defer { app.terminate() }
        openHealth(in: app)
        let disconnect = app.buttons["health.disconnect"]
        scrollTo(disconnect, in: app)
        XCTAssertTrue(disconnect.isHittable, "Completed synthetic authorization must remain distinguishable from disconnect")
        openReview(in: app, upward: false)
        for metric in ["sleep", "restingHeartRate", "hrvSDNN", "respiratoryRate"] {
            assertMissing(metric, in: app)
        }
        selectRange(30, in: app)
        assertMissing("sleep", in: app)
        let refresh = app.buttons["health.review.refresh"]
        scrollTo(refresh, in: app, upward: false)
        refresh.tap()
        assertMissing("restingHeartRate", in: app)
        XCTAssertFalse(app.staticTexts["health.review.restingHeartRate.value"].exists)
        screenshot("health-review-empty", in: app)
    }

    func testDisconnectCancelConfirmAndRelaunchCannotRestoreFixtureRecords() {
        let app = launch(scenario: "populated")
        defer { app.terminate() }
        openHealth(in: app)
        let sharing = app.switches["health.local-summary-sharing"]
        scrollTo(sharing, in: app)
        XCTAssertEqual(sharing.value as? String, "0")
        XCTAssertFalse(sharing.frame.isEmpty)
        sharing.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        XCTAssertEqual(sharing.value as? String, "1")
        // This real management action must hit the fixture's denial, not the OS.
        let manage = app.buttons["管理新增指标读取授权"]
        scrollTo(manage, in: app)
        manage.tap()
        let denied = app.staticTexts["界面测试不会请求 Apple 健康授权。"]
        scrollTo(denied, in: app, upward: false)
        XCTAssertTrue(denied.exists)
        openReview(in: app)
        assertRestingHeartRate("44 次/分", coverage: "7/7", in: app)
        app.navigationBars["健康回顾"].buttons.firstMatch.tap()

        let disconnect = app.buttons["health.disconnect"]
        scrollTo(disconnect, in: app)
        disconnect.tap()
        let alert = app.alerts["停止读取并清除本次健康回顾？"]
        XCTAssertTrue(alert.waitForExistence(timeout: 5), String(app.debugDescription.prefix(8_000)))
        XCTAssertTrue(alert.staticTexts["会关闭健康摘要共享并清除本 App 的内存回顾。Apple 健康原始记录和已有聊天不会删除。"].exists)
        let cancel = alert.buttons["health.disconnect.cancel"].firstMatch
        let confirm = alert.buttons["health.disconnect.confirm"].firstMatch
        XCTAssertTrue(cancel.waitForExistence(timeout: 5))
        XCTAssertTrue(confirm.exists)
        cancel.tap()
        XCTAssertTrue(alert.waitForNonExistence(timeout: 5), String(app.debugDescription.prefix(8_000)))
        XCTAssertTrue(app.navigationBars["Apple 健康"].exists)
        scrollTo(sharing, in: app, upward: false)
        XCTAssertEqual(sharing.value as? String, "1")
        openReview(in: app, upward: false)
        assertRestingHeartRate("44 次/分", coverage: "7/7", in: app)
        app.navigationBars["健康回顾"].buttons.firstMatch.tap()
        scrollTo(disconnect, in: app)
        disconnect.tap()
        XCTAssertTrue(alert.waitForExistence(timeout: 5), String(app.debugDescription.prefix(8_000)))
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        confirm.tap()
        XCTAssertTrue(alert.waitForNonExistence(timeout: 5), String(app.debugDescription.prefix(8_000)))
        let request = app.buttons["health.authorization.request"]
        XCTAssertTrue(request.waitForExistence(timeout: 5))
        scrollTo(sharing, in: app, upward: false)
        XCTAssertEqual(sharing.value as? String, "0")
        openReview(in: app, upward: false)
        assertDisconnectedReview(in: app)
        selectRange(56, in: app)
        app.buttons["health.review.refresh"].tap()
        assertDisconnectedReview(in: app)
        app.navigationBars["健康回顾"].buttons.firstMatch.tap()
        app.navigationBars["Apple 健康"].buttons.firstMatch.tap()
        openHealth(in: app, selectProfileTab: false)
        openReview(in: app)
        assertDisconnectedReview(in: app)

        // Reuse the exact session UUID: reinitializing services or the process
        // must not seed connection/consent again after the user's disconnect.
        app.terminate()
        app.launch()
        openHealth(in: app)
        scrollTo(sharing, in: app)
        XCTAssertEqual(sharing.value as? String, "0")
        openReview(in: app, upward: false)
        assertDisconnectedReview(in: app)
        screenshot("health-review-disconnected-after-relaunch", in: app)
    }

    private func launch(scenario: String, accessibilitySize: Bool = false, dark: Bool = false) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = [
            "--elder-ui-fixture", "due", "--elder-ui-session", UUID().uuidString,
            "--elder-ui-mode", "complete", "--health-review-ui-fixture", scenario,
            "-hasCompletedFirstLaunchSetup", "YES", "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN",
            "-appColorSchemePreference", dark ? "dark" : "light",
            "-UIPreferredContentSizeCategoryName", accessibilitySize
                ? "UICTContentSizeCategoryAccessibilityXXXL" : "UICTContentSizeCategoryL",
            "-AppPersistenceCommitter.failureMessage", "", "-DoseActionPersistence.failureMessage", ""
        ]
        app.launchEnvironment["TZ"] = "UTC"
        app.launch()
        return app
    }

    private func openHealth(in app: XCUIApplication, selectProfileTab: Bool = true) {
        if selectProfileTab {
            let tabs = app.tabBars.firstMatch
            XCTAssertTrue(tabs.waitForExistence(timeout: 10))
            tabs.buttons.element(boundBy: 4).tap()
        }
        let health = app.buttons["profile.health"]
        scrollTo(health, in: app)
        health.tap()
        XCTAssertTrue(app.navigationBars["Apple 健康"].waitForExistence(timeout: 5))
    }

    private func openReview(in app: XCUIApplication, upward: Bool = true) {
        let review = app.buttons["health.review.open"]
        scrollTo(review, in: app, upward: upward)
        review.tap()
        XCTAssertTrue(app.navigationBars["健康回顾"].waitForExistence(timeout: 5))
    }

    private func selectRange(_ days: Int, in app: XCUIApplication) {
        let range = element("health.review.range", in: app)
        scrollTo(range, in: app, upward: false)
        range.tap()
        let option = app.buttons["近 \(days) 天"]
        XCTAssertTrue(option.waitForExistence(timeout: 5))
        option.tap()
    }

    private func assertRestingHeartRate(_ value: String, coverage: String, in app: XCUIApplication) {
        let days = coverage.components(separatedBy: "/")[0]
        let range = element("health.review.range", in: app)
        XCTAssertTrue(range.waitForExistence(timeout: 5))
        let selected = "近 \(days) 天"
        let starts = ["7/7": "2026-09-23", "30/30": "2026-08-31", "56/56": "2026-08-05"]
        let window = app.staticTexts["health.review.window"]
        XCTAssertTrue(window.waitForExistence(timeout: 5))
        let iso = ISO8601DateFormatter()
        let start = iso.date(from: (starts[coverage] ?? "invalid") + "T00:00:00Z")!
        let end = iso.date(from: "2026-09-30T12:00:00Z")!
        let style = Date.FormatStyle(date: .abbreviated, time: .omitted,
            locale: Locale(identifier: "zh_CN"), timeZone: TimeZone(secondsFromGMT: 0)!)
        let expectedWindow = "\(start.formatted(style)) 至 \(end.formatted(style))"
        let settledWindow = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label == %@", expectedWindow), object: window
        )
        XCTAssertEqual(XCTWaiter.wait(for: [settledWindow], timeout: 5), .completed)
        XCTAssertTrue(range.label.contains(selected) || (range.value as? String)?.contains(selected) == true
            || range.staticTexts[selected].exists, "Picker label: \(range.label), value: \(String(describing: range.value))")
        let timeZone = app.staticTexts["health.review.timezone"]
        XCTAssertTrue(timeZone.waitForExistence(timeout: 5))
        XCTAssertEqual(timeZone.label, "回顾时区：Etc/UTC")
        let reading = app.staticTexts["health.review.restingHeartRate.value"]
        scrollTo(reading, in: app)
        // The expected window above has already settled. Dates and facts are
        // rendered from one published bundle; another short polling deadline
        // can expire inside an accessibility query without observing a mismatch.
        // Read once and compare exactly, so a real mismatch reports both values.
        let observedValue = reading.label
        var diagnostic = "Range \(days), settled window: \(expectedWindow)"
        if observedValue != value {
            screenshot("health-review-\(days)-day-value-mismatch", in: app)
            // Only this isolated synthetic fixture is launched by this suite.
            // Keep failure evidence in the log even if CI exports no xcresult.
            diagnostic += "\nObserved window: \(window.label)\n" + String(app.debugDescription.prefix(8_000))
        }
        XCTAssertEqual(observedValue, value, diagnostic)
        let coverageText = app.staticTexts["health.review.restingHeartRate.coverage"]
        scrollTo(coverageText, in: app)
        XCTAssertTrue(coverageText.label.contains(coverage))
        let source = app.staticTexts["health.review.restingHeartRate.source"]
        scrollTo(source, in: app)
        XCTAssertTrue(source.label.contains("UI Fixture"))
        // The deterministic local answer includes an ISO window independent of
        // device date formatting. Do not derive expected dates from the fixture.
        let answer = app.staticTexts["health.review.answer"]
        scrollTo(answer, in: app)
        XCTAssertTrue(answer.label.contains(starts[coverage] ?? "unexpected range"))
        XCTAssertTrue(answer.label.contains("2026-09-30"))
    }

    private func assertMissing(_ metric: String, in app: XCUIApplication) {
        let empty = app.staticTexts["health.review.\(metric).empty"]
        scrollTo(empty, in: app)
        XCTAssertEqual(empty.label, "暂无可用汇总")
        let quality = app.staticTexts["health.review.\(metric).quality.noReadableData"]
        scrollTo(quality, in: app)
        XCTAssertEqual(quality.label, "当前没有可读取的数据，可能尚未记录或未允许读取")
        XCTAssertFalse(app.staticTexts["health.review.\(metric).value"].exists)
    }

    private func assertDisconnectedReview(in app: XCUIApplication) {
        let status = app.staticTexts["health.review.status"]
        XCTAssertTrue(status.waitForExistence(timeout: 5))
        XCTAssertTrue(status.label.contains("尚未完成") || status.label.contains("已停止读取"))
        XCTAssertFalse(app.staticTexts["health.review.restingHeartRate.value"].exists)
        XCTAssertFalse(app.staticTexts["health.review.answer"].exists)
        XCTAssertFalse(app.staticTexts["health.review.window"].exists)
    }

    private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    private func scrollTo(_ element: XCUIElement, in app: XCUIApplication, upward: Bool = true) {
        for _ in 0..<24 {
            if element.exists && element.isHittable { return }
            if upward { app.swipeUp() } else { app.swipeDown() }
        }
        XCTAssertTrue(element.waitForExistence(timeout: 5))
        XCTAssertTrue(element.isHittable)
    }

    private func screenshot(_ name: String, in app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
