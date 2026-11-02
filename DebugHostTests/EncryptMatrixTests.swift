import UIKit
import XCTest

/// 17 portrait states and 4 landscape states per theme/profile: 126 native extension frames.
final class EncryptMatrixTests: XCTestCase {
    override func setUp() { continueAfterFailure = false }
    private let states = [
        "unselected", "empty", "ready", "picker", "no-contacts", "sending", "success", "limit", "no-key", "key-error",
        "contacts-error", "no-access", "changed", "selection", "failure", "document-changed", "long-name",
    ]
    @MainActor func testCaptureLightCurrentProfile() throws { try capture(theme: "light") }
    @MainActor func testCaptureDarkCurrentProfile() throws { try capture(theme: "dark") }
    @MainActor private func capture(theme: String) throws {
        XCUIDevice.shared.orientation = .portrait
        let host = XCUIApplication(bundleIdentifier: "dev.cipherkeyboard.typinghost")
        host.launchArguments = ["-typing-theme", theme]; host.launch()
        TypingTestSupport.openCipher(in: host)
        let width = host.frame.width, height = host.frame.height
        XCTAssertEqual(height, [375.0: 667.0, 402.0: 874.0, 440.0: 956.0][width])
        for landscape in [false, true] {
            XCUIDevice.shared.orientation = landscape ? .landscapeLeft : .portrait
            TypingTestSupport.waitLayout(in: host, width: landscape ? height : width)
            for state in landscape ? ["ready", "picker", "limit", "long-name"] : states {
                try TypingTestSupport.tapHostControl("С выделением", in: host)
                try TypingTestSupport.tapHostControl("Курсор", in: host)
                TypingTestSupport.fixture("enc-" + state, in: host)
                if ["success", "failure", "document-changed"].contains(state) {
                    let idle = XCTNSPredicateExpectation(
                        predicate: NSPredicate(format: "label != %@", "Шифруем…"),
                        object: host.staticTexts["keyboard.encrypt.status"])
                    XCTAssertEqual(XCTWaiter.wait(for: [idle], timeout: 5), .completed)
                }
                try frame(host, width: width, landscape: landscape, theme: theme, state: state)
            }
        }
        // Keep the last landscape frame stable until XCTest has finalized its attachments.
    }
    @MainActor private func frame(
        _ host: XCUIApplication, width: CGFloat, landscape: Bool, theme: String, state: String
    ) throws {
        TypingTestSupport.verifyBuild(in: host)
        XCTAssertFalse(host.otherElements["keyboard.fixtureGrid"].exists)
        let panel = host.descendants(matching: .any)["keyboard.panel"].firstMatch.frame
        XCTAssertLessThanOrEqual(panel.height, landscape ? 240 : 420)
        let field = host.textViews["host.editor"]
        XCTAssertTrue(field.isHittable); XCTAssertGreaterThanOrEqual(field.frame.height, 48)
        XCTAssertLessThanOrEqual(field.frame.maxY, panel.minY + 0.5)
        let parsed = try XCTUnwrap((host.buttons["keyboard.debugFixtures"].value as? String)?.data(using: .utf8))
        let rendered = try XCTUnwrap(JSONSerialization.jsonObject(with: parsed) as? [String: Any])
        XCTAssertEqual(rendered["resolvedTheme"] as? String, theme)
        let buttons = host.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "keyboard."))
            .allElementsBoundByIndex
        var keys: [[String: Any]] = []
        for button in buttons where button.identifier != "keyboard.debugFixtures" && button.isHittable {
            let rect = button.frame
            let letter = button.identifier.hasPrefix("keyboard.key.")
            XCTAssertGreaterThanOrEqual(
                rect.height,
                letter
                    || [
                        "keyboard.return", "keyboard.space", "keyboard.shift", "keyboard.delete", "keyboard.language",
                        "keyboard.numbers", "keyboard.next",
                    ].contains(button.identifier) ? (landscape ? 32 : 44) : 44)
            if letter { XCTAssertGreaterThanOrEqual(rect.width, 26) }
            if button.identifier.hasPrefix("keyboard.recipient.") && button.identifier != "keyboard.recipient.back" {
                XCTAssertGreaterThanOrEqual(rect.width, 44)
                XCTAssertFalse(panel.intersection(rect).isEmpty)
            } else {
                XCTAssertTrue(panel.insetBy(dx: -0.5, dy: -0.5).contains(rect))
            }
            keys.append(["id": button.identifier, "label": button.label, "rect": rectangle(rect)])
        }
        if state == "picker" {
            XCTAssertTrue(host.scrollViews["keyboard.recipient.list"].exists)
            XCTAssertTrue(host.buttons["keyboard.recipient.back"].isHittable)
        } else {
            for name in ["delete", "language", "numbers", "space", "return", "recipient", "encrypt"] {
                XCTAssertTrue(host.buttons["keyboard." + name].exists)
            }
        }
        let orientation = landscape ? "landscape" : "portrait"
        let name = "encrypt-frame--extension--\(Int(width))--\(orientation)--\(theme)--\(state)"
        let screenshotData = XCUIScreen.main.screenshot().pngRepresentation
        let screenshot = XCTAttachment(data: screenshotData, uniformTypeIdentifier: "public.png");
        screenshot.name = name;
        screenshot.lifetime = .keepAlways; add(screenshot)
        let geometry: [String: Any] = [
            "kind": "extension", "width": Int(width), "orientation": orientation, "theme": theme, "state": state,
            "panel": rectangle(panel),
            "editor": state == "picker" ? [:] : rectangle(TypingTestSupport.draft(in: host).frame), "keys": keys,
            "scale": UIScreen.main.scale, "rendered": rendered,
            "build": host.buttons["keyboard.debugFixtures"].label,
            "hostField": [
                "frame": rectangle(field.frame), "visibleIntersection": rectangle(field.frame),
                "hittable": field.isHittable,
            ],
            "status": state == "picker" ? "" : host.staticTexts["keyboard.encrypt.status"].label,
        ]
        let data = try JSONSerialization.data(withJSONObject: geometry, options: [.prettyPrinted, .sortedKeys])
        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
        attachment.name = name.replacingOccurrences(of: "-frame--", with: "-geometry--")
        attachment.lifetime = .keepAlways; add(attachment)
    }
    private func rectangle(_ rect: CGRect) -> [String: Double] {
        ["x": rect.minX, "y": rect.minY, "width": rect.width, "height": rect.height]
    }
}
