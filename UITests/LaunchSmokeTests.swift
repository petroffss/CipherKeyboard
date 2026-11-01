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

        let tabs = ["tab.contacts", "tab.decrypt", "tab.setup", "tab.myKey"]
        for destination in tabs {
            for identifier in tabs {
                XCTAssertTrue(app.tabBars.buttons[identifier].waitForExistence(timeout: 5), identifier)
            }
            app.tabBars.buttons[destination].tap()
        }
        for identifier in tabs {
            XCTAssertTrue(app.tabBars.buttons[identifier].exists, identifier)
        }
        XCTAssertTrue(title.waitForExistence(timeout: 5))
    }
}
