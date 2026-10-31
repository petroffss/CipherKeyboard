import CipherCore
import SwiftUI
import UIKit

/// Вкладка «Мой ключ»: QR, отпечаток и строка открытого ключа, «Скопировать ключ» и «Поделиться».
/// Приватный ключ здесь не показывается и не экспортируется.
struct MyKeyView: View {
    let info: MyKeyInfo
    @State private var toastVisible = false
    @State private var toastTask: Task<Void, Never>?
    /// Верх плашки и низ блока кнопок в координатах экрана — чтобы плашка не легла на кнопки.
    @State private var toastTop: CGFloat?
    @State private var actionsBottom: CGFloat = 0

    var body: some View {
        ScrollViewReader { proxy in
            content
                // Плашка — в нижней вставке над таб-баром: контент прокручивается с её учётом, касания она не перехватывает.
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    if toastVisible {
                        CopiedToast()
                            .allowsHitTesting(false)
                            .padding(.top, 8)
                            .padding(.bottom, 16)
                            .frame(maxWidth: .infinity)
                            .onGeometryChange(for: CGFloat.self) {
                                $0.frame(in: .global).minY
                            } action: {
                                toastTop = $0
                            }
                            .transition(.opacity)
                    }
                }
                .onChange(of: toastTop) { _, top in
                    // Кнопки оказались под плашкой (узкий непрокрученный экран) — прокручиваем их над ней.
                    guard let top, actionsBottom > top else { return }
                    withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(Self.actionsID, anchor: .bottom) }
                }
        }
    }

    private static let actionsID = "mykey.actions"

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("Мой ключ")
                    .font(.largeTitle.bold())
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("mykey.title")
                    .padding(.top, 4)
                Text("Покажите QR собеседнику или отправьте ему ключ — тогда он сможет писать вам.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 6)
                qrCard
                    .frame(maxWidth: .infinity)
                    .padding(.top, 16)
                Text("Отпечаток")
                    .font(.footnote)
                    .textCase(.uppercase)
                    .foregroundStyle(.secondary)
                    .padding(.top, 16)
                Text(info.fingerprintTwoLines)
                    .font(.body.monospaced().weight(.semibold))
                    .tracking(0.5)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel(Text(info.fingerprint))
                    .accessibilityIdentifier("mykey.fingerprint")
                    .padding(.top, 4)
                PublicKeyText(text: info.publicKey.string)
                    .padding(.vertical, 8)
                    .padding(.horizontal, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 10))
                    .padding(.top, 10)
                VStack(spacing: 0) {
                    Button("Скопировать ключ", action: copyKey)
                        .buttonStyle(PrimaryButtonStyle())
                        .accessibilityIdentifier("mykey.copy")
                    ShareLink(item: info.publicKey.string) {
                        Text("Поделиться")
                    }
                    .buttonStyle(SecondaryButtonStyle())
                    .accessibilityIdentifier("mykey.share")
                    .padding(.top, 12)
                }
                .id(Self.actionsID)
                .onGeometryChange(for: CGFloat.self) {
                    $0.frame(in: .global).maxY
                } action: {
                    actionsBottom = $0
                }
                .padding(.top, 16)
                HStack(spacing: 6) {
                    Image(systemName: "lock.fill")
                        .accessibilityHidden(true)
                    Text("Приватный ключ хранится только на этом iPhone")
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.top, 14)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 72)
        }
        .background(Color(.systemGroupedBackground))
    }

    private var qrCard: some View {
        Group {
            if let qrCode = info.qrCode {
                Image(decorative: qrCode, scale: 1)
                    .resizable()
                    .interpolation(.none)
            } else {
                Color.white
            }
        }
        .frame(width: 220, height: 220)
        .padding(14)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.08), radius: 1.5, y: 1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("QR-код вашего открытого ключа")
        .accessibilityAddTraits(.isImage)
        .accessibilityIdentifier("mykey.qr")
    }

    /// Кладёт в буфер ровно строку открытого ключа; плашка видна 2 секунды после последнего нажатия.
    private func copyKey() {
        UIPasteboard.general.string = info.publicKey.string
        withAnimation(.easeOut(duration: 0.15)) { toastVisible = true }
        toastTask?.cancel()
        toastTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            withAnimation(.easeIn(duration: 0.15)) { toastVisible = false }
            toastTop = nil
        }
    }
}

/// Плашка «Ключ скопирован»: капсула над таб-баром, цвета инвертированы к теме.
struct CopiedToast: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "checkmark")
                .accessibilityHidden(true)
            Text("Ключ скопирован")
        }
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(colorScheme == .dark ? Color.black : Color.white)
        .padding(.vertical, 12)
        .padding(.horizontal, 20)
        .background(
            colorScheme == .dark
                ? Color(red: 242 / 255, green: 242 / 255, blue: 247 / 255).opacity(0.94)
                : Color(red: 28 / 255, green: 28 / 255, blue: 30 / 255).opacity(0.92),
            in: Capsule()
        )
        .shadow(color: .black.opacity(0.2), radius: 8, y: 4)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("mykey.copiedToast")
    }
}

/// Строка открытого ключа. UILabel вместо `Text`: перенос строго посимвольный, без автоматического дефиса —
/// дефис можно принять за символ ключа (в base64url есть настоящие «-»).
struct PublicKeyText: UIViewRepresentable {
    let text: String

    func makeUIView(context: Context) -> UILabel {
        let label = UILabel()
        label.numberOfLines = 0
        label.lineBreakMode = .byCharWrapping
        label.adjustsFontForContentSizeCategory = true
        label.font = UIFontMetrics(forTextStyle: .caption1).scaledFont(
            for: .monospacedSystemFont(
                ofSize: UIFont.preferredFont(forTextStyle: .caption1).pointSize, weight: .regular))
        label.textColor = .secondaryLabel
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        label.accessibilityIdentifier = "mykey.publicKey"
        return label
    }

    func updateUIView(_ label: UILabel, context: Context) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byCharWrapping
        paragraph.hyphenationFactor = 0
        label.attributedText = NSAttributedString(string: text, attributes: [.paragraphStyle: paragraph])
        label.accessibilityLabel = text
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView label: UILabel, context: Context) -> CGSize? {
        let width = proposal.width ?? label.intrinsicContentSize.width
        let fitted = label.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        return CGSize(width: width, height: ceil(fitted.height))
    }
}
