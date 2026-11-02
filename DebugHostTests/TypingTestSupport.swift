import XCTest
import Foundation

@MainActor enum TypingTestSupport {
    static func configureKeyboard(fullAccess: Bool) throws {
        let settings = XCUIApplication(bundleIdentifier: "com.apple.Preferences")
        settings.launch()
        let general = settings.buttons["com.apple.settings.general"]
        for _ in 0..<8 {
            if general.exists { break }
            let back = settings.navigationBars.buttons.element(boundBy: 0)
            if back.exists { back.tap() } else { break }
        }
        XCTAssertTrue(general.waitForExistence(timeout: 5), settings.debugDescription)
        navigateSettings(
            settings, row: general, destination: settings.buttons["com.apple.settings.general.keyboard"])
        navigateSettings(
            settings, row: settings.buttons["com.apple.settings.general.keyboard"],
            destination: settings.buttons["KEYBOARDS"])
        settings.buttons["KEYBOARDS"].tap()
        var cipher = settings.descendants(matching: .any).matching(
            NSPredicate(format: "label BEGINSWITH %@", "CipherKeyboard")
        ).firstMatch
        if !cipher.waitForExistence(timeout: 2) {
            settings.buttons["AddNewKeyboard"].tap()
            settings.staticTexts["CipherKeyboard"].tap()
            cipher =
                settings.descendants(matching: .any).matching(
                    NSPredicate(format: "label BEGINSWITH %@", "CipherKeyboard")
                ).firstMatch
        }
        XCTAssertTrue(cipher.waitForExistence(timeout: 5), settings.debugDescription)
        cipher.tap()
        let row = settings.switches.matching(
            NSPredicate(format: "label CONTAINS[c] %@ OR label CONTAINS[c] %@", "доступ", "access")
        ).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5), settings.debugDescription)
        let nested = row.switches.firstMatch
        let toggle = nested.exists ? nested : row
        XCTAssertTrue(
            row.label.localizedCaseInsensitiveContains("доступ")
                || row.label.localizedCaseInsensitiveContains("access"))
        let wanted = fullAccess ? "1" : "0"
        if toggle.value as? String != wanted {
            if nested.exists {
                toggle.tap()
            } else {
                toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
            }
            let allow = settings.alerts.buttons.matching(
                NSPredicate(format: "label == %@ OR label == %@", "Разрешить", "Allow")
            ).firstMatch
            if allow.waitForExistence(timeout: 2) { allow.tap() }
        }
        let changed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", wanted), object: toggle)
        XCTAssertEqual(XCTWaiter.wait(for: [changed], timeout: 5), .completed)
        XCTContext.runActivity(named: "Actual Full Access \(fullAccess ? "ON" : "OFF")") { activity in
            let screenshot = XCTAttachment(screenshot: settings.screenshot())
            screenshot.name = "settings-full-access-\(wanted)"
            screenshot.lifetime = .keepAlways
            activity.add(screenshot)
        }
    }

    /// Settings' SwiftUI rows can report Button in modern AX and Other in legacy AX.
    /// A coordinate tap on the visible row avoids a silent AX activation no-op.
    /// Arrival at the actual next screen remains mandatory; do not continue on a stale hierarchy.
    private static func navigateSettings(_ app: XCUIApplication, row: XCUIElement, destination: XCUIElement) {
        for _ in 0..<2 {
            if destination.exists && !row.exists { return }
            XCTAssertTrue(row.waitForExistence(timeout: 5), app.debugDescription)
            for _ in 0..<4 {
                let visible = app.frame.insetBy(dx: 8, dy: 80)
                if row.isHittable && visible.contains(CGPoint(x: row.frame.midX, y: row.frame.midY)) { break }
                app.swipeUp()
            }
            XCTAssertTrue(row.isHittable, app.debugDescription)
            row.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
            if destination.waitForExistence(timeout: 3) { return }
        }
        XCTAssertTrue(
            destination.exists, "Settings row did not navigate to its required destination: " + app.debugDescription)
    }

    static func openCipher(in host: XCUIApplication) {
        host.buttons["Открыть"].tap()
        let introduction = host.buttons["Continue"]
        if introduction.waitForExistence(timeout: 1) { introduction.tap() }
        let editor = host.descendants(matching: .any)["keyboard.editor"].firstMatch
        if editor.waitForExistence(timeout: 2) { verifyBuild(in: host); return }
        for attempt in 0..<2 {
            let globe = host.buttons.matching(
                NSPredicate(format: "label == %@ OR label == %@", "Next keyboard", "Следующая клавиатура")
            ).firstMatch
            XCTAssertTrue(globe.waitForExistence(timeout: 5), host.debugDescription)
            globe.press(forDuration: 0.8)
            let choice = host.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "CipherKeyboard"))
                .firstMatch
            XCTAssertTrue(choice.waitForExistence(timeout: 5), host.debugDescription)
            choice.tap()
            if editor.waitForExistence(timeout: 5) { break }
            let blankInputView = host.otherElements["inputView"].exists && host.keyboards.keys.count == 0
            guard attempt == 0, blankInputView else { break }
            if blankInputView {
                XCTContext.runActivity(named: "Keyboard activation after Settings change required reopen") { activity in
                    let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
                    screenshot.lifetime = .keepAlways; activity.add(screenshot)
                    let hierarchy = XCTAttachment(string: host.debugDescription)
                    hierarchy.lifetime = .keepAlways; activity.add(hierarchy)
                }
                host.buttons["Скрыть"].tap()
                XCTAssertTrue(editor.waitForNonExistence(timeout: 3))
                host.buttons["Открыть"].tap()
                if editor.waitForExistence(timeout: 3) { break }
            }
        }
        XCTAssertTrue(editor.exists, host.debugDescription)
        verifyBuild(in: host)
    }

    static func fixture(_ name: String, in app: XCUIApplication) {
        app.buttons["keyboard.debugFixtures"].tap()
        let grid = app.otherElements["keyboard.fixtureGrid"]
        XCTAssertTrue(grid.waitForExistence(timeout: 3), app.debugDescription)
        let item = app.buttons["keyboard.fixture." + name]
        XCTAssertTrue(item.exists && item.isHittable, app.debugDescription)
        item.tap()
        XCTAssertTrue(grid.waitForNonExistence(timeout: 3), "Fixture picker must disappear before capture")
        let status = app.buttons["keyboard.debugFixtures"]
        let received = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label CONTAINS %@", "fixture=" + name), object: status)
        XCTAssertEqual(XCTWaiter.wait(for: [received], timeout: 5), .completed)
    }
    static func waitLayout(in host: XCUIApplication, width: CGFloat) {
        let settled = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label BEGINSWITH %@", "width=\(width);"),
            object: host.staticTexts["host.controlsGeometry"])
        XCTAssertEqual(XCTWaiter.wait(for: [settled], timeout: 5), .completed)
    }
    static func draft(in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)["keyboard.editor"].firstMatch
    }
    static func assertReset(in app: XCUIApplication) {
        let editor = draft(in: app)
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        XCTAssertEqual(editor.value as? String, "")
        XCTAssertEqual(app.buttons["keyboard.language"].label, "Сменить язык")
        XCTAssertTrue(app.buttons["keyboard.key.й"].exists)
        XCTAssertEqual(app.buttons["keyboard.shift"].value as? String, "Заглавные")
    }
    static func sequence(in app: XCUIApplication) {
        for key in ["п", "р", "и", "в", "е", "т"] { app.buttons["keyboard.key." + key].tap() }
        app.buttons["keyboard.delete"].tap()
        app.buttons["keyboard.return"].tap()
        app.buttons["keyboard.numbers"].tap()
        app.buttons["keyboard.key.1"].tap()
        app.buttons["keyboard.symbols"].tap()
        app.buttons["keyboard.key.#"].tap()
        app.buttons["keyboard.numbers"].tap()
        app.buttons["keyboard.key.е"].press(forDuration: 0.55)
        app.buttons["keyboard.key.ь"].press(forDuration: 0.55)
        app.buttons["keyboard.language"].tap()
        app.buttons["keyboard.key.q"].tap()
        app.buttons["keyboard.space"].tap()
        app.buttons["keyboard.return"].tap()
        XCTAssertEqual(draft(in: app).value as? String, "Приве\n1#ёъq \n")
    }
    static func openPreview(_ app: XCUIApplication) {
        app.launch()
        XCTAssertTrue(app.staticTexts["mykey.title"].waitForExistence(timeout: 10))
        app.tabBars.buttons["Настройка"].tap()
        app.scrollViews["setup.scroll"].swipeUp()
        app.buttons["setup.tryKeyboard"].tap()
        XCTAssertTrue(draft(in: app).waitForExistence(timeout: 5))
    }

    private final class BuildIdentity: NSObject {}
    static func verifyBuild(in host: XCUIApplication) {
        let expected = Bundle(for: BuildIdentity.self).object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
        XCTAssertFalse(
            expected.isEmpty || expected == "1", "Use scripts/typing-integration.sh to set the source revision")
        let actual = host.buttons["keyboard.debugFixtures"].label
        XCTAssertTrue(actual.contains("build=" + expected + ";"), "Expected source build \(expected), actual \(actual)")
    }

    static func tapHostControl(_ name: String, in host: XCUIApplication) throws {
        let geometryElement = host.staticTexts["host.controlsGeometry"]
        let dimensions = host.frame.size
        let width =
            XCUIDevice.shared.orientation.isLandscape
            ? max(dimensions.width, dimensions.height) : min(dimensions.width, dimensions.height)
        let expectedWidth = "width=\(width);"
        let settled = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label BEGINSWITH %@", expectedWidth), object: geometryElement)
        XCTAssertEqual(XCTWaiter.wait(for: [settled], timeout: 5), .completed)
        let geometry = geometryElement.label
        let entry = try XCTUnwrap(geometry.split(separator: ";").first { $0.hasPrefix(name + "=") })
        let point = entry.dropFirst(name.count + 1).split(separator: ",").compactMap { Double($0) }
        XCTAssertEqual(point.count, 2)
        guard point.count == 2 else { return }
        host.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: point[0], dy: point[1])).tap()
    }
}
