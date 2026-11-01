import Foundation

// Хранение контактов: только чтение. Запись (`ContactStore`) — в отдельном модуле `CipherCoreContactStore`,
// который линкует только приложение: клавиатура не может дописать или «починить» файл контактов — это не скомпилируется.

/// Хранилище байтов файла контактов, только чтение.
public protocol ContactStorageReading: Sendable {
    /// Байты файла; `nil` — файла нет (контактов ещё не было). Любая другая неудача — ошибка: файл нечитаем.
    func read() throws -> Data?
}

/// Результат чтения контактов без права записи.
public enum ContactsReadResult: Equatable, Sendable {
    /// Контакты прочитаны (нет файла → пустой массив).
    case contacts([Contact])
    /// Файл есть, но не читается: не JSON, не та версия, плохой ключ, повтор `id`, нет прав. Это не «контактов нет».
    case unreadable
}

/// Только чтение контактов — для клавиатуры. Метода записи у типа нет.
public struct ContactsReader: Sendable {
    private let storage: any ContactStorageReading

    public init(storage: any ContactStorageReading) {
        self.storage = storage
    }

    /// Читатель файла в общем контейнере App Group приложения и клавиатуры.
    public static var appGroup: ContactsReader { ContactsReader(storage: FileContactStorage.appGroup) }

    public func read() -> ContactsReadResult {
        guard let book = try? readBook(storage) else { return .unreadable }
        return .contacts(book.contacts)
    }
}

/// Читает и разбирает книгу из хранилища; нет файла — пустая книга. `package`: нужно `ContactStore`.
package func readBook(_ storage: any ContactStorageReading) throws -> ContactBook {
    guard let data = try storage.read() else { return ContactBook() }
    return try decodeContactsFile(data)
}

/// Файл `contacts.v1.json`: `{"version":1,"contacts":[{"id","name","publicKey"}, …]}`.
struct ContactsFile: Codable {
    static let currentVersion = 1

    var version: Int
    var contacts: [Contact]
}

/// Разбор файла контактов. Любое отклонение — ошибка: версия не 1, ключ не проходит `PublicKey(string:)`
/// (через `Codable` ключа), повторяющийся `id` или ключ.
package func decodeContactsFile(_ data: Data) throws -> ContactBook {
    let file = try JSONDecoder().decode(ContactsFile.self, from: data)
    guard file.version == ContactsFile.currentVersion else { throw ContactsFileError.unsupportedVersion }
    var ids: Set<UUID> = []
    var keys: Set<PublicKey> = []
    for contact in file.contacts {
        guard ids.insert(contact.id).inserted else { throw ContactsFileError.duplicateID }
        guard keys.insert(contact.publicKey).inserted else { throw ContactsFileError.duplicateKey }
    }
    return ContactBook(contacts: file.contacts)
}

/// Кодирование книги в байты файла. `package`: пишет только `ContactStore`.
package func encodeContactsFile(_ book: ContactBook) throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    return try encoder.encode(ContactsFile(version: ContactsFile.currentVersion, contacts: book.contacts))
}

enum ContactsFileError: Error {
    case unsupportedVersion
    case duplicateID
    case duplicateKey
    /// Контейнер группы или само хранилище недоступны.
    case unavailable
}

/// Файл контактов на диске. Чтение — здесь; запись добавляет модуль `CipherCoreContactStore`.
public struct FileContactStorage: ContactStorageReading {
    /// Имя файла в корне контейнера группы.
    public static let fileName = "contacts.v1.json"
    /// Идентификатор App Group приложения и клавиатуры.
    public static let appGroupIdentifier = "group.dev.cipherkeyboard"

    /// Путь к файлу; `nil` — контейнер группы недоступен (нет entitlement) — тогда файл нечитаем.
    package let url: URL?

    public init(url: URL?) {
        self.url = url
    }

    /// Файл в корне контейнера App Group.
    public static var appGroup: FileContactStorage {
        let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier)
        return FileContactStorage(url: container?.appendingPathComponent(fileName, isDirectory: false))
    }

    public func read() throws -> Data? {
        guard let url else { throw ContactsFileError.unavailable }
        do {
            return try Data(contentsOf: url)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return nil
        }
    }
}

/// Хранилище в памяти: для тестов ядра и UI-тестов приложения (только в Debug). Настоящий файл не трогает.
public final class InMemoryContactStorage: ContactStorageReading, @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Data?
    private var failingReads: Int

    /// - Parameters:
    ///   - data: байты файла, которые уже лежат в хранилище (`nil` — файла нет).
    ///   - failingReads: сколько первых чтений закончатся ошибкой «нечитаемо» (затем чтение работает).
    public init(data: Data? = nil, failingReads: Int = 0) {
        stored = data
        self.failingReads = failingReads
    }

    /// Текущие байты «файла» — для проверок в тестах.
    public var data: Data? { lock.withLock { stored } }

    public func read() throws -> Data? {
        try lock.withLock {
            if failingReads > 0 {
                failingReads -= 1
                throw ContactsFileError.unavailable
            }
            return stored
        }
    }

    /// Замена байтов «файла». `package`: снаружи пакета доступна только через `ContactStore`.
    package func replace(_ data: Data) {
        lock.withLock { stored = data }
    }
}
