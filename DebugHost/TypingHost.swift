#if DEBUG
    import UIKit

    /// Separate disposable-simulator host. Never a source member of the shipping app/extension.
    @main final class TypingHostApp: UIResponder, UIApplicationDelegate {
        func application(
            _ application: UIApplication, configurationForConnecting session: UISceneSession,
            options: UIScene.ConnectionOptions
        ) -> UISceneConfiguration {
            let config = UISceneConfiguration(name: "TypingHost", sessionRole: session.role)
            config.delegateClass = TypingHostScene.self
            return config
        }
    }
    final class TypingHostScene: UIResponder, UIWindowSceneDelegate {
        var window: UIWindow?
        func scene(
            _ scene: UIScene, willConnectTo session: UISceneSession,
            options connectionOptions: UIScene.ConnectionOptions
        ) {
            guard let scene = scene as? UIWindowScene else { return }
            let window = UIWindow(windowScene: scene)
            window.rootViewController = TypingHostController()
            window.makeKeyAndVisible()
            self.window = window
        }
    }
    final class TypingHostController: UIViewController, UITextViewDelegate {
        private let field = UITextView()
        private let diagnostics = UILabel()
        override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .allButUpsideDown }
        override func viewDidLoad() {
            super.viewDidLoad()
            view.backgroundColor = .systemGroupedBackground
            let title = UILabel()
            title.text = "Тестовый хозяин · только Debug"
            title.font = .systemFont(ofSize: 17, weight: .semibold)
            let buttons = UIStackView()
            buttons.axis = .horizontal
            buttons.spacing = 12
            for (name, action) in [
                ("Пустое", #selector(empty)), ("С выделением", #selector(seed)), ("Скрыть", #selector(hide)),
                ("Открыть", #selector(showKeyboard)),
            ] {
                let button = UIButton(type: .system)
                button.setTitle(name, for: .normal)
                button.addTarget(self, action: action, for: .touchUpInside)
                buttons.addArrangedSubview(button)
            }
            field.font = .systemFont(ofSize: 17)
            field.backgroundColor = .secondarySystemGroupedBackground
            field.accessibilityIdentifier = "host.editor"
            field.delegate = self
            field.autocorrectionType = .no
            diagnostics.numberOfLines = 3
            diagnostics.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
            diagnostics.accessibilityIdentifier = "host.diagnostics"
            let stack = UIStackView(arrangedSubviews: [title, buttons, diagnostics, field])
            stack.axis = .vertical
            stack.spacing = 8
            stack.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(stack)
            NSLayoutConstraint.activate([
                stack.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
                stack.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
                stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
                field.heightAnchor.constraint(equalToConstant: 48),
            ])
            seed()
        }
        @objc private func empty() { field.text = ""; field.selectedRange = NSRange(location: 0, length: 0); update() }
        @objc private func seed() {
            field.text = "До встречи!"; field.selectedRange = NSRange(location: 3, length: 7); update()
        }
        @objc private func hide() { field.resignFirstResponder() }
        @objc private func showKeyboard() { field.becomeFirstResponder() }
        private func update() {
            diagnostics.text =
                "Текст: \(field.text ?? "")\nВыделение UTF-16: \(field.selectedRange.location), \(field.selectedRange.length)"
        }
        func textViewDidChange(_ textView: UITextView) { update() }
        func textViewDidChangeSelection(_ textView: UITextView) { update() }
    }
#endif
