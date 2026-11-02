#if DEBUG && canImport(UIKit)
    import CipherCore
    import Foundation

    /// Process-local synthetic sources and fault controls. Never compiled into Release.
    @MainActor enum KeyboardEncryptFixture {
        /// The design success anchor freezes the injected clock; real runtime tests use SystemKeyboardClock.
        @MainActor final class FrozenClock: KeyboardClock {
            var now: TimeInterval { 0 }
            func schedule(after delay: TimeInterval, _ action: @escaping @MainActor () -> Void) -> UUID { UUID() }
            func cancel(_ token: UUID) {}
        }
        @MainActor final class Context: CiphertextHost, RecipientPreference {
            weak var host: (any CiphertextHost)?
            var recipientID: UUID?
            var document = UUID()
            var documentIdentifier: UUID { document }
            var hasSelection: Bool { host?.hasSelection ?? false }
            var identity: IdentityReadResult
            var contacts: ContactsReadResult
            let sender = Identity.generate()
            let recipient = Identity.generate()
            init(host: any CiphertextHost) {
                self.host = host
                identity = .identity(sender)
                let names = [
                    "Анна", "Борис", "Вера", "Глеб", "Дарья", "Елена", "Жанна", "Зоя", "Иван", "Кирилл", "Лев", "Мария",
                    "Николай", "Ольга", "Павел", "Роман", "Сергей", "Татьяна", "Ульяна",
                    String(repeating: "Я", count: 40),
                ]
                let publicKey = recipient.publicKey
                contacts = .contacts(
                    names.enumerated().map { index, name in
                        Contact(
                            id: UUID(uuidString: String(format: "06000000-0000-0000-0000-%012d", index + 1)) ?? UUID(),
                            name: name, publicKey: publicKey)
                    })
            }
            func insertCiphertext(_ ciphertext: String) { host?.insertCiphertext(ciphertext) }
        }
        static func apply(to panel: KeyboardPanel, state: String) {
            guard let host = panel.debugHost else { return }
            panel.encryption?.hide()
            let context = Context(host: host)
            panel.debugEncryptionContext = context
            if state == "no-key" { context.identity = .missing }
            if state == "key-error" { context.identity = .unavailable(.unavailable(status: -1)) }
            if state == "no-contacts" { context.contacts = .contacts([]) }
            let clock: any KeyboardClock = state == "success" ? FrozenClock() : SystemKeyboardClock()
            let model = EncryptInsertCoordinator(
                adapter: panel.adapter, host: context, preference: context,
                access: { [weak panel] in state != "no-access" && panel?.debugAccess?() == true },
                identity: { [weak context] in context?.identity ?? .missing },
                contacts: { [weak context] in context?.contacts ?? .unreadable }, clock: clock,
                seal: { text, sender, recipient in
                    if state == "sending" || state == "document-changed" {
                        try await Task.sleep(for: .seconds(state == "sending" ? 30 : 0.1))
                    }
                    if state == "failure" { throw CipherError.tampered }
                    return try CipherMessage.seal(text, from: sender, to: [recipient])
                })
            panel.enableEncryption(model)
            model.open()
            let firstID = UUID(uuidString: "06000000-0000-0000-0000-000000000001") ?? UUID()
            if !["unselected", "no-contacts", "no-access"].contains(state) {
                model.select(
                    state == "long-name"
                        ? (UUID(uuidString: "06000000-0000-0000-0000-000000000020") ?? UUID()) : firstID)
            }
            let draft =
                state == "long-name"
                ? "Привет!\nВстречаемся завтра.\nВозьми документы.\nОбсудим детали при встрече."
                : (state == "empty" ? "" : "Привет, Анна!")
            panel.adapter.seedForTesting(draft)
            if state == "contacts-error" {
                // Start from a validated selection, then fail the book read without changing its identity.
                context.contacts = .unreadable; model.refresh()
            }
            if state == "picker" { model.openPicker() }
            if state == "limit" {
                panel.adapter.seedDefensiveLimitForTesting()
                model.encrypt()
            }
            if state == "changed" {
                context.contacts = .contacts([]); model.encrypt()
            }
            if ["sending", "success", "selection", "failure", "document-changed"].contains(state) { model.encrypt() }
            if state == "document-changed" { context.document = UUID() }
            panel.debugFixture = "fixture=enc-\(state);"
        }
    }
#endif
