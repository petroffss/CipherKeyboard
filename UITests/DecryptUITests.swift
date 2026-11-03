import XCTest

final class DecryptUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

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
            XCTAssertTrue(app.staticTexts["decrypt.date"].label.hasPrefix("Дата по часам отправителя: "))
            XCTAssertFalse(app.staticTexts["decrypt.ageWarning"].exists)
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
        XCUIDevice.shared.orientation = .portrait
        let app = launch()
        let input = app.textViews["decrypt.input"]
        let value = input.value as? String
        XCTAssertTrue(value?.hasPrefix("ckmsg2:") == true)
        let portrait = waitForLayout(in: app, landscape: false, requireSubmit: true)
        XCUIDevice.shared.orientation = .landscapeLeft
        let landscape = waitForLayout(in: app, landscape: true, requireSubmit: false)
        XCTAssertEqual(landscape[0].size, CGSize(width: portrait[0].height, height: portrait[0].width))
        XCTAssertEqual(input.value as? String, value)
        XCUIDevice.shared.orientation = .portrait
        let restored = waitForLayout(in: app, landscape: false, requireSubmit: true)
        XCTAssertEqual(restored, portrait)
        XCTAssertEqual(input.value as? String, value)
        let window = restored[0], button = restored[2]
        app.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: button.midX - window.minX, dy: button.midY - window.minY)).tap()
        XCTAssertTrue(app.staticTexts["decrypt.text"].waitForExistence(timeout: 5))
        // This path consumes the field. The real extension clipboard path is exercised by DebugHost runtime tests.
    }

    @MainActor private func waitForLayout(
        in app: XCUIApplication, landscape: Bool, requireSubmit: Bool
    ) -> [CGRect] {
        let input = app.textViews["decrypt.input"], submit = app.buttons["decrypt.submit"]
        var previous: [CGRect] = []
        var stableSince = Date()
        let settled = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in
                let window = app.frame, editor = input.frame, button = submit.frame
                let geometry = [window, editor, button]
                let ready =
                    !window.isEmpty && (window.width > window.height) == landscape
                    && XCUIDevice.shared.orientation.isLandscape == landscape
                    && input.isHittable && window.intersects(editor) && submit.isEnabled
                    && (!requireSubmit || (submit.isHittable && window.contains(button) && editor.maxY < button.minY))
                if !ready || geometry != previous { stableSince = Date(); previous = geometry }
                return ready && Date().timeIntervalSince(stableSince) >= 0.4
            }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [settled], timeout: 8), .completed, app.debugDescription)
        XCTAssertEqual([app.frame, input.frame, submit.frame], previous)
        return previous
    }
}
