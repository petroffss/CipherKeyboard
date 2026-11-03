import Foundation
import Security
import Testing

@testable import CipherCore

/// Словари запросов Keychain — без обращения к настоящему Keychain.
@Suite("Запросы Keychain для записи личности")
struct KeychainSecretStorageTests {
    let storage = KeychainSecretStorage.identity

    @Test("Запрос добавления: класс, сервис, аккаунт, группа, защита, без iCloud, 64 байта")
    func addQuery() {
        let key = Identity.generate().publicKey
        let data = Data((0..<64).map { UInt8($0) })
        let query = storage.addQuery(data: data, publicKey: key)

        #expect(query[kSecClass as String] as? String == kSecClassGenericPassword as String)
        #expect(query[kSecAttrService as String] as? String == "dev.cipherkeyboard.identity")
        #expect(query[kSecAttrAccount as String] as? String == "identity.v1")
        #expect(query[kSecAttrAccessGroup as String] as? String == "group.dev.cipherkeyboard")
        #expect(
            query[kSecAttrAccessible as String] as? String == kSecAttrAccessibleWhenUnlockedThisDeviceOnly as String)
        #expect(query[kSecAttrSynchronizable as String] as? Bool == false)
        #expect(query[kSecValueData as String] as? Data == data)
        #expect(query[kSecAttrGeneric as String] as? Data == Data(key.raw))
    }

    @Test("Запрос чтения: те же атрибуты записи, одна запись с данными, без kSecAttrSynchronizableAny")
    func readQuery() {
        let query = storage.readQuery(includeSecret: true)

        #expect(query[kSecClass as String] as? String == kSecClassGenericPassword as String)
        #expect(query[kSecAttrService as String] as? String == "dev.cipherkeyboard.identity")
        #expect(query[kSecAttrAccount as String] as? String == "identity.v1")
        #expect(query[kSecAttrAccessGroup as String] as? String == "group.dev.cipherkeyboard")
        #expect(query[kSecReturnData as String] as? Bool == true)
        #expect(query[kSecReturnAttributes as String] as? Bool == true)
        #expect(query[kSecReturnPersistentRef as String] == nil)
        #expect(query[kSecMatchLimit as String] as? String == kSecMatchLimitOne as String)
        #expect(query[kSecAttrSynchronizable as String] as? String != kSecAttrSynchronizableAny as String)
        #expect(!query.values.contains { $0 as? String == kSecAttrSynchronizableAny as String })
        #expect(query[kSecValueData as String] == nil)
    }

    @Test func metadataRequestsOnlyAttributesOfSameRecord() {
        let metadata = storage.readQuery(includeSecret: false)
        let secret = storage.readQuery(includeSecret: true)
        for attribute in [kSecClass, kSecAttrService, kSecAttrAccount, kSecAttrAccessGroup, kSecMatchLimit] {
            #expect(metadata[attribute as String] as? String == secret[attribute as String] as? String)
        }
        #expect(metadata[kSecReturnAttributes as String] as? Bool == true)
        #expect(metadata[kSecAttrSynchronizable as String] as? Bool == false)
        #expect(metadata[kSecReturnData as String] == nil)
        #expect(metadata[kSecReturnRef as String] == nil)
        #expect(metadata[kSecReturnPersistentRef as String] == nil)
        #expect(metadata[kSecValueData as String] == nil)
    }

    @Test func legacyMigrationTargetsOnlyTheReadRowAndUpdatesOnlyPublicMetadata() throws {
        let identity = Identity.generate(), reference = Data([1, 2, 3])
        let record: [String: Any] = [
            kSecValueData as String: identity.privateKeyData(), kSecValuePersistentRef as String: reference,
        ]
        #expect(KeychainSecretStorage.metadata(from: record) == .unavailable(.missingPublicMetadata))
        #expect(throws: IdentityStorageError.missingPublicMetadata) {
            try KeychainSecretStorage.decode(item: record, allowLegacy: false)
        }
        let (legacy, legacyReference) = try KeychainSecretStorage.decode(item: record, allowLegacy: true)
        #expect(legacy.publicKey == identity.publicKey)
        #expect(legacyReference == reference)
        let query = storage.legacyUpdateQuery(reference: reference)
        #expect(query[kSecValuePersistentRef as String] as? Data == reference)
        #expect(Set(query.keys) == [kSecValuePersistentRef as String])
        let updates = storage.publicMetadataAttributes(legacy.publicKey)
        #expect(Set(updates.keys) == [kSecAttrGeneric as String])
        let migrated = record.merging(updates) { _, update in update }
        let (reloaded, reloadedReference) = try KeychainSecretStorage.decode(item: migrated, allowLegacy: false)
        #expect(reloaded.publicKey == identity.publicKey)
        #expect(reloadedReference == nil)
        #expect(migrated[kSecValueData as String] as? Data == identity.privateKeyData())
    }

    @Test func malformedOrMismatchedMetadataCannotBeUsedOrMigrated() {
        let identity = Identity.generate(), foreign = Identity.generate().publicKey
        for raw in [Data([42]), Data(foreign.raw)] {
            let record = [
                kSecValueData as String: identity.privateKeyData(),
                kSecValuePersistentRef as String: Data([1]),
                kSecAttrGeneric as String: raw,
            ]
            #expect(throws: IdentityStorageError.invalidPublicMetadata) {
                try KeychainSecretStorage.decode(item: record, allowLegacy: true)
            }
        }
    }
}
