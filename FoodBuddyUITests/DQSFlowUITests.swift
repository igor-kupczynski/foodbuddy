import Foundation
import XCTest

@MainActor
final class DQSFlowUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testHistoryDayHeaderShowsScoreAndNavigatesToDailyView() throws {
        let app = launchAppWithFixture()

        let dayLink = firstElement(withIdentifierPrefix: "dqs-day-score-link-", in: app)
        XCTAssertTrue(dayLink.waitForExistence(timeout: 5))

        let dayBadge = firstElement(withIdentifierPrefix: "dqs-day-score-badge-", in: app)
        XCTAssertTrue(dayBadge.waitForExistence(timeout: 5))

        dayLink.tap()

        XCTAssertTrue(app.navigationBars["Daily DQS"].waitForExistence(timeout: 5))
        XCTAssertTrue(element(withIdentifier: "dqs-daily-total-score", in: app).waitForExistence(timeout: 5))
        XCTAssertTrue(element(withIdentifier: "dqs-category-row-fruits", in: app).waitForExistence(timeout: 5))
    }

    func testCategoryHelpShowsServingGuideAndExamples() throws {
        let app = launchAppWithFixture()
        openDailyView(app: app)

        let helpButton = element(withIdentifier: "dqs-category-help-button", in: app)
        XCTAssertTrue(helpButton.waitForExistence(timeout: 5))
        helpButton.tap()

        XCTAssertTrue(app.navigationBars["DQS Category Help"].waitForExistence(timeout: 5))
        XCTAssertTrue(element(withIdentifier: "dqs-category-help-row-fruits", in: app).waitForExistence(timeout: 5))
        XCTAssertTrue(element(withIdentifier: "dqs-category-help-serving-fruits", in: app).waitForExistence(timeout: 5))
        XCTAssertTrue(element(withIdentifier: "dqs-category-help-examples-vegetables", in: app).waitForExistence(timeout: 5))

        app.buttons["dqs-category-help-done"].tap()
        XCTAssertTrue(app.navigationBars["Daily DQS"].waitForExistence(timeout: 5))
    }

    func testAddEditDeleteFoodItemUpdatesDailyScore() throws {
        let app = launchAppWithFixture()
        openDailyView(app: app)

        let initialScore = try XCTUnwrap(currentScore(in: app))

        app.buttons["dqs-add-food-item"].tap()
        XCTAssertTrue(app.textFields["dqs-manual-food-item-name"].waitForExistence(timeout: 5))

        let nameField = app.textFields["dqs-manual-food-item-name"]
        nameField.tap()
        nameField.typeText("UI Test Veg")

        app.buttons["dqs-manual-food-item-save"].tap()

        let scoreAfterAdd = try XCTUnwrap(currentScore(in: app))
        XCTAssertEqual(scoreAfterAdd, initialScore + 2)

        let addedRow = firstButton(withLabelContaining: "UI Test Veg", in: app)
        XCTAssertTrue(scrollToElement(addedRow, in: app), "Expected added food item row to be visible")
        addedRow.tap()
        XCTAssertTrue(app.textFields["dqs-food-item-edit-name"].waitForExistence(timeout: 5))

        let editNameField = app.textFields["dqs-food-item-edit-name"]
        editNameField.tap()
        if let existing = editNameField.value as? String {
            let deleteString = String(repeating: XCUIKeyboardKey.delete.rawValue, count: existing.count)
            editNameField.typeText(deleteString)
        }
        editNameField.typeText("UI Test Veg Edited")
        XCTAssertEqual(editNameField.value as? String, "UI Test Veg Edited")
        XCTAssertTrue(app.buttons["dqs-food-item-edit-delete"].waitForExistence(timeout: 5))
        app.buttons["dqs-food-item-edit-delete"].tap()
        let confirmDelete = app.sheets.buttons["Delete"].firstMatch
        XCTAssertTrue(confirmDelete.waitForExistence(timeout: 5))
        confirmDelete.tap()

        ensureOnDailyView(app: app)
        let scoreAfterDelete = try XCTUnwrap(currentScore(in: app))
        XCTAssertEqual(scoreAfterDelete, initialScore)
    }

    private func launchAppWithFixture() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments.append("--use-mock-food-recognition")
        app.launchEnvironment["FOODBUDDY_USE_MOCK_FOOD_RECOGNITION"] = "1"
        app.launchEnvironment["FOODBUDDY_MISTRAL_KEYCHAIN_SERVICE"] = "info.kupczynski.foodbuddy.uitests.\(UUID().uuidString)"
        app.launchEnvironment["FOODBUDDY_LOCAL_STORE_SUFFIX"] = "uitests-\(UUID().uuidString)"
        app.launchEnvironment["FOODBUDDY_DQS_FIXTURE"] = "baseline"
        app.launch()
        return app
    }

    private func openDailyView(app: XCUIApplication) {
        ensureOnHistoryView(app: app)
        let dayLink = firstElement(withIdentifierPrefix: "dqs-day-score-link-", in: app)
        XCTAssertTrue(dayLink.waitForExistence(timeout: 5))
        dayLink.tap()
        XCTAssertTrue(app.navigationBars["Daily DQS"].waitForExistence(timeout: 5))
    }

    private func ensureOnDailyView(app: XCUIApplication) {
        if app.navigationBars["Daily DQS"].exists,
           element(withIdentifier: "dqs-daily-total-score", in: app).waitForExistence(timeout: 1) {
            return
        }

        ensureOnHistoryView(app: app)
        let dayLink = firstElement(withIdentifierPrefix: "dqs-day-score-link-", in: app)
        if dayLink.waitForExistence(timeout: 5) {
            dayLink.tap()
            XCTAssertTrue(app.navigationBars["Daily DQS"].waitForExistence(timeout: 5))
        }
    }

    private func ensureOnHistoryView(app: XCUIApplication) {
        for _ in 0..<6 {
            let dayLink = firstElement(withIdentifierPrefix: "dqs-day-score-link-", in: app)
            if dayLink.exists {
                return
            }

            let backButton = app.navigationBars.buttons.firstMatch
            if backButton.exists {
                backButton.tap()
                continue
            }

            break
        }
    }

    private func firstElement(withIdentifierPrefix prefix: String, in app: XCUIApplication) -> XCUIElement {
        let predicate = NSPredicate(format: "identifier BEGINSWITH %@", prefix)
        return app.descendants(matching: .any).matching(predicate).firstMatch
    }

    private func element(withIdentifier identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    private func firstButton(withLabelContaining value: String, in app: XCUIApplication) -> XCUIElement {
        let predicate = NSPredicate(format: "label CONTAINS[c] %@", value)
        return app.buttons.matching(predicate).firstMatch
    }

    private func scrollToElement(_ element: XCUIElement, in app: XCUIApplication, maxSwipes: Int = 5) -> Bool {
        if element.waitForExistence(timeout: 1) {
            return true
        }

        for _ in 0..<maxSwipes {
            app.swipeUp()
            if element.waitForExistence(timeout: 1) {
                return true
            }
        }

        for _ in 0..<maxSwipes {
            app.swipeDown()
            if element.waitForExistence(timeout: 1) {
                return true
            }
        }

        return false
    }

    private func currentScore(in app: XCUIApplication) -> Int? {
        let scoreElement = element(withIdentifier: "dqs-daily-total-score", in: app)
        guard scoreElement.waitForExistence(timeout: 5) else {
            return nil
        }

        if let value = scoreElement.value as? String, let parsed = Int(value) {
            return parsed
        }

        if let parsed = Int(scoreElement.label) {
            return parsed
        }

        return nil
    }
}
