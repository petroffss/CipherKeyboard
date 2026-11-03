import XCTest

final class DecryptUITests: XCTestCase {
    @MainActor private func launch(_ state: String = "contact") -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-keystore", "memory", "-decrypt-fixture", "-decrypt-state", state]
        app.launch()
        XCTAssertTrue(app.staticTexts["mykey.fingerprint"].waitForExistence(timeout: 15))
        app.navigationTab("tab.decrypt").tap()
        XCTAssertTrue(app.textViews["decrypt.input"].waitForExistence(timeout: 5))
        return app
    }
    @MainActor private func submit(_ app: XCUIApplication) {
        let button = app.buttons["decrypt.submit"]
        if !button.isHittable { app.swipeUp() }
        XCTAssertTrue(button.isEnabled); button.tap()
    }
    @MainActor func testSenderVariants() {
        for (state, expected) in [("contact", "От: Анна"), ("self", "От: вы"), ("unknown", "От неизвестного ключа")] {
            let app = launch(state); submit(app)
            let sender = app.staticTexts["decrypt.sender"]
            XCTAssertTrue(sender.waitForExistence(timeout: 5)); XCTAssertTrue(sender.label.hasPrefix(expected))
            XCTAssertEqual(app.staticTexts["decrypt.signature"].label, "✓ Подпись верна")
            XCTAssertEqual(app.staticTexts["decrypt.text"].label, "  Привет, Анна!\nЗавтра в 19:30 👨‍👩‍👧‍👦  ")
            XCTAssertFalse(app.textViews["decrypt.input"].exists)
            app.buttons["decrypt.close"].tap(); XCTAssertTrue(app.textViews["decrypt.input"].exists)
            XCTAssertFalse(app.staticTexts["decrypt.text"].exists); app.terminate()
        }
    }
    @MainActor func testErrorsAfterSuccess() {
        for (state, expected) in [
            ("corrupt", "Сообщение повреждено или подделано"),
            ("foreign", "Сообщение зашифровано не для вас"),
            ("version", "Сообщение из более новой версии CipherKeyboard — обновите приложение"),
            ("generic", "Не удалось расшифровать сообщение. Повторите попытку"),
            ("no-message", "В тексте нет зашифрованного сообщения"),
        ] {
            let success = launch(); submit(success)
            XCTAssertTrue(success.staticTexts["decrypt.text"].waitForExistence(timeout: 5)); success.terminate()
            let app = launch(state); let previous = app.textViews["decrypt.input"].value as? String
            submit(app)
            let error = app.staticTexts["decrypt.status"]
            XCTAssertTrue(error.waitForExistence(timeout: 5)); XCTAssertEqual(error.label, expected)
            XCTAssertFalse(app.staticTexts["decrypt.text"].exists);
            XCTAssertFalse(app.staticTexts["decrypt.signature"].exists)
            XCTAssertEqual(app.textViews["decrypt.input"].value as? String, previous); app.terminate()
        }
    }
    @MainActor func testBusyAndCancel() {
        let app = launch("busy"); submit(app)
        XCTAssertTrue(app.buttons["decrypt.close"].waitForExistence(timeout: 2))
        XCTAssertFalse(app.buttons["decrypt.submit"].exists)
        app.buttons["decrypt.close"].tap()
        XCTAssertTrue(app.textViews["decrypt.input"].exists)
        XCTAssertFalse(app.buttons["decrypt.submit"].isEnabled)
        let late = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == true"), object: app.staticTexts["decrypt.text"])
        XCTAssertEqual(XCTWaiter.wait(for: [late], timeout: 4), .timedOut)
    }
    @MainActor func testLifecycle() {
        let app = launch(); submit(app)
        XCTAssertTrue(app.staticTexts["decrypt.text"].waitForExistence(timeout: 5))
        app.navigationTab("tab.contacts").tap(); app.navigationTab("tab.decrypt").tap()
        XCTAssertFalse(app.staticTexts["decrypt.text"].exists)
        XCTAssertFalse(app.buttons["decrypt.submit"].isEnabled)
        app.terminate()
        let busy = launch("busy"); submit(busy)
        XCUIDevice.shared.press(.home); busy.activate()
        XCTAssertTrue(busy.textViews["decrypt.input"].waitForExistence(timeout: 5))
        XCTAssertFalse(busy.staticTexts["decrypt.text"].exists);
        XCTAssertFalse(busy.buttons["decrypt.submit"].isEnabled)
    }
    @MainActor func testAppPasteEditClose() {
        let app = launch(); let input = app.textViews["decrypt.input"]
        let envelope = input.value as? String
        XCTAssertTrue(app.otherElements["decrypt.paste"].exists || app.buttons["decrypt.paste"].exists)
        submit(app); XCTAssertTrue(app.staticTexts["decrypt.text"].waitForExistence(timeout: 5))
        app.buttons["decrypt.close"].tap(); XCTAssertEqual(input.value as? String, "")
        XCTAssertFalse(app.buttons["decrypt.submit"].isEnabled)
        input.tap(); input.typeText("   "); XCTAssertFalse(app.buttons["decrypt.submit"].isEnabled)
        input.typeText("фраза"); app.swipeUp(); submit(app)
        XCTAssertTrue(app.staticTexts["decrypt.status"].waitForExistence(timeout: 5))
        input.tap(); input.typeText("x"); XCTAssertFalse(app.staticTexts["decrypt.status"].exists)
        XCTAssertNotNil(envelope)
    }
    @MainActor func testAccessAndKeyErrors() {
        let app = launch("key-error")
        XCTAssertEqual(app.staticTexts["decrypt.status"].label, "Ключ недоступен — повторите попытку")
        // Retry remains an ordinary action; a transient key failure must not disable it forever.
        XCTAssertTrue(app.buttons["decrypt.submit"].isEnabled)
    }
    @MainActor func testExplicitClipboardRead() {
        let app = launch()
        let value = app.textViews["decrypt.input"].value as? String
        XCUIDevice.shared.orientation = .landscapeLeft
        XCUIDevice.shared.orientation = .portrait
        XCTAssertEqual(app.textViews["decrypt.input"].value as? String, value)
        submit(app)
        XCTAssertTrue(app.staticTexts["decrypt.text"].waitForExistence(timeout: 5))
        // This path consumes the field. The real extension clipboard path is exercised by DebugHost runtime tests.
    }
}
