import Testing
@testable import KeyboardTyping

/// A shell owns its host separately, just as UIInputViewController does. The shared production
/// adapter cannot access this capability; every editing action is exercised below.
@MainActor struct KeyboardIsolationTests {
    final class HostSpy {
        var calls = 0
        var documentContextBeforeInput: String? { calls += 1; return "before" }
        var documentContextAfterInput: String? { calls += 1; return "after" }
        var selectedText: String? { calls += 1; return "selected" }
        func insertText(_ text: String) { calls += 1 }
        func deleteBackward() { calls += 1 }
        func adjustTextPosition(byCharacterOffset offset: Int) { calls += 1 }
    }
    @Test func noHostProxyCalls() {
        let host = HostSpy()
        let clock = ManualKeyboardClock()
        let adapter = KeyboardInputAdapter(clock: clock)
        for action in [
            KeyboardAction.delete, .enter, .space, .shift, .character("е"), .language, .numbers, .symbols,
            .character("1"), .delete,
        ] {
            adapter.activate(action)
        }
        adapter.moveCursor(to: 0)
        let delete = adapter.press(.delete); clock.advance(1); adapter.release(delete, inside: true)
        let letter = adapter.press(.character("е")); clock.advance(0.45); adapter.release(letter, inside: true)
        adapter.rotate(); adapter.hide(); clock.advance(1)
        #expect(host.calls == 0)
        #expect(adapter.input.text.isEmpty)
    }
}

extension KeyboardIsolationTests {
    @Test func noAccessNeverConstructsSharedReaders() {
        var identityCalls = 0
        var contactsCalls = 0
        let status = KeyboardSharedStatus.read(
            hasFullAccess: false,
            identity: {
                identityCalls += 1
                return .missing
            },
            contacts: {
                contactsCalls += 1
                return .unreadable
            })
        #expect(identityCalls == 0 && contactsCalls == 0)
        #expect(status.identity == "Включите «Полный доступ» в Настройках, чтобы шифровать")
        #expect(status.contacts == nil)
        let missing = KeyboardSharedStatus.read(hasFullAccess: true, identity: { .missing }, contacts: { .unreadable })
        #expect(missing.identity == "Откройте приложение CipherKeyboard, чтобы создать ключ")
        #expect(missing.contacts == "Не удалось прочитать контакты")
        let failed = KeyboardSharedStatus.read(
            hasFullAccess: true, identity: { .unavailable(.unavailable(status: -1)) }, contacts: { .contacts([]) })
        #expect(failed.identity == "Не удалось открыть хранилище ключей")
    }
}
