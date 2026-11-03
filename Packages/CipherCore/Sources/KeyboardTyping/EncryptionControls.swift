#if canImport(UIKit)
    import CipherCore
    import UIKit

    /// Labels share the same leading edge; selection reserves a separate far-trailing check column.
    @MainActor private final class RecipientRowButton: UIButton {
        private let name = UILabel()
        private let fingerprint = UILabel()
        private let check = UILabel()
        private let separator = UIView()
        init(contact: Contact, selected: Bool) {
            super.init(frame: .zero)
            isSelected = selected
            name.text = contact.name; name.font = .systemFont(ofSize: 16); name.numberOfLines = 0
            name.lineBreakMode = .byWordWrapping
            name.textColor = .label
            fingerprint.text = contact.publicKey.fingerprint.short
            fingerprint.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
            fingerprint.textColor = KeyboardPanel.encryptionSecondary
            check.text = "✓"; check.font = .systemFont(ofSize: 17); check.textColor = KeyboardPanel.accent
            check.isHidden = !selected
            separator.backgroundColor = KeyboardPanel.encryptionSeparator
            for view in [name, fingerprint, check, separator] {
                view.isUserInteractionEnabled = false; view.isAccessibilityElement = false; addSubview(view)
            }
            isAccessibilityElement = true
            accessibilityIdentifier = "keyboard.recipient." + contact.id.uuidString
            accessibilityLabel = contact.name + ", " + contact.publicKey.fingerprint.short
            accessibilityTraits = selected ? [.button, .selected] : [.button]
        }
        required init?(coder: NSCoder) { nil }
        private func textWidth(_ width: CGFloat) -> CGFloat { max(0, width - 24 - (isSelected ? 32 : 0)) }
        override func sizeThatFits(_ size: CGSize) -> CGSize {
            let nameHeight = name.sizeThatFits(CGSize(width: textWidth(size.width), height: .greatestFiniteMagnitude))
                .height
            return CGSize(width: size.width, height: max(56, 14 + nameHeight + 3 + fingerprint.font.lineHeight))
        }
        override func layoutSubviews() {
            super.layoutSubviews()
            let width = textWidth(bounds.width)
            let nameHeight = name.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude)).height
            let textHeight = nameHeight + 3 + fingerprint.font.lineHeight
            let top = (bounds.height - textHeight) / 2
            name.frame = CGRect(x: 12, y: top, width: width, height: nameHeight)
            fingerprint.frame = CGRect(x: 12, y: name.frame.maxY + 3, width: width, height: fingerprint.font.lineHeight)
            check.frame = CGRect(x: bounds.width - 32, y: (bounds.height - 22) / 2, width: 20, height: 22)
            separator.frame = CGRect(x: 0, y: bounds.height - 1, width: bounds.width, height: 1)
        }
        #if DEBUG
            var captureGeometry: [String: Any] {
                [
                    "id": accessibilityIdentifier ?? "", "selected": isSelected,
                    "nameMinX": name.frame.minX, "fingerprintMinX": fingerprint.frame.minX,
                    "checkMaxX": check.frame.maxX, "width": bounds.width, "height": bounds.height,
                    "separatorHeight": separator.frame.height,
                ]
            }
        #endif
    }

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
        private var contactButtons: [RecipientRowButton] = []
        var showsRetry: Bool { !retry.isHidden && !model.pickerOpen }
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
            encrypt.setTitleColor(.white, for: .normal)
            encrypt.setTitleColor(.white, for: .disabled)
            encrypt.layer.cornerRadius = 10
            for button in [recipient, encrypt] { button.titleLabel?.font = .systemFont(ofSize: 15, weight: .semibold) }
            notice.font = .systemFont(ofSize: 13); notice.numberOfLines = 0
            notice.accessibilityTraits = .updatesFrequently
            retry.backgroundColor = .secondarySystemGroupedBackground; retry.layer.cornerRadius = 8
            retry.setTitle("Повторить", for: .normal); retry.titleLabel?.font = .systemFont(ofSize: 14)
            var backStyle = UIButton.Configuration.plain()
            backStyle.title = "‹ Назад"; backStyle.baseForegroundColor = KeyboardPanel.accent
            backStyle.contentInsets = .init(top: 0, leading: 10, bottom: 0, trailing: 0)
            backStyle.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attrs in
                var attrs = attrs; attrs.font = .systemFont(ofSize: 15); return attrs
            }
            back.configuration = backStyle; back.contentHorizontalAlignment = .leading
            back.accessibilityLabel = "Назад"
            title.text = "Кому зашифровать"; title.font = .systemFont(ofSize: 17, weight: .semibold)
            picker.backgroundColor = .systemGroupedBackground
            list.backgroundColor = .secondarySystemGroupedBackground; list.layer.cornerRadius = 10
            for view in [recipient, encrypt, notice, retry, picker] { addSubview(view) }
            hint.text = "Выберите контакт. Черновик и его курсор сохранятся."
            hint.font = .systemFont(ofSize: 13); hint.textColor = KeyboardPanel.encryptionSecondary;
            hint.numberOfLines = 2
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
            if !model.permitted || model.error == EncryptInsertCoordinator.missingMessage {
                notice.textColor = KeyboardPanel.encryptionSecondary
            } else {
                notice.textColor =
                    (model.error != nil || model.adapter.input.limitError)
                    ? KeyboardPanel.danger
                    : (model.success != nil ? KeyboardPanel.accent : KeyboardPanel.encryptionSecondary)
            }
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
                    let button = RecipientRowButton(contact: contact, selected: model.selected?.id == contact.id)
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
        func layoutNotice(x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat, sharesCaption: Bool) -> CGFloat {
            let serviceHeight: CGFloat = sharesCaption || model.adapter.input.counter != nil ? 12 : 0
            let retryWidth: CGFloat
            if sharesCaption {
                let titleWidth = retry.titleLabel?.intrinsicContentSize.width ?? retry.intrinsicContentSize.width
                retryWidth = max(44, ceil(titleWidth) + 8)
            } else {
                retryWidth = 94
            }
            let leadingWidth = width - 8 - (retry.isHidden ? 0 : retryWidth)
            notice.frame = CGRect(
                x: x + 4, y: y + serviceHeight, width: leadingWidth, height: height - serviceHeight)
            retry.frame = CGRect(x: x + width - retryWidth, y: y, width: retryWidth, height: 44)
            return leadingWidth
        }
        #if DEBUG
            var captureMetadata: [String: Any] {
                var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
                notice.textColor.resolvedColor(with: traitCollection).getRed(
                    &red, green: &green, blue: &blue, alpha: &alpha)
                return [
                    "noticeColor": [red, green, blue, alpha], "noticeMinY": notice.frame.minY,
                    "pickerTitle": title.text ?? "", "retryVisible": showsRetry,
                    "pickerRows": contactButtons.map { $0.captureGeometry },
                ]
            }
        #endif
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
                button.layoutIfNeeded()
                tops[col] += height
            }
            list.contentSize = CGSize(width: list.bounds.width, height: tops.max() ?? 0)
        }
    }
#endif
