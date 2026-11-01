import XCTest

final class KeyboardTypingTests: XCTestCase {
    override func setUp() { continueAfterFailure = false }
    @MainActor func testPreviewTyping() {
        let app = XCUIApplication()
        app.launchArguments = ["-keystore", "memory", "-setup-state", "absent"]
        app.launch()
        XCTAssertTrue(app.staticTexts["mykey.title"].waitForExistence(timeout: 10))
        app.navigationTab("tab.setup").tap()
        app.scrollViews["setup.scroll"].swipeUp()
        app.buttons["setup.tryKeyboard"].tap()
        let editor = app.descendants(matching: .any)["keyboard.editor"].firstMatch
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Набирайте текст внутри клавиатуры. При выходе черновик будет стёрт"].exists)
        XCTAssertEqual(editor.value as? String, "")
        for key in ["п", "р", "и", "в", "е", "т"] { app.buttons["keyboard.key.\(key)"].tap() }
        XCTAssertEqual(editor.value as? String, "Привет")
        app.buttons["keyboard.return"].tap()
        app.buttons["keyboard.language"].tap()
        app.buttons["keyboard.key.a"].tap()
        XCTAssertEqual(editor.value as? String, "Привет\nA")
        XCTAssertEqual(app.staticTexts["preview.host"].label, "До встречи!")
        XCTAssertFalse(app.buttons["keyboard.next"].exists)
        XCTAssertEqual(app.keyboards.count, 0)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.buttons["setup.tryKeyboard"].tap()
        XCTAssertEqual(editor.value as? String, "")
        app.buttons["keyboard.key.п"].tap()
        app.navigationTab("tab.myKey").tap()
        app.navigationTab("tab.setup").tap()
        XCTAssertEqual(editor.value as? String, "")
        app.buttons["keyboard.key.п"].tap()
        XCUIDevice.shared.press(.home)
        app.activate()
        XCTAssertEqual(editor.value as? String, "")
    }
    @MainActor func testProductionControllerIsolation() {
        let app = XCUIApplication()
        app.launchArguments = ["-keystore", "memory", "-typing-isolation"]
        app.launch()
        let result = app.staticTexts["typing.isolationResult"]
        XCTAssertTrue(result.waitForExistence(timeout: 10))
        XCTAssertEqual(result.label, "PASS: production controller, proxy calls 0")
    }
}
