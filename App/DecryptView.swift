import CipherCore
import KeyboardTyping
import SwiftUI
import UIKit

struct DecryptView: View {
    let selected: Bool
    @State private var model: DecryptCoordinator
    @Environment(\.scenePhase) private var phase
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .body) private var scaledPasteHeight = DecryptInput.minimumPasteHeight
    @AccessibilityFocusState private var focusSubmit: Bool
    @AccessibilityFocusState private var focusError: Bool

    init(selected: Bool = true) {
        self.selected = selected
        _model = State(initialValue: DecryptLaunch.makeCoordinator())
    }
    var body: some View {
        let pasteHeight =
            dynamicTypeSize.isAccessibilitySize
            ? max(DecryptInput.minimumPasteHeight, ceil(scaledPasteHeight))
            : DecryptInput.minimumPasteHeight
        VStack(alignment: .leading, spacing: 16) {
            Text("Расшифровать")
                .font(verticalSizeClass == .compact ? .title2.bold() : .largeTitle.bold())
                .padding(.top, verticalSizeClass == .compact ? 3 : 8)
            if model.result != nil || model.busy {
                DecryptResultView(model: model)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Вставьте зашифрованное сообщение").font(.subheadline)
                        DecryptInput(model: model)
                            .frame(height: DecryptInput.editorHeight + DecryptInput.spacing + pasteHeight)
                        if model.busy {
                            ProgressView("Расшифровываем…")
                                .accessibilityIdentifier("decrypt.status")
                            Button("Закрыть") { close() }.buttonStyle(SecondaryButtonStyle())
                                .accessibilityIdentifier("decrypt.close")
                        } else {
                            Button("Расшифровать") { model.start() }
                                .buttonStyle(PrimaryButtonStyle()).disabled(!model.canStart)
                                .accessibilityIdentifier("decrypt.submit").accessibilityFocused($focusSubmit)
                        }
                        if let error = model.error {
                            Text(error).foregroundStyle(.red).font(.subheadline)
                                .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                                .background(
                                    Color(uiColor: .secondarySystemGroupedBackground),
                                    in: RoundedRectangle(cornerRadius: 10)
                                )
                                .accessibilityIdentifier("decrypt.status")
                                .accessibilityAddTraits(.updatesFrequently)
                                .accessibilityFocused($focusError)
                        }
                        Text("Текст показывается только здесь.\nПри уходе с вкладки всё стирается.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
                .scrollDismissesKeyboard(.interactively)
            }
        }
        #if DEBUG
            .overlay(alignment: .topTrailing) {
                Text(
                    "coordinators=\(DecryptDebugLifetime.liveCoordinators);operations=\(DecryptDebugLifetime.liveOperations)"
                )
                .font(.system(size: 1)).foregroundStyle(.clear).frame(width: 1, height: 1)
                .accessibilityIdentifier("decrypt.debugLifetime")
            }
        #endif
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(uiColor: .systemGroupedBackground))
        .onAppear { if selected && phase == .active { model.activate() } }
        .onDisappear { model.deactivate() }
        .onChange(of: phase) { _, phase in
            if phase == .active && selected { model.activate() } else { model.deactivate() }
        }
        .onChange(of: selected) { _, selected in
            if selected && phase == .active { model.activate() } else { model.deactivate() }
        }
        .onChange(of: model.presenting) { _, presenting in
            if presenting {
                UIApplication.shared.sendAction(
                    #selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
            }
        }
        .onChange(of: model.error) { _, error in if error != nil { focusError = true } }
        .onChange(of: model.presenting) { old, new in if old && !new { focusSubmit = true } }
        .onChange(of: model.status) { _, value in
            if let value { UIAccessibility.post(notification: .announcement, argument: value) }
        }
    }
    private func close() { model.close(); focusSubmit = true }
}

private struct DecryptResultView: UIViewRepresentable {
    let model: DecryptCoordinator
    func makeUIView(context: Context) -> PrivateDecryptPanel {
        let panel = PrivateDecryptPanel(prefix: "decrypt")
        panel.onClose = { [weak model] in
            model?.close()
            UIAccessibility.post(notification: .screenChanged, argument: "Расшифровать")
        }
        panel.display(model)
        return panel
    }
    func updateUIView(_ view: PrivateDecryptPanel, context: Context) { view.display(model) }
    static func dismantleUIView(_ view: PrivateDecryptPanel, coordinator: ()) { view.clear(); view.onClose = nil }
}

/// System paste delivers text to the same delegate as typing; an oversized replacement is rejected atomically.
private struct DecryptInput: UIViewRepresentable {
    static let editorHeight: CGFloat = 150
    static let spacing: CGFloat = 12
    static let minimumPasteHeight: CGFloat = 50

