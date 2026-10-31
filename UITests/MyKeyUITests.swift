import CoreImage
import CryptoKit
import UIKit
import XCTest

/// Экран «Мой ключ»: создание личности, отпечаток, QR, копирование и ошибка хранилища (фича 02-my-key).
final class MyKeyUITests: XCTestCase {
    private let fingerprintPattern = "^([0-9A-F]{4} ){7}[0-9A-F]{4}$"
    private let publicKeyPattern = "^ckpub1:[A-Za-z0-9_-]{86}$"

    override func setUp() {
        continueAfterFailure = false
    }

    // MARK: - E8

    @MainActor
    func testFirstLaunchShowsMyKey() throws {
        let app = launch(["-keystore", "memory"])

        let title = app.staticTexts["mykey.title"]
        XCTAssertTrue(title.waitForExistence(timeout: 10))
        XCTAssertEqual(title.label, "Мой ключ")

        // Вкладки: подписи, порядок слева направо, выбрана «Мой ключ».
        let tabIDs = ["tab.myKey", "tab.contacts", "tab.decrypt", "tab.setup"]
        let tabLabels = ["Мой ключ", "Контакты", "Расшифровать", "Настройка"]
        let tabs = tabIDs.map { app.tabBars.buttons[$0] }
        for (tab, label) in zip(tabs, tabLabels) {
            XCTAssertTrue(tab.waitForExistence(timeout: 5), "нет вкладки \(label)")
            XCTAssertEqual(tab.label, label)
        }
        for index in 1..<tabs.count {
            XCTAssertLessThan(tabs[index - 1].frame.minX, tabs[index].frame.minX)
        }
        XCTAssertTrue(tabs[0].isSelected)

        // QR не меньше 220 × 220 pt.
        let qr = app.descendants(matching: .any)["mykey.qr"]
        XCTAssertTrue(qr.exists)
        XCTAssertGreaterThanOrEqual(qr.frame.width, 220)
        XCTAssertGreaterThanOrEqual(qr.frame.height, 220)

        // Строка ключа и отпечаток, посчитанный в тесте независимо от приложения.
        let publicKey = app.staticTexts["mykey.publicKey"].label
        XCTAssertNotNil(publicKey.range(of: publicKeyPattern, options: .regularExpression), publicKey)
        let fingerprint = app.staticTexts["mykey.fingerprint"].label
        XCTAssertNotNil(fingerprint.range(of: fingerprintPattern, options: .regularExpression), fingerprint)
        XCTAssertEqual(fingerprint, try expectedFingerprint(of: publicKey))

        let copy = app.buttons["mykey.copy"]
        XCTAssertTrue(copy.exists)
        XCTAssertTrue(copy.isEnabled)
        XCTAssertEqual(copy.label, "Скопировать ключ")
        let share = app.buttons["mykey.share"]
        XCTAssertTrue(share.exists)
        XCTAssertTrue(share.isEnabled)
        XCTAssertEqual(share.label, "Поделиться")

        XCTAssertTrue(app.staticTexts["Приватный ключ хранится только на этом iPhone"].exists)

        // Нет экспорта, показа, пересоздания или удаления приватного ключа.
        let forbidden = ["приват", "экспорт", "пересоздать", "удалить", "новый ключ"]
        for button in app.buttons.allElementsBoundByIndex {
            let label = button.label.lowercased()
            for word in forbidden {
                XCTAssertFalse(label.contains(word), "кнопка «\(button.label)» содержит «\(word)»")
            }
        }

        tabs[1].tap()
        XCTAssertTrue(app.staticTexts["Появится в следующей версии"].waitForExistence(timeout: 5))
    }

    // MARK: - E9

    @MainActor
    func testFingerprintSurvivesRelaunch() {
        // Настоящий Keychain симулятора — без аргументов хранилища.
        let app = XCUIApplication()
        app.launch()
        let first = readKey(app)
        app.terminate()

        app.launch()
        let second = readKey(app)

        XCTAssertNotNil(first.fingerprint.range(of: fingerprintPattern, options: .regularExpression))
        XCTAssertNotNil(second.fingerprint.range(of: fingerprintPattern, options: .regularExpression))
        XCTAssertEqual(first.fingerprint, second.fingerprint)
        XCTAssertEqual(first.publicKey, second.publicKey)
    }

    @MainActor
    func testMemoryStoreStartsEmpty() {
        let app = launch(["-keystore", "memory"])
        let first = readKey(app)
        app.terminate()

        app.launch()
        let second = readKey(app)

        XCTAssertNotNil(first.fingerprint.range(of: fingerprintPattern, options: .regularExpression))
        XCTAssertNotNil(second.fingerprint.range(of: fingerprintPattern, options: .regularExpression))
        XCTAssertNotEqual(first.fingerprint, second.fingerprint)
    }

