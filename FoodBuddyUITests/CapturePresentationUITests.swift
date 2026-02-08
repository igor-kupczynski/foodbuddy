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
        XCTAssertTrue(app.buttons["capture-mealtype-cancel"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["capture-mealtype-save"].waitForExistence(timeout: 5))
    }

    private func launchApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments.append("--use-mock-camera-capture")
        app.launchEnvironment["FOODBUDDY_USE_MOCK_CAMERA_CAPTURE"] = "1"
        app.launch()
        return app
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
