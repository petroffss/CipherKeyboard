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
        let data = Data((0..<64).map { UInt8($0) })
        let query = storage.addQuery(data: data)

        #expect(query[kSecClass as String] as? String == kSecClassGenericPassword as String)
        #expect(query[kSecAttrService as String] as? String == "dev.cipherkeyboard.identity")
        #expect(query[kSecAttrAccount as String] as? String == "identity.v1")
        #expect(query[kSecAttrAccessGroup as String] as? String == "group.dev.cipherkeyboard")
        #expect(
            query[kSecAttrAccessible as String] as? String == kSecAttrAccessibleWhenUnlockedThisDeviceOnly as String)
        #expect(query[kSecAttrSynchronizable as String] as? Bool == false)
        #expect(query[kSecValueData as String] as? Data == data)
    }

    @Test("Запрос чтения: те же атрибуты записи, одна запись с данными, без kSecAttrSynchronizableAny")
    func readQuery() {
        let query = storage.readQuery()

        #expect(query[kSecClass as String] as? String == kSecClassGenericPassword as String)
        #expect(query[kSecAttrService as String] as? String == "dev.cipherkeyboard.identity")
        #expect(query[kSecAttrAccount as String] as? String == "identity.v1")
        #expect(query[kSecAttrAccessGroup as String] as? String == "group.dev.cipherkeyboard")
        #expect(query[kSecReturnData as String] as? Bool == true)
        #expect(query[kSecMatchLimit as String] as? String == kSecMatchLimitOne as String)
        #expect(query[kSecAttrSynchronizable as String] as? String != kSecAttrSynchronizableAny as String)
        #expect(!query.values.contains { $0 as? String == kSecAttrSynchronizableAny as String })
        #expect(query[kSecValueData as String] == nil)
    }
}
