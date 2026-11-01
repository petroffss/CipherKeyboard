#if canImport(UIKit)
    import CipherCore
    import UIKit

    /// Reads shared stores only behind Full Access. Plaintext editing has no document-proxy capability.
    open class KeyboardExtensionController: UIInputViewController {
        public let panel = KeyboardPanel()
        private var panelHeight: NSLayoutConstraint?

        public override func viewDidLoad() {
            super.viewDidLoad()
            #if DEBUG
                panel.debugBuild =
                    Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unversioned"
            #endif
            panel.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(panel)
            NSLayoutConstraint.activate([
                panel.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                panel.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                panel.topAnchor.constraint(equalTo: view.topAnchor),
                panel.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            ])
            let height = view.heightAnchor.constraint(equalToConstant: 320)
            height.priority = .init(999)
            height.isActive = true
            panelHeight = height
            panel.heightChanged = { [weak self] height in
                guard let self else { return }
                self.panelHeight?.constant = height + self.view.safeAreaInsets.bottom
            }
            panel.nextKeyboardButton.addTarget(self, action: #selector(nextKeyboard(_:event:)), for: .allTouchEvents)
            NotificationCenter.default.addObserver(
                self, selector: #selector(clearSession), name: .NSExtensionHostWillResignActive,
                object: nil)
            NotificationCenter.default.addObserver(
                self, selector: #selector(clearSession), name: .NSExtensionHostDidEnterBackground,
                object: nil)
        }

        public override func viewWillAppear(_ animated: Bool) {
            super.viewWillAppear(animated)
            let permitted = hasFullAccess
            KeyboardAccessRecorder.record(hasFullAccess: permitted) { FileKeyboardSetupStorage.appGroup }
            let status = KeyboardSharedStatus.read(hasFullAccess: permitted)
            panel.statusText = status.identity
            panel.contactsText = status.contacts
            #if DEBUG
                if let fixture = ProcessInfo.processInfo.environment["CIPHER_TYPING_FIXTURE"] {
                    KeyboardDebugFixture.apply(to: panel, name: fixture)
                }
            #endif
        }
        public override func viewWillDisappear(_ animated: Bool) {
            super.viewWillDisappear(animated)
            clearSession()
        }
        public override func viewWillTransition(
            to size: CGSize, with coordinator: any UIViewControllerTransitionCoordinator
        ) {
            panel.adapter.rotate()
            super.viewWillTransition(to: size, with: coordinator)
        }
        public override func viewWillLayoutSubviews() {
            super.viewWillLayoutSubviews()
            panel.showsNextKeyboard = needsInputModeSwitchKey
            panel.landscape = view.window?.windowScene?.interfaceOrientation.isLandscape ?? (view.bounds.width > 600)
            panelHeight?.constant = panel.panelHeight + view.safeAreaInsets.bottom
        }
        @objc private func clearSession() { panel.clearSession() }
        @objc private func nextKeyboard(_ sender: UIButton, event: UIEvent) {
            clearSession()
            handleInputModeList(from: sender, with: event)
        }
    }
#endif
