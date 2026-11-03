import CipherCore
import Foundation
import Observation

public enum ClipboardText: Sendable { case text(String), empty, denied }

/// This capability has no host or write APIs. Invoked only by an explicit action.
@MainActor public protocol DecryptClipboardReading: AnyObject {
    func readText() async -> ClipboardText
}

/// A system reader can preserve the current UI action's user-intent context.
/// Delayed readers remain asynchronous for cancellation and race verification.
@MainActor public protocol DecryptClipboardSnapshotReading: DecryptClipboardReading {
    func readTextSnapshot() -> ClipboardText
}

public struct DecryptResult: Equatable, Sendable {
    public let text: String
    public let sender: String
    public let unknown: Bool
    public let contactsWarning: Bool
}

/// Shared application/extension state machine. A generation fences every suspension.
@MainActor @Observable public final class DecryptCoordinator {
    public enum Surface { case keyboard, app }
    public typealias Opener = @Sendable (String, Identity, [Contact]) async throws -> OpenedMessage
    public static let limit = 65536
    public static let oversize = "Слишком большой текст для вставки: максимум 65536 байт"
    public static let accessMessage = "Включите «Полный доступ» в Настройках, чтобы расшифровывать"
    public static let changedMessage = "Данные изменились — повторите расшифровку"
    public static let clipboardMessage = "Нет доступа к буферу обмена"
    public static let clipboardRecovery =
        "Настройки → Приложения → CipherKeyboard → Вставка из других приложений → Разрешить. Чтение — только по нажатию."
    public static let contactsMessage = "Не удалось прочитать контакты — имя отправителя не определено"
    public static let unknownHint = "Добавьте контакт в приложении, чтобы видеть имя"
    public static let failureMessage = "Не удалось расшифровать сообщение. Повторите попытку"
    public private(set) var input = ""
    public private(set) var busy = false
    public private(set) var presenting = false
    public private(set) var error: String?
    public private(set) var result: DecryptResult?
    public private(set) var active = false
    public private(set) var identityAvailable = false
    public var onChange: (() -> Void)?
    @ObservationIgnored private let surface: Surface
    @ObservationIgnored private let access: () -> Bool
    @ObservationIgnored private let identity: () -> IdentityReadResult
    @ObservationIgnored private let contacts: () -> ContactsReadResult
    @ObservationIgnored private let clipboard: (any DecryptClipboardReading)?
    @ObservationIgnored private let blocked: () -> Bool
    @ObservationIgnored private let document: () -> UUID
    @ObservationIgnored private let opener: Opener
    @ObservationIgnored private let fingerprintText: (PublicKey) -> String
    @ObservationIgnored private var session = UUID()
    @ObservationIgnored private var operation: UUID?
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var baseline: PublicKey?
    @ObservationIgnored private var shownDocument: UUID?

