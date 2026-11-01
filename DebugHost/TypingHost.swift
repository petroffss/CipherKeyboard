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
        private let focus = UILabel()
        private let geometry = UILabel()
        private let auditClipboard = UILabel()
        private var controls: [String: UIButton] = [:]
        private weak var controlsStack: UIStackView?
        override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .allButUpsideDown }
        override func viewDidLoad() {
            super.viewDidLoad()
            let args = ProcessInfo.processInfo.arguments
            if let index = args.firstIndex(of: "-typing-theme"), args.indices.contains(index + 1) {
                overrideUserInterfaceStyle = args[index + 1] == "dark" ? .dark : .light
                field.keyboardAppearance = args[index + 1] == "dark" ? .dark : .light
            }
            view.backgroundColor = .systemGroupedBackground
            let title = UILabel()
            title.text = "Тестовый хозяин · только Debug"
            title.font = .systemFont(ofSize: 17, weight: .semibold)
            let buttons = UIStackView()
            controlsStack = buttons
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
                controls[name] = button
            }
            field.font = .systemFont(ofSize: 17)
            field.backgroundColor = .secondarySystemGroupedBackground
            field.accessibilityIdentifier = "host.editor"
            field.delegate = self
            field.autocorrectionType = .no
            diagnostics.numberOfLines = 3
            diagnostics.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
            diagnostics.accessibilityIdentifier = "host.diagnostics"
            focus.accessibilityIdentifier = "host.focus"
            focus.font = .systemFont(ofSize: 10)
            geometry.accessibilityIdentifier = "host.controlsGeometry"
            geometry.font = .systemFont(ofSize: 8)
            let stack = UIStackView(arrangedSubviews: [title, buttons, diagnostics, focus, geometry, field])
            stack.axis = .vertical
            if args.contains("-typing-audit-setup") {
                let sentinel = UIButton(type: .system)
                sentinel.setTitle("Установить тестовый sentinel", for: .normal)
                sentinel.accessibilityIdentifier = "host.setSentinel"
                sentinel.addAction(
                    UIAction { [weak self] _ in
                        // Explicit audit setup, never transports the keyboard draft.
                        UIPasteboard.general.string = "TypingClipboardSentinel05-20261101"
                        self?.auditClipboard.text =
                            "sentinel=\(UIPasteboard.general.string == "TypingClipboardSentinel05-20261101")"
                    }, for: .touchUpInside)
                auditClipboard.accessibilityIdentifier = "host.sentinelStatus"
                stack.insertArrangedSubview(sentinel, at: 1)
                stack.insertArrangedSubview(auditClipboard, at: 2)
            }
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
        override func viewDidLayoutSubviews() {
            super.viewDidLayoutSubviews()
            DispatchQueue.main.async { [weak self] in self?.publishGeometry() }
        }
        private func publishGeometry() {
            controlsStack?.layoutIfNeeded()
            let value =
                "width=\(view.bounds.width);height=\(view.bounds.height);"
                + controls.keys.sorted().compactMap { name -> String? in
                    guard let button = controls[name] else { return nil }
                    let rect = button.convert(button.bounds, to: view.window)
                    return "\(name)=\(rect.midX),\(rect.midY)"
                }.joined(separator: ";")
            if geometry.text != value { geometry.text = value }
        }
        @objc private func empty() { field.text = ""; field.selectedRange = NSRange(location: 0, length: 0); update() }
        @objc private func seed() {
            field.text = "До встречи!"; field.selectedRange = NSRange(location: 3, length: 7); update()
        }
        @objc private func hide() {
            let result = field.resignFirstResponder()
            focus.text = "hide=\(result); focused=\(field.isFirstResponder)"
        }
        @objc private func showKeyboard() {
            let result = field.becomeFirstResponder()
            focus.text = "show=\(result); focused=\(field.isFirstResponder)"
        }
        private func update() {
            diagnostics.text =
                "Текст: \(field.text ?? "")\nВыделение UTF-16: \(field.selectedRange.location), \(field.selectedRange.length)"
        }
        func textViewDidChange(_ textView: UITextView) { update() }
        func textViewDidChangeSelection(_ textView: UITextView) { update() }
    }
#endif
