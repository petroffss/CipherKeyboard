#if canImport(UIKit)
    import CipherCore
    import UIKit

    /// Transparent hit testing keeps the private editor and typing controls accessible below this layer.
    @MainActor final class EncryptionControls: UIView {
        let model: EncryptInsertCoordinator
        private let recipient = UIButton(type: .system)
        private let encrypt = UIButton(type: .system)
        private let notice = UILabel()
        private let retry = UIButton(type: .system)
        private let picker = UIView()
        private let back = UIButton(type: .system)
        private let title = UILabel()
        private let list = UIScrollView()
        private let hint = UILabel()
        private var lastAnnouncement = ""
        private var contactButtons: [UIButton] = []
        private var signature = ""
        init(coordinator: EncryptInsertCoordinator) {
            model = coordinator
            super.init(frame: .zero)
            tintColor = KeyboardPanel.accent
            recipient.setTitleColor(.label, for: .normal)
            recipient.setTitleColor(.label, for: .disabled)
            recipient.accessibilityIdentifier = "keyboard.recipient"
            encrypt.accessibilityIdentifier = "keyboard.encrypt"
            notice.accessibilityIdentifier = "keyboard.encrypt.status"
            retry.accessibilityIdentifier = "keyboard.contacts.retry"
            back.accessibilityIdentifier = "keyboard.recipient.back"
            list.accessibilityIdentifier = "keyboard.recipient.list"
            recipient.contentHorizontalAlignment = .leading
            recipient.titleLabel?.lineBreakMode = .byTruncatingTail
            recipient.backgroundColor = .secondarySystemGroupedBackground
            recipient.layer.cornerRadius = 9
            encrypt.backgroundColor = KeyboardPanel.accent; encrypt.tintColor = .white
            encrypt.layer.cornerRadius = 10
            for button in [recipient, encrypt] { button.titleLabel?.font = .systemFont(ofSize: 15, weight: .semibold) }
            notice.font = .systemFont(ofSize: 13); notice.numberOfLines = 0
            notice.accessibilityTraits = .updatesFrequently
            retry.backgroundColor = .secondarySystemGroupedBackground; retry.layer.cornerRadius = 8
            retry.setTitle("Повторить", for: .normal); retry.titleLabel?.font = .systemFont(ofSize: 14)
            back.setTitle("Назад", for: .normal)
            title.text = "Получатель"; title.font = .systemFont(ofSize: 17, weight: .semibold)
            picker.backgroundColor = .systemGroupedBackground
            list.backgroundColor = .secondarySystemGroupedBackground; list.layer.cornerRadius = 10
            for view in [recipient, encrypt, notice, retry, picker] { addSubview(view) }
            hint.text = "Выберите контакт. Черновик и его курсор сохранятся."
            hint.font = .systemFont(ofSize: 13); hint.textColor = .secondaryLabel; hint.numberOfLines = 2
            for view in [back, title, list, hint] { picker.addSubview(view) }
            recipient.addAction(UIAction { [weak self] _ in self?.model.openPicker() }, for: .touchUpInside)
            encrypt.addAction(UIAction { [weak self] _ in self?.model.encrypt() }, for: .touchUpInside)
            retry.addAction(UIAction { [weak self] _ in self?.model.refresh() }, for: .touchUpInside)
            back.addAction(UIAction { [weak self] _ in self?.model.closePicker() }, for: .touchUpInside)
            refresh()
        }
        required init?(coder: NSCoder) { nil }
        override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
            let result = super.hitTest(point, with: event)
            return result === self ? nil : result
        }
        func refresh() {
            let recipientName = model.selected?.name ?? "выберите контакт"
            recipient.setTitle("  Кому: " + recipientName + " ▾", for: .normal)
            recipient.accessibilityLabel = "Кому: " + recipientName
            recipient.isEnabled = model.canSelect
            encrypt.setTitle(model.busy ? "Шифруем…" : "Зашифровать", for: .normal)
            encrypt.accessibilityLabel = model.busy ? "Шифруем…" : "Зашифровать"
            encrypt.isEnabled = model.canEncrypt
            encrypt.alpha = encrypt.isEnabled ? 1 : 0.42; recipient.alpha = recipient.isEnabled ? 1 : 0.42
            notice.text = model.status
            if lastAnnouncement != model.status {
                lastAnnouncement = model.status
                if UIAccessibility.isVoiceOverRunning && (model.error != nil || model.success != nil || model.busy) {
                    UIAccessibility.post(notification: .announcement, argument: model.status)
                }
            }
            notice.textColor =
                (model.error != nil || model.adapter.input.limitError)
                ? KeyboardPanel.danger : (model.success != nil ? KeyboardPanel.accent : .secondaryLabel)
            retry.isHidden = !model.contactsUnreadable || !model.permitted || model.busy
            picker.isHidden = !model.pickerOpen
            for view in [recipient, encrypt, notice, retry] { if model.pickerOpen { view.isHidden = true } }
            if !model.pickerOpen {
                recipient.isHidden = false; encrypt.isHidden = false; notice.isHidden = false
            }
            let newSignature =
                model.contacts.map { $0.id.uuidString + $0.name + $0.publicKey.string }.joined()
                + (model.selected?.id.uuidString ?? "")
            if newSignature != signature {
                signature = newSignature
                contactButtons.forEach { $0.removeFromSuperview() }
                contactButtons = model.contacts.map { contact in
                    let button = UIButton(type: .system)
                    var config = UIButton.Configuration.plain()
                    config.baseForegroundColor = .label
                    let accent = KeyboardPanel.accent
                    config.imageColorTransformer = UIConfigurationColorTransformer { _ in accent }
                    config.titleLineBreakMode = .byWordWrapping
                    config.title = contact.name
                    config.subtitle = contact.publicKey.fingerprint.short
                    config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attrs in
                        var attrs = attrs; attrs.font = .systemFont(ofSize: 16); return attrs
                    }
                    config.subtitleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attrs in
                        var attrs = attrs; attrs.font = .monospacedSystemFont(ofSize: 12, weight: .regular);
                        attrs.foregroundColor = .secondaryLabel; return attrs
                    }
                    config.contentInsets = .init(top: 7, leading: 12, bottom: 7, trailing: 12)
                    if model.selected?.id == contact.id {
                        config.image = UIImage(systemName: "checkmark"); config.imagePlacement = .trailing
                    }
                    button.configuration = config
                    button.contentHorizontalAlignment = .leading
                    button.titleLabel?.numberOfLines = 0
                    button.accessibilityIdentifier = "keyboard.recipient." + contact.id.uuidString
                    button.accessibilityLabel = contact.name + ", " + contact.publicKey.fingerprint.short
                    button.accessibilityTraits = model.selected?.id == contact.id ? [.button, .selected] : [.button]
                    button.addAction(UIAction { [weak self] _ in self?.model.select(contact.id) }, for: .touchUpInside)
                    list.addSubview(button)
                    return button
                }
            }
            setNeedsLayout()
        }
        func layoutToolbar(x: CGFloat, y: CGFloat, width: CGFloat, landscape: Bool) {
            notice.font = .systemFont(ofSize: landscape ? 12 : 13)
            let buttonWidth: CGFloat = landscape ? 116 : 142
            recipient.frame = CGRect(x: x, y: y, width: width - buttonWidth - 6, height: 44)
            encrypt.frame = CGRect(x: recipient.frame.maxX + 6, y: y, width: buttonWidth, height: 44)
            recipient.titleLabel?.font = .systemFont(ofSize: landscape ? 14 : 15, weight: .semibold)
            encrypt.titleLabel?.font = recipient.titleLabel?.font
        }
        func layoutNotice(x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat) {
            notice.frame = CGRect(
                x: x + 4, y: y, width: width - (retry.isHidden ? 8 : 102),
                height: height - (model.adapter.input.counter == nil ? 0 : 12))
            retry.frame = CGRect(x: x + width - 94, y: y, width: 94, height: 44)
        }
        func layoutPicker(in rect: CGRect, landscape: Bool) {
            picker.frame = rect
            back.frame = CGRect(x: 0, y: 0, width: 74, height: 44)
            title.frame = CGRect(x: 86, y: 0, width: rect.width - 90, height: 44)
            list.frame = CGRect(x: 0, y: 46, width: rect.width, height: rect.height - 46 - (landscape ? 0 : 33))
            hint.isHidden = landscape
            hint.frame = CGRect(x: 4, y: list.frame.maxY + 2, width: rect.width - 8, height: 31)
            list.isHidden = model.contacts.isEmpty
            if model.pickerOpen && model.contacts.isEmpty {
                notice.isHidden = false
                notice.frame = CGRect(x: rect.minX + 4, y: rect.minY + 50, width: rect.width - 8, height: 60)
                retry.isHidden = !model.contactsUnreadable
                retry.frame = CGRect(x: rect.minX + 4, y: rect.minY + 112, width: 94, height: 44)
                bringSubviewToFront(notice); bringSubviewToFront(retry)
            }
            let columns = landscape ? 2 : 1
            let width = list.bounds.width / CGFloat(columns)
            var tops = Array(repeating: CGFloat.zero, count: columns)
            for (i, button) in contactButtons.enumerated() {
                let col = i % columns
                let measured = button.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude)).height
                let height = max(56, measured)
                button.frame = CGRect(x: CGFloat(col) * width, y: tops[col], width: width, height: height)
                tops[col] += height
            }
            list.contentSize = CGSize(width: list.bounds.width, height: tops.max() ?? 0)
        }
    }
#endif
