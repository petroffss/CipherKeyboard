import CipherCore
import UIKit

/// Точка входа расширения клавиатуры. Каркас: состояние своего ключа, строка контактов и кнопка 🌐;
/// раскладки и внутреннее поле — фича 05. Клавиатура личность и контакты только читает
/// (`IdentityReader`, `ContactsReader`): создать ключ или изменить контакты отсюда нельзя.
final class KeyboardViewController: UIInputViewController {
    private let nextKeyboardButton = UIButton(type: .system)
    private let statusLabel = UILabel()
    private let contactsLabel = UILabel()
    private let statusStack = UIStackView()

    override func viewDidLoad() {
        super.viewDidLoad()

        statusLabel.font = .systemFont(ofSize: 17, weight: .semibold)
        statusLabel.textColor = .label
        statusLabel.textAlignment = .center
        statusLabel.numberOfLines = 0
        statusLabel.adjustsFontForContentSizeCategory = false
        statusLabel.accessibilityIdentifier = "keyboard.identityStatus"

        contactsLabel.font = .systemFont(ofSize: 15)
        contactsLabel.textColor = .secondaryLabel
        contactsLabel.textAlignment = .center
        contactsLabel.numberOfLines = 0
        contactsLabel.adjustsFontForContentSizeCategory = false
        contactsLabel.accessibilityIdentifier = "keyboard.contactsStatus"

        statusStack.axis = .vertical
        statusStack.alignment = .center
        statusStack.spacing = 6
        statusStack.addArrangedSubview(statusLabel)
        statusStack.addArrangedSubview(contactsLabel)
        statusStack.translatesAutoresizingMaskIntoConstraints = false

        nextKeyboardButton.setImage(UIImage(systemName: "globe"), for: .normal)
        nextKeyboardButton.accessibilityLabel = "Следующая клавиатура"
        nextKeyboardButton.accessibilityIdentifier = "keyboard.next"
        nextKeyboardButton.addTarget(self, action: #selector(handleInputModeList(from:with:)), for: .allTouchEvents)
        nextKeyboardButton.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(statusStack)
        view.addSubview(nextKeyboardButton)
        NSLayoutConstraint.activate([
            view.heightAnchor.constraint(equalToConstant: 216),
            statusStack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            statusStack.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            statusStack.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 48),
            statusStack.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -48),
            nextKeyboardButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            nextKeyboardButton.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -12),
            nextKeyboardButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 44),
            nextKeyboardButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 44),
        ])
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // Перечитываем при каждом показе: ключ и контакты могли измениться в приложении, пока клавиатура была скрыта.
        let permitted = hasFullAccess
        KeyboardAccessRecorder.record(hasFullAccess: permitted) { FileKeyboardSetupStorage.appGroup }
        statusLabel.text = Self.statusText(hasFullAccess: permitted)
        let contactsText = Self.contactsText(hasFullAccess: permitted)
        contactsLabel.text = contactsText
        contactsLabel.isHidden = contactsText == nil
    }

    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        nextKeyboardButton.isHidden = !needsInputModeSwitchKey
    }

    /// Текст строки состояния. Без полного доступа Keychain не читается.
    private static func statusText(hasFullAccess: Bool) -> String {
        guard hasFullAccess else { return "Включите «Полный доступ» в Настройках, чтобы шифровать" }
        switch IdentityReader.keychain.read() {
        case .identity(let identity):
            return "Ваш ключ: " + identity.publicKey.fingerprint.short
        case .missing:
            return "Откройте приложение CipherKeyboard, чтобы создать ключ"
        case .unavailable:
            return "Не удалось открыть хранилище ключей"
        }
    }

    /// Строка контактов. Без полного доступа файл группы не читается — строки нет.
    private static func contactsText(hasFullAccess: Bool) -> String? {
        guard hasFullAccess else { return nil }
        switch ContactsReader.appGroup.read() {
        case .contacts(let contacts) where contacts.isEmpty:
            return "Контактов нет"
        case .contacts(let contacts):
            return "Контактов: \(contacts.count)"
        case .unreadable:
            return "Не удалось прочитать контакты"
        }
    }
}
