#if DEBUG
    import CipherCore
    import CipherCoreContactStore
    import Foundation

    /// Explicit setup on disposable test simulators. Writes only synthetic public contacts, never a draft.
    enum EncryptSetupProbe {
        static var publicKey: String {
            if case .identity(let identity) = IdentityReader.keychain.read() { return identity.publicKey.string }
            return ""
        }
        static func run() -> String {
            guard case .identity(let own) = IdentityReader.keychain.read() else { return "FAIL: identity prerequisite" }
            do {
                let store = ContactStore.appGroup
                for index in 0..<20 {
                    let name =
                        index == 0
                        ? "Анна06"
                        : (index == 19 ? String(repeating: "Я", count: 40) : String(format: "Контакт06 %02d", index))
                    let key = try Identity(privateKeyData: Data(repeating: UInt8(22 + index), count: 64)).publicKey
                    guard case .contacts(let existing) = store.read() else { return "FAIL: contacts unreadable" }
                    if let match = existing.first(where: { $0.name == name }) {
                        guard match.publicKey == key else { return "FAIL: existing fixture name has another key" }
                    } else {
                        try store.add(name: name, key: key.string, own: own.publicKey)
                    }
                }
                return "PASS: real Keychain identity; 20 synthetic public contacts"
            } catch { return "FAIL: synthetic contact setup" }
        }
    }
#endif
