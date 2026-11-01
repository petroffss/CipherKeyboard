import CipherCore
import SwiftUI

/// Вкладка «Контакты»: список собеседников, пустое состояние, ошибка чтения файла. Карточка — push, добавление — лист.
struct ContactsView: View {
    let model: ContactsModel
    @State private var showingAdd = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                header
                content
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Контакты")
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: UUID.self) { id in
                ContactDetailView(model: model, id: id)
            }
        }
        .sheet(isPresented: $showingAdd) {
            AddContactSheet(model: model)
                .presentationDetents([.large])
        }
        .task { model.loadIfNeeded() }
    }

    /// Панель навигации: «+» справа — только когда список не пуст; под ней большой заголовок.
    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Spacer()
                if case .ready(let book) = model.state, !book.isEmpty {
                    Button {
                        showingAdd = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.title2)
                            .frame(width: 44, height: 44)
                    }
                    .accessibilityLabel("Добавить контакт")
                    .accessibilityIdentifier("contacts.add")
                }
            }
            .frame(height: 44)
            Text("Контакты")
                .font(.largeTitle.bold())
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("contacts.title")
                .padding(.bottom, 6)
        }
        .padding(.horizontal, 20)
    }

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .loading:
            ProgressView()
                .controlSize(.large)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .unreadable:
            ContactsErrorView(retry: model.retry)
        case .ready(let book) where book.isEmpty:
            ContactsEmptyView { showingAdd = true }
        case .ready(let book):
            List(book.contacts) { contact in
                NavigationLink(value: contact.id) {
                    ContactRow(contact: contact)
                }
                .accessibilityIdentifier("contacts.row")
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .environment(\.defaultMinListHeaderHeight, 0)
            .accessibilityIdentifier("contacts.list")
        }
    }
}

/// Строка списка: имя и первые две группы отпечатка моноширинным.
struct ContactRow: View {
    let contact: Contact

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(contact.name)
                .font(.body)
                .foregroundStyle(.primary)
            Text(contact.publicKey.fingerprint.short)
                .font(.subheadline.monospaced())
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}

struct ContactsEmptyView: View {
    let add: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 0) {
                Image(systemName: "person.2")
                    .font(.system(size: 56))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                Text("Пока нет контактов")
                    .font(.title2.weight(.semibold))
                    .padding(.top, 14)
                Text("Добавьте ключ собеседника — отсканируйте его QR или вставьте текст.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.top, 6)
            }
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("contacts.empty")
            Button("Добавить контакт", action: add)
                .buttonStyle(PrimaryButtonStyle(fullWidth: false))
                .accessibilityIdentifier("contacts.addFirst")
                .padding(.top, 16)
        }
        .padding(.horizontal, 32)
        .padding(.bottom, 120)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Файл контактов не читается: добавить нельзя, файл не трогается, можно повторить чтение.
struct ContactsErrorView: View {
    let retry: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 0) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 52))
                    .foregroundStyle(.red)
                    .accessibilityHidden(true)
                Text("Не удалось прочитать контакты")
                    .font(.title2.weight(.semibold))
                    .padding(.top, 14)
                Text("Файл контактов повреждён или недоступен. Контакты не удалены.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.top, 8)
            }
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("contacts.error")
            Button("Повторить", action: retry)
                .buttonStyle(PrimaryButtonStyle(fullWidth: false))
                .accessibilityIdentifier("contacts.retry")
                .padding(.top, 12)
        }
        .padding(.horizontal, 32)
        .padding(.bottom, 140)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Подпись блока: 13 pt, вторичный цвет, капителью.
struct SectionLabel: View {
    let text: String
    var topPadding: CGFloat = 14

    var body: some View {
        Text(text)
            .font(.footnote)
            .textCase(.uppercase)
            .foregroundStyle(.secondary)
            .padding(.top, topPadding)
    }
}

/// Красное сообщение под полем: 13 pt.
struct FieldError: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(.red)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 8)
    }
}

/// Пояснение под отпечатком: 13 pt, вторичный цвет.
struct FieldHint: View {
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

extension PublicKey {
    /// Отпечаток в две строки по 4 группы — только для показа.
    var twoLineFingerprint: String {
        let groups = fingerprint.description.split(separator: " ")
        return groups.prefix(4).joined(separator: " ") + "\n" + groups.dropFirst(4).joined(separator: " ")
    }
}

/// Отпечаток в две строки: моноширинный 17 semibold; для тестов — `Fingerprint.description` одной строкой.
struct FingerprintText: View {
    let key: PublicKey
    let identifier: String

    var body: some View {
        Text(key.twoLineFingerprint)
            .font(.body.monospaced().weight(.semibold))
            .tracking(0.5)
            .lineSpacing(2)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityLabel(Text(key.fingerprint.description))
            .accessibilityIdentifier(identifier)
            .padding(.top, 4)
    }
}
