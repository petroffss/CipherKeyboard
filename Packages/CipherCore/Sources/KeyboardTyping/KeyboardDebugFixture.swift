#if DEBUG && canImport(UIKit)
    import Foundation
    import CipherCore

    /// Synthetic, process-local design fixtures. No defaults/container/clipboard transport.
    /// Select fixed states with the Debug status-strip menu. Absent in Release.
    @MainActor public enum KeyboardDebugFixture {
        public static func apply(to panel: KeyboardPanel, name: String) {
            let adapter = panel.adapter
            if name == "clear" { adapter.hide(); panel.debugFixture = "fixture=clear"; return }
            if name == "canary" {
                adapter.seedForTesting("TypingCanary05-Ж-20261101"); panel.debugFixture = "fixture=canary"; return
            }
            adapter.seedForTesting(name == "ru-empty" ? "" : "Привет, Анна!")
            panel.statusText = "Ключ A1B2 C3D4"
            panel.contactsText = "Контактов: 2"
            var identityReads = 0
            var contactsReads = 0
            if ["no-access", "no-key", "key-error", "contacts-error"].contains(name) {
                let status = KeyboardSharedStatus.read(
                    hasFullAccess: name != "no-access",
                    identity: {
                        identityReads += 1
                        return name == "key-error" ? .unavailable(.unavailable(status: -1)) : .missing
                    },
                    contacts: {
                        contactsReads += 1
                        return name == "contacts-error" ? .unreadable : .contacts([])
                    })
                panel.statusText = name == "contacts-error" ? "Ключ A1B2 C3D4" : status.identity
                panel.contactsText = name == "contacts-error" ? status.contacts : nil
            }
            panel.debugFixture = "fixture=\(name);identityReads=\(identityReads);contactsReads=\(contactsReads)"
            switch name {
            case "ru-empty": adapter.hide()
            case "shift": adapter.activate(.shift)
            case "caps": adapter.activate(.shift); adapter.activate(.shift)
            case "en": adapter.seedForTesting("Hello, Anna!"); adapter.activate(.language)
            case "numbers": adapter.seedForTesting("Встреча в 18:30"); adapter.activate(.numbers)
            case "symbols": adapter.seedForTesting("Цена: 25 €"); adapter.activate(.numbers); adapter.activate(.symbols)
            case "alternate-e": adapter.seedForTesting("Ещ"); adapter.press(.character("е"))
            case "alternate-softsign": adapter.seedForTesting("Под"); adapter.press(.character("ь"))
            case "multiline":
                adapter.seedForTesting("Первая строка\nВторая строка\nТретья строка\nЧетвёртая строка\nПятая строка")
            case "limit": adapter.seedForTesting(String(repeating: "я", count: 2048)); adapter.activate(.character("я"))
            default: break
            }
        }
    }
#endif
