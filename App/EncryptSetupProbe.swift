#if DEBUG && targetEnvironment(simulator)
    import CipherCore
    import CipherCoreContactStore
    import CipherCoreIdentityStore
    import Foundation

    enum EncryptSetupProbe {
        /// A throwaway key. Its secret stays in this process and is never exported to a fixture file.
        static func makeIdentity() throws -> Identity {
            try IdentityStore(storage: InMemorySecretStorage()).loadOrCreate()
        }

        static var publicKey: String {
            guard LaunchStorage.permitsSharedSimulatorFixtures else { return "" }
            if case .identity(let identity) = IdentityReader.keychain.read() { return identity.publicKey.string }
            return ""
        }

        /// Real-extension tests explicitly opt into sharing only newly generated public keys.
        static func seedSharedSimulatorBook() -> String {
            guard LaunchStorage.permitsSharedSimulatorFixtures,
                case .identity(let own) = IdentityReader.keychain.read()
            else { return "FAIL: simulator test fixture opt-in and identity required" }
            do {
                let store = ContactStore.appGroup
                for index in 0..<20 {
                    let name =
                        index == 0
                        ? "Анна06 тест"
                        : (index == 19
                            ? (String(repeating: "Я", count: 39) + "Ю") : String(format: "Тест06 %02d", index))
                    guard case .contacts(let existing) = store.read() else { return "FAIL: contacts unreadable" }
                    if !existing.contains(where: { $0.name == name }) {
                        try store.add(name: name, key: makeIdentity().publicKey.string, own: own.publicKey)
                    }
                }
                return "PASS: real Keychain identity; 20 synthetic public contacts"
            } catch { return "FAIL: synthetic contact setup" }
        }
    }
#endif
