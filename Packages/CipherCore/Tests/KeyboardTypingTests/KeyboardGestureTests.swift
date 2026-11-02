import Foundation
import Testing
@testable import KeyboardTyping

@MainActor final class ManualKeyboardClock: KeyboardClock {
    var now: TimeInterval = 0
    var jobs: [UUID: (TimeInterval, @MainActor () -> Void)] = [:]
    func schedule(after delay: TimeInterval, _ action: @escaping @MainActor () -> Void) -> UUID {
        let id = UUID(); jobs[id] = (now + delay, action); return id
    }
    func cancel(_ token: UUID) { jobs[token] = nil }
    func advance(_ amount: TimeInterval) {
        let end = now + amount
        while let next = jobs.min(by: { $0.value.0 < $1.value.0 }), next.value.0 <= end + 0.00000001 {
            now = next.value.0; jobs[next.key] = nil; next.value.1()
        }
        now = end
    }
}
@MainActor struct KeyboardGestureTests {
    @Test func alternateTimingAndCancellation() {
        for base in ["е", "ь"] {
            for uppercase in [true, false] {
                for duration in [0.449, 0.450] {
                    let clock = ManualKeyboardClock(); let a = KeyboardInputAdapter(clock: clock)
                    if !uppercase { a.activate(.shift) }
                    let token = a.press(.character(base)); clock.advance(duration)
                    let alternate = base == "е" ? "ё" : "ъ"
                    #expect(a.alternative == (duration < 0.450 ? nil : alternate))
                    a.release(token, inside: true)
                    let expected = duration < 0.450 ? base : alternate
                    #expect(a.input.text == (uppercase ? expected.uppercased() : expected))
                    #expect(clock.jobs.isEmpty)
                }
            }
            for cancellation in 0..<4 {
                let clock = ManualKeyboardClock(); let a = KeyboardInputAdapter(clock: clock)
                let token = a.press(.character(base)); clock.advance(0.450)
                switch cancellation {
                case 0: a.release(token, inside: false);
                case 1: a.hide();
                case 2: a.rotate();
                default: a.cancelGesture()
                }
                clock.advance(1); a.release(token, inside: true)
                #expect(a.input.text.isEmpty && clock.jobs.isEmpty && a.activeTimerCount == 0)
            }
        }
    }
    @Test func repeatStops() {
        for duration in [0.399, 0.400, 0.480] {
            for cancellation in 0..<3 {
                let clock = ManualKeyboardClock(); let a = KeyboardInputAdapter(clock: clock)
                a.seedForTesting("abcdefghij"); let token = a.press(.delete); clock.advance(duration)
                let deleted = duration < 0.400 ? 1 : (duration < 0.480 ? 2 : 3)
                #expect(a.input.text == String("abcdefghij".dropLast(deleted)))
                switch cancellation {
                case 0: a.release(token, inside: true);
                case 1: a.cancelGesture();
                default: a.hide()
                }
                let before = a.input.text; clock.advance(1)
                #expect(a.input.text == before && clock.jobs.isEmpty)
            }
        }
        let clock = ManualKeyboardClock(); let a = KeyboardInputAdapter(clock: clock)
        let token = a.press(.character("a")); clock.advance(10); #expect(a.input.text.isEmpty)
        a.release(token, inside: true); #expect(a.input.text == "A")
    }
}

extension KeyboardGestureTests {
    @Test func overlappingLettersCommitEveryValidReleaseInReleaseOrder() {
        for reverse in [false, true] {
            let adapter = KeyboardInputAdapter(clock: ManualKeyboardClock())
            let first = adapter.press(.character("п"))
            let second = adapter.press(.character("р"))
            #expect(adapter.input.text.isEmpty)
            adapter.release(reverse ? second : first, inside: true)
            #expect(adapter.input.text == (reverse ? "Р" : "П"))
            adapter.release(reverse ? first : second, inside: true)
            #expect(adapter.input.text == (reverse ? "Рп" : "Пр"))
            adapter.release(first, inside: true); adapter.release(second, inside: true)
            #expect(adapter.input.text == (reverse ? "Рп" : "Пр"))
        }
    }
    @Test func cancelledTouchDoesNotDiscardAnotherValidTouch() {
        for cancelFirst in [false, true] {
            let adapter = KeyboardInputAdapter(clock: ManualKeyboardClock())
            let first = adapter.press(.character("п"))
            let second = adapter.press(.character("р"))
            adapter.cancelGesture(cancelFirst ? first : second)
            adapter.release(first, inside: true); adapter.release(second, inside: true)
            #expect(adapter.input.text == (cancelFirst ? "Р" : "П"))
        }
    }
    @Test func overlappingAlternatesKeepIndependentDeadlinesAndCancellation() {
        let clock = ManualKeyboardClock(); let adapter = KeyboardInputAdapter(clock: clock)
        let first = adapter.press(.character("е")); clock.advance(0.2)
        let second = adapter.press(.character("ь")); clock.advance(0.25)
        #expect(adapter.alternative == "ё" && adapter.activeTimerCount == 1)
        adapter.release(first, inside: true)
        #expect(adapter.input.text == "Ё" && adapter.alternative == nil)
        clock.advance(0.2)
        #expect(adapter.alternative == "ъ")
        adapter.release(second, inside: true)
        #expect(adapter.input.text == "Ёъ" && clock.jobs.isEmpty)
        let cancelled = adapter.press(.character("е"))
        let surviving = adapter.press(.character("ь"))
        adapter.cancelGesture(cancelled); clock.advance(0.45)
        adapter.release(surviving, inside: true)
        #expect(adapter.input.text == "Ёъъ" && clock.jobs.isEmpty)
    }
    @Test func overlappingDeleteDoesNotOwnAnotherKeysRelease() {
        let clock = ManualKeyboardClock(); let adapter = KeyboardInputAdapter(clock: clock)
        adapter.seedForTesting("abcdef")
        let deletion = adapter.press(.delete)
        let letter = adapter.press(.character("р"))
        adapter.release(letter, inside: true)
        #expect(adapter.input.text == "abcdeр")
        clock.advance(0.4)
        #expect(adapter.input.text == "abcde")
        adapter.release(deletion, inside: true); clock.advance(1)
        #expect(adapter.input.text == "abcde" && clock.jobs.isEmpty)
        _ = adapter.press(.delete); _ = adapter.press(.character("е")); _ = adapter.press(.character("ь"))
        #expect(adapter.activeTimerCount == 3)
        adapter.rotate(); let before = adapter.input.text; clock.advance(1)
        #expect(adapter.input.text == before && clock.jobs.isEmpty && adapter.alternative == nil)
    }
    @Test func overlappingControlReleasesRemainIndependent() {
        for action in [KeyboardAction.shift, .language, .numbers, .symbols, .space, .enter] {
            let adapter = KeyboardInputAdapter(clock: ManualKeyboardClock())
            let control = adapter.press(action)
            let letter = adapter.press(.character("п"))
            adapter.release(letter, inside: true)
            #expect(adapter.input.text == "П")
            adapter.release(control, inside: true)
            switch action {
            case .space: #expect(adapter.input.text == "П ")
            case .enter: #expect(adapter.input.text == "П\n")
            case .language: #expect(adapter.input.language == .english)
            case .numbers: #expect(adapter.input.page == .numbers)
            case .symbols: #expect(adapter.input.page == .symbols)
            case .shift: #expect(adapter.input.uppercase)
            default: Issue.record("Unexpected test action")
            }
        }
    }
}
