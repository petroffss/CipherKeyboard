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
                if state != "selection" { try TypingTestSupport.tapHostControl("Курсор", in: host) }
                XCTAssertEqual(host.textViews["host.editor"].value as? String, "До встречи!")
                let range = state == "selection" ? "3, 7" : "3, 0"
                XCTAssertTrue(host.staticTexts["host.diagnostics"].label.contains("Выделение UTF-16: " + range))
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
    /// Separate stress proof; does not add a state to the approved 126-frame matrix.
    @MainActor func testLongName40CharacterStress() throws {
        XCUIDevice.shared.orientation = .portrait
        let host = XCUIApplication(bundleIdentifier: "dev.cipherkeyboard.typinghost")
        host.launch(); TypingTestSupport.openCipher(in: host)
        try TypingTestSupport.tapHostControl("С выделением", in: host)
        try TypingTestSupport.tapHostControl("Курсор", in: host)
        TypingTestSupport.fixture("enc-long-name", in: host)
        XCTAssertEqual(host.buttons["keyboard.recipient"].label, "Кому: " + String(repeating: "Я", count: 40))
        XCTAssertEqual((TypingTestSupport.draft(in: host).value as? String)?.split(separator: "\n").count, 4)
        host.buttons["keyboard.recipient"].tap()
        let row = host.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", String(repeating: "Я", count: 40)))
            .firstMatch
        let list = host.scrollViews["keyboard.recipient.list"]
        list.swipeUp(); list.swipeUp()
        XCTAssertTrue(row.isHittable); XCTAssertTrue(row.isSelected)
        XCTAssertGreaterThanOrEqual(row.frame.height, 44)
        let proof = XCTAttachment(screenshot: host.screenshot())
        proof.name = "encrypt-40-character-name-stress-separate"; proof.lifetime = .keepAlways; add(proof)
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
        let secondary = try XCTUnwrap(rendered["statusColor"] as? [Double])
        let rgb = theme == "dark" ? [152.0, 152.0, 159.0] : [108.0, 108.0, 112.0]
        XCTAssertEqual(secondary.count, 4)
        for index in 0..<3 { XCTAssertEqual(secondary[index], rgb[index] / 255, accuracy: 0.001) }
        XCTAssertEqual(secondary[3], 1, accuracy: 0.001)
        let encryption = try XCTUnwrap(rendered["encryption"] as? [String: Any])
        let noticeColor = try XCTUnwrap(encryption["noticeColor"] as? [Double])
        let dangerStates = [
            "limit", "key-error", "contacts-error", "changed", "selection", "failure", "document-changed",
        ]
        let noticeRGB: [Double]
        if dangerStates.contains(state) {
            noticeRGB = theme == "dark" ? [255, 105, 97] : [217, 45, 32]
        } else if state == "success" {
            noticeRGB = theme == "dark" ? [91, 140, 255] : [47, 91, 234]
        } else {
            noticeRGB = rgb
        }
        for index in 0..<3 { XCTAssertEqual(noticeColor[index], noticeRGB[index] / 255, accuracy: 0.001) }
        XCTAssertEqual(noticeColor[3], 1, accuracy: 0.001)
        if state == "no-key" {
            XCTAssertEqual(host.staticTexts["keyboard.identityStatus"].label, "Личный ключ ещё не создан")
        } else if state == "key-error" {
            XCTAssertEqual(host.staticTexts["keyboard.identityStatus"].label, "Не удалось открыть хранилище ключей")
        } else if state == "no-access" {
            XCTAssertEqual(host.staticTexts["keyboard.identityStatus"].label, "Общие данные недоступны")
        }
        if state == "long-name" {
            XCTAssertEqual(
                TypingTestSupport.draft(in: host).value as? String,
                "Привет!\nВстречаемся завтра.\nВозьми документы.\nОбсудим детали при встрече.")
            if !landscape { XCTAssertEqual(TypingTestSupport.draft(in: host).frame.height, 100, accuracy: 2) }
        }
        if state == "limit" {
            let actual = try XCTUnwrap(TypingTestSupport.draft(in: host).value as? String)
            XCTAssertEqual(actual.utf8.count, 4097)
            XCTAssertTrue(
                actual.hasPrefix("Синтетический черновик: 4097 байт…\n(полный текст — в тестовой зависимости)\n"))
            XCTAssertEqual(rendered["byteCount"] as? Int, 4097)
            XCTAssertLessThanOrEqual(
                try XCTUnwrap(rendered["counterMaxY"] as? Double),
                try XCTUnwrap(encryption["noticeMinY"] as? Double))
        }
        if state == "selection" {
            XCTAssertEqual(field.value as? String, "До встречи!")
            XCTAssertTrue(host.staticTexts["host.diagnostics"].label.contains("Выделение UTF-16: 3, 7"))
        }
        if state == "contacts-error" {
            XCTAssertNotEqual(host.buttons["keyboard.recipient"].label, "Кому: выберите контакт")
            XCTAssertTrue(host.buttons["keyboard.contacts.retry"].isHittable)
            XCTAssertEqual(TypingTestSupport.draft(in: host).frame.height, 40, accuracy: 0.5)
        }
        if state == "picker" {
            XCTAssertEqual(encryption["pickerTitle"] as? String, "Кому зашифровать")
            let rows = try XCTUnwrap(encryption["pickerRows"] as? [[String: Any]])
            XCTAssertFalse(rows.isEmpty)
            for row in rows {
                XCTAssertEqual(try XCTUnwrap(row["nameMinX"] as? Double), 12, accuracy: 0.5)
                XCTAssertEqual(try XCTUnwrap(row["fingerprintMinX"] as? Double), 12, accuracy: 0.5)
                XCTAssertEqual(try XCTUnwrap(row["separatorHeight"] as? Double), 1, accuracy: 0.5)
                XCTAssertGreaterThanOrEqual(try XCTUnwrap(row["height"] as? Double), 44)
                if row["selected"] as? Bool == true {
                    XCTAssertEqual(
                        try XCTUnwrap(row["checkMaxX"] as? Double),
                        try XCTUnwrap(row["width"] as? Double) - 12, accuracy: 0.5)
                }
            }
        }
        if landscape && state != "picker" {
            let editor = TypingTestSupport.draft(in: host).frame
            XCTAssertEqual(editor.minX - panel.minX, 44, accuracy: 0.5)
            let available = panel.width - 88
            let expectedWidth = available - max(352, (available - 12) / 1.75) - 12
            XCTAssertEqual(editor.width, expectedWidth, accuracy: 0.5)
        }
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
