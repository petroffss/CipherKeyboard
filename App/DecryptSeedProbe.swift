#if DEBUG
    import CipherCore
    import CipherCoreContactStore
    import Foundation

    /// Explicit preparation for a disposable simulator. Release consumes the ordinary stores after reinstall.
    enum DecryptSeedProbe {
        static func run() -> String {
            guard case .identity(let own) = IdentityReader.keychain.read() else { return "FAIL: identity prerequisite" }
            do {
                let mode = ProcessInfo.processInfo.environment["CIPHER_DECRYPT_SYNTHETIC_CASE"] ?? "contact"
                let sender = try Identity(privateKeyData: Data(repeating: mode == "unknown" ? 110 : 107, count: 64))
                let store = ContactStore.appGroup
                guard case .contacts(let book) = store.read() else { return "FAIL: contacts unreadable" }
                if mode != "unknown" && !book.contains(where: { $0.publicKey == sender.publicKey }) {
                    try store.add(name: "Анна07", key: sender.publicKey.string, own: own.publicKey)
                }
                let text = mode == "long" ? String(repeating: "a", count: 4096) : "  Привет, Анна!\nЗавтра в 19:30 👨‍👩‍👧‍👦  "
                return try CipherMessage.seal(text, from: mode == "self" ? own : sender, to: [own.publicKey])
            } catch { return "FAIL: synthetic decrypt setup" }
        }
    }
#endif
