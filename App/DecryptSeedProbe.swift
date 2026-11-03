#if DEBUG && targetEnvironment(simulator)
    import CipherCore
    import CipherCoreContactStore
    import Foundation

    /// Opt-in setup for a disposable simulator. Only random public fixture keys cross the process boundary.
    enum DecryptSeedProbe {
        struct Output {
            let text: String
            let contactName: String
            init(_ text: String, contactName: String = "") {
                self.text = text
                self.contactName = contactName
            }
        }

        static func run() -> Output {
            guard LaunchStorage.permitsSharedSimulatorFixtures,
                case .identity(let own) = IdentityReader.keychain.read()
            else { return Output("FAIL: simulator test fixture opt-in and identity required") }
            do {
                let mode = ProcessInfo.processInfo.environment["CIPHER_DECRYPT_SYNTHETIC_CASE"] ?? "contact"
                if mode == "export-own-public-key" { return Output(own.publicKey.string) }
                let store = ContactStore.appGroup
                guard case .contacts(let book) = store.read() else { return Output("FAIL: contacts unreadable") }
                guard ["contact", "unknown", "self", "long"].contains(mode) else {
                    return Output("FAIL: unsupported synthetic decrypt case")
                }
                let sender = mode == "self" ? own : try EncryptSetupProbe.makeIdentity()
                var name = ""
                if mode != "unknown", mode != "self" {
                    let usedNames = Set(book.map(\.name))
                    let base = "Анна07"
                    name = base
                    var index = 2
                    while usedNames.contains(name) {
                        name = "\(base) · \(index)"
                        index += 1
                    }
                    try store.add(name: name, key: sender.publicKey.string, own: own.publicKey)
                }
                let text = mode == "long" ? String(repeating: "a", count: 4096) : "  Привет, Анна!\nЗавтра в 19:30 👨‍👩‍👧‍👦  "
                return Output(try CipherMessage.seal(text, from: sender, to: [own.publicKey]), contactName: name)
            } catch { return Output("FAIL: synthetic decrypt setup") }
        }
    }
#endif
