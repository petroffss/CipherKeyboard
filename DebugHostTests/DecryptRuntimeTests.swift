import XCTest
import Foundation

/// Installed production extension and independent UIKit host. Fixtures are used only for explicit fault/design states.
final class DecryptRuntimeTests: XCTestCase {
    override func setUp() { continueAfterFailure = false }
    @MainActor private func prepare(_ mode: String = "contact") throws -> String {
        let app = XCUIApplication(bundleIdentifier: "dev.cipherkeyboard.app")
        app.launchArguments = []; app.launch()
        XCTAssertTrue(app.staticTexts["mykey.fingerprint"].waitForExistence(timeout: 15)); app.terminate()
        app.launchArguments = ["-decrypt-seed"]
        app.launchEnvironment = ["CIPHER_DECRYPT_SYNTHETIC_CASE": mode]; app.launch()
        let output = app.staticTexts["decrypt.seedResult"]
        XCTAssertTrue(output.waitForExistence(timeout: 5))
        let ciphertext = output.label; XCTAssertTrue(ciphertext.hasPrefix("ckmsg1:"), ciphertext)
        app.terminate(); return ciphertext
    }
    @MainActor private func host(_ ciphertext: String) -> XCUIApplication {
        let host = XCUIApplication(bundleIdentifier: "dev.cipherkeyboard.typinghost")
        host.launchEnvironment = ["CIPHER_DECRYPT_SYNTHETIC_CIPHERTEXT": ciphertext]
        host.launch(); host.buttons["host.copyCiphertext"].tap()
        TypingTestSupport.openCipher(in: host)
        return host
    }
    @MainActor private func metrics(_ host: XCUIApplication) throws -> [String: Any] {
        let raw = try XCTUnwrap(host.buttons["keyboard.debugFixtures"].value as? String)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: Data(raw.utf8)) as? [String: Any])
    }
    @MainActor func testExplicitClipboardRead() throws {
        let ciphertext = try prepare(); try TypingTestSupport.configureKeyboard(fullAccess: true)
        let host = host(ciphertext)
        let before = try metrics(host)
        let initial = before["decryptClipboardContentReads"] as? Int ?? -1
        let initialMetadata = before["decryptClipboardMetadataReads"] as? Int ?? -1
        XCTAssertGreaterThanOrEqual(initial, 0); XCTAssertGreaterThanOrEqual(initialMetadata, 0)
        host.buttons["keyboard.language"].tap()
        XCUIDevice.shared.orientation = .landscapeLeft
        XCUIDevice.shared.orientation = .portrait
        // A bounded predicate waits for five seconds while continually asserting the observation stays zero.
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline {
            XCTAssertEqual(try metrics(host)["decryptClipboardContentReads"] as? Int, initial)
            XCTAssertEqual(try metrics(host)["decryptClipboardMetadataReads"] as? Int, initialMetadata)
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        let field = host.textViews["host.editor"].value as? String
        let diagnostics = host.staticTexts["host.diagnostics"].label
        XCTAssertTrue(host.buttons["keyboard.decrypt"].isEnabled)
        host.buttons["keyboard.decrypt"].tap()
        let allow = host.alerts.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] %@ OR label CONTAINS[c] %@", "Allow", "Разрешить")
        ).firstMatch
        if allow.waitForExistence(timeout: 2) { allow.tap() }
        let text = host.staticTexts["keyboard.decrypt.text"]
        XCTAssertTrue(text.waitForExistence(timeout: 5), host.debugDescription)
        XCTAssertEqual(text.label, "  Привет, Анна!\nЗавтра в 19:30 👨‍👩‍👧‍👦  ")
        XCTAssertEqual(host.staticTexts["keyboard.decrypt.sender"].label, "От: Анна07")
        XCTAssertEqual(host.staticTexts["keyboard.decrypt.signature"].label, "✓ Подпись верна")
        XCTAssertEqual(try metrics(host)["decryptClipboardContentReads"] as? Int, initial + 1)
        XCTAssertEqual(try metrics(host)["decryptClipboardMetadataReads"] as? Int, initialMetadata + 1)
        XCTAssertEqual(host.textViews["host.editor"].value as? String, field)
        XCTAssertEqual(host.staticTexts["host.diagnostics"].label, diagnostics)
        host.buttons["keyboard.decrypt.close"].tap()
        XCTAssertTrue(host.buttons["keyboard.key.й"].exists)
        XCTAssertEqual(try metrics(host)["decryptClipboardContentReads"] as? Int, initial + 1)
    }
    @MainActor func testAppSystemPasteAndTenCycles() throws {
        let ciphertext = try prepare("long")
        let app = XCUIApplication(bundleIdentifier: "dev.cipherkeyboard.app")
        app.launchArguments = []
        let clipboardHost = XCUIApplication(bundleIdentifier: "dev.cipherkeyboard.typinghost")
        func copy(_ value: String) {
            clipboardHost.terminate()
            clipboardHost.launchEnvironment = ["CIPHER_DECRYPT_SYNTHETIC_CIPHERTEXT": value]
            clipboardHost.launch()
            clipboardHost.buttons["host.copyCiphertext"].tap()
            app.activate()
        }
        func tab(_ name: String) {
            let button = app.tabBars.buttons.matching(NSPredicate(format: "label == %@", name)).firstMatch
            XCTAssertTrue(button.waitForExistence(timeout: 5)); button.tap()
        }
        func pasteAndSubmit() {
            let paste = app.descendants(matching: .any)["decrypt.paste"].firstMatch
            XCTAssertTrue(paste.waitForExistence(timeout: 5)); paste.tap()
            let input = app.textViews["decrypt.input"]
            let received = XCTNSPredicateExpectation(
                predicate: NSPredicate { _, _ in
                    !(input.value as? String ?? "").isEmpty
                }, object: nil)
            XCTAssertEqual(XCTWaiter.wait(for: [received], timeout: 5), .completed)
            let submit = app.buttons["decrypt.submit"]
            XCTAssertTrue(submit.isEnabled)
            if !submit.isHittable { app.swipeUp() }
            submit.tap()
        }
        app.launch()
        XCTAssertTrue(app.staticTexts["mykey.fingerprint"].waitForExistence(timeout: 10))
        for index in 0..<10 {
            copy(ciphertext); tab("Расшифровать"); pasteAndSubmit()
            let text = app.staticTexts["decrypt.text"]
            XCTAssertTrue(text.waitForExistence(timeout: 5)); XCTAssertEqual(text.label.utf8.count, 4096)
            XCTAssertEqual(app.staticTexts["decrypt.sender"].label, "От: Анна07")
            app.buttons["decrypt.close"].tap()
            XCTAssertTrue(app.textViews["decrypt.input"].exists)
            XCTAssertFalse(app.buttons["decrypt.submit"].isEnabled)
            copy("ckmsg1:invalid"); tab("Расшифровать"); pasteAndSubmit()
            let error = app.staticTexts["decrypt.status"]
            XCTAssertTrue(error.waitForExistence(timeout: 5));
            XCTAssertEqual(error.label, "Сообщение повреждено или подделано")
            XCTAssertFalse(app.staticTexts["decrypt.signature"].exists)
            tab("Контакты"); tab("Расшифровать")
            XCTAssertFalse(app.buttons["decrypt.submit"].isEnabled)
            let lifetime = app.staticTexts["decrypt.debugLifetime"]
            let released = XCTNSPredicateExpectation(
                predicate: NSPredicate(format: "label CONTAINS %@", "operations=0"), object: lifetime)
            XCTAssertEqual(XCTWaiter.wait(for: [released], timeout: 3), .completed)
            let frame = XCTAttachment(screenshot: app.screenshot()); frame.name = "decrypt-app-cycle-\(index)";
            frame.lifetime = .keepAlways; add(frame)
        }
    }
    @MainActor func testTenCyclesAndLifecycle() throws {
        let ciphertext = try prepare("long"); try TypingTestSupport.configureKeyboard(fullAccess: true)
        let host = host(ciphertext)
        let baseline = try metrics(host)["decryptLiveCoordinators"] as? Int
        for index in 0..<10 {
            host.buttons["keyboard.decrypt"].tap()
            let text = host.staticTexts["keyboard.decrypt.text"]
            XCTAssertTrue(text.waitForExistence(timeout: 5), host.debugDescription)
            XCTAssertEqual(text.label.utf8.count, 4096)
            host.buttons["keyboard.decrypt.close"].tap()
            TypingTestSupport.fixture("dec-corrupt", in: host)
            let error = host.staticTexts["keyboard.decrypt.status"]
            XCTAssertTrue(error.waitForExistence(timeout: 5))
            XCTAssertEqual(error.label, "Сообщение повреждено или подделано")
            XCTAssertFalse(host.staticTexts["keyboard.decrypt.signature"].exists)
            host.buttons["keyboard.decrypt.close"].tap()
            // Reopen the real controller to discard fixture sources and regain real clipboard/identity adapters.
            host.buttons["Скрыть"].tap(); host.buttons["Открыть"].tap()
            XCTAssertTrue(host.buttons["keyboard.decrypt"].waitForExistence(timeout: 5))
            let released = XCTNSPredicateExpectation(
                predicate: NSPredicate { _, _ in
                    guard let values = try? self.metrics(host) else { return false }
                    return values["decryptLiveOperations"] as? Int == 0
                        && values["decryptLiveCoordinators"] as? Int == baseline
                }, object: nil)
            XCTAssertEqual(XCTWaiter.wait(for: [released], timeout: 3), .completed)
            let proof = XCTAttachment(screenshot: host.screenshot()); proof.name = "decrypt-cycle-\(index)";
            proof.lifetime = .keepAlways; add(proof)
        }
        host.buttons["keyboard.decrypt"].tap()
        XCTAssertTrue(host.staticTexts["keyboard.decrypt.text"].waitForExistence(timeout: 5))
        XCUIDevice.shared.press(.home); host.activate()
        XCTAssertFalse(host.staticTexts["keyboard.decrypt.text"].exists)
        XCTAssertTrue(host.buttons["keyboard.decrypt"].waitForExistence(timeout: 5))
    }
}
