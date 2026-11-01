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
    @MainActor func testCaptureAllCurrentProfile() throws {
        try capture(states: states, themes: ["light", "dark"], includePreview: true, prefix: "typing")
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
                app.launchArguments = ["-AppleInterfaceStyle", theme == "dark" ? "Dark" : "Light"]
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
        let panel = app.descendants(matching: .any)["keyboard.panel"].firstMatch
        XCTAssertTrue(panel.exists)
        let panelFrame = panel.frame
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
