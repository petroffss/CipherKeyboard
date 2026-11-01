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
    @Test func overlappingTouchesOwnTheirReleaseAndCancellation() {
        for first in [
            KeyboardAction.character("п"), .character("е"), .delete, .shift, .language, .numbers, .symbols, .space,
            .enter,
        ] {
            let clock = ManualKeyboardClock()
            let adapter = KeyboardInputAdapter(clock: clock)
            let old = adapter.press(first)
            let current = adapter.press(.character("р"))
            let before = adapter.input.text
            adapter.release(old, inside: true)
            adapter.cancelGesture(old)
            #expect(adapter.input.text == before)
            clock.advance(1)
            adapter.release(current, inside: true)
            #expect(adapter.input.text == before + "Р")
            #expect(adapter.activeTimerCount == 0 && clock.jobs.isEmpty)
        }
        let clock = ManualKeyboardClock(); let adapter = KeyboardInputAdapter(clock: clock)
        adapter.seedForTesting("abcdef")
        let old = adapter.press(.character("е"))
        let deletion = adapter.press(.delete)
        adapter.cancelGesture(old)
        clock.advance(0.48)
        #expect(adapter.input.text == "abc")
        adapter.release(old, inside: false)
        adapter.release(deletion, inside: true)
        clock.advance(1)
        #expect(adapter.input.text == "abc" && clock.jobs.isEmpty)
        let alternate = adapter.press(.character("е"))
        clock.advance(0.45)
        adapter.release(deletion, inside: true)
        #expect(adapter.input.text == "abc")
        adapter.release(alternate, inside: true)
        #expect(adapter.input.text == "abcё")
    }
}
