import XCTest

/// Actual installed extension, OS Full Access, real stores and editable UIKit host.
final class EncryptRuntimeTests: XCTestCase {
    override func setUp() { continueAfterFailure = false }
    @MainActor func testEncryptionPreflight() throws {
        let app = XCUIApplication(bundleIdentifier: "dev.cipherkeyboard.app")
        app.launchArguments = []; app.launch()
        XCTAssertTrue(app.staticTexts["mykey.fingerprint"].waitForExistence(timeout: 15))
        app.terminate()
        app.launchArguments = ["-encrypt-seed"]; app.launch()
        XCTAssertEqual(
            app.staticTexts["encrypt.seedResult"].label, "PASS: real Keychain identity; 20 synthetic public contacts")
        let sender = try XCTUnwrap(app.staticTexts["encrypt.seedResult"].value as? String)
        XCTAssertTrue(sender.hasPrefix("ckpub1:"))
        let publicProof = XCTAttachment(string: sender); publicProof.name = "encrypt06-sender-public-key";
        publicProof.lifetime = .keepAlways; add(publicProof)
        app.terminate()
        try TypingTestSupport.configureKeyboard(fullAccess: true)
    }
    @MainActor private func selectAnna(in host: XCUIApplication) {
        host.buttons["keyboard.recipient"].tap()
        let anna = host.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@ AND label BEGINSWITH %@", "keyboard.recipient.", "Анна06,")
        ).firstMatch
        XCTAssertTrue(anna.waitForExistence(timeout: 4), host.debugDescription)
        anna.tap()
    }
    @MainActor func testRealInsertAndTenCycles() throws {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication(bundleIdentifier: "dev.cipherkeyboard.app")
        app.launchArguments = ["-encrypt-seed"]; app.launch()
        let sender = try XCTUnwrap(app.staticTexts["encrypt.seedResult"].value as? String)
        XCTAssertTrue(sender.hasPrefix("ckpub1:"))
        let publicProof = XCTAttachment(string: sender); publicProof.name = "encrypt06-sender-public-key";
        publicProof.lifetime = .keepAlways; add(publicProof)
        app.terminate()
        let host = XCUIApplication(bundleIdentifier: "dev.cipherkeyboard.typinghost")
        host.launch(); TypingTestSupport.openCipher(in: host)
        for index in 0..<10 {
            // Empty host selection at the middle of its existing text.
            try TypingTestSupport.tapHostControl("С выделением", in: host)
            let field = host.textViews["host.editor"]
            field.tap()  // collapse selection using the actual host, never through the keyboard proxy
            // Place the caret precisely through the host's explicit Debug action.
            try TypingTestSupport.tapHostControl("Курсор", in: host)
            selectAnna(in: host)
            if index == 9 {
                TypingTestSupport.fixture("enc-bytes4096", in: host)
            } else {
                for key in ["п", "р", "и", "в", "е", "т"] { host.buttons["keyboard.key." + key].tap() }
            }
            XCTAssertTrue(host.buttons["keyboard.encrypt"].isEnabled)
            host.buttons["keyboard.encrypt"].tap()
            let success = XCTNSPredicateExpectation(
                predicate: NSPredicate(format: "label BEGINSWITH %@", "Зашифровано для "),
                object: host.staticTexts["keyboard.encrypt.status"])
            XCTAssertEqual(XCTWaiter.wait(for: [success], timeout: 5), .completed)
            XCTAssertEqual(TypingTestSupport.draft(in: host).value as? String, "")
            let result = try XCTUnwrap(field.value as? String)
            XCTAssertTrue(result.hasPrefix("До ckmsg1:")); XCTAssertTrue(result.hasSuffix("встречи!"))
            XCTAssertTrue(
                host.staticTexts["host.trace"].label.hasPrefix(
                    "insertions=1;deletions=0;replacements=0;ciphertext=true;"))
            let attachment = XCTAttachment(string: result)
            attachment.name = "encrypt06-host-result-\(index)"; attachment.lifetime = .keepAlways; add(attachment)
            let screenshot = XCTAttachment(screenshot: host.screenshot()); screenshot.name = "encrypt06-cycle-\(index)";
            screenshot.lifetime = .keepAlways; add(screenshot)
            try TypingTestSupport.tapHostControl("Скрыть", in: host)
            XCTAssertTrue(TypingTestSupport.draft(in: host).waitForNonExistence(timeout: 5))
            TypingTestSupport.openCipher(in: host)
            XCTAssertEqual(TypingTestSupport.draft(in: host).value as? String, "")
        }
    }
    @MainActor func testSelectionAndSuccessGeometry() throws {
        let host = XCUIApplication(bundleIdentifier: "dev.cipherkeyboard.typinghost")
        host.launch(); TypingTestSupport.openCipher(in: host)
        try TypingTestSupport.tapHostControl("С выделением", in: host)
        selectAnna(in: host)
        host.buttons["keyboard.key.а"].tap()
        host.buttons["keyboard.encrypt"].tap()
        XCTAssertEqual(host.staticTexts["keyboard.encrypt.status"].label, "Снимите выделение в поле сообщения")
        XCTAssertEqual(host.textViews["host.editor"].value as? String, "До встречи!")
        let draft = TypingTestSupport.draft(in: host).value as? String
        try TypingTestSupport.tapHostControl("Курсор", in: host)
        XCTAssertEqual(TypingTestSupport.draft(in: host).value as? String, draft)
        let before = [
            TypingTestSupport.draft(in: host).frame, host.buttons["keyboard.return"].frame,
            host.textViews["host.editor"].frame,
        ]
        host.buttons["keyboard.encrypt"].tap()
        let appeared = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label BEGINSWITH %@", "Зашифровано для "),
            object: host.staticTexts["keyboard.encrypt.status"])
        XCTAssertEqual(XCTWaiter.wait(for: [appeared], timeout: 4), .completed)
        let start = Date()
        XCTAssertEqual(
            before,
            [
                TypingTestSupport.draft(in: host).frame, host.buttons["keyboard.return"].frame,
                host.textViews["host.editor"].frame,
            ])
        let gone = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "NOT (label BEGINSWITH %@)", "Зашифровано для "),
            object: host.staticTexts["keyboard.encrypt.status"])
        XCTAssertEqual(XCTWaiter.wait(for: [gone], timeout: 3), .completed)
        XCTAssertLessThanOrEqual(Date().timeIntervalSince(start), 2.3)
        XCTAssertEqual(
            before,
            [
                TypingTestSupport.draft(in: host).frame, host.buttons["keyboard.return"].frame,
                host.textViews["host.editor"].frame,
            ])
        host.buttons["keyboard.key.б"].tap();
        XCTAssertFalse((TypingTestSupport.draft(in: host).value as? String ?? "").isEmpty)
    }
    @MainActor func testDoubleTapDelayedSelectionAndCancellation() throws {
        let host = XCUIApplication(bundleIdentifier: "dev.cipherkeyboard.typinghost")
        host.launch(); TypingTestSupport.openCipher(in: host)
        try TypingTestSupport.tapHostControl("С выделением", in: host)
        try TypingTestSupport.tapHostControl("Курсор", in: host)
        selectAnna(in: host)
        host.buttons["keyboard.key.а"].tap()
        TypingTestSupport.fixture("enc-delay", in: host)
        host.buttons["keyboard.encrypt"].doubleTap()
        XCTAssertEqual(host.staticTexts["keyboard.encrypt.status"].label, "Шифруем…")
        XCTAssertFalse(host.buttons["keyboard.recipient"].isEnabled)
        XCTAssertFalse(host.buttons["keyboard.key.б"].isEnabled)
        try TypingTestSupport.tapHostControl("С выделением", in: host)
        let selectionError = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label == %@", "Снимите выделение в поле сообщения"),
            object: host.staticTexts["keyboard.encrypt.status"])
        XCTAssertEqual(XCTWaiter.wait(for: [selectionError], timeout: 5), .completed)
        XCTAssertEqual(host.textViews["host.editor"].value as? String, "До встречи!")
        XCTAssertEqual(TypingTestSupport.draft(in: host).value as? String, "А")
        try TypingTestSupport.tapHostControl("Курсор", in: host)
        host.buttons["keyboard.encrypt"].doubleTap()
        let success = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label BEGINSWITH %@", "Зашифровано для "),
            object: host.staticTexts["keyboard.encrypt.status"])
        XCTAssertEqual(XCTWaiter.wait(for: [success], timeout: 5), .completed)
        XCTAssertTrue(host.staticTexts["host.trace"].label.hasPrefix("insertions=1;deletions=0;replacements=0;"))
        try TypingTestSupport.tapHostControl("С выделением", in: host)
        try TypingTestSupport.tapHostControl("Курсор", in: host)
        host.buttons["keyboard.key.а"].tap(); host.buttons["keyboard.encrypt"].tap()
        try TypingTestSupport.tapHostControl("Скрыть", in: host)
        XCTAssertTrue(TypingTestSupport.draft(in: host).waitForNonExistence(timeout: 5))
        TypingTestSupport.openCipher(in: host)
        XCTAssertEqual(TypingTestSupport.draft(in: host).value as? String, "")
        XCTAssertEqual(host.textViews["host.editor"].value as? String, "До встречи!")
    }
    @MainActor func testLiveMultilinePickerAndFailureRecovery() throws {
        let host = XCUIApplication(bundleIdentifier: "dev.cipherkeyboard.typinghost")
        host.launch(); TypingTestSupport.openCipher(in: host)
        try TypingTestSupport.tapHostControl("Курсор", in: host)
        for _ in 0..<4 { host.buttons["keyboard.key.а"].tap(); host.buttons["keyboard.return"].tap() }
        let draft = TypingTestSupport.draft(in: host).value as? String
        host.buttons["keyboard.recipient"].tap()
        let list = host.scrollViews["keyboard.recipient.list"]
        XCTAssertTrue(list.exists); list.swipeUp(); list.swipeUp()
        let long = host.buttons.matching(
            NSPredicate(
                format: "identifier BEGINSWITH %@ AND label BEGINSWITH %@", "keyboard.recipient.",
                String(repeating: "Я", count: 40))
        ).firstMatch
        XCTAssertTrue(long.isHittable); long.tap()
        XCTAssertTrue(host.buttons["keyboard.recipient"].label.contains(String(repeating: "Я", count: 40)))
        XCTAssertEqual(TypingTestSupport.draft(in: host).value as? String, draft)
        for landscape in [true, false] {
            XCUIDevice.shared.orientation = landscape ? .landscapeLeft : .portrait
            let dimensions = host.frame.size
            TypingTestSupport.waitLayout(
                in: host,
                width: landscape ? max(dimensions.width, dimensions.height) : min(dimensions.width, dimensions.height))
            XCTAssertEqual(TypingTestSupport.draft(in: host).value as? String, draft)
            host.buttons["keyboard.recipient"].tap(); host.buttons["keyboard.recipient.back"].tap()
            XCTAssertTrue(host.buttons["keyboard.return"].isHittable)
        }
        TypingTestSupport.fixture("enc-fault", in: host); host.buttons["keyboard.encrypt"].tap()
        let failure = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label == %@", "Не удалось зашифровать сообщение. Повторите попытку"),
            object: host.staticTexts["keyboard.encrypt.status"])
        XCTAssertEqual(XCTWaiter.wait(for: [failure], timeout: 5), .completed)
        XCTAssertEqual(TypingTestSupport.draft(in: host).value as? String, draft)
        TypingTestSupport.fixture("enc-normal", in: host); host.buttons["keyboard.encrypt"].tap()
        let success = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label BEGINSWITH %@", "Зашифровано для "),
            object: host.staticTexts["keyboard.encrypt.status"])
        XCTAssertEqual(XCTWaiter.wait(for: [success], timeout: 5), .completed)
        XCTAssertEqual(TypingTestSupport.draft(in: host).value as? String, "")
    }
    @MainActor func testEncryptAuditCanary() throws {
        let host = XCUIApplication(bundleIdentifier: "dev.cipherkeyboard.typinghost")
        host.launch(); TypingTestSupport.openCipher(in: host)
        try TypingTestSupport.tapHostControl("Курсор", in: host)
        selectAnna(in: host)
        TypingTestSupport.fixture("enc-canary", in: host)
        TypingTestSupport.fixture("enc-fault", in: host); host.buttons["keyboard.encrypt"].tap()
        let failure = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label == %@", "Не удалось зашифровать сообщение. Повторите попытку"),
            object: host.staticTexts["keyboard.encrypt.status"])
        XCTAssertEqual(XCTWaiter.wait(for: [failure], timeout: 5), .completed)
        XCTAssertEqual(TypingTestSupport.draft(in: host).value as? String, "EncryptCanary06-Ж-20261102")
        TypingTestSupport.fixture("enc-normal", in: host); host.buttons["keyboard.encrypt"].tap()
        let cleared = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value == %@", ""), object: TypingTestSupport.draft(in: host))
        XCTAssertEqual(XCTWaiter.wait(for: [cleared], timeout: 5), .completed)
        try TypingTestSupport.tapHostControl("Скрыть", in: host)
        host.terminate(); XCUIDevice.shared.press(.home)
    }

    @MainActor func testTwoHostDocumentsRejectLateCompletion() throws {
        let host = XCUIApplication(bundleIdentifier: "dev.cipherkeyboard.typinghost")
        host.launch(); TypingTestSupport.openCipher(in: host)
        try TypingTestSupport.tapHostControl("Курсор", in: host)
        selectAnna(in: host); host.buttons["keyboard.key.а"].tap()
        TypingTestSupport.fixture("enc-delay", in: host)
        host.buttons["keyboard.encrypt"].tap()
        try TypingTestSupport.tapHostControl("Поле2", in: host)
        XCTAssertEqual(host.textViews["host.editor2"].value as? String, "Второе поле")
        let documentError = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label == %@", "Поле сообщения изменилось — повторите попытку"),
            object: host.staticTexts["keyboard.encrypt.status"])
        XCTAssertEqual(XCTWaiter.wait(for: [documentError], timeout: 5), .completed)
        XCTAssertEqual(TypingTestSupport.draft(in: host).value as? String, "А")
        XCTAssertEqual(host.textViews["host.editor2"].value as? String, "Второе поле")
        try TypingTestSupport.tapHostControl("Поле2", in: host)
        XCTAssertEqual(host.textViews["host.editor"].value as? String, "До встречи!")
    }
    @MainActor func testOrdinarySettingsEncryption() throws {
        try TypingTestSupport.configureKeyboard(fullAccess: true)
        let settings = XCUIApplication(bundleIdentifier: "com.apple.Preferences")
        settings.launch()
        for _ in 0..<8 {
            if settings.searchFields.firstMatch.exists { break }
            let back = settings.navigationBars.buttons.firstMatch
            if back.exists { back.tap() } else { break }
        }
        let field = settings.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5)); field.tap()
        let editor = TypingTestSupport.draft(in: settings)
        if !editor.waitForExistence(timeout: 2) {
            let globe = settings.buttons.matching(
                NSPredicate(format: "label == %@ OR label == %@", "Next keyboard", "Следующая клавиатура")
            ).firstMatch
            XCTAssertTrue(globe.exists); globe.press(forDuration: 0.8)
            settings.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "CipherKeyboard")).firstMatch.tap()
        }
        XCTAssertTrue(editor.waitForExistence(timeout: 5)); TypingTestSupport.verifyBuild(in: settings)
        selectAnna(in: settings)
        let before = field.value as? String
        settings.buttons["keyboard.key.а"].tap()
        XCTAssertEqual(field.value as? String, before)
        settings.buttons["keyboard.encrypt"].tap()
        let inserted = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value BEGINSWITH %@", "ckmsg1:"), object: field)
        XCTAssertEqual(XCTWaiter.wait(for: [inserted], timeout: 5), .completed)
        XCTAssertEqual(editor.value as? String, "")
        let actualCiphertext = try XCTUnwrap(field.value as? String)
        let app = XCUIApplication(bundleIdentifier: "dev.cipherkeyboard.app")
        app.launchArguments = ["-encrypt-self-open"]
        app.launchEnvironment = ["CIPHER_INSERTED_SYNTHETIC_CIPHERTEXT": actualCiphertext]
        app.launch()
        let selfOpen = app.staticTexts["encrypt.selfOpenResult"]
        XCTAssertTrue(selfOpen.waitForExistence(timeout: 5))
        XCTAssertTrue(
            selfOpen.label.hasPrefix(
                "PASS: actual inserted ciphertext; Keychain sender self-open; exact UTF-8; sender.me; ckpub1:"))
        let selfProof = XCTAttachment(string: selfOpen.label);
        selfProof.name = "encrypt06-actual-Keychain-sender-self-open"; selfProof.lifetime = .keepAlways; add(selfProof)
        app.terminate(); settings.activate()
        let proof = XCTAttachment(screenshot: settings.screenshot()); proof.name = "encrypt06-ordinary-settings-insert";
        proof.lifetime = .keepAlways; add(proof)
    }

}
