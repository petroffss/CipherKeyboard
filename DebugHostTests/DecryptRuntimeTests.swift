import XCTest
import Foundation

/// Installed production extension and independent UIKit host. Fixtures are used only for explicit fault/design states.
final class DecryptRuntimeTests: XCTestCase {
    override func setUp() { continueAfterFailure = false }
    @MainActor func testResultSenderReadability() throws {
        XCUIDevice.shared.orientation = .portrait
        let ciphertext = try prepare(); let host = host(ciphertext)
        let layoutKeys = ["keyboard.key.й", "keyboard.key.q"]
        let activeKeys = layoutKeys.filter { host.buttons[$0].exists }
        XCTAssertEqual(activeKeys.count, 1)
        let activeKey = try XCTUnwrap(activeKeys.first)
        let editor = TypingTestSupport.draft(in: host)
        XCTAssertTrue(editor.exists)
        let draft = try XCTUnwrap(editor.value as? String)
        let field = host.textViews["host.editor"]
        let diagnostics = host.staticTexts["host.diagnostics"]
        XCTAssertEqual(field.value as? String, "До встречи!")
        let selection = diagnostics.label
        XCTAssertTrue(selection.hasSuffix("Выделение UTF-16: 3, 7"), selection)
        host.buttons["keyboard.decrypt"].tap()
        let sender = host.staticTexts["keyboard.decrypt.sender"]
        XCTAssertTrue(sender.waitForExistence(timeout: 5), host.debugDescription)
        XCTAssertEqual(sender.label, "От: " + preparedSenderName)
        XCTAssertEqual(host.staticTexts["keyboard.decrypt.signature"].label, "✓ Подпись верна")
        let panel = host.otherElements["keyboard.decrypt.panel"]
        XCTAssertTrue(panel.frame.contains(sender.frame), host.debugDescription)
        XCTAssertGreaterThanOrEqual(host.buttons["keyboard.decrypt.close"].frame.height, 44)
        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "native402-sender-after"; screenshot.lifetime = .keepAlways; add(screenshot)
        let geometry = XCTAttachment(string: host.debugDescription)
        geometry.name = "native402-sender-after-geometry"; geometry.lifetime = .keepAlways; add(geometry)
        host.buttons["keyboard.decrypt.close"].tap()
        XCTAssertTrue(host.buttons[activeKey].waitForExistence(timeout: 5))
        XCTAssertEqual(layoutKeys.filter { host.buttons[$0].exists }, activeKeys)
        XCTAssertTrue(editor.isHittable)
        XCTAssertEqual(editor.value as? String, draft)
        XCTAssertEqual(field.value as? String, "До встречи!")
        XCTAssertEqual(diagnostics.label, selection)
        XCTAssertFalse(sender.exists)
        let restored = XCTAttachment(string: host.debugDescription)
        restored.name = "native402-restored-compose-geometry"; restored.lifetime = .keepAlways; add(restored)
    }
    @MainActor private var preparedSenderName = ""
    @MainActor private func prepare(_ mode: String = "contact") throws -> String {
        let app = XCUIApplication(bundleIdentifier: "dev.cipherkeyboard.app")
        app.launchArguments = []; app.launch()
        XCTAssertTrue(app.staticTexts["mykey.fingerprint"].waitForExistence(timeout: 15)); app.terminate()
        app.launchArguments = ["-contacts", "memory", "-simulator-test-shared-contacts", "-decrypt-seed"]
        app.launchEnvironment = ["CIPHER_DECRYPT_SYNTHETIC_CASE": mode]; app.launch()
        let output = app.staticTexts["decrypt.seedResult"]
        XCTAssertTrue(output.waitForExistence(timeout: 5))
        let ready = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label BEGINSWITH %@ OR label BEGINSWITH %@", "ckmsg", "FAIL:"),
            object: output)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 8), .completed)
        preparedSenderName = output.value as? String ?? ""
        let ciphertext = output.label; XCTAssertTrue(ciphertext.hasPrefix("ckmsg2:"), ciphertext)
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
        app.launchArguments = ["-contacts", "memory", "-simulator-test-shared-contacts", "-decrypt-seed"]
        app.launchEnvironment = ["CIPHER_DECRYPT_SYNTHETIC_CASE": "export-own-public-key"]; app.launch()
        let output = app.staticTexts["decrypt.seedResult"]
        let publicReady = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label BEGINSWITH %@", "ckpub1:"), object: output)
        XCTAssertEqual(XCTWaiter.wait(for: [publicReady], timeout: 8), .completed)
        XCTAssertTrue(output.label.hasPrefix("ckpub1:"))
        let publicKey = XCTAttachment(string: output.label); publicKey.name = "actual-keychain-public-key";
        publicKey.lifetime = .keepAlways; add(publicKey); app.terminate()
        if let key = ProcessInfo.processInfo.environment["CIPHER_NATIVE_IMPORT_PUBLIC_KEY"] {
            let name = try XCTUnwrap(ProcessInfo.processInfo.environment["CIPHER_NATIVE_IMPORT_NAME"])
            // Import through the ordinary Contacts screen, using the simulator QR source only as input.
            app.launchArguments = ["-contacts-scan", key]
            app.launchEnvironment = [:]
            app.launch()
            XCTAssertTrue(app.staticTexts["mykey.fingerprint"].waitForExistence(timeout: 15))
            let contacts = app.tabBars.buttons.matching(
                NSPredicate(format: "identifier == %@ OR label == %@", "tab.contacts", "Контакты")
            ).firstMatch
            XCTAssertTrue(contacts.waitForExistence(timeout: 5)); contacts.tap()
            let row = app.buttons.matching(
                NSPredicate(format: "identifier == %@ AND label BEGINSWITH %@", "contacts.row", name + ",")
            ).firstMatch
            if !row.exists {
                let first = app.buttons["contacts.addFirst"]
                let add = first.exists ? first : app.buttons["contacts.add"]
                XCTAssertTrue(add.waitForExistence(timeout: 5)); add.tap()
                app.buttons["addcontact.scan"].tap()
                let fingerprint = app.staticTexts["addcontact.fingerprint"]
                XCTAssertTrue(fingerprint.waitForExistence(timeout: 8))
                let field = app.textFields["addcontact.name"]
                XCTAssertTrue(field.waitForExistence(timeout: 5)); field.tap(); field.typeText(name)
                let exact = XCTNSPredicateExpectation(
                    predicate: NSPredicate(format: "value == %@", name), object: field)
                XCTAssertEqual(XCTWaiter.wait(for: [exact], timeout: 5), .completed)
                let save = app.buttons["addcontact.save"]
                XCTAssertTrue(save.isEnabled && save.isHittable); save.tap()
                XCTAssertTrue(app.staticTexts["addcontact.title"].waitForNonExistence(timeout: 5))
            }
            XCTAssertTrue(row.waitForExistence(timeout: 5)); row.tap()
            let imported = app.staticTexts["contact.publicKey"]
            XCTAssertTrue(imported.waitForExistence(timeout: 5))
            XCTAssertEqual(imported.label, key)
            app.terminate()
        }
    }
    /// Receiver phase consumes the exact retained C from the other device; it never creates a replacement envelope.
    @MainActor func testProvidedCiphertextReceiver() throws {
        let ciphertext = try XCTUnwrap(ProcessInfo.processInfo.environment["CIPHER_NATIVE_PROVIDED_CIPHERTEXT"])
        let sender = try XCTUnwrap(ProcessInfo.processInfo.environment["CIPHER_NATIVE_EXPECTED_SENDER"])
        XCTAssertTrue(ciphertext.hasPrefix("ckmsg2:"))
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
        XCTAssertEqual(host.staticTexts["keyboard.decrypt.sender"].label, "От: " + preparedSenderName)
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
        app.launchArguments = ["-contacts", "memory", "-simulator-test-shared-contacts", "-encrypt-seed"]; app.launch()
        XCTAssertEqual(
            app.staticTexts["encrypt.seedResult"].label,
            "PASS: real Keychain identity; 20 synthetic public contacts")
        app.terminate(); try TypingTestSupport.configureKeyboard(fullAccess: true)
        XCUIDevice.shared.orientation = .portrait
        let host = XCUIApplication(bundleIdentifier: "dev.cipherkeyboard.typinghost")
        host.launchEnvironment = [:]; host.launch(); TypingTestSupport.openCipher(in: host)
        try TypingTestSupport.tapHostControl("Курсор", in: host)
        host.buttons["keyboard.recipient"].tap()
        let recipientName = ProcessInfo.processInfo.environment["CIPHER_NATIVE_RECIPIENT_NAME"] ?? "Анна06 тест"
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
        XCTAssertTrue(field.hasPrefix("До ckmsg2:")); XCTAssertTrue(field.hasSuffix("встречи!"))
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
        XCUIDevice.shared.orientation = .portrait
        let ciphertext = try prepare(); try TypingTestSupport.configureKeyboard(fullAccess: true)
        let host = host(ciphertext)
        let portrait = host.frame.size
        XCTAssertGreaterThan(portrait.height, portrait.width)
        let before = try metrics(host)
        let initial = before["decryptClipboardContentReads"] as? Int ?? -1
        let initialMetadata = before["decryptClipboardMetadataReads"] as? Int ?? -1
        XCTAssertGreaterThanOrEqual(initial, 0); XCTAssertGreaterThanOrEqual(initialMetadata, 0)
        host.buttons["keyboard.language"].tap()
        XCUIDevice.shared.orientation = .landscapeLeft
        TypingTestSupport.waitLayout(in: host, width: portrait.height)
        XCUIDevice.shared.orientation = .portrait
        TypingTestSupport.waitLayout(in: host, width: portrait.width)
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
        XCTAssertEqual(host.staticTexts["keyboard.decrypt.sender"].label, "От: " + preparedSenderName)
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
            XCTAssertEqual(app.staticTexts["decrypt.sender"].label, "От: " + preparedSenderName)
            app.buttons["decrypt.close"].tap()
            XCTAssertTrue(app.textViews["decrypt.input"].exists)
            XCTAssertFalse(app.buttons["decrypt.submit"].isEnabled)
            copy("ckmsg2:invalid"); tab("Расшифровать"); pasteAndSubmit()
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
    @MainActor func testHeldLiveOpenDoesNotCrossSessionBoundaries() throws {
        XCUIDevice.shared.orientation = .portrait
        let ciphertext = try prepare()
        try TypingTestSupport.configureKeyboard(fullAccess: true)
        for event in ["document", "hide", "background", "globe"] {
            let host = host(ciphertext)
            let first = host.textViews["host.editor"]
            let second = host.textViews["host.editor2"]
            let outerPanel = host.otherElements["keyboard.panel"]
            let start = host.buttons["keyboard.decrypt"]
            let status = host.staticTexts["keyboard.decrypt.status"]
            let text = host.staticTexts["keyboard.decrypt.text"]
            let sender = host.staticTexts["keyboard.decrypt.sender"]
            let signature = host.staticTexts["keyboard.decrypt.signature"]
            let close = host.buttons["keyboard.decrypt.close"]
            let fixture = host.buttons["keyboard.debugFixtures"]

            func observed(_ condition: @escaping () -> Bool) {
                let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in condition() }, object: nil)
                XCTAssertEqual(
                    XCTWaiter.wait(for: [ready], timeout: 5), .completed, "\(event): \(host.debugDescription)")
            }
            func capture(_ stage: String) {
                let frame = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
                frame.name = "\(event)-\(stage)"; frame.lifetime = .keepAlways; add(frame)
                let hierarchy = XCTAttachment(string: host.debugDescription)
                hierarchy.name = "\(event)-\(stage)-ax"; hierarchy.lifetime = .keepAlways; add(hierarchy)
            }
            func hasNoResult() -> Bool {
                !status.exists && !text.exists && !sender.exists && !signature.exists && !close.exists
            }
            func liveMetrics() -> [String: Any]? {
                guard let raw = fixture.value as? String else { return nil }
                return (try? JSONSerialization.jsonObject(with: Data(raw.utf8))) as? [String: Any]
            }

            observed { first.exists && first.debugDescription.contains("Keyboard Focused") }
            XCTAssertEqual(first.value as? String, "До встречи!")
            let before = try metrics(host)
            let reads = try XCTUnwrap(before["decryptClipboardContentReads"] as? Int)
            let metadata = try XCTUnwrap(before["decryptClipboardMetadataReads"] as? Int)
            let held = try XCTUnwrap(before["decryptHeldOpenCount"] as? Int)
            TypingTestSupport.fixture("hold-live-decrypt", in: host)
            XCTAssertTrue(start.isEnabled)
            XCTAssertTrue(hasNoResult())
            let armed = try metrics(host)
            XCTAssertEqual(armed["decryptClipboardContentReads"] as? Int, reads)
            XCTAssertEqual(armed["decryptClipboardMetadataReads"] as? Int, metadata)
            XCTAssertEqual(armed["decryptLiveOperations"] as? Int, 0)
            start.tap()
            observed {
                let values = liveMetrics()
                return status.exists && status.label == "Расшифровываем…"
                    && values?["decryptHeldOpenCount"] as? Int == held + 1
                    && values?["decryptLiveOperations"] as? Int == 1
            }
            let busy = try metrics(host)
            XCTAssertEqual(busy["decryptClipboardContentReads"] as? Int, reads + 1)
            XCTAssertEqual(busy["decryptClipboardMetadataReads"] as? Int, metadata + 1)
            XCTAssertEqual(busy["decryptBusy"] as? Bool, true)
            XCTAssertFalse(text.exists); XCTAssertFalse(sender.exists); XCTAssertFalse(signature.exists)
            XCTAssertTrue(close.isHittable)
            capture("held-open")

            switch event {
            case "document":
                try TypingTestSupport.tapHostControl("Поле2", in: host)
                observed { !first.exists && second.exists && second.debugDescription.contains("Keyboard Focused") }
                XCTAssertEqual(second.value as? String, "Второе поле")
            case "hide":
                try TypingTestSupport.tapHostControl("Скрыть", in: host)
                observed {
                    host.staticTexts["host.focus"].label == "hide=true; focused=false"
                        && !outerPanel.exists && hasNoResult()
                }
                capture("keyboard-hidden")
                try TypingTestSupport.tapHostControl("Открыть", in: host)
            case "background":
                XCUIDevice.shared.press(.home)
                observed { host.state == .runningBackground || host.state == .runningBackgroundSuspended }
                capture("host-background")
                host.activate()
                if !outerPanel.waitForExistence(timeout: 3) {
                    try TypingTestSupport.tapHostControl("Открыть", in: host)
                }
            default:
                let ownGlobe = host.buttons["keyboard.next"]
                let systemGlobe = host.buttons.matching(
                    NSPredicate(format: "label IN %@", ["Next keyboard", "Следующая клавиатура"])
                ).firstMatch
                let globe = ownGlobe.isHittable ? ownGlobe : systemGlobe
                XCTAssertTrue(globe.isHittable)
                globe.press(forDuration: 0.8)
                let russian = host.staticTexts.matching(
                    NSPredicate(format: "label IN %@", ["Русская", "Russian"])
                ).firstMatch
                XCTAssertTrue(russian.waitForExistence(timeout: 5)); russian.tap()
                observed { !outerPanel.exists && host.keyboards.firstMatch.keys.firstMatch.exists }
                capture("stock-keyboard")
                TypingTestSupport.openCipher(in: host)
            }

            observed {
                let values = liveMetrics()
                return start.isHittable && start.isEnabled && hasNoResult()
                    && values?["decryptLiveOperations"] as? Int == 0
                    && values?["decryptBusy"] as? Bool == false
            }
            TypingTestSupport.verifyBuild(in: host)
            capture("cleared-after-late-open")
            XCTAssertTrue(hasNoResult())
            let cleared = try metrics(host)
            if event == "document" {
                XCTAssertEqual(cleared["decryptHeldOpenCount"] as? Int, held + 1)
                XCTAssertEqual(cleared["decryptClipboardContentReads"] as? Int, reads + 1)
                XCTAssertEqual(cleared["decryptClipboardMetadataReads"] as? Int, metadata + 1)
            }

            start.tap()
            XCTAssertTrue(text.waitForExistence(timeout: 5), host.debugDescription)
            XCTAssertEqual(text.label, "  Привет, Анна!\nЗавтра в 19:30 👨‍👩‍👧‍👦  ")
            XCTAssertEqual(sender.label, "От: " + preparedSenderName)
            XCTAssertEqual(signature.label, "✓ Подпись верна")
            let recovered = try metrics(host)
            XCTAssertEqual(
                recovered["decryptClipboardContentReads"] as? Int,
                try XCTUnwrap(cleared["decryptClipboardContentReads"] as? Int) + 1)
            XCTAssertEqual(recovered["decryptHeldOpenCount"] as? Int, cleared["decryptHeldOpenCount"] as? Int)
            capture("new-explicit-result")
            close.tap()
            XCTAssertTrue(text.waitForNonExistence(timeout: 5))
            host.terminate()
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