    let model: DecryptCoordinator
    func makeCoordinator() -> Delegate { Delegate(model: model) }
    func makeUIView(context: Context) -> UIStackView {
        let editor = CiphertextEntryView(frame: .zero, textContainer: nil)
        editor.font = UIFontMetrics(forTextStyle: .body).scaledFont(
            for: .monospacedSystemFont(ofSize: 14, weight: .regular))
        editor.adjustsFontForContentSizeCategory = true
        editor.textContainerInset = UIEdgeInsets(top: 12, left: 10, bottom: 12, right: 10)
        editor.backgroundColor = .secondarySystemGroupedBackground
        editor.layer.cornerRadius = 10; editor.layer.borderWidth = 1
        editor.accessibilityIdentifier = "decrypt.input"
        editor.accessibilityLabel = CipherMessage.outputPrefix + "…"
        editor.autocorrectionType = .no; editor.spellCheckingType = .no
        editor.autocapitalizationType = .none; editor.smartQuotesType = .no; editor.smartDashesType = .no
        editor.smartInsertDeleteType = .no; editor.isSecureTextEntry = false
        editor.textContentType = .none
        editor.textDragInteraction?.isEnabled = false
        if let drop = editor.textDropInteraction { editor.removeInteraction(drop) }
        if #available(iOS 18.0, *) { editor.writingToolsBehavior = .none }
        if #available(iOS 17.0, *) { editor.inlinePredictionType = .no }
        editor.delegate = context.coordinator
        editor.pasteDelegate = context.coordinator
        let config = UIPasteControl.Configuration()
        config.displayMode = .iconAndLabel
        config.baseBackgroundColor = .systemGroupedBackground; config.baseForegroundColor = KeyboardPanel.accent
        let paste = UIPasteControl(configuration: config)
        paste.target = editor
        paste.accessibilityIdentifier = "decrypt.paste"; paste.accessibilityLabel = "Вставить"
        paste.layer.cornerRadius = 14; paste.layer.borderWidth = 1.5
        // Keep the editor at its original height and give the remaining space to the native control.
        editor.heightAnchor.constraint(equalToConstant: Self.editorHeight).isActive = true
        let stack = UIStackView(arrangedSubviews: [editor, paste])
        stack.axis = .vertical
        stack.spacing = Self.spacing
        return stack
    }
    func updateUIView(_ stack: UIStackView, context: Context) {
        guard let editor = stack.arrangedSubviews.first as? UITextView else { return }
        if editor.text != model.input { editor.text = model.input }
        editor.layer.borderColor = UIColor.separator.resolvedColor(with: stack.traitCollection).cgColor
        stack.arrangedSubviews.last?.layer.borderColor =
            KeyboardPanel.accent.resolvedColor(with: stack.traitCollection).cgColor
        editor.isEditable = model.active && !model.busy && model.result == nil
        stack.arrangedSubviews.last?.isUserInteractionEnabled = editor.isEditable
        if !editor.isEditable { editor.resignFirstResponder() }
    }
    static func dismantleUIView(_ stack: UIStackView, coordinator: Delegate) {
        coordinator.attached = false
        if let editor = stack.arrangedSubviews.first as? UITextView {
            editor.isEditable = false; editor.text = ""; editor.delegate = nil
            // Keep the rejecting paste delegate for already retained native deliveries.
            editor.pasteDelegate = coordinator
        }
    }
    final class Delegate: NSObject, UITextViewDelegate, UITextPasteDelegate {
        let model: DecryptCoordinator
        var attached = true
        private static let stampKey = NSAttributedString.Key("CipherKeyboardPasteGeneration")
        private final class PasteStamp: NSObject, @unchecked Sendable {
            let generation: UUID
            let selection: NSRange
            init(_ generation: UUID, _ selection: NSRange) {
                self.generation = generation; self.selection = selection
            }
        }
        // UIKit explicitly permits UITextPasteItem result methods from any thread.
        private struct PasteItem: @unchecked Sendable { let item: any UITextPasteItem }
        init(model: DecryptCoordinator) { self.model = model }
        private var acceptsInput: Bool { attached && model.active && !model.busy && model.result == nil }
        func textPasteConfigurationSupporting(
            _ supporting: any UITextPasteConfigurationSupporting, transform item: any UITextPasteItem
        ) {
            guard acceptsInput, let view = supporting as? UITextView else { item.setNoResult(); return }
            let stamp = PasteStamp(model.inputGeneration, view.selectedRange)
            let output = PasteItem(item: item), key = Self.stampKey
            item.itemProvider.loadObject(ofClass: NSString.self) { [weak self, weak view] value, error in
                let text = value as? String
                Task { @MainActor in
                    guard let self, let view, self.acceptsInput,
                        stamp.generation == self.model.inputGeneration,
                        stamp.selection == view.selectedRange, view.text == self.model.input
                    else { output.item.setNoResult(); return }
                    if error != nil {
                        self.model.pasteFailed()
                        output.item.setNoResult()
                        return
                    }
                    guard let text else { output.item.setNoResult(); return }
                    output.item.setResult(attributedString: NSAttributedString(string: text, attributes: [key: stamp]))
                }
            }
        }
        func textPasteConfigurationSupporting(
            _ supporting: any UITextPasteConfigurationSupporting,
            performPasteOf attributedString: NSAttributedString, to range: UITextRange
        ) -> UITextRange {
            guard acceptsInput, let view = supporting as? UITextView,
                view.text == model.input, attributedString.length > 0
            else { return range }
            var valid = true
            attributedString.enumerateAttribute(
                Self.stampKey, in: NSRange(location: 0, length: attributedString.length)
            ) { value, _, _ in
                guard let stamp = value as? PasteStamp,
                    stamp.generation == model.inputGeneration, stamp.selection == view.selectedRange
                else { valid = false; return }
            }
            guard valid else { return range }
            let replacement = NSRange(
                location: view.offset(from: view.beginningOfDocument, to: range.start),
                length: view.offset(from: range.start, to: range.end))
            guard let swiftRange = Range(replacement, in: view.text),
                model.setInput(view.text.replacingCharacters(in: swiftRange, with: attributedString.string))
            else { return range }
            // Only mutate UIKit after the complete replacement passes the UTF-8 bound and stamp.
            let generation = model.inputGeneration
            let selection = NSRange(location: replacement.location + attributedString.length, length: 0)
            view.text = model.input
            view.selectedRange = selection
            view.setNeedsLayout()
            // Let UIKit consume the returned range before dismissing the keyboard it focused for paste.
            DispatchQueue.main.async { [weak self, weak view] in
                guard let self, let view, self.acceptsInput,
                    self.model.inputGeneration == generation, self.model.error == nil,
                    view.text == self.model.input, view.selectedRange == selection,
                    view.window != nil, view.isFirstResponder
                else { return }
                view.resignFirstResponder()
            }
            return view.selectedTextRange ?? range
        }
        func textView(_ view: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
            guard acceptsInput, let range = Range(range, in: view.text) else { return false }
            return model.setInput(view.text.replacingCharacters(in: range, with: text))
        }
        func textViewDidChange(_ view: UITextView) {
            guard acceptsInput else { view.text = ""; view.setNeedsLayout(); return }
            if view.text != model.input, !model.setInput(view.text) { view.text = model.input }
            view.setNeedsLayout()
        }
    }
}

