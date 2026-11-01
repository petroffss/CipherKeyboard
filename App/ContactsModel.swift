import CipherCore
import CipherCoreContactStore
import Foundation
import Observation

/// Контакты приложения: чтение файла, добавление, переименование, удаление. Каждая операция идёт через
/// `ContactStore` (файл перечитывается и переписывается целиком), результат — новая книга для интерфейса.
@MainActor
@Observable
final class ContactsModel {
    enum State {
        case loading
        case ready(ContactBook)
        case unreadable
    }

    private(set) var state: State = .loading
    /// Своя личность — чтобы не добавить собственный ключ как контакт.
    let ownKey: PublicKey
    private let store: ContactStore
    private var isLoading = false
    private var started = false

    init(store: ContactStore, ownKey: PublicKey) {
        self.store = store
        self.ownKey = ownKey
    }

    /// Книга, если файл прочитан; иначе пустая (для проверок ввода, пока список грузится).
    var book: ContactBook {
        if case .ready(let book) = state { return book }
        return ContactBook()
    }

    var isReady: Bool {
        if case .ready = state { return true }
        return false
    }

    func contact(id: UUID) -> Contact? { book.contact(id: id) }

    /// Первая загрузка при появлении вкладки.
    func loadIfNeeded() {
        guard !started else { return }
        started = true
        load()
    }

    /// «Повторить»: заново читает файл.
    func retry() {
        load()
    }

    private func load() {
        guard !isLoading else { return }
        isLoading = true
        state = .loading
        let store = store
        Task {
            let result = await Task.detached { store.read() }.value
            switch result {
            case .contacts(let contacts):
                state = .ready(ContactBook(contacts: contacts))
            case .unreadable:
                state = .unreadable
            }
            isLoading = false
        }
    }

    func add(name: String, key: String) async throws(ContactError) {
        try await perform { store, own in
            Result { () throws(ContactError) in try store.add(name: name, key: key, own: own) }
        }
    }

    func rename(id: UUID, to name: String) async throws(ContactError) {
        try await perform { store, _ in
            Result { () throws(ContactError) in try store.rename(id: id, to: name) }
        }
    }

    func remove(id: UUID) async throws(ContactError) {
        try await perform { store, _ in
            Result { () throws(ContactError) in try store.remove(id: id) }
        }
    }

    /// Выполняет операцию стора не на главном потоке (файл) и обновляет книгу.
    /// После любой ошибки книга перечитывается с диска: список на экране всегда совпадает с файлом, даже если
    /// запись не удалась или файл изменился. Нечитаемый файл переводит вкладку в состояние ошибки чтения.
    private func perform(
        _ operation: @Sendable @escaping (ContactStore, PublicKey) -> Result<ContactBook, ContactError>
    ) async throws(ContactError) {
        let store = store
        let own = ownKey
        let result = await Task.detached { operation(store, own) }.value
        switch result {
        case .success(let book):
            state = .ready(book)
        case .failure(let error):
            let fresh = await Task.detached { store.read() }.value
            switch fresh {
            case .contacts(let contacts):
                state = .ready(ContactBook(contacts: contacts))
            case .unreadable:
                state = .unreadable
            }
            throw error
        }
    }
}
