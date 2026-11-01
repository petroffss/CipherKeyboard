import XCTest

extension XCUIApplication {
    /// SwiftUI may replace UITabBarItem after the identifier bridge runs. Match the actual visible
    /// tab by its exact Russian label in that case; never fall back from an existing but unusable ID.
    @MainActor
    func navigationTab(_ identifier: String, file: StaticString = #filePath, line: UInt = #line) -> XCUIElement {
        let labels = [
            "tab.myKey": "Мой ключ", "tab.contacts": "Контакты", "tab.decrypt": "Расшифровать",
            "tab.setup": "Настройка",
        ]
        let identified = tabBars.buttons.matching(identifier: identifier)
        if identified.count > 0 {
            XCTAssertEqual(identified.count, 1, identifier, file: file, line: line)
            XCTAssertTrue(identified.firstMatch.isHittable, identifier, file: file, line: line)
            return identified.firstMatch
        }
        let label = labels[identifier] ?? identifier
        let visible = tabBars.buttons.matching(NSPredicate(format: "label == %@", label))
        XCTAssertTrue(visible.firstMatch.waitForExistence(timeout: 5), label, file: file, line: line)
        XCTAssertEqual(visible.count, 1, label, file: file, line: line)
        XCTAssertTrue(visible.firstMatch.isHittable, label, file: file, line: line)
        let diagnostic = XCTAttachment(string: "Tab identifier missing: \(identifier); exact visible label: \(label)")
        diagnostic.name = "Tab identifier diagnostic"
        diagnostic.lifetime = .keepAlways
        XCTContext.runActivity(named: "Tab navigation fallback") { $0.add(diagnostic) }
        return visible.firstMatch
    }
}
