#if DEBUG && canImport(UIKit)
    import CipherCore
    import Foundation

    /// Design sources only, always using real envelopes and production CipherMessage.open.
    @MainActor enum KeyboardDecryptFixture {
        private final class Reader: DecryptClipboardReading {
            let value: ClipboardText
            init(_ value: ClipboardText) { self.value = value }
            func readText() async -> ClipboardText { value }
        }
        private final class Context {
            let own = Identity.generate(), sender = Identity.generate()
            var changed = false
        }
        static func apply(to panel: KeyboardPanel, state: String) {
            if state == "idle" {
                // Reuse the approved compose fixture: selected Anna and the exact visible draft.
                KeyboardEncryptFixture.apply(to: panel, state: "ready")
            }
            let context = Context()
            let key = state == "self" ? context.own : context.sender
            let name = state == "long" ? String(repeating: "Анна ", count: 8) : "Анна"
            let contact = Contact(name: name, publicKey: context.sender.publicKey)
            let plain =
                state == "long"
                ? String(repeating: "Длинное сообщение 🙂\n", count: 100) + "Последняя строка"
                : "  Привет, Анна!\nЗавтра в 19:30 👨‍👩‍👧‍👦  "
            guard
                let ciphertext = try? CipherMessage.seal(
                    plain, from: key,
                    to: [state == "foreign" ? Identity.generate().publicKey : context.own.publicKey])
            else { return }
            let text: String
            switch state {
            case "no-message": text = "Обычное сообщение"
            case "corrupt": text = "ckmsg1:invalid"
            case "version": text = "ckmsg2:AA"
            case "oversize": text = String(repeating: "a", count: 65537)
            default: text = ciphertext
            }
            let model = DecryptCoordinator(
                surface: .keyboard,
                access: { [weak panel] in state != "no-access" && panel?.debugAccess?() == true },
                identity: {
                    if state == "no-key" { return .missing }
                    if state == "key-error" { return .unavailable(.unavailable(status: -1)) }
                    if state == "changed" && context.changed { return .identity(context.sender) }
                    return .identity(context.own)
                },
                contacts: {
                    state == "contacts-warning" ? .unreadable : .contacts(state == "unknown" ? [] : [contact])
                }, clipboard: Reader(state == "paste-error" ? .denied : .text(text)),
                blocked: { [weak panel] in panel?.encryption?.busy == true },
                document: { [weak panel] in panel?.debugHost?.documentIdentifier ?? UUID() },
                opener: { text, own, contacts in
                    if state == "busy" { try await Task.sleep(for: .seconds(30)) }
                    if state == "generic" { throw CocoaError(.coderInvalidValue) }
                    return try CipherMessage.open(text, as: own, contacts: contacts)
                })
            panel.enableDecryption(model); model.activate()
            if !["idle", "no-access", "no-key", "key-error"].contains(state) {
                model.start(); context.changed = true
            }
            panel.debugFixture = "fixture=dec-\(state);"
        }
    }
#endif
