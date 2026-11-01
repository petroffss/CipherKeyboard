import UIKit
import XCTest

/// Run once on each native 375/402/440 profile. The full method captures 62 frames per profile.
final class KeyboardMatrixTests: XCTestCase {
    override func setUp() { continueAfterFailure = false }
    private let states = [
        "ru-empty", "ru-text", "shift", "caps", "en", "numbers", "symbols", "alternate-e", "alternate-softsign",
        "multiline", "limit", "no-access", "no-key", "key-error", "contacts-error",
    ]

    @MainActor func testMatrixSmoke() throws {
        try capture(
            states: states, themes: ["light"],
            includePreview: true,
            prefix: "smoke")
    }
    // The runner sets and reads back actual Simulator OS appearance between these two batches.
    @MainActor func testCaptureLightCurrentProfile() throws {
        try capture(states: states, themes: ["light"], includePreview: true, prefix: "typing")
    }
    @MainActor func testCaptureDarkCurrentProfile() throws {
        try capture(states: states, themes: ["dark"], includePreview: true, prefix: "typing")
    }
    @MainActor func testDarkLandscapeAndPreviewControl() throws {
        try capture(
            states: ["ru-text", "multiline", "limit", "no-access"], themes: ["dark"], includePreview: true,
            prefix: "smoke")
    }
    @MainActor private func capture(states: [String], themes: [String], includePreview: Bool, prefix: String) throws {
        XCUIDevice.shared.orientation = .portrait
        let host = XCUIApplication(bundleIdentifier: "dev.cipherkeyboard.typinghost")
        for theme in themes {
            host.launchArguments = ["-typing-theme", theme]
            host.launch(); TypingTestSupport.openCipher(in: host)
            let width = host.frame.width
            let height = host.frame.height
            XCTAssertTrue([375.0, 402.0, 440.0].contains(width))
            XCTAssertEqual(height, [375.0: 667.0, 402.0: 874.0, 440.0: 956.0][width])
            for landscape in [false, true] {
                XCUIDevice.shared.orientation = landscape ? .landscapeLeft : .portrait
                TypingTestSupport.waitLayout(in: host, width: landscape ? height : width)
                for state in states {
                    TypingTestSupport.fixture(state, in: host)
                    if state.hasPrefix("alternate-") {
                        XCTAssertTrue(host.staticTexts["keyboard.alternative"].waitForExistence(timeout: 2))
                    }
                    try captureFrame(
                        app: host, kind: "extension", width: width, landscape: landscape, theme: theme, state: state,
                        prefix: prefix)
                }
            }
            XCUIDevice.shared.orientation = .portrait
            TypingTestSupport.waitLayout(in: host, width: width)
            if includePreview {
                let app = XCUIApplication(bundleIdentifier: "dev.cipherkeyboard.app")
                app.launchArguments = []
                TypingTestSupport.openPreview(app)
                TypingTestSupport.fixture("preview", in: app)
                try captureFrame(
                    app: app, kind: "preview", width: width, landscape: false, theme: theme, state: "preview",
                    prefix: prefix)
            }
        }
        XCUIDevice.shared.orientation = .portrait
    }

