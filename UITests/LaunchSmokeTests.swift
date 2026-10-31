import XCTest

/// Смоук: приложение запускается и показывает стартовый экран.
final class LaunchSmokeTests: XCTestCase {
    @MainActor
    func testAppLaunchesAndShowsTitle() {
        let app = XCUIApplication()
        app.launch()
        let title = app.staticTexts["app.title"]
        XCTAssertTrue(title.waitForExistence(timeout: 10))
        XCTAssertEqual(title.label, "CipherKeyboard")
    }
}