/// An ordinary editable ciphertext field; the placeholder never contains user data.
private final class CiphertextEntryView: UITextView {
    private let placeholder = UILabel()
    override init(frame: CGRect, textContainer: NSTextContainer?) {
        super.init(frame: frame, textContainer: textContainer)
        placeholder.text = CipherMessage.outputPrefix + "…"
        placeholder.textColor = .placeholderText
        placeholder.numberOfLines = 0
        placeholder.lineBreakMode = .byCharWrapping
        placeholder.isUserInteractionEnabled = false
        placeholder.isAccessibilityElement = false
        addSubview(placeholder)
        updatePlaceholderFont()
        registerForTraitChanges([UITraitPreferredContentSizeCategory.self, UITraitLegibilityWeight.self]) {
            (view: CiphertextEntryView, _) in view.updatePlaceholderFont()
        }
    }
    required init?(coder: NSCoder) { nil }

    private func updatePlaceholderFont() {
        placeholder.font = .preferredFont(forTextStyle: .body, compatibleWith: traitCollection)
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        placeholder.isHidden = !text.isEmpty
        guard !placeholder.isHidden else { return }

        let inset = textContainerInset
        let padding = textContainer.lineFragmentPadding
        let width = max(0, bounds.width - inset.left - inset.right - 2 * padding)
        let size = placeholder.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        // Preserve the regular baseline and grow to fit larger text.
        placeholder.frame = CGRect(
            x: inset.left + padding, y: inset.top, width: width, height: max(28, ceil(size.height)))
    }
}

enum DecryptLaunch {
    @MainActor static func makeCoordinator() -> DecryptCoordinator {
        #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-decrypt-fixture") { return DecryptAppFixture.make() }
        #endif
        return DecryptCoordinator(surface: .app)
    }
}

/// Covers the window synchronously before the application switcher can capture it.
struct AppPrivacyShield: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> Controller { Controller() }
    func updateUIViewController(_ controller: Controller, context: Context) {}
    final class Controller: UIViewController {
        private let cover = UIView()
        override func viewDidLoad() {
            super.viewDidLoad(); view.isUserInteractionEnabled = false
            cover.backgroundColor = .systemGroupedBackground; cover.isUserInteractionEnabled = false
            NotificationCenter.default.addObserver(
                self, selector: #selector(hideContent), name: UIApplication.willResignActiveNotification, object: nil)
            NotificationCenter.default.addObserver(
                self, selector: #selector(reveal), name: UIApplication.didBecomeActiveNotification, object: nil)
        }
        @objc private func hideContent() {
            guard let window = view.window else { return }
            cover.frame = window.bounds; cover.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            window.addSubview(cover)
        }
        @objc private func reveal() { cover.removeFromSuperview() }
        deinit { NotificationCenter.default.removeObserver(self) }
    }
}
