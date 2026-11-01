import CipherCore
import UIKit

/// Точка входа расширения клавиатуры. Каркас: состояние своего ключа и кнопка 🌐; раскладки и внутреннее поле — фича 05.
/// Клавиатура личность только читает (`IdentityReader`): создать ключ отсюда нельзя.
final class KeyboardViewController: UIInputViewController {
    private let nextKeyboardButton = UIButton(type: .system)
    private let statusLabel = UILabel()

    override func viewDidLoad() {
        super.viewDidLoad()

        statusLabel.font = .systemFont(ofSize: 17, weight: .semibold)
        statusLabel.textColor = .label
        statusLabel.textAlignment = .center
        statusLabel.numberOfLines = 0
        statusLabel.adjustsFontForContentSizeCategory = false
        statusLabel.accessibilityIdentifier = "keyboard.identityStatus"
        statusLabel.translatesAutoresizingMaskIntoConstraints = false

        nextKeyboardButton.setImage(UIImage(systemName: "globe"), for: .normal)
        nextKeyboardButton.accessibilityLabel = "Следующая клавиатура"
        nextKeyboardButton.addTarget(self, action: #selector(handleInputModeList(from:with:)), for: .allTouchEvents)
        nextKeyboardButton.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(statusLabel)
        view.addSubview(nextKeyboardButton)
        NSLayoutConstraint.activate([
            view.heightAnchor.constraint(equalToConstant: 216),
            statusLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            statusLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            statusLabel.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 48),
            statusLabel.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -48),
            nextKeyboardButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            nextKeyboardButton.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -12),
            nextKeyboardButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 44),
            nextKeyboardButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 44),
        ])
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // Перечитываем при каждом показе: ключ мог появиться в приложении, пока клавиатура была скрыта.
        statusLabel.text = Self.statusText(hasFullAccess: hasFullAccess)
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
}
