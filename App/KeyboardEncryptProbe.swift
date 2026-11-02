#if DEBUG
    import CipherCore
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
            override var textDocumentProxy: any UITextDocumentProxy { proxy }
            override var hasFullAccess: Bool { true }
        }
        /// Opens only the synthetic ciphertext passed by a retained real-extension UI scenario.
        /// The actual sender identity stays in Keychain; only a boolean verdict/public key leaves this probe.
        static func openInserted(_ ciphertext: String) -> String {
            guard case .identity(let sender) = IdentityReader.keychain.read() else {
                return "FAIL: missing real identity"
            }
            do {
                let opened = try CipherMessage.open(ciphertext, as: sender, contacts: [])
                guard opened.text == "А", opened.sender == .me, opened.senderKey == sender.publicKey else {
                    return "FAIL: self-open verification"
                }
                return "PASS: actual inserted ciphertext; Keychain sender self-open; exact UTF-8; sender.me; "
                    + sender.publicKey.string
            } catch { return "FAIL: self-open" }
        }
        static func run() async -> String {
            guard EncryptSetupProbe.run().hasPrefix("PASS"),
                case .identity(let sender) = IdentityReader.keychain.read()
            else { return "FAIL: setup" }
            let controller = Controller()
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
                let recipient = try Identity(privateKeyData: Data(repeating: 22, count: 64))
                let third = try Identity(privateKeyData: Data(repeating: 77, count: 64))
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
