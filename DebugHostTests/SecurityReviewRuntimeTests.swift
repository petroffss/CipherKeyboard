import XCTest

final class SecurityReviewRuntimeTests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    @MainActor func testUnknownFingerprintAndLongMessageWarning() throws {
        XCUIDevice.shared.orientation = .portrait
        defer { XCUIDevice.shared.orientation = .portrait }
        try TypingTestSupport.configureKeyboard(fullAccess: true)
        let host = XCUIApplication(bundleIdentifier: "dev.cipherkeyboard.typinghost")
        host.launch(); TypingTestSupport.openCipher(in: host)
        let portraitWidth = host.frame.width, landscapeWidth = host.frame.height
        for orientation in [UIDeviceOrientation.portrait, .landscapeLeft] {
            XCUIDevice.shared.orientation = orientation
            TypingTestSupport.waitLayout(
                in: host, width: orientation == .portrait ? portraitWidth : landscapeWidth)
            TypingTestSupport.fixture("dec-unknown", in: host)
            let sender = host.staticTexts["keyboard.decrypt.sender"]
            XCTAssertTrue(sender.waitForExistence(timeout: 5))
            let fingerprint = String(sender.label.dropFirst("От неизвестного ключа ".count))
            XCTAssertEqual(fingerprint.count, 39)
            XCTAssertEqual(fingerprint.split(separator: " ").count, 8)
            XCTAssertTrue(host.buttons["keyboard.decrypt.close"].isHittable)
            capture(host, "unknown-\(orientation.rawValue)")
            host.buttons["keyboard.decrypt.close"].tap()
            TypingTestSupport.fixture("enc-ready", in: host)
            TypingTestSupport.fixture("enc-bytes4096", in: host)
            let notice = host.staticTexts["keyboard.encrypt.status"]
            XCTAssertTrue(notice.waitForExistence(timeout: 5))
            XCTAssertEqual(notice.label, "Для Telegram сократите до 2720 байт")
            XCTAssertEqual(host.staticTexts["keyboard.counter"].label, "4096 / 4096 байт")
            XCTAssertTrue(host.buttons["keyboard.encrypt"].isEnabled)
            capture(host, "warning-\(orientation.rawValue)")
        }
    }

    @MainActor private func capture(_ host: XCUIApplication, _ name: String) {
        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "security-review-" + name; screenshot.lifetime = .keepAlways; add(screenshot)
    }
}