    // MARK: - E10

    @MainActor
    func testQRCodeEncodesPublicKey() throws {
        let app = launch(["-keystore", "memory"])
        let key = readKey(app).publicKey

        let qr = app.descendants(matching: .any)["mykey.qr"]
        let image = try XCTUnwrap(CIImage(image: qr.screenshot().image))
        let detector = try XCTUnwrap(
            CIDetector(
                ofType: CIDetectorTypeQRCode, context: nil, options: [CIDetectorAccuracy: CIDetectorAccuracyHigh]))
        let codes = detector.features(in: image).compactMap { $0 as? CIQRCodeFeature }

        XCTAssertEqual(codes.count, 1)
        let message = try XCTUnwrap(codes.first?.messageString)
        XCTAssertEqual(message, key)
        XCTAssertEqual(message.count, 93)
        XCTAssertTrue(message.hasPrefix("ckpub1:"))
        XCTAssertNil(message.rangeOfCharacter(from: .whitespacesAndNewlines))
    }

    // MARK: - E12

    @MainActor
    func testDoubleCopyShowsSingleToast() {
        let app = launch(["-keystore", "memory"])
        _ = readKey(app)
        let copy = app.buttons["mykey.copy"]
        let toasts = app.descendants(matching: .any).matching(identifier: "mykey.copiedToast")
        let toast = toasts.firstMatch

        let start = Date()
        copy.tap()
        XCTAssertTrue(toast.waitForExistence(timeout: 1))
        XCTAssertTrue(toast.label.contains("Ключ скопирован"), toast.label)

        wait(until: start.addingTimeInterval(1.0))
        copy.tap()
        XCTAssertEqual(toasts.count, 1)

        wait(until: start.addingTimeInterval(2.4))
        XCTAssertTrue(toast.exists, "плашка должна быть видна 2 секунды после последнего нажатия")

        wait(until: start.addingTimeInterval(4.5))
        XCTAssertFalse(toast.exists, "плашка должна исчезнуть")
    }

    // MARK: - E14

    @MainActor
    func testKeystoreErrorShowsRetry() {
        let app = launch(["-keystore", "memory", "-keystore-fault", "read"])

        let error = app.descendants(matching: .any)["mykey.error"]
        XCTAssertTrue(error.waitForExistence(timeout: 10))
        XCTAssertTrue(error.label.contains("Не удалось открыть хранилище ключей"), error.label)
        XCTAssertTrue(
            error.label.contains("Разблокируйте iPhone и попробуйте ещё раз. Ваш ключ не удалён."), error.label)

        let retry = app.buttons["mykey.retry"]
        XCTAssertTrue(retry.exists)
        XCTAssertEqual(retry.label, "Повторить")

        XCTAssertFalse(app.descendants(matching: .any)["mykey.qr"].exists)
        XCTAssertFalse(app.staticTexts["mykey.fingerprint"].exists)
        XCTAssertFalse(app.staticTexts["mykey.publicKey"].exists)
        XCTAssertFalse(app.buttons["mykey.copy"].exists)

        retry.tap()
        let title = app.staticTexts["mykey.title"]
        XCTAssertTrue(title.waitForExistence(timeout: 10))
        XCTAssertEqual(title.label, "Мой ключ")
        let fingerprint = app.staticTexts["mykey.fingerprint"].label
        XCTAssertNotNil(fingerprint.range(of: fingerprintPattern, options: .regularExpression), fingerprint)
    }

    // MARK: - Помощники

    @MainActor
    private func launch(_ arguments: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = arguments
        app.launch()
        return app
    }

    @MainActor
    private func readKey(_ app: XCUIApplication) -> (fingerprint: String, publicKey: String) {
        XCTAssertTrue(app.staticTexts["mykey.title"].waitForExistence(timeout: 10))
        return (app.staticTexts["mykey.fingerprint"].label, app.staticTexts["mykey.publicKey"].label)
    }

    private func wait(until date: Date) {
        let interval = date.timeIntervalSinceNow
        if interval > 0 { Thread.sleep(forTimeInterval: interval) }
    }

    /// Отпечаток независимо от приложения: base64url → 64 байта → SHA-256 → первые 16 байт → HEX группами по 4.
    private func expectedFingerprint(of publicKey: String) throws -> String {
        var base64 = String(publicKey.dropFirst("ckpub1:".count))
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while base64.count % 4 != 0 { base64 += "=" }
        let raw = try XCTUnwrap(Data(base64Encoded: base64))
        XCTAssertEqual(raw.count, 64)
        let hex = SHA256.hash(data: raw).prefix(16).map { String(format: "%02X", $0) }.joined()
        var groups: [String] = []
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 4)
            groups.append(String(hex[index..<next]))
            index = next
        }
        return groups.joined(separator: " ")
    }
}
