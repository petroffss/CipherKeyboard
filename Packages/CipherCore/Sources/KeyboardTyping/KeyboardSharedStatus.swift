import CipherCore

/// Lazy readers keep even construction of shared-store adapters behind the access check.
public struct KeyboardSharedStatus: Sendable {
    public let identity: String
    public let contacts: String?
    public let isWarning: Bool
    public static func read(
        hasFullAccess: Bool,
        identity: () -> IdentityReadResult = { IdentityReader.keychain.read() },
        contacts: () -> ContactsReadResult = { ContactsReader.appGroup.read() }
    ) -> KeyboardSharedStatus {
        guard hasFullAccess else {
            return KeyboardSharedStatus(
                identity: "Включите «Полный доступ» в Настройках, чтобы шифровать", contacts: nil, isWarning: true)
        }
        let status: String
        let identityWarning: Bool
        switch identity() {
        case .identity(let identity):
            status = "Ваш ключ: " + identity.publicKey.fingerprint.short; identityWarning = false
        case .missing: status = "Откройте приложение CipherKeyboard, чтобы создать ключ"; identityWarning = true
        case .unavailable: status = "Не удалось открыть хранилище ключей"; identityWarning = true
        }
        let count: String
        let contactsWarning: Bool
        switch contacts() {
        case .contacts(let values):
            count = values.isEmpty ? "Контактов нет" : "Контактов: \(values.count)"; contactsWarning = false
        case .unreadable: count = "Не удалось прочитать контакты"; contactsWarning = true
        }
        return KeyboardSharedStatus(identity: status, contacts: count, isWarning: identityWarning || contactsWarning)
    }
}
