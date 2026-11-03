#if DEBUG && targetEnvironment(simulator)
    import CipherCore
    import CipherCoreContactStore
    import KeyboardTyping
    import UIKit

    /// The shipping controller and sealer against an instrumented UITextDocumentProxy.
    /// This probe complements, and does not replace, installed-extension runtime scenarios.
    @MainActor enum KeyboardEncryptProbe {
        private final class Proxy: NSObject, UITextDocumentProxy {
            var inserts: [String] = []
            var contextReads = 0, deletes = 0, adjusts = 0
            let id = UUID()
            var documentContextBeforeInput: String? { contextReads += 1; return "До " }
            var documentContextAfterInput: String? { contextReads += 1; return "встречи!" }
            var selectedText: String? { nil }
            var documentIdentifier: UUID { id }
            var documentInputMode: UITextInputMode? { nil }
            var hasText: Bool { contextReads += 1; return true }
            func insertText(_ text: String) { inserts.append(text) }
            func deleteBackward() { deletes += 1 }
            func adjustTextPosition(byCharacterOffset offset: Int) { adjusts += 1 }
            func setMarkedText(_ markedText: String, selectedRange: NSRange) { adjusts += 1 }
            func unmarkText() { adjusts += 1 }
        }
        private final class Controller: KeyboardExtensionController {
            let proxy = Proxy()
            var identity: Identity?
            var store: ContactStore?
            override var simulatorProbeIdentity: (() -> IdentityReadResult)? {
                guard let identity else { return nil }
                return { .identity(identity) }
            }
            override var simulatorProbeContacts: (() -> ContactsReadResult)? {
                guard let store else { return nil }
                return { store.read() }
            }
            override var textDocumentProxy: any UITextDocumentProxy { proxy }
            override var hasFullAccess: Bool { true }
        }
        /// Closed public IDs select constants already used by synthetic runtime proof scenarios.
        /// No expected plaintext is accepted from launch arguments, environment, files or UI.
        private enum SelfOpenCase: String {
            case settingsA = "settings-a"
            case nativeHello = "native-hello"
            case nativeASCII4096 = "native-ascii4096"
            case nativeLiteralAnna = "native-literal-anna"
            case nativeWhitespaceUnicode = "native-whitespace-unicode"
            var expectedText: String {
                switch self {
                case .settingsA: "А"
                case .nativeHello: "Привет"
                case .nativeASCII4096: String(repeating: "a", count: 4096)
                case .nativeLiteralAnna: "Привет, Анна!"
                case .nativeWhitespaceUnicode: "  Привет, Анна! 👨‍👩‍👧‍👦\nе\u{301}  \n"
                }
            }
        }
        /// Opens only the synthetic ciphertext passed by a retained real-extension UI scenario.
        /// The actual sender identity stays in Keychain; only a boolean verdict/public key leaves this probe.
        static func openInserted(_ ciphertext: String) -> String {
            let caseID =
                ProcessInfo.processInfo.environment["CIPHER_INSERTED_SYNTHETIC_CASE"]
                ?? SelfOpenCase.settingsA.rawValue
            guard let proofCase = SelfOpenCase(rawValue: caseID) else { return "FAIL: unsupported synthetic case" }
            guard case .identity(let sender) = IdentityReader.keychain.read() else {
                return "FAIL: missing real identity"
            }
            do {
                let opened = try CipherMessage.open(ciphertext, as: sender, contacts: [])
                guard Array(opened.text.utf8) == Array(proofCase.expectedText.utf8),
                    opened.sender == .me, opened.senderKey == sender.publicKey
                else {
                    return "FAIL: self-open verification"
                }
                let verdict =
                    "PASS: actual inserted ciphertext; Keychain sender self-open; exact UTF-8; sender.me; "
                    + sender.publicKey.string
                return proofCase == .settingsA ? verdict : verdict + "; case=" + proofCase.rawValue
            } catch { return "FAIL: self-open" }
        }
        static func run() async -> String {
            guard LaunchStorage.permitsSimulatorProbes,
                let sender = try? EncryptSetupProbe.makeIdentity(),
                let recipient = try? EncryptSetupProbe.makeIdentity(),
                let third = try? EncryptSetupProbe.makeIdentity()
            else { return "FAIL: setup" }
            let store = ContactStore(storage: InMemoryContactStorage())
            guard (try? store.add(name: "Анна06", key: recipient.publicKey.string, own: sender.publicKey)) != nil
            else { return "FAIL: in-memory contacts" }
            let controller = Controller()
            controller.identity = sender
            controller.store = store
            controller.loadViewIfNeeded(); controller.viewWillAppear(false)
            guard let coordinator = controller.panel.encryption,
                let contact = coordinator.contacts.first(where: { $0.name == "Анна06" })
            else { return "FAIL: contacts" }
            coordinator.select(contact.id)
            let draft = "  Привет, Анна! 👨‍👩‍👧‍👦\nе\u{301}  \n"
            controller.panel.adapter.seedForTesting(draft, cursor: 3)
            coordinator.encrypt(); coordinator.encrypt()
            for _ in 0..<2000 {
                if !coordinator.busy { break }
                try? await Task.sleep(for: .milliseconds(1))
            }
            let proxy = controller.proxy
            guard proxy.inserts.count == 1, let value = proxy.inserts.first,
                proxy.contextReads == 0, proxy.deletes == 0, proxy.adjusts == 0,
                controller.panel.adapter.input.text.isEmpty, controller.panel.adapter.input.cursor == 0
            else { return "FAIL: host capability trace" }
            do {
                let opened = try CipherMessage.open(value, as: recipient, contacts: [])
                let own = try CipherMessage.open(value, as: sender, contacts: [])
                guard Array(opened.text.utf8) == Array(draft.utf8), own.text == draft,
                    opened.senderKey == sender.publicKey, own.sender == .me
                else { return "FAIL: roundtrip" }
                do {
                    _ = try CipherMessage.open(value, as: third, contacts: []); return "FAIL: third recipient"
                } catch CipherError.notARecipient {} catch { return "FAIL: third error" }
                controller.viewWillDisappear(false)
                return
                    "PASS: shipping controller; insertText=1; context=0; delete=0; adjust=0; sender+recipient roundtrip; third rejected"
            } catch { return "FAIL: ciphertext" }
        }
    }
#endif
