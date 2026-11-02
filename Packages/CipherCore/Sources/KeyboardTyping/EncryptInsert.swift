import CipherCore
import Foundation

/// The coordinator's entire host capability. No context, deletion, cursor movement or clipboard.
@MainActor public protocol CiphertextHost: AnyObject {
    var documentIdentifier: UUID { get }
    var hasSelection: Bool { get }
    func insertCiphertext(_ ciphertext: String)
}

@MainActor public protocol RecipientPreference: AnyObject {
    var recipientID: UUID? { get set }
}

/// Only this UUID is persisted, in the extension's local preferences. The caller gates every access.
@MainActor public final class LocalRecipientPreference: RecipientPreference {
    private let defaults: () -> UserDefaults
    private let key = "keyboard.lastRecipientID"
    public init(defaults: @escaping () -> UserDefaults = { .standard }) { self.defaults = defaults }
    public var recipientID: UUID? {
        get { defaults().string(forKey: key).flatMap(UUID.init(uuidString:)) }
        set {
            if let newValue {
                defaults().set(newValue.uuidString, forKey: key)
            } else {
                defaults().removeObject(forKey: key)
            }
        }
    }
}

/// Session-local state machine. Stores and host are checked again after every suspension, before commit.
@MainActor public final class EncryptInsertCoordinator {
    public typealias Sealer = @Sendable (String, Identity, PublicKey) async throws -> String
    private enum IdentityAvailability { case unknown, available, missing, unavailable }
    public static let accessMessage = "Включите «Полный доступ» в Настройках, чтобы шифровать"
    public static let changedMessage = "Данные изменились — выберите получателя заново"
    public static let missingMessage = "Откройте приложение CipherKeyboard, чтобы создать ключ"
    public static let keyErrorMessage = "Ключ недоступен — откройте приложение CipherKeyboard"
    public static let contactsErrorMessage = "Не удалось прочитать контакты"
    public static let selectionMessage = "Снимите выделение в поле сообщения"
    public static let documentMessage = "Поле сообщения изменилось — повторите попытку"
    public static let failureMessage = "Не удалось зашифровать сообщение. Повторите попытку"

