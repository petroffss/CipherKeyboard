import XCTest

final class KeyboardRuntimeTests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    /// Setup is intentionally separate from captures and before/after persistence snapshots.
    @MainActor func testFullAccessPreflight() throws {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication(bundleIdentifier: "dev.cipherkeyboard.app")
        app.launchArguments = []
        app.launch()
        XCTAssertTrue(app.staticTexts["mykey.fingerprint"].waitForExistence(timeout: 15))
        XCTAssertFalse(app.staticTexts["mykey.fingerprint"].label.isEmpty)
        app.terminate()
        app.launchArguments = ["-typing-identity-metadata"]
        app.launch()
        XCTAssertEqual(
            app.staticTexts["typing.identityMetadata"].label,
            "PASS: real identity.v1; attributes only; rows=1")
        let identityProof = XCTAttachment(string: app.staticTexts["typing.identityMetadata"].label)
        identityProof.name = "real-identity-attribute-query-precondition"; identityProof.lifetime = .keepAlways
        add(identityProof)
        app.terminate()
        try TypingTestSupport.configureKeyboard(fullAccess: true)
        let host = XCUIApplication(bundleIdentifier: "dev.cipherkeyboard.typinghost")
        host.launch(); TypingTestSupport.openCipher(in: host)
        XCTAssertTrue(host.staticTexts["keyboard.identityStatus"].label.hasPrefix("Ваш ключ: "))
        try TypingTestSupport.tapHostControl("Скрыть", in: host)
        XCTAssertTrue(TypingTestSupport.draft(in: host).waitForNonExistence(timeout: 5))
        XCUIDevice.shared.press(.home)
        host.terminate()
    }

    @MainActor func testClipboardSentinelSetup() {
        let host = XCUIApplication(bundleIdentifier: "dev.cipherkeyboard.typinghost")
        host.launchArguments = ["-typing-audit-setup"]
        host.launch()
        host.buttons["host.setSentinel"].tap()
        XCTAssertEqual(host.staticTexts["host.sentinelStatus"].label, "sentinel=true")
        let proof = XCTAttachment(screenshot: host.screenshot())
        proof.name = "actual-in-process-clipboard-sentinel-readback"; proof.lifetime = .keepAlways; add(proof)
        XCUIDevice.shared.press(.home)
        host.terminate()
    }

    @MainActor func testEditingMatrixWithoutFullAccess() throws { try editingMatrix(fullAccess: false) }
    @MainActor func testEditingMatrixWithFullAccess() throws { try editingMatrix(fullAccess: true) }
    @MainActor private func editingMatrix(fullAccess: Bool) throws {
        try TypingTestSupport.configureKeyboard(fullAccess: fullAccess)
        for selected in [false, true] {
            let host = XCUIApplication(bundleIdentifier: "dev.cipherkeyboard.typinghost")
            host.launch()
            if !selected { host.buttons["Пустое"].tap() }
            TypingTestSupport.openCipher(in: host)
            let initial = host.staticTexts["host.diagnostics"].label
            if !fullAccess {
                XCTAssertEqual(
                    host.staticTexts["keyboard.identityStatus"].label,
                    "Включите «Полный доступ» в Настройках, чтобы шифровать",
                    "Real extension metadata: " + String(describing: host.buttons["keyboard.debugFixtures"].value))
            }
            TypingTestSupport.assertReset(in: host)
            TypingTestSupport.sequence(in: host)
            XCTAssertEqual(host.staticTexts["host.diagnostics"].label, initial)
            let attachment = XCTAttachment(screenshot: host.screenshot())
            attachment.name = "editing-access-\(fullAccess)-selected-\(selected)"; attachment.lifetime = .keepAlways;
            add(attachment)
            try TypingTestSupport.tapHostControl("Скрыть", in: host)
            XCTAssertEqual(host.staticTexts["host.focus"].label, "hide=true; focused=false")
            XCTAssertTrue(TypingTestSupport.draft(in: host).waitForNonExistence(timeout: 5))
            TypingTestSupport.openCipher(in: host)
            TypingTestSupport.assertReset(in: host)
        }
    }

    @MainActor func testBackgroundGlobeAndShellParity() throws {
        let host = XCUIApplication(bundleIdentifier: "dev.cipherkeyboard.typinghost")
        host.launch(); TypingTestSupport.openCipher(in: host)
        TypingTestSupport.sequence(in: host)
        let extensionText = TypingTestSupport.draft(in: host).value as? String
        XCUIDevice.shared.press(.home)
        host.activate(); TypingTestSupport.openCipher(in: host)
        TypingTestSupport.assertReset(in: host)
        host.buttons["keyboard.key.п"].tap()
        let own = host.buttons["keyboard.next"]
        let system = host.buttons.matching(
            NSPredicate(format: "label == %@ OR label == %@", "Next keyboard", "Следующая клавиатура")
        ).firstMatch
        let globe = own.exists ? own : system
        XCTAssertTrue(globe.exists)
        XCTAssertFalse(own.exists && system.exists && own.identifier != system.identifier)
        globe.press(forDuration: 0.8)
        let russian = host.staticTexts.matching(NSPredicate(format: "label == %@ OR label == %@", "Русская", "Russian"))
            .firstMatch
        XCTAssertTrue(russian.waitForExistence(timeout: 5)); russian.tap()
        XCTAssertTrue(TypingTestSupport.draft(in: host).waitForNonExistence(timeout: 5))
        TypingTestSupport.openCipher(in: host); TypingTestSupport.assertReset(in: host)
        let app = XCUIApplication(bundleIdentifier: "dev.cipherkeyboard.app")
        TypingTestSupport.openPreview(app)
        TypingTestSupport.sequence(in: app)
        XCTAssertEqual(TypingTestSupport.draft(in: app).value as? String, extensionText)
        XCTAssertEqual(app.staticTexts["preview.host"].label, "До встречи!")
        XCTAssertFalse(app.buttons["keyboard.next"].exists)
    }

    @MainActor func testNoExportCanary() throws {
        let host = XCUIApplication(bundleIdentifier: "dev.cipherkeyboard.typinghost")
        host.launch(); TypingTestSupport.openCipher(in: host)
        TypingTestSupport.fixture("canary", in: host)
        let editor = TypingTestSupport.draft(in: host)
        XCTAssertEqual(editor.value as? String, "TypingCanary05-Ж-20261101")
        let before = host.staticTexts["host.diagnostics"].label
        editor.press(forDuration: 0.8)
        for label in ["Copy", "Cut", "Paste", "Копировать", "Вырезать", "Вставить", "Share", "Поделиться"] {
            XCTAssertFalse(host.menuItems[label].exists)
        }
        editor.press(forDuration: 1, thenDragTo: host.textViews["host.editor"])
        XCTAssertEqual(host.staticTexts["host.diagnostics"].label, before)
        XCTAssertEqual(editor.value as? String, "TypingCanary05-Ж-20261101")
        let evidence = XCTAttachment(screenshot: host.screenshot())
        evidence.name = "canary-noexport"; evidence.lifetime = .keepAlways; add(evidence)
        try TypingTestSupport.tapHostControl("Скрыть", in: host)
        XCTAssertEqual(host.staticTexts["host.focus"].label, "hide=true; focused=false")
        XCTAssertTrue(editor.waitForNonExistence(timeout: 5))
        TypingTestSupport.openCipher(in: host)
        TypingTestSupport.assertReset(in: host)
        TypingTestSupport.fixture("canary", in: host)
        XCUIDevice.shared.press(.home)
        host.terminate()
    }

    @MainActor func testOrdinarySettingsSearchIsolation() throws {
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
            globe.press(forDuration: 0.8)
            settings.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "CipherKeyboard")).firstMatch.tap()
        }
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        TypingTestSupport.verifyBuild(in: settings)
        let before = field.value as? String
        for key in ["п", "р", "и"] { settings.buttons["keyboard.key." + key].tap() }
        settings.buttons["keyboard.delete"].tap(); settings.buttons["keyboard.return"].tap()
        XCTAssertEqual(editor.value as? String, "Пр\n")
        XCTAssertEqual(field.value as? String, before)
    }
}
