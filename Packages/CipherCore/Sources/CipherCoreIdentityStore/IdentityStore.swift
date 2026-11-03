import CipherCore
import Foundation
import Security

// Создание своей личности. Отдельный модуль пакета (продукт `CipherCoreIdentityStore`): его линкует только приложение.
// Клавиатура зависит лишь от `CipherCore`, где есть `IdentityReader` (только чтение), поэтому вызвать
// `loadOrCreate()` или записать личность в Keychain из расширения нельзя на уровне компилятора.

/// Личность приложения: прочитать из хранилища, а если записи нет — создать и записать одной операцией.
public struct IdentityStore: Sendable {
    private let read: @Sendable () -> IdentityReadResult
    private let add: @Sendable (Identity) -> OSStatus

    public init(storage: any SecretStorage) {
        let reader = IdentityReader(storage: storage)
        read = { reader.read() }
        add = { storage.add($0.privateKeyData()) }
    }

    private init(keychain: KeychainSecretStorage) {
        read = { Self.readAndMigrate(keychain) }
        add = { identity in
            let query = keychain.addQuery(data: identity.privateKeyData(), publicKey: identity.publicKey)
            return SecItemAdd(query as CFDictionary, nil)
        }
    }

    /// Хранилище приложения в общем Keychain.
    public static var keychain: IdentityStore { IdentityStore(keychain: .identity) }

    /// Читает личность; новую создаёт **только** если Keychain ответил «записи нет».
    /// Приватные данные существующей записи никогда не меняются.
    public func loadOrCreate() throws(IdentityStorageError) -> Identity {
        switch read() {
        case .identity(let identity): return identity
        case .unavailable(let error): throw error
        case .missing: break
        }

        let created = Identity.generate()
        let status = add(created)
        switch status {
        case errSecSuccess:
            return created
        case errSecDuplicateItem:
            // Запись успел создать другой запуск — используем её, а свою новую личность выбрасываем.
            switch read() {
            case .identity(let identity): return identity
            case .unavailable(let error): throw error
            case .missing: throw .unavailable(status: errSecItemNotFound)
            }
        default:
            throw .unavailable(status: status)
        }
    }

    private static func readAndMigrate(_ keychain: KeychainSecretStorage) -> IdentityReadResult {
        let (result, reference) = keychain.read(allowLegacy: true)
        guard case .identity(let identity) = result, let reference else { return result }
        // Update only the public attribute on the legacy row whose private key was read.
        // Concurrent backfills can only install the same public key.
        let query = keychain.legacyUpdateQuery(reference: reference)
        let attributes = keychain.publicMetadataAttributes(identity.publicKey)
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            return .unavailable(.unavailable(status: status))
        }
        // Read attributes again after the write or a competing backfill. An absent row here
        // is an error, so loadOrCreate cannot create a replacement for a migrated identity.
        switch keychain.readMetadata() {
        case .publicKey(let key) where key == identity.publicKey: return .identity(identity)
        case .unavailable(let error): return .unavailable(error)
        default: return .unavailable(.invalidPublicMetadata)
        }
    }
}
