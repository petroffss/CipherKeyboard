import CipherCore
import SwiftUI

/// Лист «Новый контакт»: ключ собеседника (вставка или QR), предпросмотр отпечатка, имя, «Сохранить».
/// Ключ разбирает только `ContactBook.validatedKey` → `PublicKey(string:)`; текст из сканера идёт в то же поле.
struct AddContactSheet: View {
    let model: ContactsModel
    @Environment(\.dismiss) private var dismiss
    @State private var keyText = ""
    @State private var name = ""
    @State private var nameTouched = false
    @State private var isSaving = false
    @State private var saveFailed = false
    @State private var showingScanner = false
    /// Ключ, который сейчас записывается: пока идёт запись и закрывается лист, предпросмотр показывает его,
    /// а не «уже сохранён как …» из обновлённой книги.
    @State private var savingKey: PublicKey?
    @FocusState private var nameFocused: Bool

    private enum KeyStatus: Equatable {
        case empty
        case valid(PublicKey)
        case invalid(ContactError)
    }

    private var keyStatus: KeyStatus {
        if let savingKey { return .valid(savingKey) }
        let trimmed = keyText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .empty }
        do {
            return .valid(try model.book.validatedKey(trimmed, own: model.ownKey))
        } catch {
            return .invalid(error)
        }
    }

    private var keyMessage: String? {
        guard case .invalid(let error) = keyStatus else { return nil }
        switch error {
        case .unsupportedVersion:
            return "Этот ключ создан более новой версией CipherKeyboard. Обновите приложение."
        case .ownKey:
            return "Это ваш собственный ключ. Добавьте ключ собеседника."
        case .duplicateKey(let existingName):
            return "Этот ключ уже сохранён как «\(existingName)»"
        case .sharedAgreementKey(let existingName):
            return
                "Часть шифрования совпадает с ключом «\(existingName)», но подпись другая. Возможна подмена — сверьте полный отпечаток с собеседником."
        default:
            return "Это не ключ CipherKeyboard. Вставьте строку целиком — она начинается с ckpub1:"
        }
    }

    private var validKey: PublicKey? {
        if case .valid(let key) = keyStatus { return key }
        return nil
    }

    private var nameCheck: NameCheck {
        // Пока идёт запись, имя проверяется по книге без нового контакта (иначе оно стало бы «дублем» самого себя).
        NameCheck(
            name: name, touched: nameTouched, book: savingKey == nil ? model.book : bookBeforeSave, excluding: nil)
    }

    @State private var bookBeforeSave = ContactBook()

    private var canSave: Bool { model.isReady && validKey != nil && nameCheck.isValid && !isSaving }

    var body: some View {
        NavigationStack {
            ContactFormScroll(nameFocused: nameFocused, nameMessage: nameCheck.message) {
                VStack(alignment: .leading, spacing: 0) {
                    SectionLabel(text: "Ключ собеседника", topPadding: 4)
                    keyField
                    HStack(spacing: 12) {
                        PasteButton(payloadType: String.self) { strings in
                            keyText = strings.first ?? ""
                        }
                        .labelStyle(.titleOnly)
                        .buttonBorderShape(.roundedRectangle(radius: 14))
                        .tint(Color.accentColor)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .disabled(isSaving)
                        .accessibilityIdentifier("addcontact.paste")
                        Button("Сканировать QR") {
                            showingScanner = true
                        }
                        .buttonStyle(SecondaryButtonStyle(minHeight: 44, font: .subheadline.weight(.semibold)))
                        .disabled(isSaving)
                        .accessibilityIdentifier("addcontact.scan")
                    }
                    .padding(.top, 12)
                    if let keyMessage {
                        FieldError(text: keyMessage)
                            .accessibilityIdentifier("addcontact.keyError")
                    }
                    if let validKey {
                        preview(for: validKey)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 16)
            } footer: {
                footer
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    // Пока идёт запись, лист не закрыть: контакт либо сохранится и лист закроется сам,
                    // либо будет ошибка на месте — а не «закрыли, но контакт всё равно появился».
                    Button("Отмена") { dismiss() }
                        .disabled(isSaving)
                        .accessibilityIdentifier("addcontact.cancel")
                }
                ToolbarItem(placement: .principal) {
                    Text("Новый контакт")
                        .font(.headline)
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityIdentifier("addcontact.title")
                }
            }
            .navigationBarTitleDisplayMode(.inline)
        }
        .interactiveDismissDisabled(isSaving)
        .fullScreenCover(isPresented: $showingScanner) {
            QRScannerView { payload in
                keyText = payload
            }
        }
    }

    private var keyField: some View {
        TextField("ckpub1:…", text: $keyText, axis: .vertical)
            .font(.subheadline.monospaced())
            .lineLimit(3...8)
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
            .keyboardType(.asciiCapable)
            .padding(12)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 10))
            .accessibilityIdentifier("addcontact.key")
            .padding(.top, 6)
    }

    private func preview(for key: PublicKey) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionLabel(text: "Отпечаток")
            FingerprintText(key: key, identifier: "addcontact.fingerprint")
            FieldHint(
                text:
                    "Сверьте отпечаток с собеседником при встрече или по телефону — он должен совпасть. Не совпадает — не сохраняйте: ключ мог быть подменён."
            )
            .accessibilityIdentifier("addcontact.fingerprintHint")
            NameField(name: $name, touched: $nameTouched, check: nameCheck, identifierPrefix: "addcontact")
                .focused($nameFocused)
                .id("contact.nameBlock")
        }
    }

    private var footer: some View {
        VStack(spacing: 8) {
            Button("Сохранить", action: save)
                .buttonStyle(PrimaryButtonStyle())
                .disabled(!canSave)
                .accessibilityIdentifier("addcontact.save")
            if !model.isReady {
                Button("Повторить чтение контактов", action: model.retry)
                    .accessibilityIdentifier("addcontact.retry")
                Text("Не удалось прочитать контакты. Контакты не удалены.")
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .accessibilityIdentifier("addcontact.readError")
            } else if saveFailed {
                Text("Не удалось сохранить контакт. Попробуйте ещё раз.")
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .accessibilityIdentifier("addcontact.saveError")
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 8)
        .background(Color(.systemGroupedBackground))
    }

    /// Запись одного контакта: пока идёт, кнопка недоступна — двойное нажатие даёт один контакт.
    private func save() {
        nameTouched = true
        guard let validKey, nameCheck.isValid, !isSaving else { return }
        isSaving = true
        saveFailed = false
        bookBeforeSave = model.book
        savingKey = validKey
        let keyString = validKey.string
        let trimmedName = ContactBook.trimmedName(name)
        Task {
            do {
                try await model.add(name: trimmedName, key: keyString)
                dismiss()
            } catch {
                saveFailed = true
                isSaving = false
                savingKey = nil
            }
        }
    }
}

