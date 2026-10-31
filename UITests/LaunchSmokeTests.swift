import XCTest

/// Смоук: приложение запускается и показывает первый экран — вкладку «Мой ключ».
final class LaunchSmokeTests: XCTestCase {
    @MainActor
    func testAppLaunchesAndShowsMyKey() {
        let app = XCUIApplication()
        app.launch()
        let title = app.staticTexts["mykey.title"]
        XCTAssertTrue(title.waitForExistence(timeout: 10))
        XCTAssertEqual(title.label, "Мой ключ")
    }
}
