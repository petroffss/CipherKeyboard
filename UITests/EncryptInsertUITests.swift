import XCTest

final class EncryptInsertUITests: XCTestCase {
    @MainActor func testProductionControllerRoundTrip() {
        let app = XCUIApplication()
        app.launchArguments = []; app.launch()
        XCTAssertTrue(app.staticTexts["mykey.fingerprint"].waitForExistence(timeout: 15))
        app.terminate()
        app.launchArguments = ["-encrypt-probe"]; app.launch()
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
