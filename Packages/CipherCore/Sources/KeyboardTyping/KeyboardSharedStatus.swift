import CipherCore

/// Lazy readers keep even construction of shared-store adapters behind the access check.
public struct KeyboardSharedStatus: Sendable {
    public let identity: String
    public let contacts: String?
    public static func read(
        hasFullAccess: Bool,
        identity: () -> IdentityReadResult = { IdentityReader.keychain.read() },
        contacts: () -> ContactsReadResult = { ContactsReader.appGroup.read() }
    ) -> KeyboardSharedStatus {
        guard hasFullAccess else {
            return KeyboardSharedStatus(
                identity: "Включите «Полный доступ» в Настройках, чтобы шифровать", contacts: nil)
        }
        let status: String
        switch identity() {
        case .identity(let identity): status = "Ваш ключ: " + identity.publicKey.fingerprint.short
        case .missing: status = "Откройте приложение CipherKeyboard, чтобы создать ключ"
        case .unavailable: status = "Не удалось открыть хранилище ключей"
        }
        let count: String
        switch contacts() {
        case .contacts(let values): count = values.isEmpty ? "Контактов нет" : "Контактов: \(values.count)"
        case .unreadable: count = "Не удалось прочитать контакты"
        }
        return KeyboardSharedStatus(identity: status, contacts: count)
    }
}
