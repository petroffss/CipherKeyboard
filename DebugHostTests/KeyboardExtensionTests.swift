import XCTest

final class KeyboardExtensionTests: XCTestCase {
    override func setUp() { continueAfterFailure = false }
    /// Requires scripts/typing-host.sh and the keyboard enabled in this disposable simulator.
    @MainActor func testRealExtensionTyping() throws {
        let host = XCUIApplication(bundleIdentifier: "dev.cipherkeyboard.typinghost")
        host.launch()
        host.buttons["Открыть"].tap()
        let editor = host.descendants(matching: .any)["keyboard.editor"].firstMatch
        XCTAssertTrue(editor.waitForExistence(timeout: 10), host.debugDescription)
        let before = host.staticTexts["host.diagnostics"].label
        for key in ["п", "р", "и", "в", "е", "т"] { host.buttons["keyboard.key.\(key)"].tap() }
        host.buttons["keyboard.return"].tap()
        XCTAssertEqual(editor.value as? String, "Привет\n")
        XCTAssertEqual(host.staticTexts["host.diagnostics"].label, before)
        let evidence = XCTAttachment(screenshot: host.screenshot())
        evidence.name = "Real extension: draft and unchanged host selection"
        evidence.lifetime = .keepAlways
        add(evidence)
        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertEqual(editor.value as? String, "Привет\n")
        XCTAssertEqual(host.staticTexts["host.diagnostics"].label, before)
        XCUIDevice.shared.orientation = .portrait
        host.buttons["Скрыть"].tap()
        host.buttons["Открыть"].tap()
        XCTAssertEqual(editor.value as? String, "")
    }
}
