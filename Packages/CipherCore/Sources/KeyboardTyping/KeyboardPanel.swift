#if canImport(UIKit)
    import UIKit
    import CipherCore

    /// A display-only text view: never a text-input responder and never offers system editing interactions.
    /// TextKit provides wrapping/hit testing; all edits and cursor positions belong to KeyboardInput.
    @MainActor final class PrivateDraftView: UITextView {
        var cursorTapped: ((Int) -> Void)?
        private let caret = UIView()
        override var canBecomeFirstResponder: Bool { false }
        override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool { false }
        init() {
            let storage = NSTextStorage()
            let manager = NSLayoutManager()
            let container = NSTextContainer(size: .zero)
            storage.addLayoutManager(manager)
            manager.addTextContainer(container)
            super.init(frame: .zero, textContainer: container)
            // This private editor has no bar covering its content. iOS 26's automatic
            // scroll-edge material otherwise fades the top line of a short text view.
            if #available(iOS 26.0, *) {
                topEdgeEffect.isHidden = true
                bottomEdgeEffect.isHidden = true
                leftEdgeEffect.isHidden = true
                rightEdgeEffect.isHidden = true
            }
            contentInsetAdjustmentBehavior = .never
            isEditable = false
            isSelectable = false
            textDragInteraction?.isEnabled = false
            if let drop = textDropInteraction { removeInteraction(drop) }
            autocorrectionType = .no
            spellCheckingType = .no
            smartQuotesType = .no
            smartDashesType = .no
            smartInsertDeleteType = .no
            if #available(iOS 18.0, *) { writingToolsBehavior = .none }
            font = .systemFont(ofSize: 17)
            textContainerInset = UIEdgeInsets(top: 8, left: 5, bottom: 8, right: 5)
            layer.cornerRadius = 9
            backgroundColor = .secondarySystemGroupedBackground
            accessibilityIdentifier = "keyboard.editor"
            accessibilityLabel = "Черновик"
            accessibilityTraits = [.staticText]
            caret.backgroundColor = KeyboardPanel.accent
            caret.isUserInteractionEnabled = false
            addSubview(caret)
            addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tapped(_:))))
            panGestureRecognizer.addTarget(self, action: #selector(manualPanChanged(_:)))
            #if DEBUG
                delegate = self
            #endif
        }
        required init?(coder: NSCoder) { nil }
        private var draft = ""
        private var position = 0
        func display(_ input: KeyboardInput, landscape: Bool, secondaryColor: UIColor = .secondaryLabel) {
            draft = input.text
            position = input.cursor
            textContainerInset.top = landscape ? 4 : 8
            textContainerInset.bottom = landscape ? 4 : 8
            let displayed = draft.isEmpty ? "Текст будет зашифрован" : draft
            if text != displayed { text = displayed }
            textColor = draft.isEmpty ? secondaryColor : .label
            accessibilityValue = draft
            setNeedsLayout()
        }
        var measuredHeight: CGFloat {
            sizeThatFits(CGSize(width: bounds.width, height: .greatestFiniteMagnitude)).height
        }
        var requiresFourLineViewport: Bool {
            guard !draft.isEmpty else { return false }
            layoutManager.ensureLayout(for: textContainer)
            var lines = 0
            layoutManager.enumerateLineFragments(
                forGlyphRange: NSRange(location: 0, length: layoutManager.numberOfGlyphs)
            ) { _, _, _, _, stop in
                lines += 1
                if lines >= 4 { stop.pointee = true }
            }
            if layoutManager.extraLineFragmentRect.height > 0 { lines += 1 }
            return lines >= 4
        }
        override func layoutSubviews() {
            super.layoutSubviews()
            layoutManager.ensureLayout(for: textContainer)
            let offset = String(draft.prefix(position)).utf16.count
            var rect: CGRect
            if offset >= textStorage.length && !draft.isEmpty {
                if draft.hasSuffix("\n") {
                    rect = layoutManager.extraLineFragmentRect
                } else {
                    let glyph = layoutManager.glyphIndexForCharacter(at: max(0, offset - 1))
                    let box = layoutManager.boundingRect(
                        forGlyphRange: NSRange(location: glyph, length: 1), in: textContainer)
                    rect = CGRect(x: box.maxX, y: box.minY, width: 2, height: 22)
                }
            } else {
                let glyph = layoutManager.glyphIndexForCharacter(at: offset)
                rect = layoutManager.boundingRect(forGlyphRange: NSRange(location: glyph, length: 1), in: textContainer)
            }
            caret.frame = CGRect(
                x: rect.minX + textContainerInset.left, y: rect.minY + textContainerInset.top,
                width: 2, height: 22)
            #if DEBUG
                let requested = needsScrollToCaret
            #endif
            if needsScrollToCaret {
                needsScrollToCaret = false
                scrollRectToVisible(caret.frame.insetBy(dx: -4, dy: -2), animated: false)
            }
            #if DEBUG
                debugLayoutSamples.append([
                    "requested": requested ? 1 : 0, "width": bounds.width, "height": bounds.height,
                    "contentHeight": contentSize.height, "offsetY": contentOffset.y,
                    "caretMinY": caret.frame.minY, "caretMaxY": caret.frame.maxY,
                ])
                if debugLayoutSamples.count > 8 { debugLayoutSamples.removeFirst() }
                viewportDidLayout?()
            #endif
        }
        var needsScrollToCaret = true
        private(set) var manualScrollEpoch: UInt64 = 0
        var isModelCaretVisible: Bool { bounds.insetBy(dx: -0.5, dy: -0.5).contains(caret.frame) }
        @objc private func manualPanChanged(_ gesture: UIPanGestureRecognizer) {
            if gesture.state == .began || gesture.state == .changed { manualScrollEpoch &+= 1 }
        }
        #if DEBUG
            var viewportDidLayout: (() -> Void)?
            private(set) var debugLayoutSamples: [[String: CGFloat]] = []
            var debugCaretFrame: CGRect { caret.frame }
            var debugCaretVisible: Bool {
                isModelCaretVisible
            }
        #endif
        @objc private func tapped(_ gesture: UITapGestureRecognizer) {
            guard !draft.isEmpty else { cursorTapped?(0); return }
            var point = gesture.location(in: self)
            point.x -= textContainerInset.left
            point.y -= textContainerInset.top
            var fraction: CGFloat = 0
            let raw = layoutManager.characterIndex(
                for: point, in: textContainer, fractionOfDistanceBetweenInsertionPoints: &fraction)
            let target = min(draft.utf16.count, raw + (fraction > 0.5 ? 1 : 0))
            var boundaries = [0]
            for character in draft { boundaries.append((boundaries.last ?? 0) + String(character).utf16.count) }
            let nearest =
                boundaries.enumerated().min { abs($0.element - target) < abs($1.element - target) }?.offset ?? 0
            cursorTapped?(nearest)
        }
    }

    #if DEBUG
        extension PrivateDraftView: UITextViewDelegate {
            func scrollViewDidScroll(_ scrollView: UIScrollView) { viewportDidLayout?() }
        }
    #endif

    @MainActor final class DraftKey: UIButton {
        let action: KeyboardAction
        weak var adapter: KeyboardInputAdapter?
        private var cancelled = false
        private var token: UUID?
        init(action: KeyboardAction, adapter: KeyboardInputAdapter) {
            self.action = action
            self.adapter = adapter
            super.init(frame: .zero)
            layer.cornerRadius = 5
            layer.shadowColor = UIColor.black.cgColor
            layer.shadowOpacity = 0.25
            layer.shadowOffset = CGSize(width: 0, height: 1)
            layer.shadowRadius = 0
            accessibilityTraits = .button
        }
        required init?(coder: NSCoder) { nil }
        override func beginTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
            cancelled = false
            token = adapter?.press(action)
            isHighlighted = true
            return true
        }
        override func continueTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
            if !bounds.contains(touch.location(in: self)) {
                cancelled = true
                if let token { adapter?.cancelGesture(token) }
                token = nil
                isHighlighted = false
            }
            return true
        }
        override func endTracking(_ touch: UITouch?, with event: UIEvent?) {
            let inside = touch.map { bounds.contains($0.location(in: self)) } ?? false
            if let token { adapter?.release(token, inside: inside && !cancelled) }
            token = nil
            isHighlighted = false
        }
        override func cancelTracking(with event: UIEvent?) {
            if let token { adapter?.cancelGesture(token) }
            token = nil
            isHighlighted = false
        }
        override func accessibilityActivate() -> Bool { adapter?.activate(action); return true }
    }

    /// Shared production panel, embedded unchanged in the extension and the app preview.
    @MainActor public final class KeyboardPanel: UIView {
        public let adapter: KeyboardInputAdapter
        public private(set) var encryption: EncryptInsertCoordinator?
        private var encryptionControls: EncryptionControls?
        public func enableEncryption(_ coordinator: EncryptInsertCoordinator) {
            viewportTransitionEpoch = UUID()
            encryption = coordinator
            let controls = EncryptionControls(coordinator: coordinator)
            encryptionControls?.removeFromSuperview()
            encryptionControls = controls
            addSubview(controls)
            coordinator.onChange = { [weak self] in self?.refresh() }
            refresh()
        }
        public private(set) var decryption: DecryptCoordinator?
        private let decryptButton = UIButton(type: .system)
        private let decryptNotice = UILabel()
        private let decryptPanel = PrivateDecryptPanel(prefix: "keyboard.decrypt")
        public func enableDecryption(_ model: DecryptCoordinator) {
            decryption?.deactivate()
            decryption = model
            decryptButton.removeAction(identifiedBy: UIAction.Identifier("decrypt.start"), for: .touchUpInside)
            decryptButton.setTitle("Расшифровать", for: .normal)
            decryptButton.accessibilityIdentifier = "keyboard.decrypt"
            decryptButton.titleLabel?.font = .systemFont(ofSize: 15, weight: .semibold)
            decryptButton.layer.cornerRadius = 9; decryptButton.layer.borderWidth = 1
            decryptButton.addAction(
                UIAction(identifier: UIAction.Identifier("decrypt.start")) { [weak model] _ in model?.start() },
                for: .touchUpInside)
            decryptNotice.numberOfLines = 0; decryptNotice.font = .systemFont(ofSize: 11)
            decryptNotice.textColor = .secondaryLabel
            decryptPanel.onClose = { [weak self, weak model] in
                model?.close()
                if let button = self?.decryptButton {
                    UIAccessibility.post(notification: .screenChanged, argument: button)
                }
            }
            addSubview(decryptButton); addSubview(decryptNotice); addSubview(decryptPanel)
            encryption?.externallyBlocked = { [weak model] in model?.presenting == true }
            model.onChange = { [weak self, weak model] in
                guard let self else { return }
                self.adapter.cancelGesture()
                self.adapter.interactionEnabled = model?.presenting != true && self.encryption?.busy != true
                self.refresh()
            }
            refresh()
        }
        public let nextKeyboardButton = UIButton(type: .system)
        public var heightChanged: ((CGFloat) -> Void)?
        public var statusText = "" { didSet { refresh() } }
        public var contactsText: String? { didSet { refresh() } }
        public var statusIsWarning = false { didSet { setNeedsLayout() } }
        public var showsNextKeyboard = false { didSet { if oldValue != showsNextKeyboard { rebuildKeys() } } }
        public var landscape = false { didSet { if oldValue != landscape { adapter.rotate(); setNeedsLayout() } } }
        public private(set) var panelHeight: CGFloat = 319
        #if DEBUG
            let debugFaults = KeyboardEncryptFaults()
            weak var debugHost: (any CiphertextHost)?
            var debugAccess: (() -> Bool)?
            var debugEncryptionContext: KeyboardEncryptFixture.Context?
            public var debugFixture = "" { didSet { updateDebugMetadata() } }
            public var debugBuild = "unversioned" { didSet { updateDebugMetadata() } }
            private let debugFixtureButton = UIButton(type: .system)
            private var debugPicker: UIView?
            private var debugChoices: [UIButton] = []
            @objc private func showDebugFixtures() {
                guard debugPicker == nil else { dismissDebugFixtures(); return }
                adapter.cancelGesture()
                let picker = UIView()
                picker.backgroundColor = .secondarySystemGroupedBackground
                picker.accessibilityIdentifier = "keyboard.fixtureGrid"
                let names = [
                    "dec-idle", "dec-busy", "dec-contact", "dec-self", "dec-unknown", "dec-long", "dec-no-message",
                    "dec-corrupt", "dec-foreign", "dec-version", "dec-paste-error", "dec-no-access", "dec-no-key",
                    "dec-key-error", "dec-contacts-warning", "dec-changed", "dec-oversize", "dec-generic",
                    "ru-empty", "ru-text", "shift", "caps", "en", "numbers", "symbols", "alternate-e",
                    "alternate-softsign", "multiline", "limit", "preview", "no-access", "no-key",
                    "key-error", "contacts-error", "clear", "canary",
                    "enc-delay", "enc-fault", "enc-normal", "enc-canary", "enc-bytes4096", "enc-proof-unicode",
                    "enc-unselected",
                    "enc-empty", "enc-ready", "enc-picker", "enc-no-contacts",
                    "enc-sending",
                    "enc-success", "enc-limit", "enc-no-key", "enc-key-error", "enc-contacts-error", "enc-no-access",
                    "enc-changed", "enc-selection", "enc-failure", "enc-document-changed", "enc-long-name",
                    "enc-proof-decrypt",
                ]
                debugChoices = names.map { name in
                    let button = UIButton(type: .system)
                    button.setTitle(name, for: .normal)
                    button.titleLabel?.font = .systemFont(ofSize: 12)
                    button.accessibilityIdentifier = "keyboard.fixture." + name
                    button.addAction(
                        UIAction { [weak self] _ in
                            guard let self else { return }
                            // Remove the entire picker before applying a fixture or starting a timer.
                            self.dismissDebugFixtures()
                            KeyboardDebugFixture.apply(to: self, name: name)
                        }, for: .touchUpInside)
                    picker.addSubview(button)
                    return button
                }
                debugPicker = picker
                addSubview(picker)
                setNeedsLayout()
            }
            private func dismissDebugFixtures() {
                debugPicker?.removeFromSuperview()
                debugPicker = nil
                debugChoices.removeAll()
            }
            public func disableEncryptionForTesting() {
                decryption?.deactivate(); decryptPanel.clear(); decryptPanel.isHidden = true
                decryptButton.isHidden = true; decryptNotice.isHidden = true
                encryption?.hide(); encryption = nil
                encryptionControls?.removeFromSuperview(); encryptionControls = nil
                error.isHidden = false; status.isHidden = false; caption.isHidden = false; editor.isHidden = false;
                meter.isHidden = false
                for key in rows.flatMap({ $0 }) { key.isHidden = false; key.isEnabled = true }
                editor.isUserInteractionEnabled = true; refresh()
            }
            private func updateDebugMetadata() {
                status.accessibilityValue = "build=\(debugBuild);" + debugFixture
                debugFixtureButton.accessibilityLabel = "Debug fixtures;build=\(debugBuild);" + debugFixture
            }
            private func updateCaptureMetadata(lineHeight: CGFloat, synchronizeEditor: Bool = true) {
                if synchronizeEditor { editor.layoutIfNeeded() }
                var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
                status.textColor.resolvedColor(with: traitCollection).getRed(
                    &red, green: &green, blue: &blue, alpha: &alpha)
                var values: [String: Any] = [
                    "resolvedTheme": traitCollection.userInterfaceStyle == .dark ? "dark" : "light",
                    "warning": statusIsWarning, "statusFont": status.font.pointSize,
                    "statusLineHeight": lineHeight, "statusColor": [red, green, blue, alpha],
                    "caretVisible": editor.debugCaretVisible, "cursor": adapter.input.cursor,
                    "byteCount": adapter.input.byteCount,
                    "systemFullAccess": debugAccess?() ?? false,
                    "modelFullAccess": encryption?.permitted ?? false,
                    "sessionActive": encryption?.sessionActive ?? false,
                    "encryptionStatus": encryption?.status ?? "typing-only",
                ]
                values["encryption"] = encryptionControls?.captureMetadata
                values["decryptClipboardMetadataReads"] = DecryptDebugMetrics.metadataReads
                values["decryptClipboardContentReads"] = DecryptDebugMetrics.contentReads
                values["decryptLiveCoordinators"] = DecryptDebugLifetime.liveCoordinators
                values["decryptLiveOperations"] = DecryptDebugLifetime.liveOperations
                values["decryptBusy"] = decryption?.busy ?? false
                values["decryptPresenting"] = decryption?.presenting ?? false
                values["counterMaxY"] = meter.frame.maxY
                values["editorViewportWidth"] = editor.bounds.width
                values["editorViewportHeight"] = editor.bounds.height
                values["editorOffsetY"] = editor.contentOffset.y
                values["editorContentHeight"] = editor.contentSize.height
                values["editorSystemSelection"] = editor.selectedRange.location
                values["editorCaretMinY"] = editor.debugCaretFrame.minY
                values["editorCaretMaxY"] = editor.debugCaretFrame.maxY
                values["editorNeedsScroll"] = editor.needsScrollToCaret
                values["editorLayoutSamples"] = editor.debugLayoutSamples
                values["viewportTransitionState"] = viewportTransitionState
                if let data = try? JSONSerialization.data(withJSONObject: values, options: [.sortedKeys]) {
                    debugFixtureButton.accessibilityValue = String(data: data, encoding: .utf8)
                }
            }
        #endif
        private let status = UILabel()
        private let caption = UILabel()
        private let editor = PrivateDraftView()
        private let meter = UILabel()
        private let error = UILabel()
        private let popup = UILabel()
        private var viewportTransitionEpoch = UUID()
        #if DEBUG
            private var viewportTransitionState = "idle"
        #endif
        private var rows: [[DraftKey]] = []
        private var signature = ""
        private var lastSize = CGSize.zero
        public static var accent: UIColor {
            UIColor {
                $0.userInterfaceStyle == .dark
                    ? UIColor(red: 0.357, green: 0.549, blue: 1, alpha: 1)
                    : UIColor(red: 0.184, green: 0.357, blue: 0.918, alpha: 1)
            }
        }
        static var danger: UIColor { color(0xD92D20, 0xFF6961) }
        static var encryptionSecondary: UIColor { color(0x6C6C70, 0x98989F) }
        static var encryptionSeparator: UIColor { color(0xC6C6C8, 0x38383A) }
        private static func color(_ light: UInt32, _ dark: UInt32) -> UIColor {
            UIColor { traits in
                let hex = traits.userInterfaceStyle == .dark ? dark : light
                return UIColor(
                    red: CGFloat((hex >> 16) & 255) / 255, green: CGFloat((hex >> 8) & 255) / 255,
                    blue: CGFloat(hex & 255) / 255, alpha: 1)
            }
        }
        public init(adapter: KeyboardInputAdapter = KeyboardInputAdapter()) {
            self.adapter = adapter
            super.init(frame: .zero)
            accessibilityIdentifier = "keyboard.panel"
            backgroundColor = Self.color(0xD1D5DB, 0x24262B)
            status.textColor = .secondaryLabel
            status.numberOfLines = 2
            status.accessibilityIdentifier = "keyboard.identityStatus"
            caption.text = "Черновик · стирается при закрытии"
            caption.textColor = .secondaryLabel
            caption.font = .systemFont(ofSize: 10)
            meter.textColor = .secondaryLabel
            meter.font = .systemFont(ofSize: 10)
            meter.accessibilityIdentifier = "keyboard.counter"
            error.textColor = .systemRed
            error.font = .systemFont(ofSize: 10)
            error.accessibilityIdentifier = "keyboard.limitError"
            popup.backgroundColor = .secondarySystemGroupedBackground
            popup.textColor = Self.accent
            popup.textAlignment = .center
            popup.font = .systemFont(ofSize: 24)
            popup.layer.cornerRadius = 9
            popup.layer.borderWidth = 1
            popup.layer.borderColor = Self.accent.cgColor
            popup.clipsToBounds = true
            popup.isHidden = true
            popup.accessibilityIdentifier = "keyboard.alternative"
            nextKeyboardButton.setImage(UIImage(systemName: "globe"), for: .normal)
            nextKeyboardButton.accessibilityLabel = "Следующая клавиатура"
            nextKeyboardButton.accessibilityIdentifier = "keyboard.next"
            nextKeyboardButton.tintColor = .label
            nextKeyboardButton.layer.cornerRadius = 5
            for item in [status, caption, editor, meter, error, nextKeyboardButton, popup] { addSubview(item) }
            #if DEBUG
                debugFixtureButton.isAccessibilityElement = true
                debugFixtureButton.accessibilityTraits = .button
                debugFixtureButton.accessibilityIdentifier = "keyboard.debugFixtures"
                updateDebugMetadata()
                debugFixtureButton.addTarget(self, action: #selector(showDebugFixtures), for: .touchUpInside)
                addSubview(debugFixtureButton)
                editor.viewportDidLayout = { [weak self] in
                    guard let self, self.encryption != nil else { return }
                    self.updateCaptureMetadata(lineHeight: self.status.font.lineHeight, synchronizeEditor: false)
                }
            #endif
            editor.cursorTapped = { [weak adapter] in adapter?.moveCursor(to: $0) }
            adapter.onChange = { [weak self] in self?.refresh() }
            rebuildKeys()
        }
        required init?(coder: NSCoder) { nil }
        public func clearSession() {
            viewportTransitionEpoch = UUID()
            #if DEBUG
                dismissDebugFixtures()
            #endif
            decryption?.deactivate(); decryptPanel.clear()
            if let encryption { encryption.hide() } else { adapter.hide() }
        }
        /// One post-transition reconciliation, cancelled by a new session/transition or manual scroll intent.
        func makeViewportTransitionReveal() -> @MainActor () -> Void {
            viewportTransitionEpoch = UUID()
            let epoch = viewportTransitionEpoch
            let previousSize = editor.bounds.size
            let manualEpoch = editor.manualScrollEpoch
            #if DEBUG
                viewportTransitionState = "scheduled"
            #endif
            var consumed = false
            return { [weak self] in
                guard let self, !consumed, self.viewportTransitionEpoch == epoch else { return }
                consumed = true
                #if DEBUG
                    defer {
                        self.updateCaptureMetadata(lineHeight: self.status.font.lineHeight, synchronizeEditor: false)
                    }
                #endif
                guard self.window != nil, !self.isHidden, let model = self.encryption,
                    model.sessionActive, !model.pickerOpen
                else {
                    #if DEBUG
                        self.viewportTransitionState = "inactive"
                    #endif
                    return
                }
                self.layoutIfNeeded()
                guard !self.editor.isHidden, self.editor.bounds.size != previousSize,
                    self.editor.manualScrollEpoch == manualEpoch,
                    !self.editor.isDragging, !self.editor.isDecelerating, !self.editor.isTracking
                else {
                    #if DEBUG
                        self.viewportTransitionState = "unchanged-or-manual"
                    #endif
                    return
                }
                // Repaint the final viewport once, including the already-visible caret branch.
                defer {
                    let rect = self.editor.bounds.offsetBy(
                        dx: -self.editor.textContainerInset.left, dy: -self.editor.textContainerInset.top)
                    if rect.origin.x.isFinite, rect.origin.y.isFinite,
                        rect.width.isFinite, rect.height.isFinite, rect.width > 0, rect.height > 0
                    {
                        let manager = self.editor.layoutManager
                        let glyphs = manager.glyphRange(
                            forBoundingRectWithoutAdditionalLayout: rect, in: self.editor.textContainer)
                        let count = manager.numberOfGlyphs
                        if glyphs.location != NSNotFound, glyphs.location >= 0, glyphs.length > 0,
                            glyphs.location < count, glyphs.length <= count - glyphs.location
                        {
                            manager.invalidateDisplay(forGlyphRange: glyphs)
                        }
                    }
                }
                guard !self.editor.isModelCaretVisible else {
                    #if DEBUG
                        self.viewportTransitionState = "already-visible"
                    #endif
                    return
                }
                self.editor.needsScrollToCaret = true
                self.editor.setNeedsLayout()
                self.editor.layoutIfNeeded()
                #if DEBUG
                    self.viewportTransitionState = self.editor.isModelCaretVisible ? "revealed" : "not-visible"
                #endif
            }
        }
        private func rebuildKeys() {
            for key in rows.flatMap({ $0 }) { key.removeFromSuperview() }
            let input = adapter.input
            rows = input.rows.map { $0.map { makeKey(.character($0)) } }
            rows[2].insert(makeKey(input.page == .letters ? .shift : .symbols), at: 0)
            rows[2].append(makeKey(.delete))
            rows.append([makeKey(.language), makeKey(.numbers), makeKey(.space), makeKey(.enter)])
            signature = "\(input.language)-\(input.page)"
            refresh()
        }
        private func makeKey(_ action: KeyboardAction) -> DraftKey {
            let key = DraftKey(action: action, adapter: adapter)
            addSubview(key)
            if case .character(let value) = action {
                key.accessibilityIdentifier = "keyboard.key.\(value)"
                if value == "е" || value == "ь" {
                    let alternative = value == "е" ? "ё" : "ъ"
                    key.accessibilityHint = "Удерживайте для \(alternative)"
                    key.accessibilityCustomActions = [
                        UIAccessibilityCustomAction(
                            name: "Ввести \(alternative)",
                            actionHandler: { [weak adapter] _ in
                                adapter?.activate(.character(alternative)); return true
                            })
                    ]
                }
            }
            return key
        }
        private func refresh() {
            let input = adapter.input
            if signature != "\(input.language)-\(input.page)" { rebuildKeys(); return }
            status.text = ([statusText] + [contactsText].compactMap { $0 }).filter { !$0.isEmpty }.joined(
                separator: " · ")
            let secondary: UIColor = encryption == nil ? .secondaryLabel : Self.encryptionSecondary
            caption.textColor = secondary; meter.textColor = secondary
            editor.display(input, landscape: landscape, secondaryColor: secondary)
            #if DEBUG
                editor.accessibilityHint = "cursor=\(input.cursor);timers=\(adapter.activeTimerCount)"
            #endif
            editor.needsScrollToCaret = true
            meter.text = input.counter
            error.text = input.limitError ? KeyboardInput.limitMessage : nil
            for key in rows.flatMap({ $0 }) {
                var special = true
                let title: String
                let label: String
                let id: String
                switch key.action {
                case .character(let value):
                    title = input.uppercase && input.page == .letters ? value.uppercased() : value
                    label = title; id = "key.\(value)"; special = false
                case .delete: title = "⌫"; label = "Удалить"; id = "delete"
                case .shift:
                    title = input.shift == .caps ? "⇪" : "⇧"; label = "Регистр"; id = "shift"
                    key.accessibilityValue =
                        input.shift == .caps ? "Caps Lock" : (input.uppercase ? "Заглавные" : "Строчные")
                case .language:
                    title = input.language == .russian ? "РУС" : "ENG"; label = "Сменить язык"; id = "language"
                case .numbers:
                    title = input.page == .letters ? "123" : (input.language == .russian ? "АБВ" : "ABC");
                    label = input.page == .letters ? "Цифры" : "Буквы"; id = "numbers"
                case .symbols:
                    title = input.page == .symbols ? "123" : "#+=";
                    label = input.page == .symbols ? "Цифры" : "Символы"; id = "symbols"
                case .space: title = "пробел"; label = "Пробел"; id = "space"; special = false
                case .enter: title = "↵"; label = "Новая строка"; id = "return"
                }
                key.setTitle(title, for: .normal)
                key.accessibilityLabel = label
                key.accessibilityIdentifier = "keyboard.\(id)"
                let activeShift = key.action == .shift && input.uppercase
                key.backgroundColor =
                    activeShift
                    ? .secondarySystemGroupedBackground
                    : (special
                        ? Self.color(encryption == nil ? 0xADB4BF : 0xADB4C0, encryption == nil ? 0x32343B : 0x303035)
                        : Self.color(0xFFFFFF, encryption == nil ? 0x45474E : 0x505056))
                key.setTitleColor(activeShift ? Self.accent : .label, for: .normal)
            }
            if let encryption {
                encryptionControls?.refresh()
                status.text = encryption.identityMetadata
                caption.text = "Черновик · стирается при закрытии"
                for key in rows.flatMap({ $0 }) {
                    key.isEnabled = !encryption.busy && !encryption.pickerOpen
                    key.accessibilityTraits = key.isEnabled ? .button : [.button, .notEnabled]
                }
                editor.isUserInteractionEnabled = !encryption.busy && !encryption.pickerOpen
            }
            popup.isHidden = adapter.alternative == nil
            popup.text = adapter.alternative.map { input.uppercase ? $0.uppercased() : $0 }
            popup.accessibilityLabel = popup.text
            nextKeyboardButton.isHidden = !showsNextKeyboard
            nextKeyboardButton.backgroundColor = Self.color(
                encryption == nil ? 0xADB4BF : 0xADB4C0, encryption == nil ? 0x32343B : 0x303035)
            bringSubviewToFront(popup)
            setNeedsLayout()
        }
        private func layoutEncryption(_ model: EncryptInsertCoordinator, controls: EncryptionControls) {
            backgroundColor = .systemGroupedBackground
            // Internal CSS padding; the system already frames this panel in the native input surface.
            let side: CGFloat = landscape ? 44 : 6
            let available = bounds.width - side * 2
            // 11 Russian keys retain at least 26pt even on the narrow 667pt landscape profile.
            let keyWidth: CGFloat = landscape ? max(352, (available - 12) / 1.75) : available
            let composeWidth = landscape ? available - keyWidth - 12 : available
            let hasDecrypt = decryption != nil
            let height: CGFloat = landscape ? (hasDecrypt ? 240 : 198) : 420
            let metadataY: CGFloat = (landscape ? 12 : 6) + (hasDecrypt ? 38 : 0)
            status.font = .systemFont(ofSize: landscape ? 10 : 11)
            status.textColor = Self.encryptionSecondary
            status.numberOfLines = 1
            status.frame = CGRect(x: side + 4, y: metadataY, width: composeWidth - 8, height: 13)
            caption.frame = CGRect(x: side + 4, y: metadataY + 13, width: composeWidth - 8, height: 13)
            let rowY: CGFloat = hasDecrypt ? 44 : metadataY + 28
            controls.frame = bounds
            controls.layoutToolbar(x: side, y: rowY, width: composeWidth, landscape: landscape)
            let previousViewport = editor.bounds.size
            let initialHeight = previousViewport.height > 0 ? previousViewport.height : (landscape ? 38 : 48)
            editor.frame = CGRect(x: side, y: rowY + 46, width: composeWidth, height: initialHeight)
            let draftHeight: CGFloat
            if controls.showsRetry {
                draftHeight = 40
            } else if landscape {
                draftHeight = 38
            } else {
                let measured = editor.measuredHeight
                draftHeight =
                    editor.requiresFourLineViewport ? 100 : min(100, max(48, measured))
            }
            editor.frame.size.height = draftHeight
            if editor.bounds.size != previousViewport {
                // A refresh may have consumed the request against the old viewport before rotation settled.
                // Re-arm only for an actual final size change; ordinary/manual scrolling keeps its offset.
                editor.needsScrollToCaret = true
                editor.setNeedsLayout()
                editor.layoutIfNeeded()
            }
            let noticeY = rowY + (hasDecrypt ? 46 : 48) + draftHeight
            controls.layoutNotice(
                x: side, y: noticeY, width: composeWidth, height: landscape ? 52 : (hasDecrypt ? 38 : 44))
            // Counter has a permanent slot in the notice, regardless of byte count.
            meter.frame = CGRect(x: side + 4, y: noticeY, width: composeWidth - 8, height: 12)
            error.isHidden = true
            let keyHeight: CGFloat = landscape ? 32 : 44
            let keyX = landscape ? side + composeWidth + 12 : side
            var y: CGFloat = landscape ? 30 : height - 6 - 185
            for (index, row) in rows.enumerated() {
                let bottom = index == 3
                let hasGlobe = bottom && showsNextKeyboard
                let count = row.count + (hasGlobe ? 1 : 0)
                let specialWidth: CGFloat = 44
                let fixedCount = bottom ? 3 + (hasGlobe ? 1 : 0) : (index == 2 ? 2 : 0)
                let letter =
                    (keyWidth - CGFloat(count - 1) * 3 - CGFloat(fixedCount) * specialWidth)
                    / CGFloat(count - fixedCount)
                var x = keyX
                for (column, key) in row.enumerated() {
                    if hasGlobe && column == 2 {
                        nextKeyboardButton.frame = CGRect(x: x, y: y, width: 44, height: keyHeight); x += 47
                    }
                    let fixed = bottom ? key.action != .space : (index == 2 && (column == 0 || column == row.count - 1))
                    key.frame = CGRect(x: x, y: y, width: fixed ? specialWidth : letter, height: keyHeight)
                    key.titleLabel?.font = .systemFont(
                        ofSize: bottom || fixed ? (landscape ? 12 : 15) : (landscape ? 18 : 21))
                    key.isHidden = model.pickerOpen
                    x = key.frame.maxX + 3
                }
                y += keyHeight + 3
            }
            nextKeyboardButton.isHidden = !showsNextKeyboard || model.pickerOpen
            for view in [status, caption, editor, meter] {
                view.isHidden = model.pickerOpen || (hasDecrypt && (view === status || view === caption))
            }
            controls.layoutPicker(
                in: CGRect(x: side, y: 6, width: available, height: height - 12), landscape: landscape)
            if let alternate = adapter.alternative,
                let key = rows.flatMap({ $0 }).first(where: { $0.action == .character(alternate == "ё" ? "е" : "ь") })
            {
                popup.frame = CGRect(
                    x: max(side, min(bounds.width - side - 52, key.frame.midX - 26)), y: key.frame.minY - 46, width: 52,
                    height: 44)
            }
            bringSubviewToFront(controls)
            // Controls only intercept their own buttons/list; the draft and keys remain directly interactive.
            bringSubviewToFront(popup)
            #if DEBUG
                debugFixtureButton.frame =
                    hasDecrypt
                    ? CGRect(x: side + min(160, composeWidth), y: 0, width: max(0, composeWidth - 160), height: 44)
                    : status.frame
                if hasDecrypt && landscape {
                    debugFixtureButton.frame = CGRect(x: bounds.width - 44, y: 0, width: 44, height: 28)
                }
                bringSubviewToFront(debugFixtureButton)
                layoutDebugPicker()
                updateCaptureMetadata(lineHeight: status.font.lineHeight)
            #endif
            if let decrypt = decryption {
                decryptButton.frame = CGRect(x: side, y: 0, width: min(155, composeWidth), height: 44)
                decryptButton.isEnabled = decrypt.canStart && !model.pickerOpen
                decryptButton.tintColor = Self.accent
                decryptButton.layer.borderColor = Self.accent.cgColor
                decryptNotice.text = decrypt.permitted ? "Только по нажатию" : DecryptCoordinator.accessMessage
                if !decrypt.identityAvailable && decrypt.permitted { decryptNotice.text = decrypt.error }
                decryptNotice.frame =
                    landscape
                    ? CGRect(x: side + composeWidth + 12, y: 0, width: keyWidth, height: 28)
                    : CGRect(x: side + min(160, composeWidth), y: 0, width: max(0, composeWidth - 160), height: 44)
                decryptButton.isHidden = decrypt.presenting || model.pickerOpen
                decryptNotice.isHidden = decrypt.presenting || model.pickerOpen
                decryptPanel.isHidden = !decrypt.presenting
                if decrypt.presenting {
                    for view in [status, caption, editor, meter, error, popup, nextKeyboardButton] {
                        view.isHidden = true
                    }
                    for key in rows.flatMap({ $0 }) { key.isHidden = true }
                    controls.isHidden = true
                    decryptPanel.frame = CGRect(x: side, y: 6, width: available, height: height - 12)
                    decryptPanel.display(decrypt)
                    bringSubviewToFront(decryptPanel)
                    #if DEBUG
                        debugFixtureButton.frame = CGRect(x: bounds.width - 44, y: 0, width: 44, height: 44)
                        bringSubviewToFront(debugFixtureButton)
                    #endif
                } else {
                    controls.isHidden = false; decryptPanel.clear()
                }
            }
            #if DEBUG
                // The design picker must stay above a currently presented decrypt panel.
                layoutDebugPicker()
            #endif
            if panelHeight != height { panelHeight = height; heightChanged?(height) }
        }
        #if DEBUG
            private func layoutDebugPicker() {
                guard let picker = debugPicker else { return }
                picker.frame = bounds
                let columns = landscape ? 6 : 3
                let count = (debugChoices.count + columns - 1) / columns
                for (i, button) in debugChoices.enumerated() {
                    button.frame = CGRect(
                        x: CGFloat(i % columns) * bounds.width / CGFloat(columns),
                        y: CGFloat(i / columns) * bounds.height / CGFloat(count),
                        width: bounds.width / CGFloat(columns), height: bounds.height / CGFloat(count))
                }
                bringSubviewToFront(picker)
            }
        #endif
        public override func layoutSubviews() {
            super.layoutSubviews()
            if lastSize.width != bounds.width {
                if lastSize.width > 0 { adapter.rotate() }
                lastSize = bounds.size
            }
            if let encryption, let controls = encryptionControls {
                layoutEncryption(encryption, controls: controls)
                return
            }
            let side = max(5, safeAreaInsets.left, safeAreaInsets.right)
            let width = bounds.width - side * 2
            let gap: CGFloat = landscape ? 3 : 7
            let keyHeight: CGFloat = landscape ? 32 : 44
            var y: CGFloat = landscape ? 4 : 7
            let statusFont = UIFont.systemFont(ofSize: landscape ? 10 : (statusIsWarning ? 12 : 11))
            let statusColor: UIColor = statusIsWarning ? .label : .secondaryLabel
            status.font = statusFont
            status.textColor = statusColor
            let statusLineHeight: CGFloat = landscape ? 12 : 15
            if statusIsWarning {
                let paragraph = NSMutableParagraphStyle()
                paragraph.minimumLineHeight = statusLineHeight
                paragraph.maximumLineHeight = statusLineHeight
                status.attributedText = NSAttributedString(
                    string: status.text ?? "",
                    attributes: [
                        .font: statusFont, .foregroundColor: statusColor,
                        .paragraphStyle: paragraph,
                    ])
            } else {
                status.attributedText = nil
                status.text = ([statusText] + [contactsText].compactMap { $0 }).filter { !$0.isEmpty }.joined(
                    separator: " · ")
            }
            let statusHeight = max(
                landscape ? 14 : 18, status.sizeThatFits(CGSize(width: width - 10, height: 40)).height)
            status.frame = CGRect(x: side + 5, y: y, width: width - 10, height: statusHeight)
            #if DEBUG
                debugFixtureButton.frame = status.frame
            #endif
            y += statusHeight
            caption.frame = CGRect(x: side + 6, y: y, width: width - 12, height: landscape ? 14 : 16)
            y += landscape ? 14 : 16
            editor.frame = CGRect(x: side + 3, y: y, width: width - 6, height: 38)
            let editorHeight = landscape ? 30 : min(100, max(38, editor.measuredHeight))
            editor.frame.size.height = editorHeight
            y += editorHeight
            let meterHeight: CGFloat = landscape ? 18 : 32
            meter.frame = CGRect(x: side + 7, y: y + 2, width: width - 14, height: 13)
            error.frame = CGRect(x: side + 7, y: y + (landscape ? 2 : 15), width: width - 14, height: 13)
            if landscape { meter.frame.size.width = 130; error.frame.origin.x += 135; error.frame.size.width -= 135 }
            y += meterHeight
            for (index, row) in rows.enumerated() {
                let bottom = index == 3
                let hasGlobe = bottom && showsNextKeyboard
                let count = row.count + (hasGlobe ? 1 : 0)
                let specialWidth: CGFloat = landscape ? 52 : 44
                let specialCount = bottom ? 3 + (hasGlobe ? 1 : 0) : (index == 2 ? 2 : 0)
                let flexible = count - specialCount
                let letterWidth =
                    (width - CGFloat(count - 1) * 4 - CGFloat(specialCount) * specialWidth) / CGFloat(flexible)
                var x = side
                for (column, key) in row.enumerated() {
                    if hasGlobe && column == 2 {
                        nextKeyboardButton.frame = CGRect(x: x, y: y, width: specialWidth, height: keyHeight)
                        x += specialWidth + 4
                    }
                    let fixed = bottom ? key.action != .space : (index == 2 && (column == 0 || column == row.count - 1))
                    key.frame = CGRect(x: x, y: y, width: fixed ? specialWidth : letterWidth, height: keyHeight)
                    key.titleLabel?.font = .systemFont(
                        ofSize: bottom ? (landscape ? 13 : 14) : (fixed ? 16 : (landscape ? 18 : 22)))
                    x = key.frame.maxX + 4
                }
                y += keyHeight + (index == 3 ? 0 : gap)
            }
            if let alternate = adapter.alternative {
                let base = alternate == "ё" ? "е" : "ь"
                if let key = rows.flatMap({ $0 }).first(where: { $0.action == .character(base) }) {
                    popup.frame = CGRect(
                        x: max(side, min(bounds.width - side - 52, key.frame.midX - 26)),
                        y: max(0, key.frame.minY - 46), width: 52, height: 44)
                }
            }
            #if DEBUG
                if let picker = debugPicker {
                    picker.frame = bounds
                    let columns = landscape ? 6 : 3
                    let count = (debugChoices.count + columns - 1) / columns
                    let cellWidth = bounds.width / CGFloat(columns)
                    let cellHeight = bounds.height / CGFloat(count)
                    for (index, button) in debugChoices.enumerated() {
                        button.frame = CGRect(
                            x: CGFloat(index % columns) * cellWidth, y: CGFloat(index / columns) * cellHeight,
                            width: cellWidth, height: cellHeight)
                    }
                    bringSubviewToFront(picker)
                }
            #endif
            let height = y + (landscape ? 3 : 8)
            if abs(height - panelHeight) > 0.5 { panelHeight = height; heightChanged?(height) }
            #if DEBUG
                updateCaptureMetadata(lineHeight: statusIsWarning ? statusLineHeight : status.font.lineHeight)
            #endif
        }
    }
#endif
