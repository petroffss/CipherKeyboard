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
            let own: Identity
            let sender: Identity
            var changed = false
            init(compose: KeyboardEncryptFixture.Context?) {
                own = compose?.sender ?? Identity.generate()
                sender = compose?.recipient ?? Identity.generate()
            }
        }
        static func apply(to panel: KeyboardPanel, state: String) {
            let composeStates = ["idle", "no-access", "no-key", "key-error"]
            let compose: KeyboardEncryptFixture.Context?
            if composeStates.contains(state) {
                // The two coordinators render the same synthetic access, key and contacts.
                KeyboardEncryptFixture.apply(to: panel, state: state == "idle" ? "ready" : state)
                compose = panel.debugEncryptionContext
                panel.adapter.seedForTesting("До встречи!\nВозьми документы.", cursor: 7)
            } else {
                compose = nil
            }
            let context = Context(compose: compose)
            let key = state == "self" ? context.own : context.sender
            let name = state == "long" ? "Александра Константинопольская — работа" : "Анна"
            let contact = Contact(name: name, publicKey: context.sender.publicKey)
            let plain =
                state == "long"
                ? KeyboardDebugFixture.decryptionDesignLongText
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
                    if let compose { return compose.identity }
                    if state == "changed" && context.changed { return .identity(context.sender) }
                    return .identity(context.own)
                },
                contacts: {
                    if let compose { return compose.contacts }
                    return state == "contacts-warning" ? .unreadable : .contacts(state == "unknown" ? [] : [contact])
                }, clipboard: Reader(state == "paste-error" ? .denied : .text(text)),
                blocked: { [weak panel] in panel?.encryption?.busy == true },
                document: { [weak panel] in panel?.debugHost?.documentIdentifier ?? UUID() },
                opener: { text, own, contacts in
                    if state == "busy" { try await Task.sleep(for: .seconds(30)) }
                    if state == "generic" { throw CocoaError(.coderInvalidValue) }
                    return try CipherMessage.open(text, as: own, contacts: contacts)
                })
            panel.enableDecryption(model); model.activate()
            if !composeStates.contains(state) {
                model.start(); context.changed = true
            }
            panel.debugFixture = "fixture=dec-\(state);"
        }
    }
#endif