    public let adapter: KeyboardInputAdapter
    public private(set) var contacts: [Contact] = []
    public private(set) var selected: Contact?
    public private(set) var pickerOpen = false
    public private(set) var busy = false
    public private(set) var error: String?
    public private(set) var success: String?
    public private(set) var contactsUnreadable = false
    public private(set) var identityKey: PublicKey?
    private var identityAvailability = IdentityAvailability.unknown
    public var identityMetadata: String {
        guard access() else { return "Общие данные недоступны" }
        switch identityAvailability {
        case .missing: return "Личный ключ ещё не создан"
        case .unavailable: return "Не удалось открыть хранилище ключей"
        case .unknown: return "CipherKeyboard"
        case .available:
            guard let identityKey else { return "CipherKeyboard" }
            let own = "Ваш ключ: " + identityKey.fingerprint.short
            return contactsUnreadable ? own : own + " · Контактов: \(contacts.count)"
        }
    }
    public var onChange: (() -> Void)?
    private let access: () -> Bool
    private let identityReader: () -> IdentityReadResult
    private let contactsReader: () -> ContactsReadResult
    private let preference: any RecipientPreference
    private weak var host: (any CiphertextHost)?
    private let seal: Sealer
    private let clock: any KeyboardClock
    private var session = UUID()
    private var active = false
    // Session-local full key survives failed reads; identityKey tracks current availability only.
    private var lastValidatedIdentityKey: PublicKey?
    private var operation: UUID?
    private var task: Task<Void, Never>?
    private var successTimer: UUID?
    public var sessionActive: Bool { active }
    public var permitted: Bool { access() }
    public var canSelect: Bool { active && access() && !busy }
    public var canEncrypt: Bool {
        active && access() && !busy && identityKey != nil && selected != nil && !contactsUnreadable
            && !adapter.input.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && adapter.input.byteCount <= CipherMessage.maxPlaintextBytes
    }
    public var status: String {
        if !access() { return Self.accessMessage }
        if busy { return "Шифруем…" }
        if let error { return error }
        if adapter.input.limitError { return KeyboardInput.limitMessage }
        if let success { return success }
        if contacts.isEmpty { return "Добавьте контакт в приложении CipherKeyboard" }
        if selected == nil { return "Выберите получателя" }
        return adapter.input.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "Текст будет зашифрован только после нажатия" : "Готово к шифрованию"
    }
    public init(
        adapter: KeyboardInputAdapter, host: any CiphertextHost, preference: any RecipientPreference,
        access: @escaping () -> Bool,
        identity: @escaping () -> IdentityReadResult = { IdentityReader.keychain.read() },
        contacts: @escaping () -> ContactsReadResult = { ContactsReader.appGroup.read() },
        clock: any KeyboardClock = SystemKeyboardClock(),
        seal: @escaping Sealer = { text, identity, recipient in
            try await Task.detached { try CipherMessage.seal(text, from: identity, to: [recipient]) }.value
        }
    ) {
        self.adapter = adapter; self.host = host; self.preference = preference; self.access = access
        identityReader = identity; contactsReader = contacts; self.clock = clock; self.seal = seal
    }
    public func open() {
        if active { refresh(); return }
        active = true; session = UUID(); error = nil; success = nil
        guard gate() else { return }
        let remembered = preference.recipientID
        _ = readIdentity()
        if readContacts(), let remembered {
            selected = contacts.first { $0.id == remembered }
            if selected == nil { preference.recipientID = nil }
        }
        onChange?()
    }
    public func refresh() {
        guard active, !busy, gate() else { return }
        error = nil
        _ = readIdentity()
        _ = readContacts()
        onChange?()
    }
    public func openPicker() {
        guard canSelect, gate() else { return }
        refresh(); pickerOpen = true; onChange?()
    }
    public func closePicker() { guard !busy else { return }; pickerOpen = false; onChange?() }
    public func select(_ id: UUID) {
        guard canSelect, gate() else { return }
        // Explicit selection reads the current book, not a stale displayed row.
        guard readContacts(), let contact = contacts.first(where: { $0.id == id }) else {
            onChange?(); return
        }
        selected = contact; preference.recipientID = id; pickerOpen = false
        error = nil; success = nil; _ = readIdentity(); onChange?()
    }
    public func hide() {
        active = false; session = UUID(); operation = nil; task?.cancel(); task = nil
        busy = false; pickerOpen = false; selected = nil; contacts = []; identityKey = nil
        lastValidatedIdentityKey = nil; identityAvailability = .unknown
        error = nil; success = nil; contactsUnreadable = false
        if let successTimer { clock.cancel(successTimer) }; successTimer = nil
        adapter.interactionEnabled = true; adapter.hide(); onChange?()
    }
    public func encrypt() {
        begin(text: adapter.input.text)
    }
    private func begin(text: String) {
        guard active, !busy, gate(), let host else { return }
        error = nil; success = nil
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { onChange?(); return }
        guard text.utf8.count <= CipherMessage.maxPlaintextBytes else {
            error = "Слишком длинное сообщение: \(text.utf8.count) из 4096 байт"; onChange?(); return
        }
        guard let sender = readIdentity() else { onChange?(); return }
        guard readContacts(), let recipient = selected else { onChange?(); return }
        guard !host.hasSelection else { error = Self.selectionMessage; onChange?(); return }
        let document = host.documentIdentifier
        let token = UUID(), activeSession = session
        operation = token; busy = true; adapter.cancelGesture(); adapter.interactionEnabled = false
        onChange?()
        let sealer = seal
        task = Task { [weak self] in
            do {
                let ciphertext = try await sealer(text, sender, recipient.publicKey)
                guard let self, self.active, self.session == activeSession, self.operation == token else { return }
                self.commit(ciphertext, sender: sender.publicKey, recipient: recipient, document: document)
            } catch {
                guard let self, self.active, self.session == activeSession, self.operation == token else { return }
                if self.gate() { self.error = Self.failureMessage }
            }
            guard let self, self.session == activeSession, self.operation == token else { return }
            self.operation = nil; self.task = nil; self.busy = false; self.adapter.interactionEnabled = true
            self.onChange?()
        }
    }
    private func commit(_ ciphertext: String, sender: PublicKey, recipient: Contact, document: UUID) {
        guard gate(), let host else { return }
        guard host.documentIdentifier == document else { error = Self.documentMessage; return }
        guard !host.hasSelection else { error = Self.selectionMessage; return }
        guard let currentIdentity = readIdentity() else { return }
        guard currentIdentity.publicKey == sender else { invalidateRecipient(); return }
        guard readContacts(), let current = selected,
            current.id == recipient.id, current.publicKey == recipient.publicKey
        else { return }
        // Defend the narrow host boundary even when an injected sealer misbehaves.
        guard ciphertext.hasPrefix("ckmsg1:"), ciphertext.count > 7,
            !ciphertext.contains(where: { $0.isWhitespace }), !ciphertext.contains("…")
        else { error = Self.failureMessage; return }
        // No await and no user callbacks between the final gates and the one host mutation.
        guard access(), active, host.documentIdentifier == document, !host.hasSelection else {
            error = access() ? Self.documentMessage : Self.accessMessage; return
        }
        host.insertCiphertext(ciphertext)
        adapter.hide()
        success = "Зашифровано для " + current.name; error = nil
        if let successTimer { clock.cancel(successTimer) }
        let currentSession = session
        successTimer = clock.schedule(after: 2) { [weak self] in
            guard let self, self.session == currentSession else { return }
            self.success = nil; self.successTimer = nil; self.onChange?()
        }
    }
    @discardableResult private func gate() -> Bool {
        guard access() else {
            contacts = []; selected = nil; identityKey = nil; pickerOpen = false
            identityAvailability = .unknown
            error = Self.accessMessage; onChange?(); return false
        }
        return true
    }
    private func readIdentity() -> Identity? {
        guard gate() else { return nil }
        switch identityReader() {
        case .identity(let identity):
            let previous = lastValidatedIdentityKey
            identityKey = identity.publicKey; lastValidatedIdentityKey = identity.publicKey
            identityAvailability = .available
            if let previous, previous != identity.publicKey {
                invalidateRecipient(); return nil
            }
            return identity
        case .missing: identityKey = nil; identityAvailability = .missing; error = Self.missingMessage
        case .unavailable: identityKey = nil; identityAvailability = .unavailable; error = Self.keyErrorMessage
        }
        return nil
    }
    @discardableResult private func readContacts() -> Bool {
        guard gate() else { return false }
        switch contactsReader() {
        case .contacts(let values):
            contacts = ContactBook(contacts: values).contacts; contactsUnreadable = false
            if let selected {
                guard let updated = contacts.first(where: { $0.id == selected.id }),
                    updated.publicKey == selected.publicKey
                else { invalidateRecipient(); return false }
                self.selected = updated
            }
            return true
        case .unreadable:
            contacts = []; contactsUnreadable = true; error = Self.contactsErrorMessage; return false
        }
    }
    private func invalidateRecipient() {
        selected = nil
        if access() { preference.recipientID = nil }
        error = Self.changedMessage
    }
    #if DEBUG
        /// Independent defensive-limit entry, absent in Release. It does not alter the input model limit.
        public func encryptForTesting(text: String) { begin(text: text) }
    #endif
}
