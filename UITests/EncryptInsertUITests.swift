import XCTest

final class EncryptInsertUITests: XCTestCase {
    @MainActor func testSecurityProbeRequiresExplicitOptIn() {
        let app = XCUIApplication()
        app.launchArguments = ["-keystore", "memory", "-encrypt-probe"]
        app.launch()
        XCTAssertTrue(app.staticTexts["mykey.fingerprint"].waitForExistence(timeout: 15))
        XCTAssertFalse(app.staticTexts["encrypt.probeResult"].exists)
        app.terminate()

        app.launchArguments = ["-keystore", "memory", "-contacts", "memory", "-encrypt-seed"]
        app.launch()
        let result = app.staticTexts["encrypt.seedResult"]
        XCTAssertTrue(result.waitForExistence(timeout: 8))
        XCTAssertEqual(result.label, "FAIL: simulator test fixture opt-in and identity required")
    }

    @MainActor func testProductionControllerRoundTrip() {
        let app = XCUIApplication()
        app.launchArguments = ["-keystore", "memory", "-contacts", "memory", "-encrypt-probe"]
        app.launch()
        let result = app.staticTexts["encrypt.probeResult"]
        let finished = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label BEGINSWITH %@ OR label BEGINSWITH %@", "PASS:", "FAIL:"),
            object: result)
        XCTAssertEqual(XCTWaiter.wait(for: [finished], timeout: 15), .completed)
        XCTAssertEqual(
            result.label,
            "PASS: shipping controller; insertText=1; context=0; delete=0; adjust=0; sender+recipient roundtrip; third rejected"
        )
    }
}
