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
    /// Pairing phase for two real Keychains. Optional import accepts only the other device's public key.
    @MainActor func testPreparePublicPairing() throws {
        let app = XCUIApplication(bundleIdentifier: "dev.cipherkeyboard.app")
        app.launchArguments = []; app.launch()
        XCTAssertTrue(app.staticTexts["mykey.fingerprint"].waitForExistence(timeout: 15)); app.terminate()
        app.launchArguments = ["-decrypt-seed"]
        app.launchEnvironment = ["CIPHER_DECRYPT_SYNTHETIC_CASE": "export-own-public-key"]; app.launch()
        let output = app.staticTexts["decrypt.seedResult"]
        XCTAssertTrue(output.waitForExistence(timeout: 5)); XCTAssertTrue(output.label.hasPrefix("ckpub1:"))
        let publicKey = XCTAttachment(string: output.label); publicKey.name = "actual-keychain-public-key";
        publicKey.lifetime = .keepAlways; add(publicKey); app.terminate()
        if let key = ProcessInfo.processInfo.environment["CIPHER_NATIVE_IMPORT_PUBLIC_KEY"] {
            let name = try XCTUnwrap(ProcessInfo.processInfo.environment["CIPHER_NATIVE_IMPORT_NAME"])
            app.launchEnvironment = [
                "CIPHER_DECRYPT_SYNTHETIC_CASE": "import-contact",
                "CIPHER_DECRYPT_IMPORT_PUBLIC_KEY": key, "CIPHER_DECRYPT_IMPORT_NAME": name,
            ]
            app.launch(); XCTAssertTrue(output.waitForExistence(timeout: 5))
            XCTAssertEqual(output.label, "PASS: imported public contact"); app.terminate()
        }
    }
    /// Receiver phase consumes the exact retained C from the other device; it never creates a replacement envelope.
    @MainActor func testProvidedCiphertextReceiver() throws {
        let ciphertext = try XCTUnwrap(ProcessInfo.processInfo.environment["CIPHER_NATIVE_PROVIDED_CIPHERTEXT"])
        let sender = try XCTUnwrap(ProcessInfo.processInfo.environment["CIPHER_NATIVE_EXPECTED_SENDER"])
        XCTAssertTrue(ciphertext.hasPrefix("ckmsg1:"))
        try Self.configurePastePermission(allow: true)
        try TypingTestSupport.configureKeyboard(fullAccess: true)
        let expected = "  Привет, Анна!\nЗавтра в 19:30 👨‍👩‍👧‍👦  "
        let host = self.host(ciphertext)
        host.buttons["keyboard.decrypt"].tap()
        XCTAssertTrue(host.staticTexts["keyboard.decrypt.text"].waitForExistence(timeout: 5), host.debugDescription)
        XCTAssertEqual(host.staticTexts["keyboard.decrypt.text"].label, expected)
        XCTAssertEqual(host.staticTexts["keyboard.decrypt.sender"].label, sender)
        XCTAssertEqual(host.staticTexts["keyboard.decrypt.signature"].label, "✓ Подпись верна")
        let keyboard = XCTAttachment(screenshot: XCUIScreen.main.screenshot());
        keyboard.name = "actual-other-device-keyboard";
        keyboard.lifetime = .keepAlways; add(keyboard); host.buttons["keyboard.decrypt.close"].tap()
        let app = XCUIApplication(bundleIdentifier: "dev.cipherkeyboard.app")
        app.launchArguments = []; app.launch()
        app.tabBars.buttons.matching(NSPredicate(format: "label == %@", "Расшифровать")).firstMatch.tap()
        app.descendants(matching: .any)["decrypt.paste"].firstMatch.tap()
        let received = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value == %@", ciphertext), object: app.textViews["decrypt.input"])
        XCTAssertEqual(XCTWaiter.wait(for: [received], timeout: 5), .completed)
        let submit = app.buttons["decrypt.submit"]; if !submit.isHittable { app.swipeUp() }; submit.tap()
        XCTAssertTrue(app.staticTexts["decrypt.text"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["decrypt.text"].label, expected)
        XCTAssertEqual(app.staticTexts["decrypt.sender"].label, sender)
        XCTAssertEqual(app.staticTexts["decrypt.signature"].label, "✓ Подпись верна")
        let result = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); result.name = "actual-other-device-app";
        result.lifetime = .keepAlways; add(result); app.buttons["decrypt.close"].tap()
    }
    @MainActor private static func configurePastePermission(allow: Bool) throws {
        let app = XCUIApplication(bundleIdentifier: "dev.cipherkeyboard.app")
        app.launchArguments = []; app.launch()
        XCTAssertTrue(app.staticTexts["mykey.fingerprint"].waitForExistence(timeout: 15))
        app.tabBars.buttons.matching(NSPredicate(format: "label == %@", "Настройка")).firstMatch.tap()
        if app.buttons["setup.showSteps"].exists { app.buttons["setup.showSteps"].tap() }
        let open = app.buttons["setup.openSettings"]
        for _ in 0..<3 { if open.exists && open.isHittable { break }; app.scrollViews["setup.scroll"].swipeUp() }
        XCTAssertTrue(open.waitForExistence(timeout: 5)); if !open.isHittable { app.swipeUp() }; open.tap()
        let settings = XCUIApplication(bundleIdentifier: "com.apple.Preferences")
        settings.activate()
        // Some Simulator Settings builds retain the keyboard pane after the public deep link.
        // Navigate the visible Apps list rather than treating that pane as the app's permission page.
        for _ in 0..<8 {
            if settings.buttons["com.apple.settings.general"].exists { break }
            let back = settings.navigationBars.buttons.firstMatch
            if back.exists { back.tap() } else { break }
        }
        let apps = settings.buttons.matching(NSPredicate(format: "label IN %@", ["Apps", "Приложения"])).firstMatch
        for _ in 0..<6 { if apps.exists && apps.isHittable { break }; settings.swipeUp() }
        XCTAssertTrue(apps.exists && apps.isHittable, settings.debugDescription); apps.tap()
        let cipher = settings.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "CipherKeyboard"))
            .firstMatch
        for _ in 0..<6 { if cipher.exists && cipher.isHittable { break }; settings.swipeUp() }
        XCTAssertTrue(cipher.exists && cipher.isHittable, settings.debugDescription); cipher.tap()
        let hierarchy = XCTAttachment(string: settings.debugDescription)
        hierarchy.name = "system-paste-settings-before"; hierarchy.lifetime = .keepAlways
        XCTContext.runActivity(named: "Public app paste permission page") { $0.add(hierarchy) }
        let row = settings.descendants(matching: .any).matching(
            NSPredicate(
                format: "label CONTAINS[c] %@ OR (label BEGINSWITH %@ AND label CONTAINS[c] %@)",
                "Paste from Other Apps", "Вставка", "приложений"
            )
        ).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5), settings.debugDescription); row.tap()
        let choice = settings.cells.matching(
            NSPredicate(
                format: "label IN %@",
                allow
                    ? ["Allow", "Разрешить", "Разрешать"]
                    : ["Deny", "Don't Allow", "Отказать", "Запретить", "Не разрешать"]
            )
        ).firstMatch
        XCTAssertTrue(choice.waitForExistence(timeout: 5), settings.debugDescription); choice.tap()
        let selected = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in choice.exists && choice.isSelected }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [selected], timeout: 3), .completed)
        XCTContext.runActivity(named: "Actual system paste permission: \(allow ? "Allow" : "Deny")") { activity in
            let proof = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            proof.name = "system-paste-settings-\(allow ? "allow" : "deny")"; proof.lifetime = .keepAlways;
            activity.add(proof)
            let tree = XCTAttachment(string: settings.debugDescription); tree.lifetime = .keepAlways; activity.add(tree)
        }
    }
    @MainActor func testSystemPastePermissionAllow() throws {
        try Self.configurePastePermission(allow: true)
        let ciphertext = try prepare()
        let host = self.host(ciphertext)
        host.buttons["keyboard.decrypt"].tap()
        XCTAssertTrue(host.staticTexts["keyboard.decrypt.text"].waitForExistence(timeout: 5), host.debugDescription)
        XCTAssertEqual(host.staticTexts["keyboard.decrypt.sender"].label, "От: Анна07")
    }
    @MainActor func testSystemPastePermissionDeny() throws {
        addTeardownBlock { try await MainActor.run { try DecryptRuntimeTests.configurePastePermission(allow: true) } }
        try Self.configurePastePermission(allow: false)
        let ciphertext = try prepare()
        let host = self.host(ciphertext)
        let initial = try XCTUnwrap(try metrics(host)["decryptClipboardContentReads"] as? Int)
        host.buttons["keyboard.decrypt"].tap()
        let status = host.staticTexts["keyboard.decrypt.status"]
        XCTAssertTrue(status.waitForExistence(timeout: 5)); XCTAssertEqual(status.label, "Нет доступа к буферу обмена")
        XCTAssertFalse(host.staticTexts["keyboard.decrypt.text"].exists)
        XCTAssertFalse(host.staticTexts["keyboard.decrypt.signature"].exists)
        let deadline = Date().addingTimeInterval(3)
        while Date() < deadline {
            XCTAssertEqual(try metrics(host)["decryptClipboardContentReads"] as? Int, initial + 1)
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        let proof = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        proof.name = "real-user-denied-clipboard-no-retry"; proof.lifetime = .keepAlways; add(proof)
        host.buttons["keyboard.decrypt.close"].tap()
    }
    /// One retained ciphertext crosses actual 06 insertion, explicit host copying and both shipping 07 surfaces.
    @MainActor func testActualInsertedCiphertextSelfRoundTrip() throws {
        let app = XCUIApplication(bundleIdentifier: "dev.cipherkeyboard.app")
        app.launchArguments = []; app.launch()
        XCTAssertTrue(app.staticTexts["mykey.fingerprint"].waitForExistence(timeout: 15)); app.terminate()
        app.launchArguments = ["-encrypt-seed"]; app.launch()
        XCTAssertEqual(
            app.staticTexts["encrypt.seedResult"].label,
            "PASS: real Keychain identity; 20 synthetic public contacts")
        app.terminate(); try TypingTestSupport.configureKeyboard(fullAccess: true)
        XCUIDevice.shared.orientation = .portrait
        let host = XCUIApplication(bundleIdentifier: "dev.cipherkeyboard.typinghost")
        host.launchEnvironment = [:]; host.launch(); TypingTestSupport.openCipher(in: host)
        try TypingTestSupport.tapHostControl("Курсор", in: host)
        host.buttons["keyboard.recipient"].tap()
        let recipientName = ProcessInfo.processInfo.environment["CIPHER_NATIVE_RECIPIENT_NAME"] ?? "Анна06"
        let anna = host.buttons.matching(
            NSPredicate(
                format: "identifier BEGINSWITH %@ AND label BEGINSWITH %@", "keyboard.recipient.", recipientName + ","
            )
        ).firstMatch
        XCTAssertTrue(anna.waitForExistence(timeout: 5)); anna.tap()
        TypingTestSupport.fixture("enc-proof-decrypt", in: host)
        let expected = "  Привет, Анна!\nЗавтра в 19:30 👨‍👩‍👧‍👦  "
        XCTAssertEqual(TypingTestSupport.draft(in: host).value as? String, expected)
        host.buttons["keyboard.encrypt"].tap()
        let inserted = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label BEGINSWITH %@", "Зашифровано для "),
            object: host.staticTexts["keyboard.encrypt.status"])
        XCTAssertEqual(XCTWaiter.wait(for: [inserted], timeout: 5), .completed)
        let field = try XCTUnwrap(host.textViews["host.editor"].value as? String)
        XCTAssertTrue(field.hasPrefix("До ckmsg1:")); XCTAssertTrue(field.hasSuffix("встречи!"))
        XCTAssertTrue(
            host.staticTexts["host.trace"].label.hasPrefix(
                "insertions=1;deletions=0;replacements=0;ciphertext=true;"))
        let ciphertext = String(field.dropFirst(3).dropLast("встречи!".count))
        let retained = XCTAttachment(string: ciphertext); retained.name = "actual-06-inserted-for-07";
        retained.lifetime = .keepAlways; add(retained)
        host.terminate()
        let readerHost = self.host(ciphertext)
        readerHost.buttons["keyboard.decrypt"].tap()
        let allow = readerHost.alerts.buttons.matching(
            NSPredicate(
                format: "label CONTAINS[c] %@ OR label CONTAINS[c] %@", "Allow", "Разрешить"
            )
        ).firstMatch
        if allow.waitForExistence(timeout: 2) { allow.tap() }
        let text = readerHost.staticTexts["keyboard.decrypt.text"]
        XCTAssertTrue(text.waitForExistence(timeout: 5)); XCTAssertEqual(text.label, expected)
        XCTAssertEqual(readerHost.staticTexts["keyboard.decrypt.sender"].label, "От: вы")
        XCTAssertEqual(readerHost.staticTexts["keyboard.decrypt.signature"].label, "✓ Подпись верна")
        let proof = XCTAttachment(screenshot: readerHost.screenshot()); proof.name = "actual-06-to-07-keyboard-self";
        proof.lifetime = .keepAlways; add(proof)
        readerHost.buttons["keyboard.decrypt.close"].tap()
        XCTAssertEqual(readerHost.textViews["host.editor"].value as? String, "До встречи!")
        app.launchArguments = []; app.launch();
        app.tabBars.buttons.matching(NSPredicate(format: "label == %@", "Расшифровать")).firstMatch.tap()
        let paste = app.descendants(matching: .any)["decrypt.paste"].firstMatch
        XCTAssertTrue(paste.waitForExistence(timeout: 5)); paste.tap()
        let received = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value == %@", ciphertext), object: app.textViews["decrypt.input"])
        XCTAssertEqual(XCTWaiter.wait(for: [received], timeout: 5), .completed)
        app.buttons["decrypt.submit"].tap()
        XCTAssertTrue(app.staticTexts["decrypt.text"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["decrypt.text"].label, expected)
        XCTAssertEqual(app.staticTexts["decrypt.sender"].label, "От: вы")
        let appProof = XCTAttachment(screenshot: app.screenshot()); appProof.name = "actual-06-to-07-app-self";
        appProof.lifetime = .keepAlways; add(appProof)
        app.buttons["decrypt.close"].tap()
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
        XCTAssertTrue(host.buttons["keyboard.key.q"].exists)
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
