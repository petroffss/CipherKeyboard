import XCTest

final class SetupUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    @MainActor
    private func launch(_ state: String, extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-keystore", "memory", "-setup-state", state] + extra
        app.launch()
        XCTAssertTrue(app.staticTexts["mykey.title"].waitForExistence(timeout: 10))
        _ = app.navigationTab("tab.setup")
        return app
    }

    @MainActor
    func testStatesAndBanner() {
        for state in ["absent", "present", "confirmed", "unknown"] {
            let app = launch(state)
            let banner = app.buttons["mykey.setupBanner"]
            if state == "confirmed" {
                XCTAssertFalse(banner.exists)
                app.navigationTab("tab.setup").tap()
                XCTAssertTrue(app.staticTexts["Подключение проверено"].waitForExistence(timeout: 5))
                XCTAssertEqual(
                    app.staticTexts["setup.historicalNote"].label,
                    "Полный доступ был включён при последнем открытии клавиатуры. Если вы меняли настройки, откройте клавиатуру снова"
                )
                XCTAssertFalse(app.buttons["setup.openSettings"].exists)
                app.buttons["setup.showSteps"].tap()
            } else {
                app.scrollViews["mykey.scroll"].swipeUp()
                app.scrollViews["mykey.scroll"].swipeUp()
                XCTAssertTrue(banner.isHittable)
                XCTAssertEqual(banner.label, "Проверьте подключение клавиатуры")
                banner.tap()
                XCTAssertTrue(app.staticTexts["setup.title"].waitForExistence(timeout: 5))
                if state == "present" {
                    XCTAssertTrue(
                        app.staticTexts["Включите «Полный доступ» и откройте клавиатуру в любом приложении"].exists)
                } else if state == "unknown" {
                    XCTAssertTrue(app.staticTexts["Не удалось проверить подключение"].exists)
                }
            }
            for step in [
                "1. Откройте Настройки → Приложения → CipherKeyboard → Клавиатуры", "2. Включите CipherKeyboard",
                "3. Включите «Полный доступ»",
                "4. Откройте поле ввода в любом приложении, удерживайте 🌐 и выберите CipherKeyboard",
            ] { XCTAssertTrue(app.staticTexts[step].exists) }
            let open = app.buttons["setup.openSettings"]
            XCTAssertTrue(open.exists)
            XCTAssertGreaterThanOrEqual(open.frame.height, 44)
            app.scrollViews["setup.scroll"].swipeUp()
            XCTAssertTrue(app.staticTexts["Зачем полный доступ"].exists)
            XCTAssertTrue(
                app.staticTexts[
                    "Клавиатуре нужны ваши ключи и контакты из приложения и доступ к скопированному шифротексту."
                ].exists)
            XCTAssertTrue(
                app.staticTexts["CipherKeyboard не подключается к интернету и ничего никуда не отправляет."].exists)
            app.terminate()
        }
    }

    @MainActor
    func testRefreshOnForeground() {
        let app = launch("confirmed", extra: ["-setup-sequence", "confirmed,absent,present,unknown"])
        app.navigationTab("tab.setup").tap()
        XCTAssertTrue(app.staticTexts["Подключение проверено"].exists)
        for expected in [
            "Подключите клавиатуру",
            "Включите «Полный доступ» и откройте клавиатуру в любом приложении",
            "Не удалось проверить подключение",
        ] {
            XCUIDevice.shared.press(.home)
            XCTAssertTrue(app.wait(for: .runningBackground, timeout: 5))
            app.activate()
            XCTAssertTrue(app.staticTexts[expected].waitForExistence(timeout: 5))
            XCTAssertFalse(app.staticTexts["Подключение проверено"].exists)
        }
    }

    @MainActor
    func testOpenSettingsFailure() {
        for result in ["failure", "success"] {
            let app = launch("absent", extra: ["-setup-open", result])
            app.navigationTab("tab.setup").tap()
            app.buttons["setup.openSettings"].tap()
            if result == "failure" {
                XCTAssertTrue(app.staticTexts["setup.settingsError"].waitForExistence(timeout: 5))
                XCTAssertEqual(app.staticTexts["setup.settingsError"].label, "Не удалось открыть Настройки")
                XCTAssertTrue(app.staticTexts["Настройки → Основные → Клавиатура → Клавиатуры"].exists)
            } else {
                XCTAssertFalse(app.staticTexts["setup.settingsError"].waitForExistence(timeout: 2))
            }
            app.terminate()
        }
    }
}
