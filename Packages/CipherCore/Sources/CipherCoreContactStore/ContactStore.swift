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
    /// Замена файла одним шагом: байты и все атрибуты (защита до первой разблокировки — клавиатура читает контакты
    /// и до неё; исключение из резервной копии — контакты без приватного ключа бесполезны, а в чужой копии лишние)
    /// ставятся на промежуточный файл рядом, и только потом он переименованием `rename(2)` встаёт на место прежнего.
    /// Любая ошибка до переименования — прежний файл не тронут ни одним байтом, промежуточный удаляется;
    /// после переименования шагов, которые могут упасть, нет. Атрибуты и класс защиты при переименовании
    /// остаются на файле (они принадлежат файлу, а не имени).
    public func write(_ data: Data) throws {
        guard let url else { throw CocoaError(.fileWriteUnknown) }
        // Имя без «contact»: если процесс оборвётся между шагами, остаток не спутать с файлом контактов.
        var staging = url.deletingLastPathComponent()
            .appendingPathComponent(".\(UUID().uuidString).tmp", isDirectory: false)
        do {
            try data.write(to: staging, options: [.atomic])
            try FileManager.default.setAttributes(
                [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: staging.path)
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try staging.setResourceValues(values)
            guard Darwin.rename(staging.path, url.path) == 0 else {
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }
        } catch {
            try? FileManager.default.removeItem(at: staging)
            throw error
        }
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
