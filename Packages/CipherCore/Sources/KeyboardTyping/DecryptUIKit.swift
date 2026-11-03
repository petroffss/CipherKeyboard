#if canImport(UIKit)
    import UIKit
    import UniformTypeIdentifiers

    /// No polling, observation or writes. Metadata and the single value read are inside the user action.
    @MainActor public final class SystemDecryptClipboard: DecryptClipboardSnapshotReading {
        public init() {}
        public func readText() async -> ClipboardText { readTextSnapshot() }
        public func readTextSnapshot() -> ClipboardText {
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
        private let lock = UIImageView(image: UIImage(systemName: "lock.open"))
        private let body = UIView()
        private let resultRow = UIStackView()
        private let identityScroll = UIScrollView()
        private let identityContent = UIStackView()
        private let textScroll = UIScrollView()
        private let sender = UILabel()
        private let signature = UILabel()
        private let hint = UILabel()
        private let warning = UILabel()
        private let plaintext = UILabel()
        private let textSurface = UIView()
        private let statusScroll = UIScrollView()
        private let statusContainer = UIView()
        private let statusContent = UIStackView()
        private let status = UILabel()
        private let statusHint = UILabel()
        private let errorIcon = UIImageView(image: UIImage(systemName: "exclamationmark.circle"))
        private let close = UIButton(type: .system)
        private let spinner = UIActivityIndicatorView(style: .medium)
        private var identityHeight: NSLayoutConstraint!
        private var identityWidth: NSLayoutConstraint!
        private var closeHeight: NSLayoutConstraint!
        private var hasResult = false
        private var isBusy = false
        public var onClose: (() -> Void)?
        private var announcement = ""
        public init(prefix: String) {
            super.init(frame: .zero)
            backgroundColor = .secondarySystemGroupedBackground
            layer.cornerRadius = 14; clipsToBounds = true
            accessibilityIdentifier = prefix + ".panel"
            title.font = .preferredFont(forTextStyle: .headline); title.numberOfLines = 0
            title.accessibilityTraits = [.header]
            title.accessibilityIdentifier = prefix + ".title"
            lock.tintColor = KeyboardPanel.accent; lock.isAccessibilityElement = false
            identityContent.axis = .vertical; identityContent.spacing = 6
            for (label, suffix) in [
                (sender, "sender"), (signature, "signature"), (plaintext, "text"), (status, "status"),
            ] { label.accessibilityIdentifier = prefix + "." + suffix }
            for label in [sender, signature, hint, warning, plaintext, status, statusHint] {
                label.numberOfLines = 0; label.adjustsFontForContentSizeCategory = true
                label.font = .preferredFont(forTextStyle: label == plaintext ? .body : .subheadline)
                label.lineBreakMode = .byWordWrapping
            }
            sender.font = .preferredFont(forTextStyle: .headline)
            signature.textColor = KeyboardPanel.accent
            hint.textColor = .secondaryLabel; warning.textColor = KeyboardPanel.danger
            statusHint.textColor = .secondaryLabel; statusHint.font = .preferredFont(forTextStyle: .footnote)
            status.textAlignment = .center; statusHint.textAlignment = .center
            errorIcon.tintColor = KeyboardPanel.danger; errorIcon.isAccessibilityElement = false
            errorIcon.contentMode = .scaleAspectFit
            for label in [sender, signature, hint, warning] { identityContent.addArrangedSubview(label) }
            resultRow.spacing = 12; resultRow.alignment = .fill
            resultRow.addArrangedSubview(identityScroll); resultRow.addArrangedSubview(textScroll)
            textSurface.backgroundColor = .systemGroupedBackground; textSurface.layer.cornerRadius = 10
            textSurface.addSubview(plaintext); plaintext.translatesAutoresizingMaskIntoConstraints = false
            plaintext.setContentCompressionResistancePriority(.required, for: .vertical)
            NSLayoutConstraint.activate([
                plaintext.leadingAnchor.constraint(equalTo: textSurface.leadingAnchor, constant: 10),
                plaintext.trailingAnchor.constraint(equalTo: textSurface.trailingAnchor, constant: -10),
                plaintext.topAnchor.constraint(equalTo: textSurface.topAnchor, constant: 10),
                plaintext.bottomAnchor.constraint(lessThanOrEqualTo: textSurface.bottomAnchor, constant: -10),
            ])
            install(identityContent, in: identityScroll)
            install(textSurface, in: textScroll)
            textSurface.heightAnchor.constraint(greaterThanOrEqualTo: textScroll.frameLayoutGuide.heightAnchor)
                .isActive = true
            identityHeight = identityScroll.heightAnchor.constraint(equalToConstant: 64)
            identityWidth = identityScroll.widthAnchor.constraint(
                equalTo: resultRow.widthAnchor, multiplier: 0.33, constant: -8)
            statusContent.axis = .vertical; statusContent.spacing = 12; statusContent.alignment = .center
            for item in [spinner, errorIcon, status, statusHint] { statusContent.addArrangedSubview(item) }
            statusContainer.addSubview(statusContent); statusContent.translatesAutoresizingMaskIntoConstraints = false
            install(statusContainer, in: statusScroll)
            NSLayoutConstraint.activate([
                statusContainer.heightAnchor.constraint(
                    greaterThanOrEqualTo: statusScroll.frameLayoutGuide.heightAnchor),
                statusContent.leadingAnchor.constraint(equalTo: statusContainer.leadingAnchor, constant: 10),
                statusContent.trailingAnchor.constraint(equalTo: statusContainer.trailingAnchor, constant: -10),
                statusContent.centerYAnchor.constraint(equalTo: statusContainer.centerYAnchor),
                statusContent.topAnchor.constraint(greaterThanOrEqualTo: statusContainer.topAnchor, constant: 8),
                statusContent.bottomAnchor.constraint(lessThanOrEqualTo: statusContainer.bottomAnchor, constant: -8),
                errorIcon.heightAnchor.constraint(equalToConstant: 36),
                errorIcon.widthAnchor.constraint(equalToConstant: 36),
            ])
            close.setTitle("Закрыть", for: .normal)
            close.titleLabel?.font = .preferredFont(forTextStyle: .headline)
            close.layer.cornerRadius = 12; close.accessibilityIdentifier = prefix + ".close"
            close.addAction(UIAction { [weak self] _ in self?.onClose?() }, for: .touchUpInside)
            for item in [title, lock, body, close] {
                addSubview(item); item.translatesAutoresizingMaskIntoConstraints = false
            }
            for item in [resultRow, statusScroll] {
                body.addSubview(item); item.translatesAutoresizingMaskIntoConstraints = false
                NSLayoutConstraint.activate([
                    item.leadingAnchor.constraint(equalTo: body.leadingAnchor),
                    item.trailingAnchor.constraint(equalTo: body.trailingAnchor),
                    item.topAnchor.constraint(equalTo: body.topAnchor),
                    item.bottomAnchor.constraint(equalTo: body.bottomAnchor),
                ])
            }
            closeHeight = close.heightAnchor.constraint(equalToConstant: 48)
            NSLayoutConstraint.activate([
                title.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
                title.topAnchor.constraint(equalTo: topAnchor, constant: 12),
                title.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -45),
                lock.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
                lock.centerYAnchor.constraint(equalTo: title.centerYAnchor),
                lock.widthAnchor.constraint(equalToConstant: 22), lock.heightAnchor.constraint(equalToConstant: 22),
                body.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 12),
                body.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
                body.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
                body.bottomAnchor.constraint(equalTo: close.topAnchor, constant: -12),
                close.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
                close.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
                close.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12), closeHeight,
            ])
            for anchor in [title.bottomAnchor, close.topAnchor] {
                let line = UIView(); line.backgroundColor = .separator
                addSubview(line); line.translatesAutoresizingMaskIntoConstraints = false
                NSLayoutConstraint.activate([
                    line.leadingAnchor.constraint(equalTo: leadingAnchor),
                    line.trailingAnchor.constraint(equalTo: trailingAnchor),
                    line.heightAnchor.constraint(equalToConstant: 0.5),
                    line.bottomAnchor.constraint(equalTo: anchor, constant: anchor == title.bottomAnchor ? 6 : -6),
                ])
            }
            registerForTraitChanges([UITraitPreferredContentSizeCategory.self, UITraitLegibilityWeight.self]) {
                (view: PrivateDecryptPanel, _) in view.setNeedsLayout()
            }
        }
        required init?(coder: NSCoder) { nil }
        private func install(_ content: UIView, in scroll: UIScrollView) {
            scroll.contentInsetAdjustmentBehavior = .never; scroll.alwaysBounceHorizontal = false
            scroll.showsHorizontalScrollIndicator = false
            // These private scrollports already have explicit panel boundaries. System edge
            // decoration must not cover the first sender line or verified message characters.
            if #available(iOS 26.0, *) {
                scroll.topEdgeEffect.isHidden = true; scroll.bottomEdgeEffect.isHidden = true
                scroll.leftEdgeEffect.isHidden = true; scroll.rightEdgeEffect.isHidden = true
            }
            scroll.addSubview(content); content.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                content.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor),
                content.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor),
                content.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
                content.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
                content.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor),
            ])
        }
        public override func layoutSubviews() {
            let landscape = bounds.width > 500 && bounds.width > bounds.height
            let axis: NSLayoutConstraint.Axis = landscape ? .horizontal : .vertical
            if resultRow.axis != axis {
                identityHeight.isActive = false; identityWidth.isActive = false
                resultRow.axis = axis
            }
            identityWidth.isActive = landscape; identityHeight.isActive = !landscape
            // Keep at least one full accessibility-sized line in the short landscape scrollports.
            let category = traitCollection.preferredContentSizeCategory
            let chromeTraits =
                landscape && category.isAccessibilityCategory
                ? traitCollection.modifyingTraits { $0.preferredContentSizeCategory = .extraExtraLarge }
                : traitCollection
            let chromeFont = UIFont.preferredFont(forTextStyle: .headline, compatibleWith: chromeTraits)
            if title.font != chromeFont { title.font = chromeFont }
            if close.titleLabel?.font != chromeFont { close.titleLabel?.font = chromeFont }
            closeHeight.constant = max(48, (close.titleLabel?.font.lineHeight ?? 28) + 20)
            super.layoutSubviews()
            if !landscape && body.bounds.width > 0 {
                let fitting = identityContent.systemLayoutSizeFitting(
                    CGSize(width: body.bounds.width, height: UIView.layoutFittingCompressedSize.height),
                    withHorizontalFittingPriority: .required, verticalFittingPriority: .fittingSizeLevel
                ).height
                let height = min(fitting, max(24, body.bounds.height * 0.5))
                if abs(identityHeight.constant - height) > 0.5 { identityHeight.constant = height }
            }
            errorIcon.isHidden = hasResult || isBusy || landscape
        }
        public func display(_ model: DecryptCoordinator) {
            let result = model.result
            hasResult = result != nil; isBusy = model.busy
            title.text = hasResult ? "Расшифровано" : "Расшифровка"
            lock.isHidden = !hasResult; resultRow.isHidden = !hasResult; statusScroll.isHidden = hasResult
            sender.text = result?.sender; signature.text = hasResult ? "✓ Подпись верна" : nil
            plaintext.text = result?.text
            // UIKit's inferred label normalizes line separators; publish the exact verified text for VoiceOver.
            plaintext.accessibilityLabel = result?.text
            hint.text = result?.unknown == true ? DecryptCoordinator.unknownHint : nil
            warning.text = result?.contactsWarning == true ? DecryptCoordinator.contactsMessage : nil
            status.text = model.status
            status.textColor = model.busy ? .secondaryLabel : KeyboardPanel.danger
            statusHint.text =
                model.busy
                ? "Сообщение ещё не показано"
                : model.error == DecryptCoordinator.clipboardMessage
                    ? DecryptCoordinator.clipboardRecovery : "Закройте панель и повторите попытку."
            spinner.isHidden = !model.busy
            model.busy ? spinner.startAnimating() : spinner.stopAnimating()
            close.backgroundColor = hasResult ? KeyboardPanel.accent : .clear
            close.setTitleColor(hasResult ? .white : KeyboardPanel.accent, for: .normal)
            close.layer.borderWidth = hasResult ? 0 : 1.5; close.layer.borderColor = KeyboardPanel.accent.cgColor
            for label in [sender, signature, hint, warning, plaintext, status] { label.isHidden = label.text == nil }
            let next = (title.text ?? "") + (model.status ?? "") + (result?.sender ?? "")
            if next != announcement {
                announcement = next
                for scroll in [identityScroll, textScroll, statusScroll] {
                    scroll.setContentOffset(.zero, animated: false)
                }
                UIAccessibility.post(notification: .screenChanged, argument: title)
                UIAccessibility.post(notification: .announcement, argument: next)
            }
            setNeedsLayout()
        }
        public func clear() {
            for label in [title, sender, signature, hint, warning, plaintext, status, statusHint] { label.text = nil }
            plaintext.accessibilityLabel = nil
            announcement = ""; hasResult = false; isBusy = false
            resultRow.isHidden = true; statusScroll.isHidden = true; spinner.stopAnimating()
            for scroll in [identityScroll, textScroll, statusScroll] { scroll.setContentOffset(.zero, animated: false) }
        }
    }
#endif
