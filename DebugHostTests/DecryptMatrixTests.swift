import XCTest

/// 94 required native frames: 66 narrow portrait + 16 wider contact/long + 12 long landscape.
final class DecryptMatrixTests: XCTestCase {
    override func setUp() { continueAfterFailure = false }
    private let keyboardStates = [
        "idle", "busy", "contact", "self", "unknown", "long", "no-message", "corrupt", "foreign", "version",
        "paste-error", "no-access", "no-key", "key-error", "contacts-warning", "changed", "oversize",
    ]
    private let appStates = [
        "empty", "input", "busy", "contact", "self", "unknown", "long", "no-message", "corrupt", "foreign", "version",
        "paste-error", "key-error", "contacts-warning", "changed", "oversize",
    ]
    /// A bounded builder diagnostic; the independent verifier still captures all 94 approved frames.
    @MainActor func testDesignSmoke() throws {
        XCUIDevice.shared.orientation = .portrait
        try TypingTestSupport.configureKeyboard(fullAccess: true)
        let host = XCUIApplication(bundleIdentifier: "dev.cipherkeyboard.typinghost")
        host.launch(); TypingTestSupport.openCipher(in: host)
        for state in ["idle", "busy", "corrupt", "long"] {
            TypingTestSupport.fixture("dec-" + state, in: host)
            if state == "long" {
                XCTAssertTrue(host.staticTexts["keyboard.decrypt.text"].waitForExistence(timeout: 5))
                XCTAssertEqual(host.staticTexts["keyboard.decrypt.text"].label.utf8.count, 4096)
            }
            if state == "corrupt" {
                XCTAssertTrue(host.staticTexts["keyboard.decrypt.status"].waitForExistence(timeout: 5))
            }
            capture(host, name: "smoke-keyboard-" + state)
        }
        XCUIDevice.shared.orientation = .landscapeLeft
        TypingTestSupport.waitLayout(in: host, width: 874)
        capture(host, name: "smoke-keyboard-long-landscape")
        XCUIDevice.shared.orientation = .portrait
        host.terminate()
        for state in ["empty", "busy", "long"] {
            let app = XCUIApplication(bundleIdentifier: "dev.cipherkeyboard.app")
            app.launchArguments = ["-keystore", "memory", "-decrypt-fixture", "-decrypt-state", state]
            app.launch()
            XCTAssertTrue(app.staticTexts["mykey.fingerprint"].waitForExistence(timeout: 15))
            app.tabBars.buttons.matching(NSPredicate(format: "label == %@", "Расшифровать")).firstMatch.tap()
            if state == "empty" {
                capture(app, name: "smoke-app-empty"); app.terminate(); continue
            }
            let submit = app.buttons["decrypt.submit"]
            XCTAssertTrue(submit.waitForExistence(timeout: 5)); submit.tap()
            XCTAssertTrue(app.buttons["decrypt.close"].waitForExistence(timeout: 5))
            capture(app, name: "smoke-app-" + state)
            if state == "long" {
                XCUIDevice.shared.orientation = .landscapeLeft
                capture(app, name: "smoke-app-long-landscape")
                XCUIDevice.shared.orientation = .portrait
            }
            app.terminate()
        }
    }
    @MainActor func testCaptureCurrentProfile() throws {
        XCUIDevice.shared.orientation = .portrait
        let host = XCUIApplication(bundleIdentifier: "dev.cipherkeyboard.typinghost")
        host.launch(); TypingTestSupport.openCipher(in: host)
        let width = host.frame.width, height = host.frame.height
        XCTAssertEqual(height, [375.0: 667.0, 402.0: 874.0, 440.0: 956.0][width])
        for landscape in [false, true] {
            XCUIDevice.shared.orientation = landscape ? .landscapeLeft : .portrait
            TypingTestSupport.waitLayout(in: host, width: landscape ? height : width)
            let states = landscape ? ["long"] : width == 375 ? keyboardStates + ["generic"] : ["contact", "long"]
            for state in states {
                TypingTestSupport.fixture("dec-" + state, in: host)
                let ready = host.descendants(matching: .any)[
                    state == "idle" || ["no-access", "no-key", "key-error"].contains(state)
                        ? "keyboard.decrypt" : "keyboard.decrypt.close"
                ].firstMatch
                XCTAssertTrue(ready.waitForExistence(timeout: 5))
                if !["busy", "idle", "no-access", "no-key", "key-error"].contains(state) {
                    let done = XCTNSPredicateExpectation(
                        predicate: NSPredicate(format: "value CONTAINS %@", "\"decryptBusy\":false"),
                        object: host.buttons["keyboard.debugFixtures"])
                    XCTAssertEqual(XCTWaiter.wait(for: [done], timeout: 5), .completed)
                }
                let panel = host.otherElements["keyboard.panel"].frame
                XCTAssertLessThanOrEqual(panel.height, landscape ? 240 : 420)
                XCTAssertLessThanOrEqual(host.textViews["host.editor"].frame.maxY, panel.minY + 0.5)
                if ready.identifier == "keyboard.decrypt.close" { XCTAssertGreaterThanOrEqual(ready.frame.height, 44) }
                capture(host, name: "keyboard-\(state)-\(Int(width))-\(landscape ? "landscape" : "portrait")")
            }
        }
        host.terminate()
        for landscape in [false, true] {
            XCUIDevice.shared.orientation = landscape ? .landscapeLeft : .portrait
            let states = landscape ? ["long"] : width == 375 ? appStates + ["generic"] : ["contact", "long"]
            for state in states {
                let app = XCUIApplication(bundleIdentifier: "dev.cipherkeyboard.app")
                app.launchArguments = ["-keystore", "memory", "-decrypt-fixture", "-decrypt-state", state]
                app.launch()
                XCTAssertTrue(app.staticTexts["mykey.fingerprint"].waitForExistence(timeout: 15))
                let tab = app.tabBars.buttons.matching(
                    NSPredicate(format: "identifier == %@ OR label == %@", "tab.decrypt", "Расшифровать")
                ).firstMatch
                XCTAssertTrue(tab.waitForExistence(timeout: 5)); tab.tap()
                XCTAssertTrue(app.textViews["decrypt.input"].waitForExistence(timeout: 5))
                if !["empty", "input", "paste-error", "oversize", "key-error"].contains(state) {
                    let submit = app.buttons["decrypt.submit"]
                    if !submit.isHittable { app.swipeUp() }
                    submit.tap()
                    if state != "busy" {
                        let final = XCTNSPredicateExpectation(
                            predicate: NSPredicate { _, _ in
                                let status = app.staticTexts["decrypt.status"]
                                return app.staticTexts["decrypt.text"].exists
                                    || (status.exists && status.label != "Расшифровываем…")
                            }, object: nil)
                        XCTAssertEqual(XCTWaiter.wait(for: [final], timeout: 5), .completed)
                    }
                }
                XCTAssertTrue(app.tabBars.firstMatch.exists)
                if ["contact", "self", "unknown", "long", "contacts-warning"].contains(state) {
                    XCTAssertTrue(app.buttons["decrypt.close"].isHittable)
                    XCTAssertGreaterThanOrEqual(app.buttons["decrypt.close"].frame.height, 44)
                }
                capture(app, name: "app-\(state)-\(Int(width))-\(landscape ? "landscape" : "portrait")")
                app.terminate()
            }
        }
        XCUIDevice.shared.orientation = .portrait
    }
    @MainActor private func capture(_ app: XCUIApplication, name: String) {
        var previous = CGRect.null, stableSince = Date()
        let settled = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in
                let frame = app.frame
                if frame != previous { previous = frame; stableSince = Date() }
                return Date().timeIntervalSince(stableSince) >= 0.6
            }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [settled], timeout: 5), .completed)
        let frame = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); frame.name = "decrypt-" + name;
        frame.lifetime = .keepAlways; add(frame)
        let hierarchy = XCTAttachment(string: app.debugDescription); hierarchy.name = "decrypt-" + name + "-ax";
        hierarchy.lifetime = .keepAlways; add(hierarchy)
    }
}
