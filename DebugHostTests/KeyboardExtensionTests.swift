import XCTest

final class KeyboardExtensionTests: XCTestCase {
    override func setUp() { continueAfterFailure = false }
    /// Requires scripts/typing-host.sh and the keyboard enabled in this disposable simulator.
    @MainActor func testRealExtensionTyping() throws {
        let host = XCUIApplication(bundleIdentifier: "dev.cipherkeyboard.typinghost")
        host.launch()
        TypingTestSupport.openCipher(in: host)
        let editor = host.descendants(matching: .any)["keyboard.editor"].firstMatch
        if !editor.waitForExistence(timeout: 2) {
            let globe = host.buttons.matching(
                NSPredicate(format: "label == %@ OR label == %@", "Next keyboard", "Следующая клавиатура")
            ).firstMatch
            XCTAssertTrue(globe.waitForExistence(timeout: 5), host.debugDescription)
            globe.press(forDuration: 0.8)
            host.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "CipherKeyboard")).firstMatch.tap()
        }
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
        try tapHostControl("Скрыть", in: host)
        let hidden = XCTAttachment(screenshot: host.screenshot())
        hidden.name = "Immediately after hide"; hidden.lifetime = .keepAlways; add(hidden)
        XCTAssertEqual(host.staticTexts["host.focus"].label, "hide=true; focused=false")
        XCTAssertTrue(editor.waitForNonExistence(timeout: 5), "Keyboard must actually disappear before reopening")
        TypingTestSupport.openCipher(in: host)
        XCTAssertEqual(editor.value as? String, "")
    }
    @MainActor private func tapHostControl(_ name: String, in host: XCUIApplication) throws {
        // iOS 27 XCTest can retain stale AX hitpoints after rotation. Read current window-space
        // centers reported by the host's actual laid-out buttons, then send a real screen tap.
        let geometryElement = host.staticTexts["host.controlsGeometry"]
        let dimensions = host.frame.size
        let width =
            XCUIDevice.shared.orientation.isLandscape
            ? max(dimensions.width, dimensions.height) : min(dimensions.width, dimensions.height)
        let expectedWidth = "width=\(width);"
        let settled = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label BEGINSWITH %@", expectedWidth), object: geometryElement)
        XCTAssertEqual(XCTWaiter.wait(for: [settled], timeout: 5), .completed)
        let geometry = geometryElement.label
        let entry = try XCTUnwrap(geometry.split(separator: ";").first { $0.hasPrefix(name + "=") })
        let point = entry.dropFirst(name.count + 1).split(separator: ",").compactMap { Double($0) }
        XCTAssertEqual(point.count, 2)
        guard point.count == 2 else { return }
        host.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: point[0], dy: point[1])).tap()
    }
    @MainActor func testFixtureTransportAndFiveStatuses() throws {
        let host = XCUIApplication(bundleIdentifier: "dev.cipherkeyboard.typinghost")
        host.launch()
        TypingTestSupport.openCipher(in: host)
        let editor = host.descendants(matching: .any)["keyboard.editor"].firstMatch
        XCTAssertTrue(editor.waitForExistence(timeout: 10))
        let unchanged = host.staticTexts["host.diagnostics"].label
        let states = ["no-access", "no-key", "key-error", "contacts-error", "ru-text"]
        let warnings = [
            "Включите «Полный доступ» в Настройках, чтобы шифровать",
            "Откройте приложение CipherKeyboard, чтобы создать ключ", "Не удалось открыть хранилище ключей",
            "Не удалось прочитать контакты", "Контактов: 2",
        ]
        for (name, warning) in zip(states, warnings) {
            TypingTestSupport.fixture(name, in: host)
            XCTAssertTrue(host.staticTexts["keyboard.identityStatus"].label.contains(warning))
            if name == "no-access" {
                XCTAssertTrue(
                    host.buttons["keyboard.debugFixtures"].label.contains(
                        "identityReads=0;contactsReads=0"))
            }
            let before = editor.value as? String
            host.buttons["keyboard.key.а"].tap()
            XCTAssertEqual(editor.value as? String, (before ?? "") + "а")
            host.buttons["keyboard.delete"].tap()
            XCTAssertEqual(editor.value as? String, before)
            XCTAssertEqual(host.staticTexts["host.diagnostics"].label, unchanged)
        }
    }
}
