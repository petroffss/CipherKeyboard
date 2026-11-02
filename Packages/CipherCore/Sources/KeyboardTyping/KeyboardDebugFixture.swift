#if DEBUG && canImport(UIKit)
    import Foundation
    import CipherCore

    /// Synthetic, process-local design fixtures. No defaults/container/clipboard transport.
    /// Select fixed states with the Debug status-strip grid. Absent in Release.
    @MainActor public enum KeyboardDebugFixture {
        private static let referenceExcerpt =
            "Привет, Анна!\nВстречаемся завтра.\nЯ буду у входа.\nНапиши, когда придёшь.\nДо встречи!"
        public static func apply(to panel: KeyboardPanel, name: String) {
            if ["enc-delay", "enc-fault", "enc-normal", "enc-canary"].contains(name) {
                panel.debugFaults.delay = name == "enc-delay" ? 2 : 0
                panel.debugFaults.fails = name == "enc-fault"
                if name == "enc-canary" { panel.adapter.seedForTesting("EncryptCanary06-Ж-20261102") }
                panel.debugFixture = "fixture=\(name);"; return
            }
            if name == "enc-bytes4096" {
                panel.adapter.seedForTesting(String(repeating: "a", count: 4096));
                panel.debugFixture = "fixture=enc-bytes4096;"; return
            }
            if name.hasPrefix("enc-") {
                KeyboardEncryptFixture.apply(to: panel, state: String(name.dropFirst(4))); return
            }
            panel.disableEncryptionForTesting()
            let adapter = panel.adapter
            if name == "clear" { adapter.hide(); panel.debugFixture = "fixture=clear"; return }
            if name == "canary" {
                adapter.seedForTesting("TypingCanary05-Ж-20261101"); panel.debugFixture = "fixture=canary"; return
            }
            adapter.seedForTesting(name == "ru-empty" ? "" : "Привет, Анна!")
            panel.statusText = "Ключ A1B2 C3D4"
            panel.contactsText = "Контактов: 2"
            panel.statusIsWarning = false
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
                panel.statusIsWarning = status.isWarning
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
                adapter.seedForTesting(referenceExcerpt, cursor: 0)
                // The reference shows lowercase keys; explicit Shift-off preserves the visible start caret.
                adapter.activate(.shift)
            case "limit":
                let padding = String(repeating: "x", count: 4096 - referenceExcerpt.utf8.count)
                adapter.seedForTesting(referenceExcerpt + padding, cursor: 0)
                adapter.activate(.shift)
                adapter.activate(.character("я"))
            default: break
            }
        }
    }
#endif