/// Проверка имени для листов добавления и переименования: сообщение и допустимость.
struct NameCheck {
    let trimmed: String
    let error: ContactError?
    let touched: Bool

    init(name: String, touched: Bool, book: ContactBook, excluding id: UUID?) {
        trimmed = ContactBook.trimmedName(name)
        self.touched = touched
        do {
            _ = try book.validatedName(name, excluding: id)
            error = nil
        } catch {
            self.error = error
        }
    }

    var isValid: Bool { error == nil }

    /// Счётчик — по обрезанному имени, в `Character`.
    var countText: String { "\(trimmed.count)/\(ContactBook.maxNameLength)" }

    var isOverLimit: Bool { error == .nameTooLong }

    /// «Введите имя» — только после первого ввода или нажатия «Сохранить».
    var message: String? {
        switch error {
        case .emptyName:
            return touched ? "Введите имя" : nil
        case .nameTooLong:
            return "Не больше 40 символов"
        case .duplicateName:
            return "Контакт с таким именем уже есть"
        default:
            return nil
        }
    }
}

/// Поле «Имя» со счётчиком и сообщением; общее для добавления и переименования.
struct NameField: View {
    @Binding var name: String
    @Binding var touched: Bool
    let check: NameCheck
    let identifierPrefix: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionLabel(text: "Имя")
            TextField("Как вы зовёте собеседника", text: $name)
                .font(.body)
                .textInputAutocapitalization(.sentences)
                .autocorrectionDisabled()
                .submitLabel(.done)
                .padding(.vertical, 13)
                .padding(.horizontal, 12)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 10))
                .accessibilityIdentifier("\(identifierPrefix).name")
                .padding(.top, 6)
                .onChange(of: name) { touched = true }
            if let message = check.message {
                FieldError(text: message)
                    .accessibilityIdentifier("\(identifierPrefix).nameError")
            }
            Text(check.countText)
                .font(.footnote)
                .foregroundStyle(check.isOverLimit ? Color.red : Color.secondary)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .accessibilityIdentifier("\(identifierPrefix).nameCount")
                .padding(.top, 6)
        }
    }
}

/// Кнопка занимает собственное место под прокруткой. Прокручиваем весь блок имени (включая ошибку),
/// когда меняются фокус, сообщение или доступная высота после появления клавиатуры.
struct ContactFormScroll<Content: View, Footer: View>: View {
    let nameFocused: Bool
    let nameMessage: String?
    @ViewBuilder let content: () -> Content
    @ViewBuilder let footer: () -> Footer

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView { content() }
                    .scrollDismissesKeyboard(.interactively)
                    .onChange(of: nameFocused) { scrollToName(proxy) }
                    .onChange(of: nameMessage) { scrollToName(proxy, revealMessage: nameMessage != nil) }
                    .onScrollGeometryChange(for: CGSize.self) { geometry in
                        geometry.containerSize
                    } action: { _, _ in
                        scrollToName(proxy)
                    }
                    .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardDidShowNotification)) {
                        _ in
                        scrollToName(proxy)
                    }
            }
            footer()
        }
        .background(Color(.systemGroupedBackground))
    }

    private func scrollToName(_ proxy: ScrollViewProxy, revealMessage: Bool = false) {
        guard nameFocused || revealMessage else { return }
        withAnimation { proxy.scrollTo("contact.nameBlock", anchor: .bottom) }
    }
}
