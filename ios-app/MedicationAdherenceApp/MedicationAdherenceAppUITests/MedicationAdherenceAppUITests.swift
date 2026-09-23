import XCTest

@MainActor
final class MedicationAdherenceAppUITests: XCTestCase {
    private let clearedPersistenceFailureArguments = [
        "-AppPersistenceCommitter.failureMessage", "",
        "-DoseActionPersistence.failureMessage", "",
        "--ui-testing-in-memory-store"
    ]

    func testPrimaryTabsAreReachable() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = clearedPersistenceFailureArguments + [
            "-hasCompletedFirstLaunchSetup", "YES"
        ]
        app.launch()

        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 10))

        let identifiers = [
            "tab.today",
            "tab.medications",
            "tab.assistant",
            "tab.records",
            "tab.profile"
        ]
        XCTAssertEqual(tabBar.buttons.count, identifiers.count)
        for (index, identifier) in identifiers.enumerated() {
            let tab = tabBar.buttons.element(boundBy: index)
            XCTAssertTrue(tab.waitForExistence(timeout: 5), "Missing tab at index: \(index)")
            tab.tap()
            XCTAssertTrue(tab.isSelected, "Tab did not become selected: \(identifier)")
            XCTAssertTrue(
                app.descendants(matching: .any)[identifier].waitForExistence(timeout: 5),
                "Missing content identifier: \(identifier)"
            )
            if identifier == "tab.assistant" {
                dismissAssistantGatesIfPresented(in: app)
            }
        }
    }

    private func dismissAssistantGatesIfPresented(in app: XCUIApplication) {
        let noticeAcceptButton = app.buttons["assistant.thirdPartyNotice.accept"]
        if noticeAcceptButton.waitForExistence(timeout: 5) {
            noticeAcceptButton.tap()
            XCTAssertTrue(
                noticeAcceptButton.waitForNonExistence(timeout: 5),
                "Third-party notice did not dismiss"
            )
        }

        let consentCancelButton = app.buttons["assistant.consent.cancel"]
        if consentCancelButton.waitForExistence(timeout: 5) {
            consentCancelButton.tap()
            XCTAssertTrue(
                consentCancelButton.waitForNonExistence(timeout: 5),
                "AI consent sheet did not dismiss"
            )
        }
    }

    func testFirstLaunchOffersProgressAndSkipActions() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = clearedPersistenceFailureArguments + ["-showFirstLaunch"]
        app.launch()

        let nextButton = app.buttons["firstLaunch.next"]
        let skipButton = app.buttons["firstLaunch.skip"]
        XCTAssertTrue(nextButton.waitForExistence(timeout: 10))
        XCTAssertTrue(skipButton.waitForExistence(timeout: 5))
        XCTAssertFalse(app.alerts["更改未能保存"].exists)

        nextButton.tap()
        XCTAssertTrue(nextButton.waitForExistence(timeout: 5))
        XCTAssertTrue(skipButton.exists)
    }

    func testMedicationAndRiskSearchFlows() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = clearedPersistenceFailureArguments + [
            "-hasCompletedFirstLaunchSetup", "YES",
            "--seed-demo-data"
        ]
        app.launch()

        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 10))
        tabBar.buttons.element(boundBy: 1).tap()

        let medicationSearch = app.searchFields.firstMatch
        XCTAssertTrue(medicationSearch.waitForExistence(timeout: 10))
        XCTAssertFalse(medicationSearch.label.isEmpty)
        medicationSearch.tap()
        medicationSearch.typeText("Ibuprofen")

        let medicationResult = app.staticTexts["布洛芬"].firstMatch
        XCTAssertTrue(medicationResult.waitForExistence(timeout: 10))
        medicationResult.tap()
        XCTAssertTrue(app.navigationBars["药品详情"].waitForExistence(timeout: 5))
        app.navigationBars["药品详情"].buttons.element(boundBy: 0).tap()

        let restoredMedicationSearch = app.searchFields.firstMatch
        XCTAssertTrue(restoredMedicationSearch.waitForExistence(timeout: 5))
        clearSearchField(restoredMedicationSearch)
        let restoredMedicationGroup = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "当前用药")
        ).firstMatch
        XCTAssertTrue(restoredMedicationGroup.waitForExistence(timeout: 5))
        XCTAssertTrue(String(describing: restoredMedicationGroup.value).contains("已折叠"))
        XCTAssertTrue(restoredMedicationGroup.label.contains("人工泪液"))

        restoredMedicationSearch.tap()
        restoredMedicationSearch.typeText("synthetic-no-result-query")
        XCTAssertTrue(
            app.staticTexts.matching(
                NSPredicate(format: "label CONTAINS %@", "synthetic-no-result-query")
            ).firstMatch.waitForExistence(timeout: 5)
        )
        clearSearchField(restoredMedicationSearch)

        app.swipeDown()
        app.swipeDown()
        let riskReview = app.staticTexts["风险复核"].firstMatch
        XCTAssertTrue(riskReview.waitForExistence(timeout: 5))
        XCTAssertTrue(riskReview.isHittable)
        riskReview.tap()

        let riskSearch = app.searchFields.firstMatch
        XCTAssertTrue(riskSearch.waitForExistence(timeout: 10))
        XCTAssertFalse(riskSearch.label.isEmpty)
        riskSearch.tap()
        riskSearch.typeText("ibuprofen")
        let ibuprofenRiskGroup = app.buttons["布洛芬"].firstMatch
        XCTAssertTrue(ibuprofenRiskGroup.waitForExistence(timeout: 10))
        ibuprofenRiskGroup.tap()
        XCTAssertTrue(String(describing: ibuprofenRiskGroup.value).contains("已展开"))

        let riskCard = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "risk.card.")
        ).firstMatch
        XCTAssertTrue(riskCard.waitForExistence(timeout: 5))
        let archivedRiskCardIdentifier = riskCard.identifier
        riskCard.tap()
        XCTAssertTrue(app.navigationBars["警示详情"].waitForExistence(timeout: 5))
        let archiveButton = app.buttons["标记已复核并归档"]
        XCTAssertTrue(archiveButton.waitForExistence(timeout: 5))
        archiveButton.tap()
        XCTAssertTrue(app.buttons["重新打开警示"].waitForExistence(timeout: 5))
        app.navigationBars["警示详情"].buttons.element(boundBy: 0).tap()

        let restoredRiskSearch = app.searchFields.firstMatch
        XCTAssertTrue(restoredRiskSearch.waitForExistence(timeout: 5))
        let archivedIbuprofenRiskGroup = app.buttons.matching(
            NSPredicate(format: "label == %@", "布洛芬")
        ).element(boundBy: 1)
        scrollToElement(archivedIbuprofenRiskGroup, in: app)
        archivedIbuprofenRiskGroup.tap()
        let archivedCardsDisclosure = app.buttons["已复核归档"]
        scrollToElement(archivedCardsDisclosure, in: app)
        archivedCardsDisclosure.tap()
        XCTAssertTrue(app.buttons[archivedRiskCardIdentifier].waitForExistence(timeout: 5))

        app.swipeDown()
        app.swipeDown()
        clearSearchField(restoredRiskSearch)
        restoredRiskSearch.tap()
        restoredRiskSearch.typeText("loratadine")
        XCTAssertTrue(app.buttons["氯雷他定"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["布洛芬"].firstMatch.waitForNonExistence(timeout: 5))

        clearSearchField(restoredRiskSearch)
        app.swipeDown()
        app.swipeDown()
        let restoredIbuprofenRiskGroup = app.buttons["布洛芬"].firstMatch
        XCTAssertTrue(restoredIbuprofenRiskGroup.waitForExistence(timeout: 5))
        XCTAssertTrue(String(describing: restoredIbuprofenRiskGroup.value).contains("已展开"))
        let restoredArchivedIbuprofenRiskGroup = app.buttons.matching(
            NSPredicate(format: "label == %@", "布洛芬")
        ).element(boundBy: 1)
        scrollToElement(restoredArchivedIbuprofenRiskGroup, in: app)
        XCTAssertTrue(String(describing: restoredArchivedIbuprofenRiskGroup.value).contains("已展开"))
        let restoredArchivedCardsDisclosure = app.buttons["已复核归档"]
        scrollToElement(restoredArchivedCardsDisclosure, in: app)
        XCTAssertTrue(String(describing: restoredArchivedCardsDisclosure.value).contains("已展开"))
        XCTAssertTrue(app.buttons[archivedRiskCardIdentifier].waitForExistence(timeout: 5))

        app.swipeDown()
        app.swipeDown()
        restoredRiskSearch.tap()
        restoredRiskSearch.typeText("synthetic-no-risk-result-query")
        XCTAssertTrue(
            app.staticTexts.matching(
                NSPredicate(format: "label CONTAINS %@", "synthetic-no-risk-result-query")
            ).firstMatch.waitForExistence(timeout: 5)
        )
        clearSearchField(restoredRiskSearch)
    }

    func testSearchControlsRemainReachableAtLargestAccessibilityTextSize() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = clearedPersistenceFailureArguments + [
            "-hasCompletedFirstLaunchSetup", "YES",
            "--seed-demo-data",
            "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityExtraExtraExtraLarge"
        ]
        app.launch()

        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 10))
        tabBar.buttons.element(boundBy: 1).tap()

        let medicationSearch = app.searchFields.firstMatch
        XCTAssertTrue(medicationSearch.waitForExistence(timeout: 10))
        XCTAssertTrue(medicationSearch.isHittable)
        medicationSearch.tap()
        medicationSearch.typeText("Ibuprofen")
        medicationSearch.typeText("\n")
        let medicationResult = app.staticTexts["布洛芬"].firstMatch
        XCTAssertTrue(medicationResult.waitForExistence(timeout: 10))
        scrollToElement(medicationResult, in: app)
        clearSearchField(medicationSearch)

        app.swipeDown()
        app.swipeDown()
        let riskReview = app.staticTexts["风险复核"].firstMatch
        scrollToElement(riskReview, in: app)
        riskReview.tap()

        let riskSearch = app.searchFields.firstMatch
        XCTAssertTrue(riskSearch.waitForExistence(timeout: 10))
        XCTAssertTrue(riskSearch.isHittable)
        riskSearch.tap()
        riskSearch.typeText("ibuprofen")
        let riskGroup = app.buttons["布洛芬"].firstMatch
        XCTAssertTrue(riskGroup.waitForExistence(timeout: 10))
        XCTAssertTrue(riskGroup.isHittable)
        XCTAssertGreaterThanOrEqual(riskGroup.frame.height, 44)
    }

    private func clearSearchField(_ searchField: XCUIElement) {
        searchField.tap()
        let clearButton = searchField.buttons.firstMatch
        XCTAssertTrue(clearButton.waitForExistence(timeout: 2), "System search clear button is missing")
        clearButton.tap()
        XCTAssertTrue(clearButton.waitForNonExistence(timeout: 2), "Search field retained its clear button")
    }

    private func scrollToElement(_ element: XCUIElement, in app: XCUIApplication) {
        XCTAssertTrue(element.waitForExistence(timeout: 5))
        var remainingSwipes = 6
        while !element.isHittable && remainingSwipes > 0 {
            app.swipeUp()
            remainingSwipes -= 1
        }
        XCTAssertTrue(element.isHittable)
    }
}
