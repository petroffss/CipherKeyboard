import CipherCore
import UIKit

/// Точка входа расширения клавиатуры. Каркас: название и кнопка 🌐; раскладки и внутреннее поле — фича 05.
final class KeyboardViewController: UIInputViewController {
    private let nextKeyboardButton = UIButton(type: .system)

    override func viewDidLoad() {
        super.viewDidLoad()

        let titleLabel = UILabel()
        titleLabel.text = CipherCore.productName
        titleLabel.font = .preferredFont(forTextStyle: .headline)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        nextKeyboardButton.setImage(UIImage(systemName: "globe"), for: .normal)
        nextKeyboardButton.accessibilityLabel = "Следующая клавиатура"
        nextKeyboardButton.addTarget(self, action: #selector(handleInputModeList(from:with:)), for: .allTouchEvents)
        nextKeyboardButton.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(titleLabel)
        view.addSubview(nextKeyboardButton)
        NSLayoutConstraint.activate([
            view.heightAnchor.constraint(equalToConstant: 216),
            titleLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            titleLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            nextKeyboardButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            nextKeyboardButton.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -12),
            nextKeyboardButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 44),
            nextKeyboardButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 44),
        ])
    }

    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        nextKeyboardButton.isHidden = !needsInputModeSwitchKey
    }
}