    public init(
        surface: Surface, access: @escaping () -> Bool = { true },
        identity: @escaping () -> IdentityReadResult = { IdentityReader.keychain.read() },
        contacts: @escaping () -> ContactsReadResult = { ContactsReader.appGroup.read() },
        clipboard: (any DecryptClipboardReading)? = nil, blocked: @escaping () -> Bool = { false },
        document: @escaping () -> UUID = { UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)) },
        fingerprintText: @escaping (PublicKey) -> String = { $0.fingerprint.short },
        opener: @escaping Opener = { text, identity, contacts in
            try await Task.detached { try CipherMessage.open(text, as: identity, contacts: contacts) }.value
        }
    ) {
        self.surface = surface; self.access = access; self.identity = identity; self.contacts = contacts
        self.clipboard = clipboard; self.blocked = blocked; self.document = document; self.opener = opener
        self.fingerprintText = fingerprintText
        #if DEBUG
            DecryptDebugLifetime.register(self)
        #endif
    }
    deinit { task?.cancel() }
    public var permitted: Bool { access() }
    public var canStart: Bool {
        active && access() && (surface == .app || identityAvailable) && !busy && !blocked()
            && (surface == .keyboard || !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }
    public var status: String? { busy ? "Расшифровываем…" : error }
    public func activate() {
        guard !active else { refresh(); return }
        active = true; session = UUID(); refresh()
    }
    public func refresh() {
        guard active else { return }
        guard access() else {
            cancel(); input = ""; result = nil; presenting = false; baseline = nil; identityAvailable = false
            error = surface == .keyboard ? Self.accessMessage : nil; changed(); return
        }
        if let shownDocument, shownDocument != document() { deactivate(); return }
        guard !busy else { return }
        let previous = baseline
        if let value = readIdentity(), let previous, previous != value.publicKey {
            result = nil; presenting = surface == .keyboard && presenting; error = Self.changedMessage
        }
        changed()
    }
    @discardableResult public func setInput(_ value: String) -> Bool {
        guard !busy, result == nil else { return false }
        guard value.utf8.count <= Self.limit else { error = Self.oversize; changed(); return false }
        input = value; error = nil; changed(); return true
    }
    public func pasteFailed() { guard !busy else { return }; error = Self.clipboardMessage; changed() }
    public func start() {
        guard active, !busy, !blocked(), access() else { return }
        result = nil; error = nil
        let previousIdentity = baseline
        guard let own = readIdentity() else { presenting = surface == .keyboard; changed(); return }
        if let previousIdentity, previousIdentity != own.publicKey {
            presenting = surface == .keyboard; error = Self.changedMessage; changed(); return
        }
        if surface == .app && input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { changed(); return }
        let initialContacts = readContacts().0
        let token = UUID(), generation = session, currentDocument = document()
        operation = token; busy = true; presenting = true; shownDocument = currentDocument; changed()
        let field = surface == .app ? input : nil
        let reader = clipboard, open = opener
        let snapshot: ClipboardText?
        if field == nil, let synchronous = reader as? any DecryptClipboardSnapshotReading {
            guard valid(token, generation, currentDocument) else { return }
            snapshot = synchronous.readTextSnapshot()
            guard valid(token, generation, currentDocument) else { return }
        } else {
            snapshot = nil
        }
        #if DEBUG
            let lifetime = DecryptDebugLifetime.beginOperation()
        #endif
        task = Task { [weak self] in
            #if DEBUG
                defer { withExtendedLifetime(lifetime) {} }
            #endif
            let value: ClipboardText
            if let field {
                value = .text(field)
            } else if let snapshot {
                value = snapshot
            } else {
                value = await reader?.readText() ?? .empty
            }
            guard self?.valid(token, generation, currentDocument) == true else { return }
            guard self?.identityStillMatches(own.publicKey, token: token) == true else { return }
            do {
                switch value {
                case .empty: throw CipherError.noMessage
                case .denied: self?.finish(error: Self.clipboardMessage, token: token); return
                case .text(let text):
                    guard text.utf8.count <= Self.limit else {
                        self?.finish(error: Self.oversize, token: token); return
                    }
                    let opened = try await open(text, own, initialContacts)
                    guard let self, self.valid(token, generation, currentDocument) else { return }
                    guard let current = self.readIdentity() else {
                        self.finish(error: self.error, token: token); return
                    }
                    guard current.publicKey == own.publicKey else {
                        self.finish(error: Self.changedMessage, token: token); return
                    }
                    let (book, unreadable) = self.readContacts()
                    let sender: String, unknown: Bool
                    if opened.senderKey == current.publicKey {
                        sender = "От: вы"; unknown = false
                    } else if let contact = book.first(where: { $0.publicKey == opened.senderKey }) {
                        sender = "От: " + contact.name; unknown = false
                    } else {
                        sender = "От неизвестного ключа " + self.fingerprintText(opened.senderKey)
                        unknown = true
                    }
                    self.result = DecryptResult(
                        text: opened.text, sender: sender, unknown: unknown, contactsWarning: unreadable && unknown)
                    self.finish(error: nil, token: token)
                }
            } catch {
                guard let self, self.valid(token, generation, currentDocument) else { return }
                guard self.identityStillMatches(own.publicKey, token: token) else { return }
                self.finish(error: self.message(error), token: token)
            }
        }
    }
    public func close() {
        cancel(); result = nil; input = ""; error = nil; presenting = false; shownDocument = nil; changed()
    }
    public func deactivate() {
        active = false; session = UUID(); close(); baseline = nil; identityAvailable = false
    }
    private func cancel() { operation = nil; task?.cancel(); task = nil; busy = false }
    private func valid(_ token: UUID, _ generation: UUID, _ currentDocument: UUID) -> Bool {
        guard active, session == generation, operation == token else { return false }
        guard access(), document() == currentDocument else { deactivate(); return false }
        return true
    }
    private func finish(error: String?, token: UUID) {
        guard operation == token else { return }
        self.error = error; operation = nil; task = nil; busy = false; changed()
    }
    private func identityStillMatches(_ key: PublicKey, token: UUID) -> Bool {
        guard let current = readIdentity() else { finish(error: error, token: token); return false }
        guard current.publicKey == key else { finish(error: Self.changedMessage, token: token); return false }
        return true
    }
    private func readIdentity() -> Identity? {
        guard access() else { identityAvailable = false; return nil }
        switch identity() {
        case .identity(let own): identityAvailable = true; baseline = own.publicKey; return own
        case .missing:
            identityAvailable = false
            error =
                surface == .keyboard ? EncryptInsertCoordinator.missingMessage : "Ключ недоступен — повторите попытку"
        case .unavailable:
            identityAvailable = false
            error =
                surface == .keyboard ? EncryptInsertCoordinator.keyErrorMessage : "Ключ недоступен — повторите попытку"
        }
        return nil
    }
    private func readContacts() -> ([Contact], Bool) {
        guard access() else { return ([], true) }
        switch contacts() {
        case .contacts(let values): return (ContactBook(contacts: values).contacts, false)
        case .unreadable: return ([], true)
        }
    }
    private func message(_ error: any Error) -> String {
        switch error as? CipherError {
        case .noMessage:
            return surface == .keyboard
                ? "В буфере нет зашифрованного сообщения. Скопируйте его в чате"
                : "В тексте нет зашифрованного сообщения"
        case .malformed, .tampered: return "Сообщение повреждено или подделано"
        case .notARecipient: return "Сообщение зашифровано не для вас"
        case .unsupportedVersion: return "Сообщение из более новой версии CipherKeyboard — обновите приложение"
        default: return Self.failureMessage
        }
    }
    private func changed() { onChange?() }
}

#if DEBUG
    /// Weak runtime probes contain no message, key or sender data and are absent from Release.
    @MainActor public enum DecryptDebugLifetime {
        private final class WeakReference {
            weak var value: AnyObject?
            init(_ value: AnyObject) { self.value = value }
        }
        final class Operation {}
        private static var coordinators: [WeakReference] = []
        private static var operations: [WeakReference] = []
        static func register(_ model: DecryptCoordinator) {
            coordinators.removeAll { $0.value == nil }; coordinators.append(WeakReference(model))
        }
        static func beginOperation() -> Operation {
            let token = Operation()
            operations.removeAll { $0.value == nil }; operations.append(WeakReference(token))
            return token
        }
        public static var liveCoordinators: Int { coordinators.filter { $0.value != nil }.count }
        public static var liveOperations: Int { operations.filter { $0.value != nil }.count }
    }
#endif
