import Foundation
import XCTest

@MainActor
final class CapturePresentationUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testTakePhotoPresentsFullWindowMockCameraAndAllowsCancel() throws {
        let app = launchApp()

        app.buttons["Add"].tap()
        app.buttons["Take Photo"].tap()

        let mockCameraRoot = app.otherElements["mock-camera-root"]
        XCTAssertTrue(mockCameraRoot.waitForExistence(timeout: 5))

        let window = app.windows.firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 5))
        assertCoversWindow(mockCameraRoot, window: window)

        let cancelButton = app.buttons["mock-camera-cancel"]
        XCTAssertTrue(cancelButton.isHittable)

        let usePhotoButton = app.buttons["mock-camera-use-photo"]
        XCTAssertTrue(usePhotoButton.isHittable)
        cancelButton.tap()

        XCTAssertTrue(waitForNonExistence(of: mockCameraRoot, timeout: 5))
    }

    func testUsingMockPhotoPresentsSaveMealSheet() throws {
        let app = launchApp()

        app.buttons["Add"].tap()
        app.buttons["Take Photo"].tap()

        let mockCameraRoot = app.otherElements["mock-camera-root"]
        XCTAssertTrue(mockCameraRoot.waitForExistence(timeout: 5))

        app.buttons["mock-camera-use-photo"].tap()

        XCTAssertTrue(waitForNonExistence(of: mockCameraRoot, timeout: 5))
        XCTAssertTrue(app.buttons["capture-session-cancel"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["capture-session-save"].waitForExistence(timeout: 5))
    }

    func testBatchCaptureSaveCreatesMealWithTwoEntries() throws {
        let app = launchApp()

        openCaptureSession(app: app)

        addMockPhotoToSession(app: app)
        XCTAssertTrue(app.staticTexts["2 photos selected"].waitForExistence(timeout: 5))

        let saveButton = app.buttons["capture-session-save"]
        XCTAssertTrue(saveButton.waitForExistence(timeout: 5))
        XCTAssertTrue(saveButton.isEnabled)
        saveButton.tap()

        XCTAssertTrue(waitForNonExistence(of: app.otherElements["capture-session-root"], timeout: 10))
    }

    func testAddPhotoButtonHiddenAtEightPhotos() throws {
        let app = launchApp()
        openCaptureSession(app: app)

        for _ in 0..<7 {
            addMockPhotoToSession(app: app)
        }

        let identifiedAddButton = app.buttons["capture-session-add-photo"]
        let titledAddButton = app.buttons["Add another photo"]
        XCTAssertFalse(
            identifiedAddButton.waitForExistence(timeout: 2) || titledAddButton.waitForExistence(timeout: 2)
        )
    }

    private func launchApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments.append("--use-mock-camera-capture")
        app.launchEnvironment["FOODBUDDY_USE_MOCK_CAMERA_CAPTURE"] = "1"
        app.launchArguments.append("--use-mock-food-recognition")
        app.launchEnvironment["FOODBUDDY_USE_MOCK_FOOD_RECOGNITION"] = "1"
        app.launchEnvironment["FOODBUDDY_MISTRAL_KEYCHAIN_SERVICE"] = "info.kupczynski.foodbuddy.uitests.\(UUID().uuidString)"
        app.launch()
        return app
    }

    private func openCaptureSession(app: XCUIApplication) {
        app.buttons["Add"].tap()
        app.buttons["Take Photo"].tap()
        XCTAssertTrue(app.otherElements["mock-camera-root"].waitForExistence(timeout: 5))
        app.buttons["mock-camera-use-photo"].tap()
        XCTAssertTrue(app.otherElements["capture-session-root"].waitForExistence(timeout: 5))
    }

    private func tapAddAnotherPhoto(app: XCUIApplication) {
        let identifiedButton = app.buttons["capture-session-add-photo"]
        if identifiedButton.waitForExistence(timeout: 3) {
            identifiedButton.tap()
            return
        }

        let titledButton = app.buttons["Add another photo"]
        XCTAssertTrue(titledButton.waitForExistence(timeout: 3))
        titledButton.tap()
    }

    private func addMockPhotoToSession(app: XCUIApplication) {
        tapAddAnotherPhoto(app: app)
        XCTAssertTrue(app.buttons["Take Photo"].waitForExistence(timeout: 5))
        app.buttons["Take Photo"].tap()
        XCTAssertTrue(app.otherElements["mock-camera-root"].waitForExistence(timeout: 5))
        app.buttons["mock-camera-use-photo"].tap()
        XCTAssertTrue(app.otherElements["capture-session-root"].waitForExistence(timeout: 5))
    }

    private func assertCoversWindow(_ element: XCUIElement, window: XCUIElement) {
        let widthRatio = element.frame.width / max(window.frame.width, 1)
        let heightRatio = element.frame.height / max(window.frame.height, 1)

        XCTAssertGreaterThan(widthRatio, 0.9)
        XCTAssertGreaterThan(heightRatio, 0.9)
    }

    private func waitForNonExistence(of element: XCUIElement, timeout: TimeInterval) -> Bool {
        let predicate = NSPredicate(format: "exists == false")
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }
}