    @MainActor private func captureFrame(
        app: XCUIApplication, kind: String, width: CGFloat, landscape: Bool, theme: String, state: String,
        prefix: String
    ) throws {
        TypingTestSupport.verifyBuild(in: app)
        XCTAssertFalse(app.otherElements["keyboard.fixtureGrid"].exists)
        XCTAssertTrue(app.buttons["keyboard.debugFixtures"].label.contains("fixture=" + state + ";"))
        XCTAssertEqual(XCUIDevice.shared.orientation.isLandscape, landscape)
        let expectedWidth = landscape ? [375.0: 667.0, 402.0: 874.0, 440.0: 956.0][width]! : width
        let expectedHeight = landscape ? width : [375.0: 667.0, 402.0: 874.0, 440.0: 956.0][width]!
        var last: [CGRect] = []
        var stable = 0
        let settled = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in
                let current = [
                    app.frame, TypingTestSupport.draft(in: app).frame,
                    app.descendants(matching: .any)["keyboard.panel"].firstMatch.frame,
                    app.buttons["keyboard.return"].frame,
                ]
                guard current[0].width == expectedWidth, current[0].height == expectedHeight else { return false }
                stable = current == last ? stable + 1 : 0
                last = current
                return stable >= 2
            }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [settled], timeout: 8), .completed, "Unsettled frame geometry")
        let renderData = try XCTUnwrap(app.buttons["keyboard.debugFixtures"].value as? String).data(using: .utf8)
        let rendered = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(renderData)) as? [String: Any])
        XCTAssertEqual(rendered["resolvedTheme"] as? String, theme, "Actual UIKit trait must match the frame theme")
        XCTAssertEqual(rendered["caretVisible"] as? Bool, true, "The real draft caret must be visible")
        let warning = ["no-access", "no-key", "key-error", "contacts-error"].contains(state)
        XCTAssertEqual(rendered["warning"] as? Bool, warning)
        XCTAssertEqual(rendered["statusFont"] as? Double, landscape ? 10 : (warning ? 12 : 11))
        if warning {
            XCTAssertEqual(rendered["statusLineHeight"] as? Double, landscape ? 12 : 15)
            let color = try XCTUnwrap(rendered["statusColor"] as? [Double])
            let primary: [Double] = theme == "dark" ? [1, 1, 1, 1] : [0, 0, 0, 1]
            XCTAssertEqual(color.count, primary.count)
            // UIColor's color-space conversion may represent white as 1.000000119.
            for (actual, expected) in zip(color, primary) { XCTAssertEqual(actual, expected, accuracy: 0.000001) }
        }
        if ["multiline", "limit"].contains(state) {
            let excerpt = "Привет, Анна!\nВстречаемся завтра.\nЯ буду у входа.\nНапиши, когда придёшь.\nДо встречи!"
            XCTAssertTrue((TypingTestSupport.draft(in: app).value as? String)?.hasPrefix(excerpt) == true)
            XCTAssertEqual(rendered["cursor"] as? Int, 0)
            XCTAssertEqual(app.buttons["keyboard.shift"].value as? String, "Строчные")
            XCTAssertEqual(app.buttons["keyboard.key.й"].label, "й")
            if state == "limit" { XCTAssertEqual(rendered["byteCount"] as? Int, 4096) }
        }
        let panel = app.descendants(matching: .any)["keyboard.panel"].firstMatch
        XCTAssertTrue(panel.exists)
        let panelFrame = panel.frame
        var hostField: [String: Any] = [:]
        if kind == "extension" {
            let field = app.textViews["host.editor"]
            XCTAssertTrue(field.exists && field.isHittable, "Actual editable host field must remain usable")
            XCTAssertEqual(field.value as? String, "До встречи!")
            let visibleArea = app.frame.intersection(
                CGRect(
                    x: app.frame.minX, y: app.frame.minY,
                    width: app.frame.width, height: panelFrame.minY - app.frame.minY))
            let intersection = field.frame.intersection(visibleArea)
            XCTAssertGreaterThanOrEqual(field.frame.height, 48)
            XCTAssertTrue(visibleArea.contains(field.frame), "The whole host field must be above the actual panel")
            XCTAssertEqual(intersection.height, field.frame.height, accuracy: 0.5)
            XCTAssertEqual(intersection.width, field.frame.width, accuracy: 0.5)
            hostField = [
                "frame": rectangle(field.frame), "visibleIntersection": rectangle(intersection),
                "hittable": field.isHittable,
            ]
        }
        XCTAssertLessThanOrEqual(panelFrame.height, landscape ? 240 : 420)
        var keys: [[String: Any]] = []
        let allKeys = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "keyboard."))
            .allElementsBoundByIndex
        for key in allKeys where key.identifier != "keyboard.debugFixtures" {
            let rect = key.frame
            XCTAssertGreaterThanOrEqual(rect.height, landscape ? 32 : 44)
            if key.identifier.hasPrefix("keyboard.key.") { XCTAssertGreaterThanOrEqual(rect.width, 26) }
            XCTAssertGreaterThanOrEqual(rect.minX, panelFrame.minX - 0.5)
            XCTAssertLessThanOrEqual(rect.maxX, panelFrame.maxX + 0.5)
            XCTAssertLessThanOrEqual(rect.maxY, panelFrame.maxY + 0.5)
            keys.append(["id": key.identifier, "label": key.label, "rect": rectangle(rect)])
        }
        for name in ["delete", "language", "numbers", "space", "return"] {
            XCTAssertTrue(app.buttons["keyboard." + name].exists)
        }
        let ownGlobe = app.buttons["keyboard.next"].exists
        if kind == "preview" { XCTAssertFalse(ownGlobe) }
        if state.hasPrefix("alternate-") {
            let popup = app.staticTexts["keyboard.alternative"].frame
            XCTAssertTrue(panelFrame.contains(popup))
        }
        if state == "limit" {
            XCTAssertEqual(app.staticTexts["keyboard.counter"].label, "4096 / 4096 байт")
            XCTAssertEqual(app.staticTexts["keyboard.limitError"].label, "Сообщение не должно превышать 4096 байт")
        }
        let orientation = landscape ? "landscape" : "portrait"
        let name = "\(prefix)-frame--\(kind)--\(Int(width))--\(orientation)--\(theme)--\(state)"
        let image = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); image.name = name;
        image.lifetime = .keepAlways;
        add(image)
        let metadata: [String: Any] = [
            "kind": kind, "width": Int(width), "orientation": orientation, "theme": theme, "state": state,
            "panel": rectangle(panelFrame), "editor": rectangle(TypingTestSupport.draft(in: app).frame), "keys": keys,
            "ownGlobe": ownGlobe, "scale": UIScreen.main.scale,
            "rendered": rendered, "hostField": hostField,
            "build": app.buttons["keyboard.debugFixtures"].label,
            "hostGeometry": kind == "extension" ? app.staticTexts["host.controlsGeometry"].label : "portrait preview",
        ]
        let data = try JSONSerialization.data(withJSONObject: metadata, options: [.prettyPrinted, .sortedKeys])
        let geometry = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
        geometry.name = name.replacingOccurrences(of: "-frame--", with: "-geometry--")
        geometry.lifetime = .keepAlways; add(geometry)
    }
    private func rectangle(_ rect: CGRect) -> [String: Double] {
        ["x": rect.minX, "y": rect.minY, "width": rect.width, "height": rect.height]
    }
}
