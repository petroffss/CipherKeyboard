import Testing
@testable import KeyboardTyping

@MainActor struct KeyboardLifecycleTests {
    @Test func stressAndReset() {
        let clock = ManualKeyboardClock(); let a = KeyboardInputAdapter(clock: clock)
        var expected = ""
        for index in 0..<500 {
            if index % 7 == 0 {
                a.activate(.delete); if !expected.isEmpty { expected.removeLast() }
            } else {
                a.activate(.character("1")); expected += "1"
            }
        }
        #expect(a.input.text == expected)
        for _ in 0..<10 {
            a.press(.delete); a.hide(); clock.advance(1)
            #expect(a.input.text.isEmpty && a.input.cursor == 0 && a.input.language == .russian && a.input.uppercase)
            #expect(a.activeTimerCount == 0 && clock.jobs.isEmpty)
            a.activate(.character("е"))
        }
        let preview = KeyboardInputAdapter(clock: clock)
        let extensionAdapter = KeyboardInputAdapter(clock: clock)
        for action in [
            KeyboardAction.character("п"), .character("р"), .enter, .language, .character("a"), .delete, .space,
        ] {
            preview.activate(action); extensionAdapter.activate(action)
        }
        #expect(preview.input.text == "Пр\n ")
        #expect(extensionAdapter.input.text == preview.input.text)
    }
}
