import Foundation
import Security

// Хранение своей личности: только чтение. Создание и запись (`IdentityStore`) — в отдельном модуле
// `CipherCoreIdentityStore`, который линкует только приложение: клавиатура не может создать ключ — это не скомпилируется.
// Приложение и клавиатура получают готовую `Identity` или ошибку и Keychain напрямую не вызывают.

/// Хранилище одной секретной записи. Только чтение и добавление: обновления и удаления нет намеренно —
/// существующую личность нельзя перезаписать или стереть (иначе пользователь потеряет свои сообщения).
public protocol SecretStorage: Sendable {
    /// Статус Keychain и данные записи (данные — только при `errSecSuccess`).
    func read() -> (status: OSStatus, data: Data?)
    /// Добавляет запись одной операцией. Если запись уже есть — `errSecDuplicateItem`, данные не меняются.
    func add(_ data: Data) -> OSStatus
}

/// Хранилище ключей недоступно или запись в нём испорчена. Новая личность в этих случаях не создаётся.
public enum IdentityStorageError: Error, Equatable, Sendable {
    /// Keychain ответил статусом, при котором нельзя ни прочитать, ни безопасно создать личность.
    case unavailable(status: OSStatus)
    /// Запись есть, но это не личность (не 64 байта или не ключи). Запись не трогаем.
    case corruptedRecord(byteCount: Int)
    /// Старую запись нужно открыть в приложении, чтобы добавить открытый ключ.
    case missingPublicMetadata
    /// Атрибут открытого ключа повреждён или не соответствует приватному ключу.
    case invalidPublicMetadata
}

/// Результат чтения личности без права создания.
public enum IdentityReadResult: Sendable {
    /// Личность есть.
    case identity(Identity)
    /// Записи нет (`errSecItemNotFound`): ключ ещё не создан в приложении.
    case missing
    /// Хранилище недоступно или запись испорчена — это не «ключа нет».
    case unavailable(IdentityStorageError)
}

/// Только открытый ключ. Проверка статуса клавиатуры не читает приватные данные.
public enum IdentityMetadataReadResult: Equatable, Sendable {
    case publicKey(PublicKey)
    case missing
    case unavailable(IdentityStorageError)
}

/// Только чтение личности — для клавиатуры. Метода создания или записи у типа нет.
public struct IdentityReader: Sendable {
    private let readIdentity: @Sendable () -> IdentityReadResult

    public init(storage: any SecretStorage) {
        readIdentity = {
            let result = storage.read()
            switch result.status {
            case errSecSuccess:
                do throws(IdentityStorageError) {
                    return .identity(try decodeIdentity(result.data))
                } catch {
                    return .unavailable(error)
                }
            case errSecItemNotFound: return .missing
            default: return .unavailable(.unavailable(status: result.status))
            }
        }
    }

    private init(readIdentity: @escaping @Sendable () -> IdentityReadResult) {
        self.readIdentity = readIdentity
    }

    /// Читатель общего Keychain приложения и клавиатуры.
    public static var keychain: IdentityReader {
        IdentityReader { KeychainSecretStorage.identity.read().result }
    }

    /// Атрибуты той же записи Keychain, без запроса её секретного значения.
    public static func readKeychainMetadata() -> IdentityMetadataReadResult {
        KeychainSecretStorage.identity.readMetadata()
    }

    public func read() -> IdentityReadResult { readIdentity() }
}

/// Разбор записи личности. `package`: нужен `IdentityStore` из `CipherCoreIdentityStore`, снаружи пакета не виден.
package func decodeIdentity(_ data: Data?) throws(IdentityStorageError) -> Identity {
    guard let data else { throw .corruptedRecord(byteCount: 0) }
    guard data.count == 64, let identity = try? Identity(privateKeyData: data) else {
        throw .corruptedRecord(byteCount: data.count)
    }
    return identity
}

