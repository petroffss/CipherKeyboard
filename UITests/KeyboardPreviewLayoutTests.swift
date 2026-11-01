import XCTest

/// Run on native 375/402/440 pt profiles with actual light and dark OS appearance.
/// Drafts in the dynamic regression come exclusively from production key gestures.
final class KeyboardPreviewLayoutTests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    private let instruction = "Набирайте текст внутри клавиатуры. При выходе черновик будет стёрт"

    @MainActor func testRealKeysDynamicHeaderAndLifecycle() throws {
        let app = XCUIApplication()
        app.launchEnvironment = [:]
        app.launchArguments = []
        app.launch()
        XCTAssertTrue(app.staticTexts["mykey.title"].waitForExistence(timeout: 10))
        app.navigationTab("tab.setup").tap()
        app.scrollViews["setup.scroll"].swipeUp()
        app.buttons["setup.tryKeyboard"].tap()
        let editor = draft(app)
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        XCTAssertEqual(editor.value as? String, "")
        let baseline = app.staticTexts[instruction].frame
        let returnFrame = app.buttons["keyboard.return"].frame
        try capture(app, stage: "empty", baseline: baseline, returnFrame: returnFrame)

        var expected = ""
        for line in 1...5 {
            if line > 1 { app.buttons["keyboard.return"].tap(); expected += "\n" }
            app.buttons["keyboard.key.а"].tap(); expected += "А"
            XCTAssertEqual(editor.value as? String, expected)
            try capture(app, stage: "grow-\(line)", baseline: baseline, returnFrame: returnFrame)
        }
        let fullHeight = editor.frame.height
        // Real scrolling must preserve the entire draft. Tapping its last visible line restores the end caret.
        editor.swipeDown()
        XCTAssertEqual(editor.value as? String, expected)
        editor.swipeUp()
        XCTAssertEqual(editor.value as? String, expected)
        editor.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.85)).tap()
        XCTAssertEqual(try metadata(app)["cursor"] as? Int, expected.count)
        try capture(app, stage: "scrolled-end", baseline: baseline, returnFrame: returnFrame)

        for _ in 0..<4 { app.buttons["keyboard.delete"].tap() }
        expected = "А\nА\nА"
        XCTAssertEqual(editor.value as? String, expected)
        XCTAssertLessThan(editor.frame.height, fullHeight)
        XCTAssertEqual(app.staticTexts[instruction].frame.minY, baseline.minY, accuracy: 0.5)
        try capture(app, stage: "shrink-three", baseline: baseline, returnFrame: returnFrame)

        // Put the caret after the first letter, then cross the header's fit boundary in both directions.
        editor.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: 20, dy: 18)).tap()
        XCTAssertEqual(try metadata(app)["cursor"] as? Int, 1)
        for cycle in 1...2 {
            app.buttons["keyboard.return"].tap()
            XCTAssertEqual(editor.value as? String, "А\n\nА\nА")
            XCTAssertEqual(try metadata(app)["cursor"] as? Int, 2)
            try capture(app, stage: "middle-grow-\(cycle)", baseline: baseline, returnFrame: returnFrame)
            app.buttons["keyboard.delete"].tap()
            XCTAssertEqual(editor.value as? String, expected)
            XCTAssertEqual(try metadata(app)["cursor"] as? Int, 1)
            try capture(app, stage: "middle-shrink-\(cycle)", baseline: baseline, returnFrame: returnFrame)
        }
        app.buttons["keyboard.key.б"].tap()
        XCTAssertEqual(editor.value as? String, "Аб\nА\nА")
        XCTAssertEqual(try metadata(app)["cursor"] as? Int, 2)
        try capture(app, stage: "middle-insert", baseline: baseline, returnFrame: returnFrame)

        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.buttons["setup.tryKeyboard"].tap()
        try assertReset(app)
        app.buttons["keyboard.key.а"].tap()
        app.navigationTab("tab.myKey").tap()
        app.navigationTab("tab.setup").tap()
        try assertReset(app)
        app.buttons["keyboard.key.а"].tap()
        XCUIDevice.shared.press(.home)
        app.activate()
        try assertReset(app)
        try capture(app, stage: "background-reset", baseline: baseline, returnFrame: returnFrame)
    }

    /// A separate synthetic anchor control; never used to substitute for the real-key regression above.
    @MainActor func testNormalPreviewAnchorGeometry() throws {
        let app = XCUIApplication()
        app.launchArguments = []
        app.launchEnvironment = ["CIPHER_TYPING_FIXTURE": "preview"]
        app.launch()
        XCTAssertTrue(app.staticTexts["mykey.title"].waitForExistence(timeout: 10))
        app.navigationTab("tab.setup").tap()
        app.scrollViews["setup.scroll"].swipeUp()
        app.buttons["setup.tryKeyboard"].tap()
        XCTAssertTrue(draft(app).waitForExistence(timeout: 5))
        XCTAssertEqual(draft(app).value as? String, "Привет, Анна!")
        try capture(
            app, stage: "normal-anchor", baseline: app.staticTexts[instruction].frame,
            returnFrame: app.buttons["keyboard.return"].frame)
    }

    @MainActor private func draft(_ app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)["keyboard.editor"].firstMatch
    }

    @MainActor private func metadata(_ app: XCUIApplication) throws -> [String: Any] {
        let value = try XCTUnwrap(app.buttons["keyboard.debugFixtures"].value as? String)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: Data(value.utf8)) as? [String: Any])
    }

    @MainActor private func assertReset(_ app: XCUIApplication) throws {
        XCTAssertTrue(draft(app).waitForExistence(timeout: 5))
        XCTAssertEqual(draft(app).value as? String, "")
        XCTAssertEqual(try metadata(app)["cursor"] as? Int, 0)
        XCTAssertEqual(app.buttons["keyboard.shift"].value as? String, "Заглавные")
        XCTAssertTrue(app.buttons["keyboard.key.й"].exists)
    }

    @MainActor private func capture(
        _ app: XCUIApplication, stage: String, baseline: CGRect, returnFrame: CGRect
    ) throws {
        let prompt = app.staticTexts[instruction]
        let caption = app.staticTexts["Поле приложения"]
        let host = app.staticTexts["preview.host"]
        let panel = app.descendants(matching: .any)["keyboard.panel"].firstMatch
        var previous: [CGRect] = []
        var stable = 0
        let settled = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in
                let frames = [prompt.frame, caption.frame, host.frame, panel.frame, self.draft(app).frame]
                stable = frames == previous ? stable + 1 : 0
                previous = frames
                return stable >= 2
            }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [settled], timeout: 5), .completed)
        XCTAssertEqual(app.staticTexts.matching(identifier: instruction).count, 1)
        XCTAssertEqual(app.staticTexts.matching(identifier: "preview.host").count, 1)
        XCTAssertEqual(prompt.frame.height, baseline.height, accuracy: 0.5)
        XCTAssertGreaterThanOrEqual(prompt.frame.height, 35, "AX label alone cannot prove two rendered lines")
        XCTAssertGreaterThanOrEqual(prompt.frame.minY, app.navigationBars.firstMatch.frame.maxY)
        XCTAssertLessThanOrEqual(prompt.frame.maxY, caption.frame.minY)
        XCTAssertLessThanOrEqual(caption.frame.maxY, host.frame.minY)
        XCTAssertLessThanOrEqual(host.frame.maxY, panel.frame.minY)
        XCTAssertEqual(host.label, "До встречи!")
        XCTAssertGreaterThanOrEqual(host.frame.height, 44)
        XCTAssertLessThanOrEqual(panel.frame.height, 420)
        XCTAssertEqual(app.buttons["keyboard.return"].frame, returnFrame)
        XCTAssertEqual(app.keyboards.count, 0)
        var keys: [String: [String: Double]] = [:]
        let panelFrame = panel.frame
        // One real AX snapshot retains per-key bounds without repeated IPC per attribute.
        func collectKeys(_ node: any XCUIElementSnapshot) {
            if node.elementType == .button && node.identifier.hasPrefix("keyboard.")
                && node.identifier != "keyboard.debugFixtures"
            {
                XCTAssertTrue(node.isEnabled)
                XCTAssertGreaterThanOrEqual(node.frame.height, 44)
                if node.identifier.hasPrefix("keyboard.key.") { XCTAssertGreaterThanOrEqual(node.frame.width, 26) }
                XCTAssertTrue(panelFrame.contains(node.frame))
                keys[node.identifier] = rectangle(node.frame)
            }
            for child in node.children { collectKeys(child) }
        }
        collectKeys(try app.snapshot())
        for id in ["key.й", "key.а", "shift", "language", "numbers", "space", "return", "delete"] {
            XCTAssertNotNil(keys["keyboard." + id])
        }
        let rendered = try metadata(app)
        XCTAssertEqual(rendered["caretVisible"] as? Bool, true)
        let theme = try XCTUnwrap(rendered["resolvedTheme"] as? String)
        let name = "preview-dynamic--\(Int(app.frame.width))--\(theme)--\(stage)"
        let image = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        image.name = name; image.lifetime = .keepAlways; add(image)
        let data = try JSONSerialization.data(
            withJSONObject: [
                "stage": stage, "theme": theme, "app": rectangle(app.frame),
                "instruction": rectangle(prompt.frame), "caption": rectangle(caption.frame),
                "host": rectangle(host.frame), "panel": rectangle(panel.frame),
                "editor": rectangle(draft(app).frame), "keys": keys, "rendered": rendered,
                "build": app.buttons["keyboard.debugFixtures"].label,
            ], options: [.prettyPrinted, .sortedKeys])
        let geometry = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
        geometry.name = name + "--geometry"; geometry.lifetime = .keepAlways; add(geometry)
    }

    private func rectangle(_ frame: CGRect) -> [String: Double] {
        ["x": frame.minX, "y": frame.minY, "width": frame.width, "height": frame.height]
    }
}
