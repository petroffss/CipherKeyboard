import CipherCore
import Foundation

// Запись контактов. Отдельный модуль пакета (продукт `CipherCoreContactStore`): его линкует только приложение.
// Клавиатура зависит лишь от `CipherCore`, где есть `ContactsReader` (только чтение), поэтому добавить, переименовать
// или удалить контакт из расширения нельзя на уровне компилятора.

/// Хранилище байтов файла контактов с правом записи.
public protocol ContactStorageWriting: ContactStorageReading {
    /// Заменяет файл целиком. Неудача — ошибка; прежний файл при этом остаётся прежним.
    func write(_ data: Data) throws
}

/// Книга контактов приложения: каждая операция читает файл, меняет книгу и записывает файл целиком.
/// Нечитаемый файл никогда не перезаписывается (`ContactError.storeUnreadable`).
public struct ContactStore: Sendable {
    private let storage: any ContactStorageWriting

    public init(storage: any ContactStorageWriting) {
        self.storage = storage
    }

    /// Файл в общем контейнере App Group.
    public static var appGroup: ContactStore { ContactStore(storage: FileContactStorage.appGroup) }

    /// Текущее содержимое: контакты или «нечитаемо» (нет файла → пустой список).
    public func read() -> ContactsReadResult {
        ContactsReader(storage: storage).read()
    }

    /// Добавляет контакт. Проверки — как у `ContactBook.add`; возвращает книгу после записи.
    @discardableResult
    public func add(name: String, key: String, own: PublicKey?) throws(ContactError) -> ContactBook {
        try update { book throws(ContactError) in try book.add(name: name, key: key, own: own) }
    }

    /// Переименовывает контакт; ключ не меняется.
    @discardableResult
    public func rename(id: UUID, to name: String) throws(ContactError) -> ContactBook {
        try update { book throws(ContactError) in try book.rename(id: id, to: name) }
    }

    /// Удаляет контакт.
    @discardableResult
    public func remove(id: UUID) throws(ContactError) -> ContactBook {
        try update { book throws(ContactError) in try book.remove(id: id) }
    }

    private func update(_ change: (inout ContactBook) throws(ContactError) -> Void) throws(ContactError) -> ContactBook
    {
        guard var book = try? readBook(storage) else { throw .storeUnreadable }
        try change(&book)
        guard let data = try? encodeContactsFile(book) else { throw .writeFailed }
        do {
            try storage.write(data)
        } catch {
            throw .writeFailed
        }
        return book
    }
}

extension FileContactStorage: ContactStorageWriting {
    /// Запись целиком во временный файл с заменой, защита до первой разблокировки (клавиатура читает контакты
    /// и до неё), без резервной копии (контакты без приватного ключа бесполезны, а в чужой копии — лишнее).
    public func write(_ data: Data) throws {
        guard var url else { throw CocoaError(.fileWriteUnknown) }
        try data.write(to: url, options: [.atomic])
        try FileManager.default.setAttributes(
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: url.path)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try url.setResourceValues(values)
    }
}

extension InMemoryContactStorage: ContactStorageWriting {
    public func write(_ data: Data) throws {
        replace(data)
    }
}

#if DEBUG
    extension InMemoryContactStorage {
        /// Хранилище, в котором уже лежат `count` контактов «Контакт 001»… со случайными валидными ключами —
        /// для UI-тестов длинного списка (аргумент `-contacts-seed`). Только в Debug.
        public static func seeded(count: Int) -> InMemoryContactStorage {
            let width = max(3, String(count).count)
            let contacts = (1...max(count, 1)).prefix(count).map { index in
                let number = String(index)
                let padded = String(repeating: "0", count: max(0, width - number.count)) + number
                return Contact(name: "Контакт " + padded, publicKey: Identity.generate().publicKey)
            }
            let data = try? encodeContactsFile(ContactBook(contacts: Array(contacts)))
            return InMemoryContactStorage(data: data)
        }
    }
#endif