/// Одна запись общего Keychain. В этом модуле есть только чтение. Запись выполняет IdentityStore приложения.
package struct KeychainSecretStorage: Sendable {
    private let service: String
    private let account: String
    private let accessGroup: String

    package static let identity = KeychainSecretStorage(
        service: "dev.cipherkeyboard.identity", account: "identity.v1", accessGroup: "group.dev.cipherkeyboard")

    /// Атрибуты, по которым запись находится: класс, сервис, аккаунт, группа доступа.
    private func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessGroup as String: accessGroup,
            kSecAttrSynchronizable as String: false,
        ]
    }

    func readQuery(includeSecret: Bool, includeReference: Bool = false) -> [String: Any] {
        var query = baseQuery()
        query[kSecReturnAttributes as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        if includeSecret { query[kSecReturnData as String] = true }
        if includeReference { query[kSecReturnPersistentRef as String] = true }
        return query
    }

    package func addQuery(data: Data, publicKey: PublicKey) -> [String: Any] {
        var query = baseQuery()
        query[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        query.merge(publicMetadataAttributes(publicKey)) { _, value in value }
        query[kSecValueData as String] = data
        return query
    }

    package func publicMetadataAttributes(_ publicKey: PublicKey) -> [String: Any] {
        [kSecAttrGeneric as String: Data(publicKey.raw)]
    }

    package func legacyUpdateQuery(reference: Data) -> [String: Any] {
        [kSecValuePersistentRef as String: reference]
    }

    private func copyItem(_ query: [String: Any]) -> (OSStatus, [String: Any]?) {
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        return (status, result as? [String: Any])
    }

    /// Keychain may omit an unset generic attribute or return an empty value for a legacy item.
    static func metadata(from attributes: [String: Any]) -> IdentityMetadataReadResult {
        guard let value = attributes[kSecAttrGeneric as String] else {
            return .unavailable(.missingPublicMetadata)
        }
        guard let raw = value as? Data else { return .unavailable(.invalidPublicMetadata) }
        guard !raw.isEmpty else { return .unavailable(.missingPublicMetadata) }
        guard let key = try? PublicKey(validatingRaw: Array(raw)) else { return .unavailable(.invalidPublicMetadata) }
        return .publicKey(key)
    }

    package func readMetadata() -> IdentityMetadataReadResult {
        let (status, item) = copyItem(readQuery(includeSecret: false))
        switch status {
        case errSecSuccess:
            guard let item else { return .unavailable(.invalidPublicMetadata) }
            return Self.metadata(from: item)
        case errSecItemNotFound: return .missing
        default: return .unavailable(.unavailable(status: status))
        }
    }

    static func decode(
        item: [String: Any], allowLegacy: Bool
    ) throws(IdentityStorageError) -> (Identity, legacyReference: Data?) {
        let identity = try decodeIdentity(item[kSecValueData as String] as? Data)
        switch metadata(from: item) {
        case .publicKey(let key) where key == identity.publicKey:
            return (identity, nil)
        case .unavailable(.missingPublicMetadata):
            guard allowLegacy, let reference = item[kSecValuePersistentRef as String] as? Data else {
                throw .missingPublicMetadata
            }
            return (identity, reference)
        default: throw .invalidPublicMetadata
        }
    }

    package func read(allowLegacy: Bool = false) -> (result: IdentityReadResult, legacyReference: Data?) {
        let (status, item) = copyItem(readQuery(includeSecret: true, includeReference: allowLegacy))
        switch status {
        case errSecSuccess:
            guard let item else { return (.unavailable(.corruptedRecord(byteCount: 0)), nil) }
            do throws(IdentityStorageError) {
                let (identity, reference) = try Self.decode(item: item, allowLegacy: allowLegacy)
                return (.identity(identity), reference)
            } catch {
                return (.unavailable(error), nil)
            }
        case errSecItemNotFound: return (.missing, nil)
        default: return (.unavailable(.unavailable(status: status)), nil)
        }
    }
}

/// Хранилище в памяти: для тестов ядра и для UI-тестов приложения (только в Debug). Настоящий Keychain не трогает.
public final class InMemorySecretStorage: SecretStorage, @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Data?
    private var failingReads: [OSStatus]
    private let addDelay: TimeInterval

    /// - Parameters:
    ///   - data: запись, которая уже лежит в хранилище.
    ///   - failingReads: статусы, которые вернут первые чтения по очереди (затем чтение работает).
    ///   - addDelay: задержка добавления в секундах — чтобы был виден экран создания ключа.
    public init(data: Data? = nil, failingReads: [OSStatus] = [], addDelay: TimeInterval = 0) {
        stored = data
        self.failingReads = failingReads
        self.addDelay = addDelay
    }

    public func read() -> (status: OSStatus, data: Data?) {
        lock.lock()
        defer { lock.unlock() }
        if !failingReads.isEmpty { return (failingReads.removeFirst(), nil) }
        guard let stored else { return (errSecItemNotFound, nil) }
        return (errSecSuccess, stored)
    }

    public func add(_ data: Data) -> OSStatus {
        if addDelay > 0 { Thread.sleep(forTimeInterval: addDelay) }
        lock.lock()
        defer { lock.unlock() }
        guard stored == nil else { return errSecDuplicateItem }
        stored = data
        return errSecSuccess
    }
}
