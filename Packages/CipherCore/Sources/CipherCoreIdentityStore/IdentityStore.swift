import CipherCore
import Foundation
import Security

// Создание своей личности. Отдельный модуль пакета (продукт `CipherCoreIdentityStore`): его линкует только приложение.
// Клавиатура зависит лишь от `CipherCore`, где есть `IdentityReader` (только чтение), поэтому вызвать
// `loadOrCreate()` или записать личность в Keychain из расширения нельзя на уровне компилятора.

/// Личность приложения: прочитать из хранилища, а если записи нет — создать и записать одной операцией.
public struct IdentityStore: Sendable {
    private let storage: any SecretStorage

    public init(storage: any SecretStorage) {
        self.storage = storage
    }

    /// Хранилище приложения в общем Keychain.
    public static var keychain: IdentityStore { IdentityStore(storage: KeychainSecretStorage.identity) }

    /// Читает личность; новую создаёт **только** если Keychain ответил «записи нет».
    /// Любой другой ответ — `IdentityStorageError`, запись не удаляется и не перезаписывается.
    public func loadOrCreate() throws(IdentityStorageError) -> Identity {
        let first = storage.read()
        switch first.status {
        case errSecSuccess:
            return try decodeIdentity(first.data)
        case errSecItemNotFound:
            break
        default:
            throw .unavailable(status: first.status)
        }

        let created = Identity.generate()
        let status = storage.add(created.privateKeyData())
        switch status {
        case errSecSuccess:
            return created
        case errSecDuplicateItem:
            // Запись успел создать другой запуск — используем её, а свою новую личность выбрасываем.
            let existing = storage.read()
            guard existing.status == errSecSuccess else { throw .unavailable(status: existing.status) }
            return try decodeIdentity(existing.data)
        default:
            throw .unavailable(status: status)
        }
    }
}
