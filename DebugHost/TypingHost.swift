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
        private let secondField = UITextView()
        private var secondActive = false
        private var activeField: UITextView { secondActive ? secondField : field }
        private let diagnostics = UILabel()
        private let trace = UILabel()
        private var insertions = 0
        private var deletions = 0
        private var replacements = 0
        private var lastCiphertext = ""
        private let focus = UILabel()
        private let geometry = UILabel()
        private let auditClipboard = UILabel()
        private var controls: [String: UIButton] = [:]
        private weak var controlsStack: UIStackView?
        private let hostTitle = UILabel()
        override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .allButUpsideDown }
        override func viewDidLoad() {
            super.viewDidLoad()
            let args = ProcessInfo.processInfo.arguments
            if let index = args.firstIndex(of: "-typing-theme"), args.indices.contains(index + 1) {
                overrideUserInterfaceStyle = args[index + 1] == "dark" ? .dark : .light
                field.keyboardAppearance = args[index + 1] == "dark" ? .dark : .light
            }
            view.backgroundColor = .systemGroupedBackground
            hostTitle.text = "Тестовый хозяин · только Debug"
            hostTitle.font = .systemFont(ofSize: 17, weight: .semibold)
            let buttons = UIStackView()
            controlsStack = buttons
            buttons.axis = .horizontal
            buttons.spacing = 8
            buttons.distribution = .fillEqually
            for (name, action) in [
                ("Пустое", #selector(empty)), ("С выделением", #selector(seed)), ("Скрыть", #selector(hide)),
                ("Открыть", #selector(showKeyboard)), ("Курсор", #selector(caret)), ("Поле2", #selector(switchField)),
            ] {
                let button = UIButton(type: .system)
                button.setTitle(name, for: .normal)
                button.addTarget(self, action: action, for: .touchUpInside)
                buttons.addArrangedSubview(button)
                controls[name] = button
            }
            secondField.font = .systemFont(ofSize: 17)
            secondField.backgroundColor = .secondarySystemGroupedBackground
            secondField.accessibilityIdentifier = "host.editor2"
            secondField.delegate = self; secondField.autocorrectionType = .no
            secondField.text = "Второе поле"; secondField.isHidden = true
            secondField.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(secondField)
            field.font = .systemFont(ofSize: 17)
            field.backgroundColor = .secondarySystemGroupedBackground
            field.accessibilityIdentifier = "host.editor"
            field.delegate = self
            field.autocorrectionType = .no
            trace.accessibilityIdentifier = "host.trace"
            trace.font = .monospacedSystemFont(ofSize: 8, weight: .regular)
            diagnostics.numberOfLines = 3
            diagnostics.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
            diagnostics.accessibilityIdentifier = "host.diagnostics"
            focus.accessibilityIdentifier = "host.focus"
            focus.font = .systemFont(ofSize: 10)
            geometry.accessibilityIdentifier = "host.controlsGeometry"
            geometry.font = .systemFont(ofSize: 8)
            // Keep controls and actual editable field above the keyboard even on 667×375.
            // Diagnostic labels remain available to AX, but cannot push the field under the panel.
            let details = UIStackView(arrangedSubviews: [focus, geometry, trace])
            details.spacing = 4
            details.distribution = .fillEqually
            focus.setContentCompressionResistancePriority(.required, for: .horizontal)
            geometry.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            let stack = UIStackView(arrangedSubviews: [hostTitle, buttons, diagnostics, details])
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
            stack.spacing = 2
            stack.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(stack)
            field.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(field)
            NSLayoutConstraint.activate([
                stack.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
                stack.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
                stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 4),
                buttons.heightAnchor.constraint(equalToConstant: 32),
                details.heightAnchor.constraint(equalToConstant: 12),
                field.leadingAnchor.constraint(equalTo: stack.leadingAnchor),
                field.trailingAnchor.constraint(equalTo: stack.trailingAnchor),
                field.topAnchor.constraint(greaterThanOrEqualTo: stack.bottomAnchor, constant: 4),
                field.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor, constant: -4),
                field.heightAnchor.constraint(equalToConstant: 48),
                secondField.leadingAnchor.constraint(equalTo: field.leadingAnchor),
                secondField.trailingAnchor.constraint(equalTo: field.trailingAnchor),
                secondField.topAnchor.constraint(equalTo: field.topAnchor),
                secondField.heightAnchor.constraint(equalTo: field.heightAnchor),
            ])
            seed()
        }
        override func viewDidLayoutSubviews() {
            super.viewDidLayoutSubviews()
            let landscape = view.bounds.width > view.bounds.height
            hostTitle.font = .systemFont(ofSize: landscape ? 14 : 17, weight: .semibold)
            diagnostics.numberOfLines = landscape ? 1 : 3
            diagnostics.font = .monospacedSystemFont(ofSize: landscape ? 10 : 12, weight: .regular)
            DispatchQueue.main.async { [weak self] in self?.publishGeometry() }
        }
        private func publishGeometry() {
            controlsStack?.layoutIfNeeded()
            let value =
                "width=\(view.bounds.width);height=\(view.bounds.height);"
                + "field=\(field.frame.minX),\(field.frame.minY),\(field.frame.width),\(field.frame.height);"
                + "keyboardTop=\(view.keyboardLayoutGuide.layoutFrame.minY);"
                + controls.keys.sorted().compactMap { name -> String? in
                    guard let button = controls[name] else { return nil }
                    let rect = button.convert(button.bounds, to: view.window)
                    return "\(name)=\(rect.midX),\(rect.midY)"
                }.joined(separator: ";")
            if geometry.text != value { geometry.text = value }
        }
        @objc private func empty() {
            resetTrace(); activeField.text = ""; activeField.selectedRange = NSRange(location: 0, length: 0); update()
        }
        @objc private func seed() {
            resetTrace(); activeField.text = "До встречи!"; activeField.selectedRange = NSRange(location: 3, length: 7);
            update()
        }
        @objc private func caret() { activeField.selectedRange = NSRange(location: 3, length: 0); update() }
        @objc private func switchField() {
            secondActive.toggle()
            field.isHidden = secondActive; secondField.isHidden = !secondActive
            activeField.becomeFirstResponder(); update()
        }
        @objc private func hide() {
            let result = activeField.resignFirstResponder()
            focus.text = "hide=\(result); focused=\(activeField.isFirstResponder)"
        }
        @objc private func showKeyboard() {
            let result = activeField.becomeFirstResponder()
            focus.text = "show=\(result); focused=\(activeField.isFirstResponder)"
        }
        private func resetTrace() { insertions = 0; deletions = 0; replacements = 0; lastCiphertext = "" }
        func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
            if text.isEmpty { deletions += 1 } else { insertions += 1 }
            if range.length > 0 { replacements += 1 }
            lastCiphertext = text
            trace.text =
                "insertions=\(insertions);deletions=\(deletions);replacements=\(replacements);ciphertext=\(text.hasPrefix("ckmsg1:"));length=\(text.utf8.count)"
            return true
        }
        private func update() {
            diagnostics.text =
                "Текст: \(activeField.text ?? "")\nВыделение UTF-16: \(activeField.selectedRange.location), \(activeField.selectedRange.length)"
        }
        func textViewDidChange(_ textView: UITextView) { update() }
        func textViewDidChangeSelection(_ textView: UITextView) { update() }
    }
#endif
