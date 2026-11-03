import CipherCore
import KeyboardTyping
import SwiftUI
import UIKit

struct DecryptView: View {
    @State private var model: DecryptCoordinator
    @Environment(\.scenePhase) private var phase
    @AccessibilityFocusState private var focusSubmit: Bool
    @AccessibilityFocusState private var focusError: Bool

    init() { _model = State(initialValue: DecryptLaunch.makeCoordinator()) }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Расшифровать").font(.largeTitle.bold()).padding(.top, 8)
            if model.result != nil || model.busy {
                DecryptResultView(model: model)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Вставьте зашифрованное сообщение").font(.body)
                        DecryptInput(model: model).frame(height: 212)
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
        .onAppear { model.activate() }
        .onDisappear { model.deactivate() }
        .onChange(of: phase) { _, phase in
            if phase == .active { model.activate() } else { model.deactivate() }
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
    let model: DecryptCoordinator
    func makeCoordinator() -> Delegate { Delegate(model: model) }
    func makeUIView(context: Context) -> UIStackView {
        let editor = CiphertextEntryView(frame: .zero, textContainer: nil)
        editor.font = .preferredFont(forTextStyle: .body)
        editor.backgroundColor = .secondarySystemGroupedBackground
        editor.layer.cornerRadius = 12
        editor.accessibilityIdentifier = "decrypt.input"; editor.accessibilityLabel = "ckmsg1:…"
        editor.autocorrectionType = .no; editor.spellCheckingType = .no
        editor.autocapitalizationType = .none; editor.smartQuotesType = .no; editor.smartDashesType = .no
        editor.smartInsertDeleteType = .no; editor.isSecureTextEntry = false
        editor.textContentType = .none
        editor.textDragInteraction?.isEnabled = false
        if let drop = editor.textDropInteraction { editor.removeInteraction(drop) }
        if #available(iOS 18.0, *) { editor.writingToolsBehavior = .none }
        if #available(iOS 17.0, *) { editor.inlinePredictionType = .no }
        editor.delegate = context.coordinator
        let config = UIPasteControl.Configuration()
        config.displayMode = .iconAndLabel
        let paste = UIPasteControl(configuration: config)
        paste.target = editor
        paste.accessibilityIdentifier = "decrypt.paste"; paste.accessibilityLabel = "Вставить"
        paste.heightAnchor.constraint(equalToConstant: 44).isActive = true
        let stack = UIStackView(arrangedSubviews: [editor, paste]); stack.axis = .vertical; stack.spacing = 12
        return stack
    }
    func updateUIView(_ stack: UIStackView, context: Context) {
        guard let editor = stack.arrangedSubviews.first as? UITextView else { return }
        if editor.text != model.input { editor.text = model.input }
        editor.isEditable = !model.busy
        stack.arrangedSubviews.last?.isUserInteractionEnabled = !model.busy
        if model.busy { editor.resignFirstResponder() }
    }
    static func dismantleUIView(_ stack: UIStackView, coordinator: Delegate) {
        if let editor = stack.arrangedSubviews.first as? UITextView { editor.text = ""; editor.delegate = nil }
    }
    final class Delegate: NSObject, UITextViewDelegate {
        let model: DecryptCoordinator
        init(model: DecryptCoordinator) { self.model = model }
        func textView(_ view: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
            guard let range = Range(range, in: view.text) else { return false }
            return model.setInput(view.text.replacingCharacters(in: range, with: text))
        }
        func textViewDidChange(_ view: UITextView) {
            if !model.setInput(view.text) { view.text = model.input }
            view.setNeedsLayout()
        }
    }
}

/// An ordinary editable ciphertext field; the placeholder never contains user data.
private final class CiphertextEntryView: UITextView {
    private let placeholder = UILabel()
    override init(frame: CGRect, textContainer: NSTextContainer?) {
        super.init(frame: frame, textContainer: textContainer)
        placeholder.text = "ckmsg1:…"; placeholder.font = .preferredFont(forTextStyle: .body)
        placeholder.textColor = .placeholderText; placeholder.isUserInteractionEnabled = false
        placeholder.isAccessibilityElement = false; addSubview(placeholder)
    }
    required init?(coder: NSCoder) { nil }
    override func layoutSubviews() {
        super.layoutSubviews()
        placeholder.frame = CGRect(
            x: textContainerInset.left + 5, y: textContainerInset.top,
            width: bounds.width - textContainerInset.left - textContainerInset.right - 10, height: 28)
        placeholder.isHidden = !text.isEmpty
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
