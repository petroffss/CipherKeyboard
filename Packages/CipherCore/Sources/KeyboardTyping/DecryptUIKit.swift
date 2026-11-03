#if canImport(UIKit)
    import UIKit
    import UniformTypeIdentifiers

    /// No polling, observation or writes. Metadata and the single value read are inside the user action.
    @MainActor public final class SystemDecryptClipboard: DecryptClipboardReading {
        public init() {}
        public func readText() async -> ClipboardText {
            let board = UIPasteboard.general
            #if DEBUG
                DecryptDebugMetrics.metadataReads += 1
            #endif
            guard board.hasStrings else { return .empty }
            #if DEBUG
                DecryptDebugMetrics.contentReads += 1
            #endif
            guard let value = board.string else { return .denied }
            return .text(value)
        }
    }

    #if DEBUG
        @MainActor public enum DecryptDebugMetrics {
            public static var metadataReads = 0
            public static var contentReads = 0
        }
    #endif

    /// Labels retain VoiceOver reading but provide no editing, selection, drag or sharing capability.
    @MainActor public final class PrivateDecryptPanel: UIView {
        private let title = UILabel()
        private let scroll = UIScrollView()
        private let content = UIStackView()
        private let sender = UILabel()
        private let signature = UILabel()
        private let hint = UILabel()
        private let warning = UILabel()
        private let plaintext = UILabel()
        private let textSurface = UIView()
        private let separator = UIView()
        private let status = UILabel()
        private let close = UIButton(type: .system)
        private let spinner = UIActivityIndicatorView(style: .medium)
        private let prefix: String
        public var onClose: (() -> Void)?
        private var announcement = ""
        public init(prefix: String) {
            self.prefix = prefix
            super.init(frame: .zero)
            backgroundColor = .secondarySystemGroupedBackground
            layer.cornerRadius = 14; clipsToBounds = true
            accessibilityIdentifier = prefix + ".panel"
            content.axis = .vertical; content.spacing = 10; content.alignment = .fill
            title.font = .preferredFont(forTextStyle: .title3); title.numberOfLines = 0
            title.accessibilityTraits = [.header]
            title.accessibilityIdentifier = prefix + ".title"
            for (label, suffix) in [
                (sender, "sender"), (signature, "signature"), (plaintext, "text"), (status, "status"),
            ] {
                label.accessibilityIdentifier = prefix + "." + suffix
            }
            textSurface.backgroundColor = .systemGroupedBackground; textSurface.layer.cornerRadius = 10
            textSurface.addSubview(plaintext); plaintext.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                plaintext.leadingAnchor.constraint(equalTo: textSurface.leadingAnchor, constant: 10),
                plaintext.trailingAnchor.constraint(equalTo: textSurface.trailingAnchor, constant: -10),
                plaintext.topAnchor.constraint(equalTo: textSurface.topAnchor, constant: 10),
                plaintext.bottomAnchor.constraint(equalTo: textSurface.bottomAnchor, constant: -10),
            ])
            separator.backgroundColor = .separator
            for label in [sender, signature, hint, warning, plaintext, status] {
                label.numberOfLines = 0; label.adjustsFontForContentSizeCategory = true
                label.font = .preferredFont(forTextStyle: label == plaintext ? .body : .subheadline)
                label.lineBreakMode = .byWordWrapping
                content.addArrangedSubview(label === plaintext ? textSurface : label)
            }
            sender.font = .preferredFont(forTextStyle: .headline)
            signature.textColor = KeyboardPanel.accent; hint.textColor = .secondaryLabel;
            warning.textColor = KeyboardPanel.danger
            status.textColor = KeyboardPanel.danger
            plaintext.setContentCompressionResistancePriority(.required, for: .vertical)
            close.setTitle("Закрыть", for: .normal)
            close.titleLabel?.font = .preferredFont(forTextStyle: .headline)
            close.backgroundColor = KeyboardPanel.accent; close.setTitleColor(.white, for: .normal)
            close.layer.cornerRadius = 12; close.accessibilityIdentifier = prefix + ".close"
            close.addAction(UIAction { [weak self] _ in self?.onClose?() }, for: .touchUpInside)
            for view in [title, scroll, close, spinner, separator] {
                addSubview(view); view.translatesAutoresizingMaskIntoConstraints = false
            }
            scroll.addSubview(content); content.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                title.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
                title.topAnchor.constraint(equalTo: topAnchor, constant: 12),
                title.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
                title.heightAnchor.constraint(lessThanOrEqualToConstant: 55),
                scroll.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 10),
                separator.leadingAnchor.constraint(equalTo: leadingAnchor),
                separator.trailingAnchor.constraint(equalTo: trailingAnchor),
                separator.bottomAnchor.constraint(equalTo: scroll.topAnchor),
                separator.heightAnchor.constraint(equalToConstant: 0.5),
                scroll.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
                scroll.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
                scroll.bottomAnchor.constraint(equalTo: close.topAnchor, constant: -12),
                content.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor),
                content.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor),
                content.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
                content.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
                content.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor),
                close.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
                close.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
                close.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12),
                close.heightAnchor.constraint(equalToConstant: 48),
                spinner.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
                spinner.centerYAnchor.constraint(equalTo: title.centerYAnchor),
            ])
        }
        required init?(coder: NSCoder) { nil }
        public func display(_ model: DecryptCoordinator) {
            let result = model.result
            textSurface.isHidden = result == nil
            title.text = result == nil ? (model.busy ? "Расшифровка" : "Не удалось расшифровать") : "Расшифровано"
            sender.text = result?.sender; signature.text = result == nil ? nil : "✓ Подпись верна"
            plaintext.text = result?.text
            hint.text = result?.unknown == true ? DecryptCoordinator.unknownHint : nil
            warning.text = result?.contactsWarning == true ? DecryptCoordinator.contactsMessage : nil
            status.text = model.status
            status.textColor = model.busy ? .secondaryLabel : KeyboardPanel.danger
            if model.busy { hint.text = "Сообщение ещё не показано" }
            close.backgroundColor = result == nil ? .clear : KeyboardPanel.accent
            close.setTitleColor(result == nil ? KeyboardPanel.accent : .white, for: .normal)
            close.layer.borderWidth = result == nil ? 1.5 : 0
            close.layer.borderColor = KeyboardPanel.accent.cgColor
            for label in [sender, signature, hint, warning, plaintext, status] { label.isHidden = label.text == nil }
            model.busy ? spinner.startAnimating() : spinner.stopAnimating()
            let next = (title.text ?? "") + (model.status ?? "") + (result?.sender ?? "")
            if next != announcement {
                announcement = next; scroll.setContentOffset(.zero, animated: false)
                UIAccessibility.post(notification: .screenChanged, argument: title)
                UIAccessibility.post(notification: .announcement, argument: next)
            }
        }
        public func clear() {
            for label in [title, sender, signature, hint, warning, plaintext, status] { label.text = nil }
            announcement = ""; spinner.stopAnimating(); scroll.setContentOffset(.zero, animated: false)
        }
    }
#endif
