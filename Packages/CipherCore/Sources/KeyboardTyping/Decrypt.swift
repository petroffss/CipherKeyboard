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
    public let createdAt: Date?
    public let olderThanSevenDays: Bool

    init(text: String, sender: String, unknown: Bool, contactsWarning: Bool, createdAt: Date?, now: Date) {
        self.text = text
        self.sender = sender
        self.unknown = unknown
        self.contactsWarning = contactsWarning
        self.createdAt = createdAt
        self.olderThanSevenDays = createdAt.map { now.timeIntervalSince($0) > 7 * 24 * 60 * 60 } ?? false
    }
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
    /// Invalidates native input deliveries across edits, operations and visible sessions.
    public private(set) var inputGeneration = UUID()
    public var onChange: (() -> Void)?
    @ObservationIgnored private let surface: Surface
    @ObservationIgnored private let access: () -> Bool
    @ObservationIgnored private let identityAccess: KeyboardIdentityAccess
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
    #if DEBUG
        @ObservationIgnored private var delayNextOpen = false
        @ObservationIgnored private(set) var debugHeldOpenCount = 0

        func debugArmOpenDelay() -> Bool {
            guard surface == .keyboard, canStart, !presenting else { return false }
            delayNextOpen = true
            return true
        }
    #endif

    public init(
        surface: Surface, access: @escaping () -> Bool = { true },
        identity: (() -> IdentityReadResult)? = nil,
        identityMetadata: (() -> IdentityMetadataReadResult)? = nil,
        contacts: @escaping () -> ContactsReadResult = { ContactsReader.appGroup.read() },
        clipboard: (any DecryptClipboardReading)? = nil, blocked: @escaping () -> Bool = { false },
        document: @escaping () -> UUID = { UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)) },
        fingerprintText: @escaping (PublicKey) -> String = { $0.fingerprint.short },
        opener: @escaping Opener = { text, identity, contacts in
            try await Task.detached { try CipherMessage.open(text, as: identity, contacts: contacts) }.value
        }
    ) {
        self.surface = surface; self.access = access; self.contacts = contacts
        identityAccess = KeyboardIdentityAccess(identity: identity, metadata: identityMetadata)
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
        guard let value = readIdentityMetadata() else { result = nil; changed(); return }
        if let previous, previous != value {
            result = nil; presenting = surface == .keyboard && presenting; error = Self.changedMessage
        }
        changed()
    }
    @discardableResult public func setInput(_ value: String) -> Bool {
        guard active, !busy, result == nil else { return false }
        guard value.utf8.count <= Self.limit else { error = Self.oversize; changed(); return false }
        input = value; inputGeneration = UUID(); error = nil; changed(); return true
    }
    public func pasteFailed() {
        guard active, !busy, result == nil else { return }; error = Self.clipboardMessage; changed()
    }
    public func start() {
        guard active, !busy, !blocked(), access() else { return }
        inputGeneration = UUID()
        result = nil; error = nil
        let previousIdentity = baseline
        guard let own = readIdentityMetadata() else { presenting = surface == .keyboard; changed(); return }
        if let previousIdentity, previousIdentity != own {
            presenting = surface == .keyboard; error = Self.changedMessage; changed(); return
        }
        if surface == .app && input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { changed(); return }
        let initialContacts = readContacts().0
        let token = UUID(), generation = session, currentDocument = document()
        operation = token; busy = true; presenting = true; shownDocument = currentDocument; changed()
        let field = surface == .app ? input : nil
        let reader = clipboard, open = opener, readSecret = identityAccess.readSecret
        let snapshot: ClipboardText?
        if field == nil, let synchronous = reader as? any DecryptClipboardSnapshotReading {
            guard valid(token, generation, currentDocument) else { return }
            snapshot = synchronous.readTextSnapshot()
            guard valid(token, generation, currentDocument) else { return }
        } else {
            snapshot = nil
        }
        #if DEBUG
            let delayOpen = delayNextOpen
            delayNextOpen = false
            var lifetime: DecryptDebugLifetime.Operation? = DecryptDebugLifetime.beginOperation()
        #endif
        task = Task { [weak self] in
            #if DEBUG
                defer {
                    withExtendedLifetime(lifetime) {}
                    lifetime = nil
                    if delayOpen { self?.changed() }
                }
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
            guard self?.identityStillMatches(own, token: token) == true else { return }
            do {
                switch value {
                case .empty: throw CipherError.noMessage
                case .denied: self?.finish(error: Self.clipboardMessage, token: token); return
                case .text(let text):
                    guard text.utf8.count <= Self.limit else {
                        self?.finish(error: Self.oversize, token: token); return
                    }
                    let opened: OpenedMessage
                    do {
                        guard let loaded = await readSecret() else { return }
                        guard self?.valid(token, generation, currentDocument) == true,
                            let identity = self?.validateSecret(loaded, expected: own, token: token)
                        else { return }
                        opened = try await open(text, identity, initialContacts)
                    }
                    #if DEBUG
                        if delayOpen, self?.valid(token, generation, currentDocument) == true {
                            self?.debugHeldOpenCount += 1
                            self?.changed()
                            // Cancellation resumes this hold immediately. Deliver the already opened
                            // value to the normal fence so the test exercises a late successful open.
                            try? await Task.sleep(for: .seconds(15))
                        }
                    #endif
                    guard let self, self.valid(token, generation, currentDocument) else { return }
                    guard let current = self.readIdentityMetadata() else {
                        self.finish(error: self.error, token: token); return
                    }
                    guard current == own else {
                        self.finish(error: Self.changedMessage, token: token); return
                    }
                    let (book, unreadable) = self.readContacts()
                    let sender: String, unknown: Bool
                    if opened.senderKey == current {
                        sender = "От: вы"; unknown = false
                    } else if let contact = book.first(where: { $0.publicKey == opened.senderKey }) {
                        sender = "От: " + contact.name; unknown = false
                    } else {
                        sender = "От неизвестного ключа " + self.fingerprintText(opened.senderKey)
                        unknown = true
                    }
                    guard self.valid(token, generation, currentDocument) else { return }
                    self.result = DecryptResult(
                        text: opened.text, sender: sender, unknown: unknown, contactsWarning: unreadable && unknown,
                        createdAt: opened.createdAt, now: Date())
                    self.finish(error: nil, token: token)
                }
            } catch {
                guard let self, self.valid(token, generation, currentDocument) else { return }
                guard self.identityStillMatches(own, token: token) else { return }
                self.finish(error: self.message(error), token: token)
            }
        }
    }
    public func close() {
        inputGeneration = UUID()
        cancel(); result = nil; input = ""; error = nil; presenting = false; shownDocument = nil; changed()
    }
    public func deactivate() {
        active = false; session = UUID(); close(); baseline = nil; identityAvailable = false
    }
    private func cancel() {
        operation = nil; task?.cancel(); task = nil; busy = false
        #if DEBUG
            delayNextOpen = false
        #endif
    }
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
        guard let current = readIdentityMetadata() else { finish(error: error, token: token); return false }
        guard current == key else { finish(error: Self.changedMessage, token: token); return false }
        return true
    }
    private func validateSecret(_ loaded: IdentityReadResult, expected: PublicKey, token: UUID) -> Identity? {
        switch loaded {
        case .identity(let own) where own.publicKey == expected:
            return own
        case .identity:
            finish(error: Self.changedMessage, token: token)
        case .missing, .unavailable:
            setIdentityUnavailable(loaded.publicMetadata)
            finish(error: error, token: token)
        }
        return nil
    }
    private func readIdentityMetadata() -> PublicKey? {
        guard access() else { identityAvailable = false; result = nil; return nil }
        let metadata = identityAccess.readMetadata()
        if case .publicKey(let key) = metadata {
            identityAvailable = true; baseline = key
            return key
        }
        setIdentityUnavailable(metadata)
        return nil
    }
    private func setIdentityUnavailable(_ metadata: IdentityMetadataReadResult) {
        result = nil
        identityAvailable = false
        if surface == .app {
            error = "Ключ недоступен — повторите попытку"
        } else if metadata == .missing {
            error = EncryptInsertCoordinator.missingMessage
        } else {
            error = EncryptInsertCoordinator.keyErrorMessage
        }
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
