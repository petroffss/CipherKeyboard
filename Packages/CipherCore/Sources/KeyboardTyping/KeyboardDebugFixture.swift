#if DEBUG && canImport(UIKit)
    import Foundation

    /// Synthetic, process-local design fixtures. No defaults/container/clipboard transport.
    /// Pass CIPHER_TYPING_FIXTURE in the Debug process environment. Absent in Release.
    @MainActor public enum KeyboardDebugFixture {
        public static func apply(to panel: KeyboardPanel, name: String) {
            let adapter = panel.adapter
            if !["ru-empty", "no-access", "no-key", "key-error"].contains(name) {
                adapter.seedForTesting("Привет, Анна!")
            }
            switch name {
            case "ru-empty": adapter.hide()
            case "shift": adapter.activate(.shift)
            case "caps": adapter.activate(.shift); adapter.activate(.shift)
            case "en": adapter.activate(.language)
            case "numbers": adapter.activate(.numbers)
            case "symbols": adapter.activate(.numbers); adapter.activate(.symbols)
            case "alternate-e": adapter.press(.character("е"))
            case "alternate-softsign": adapter.press(.character("ь"))
            case "multiline":
                adapter.seedForTesting("Первая строка\nВторая строка\nТретья строка\nЧетвёртая строка\nПятая строка")
            case "limit": adapter.seedForTesting(String(repeating: "я", count: 2048)); adapter.activate(.character("я"))
            case "no-access":
                panel.statusText = "Включите «Полный доступ» в Настройках, чтобы шифровать"; panel.contactsText = nil
            case "no-key":
                panel.statusText = "Откройте приложение CipherKeyboard, чтобы создать ключ"; panel.contactsText = nil
            case "key-error": panel.statusText = "Не удалось открыть хранилище ключей"; panel.contactsText = nil
            case "contacts-error": panel.contactsText = "Не удалось прочитать контакты"
            default: break
            }
        }
    }
#endif
