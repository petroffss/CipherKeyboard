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
                if mode == "export-own-public-key" { return own.publicKey.string }
                let sender = try Identity(privateKeyData: Data(repeating: mode == "unknown" ? 110 : 107, count: 64))
                let store = ContactStore.appGroup
                guard case .contacts(let book) = store.read() else { return "FAIL: contacts unreadable" }
                if mode == "import-contact" {
                    guard let raw = ProcessInfo.processInfo.environment["CIPHER_DECRYPT_IMPORT_PUBLIC_KEY"],
                        let name = ProcessInfo.processInfo.environment["CIPHER_DECRYPT_IMPORT_NAME"]
                    else { return "FAIL: missing public contact" }
                    let key = try PublicKey(string: raw)
                    if let existing = book.first(where: { $0.publicKey == key }) {
                        return existing.name == name ? "PASS: imported public contact" : "FAIL: key has another name"
                    }
                    guard !book.contains(where: { $0.name == name }) else { return "FAIL: name has another key" }
                    try store.add(name: name, key: key.string, own: own.publicKey)
                    return "PASS: imported public contact"
                }
                if mode != "unknown" && !book.contains(where: { $0.publicKey == sender.publicKey }) {
                    try store.add(name: "Анна07", key: sender.publicKey.string, own: own.publicKey)
                }
                let text = mode == "long" ? String(repeating: "a", count: 4096) : "  Привет, Анна!\nЗавтра в 19:30 👨‍👩‍👧‍👦  "
                return try CipherMessage.seal(text, from: mode == "self" ? own : sender, to: [own.publicKey])
            } catch { return "FAIL: synthetic decrypt setup" }
        }
    }
#endif
