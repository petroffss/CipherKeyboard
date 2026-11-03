#if DEBUG && targetEnvironment(simulator)
    import KeyboardTyping
    import UIKit

    /// Instantiates the shipping extension controller with a real UITextDocumentProxy spy.
    /// Only the OS-provided boundary is replaced; controller, panel and editing adapter are production.
    @MainActor enum KeyboardIsolationProbe {
        private final class HostSpy: NSObject, UITextDocumentProxy {
            var calls = 0
            var documentContextBeforeInput: String? { calls += 1; return "before" }
            var documentContextAfterInput: String? { calls += 1; return "after" }
            var selectedText: String? { calls += 1; return "selected" }
            var documentInputMode: UITextInputMode? { nil }
            var documentIdentifier: UUID { UUID() }
            var hasText: Bool { calls += 1; return true }
            func insertText(_ text: String) { calls += 1 }
            func deleteBackward() { calls += 1 }
            func adjustTextPosition(byCharacterOffset offset: Int) { calls += 1 }
            func setMarkedText(_ markedText: String, selectedRange: NSRange) { calls += 1 }
            func unmarkText() { calls += 1 }
        }
        private final class ProbeController: KeyboardExtensionController {
            let spy = HostSpy()
            var requiresNextKeyboard = false
            override var needsInputModeSwitchKey: Bool { requiresNextKeyboard }
            override var textDocumentProxy: any UITextDocumentProxy { spy }
            override var hasFullAccess: Bool { false }
        }
        static func run() -> String {
            let controller = ProbeController()
            controller.loadViewIfNeeded()
            let adapter = controller.panel.adapter
            for required in [false, true] {
                controller.requiresNextKeyboard = required
                controller.viewWillLayoutSubviews()
                guard controller.panel.nextKeyboardButton.isHidden == !required else { return "FAIL: globe visibility" }
            }
            let labels = [
                "delete": "Удалить", "language": "Сменить язык", "numbers": "Цифры", "space": "Пробел",
                "return": "Новая строка", "shift": "Регистр", "next": "Следующая клавиатура",
            ]
            for (id, label) in labels {
                guard
                    controller.panel.subviews.first(where: { $0.accessibilityIdentifier == "keyboard." + id })?
                        .accessibilityLabel == label
                else { return "FAIL: control label " + id }
            }
            for (key, alternative) in [("е", "ё"), ("ь", "ъ")] {
                guard
                    let button = controller.panel.subviews.first(where: {
                        $0.accessibilityIdentifier == "keyboard.key." + key
                    }),
                    button.accessibilityHint == "Удерживайте для " + alternative,
                    button.accessibilityCustomActions?.first?.name == "Ввести " + alternative
                else { return "FAIL: alternate accessibility" }
            }
            adapter.activate(.shift); adapter.activate(.shift)
            guard
                controller.panel.subviews.first(where: { $0.accessibilityIdentifier == "keyboard.shift" })?
                    .accessibilityValue == "Caps Lock"
            else { return "FAIL: caps accessibility" }
            adapter.hide()
            for action in [
                KeyboardAction.delete, .enter, .space, .shift, .character("е"), .language, .numbers, .symbols,
                .character("1"), .delete,
            ] {
                adapter.activate(action)
            }
            adapter.moveCursor(to: 0)
            adapter.activate(.delete)
            adapter.press(.character("ь")); adapter.cancelGesture()
            adapter.press(.delete); adapter.rotate()
            adapter.hide()
            guard controller.spy.calls == 0, adapter.input.text.isEmpty, adapter.activeTimerCount == 0 else {
                return "FAIL"
            }
            return "PASS: production controller, proxy calls 0"
        }
    }
#endif
