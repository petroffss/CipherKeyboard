import CipherCore
import SwiftUI

/// Карточка контакта: имя, отпечаток, строка ключа (только показ), «Переименовать» и «Удалить».
/// Поля ключа и действия «Изменить ключ» нет намеренно: другой ключ — удалить и добавить заново, сверив отпечаток.
struct ContactDetailView: View {
    let model: ContactsModel
    let id: UUID
    @Environment(\.dismiss) private var dismiss
    @State private var showingRename = false
    @State private var confirmingDelete = false
    @State private var isDeleting = false
    @State private var deleteFailed = false

    var body: some View {
        Group {
            if let contact = model.contact(id: id) {
                card(for: contact)
            } else {
                Color(.systemGroupedBackground)
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .sheet(isPresented: $showingRename) {
            if let contact = model.contact(id: id) {
                RenameSheet(model: model, contact: contact)
                    .presentationDetents([.large])
            }
        }
    }

    private func card(for contact: Contact) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text(contact.name)
                    .font(.largeTitle.bold())
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("contact.title")
                SectionLabel(text: "Отпечаток")
                FingerprintText(key: contact.publicKey, identifier: "contact.fingerprint")
                FieldHint(text: "Сверьте отпечаток с собеседником при встрече или по телефону — он должен совпасть.")
                    .accessibilityIdentifier("contact.hint")
                SectionLabel(text: "Открытый ключ")
                PublicKeyText(text: contact.publicKey.string, identifier: "contact.publicKey")
                    .padding(.vertical, 8)
                    .padding(.horizontal, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 10))
                    .padding(.top, 6)
                Button("Переименовать") { showingRename = true }
                    .buttonStyle(SecondaryButtonStyle())
                    .accessibilityIdentifier("contact.rename")
                    .padding(.top, 20)
                Button("Удалить") { confirmingDelete = true }
                    .buttonStyle(SecondaryButtonStyle(color: .red))
                    .disabled(isDeleting)
                    .accessibilityIdentifier("contact.delete")
                    .padding(.top, 12)
                if deleteFailed {
                    Text("Не удалось удалить контакт. Попробуйте ещё раз.")
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 8)
                        .accessibilityIdentifier("contact.deleteError")
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
        .background(Color(.systemGroupedBackground))
        .confirmationDialog(
            "Удалить контакт «\(contact.name)»?", isPresented: $confirmingDelete, titleVisibility: .visible
        ) {
            Button("Удалить", role: .destructive) { delete() }
                .accessibilityIdentifier("contact.deleteConfirm")
            Button("Отмена", role: .cancel) {}
        } message: {
            Text("Вы не сможете отправлять ему сообщения.")
        }
    }

    private func delete() {
        guard !isDeleting else { return }
        isDeleting = true
        deleteFailed = false
        Task {
            do {
                try await model.remove(id: id)
                dismiss()
            } catch {
                deleteFailed = true
                isDeleting = false
            }
        }
    }
}

/// Лист «Переименовать»: одно поле имени со счётчиком; ключа здесь нет.
struct RenameSheet: View {
    let model: ContactsModel
    let contact: Contact
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var touched = false
    @State private var isSaving = false
    @State private var saveFailed = false
    @FocusState private var focused: Bool

    init(model: ContactsModel, contact: Contact) {
        self.model = model
        self.contact = contact
        _name = State(initialValue: contact.name)
    }

    private var check: NameCheck { NameCheck(name: name, touched: touched, book: model.book, excluding: contact.id) }

    var body: some View {
        NavigationStack {
            ScrollView {
                NameField(name: $name, touched: $touched, check: check, identifierPrefix: "rename")
                    .focused($focused)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 16)
            }
            .background(Color(.systemGroupedBackground))
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 8) {
                    Button("Сохранить", action: save)
                        .buttonStyle(PrimaryButtonStyle())
                        .disabled(!check.isValid || isSaving)
                        .accessibilityIdentifier("rename.save")
                    if saveFailed {
                        Text("Не удалось сохранить контакт. Попробуйте ещё раз.")
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                            .accessibilityIdentifier("rename.saveError")
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
                .background(Color(.systemGroupedBackground))
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                        .accessibilityIdentifier("rename.cancel")
                }
                ToolbarItem(placement: .principal) {
                    Text("Переименовать")
                        .font(.headline)
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityIdentifier("rename.title")
                }
            }
            .navigationBarTitleDisplayMode(.inline)
        }
        .interactiveDismissDisabled(isSaving)
        .onAppear { focused = true }
    }

    private func save() {
        touched = true
        guard check.isValid, !isSaving else { return }
        isSaving = true
        saveFailed = false
        Task {
            do {
                try await model.rename(id: contact.id, to: name)
                dismiss()
            } catch {
                saveFailed = true
                isSaving = false
            }
        }
    }
}
