#if canImport(UIKit)
    import CipherCore
    import UIKit

    /// Reads shared stores only behind Full Access. Plaintext editing has no document-proxy capability.
    open class KeyboardExtensionController: UIInputViewController, CiphertextHost {
        private var coordinator: EncryptInsertCoordinator!
        private var decrypt: DecryptCoordinator!
        private var activeDocument: UUID?
        private let privacyShield = UIView()
        public var documentIdentifier: UUID { textDocumentProxy.documentIdentifier }
        public var hasSelection: Bool { !(textDocumentProxy.selectedText ?? "").isEmpty }
        public func insertCiphertext(_ ciphertext: String) { textDocumentProxy.insertText(ciphertext) }
        public let panel = KeyboardPanel()
        private var panelHeight: NSLayoutConstraint?
        private var observedFullAccess: Bool?

        public override func viewDidLoad() {
            super.viewDidLoad()
            #if DEBUG
                panel.debugHost = self
                panel.debugAccess = { [weak self] in self?.hasFullAccess == true }
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
            #if DEBUG
                let faults = panel.debugFaults
                coordinator = EncryptInsertCoordinator(
                    adapter: panel.adapter, host: self, preference: LocalRecipientPreference(),
                    access: { [weak self] in self?.hasFullAccess == true },
                    seal: { text, sender, recipient in try await faults.seal(text, sender: sender, recipient: recipient)
                    })
            #else
                coordinator = EncryptInsertCoordinator(
                    adapter: panel.adapter, host: self, preference: LocalRecipientPreference(),
                    access: { [weak self] in self?.hasFullAccess == true })
            #endif
            panel.enableEncryption(coordinator)
            decrypt = DecryptCoordinator(
                surface: .keyboard,
                access: { [weak self] in self?.hasFullAccess == true }, clipboard: SystemDecryptClipboard(),
                blocked: { [weak self] in self?.coordinator?.busy == true },
                document: { [weak self] in self?.documentIdentifier ?? UUID() })
            panel.enableDecryption(decrypt)
            privacyShield.backgroundColor = .systemGroupedBackground
            privacyShield.isUserInteractionEnabled = false; privacyShield.isHidden = true
            view.addSubview(privacyShield)
            panel.nextKeyboardButton.addTarget(self, action: #selector(nextKeyboard(_:event:)), for: .allTouchEvents)
            NotificationCenter.default.addObserver(
                self, selector: #selector(activateSession), name: .NSExtensionHostDidBecomeActive, object: nil)
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
            panel.statusIsWarning = status.isWarning
            panel.enableEncryption(coordinator)
            if panel.decryption !== decrypt { panel.enableDecryption(decrypt) }
            coordinator.open()
            activeDocument = documentIdentifier; decrypt.activate(); privacyShield.isHidden = true
            #if DEBUG
                if let fixture = ProcessInfo.processInfo.environment["CIPHER_TYPING_FIXTURE"] {
                    KeyboardDebugFixture.apply(to: panel, name: fixture)
                }
            #endif
        }
        public override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            activateSession()
        }
        @objc private func activateSession() {
            guard isViewLoaded else { return }
            if panel.encryption !== coordinator { panel.enableEncryption(coordinator) }
            if panel.decryption !== decrypt { panel.enableDecryption(decrypt) }
            coordinator.open()
            activeDocument = documentIdentifier; decrypt.activate(); privacyShield.isHidden = true
        }
        public override func viewWillDisappear(_ animated: Bool) {
            super.viewWillDisappear(animated)
            clearSession()
        }
        public override func viewWillTransition(
            to size: CGSize, with coordinator: any UIViewControllerTransitionCoordinator
        ) {
            let reveal = panel.makeViewportTransitionReveal()
            panel.adapter.rotate()
            super.viewWillTransition(to: size, with: coordinator)
            coordinator.animate(alongsideTransition: nil) { [weak self] context in
                guard let self, !context.isCancelled else { return }
                self.view.layoutIfNeeded()
                reveal()
            }
        }
        public override func textDidChange(_ textInput: (any UITextInput)?) {
            super.textDidChange(textInput)
            guard isViewLoaded else { return }
            if let activeDocument, activeDocument != documentIdentifier {
                clearSession(); self.activeDocument = documentIdentifier
                coordinator.open(); decrypt.activate(); privacyShield.isHidden = true
            } else if decrypt?.active == true {
                decrypt.refresh()
            }
        }
        public override func viewWillLayoutSubviews() {
            super.viewWillLayoutSubviews()
            privacyShield.frame = view.bounds
            if let activeDocument, activeDocument != documentIdentifier {
                clearSession(); self.activeDocument = documentIdentifier
                coordinator.open(); decrypt.activate(); privacyShield.isHidden = true
            }
            if decrypt?.active == true, !hasFullAccess { decrypt.refresh() }
            // iOS can reuse the visible remote input view without another appearance notification.
            // Reconcile only transitions, so model onChange -> layout cannot form a refresh loop.
            if view.window != nil, let coordinator, panel.encryption === coordinator {
                if !coordinator.sessionActive { coordinator.open() }
                let currentAccess = hasFullAccess
                if observedFullAccess != currentAccess {
                    observedFullAccess = currentAccess
                    coordinator.refresh(); decrypt.refresh()
                }
            }
            panel.showsNextKeyboard = needsInputModeSwitchKey
            panel.landscape = view.window?.windowScene?.interfaceOrientation.isLandscape ?? (view.bounds.width > 600)
            panelHeight?.constant = panel.panelHeight + view.safeAreaInsets.bottom
        }
        @objc private func clearSession() {
            privacyShield.isHidden = false; view.bringSubviewToFront(privacyShield)
            panel.clearSession()
            #if DEBUG
                panel.debugFaults.delay = 0; panel.debugFaults.fails = false
            #endif
        }
        @objc private func nextKeyboard(_ sender: UIButton, event: UIEvent) {
            clearSession()
            handleInputModeList(from: sender, with: event)
        }
    }
#endif
