#if canImport(UIKit)
    import UIKit

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
        }
        required init?(coder: NSCoder) { nil }
        private var draft = ""
        private var position = 0
        func display(_ input: KeyboardInput, landscape: Bool) {
            draft = input.text
            position = input.cursor
            textContainerInset.top = landscape ? 4 : 8
            textContainerInset.bottom = landscape ? 4 : 8
            let displayed = draft.isEmpty ? "Текст будет зашифрован" : draft
            if text != displayed { text = displayed }
            textColor = draft.isEmpty ? .secondaryLabel : .label
            accessibilityValue = draft
            setNeedsLayout()
        }
        var measuredHeight: CGFloat {
            sizeThatFits(CGSize(width: bounds.width, height: .greatestFiniteMagnitude)).height
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
            if needsScrollToCaret {
                needsScrollToCaret = false
                scrollRectToVisible(caret.frame.insetBy(dx: -4, dy: -2), animated: false)
            }
        }
        var needsScrollToCaret = true
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
        public let nextKeyboardButton = UIButton(type: .system)
        public var heightChanged: ((CGFloat) -> Void)?
        public var statusText = "" { didSet { refresh() } }
        public var contactsText: String? { didSet { refresh() } }
        public var showsNextKeyboard = false { didSet { if oldValue != showsNextKeyboard { rebuildKeys() } } }
        public var landscape = false { didSet { if oldValue != landscape { adapter.rotate(); setNeedsLayout() } } }
        public private(set) var panelHeight: CGFloat = 319
        #if DEBUG
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
                    "ru-empty", "ru-text", "shift", "caps", "en", "numbers", "symbols", "alternate-e",
                    "alternate-softsign", "multiline", "limit", "preview", "no-access", "no-key",
                    "key-error", "contacts-error", "clear", "canary",
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
            private func updateDebugMetadata() {
                status.accessibilityValue = "build=\(debugBuild);" + debugFixture
                debugFixtureButton.accessibilityLabel = "Debug fixtures;build=\(debugBuild);" + debugFixture
            }
        #endif
        private let status = UILabel()
        private let caption = UILabel()
        private let editor = PrivateDraftView()
        private let meter = UILabel()
        private let error = UILabel()
        private let popup = UILabel()
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
            #endif
            editor.cursorTapped = { [weak adapter] in adapter?.moveCursor(to: $0) }
            adapter.onChange = { [weak self] in self?.refresh() }
            rebuildKeys()
        }
        required init?(coder: NSCoder) { nil }
        public func clearSession() {
            #if DEBUG
                dismissDebugFixtures()
            #endif
            adapter.hide()
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
            editor.display(input, landscape: landscape)
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
                    : (special ? Self.color(0xADB4BF, 0x32343B) : Self.color(0xFFFFFF, 0x45474E))
                key.setTitleColor(activeShift ? Self.accent : .label, for: .normal)
            }
            popup.isHidden = adapter.alternative == nil
            popup.text = adapter.alternative.map { input.uppercase ? $0.uppercased() : $0 }
            popup.accessibilityLabel = popup.text
            nextKeyboardButton.isHidden = !showsNextKeyboard
            nextKeyboardButton.backgroundColor = Self.color(0xADB4BF, 0x32343B)
            bringSubviewToFront(popup)
            setNeedsLayout()
        }
        public override func layoutSubviews() {
            super.layoutSubviews()
            if lastSize.width != bounds.width {
                if lastSize.width > 0 { adapter.rotate() }
                lastSize = bounds.size
            }
            let side = max(5, safeAreaInsets.left, safeAreaInsets.right)
            let width = bounds.width - side * 2
            let gap: CGFloat = landscape ? 3 : 7
            let keyHeight: CGFloat = landscape ? 32 : 44
            var y: CGFloat = landscape ? 4 : 7
            status.font = .systemFont(ofSize: landscape ? 10 : 11)
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
        }
    }
#endif
