#if DEBUG
    import CipherCore
    import KeyboardTyping
    import Foundation

    /// Reproducible synthetic messages; the opener is always the production cryptographic implementation.
    enum DecryptAppFixture {
        @MainActor private final class Context { var changed = false }
        @MainActor static func make() -> DecryptCoordinator {
            guard let identity = try? Identity(privateKeyData: Data(repeating: 108, count: 64)),
                let sender = try? Identity(privateKeyData: Data(repeating: 107, count: 64)),
                let foreign = try? Identity(privateKeyData: Data(repeating: 109, count: 64))
            else {
                return DecryptCoordinator(surface: .app, identity: { .unavailable(.corruptedRecord(byteCount: 64)) })
            }
            let args = ProcessInfo.processInfo.arguments
            let name =
                args.firstIndex(of: "-decrypt-state").flatMap { args.indices.contains($0 + 1) ? args[$0 + 1] : nil }
                ?? "contact"
            let context = Context()
            let contact = Contact(
                name: name == "long" ? "Александра Константинопольская — работа" : "Анна", publicKey: sender.publicKey)
            let model = DecryptCoordinator(
                surface: .app,
                identity: {
                    name == "key-error"
                        ? .unavailable(.unavailable(status: -1))
                        : .identity(context.changed ? sender : identity)
                },
                contacts: { name == "contacts-warning" ? .unreadable : .contacts(name == "unknown" ? [] : [contact]) },
                opener: { text, own, book in
                    if name == "busy" { try await Task.sleep(for: .seconds(30)) }
                    if name == "generic" { throw CocoaError(.coderInvalidValue) }
                    let opened = try CipherMessage.open(text, as: own, contacts: book)
                    if name == "changed" { await MainActor.run { context.changed = true } }
                    return opened
                })
            let plain =
                name == "long" ? KeyboardDebugFixture.decryptionDesignLongText : "  Привет, Анна!\nЗавтра в 19:30 👨‍👩‍👧‍👦  "
            guard
                let ciphertext = try? CipherMessage.seal(
                    plain, from: name == "self" ? identity : sender,
                    to: [name == "foreign" ? foreign.publicKey : identity.publicKey])
            else { return model }
            if name != "empty" {
                model.setInput(
                    name == "no-message"
                        ? "Обычная фраза"
                        : name == "corrupt" ? "ckmsg1:invalid" : name == "version" ? "ckmsg2:AA" : ciphertext)
            }
            if name == "paste-error" { model.pasteFailed() }
            if name == "oversize" { model.setInput(String(repeating: "a", count: 65537)) }
            return model
        }
    }
#endif
