import CipherCore
import SwiftUI
import UIKit

/// Вкладка «Мой ключ»: QR, отпечаток и строка открытого ключа, «Скопировать ключ» и «Поделиться».
/// Приватный ключ здесь не показывается и не экспортируется.
struct MyKeyView: View {
    let info: MyKeyInfo
    @State private var toastVisible = false
    @State private var toastTask: Task<Void, Never>?
    /// Счётчик нажатий «Скопировать ключ» — триггер тактильного отклика: меняется при каждом нажатии,
    /// в том числе повторном, пока плашка видна; при появлении экрана и скрытии плашки не меняется.
    @State private var copyCount = 0

    var body: some View {
        // Плашка живёт в собственной полосе под прокруткой, а не поверх неё: окно ScrollView кончается над полосой,
        // поэтому кнопки (они внутри прокрутки и обрезаются её краем) не попадают в зону плашки ни при какой прокрутке.
        // Пока плашки нет, полоса не занимает высоты — на iPhone 17 (402 × 874) весь экран виден без прокрутки,
        // как в макете. При появлении плашки окно прокрутки укорачивается снизу, а нижний край содержимого остаётся на месте.
        VStack(spacing: 0) {
            content
            if toastVisible {
                toastSlot
                    .transition(.opacity)
            }
            // Зазор над таб-баром (нижнее поле экрана). Он же не даёт ScrollView коснуться нижнего края safe area:
            // иначе SwiftUI растягивает прокрутку под таб-бар и низ экрана уходит под таб-бар и эффект края прокрутки.
            Color.clear
                .frame(height: 6)
                .accessibilityHidden(true)
        }
        .background(Color(.systemGroupedBackground))
    }

    /// Полоса над таб-баром с плашкой; высота следует за Dynamic Type. Нажатия сквозь неё не перехватываются.
    private var toastSlot: some View {
        CopiedToast()
            .accessibilityIdentifier("mykey.copiedToast")
            .allowsHitTesting(false)
            .padding(.top, 8)
            .padding(.bottom, 10)
            .frame(maxWidth: .infinity)
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("Мой ключ")
                    .font(.largeTitle.bold())
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("mykey.title")
                    .padding(.top, 2)
                Text("Покажите QR собеседнику или отправьте ему ключ — тогда он сможет писать вам.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 4)
                qrCard
                    .frame(maxWidth: .infinity)
                    .padding(.top, 14)
                Text("Отпечаток")
                    .font(.footnote)
                    .textCase(.uppercase)
                    .foregroundStyle(.secondary)
                    .padding(.top, 12)
                Text(info.fingerprintTwoLines)
                    .font(.body.monospaced().weight(.semibold))
                    .tracking(0.5)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel(Text(info.fingerprint))
                    .accessibilityIdentifier("mykey.fingerprint")
                    .padding(.top, 4)
                Hint(text: "Сверьте отпечаток с собеседником при встрече или по телефону — он должен совпасть.")
                    .accessibilityIdentifier("mykey.fingerprintHint")
                PublicKeyText(text: info.publicKey.string)
                    .padding(.vertical, 8)
                    .padding(.horizontal, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 10))
                    .padding(.top, 10)
                Hint(text: "Это открытый ключ — его можно отправлять кому угодно.")
                    .accessibilityIdentifier("mykey.publicKeyHint")
                VStack(spacing: 0) {
                    Button("Скопировать ключ", action: copyKey)
                        .buttonStyle(PrimaryButtonStyle())
                        .sensoryFeedback(.success, trigger: copyCount)
                        .accessibilityIdentifier("mykey.copy")
                    ShareLink(item: info.publicKey.string) {
                        Text("Поделиться")
                    }
                    .buttonStyle(SecondaryButtonStyle())
                    .accessibilityIdentifier("mykey.share")
                    .padding(.top, 12)
                }
                .padding(.top, 12)
                HStack(spacing: 6) {
                    Image(systemName: "lock.fill")
                        .accessibilityHidden(true)
                    Text("Приватный ключ хранится только на этом iPhone")
                        .accessibilityIdentifier("mykey.privateNote")
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.top, 10)
            }
            .padding(.horizontal, 20)
        }
        // Появление плашки укорачивает окно прокрутки снизу: держим нижний край содержимого на месте, чтобы кнопки,
        // видимые у нижнего края, приподнялись над полосой плашки, а не ушли под край прокрутки.
        .defaultScrollAnchor(.bottom, for: .sizeChanges)
        .accessibilityIdentifier("mykey.scroll")
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
        copyCount &+= 1
        withAnimation(.easeOut(duration: 0.15)) { toastVisible = true }
        toastTask?.cancel()
        toastTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            withAnimation(.easeIn(duration: 0.15)) { toastVisible = false }
        }
    }
}

/// Пояснение под отпечатком или строкой ключа: 13 pt (footnote), вторичный цвет, переносится.
private struct Hint: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 6)
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
        // Базовый размер 12 pt (caption1 при стандартном Dynamic Type); масштабирует только UIFontMetrics.
        label.font = UIFontMetrics(forTextStyle: .caption1).scaledFont(
            for: .monospacedSystemFont(ofSize: 12, weight: .regular))
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
