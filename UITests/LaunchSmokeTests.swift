import XCTest

/// Смоук: четыре видимые вкладки и реальные переходы в их содержимое.
final class LaunchSmokeTests: XCTestCase {
    @MainActor
    func testAppLaunchesAndShowsMyKey() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launch()
        let title = app.staticTexts["mykey.title"]
        XCTAssertTrue(title.waitForExistence(timeout: 10))
        XCTAssertEqual(title.label, "Мой ключ")

        let tabs = ["tab.contacts", "tab.decrypt", "tab.setup", "tab.myKey"]
        let content = ["contacts.title", "Расшифровать", "setup.title", "mykey.title"]
        for (destination, expected) in zip(tabs, content) {
            for identifier in tabs { _ = app.navigationTab(identifier) }
            XCTAssertEqual(app.tabBars.buttons.count, 4)
            app.navigationTab(destination).tap()
            XCTAssertTrue(app.staticTexts[expected].waitForExistence(timeout: 5), expected)
        }
        XCTAssertTrue(title.exists)
    }
}
