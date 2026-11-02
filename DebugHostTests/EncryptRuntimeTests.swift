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
    /// Establish ordinary-touch arrival before observing the editor restored by selection.
    @MainActor private func activateVisibleLongRecipient(
        _ row: XCUIElement, in host: XCUIApplication, list: XCUIElement, proofName: String
    ) {
        list.swipeUp()
        var previousFrame = CGRect.null
        var previousViewport = CGRect.null
        var stableSince = Date()
        let settled = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in
                guard row.exists, list.exists else { stableSince = Date(); return false }
                let frame = row.frame, viewport = list.frame
                let intersection = viewport.intersection(frame)
                let fullyVisible =
                    frame.width > 0 && frame.height > 0
                    && intersection.width >= frame.width - 0.5 && intersection.height >= frame.height - 0.5
                let ready = fullyVisible && row.isHittable
                if frame != previousFrame || viewport != previousViewport || !ready {
                    previousFrame = frame; previousViewport = viewport; stableSince = Date()
                }
                return ready && Date().timeIntervalSince(stableSince) >= 0.25
            }, object: nil)
        XCTAssertEqual(
            XCTWaiter.wait(for: [settled], timeout: 5), .completed,
            "Recipient row must be fully visible and stable before activation")
        let geometry = XCTAttachment(string: "stable row=\(row.frame); viewport=\(list.frame)")
        geometry.name = proofName; geometry.lifetime = .keepAlways; add(geometry)
        row.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.35)).tap()
        XCTAssertTrue(list.waitForNonExistence(timeout: 5), "Recipient picker must close after ordinary touch")
        XCTAssertEqual(host.buttons["keyboard.recipient"].label, "Кому: " + String(repeating: "Я", count: 40))
        XCTAssertTrue(TypingTestSupport.draft(in: host).waitForExistence(timeout: 5))
    }
    @MainActor private func nativeCiphertext(from result: String) -> String {
        let prefix = "До ", suffix = "встречи!"
        XCTAssertTrue(result.hasPrefix(prefix)); XCTAssertTrue(result.hasSuffix(suffix))
        let ciphertext = String(result.dropFirst(prefix.count).dropLast(suffix.count))
        XCTAssertNotNil(ciphertext.range(of: #"\Ackmsg1:[A-Za-z0-9_-]+\z"#, options: .regularExpression))
        return ciphertext
    }
    /// Only retained native C and a public closed case ID cross into the app.
    /// The expected text and actual sender's private key never cross this boundary.
    @MainActor private func actualSenderVerdict(
        _ ciphertext: String, caseID: String, proofName: String
    ) -> String {
        let app = XCUIApplication(bundleIdentifier: "dev.cipherkeyboard.app")
        app.launchArguments = ["-encrypt-self-open"]
        app.launchEnvironment = [
            "CIPHER_INSERTED_SYNTHETIC_CIPHERTEXT": ciphertext,
            "CIPHER_INSERTED_SYNTHETIC_CASE": caseID,
        ]
        app.launch()
        let result = app.staticTexts["encrypt.selfOpenResult"]
        XCTAssertTrue(result.waitForExistence(timeout: 5))
        let verdict = result.label
        let proof = XCTAttachment(string: verdict)
        proof.name = proofName; proof.lifetime = .keepAlways; add(proof)
        app.terminate()
        return verdict
    }
    private func expectedSenderVerdict(_ publicKey: String, caseID: String) -> String {
        "PASS: actual inserted ciphertext; Keychain sender self-open; exact UTF-8; sender.me; "
            + publicKey + "; case=" + caseID
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
        var nativeResults: [(caseID: String, ciphertext: String)] = []
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
            nativeResults.append((index == 9 ? "native-ascii4096" : "native-hello", nativeCiphertext(from: result)))
            let screenshot = XCTAttachment(screenshot: host.screenshot()); screenshot.name = "encrypt06-cycle-\(index)";
            screenshot.lifetime = .keepAlways; add(screenshot)
            try TypingTestSupport.tapHostControl("Скрыть", in: host)
            XCTAssertTrue(TypingTestSupport.draft(in: host).waitForNonExistence(timeout: 5))
            TypingTestSupport.openCipher(in: host)
            XCTAssertEqual(TypingTestSupport.draft(in: host).value as? String, "")
        }
        // Verify these same ten native ciphertexts as actual Keychain A after all lifecycle cycles finish.
        XCTAssertEqual(nativeResults.count, 10)
        for (index, record) in nativeResults.enumerated() {
            XCTAssertEqual(
                actualSenderVerdict(
                    record.ciphertext, caseID: record.caseID, proofName: "encrypt06-native-cycle-\(index)-actual-A"),
                expectedSenderVerdict(sender, caseID: record.caseID))
        }
    }
    @MainActor func testNativeLiteralAndUnicodeActualSenderProof() throws {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication(bundleIdentifier: "dev.cipherkeyboard.app")
        app.launchArguments = ["-encrypt-seed"]; app.launch()
        let seeded = app.staticTexts["encrypt.seedResult"]
        XCTAssertTrue(seeded.waitForExistence(timeout: 15))
        XCTAssertEqual(seeded.label, "PASS: real Keychain identity; 20 synthetic public contacts")
        let sender = try XCTUnwrap(seeded.value as? String)
        XCTAssertTrue(sender.hasPrefix("ckpub1:")); app.terminate()
        let host = XCUIApplication(bundleIdentifier: "dev.cipherkeyboard.typinghost")
        let cases = [
            (id: "native-literal-anna", text: "Привет, Анна!"),
            (id: "native-whitespace-unicode", text: "  Привет, Анна! 👨‍👩‍👧‍👦\nе\u{301}  \n"),
            (id: "native-hello", text: "Привет"),
            (id: "native-ascii4096", text: String(repeating: "a", count: 4096)),
        ]
        host.launch()
        for (index, proofCase) in cases.enumerated() {
            host.activate(); TypingTestSupport.openCipher(in: host)
            try TypingTestSupport.tapHostControl("С выделением", in: host)
            try TypingTestSupport.tapHostControl("Курсор", in: host)
            selectAnna(in: host)
            let field = host.textViews["host.editor"], editor = TypingTestSupport.draft(in: host)
            let unchanged = field.value as? String
            if index == 0 {
                for key in ["п", "р", "и", "в", "е", "т"] { host.buttons["keyboard.key." + key].tap() }
                host.buttons["keyboard.numbers"].tap(); host.buttons["keyboard.key.,"].tap()
                host.buttons["keyboard.numbers"].tap(); host.buttons["keyboard.space"].tap()
                host.buttons["keyboard.shift"].tap()
                for key in ["а", "н", "н", "а"] { host.buttons["keyboard.key." + key].tap() }
                host.buttons["keyboard.numbers"].tap(); host.buttons["keyboard.key.!"].tap()
                host.buttons["keyboard.numbers"].tap()
            } else if proofCase.id == "native-whitespace-unicode" {
                // Fixed input only; this fixture keeps the real coordinator/readers/sealer/identity.
                TypingTestSupport.fixture("enc-proof-unicode", in: host)
            } else if proofCase.id == "native-ascii4096" {
                TypingTestSupport.fixture("enc-bytes4096", in: host)
            } else {
                for key in ["п", "р", "и", "в", "е", "т"] { host.buttons["keyboard.key." + key].tap() }
            }
            XCTAssertEqual(Array(try XCTUnwrap(editor.value as? String).utf8), Array(proofCase.text.utf8))
            XCTAssertEqual(field.value as? String, unchanged)
            host.buttons["keyboard.encrypt"].tap()
            let success = XCTNSPredicateExpectation(
                predicate: NSPredicate(format: "label BEGINSWITH %@", "Зашифровано для "),
                object: host.staticTexts["keyboard.encrypt.status"])
            XCTAssertEqual(XCTWaiter.wait(for: [success], timeout: 5), .completed)
            XCTAssertEqual(editor.value as? String, "")
            XCTAssertTrue(
                host.staticTexts["host.trace"].label.hasPrefix(
                    "insertions=1;deletions=0;replacements=0;ciphertext=true;"))
            let result = try XCTUnwrap(field.value as? String)
            let ciphertext = nativeCiphertext(from: result)
            let retained = XCTAttachment(string: result)
            retained.name = "encrypt06-\(proofCase.id)-host-result"; retained.lifetime = .keepAlways; add(retained)
            XCTAssertEqual(
                actualSenderVerdict(ciphertext, caseID: proofCase.id, proofName: "encrypt06-\(proofCase.id)-actual-A"),
                expectedSenderVerdict(sender, caseID: proofCase.id))
            if index == 0 {
                // A valid native C must not pass under a different expected constant.
                XCTAssertEqual(
                    actualSenderVerdict(ciphertext, caseID: "native-hello", proofName: "encrypt06-native-wrong-case"),
                    "FAIL: self-open verification")
                for (invalidIndex, invalidID) in ["unsupported-synthetic-case", ""].enumerated() {
                    XCTAssertEqual(
                        actualSenderVerdict(
                            ciphertext, caseID: invalidID, proofName: "encrypt06-native-unknown-case-\(invalidIndex)"),
                        "FAIL: unsupported synthetic case")
                }
                XCTAssertEqual(
                    actualSenderVerdict("ckmsg1:broken", caseID: proofCase.id, proofName: "encrypt06-native-malformed"),
                    "FAIL: self-open")
                var tampered = ciphertext
                let byte = tampered.index(tampered.endIndex, offsetBy: -8)
                let replacement = tampered[byte] == "A" ? "B" : "A"
                tampered.replaceSubrange(byte...byte, with: replacement)
                XCTAssertEqual(
                    actualSenderVerdict(tampered, caseID: proofCase.id, proofName: "encrypt06-native-tampered"),
                    "FAIL: self-open")
            }
        }
    }
    @MainActor private func assertNativeCaretAfterResize(
        in host: XCUIApplication, text: String, cursor: Int, theme: String, landscape: Bool, proofName: String
    ) throws {
        let fixtures = host.buttons["keyboard.debugFixtures"]
        let editor = TypingTestSupport.draft(in: host)
        let panel = host.descendants(matching: .any)["keyboard.panel"].firstMatch
        var stable = 0
        var conditions: [String: Bool] = [:]
        let visible = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in
                guard let raw = (fixtures.value as? String)?.data(using: .utf8),
                    let state = (try? JSONSerialization.jsonObject(with: raw)) as? [String: Any],
                    let width = state["editorViewportWidth"] as? Double,
                    let height = state["editorViewportHeight"] as? Double
                else { conditions = ["metadataParsed": false]; stable = 0; return false }
                let frame = editor.frame
                let available = panel.frame.width - 88
                let expectedWidth =
                    landscape ? available - max(352, (available - 12) / 1.75) - 12 : panel.frame.width - 12
                conditions = [
                    "metadataParsed": true, "caretVisible": state["caretVisible"] as? Bool == true,
                    "theme": state["resolvedTheme"] as? String == theme,
                    "frameWidth": abs(frame.width - expectedWidth) <= 0.5,
                    "frameHeight": abs(frame.height - (landscape ? 38 : 100)) <= 2,
                    "metadataWidth": abs(width - frame.width) <= 0.5,
                    "metadataHeight": abs(height - frame.height) <= 0.5,
                ]
                guard conditions.values.allSatisfy({ $0 }) else { stable = 0; return false }
                stable += 1; return stable >= 2
            }, object: nil)
        let outcome = XCTWaiter.wait(for: [visible], timeout: 8)
        let raw = try XCTUnwrap((fixtures.value as? String)?.data(using: .utf8))
        let state = try XCTUnwrap(JSONSerialization.jsonObject(with: raw) as? [String: Any])
        func rectangle(_ rect: CGRect) -> [String: Double] {
            ["x": rect.minX, "y": rect.minY, "width": rect.width, "height": rect.height]
        }
        let textMatches = editor.value as? String == text
        var observation: [String: Any] = [
            "rendered": state, "editorFrame": rectangle(editor.frame), "panelFrame": rectangle(panel.frame),
            "expectedLandscape": landscape, "textMatches": textMatches,
            "conditions": conditions, "stablePolls": stable,
        ]
        if textMatches { observation["syntheticText"] = text }
        let image = XCTAttachment(screenshot: host.screenshot())
        image.name = proofName; image.lifetime = .keepAlways; add(image)
        let geometry = XCTAttachment(
            data: try JSONSerialization.data(withJSONObject: observation, options: [.sortedKeys]),
            uniformTypeIdentifier: "public.json")
        geometry.name = proofName + "-geometry"; geometry.lifetime = .keepAlways; add(geometry)
        XCTAssertEqual(state["cursor"] as? Int, cursor)
        XCTAssertEqual(state["resolvedTheme"] as? String, theme)
        XCTAssertEqual(TypingTestSupport.draft(in: host).value as? String, text)
        XCTAssertTrue(host.buttons["keyboard.recipient"].label.contains(String(repeating: "Я", count: 40)))
        XCTAssertFalse(host.scrollViews["keyboard.recipient.list"].exists)
        XCTAssertEqual(host.textViews["host.editor"].value as? String, "До встречи!")
        let available = panel.frame.width - 88
        let expectedWidth = landscape ? available - max(352, (available - 12) / 1.75) - 12 : panel.frame.width - 12
        XCTAssertEqual(editor.frame.width, expectedWidth, accuracy: 0.5)
        XCTAssertEqual(editor.frame.height, landscape ? 38 : 100, accuracy: 2)
        XCTAssertEqual(try XCTUnwrap(state["editorViewportWidth"] as? Double), editor.frame.width, accuracy: 0.5)
        XCTAssertEqual(try XCTUnwrap(state["editorViewportHeight"] as? Double), editor.frame.height, accuracy: 0.5)
        XCTAssertEqual(state["caretVisible"] as? Bool, true)
        XCTAssertEqual(outcome, .completed, "Two consecutive complete viewport samples were not observed")
        for id in ["keyboard.key.й", "keyboard.key.ф", "keyboard.key.я", "keyboard.return"] {
            XCTAssertTrue(host.buttons[id].isHittable)
        }
    }
    @MainActor func testNativeCaretFollowsFinalViewportBothThemes() throws {
        let app = XCUIApplication(bundleIdentifier: "dev.cipherkeyboard.app")
        app.launchArguments = ["-encrypt-seed"]; app.launch()
        let seed = app.staticTexts["encrypt.seedResult"]
        XCTAssertTrue(seed.waitForExistence(timeout: 15))
        XCTAssertEqual(seed.label, "PASS: real Keychain identity; 20 synthetic public contacts")
        app.terminate()
        for theme in ["light", "dark"] {
            XCUIDevice.shared.orientation = .portrait
            let host = XCUIApplication(bundleIdentifier: "dev.cipherkeyboard.typinghost")
            host.launchArguments = ["-typing-theme", theme]; host.launch()
            TypingTestSupport.openCipher(in: host)
            let portraitWidth = min(host.frame.width, host.frame.height)
            let landscapeWidth = max(host.frame.width, host.frame.height)
            try TypingTestSupport.tapHostControl("С выделением", in: host)
            try TypingTestSupport.tapHostControl("Курсор", in: host)
            for key in ["п", "р", "и"] { host.buttons["keyboard.key." + key].tap() }
            for _ in 0..<3 { host.buttons["keyboard.return"].tap(); host.buttons["keyboard.key.а"].tap() }
            let draft = "При\nА\nА\nА"
            XCTAssertEqual(TypingTestSupport.draft(in: host).value as? String, draft)
            host.buttons["keyboard.recipient"].tap()
            let list = host.scrollViews["keyboard.recipient.list"]
            list.swipeUp(); list.swipeUp()
            let long = host.buttons.matching(
                NSPredicate(
                    format: "identifier BEGINSWITH %@ AND label BEGINSWITH %@", "keyboard.recipient.",
                    String(repeating: "Я", count: 40))
            ).firstMatch
            XCTAssertTrue(long.isHittable)
            activateVisibleLongRecipient(
                long, in: host, list: list, proofName: "encrypt-native-caret-\(theme)-long-row-before-activation")
            try assertNativeCaretAfterResize(
                in: host, text: draft, cursor: draft.count, theme: theme, landscape: false,
                proofName: "encrypt-native-caret-\(theme)-portrait-before")
            // No picker/back, seed or text action may conceal a failed resize between these assertions.
            for (index, landscape) in [true, false, true, false].enumerated() {
                if landscape {
                    XCUIDevice.shared.orientation = index == 2 ? .landscapeRight : .landscapeLeft
                } else {
                    XCUIDevice.shared.orientation = .portrait
                }
                TypingTestSupport.waitLayout(in: host, width: landscape ? landscapeWidth : portraitWidth)
                try assertNativeCaretAfterResize(
                    in: host, text: draft, cursor: draft.count, theme: theme, landscape: landscape,
                    proofName: "encrypt-native-caret-\(theme)-resize-\(index)")
                if index == 0 { try assertNativeManualScroll(in: host, text: draft, theme: theme) }
            }
            try TypingTestSupport.tapHostControl("Скрыть", in: host)
            XCTAssertTrue(TypingTestSupport.draft(in: host).waitForNonExistence(timeout: 5))
            host.terminate()
        }
    }
    @MainActor private func assertNativeManualScroll(in host: XCUIApplication, text: String, theme: String) throws {
        let fixtures = host.buttons["keyboard.debugFixtures"]
        func snapshot() -> [String: Any]? {
            guard let raw = (fixtures.value as? String)?.data(using: .utf8) else { return nil }
            return (try? JSONSerialization.jsonObject(with: raw)) as? [String: Any]
        }
        let initial = try XCTUnwrap(snapshot()?["editorOffsetY"] as? Double)
        XCTAssertGreaterThan(initial, 5)
        TypingTestSupport.draft(in: host).swipeDown()
        var previous: Double?, stable = 0
        let preserved = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in
                guard let state = snapshot(), let offset = state["editorOffsetY"] as? Double,
                    offset < initial - 5, state["caretVisible"] as? Bool == false,
                    state["cursor"] as? Int == text.count,
                    let height = state["editorViewportHeight"] as? Double, abs(height - 38) <= 0.5
                else { stable = 0; return false }
                stable = previous.map { abs($0 - offset) <= 0.5 } == true ? stable + 1 : 0
                previous = offset
                return stable >= 2
            }, object: nil)
        let outcome = XCTWaiter.wait(for: [preserved], timeout: 8)
        let proofName = "encrypt-native-\(theme)-manual-scroll-preserved"
        let image = XCTAttachment(screenshot: host.screenshot())
        image.name = proofName; image.lifetime = .keepAlways; add(image)
        let raw = try XCTUnwrap((fixtures.value as? String)?.data(using: .utf8))
        var observation = try XCTUnwrap(JSONSerialization.jsonObject(with: raw) as? [String: Any])
        observation["initialOffsetY"] = initial
        observation["stablePolls"] = stable
        let geometry = XCTAttachment(
            data: try JSONSerialization.data(withJSONObject: observation, options: [.sortedKeys]),
            uniformTypeIdentifier: "public.json")
        geometry.name = proofName + "-geometry"; geometry.lifetime = .keepAlways; add(geometry)
        XCTAssertEqual(TypingTestSupport.draft(in: host).value as? String, text)
        XCTAssertEqual(observation["cursor"] as? Int, text.count)
        XCTAssertLessThan(try XCTUnwrap(observation["editorOffsetY"] as? Double), initial - 5)
        XCTAssertEqual(observation["caretVisible"] as? Bool, false)
        XCTAssertEqual(outcome, .completed, "Manual scroll offset did not settle without changing the cursor")
        // The next actual viewport change must bring the unchanged model cursor back into view.
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
        XCTAssertTrue(long.isHittable)
        activateVisibleLongRecipient(
            long, in: host, list: list, proofName: "encrypt-native-multiline-long-row-before-activation")
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
