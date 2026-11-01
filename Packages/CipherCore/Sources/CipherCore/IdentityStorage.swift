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

/// Только чтение личности — для клавиатуры. Метода создания или записи у типа нет.
public struct IdentityReader: Sendable {
    private let storage: any SecretStorage

    public init(storage: any SecretStorage) {
        self.storage = storage
    }

    /// Читатель общего Keychain приложения и клавиатуры.
    public static var keychain: IdentityReader { IdentityReader(storage: KeychainSecretStorage.identity) }

    public func read() -> IdentityReadResult {
        let result = storage.read()
        switch result.status {
        case errSecSuccess:
            do {
                return .identity(try decodeIdentity(result.data))
            } catch {
                return .unavailable(error)
            }
        case errSecItemNotFound:
            return .missing
        default:
            return .unavailable(.unavailable(status: result.status))
        }
    }
}

/// Разбор записи личности. `package`: нужен `IdentityStore` из `CipherCoreIdentityStore`, снаружи пакета не виден.
package func decodeIdentity(_ data: Data?) throws(IdentityStorageError) -> Identity {
    guard let data else { throw .corruptedRecord(byteCount: 0) }
    guard data.count == 64, let identity = try? Identity(privateKeyData: data) else {
        throw .corruptedRecord(byteCount: data.count)
    }
    return identity
}

/// Запись личности в Keychain, общем для приложения и клавиатуры (access group = App Group).
/// `package`: снаружи пакета тип не виден — клавиатура получает только `IdentityReader.keychain`,
/// а `add` в настоящий Keychain доступен лишь `IdentityStore.keychain` (модуль `CipherCoreIdentityStore`).
package struct KeychainSecretStorage: SecretStorage {
    package let service: String
    package let account: String
    package let accessGroup: String

    package init(service: String, account: String, accessGroup: String) {
        self.service = service
        self.account = account
        self.accessGroup = accessGroup
    }

    /// Единственная запись личности: 64 байта приватных ключей.
    package static let identity = KeychainSecretStorage(
        service: "dev.cipherkeyboard.identity", account: "identity.v1", accessGroup: "group.dev.cipherkeyboard")

    /// Атрибуты, по которым запись находится: класс, сервис, аккаунт, группа доступа.
    func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessGroup as String: accessGroup,
        ]
    }

    /// Запрос чтения: одна запись, вернуть данные. Синхронизируемые записи (iCloud) не ищутся.
    func readQuery() -> [String: Any] {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        return query
    }

    /// Запрос добавления: только на этом устройстве, только когда разблокировано, без iCloud.
    func addQuery(data: Data) -> [String: Any] {
        var query = baseQuery()
        query[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        query[kSecAttrSynchronizable as String] = false
        query[kSecValueData as String] = data
        return query
    }

    package func read() -> (status: OSStatus, data: Data?) {
        var result: CFTypeRef?
        let status = SecItemCopyMatching(readQuery() as CFDictionary, &result)
        guard status == errSecSuccess else { return (status, nil) }
        return (status, result as? Data)
    }

    package func add(_ data: Data) -> OSStatus {
        SecItemAdd(addQuery(data: data) as CFDictionary, nil)
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
