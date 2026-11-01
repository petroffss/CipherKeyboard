import Foundation

/// Ошибки книги контактов. Каждая — точная причина для понятного текста в интерфейсе.
public enum ContactError: Error, Equatable, Sendable {
    /// Текст не разбирается как ключ `ckpub1:…` (пусто, мусор, ключ среди другого текста, повреждён).
    case notAKey
    /// Ключ версии, которую эта сборка не знает (`ckpub2:…`).
    case unsupportedVersion
    /// Ключ равен собственному.
    case ownKey
    /// Такой ключ уже есть в книге под другим именем.
    case duplicateKey(existingName: String)
    /// Такое имя (без учёта регистра) уже есть у другого контакта.
    case duplicateName
    /// Имя пустое после обрезки пробелов и переносов.
    case emptyName
    /// Имя длиннее `ContactBook.maxNameLength` символов.
    case nameTooLong
    /// Контакта с таким `id` в книге нет.
    case notFound
    /// Файл контактов не читается — поверх него ничего не пишется.
    case storeUnreadable
    /// Запись в хранилище не удалась; книга на диске не изменилась.
    case writeFailed
}

/// Книга контактов: значение со списком, всегда отсортированным по имени без учёта регистра.
/// Операции замены ключа у существующего контакта нет намеренно: другой ключ — это другой контакт.
public struct ContactBook: Equatable, Sendable {
    /// Наибольшая длина имени в символах (`Character`: эмодзи с модификаторами — один символ).
    public static let maxNameLength = 40

    /// Контакты в порядке показа.
    public private(set) var contacts: [Contact]

    public init(contacts: [Contact] = []) {
        self.contacts = Self.sorted(contacts)
    }

    public var isEmpty: Bool { contacts.isEmpty }
    public var count: Int { contacts.count }

    public func contact(id: UUID) -> Contact? {
        contacts.first { $0.id == id }
    }

    public func contact(publicKey: PublicKey) -> Contact? {
        contacts.first { $0.publicKey == publicKey }
    }

    /// Имя после обрезки пробелов и переносов по краям; внутренние пробелы не трогаются.
    public static func trimmedName(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Проверяет имя: обрезает края, не пустое, не длиннее `maxNameLength`, не совпадает без учёта регистра
    /// с именем другого контакта (`excluding` — контакт, чьё собственное имя дублем не считается).
    public func validatedName(_ name: String, excluding id: UUID? = nil) throws(ContactError) -> String {
        let trimmed = Self.trimmedName(name)
        guard !trimmed.isEmpty else { throw .emptyName }
        guard trimmed.count <= Self.maxNameLength else { throw .nameTooLong }
        if contacts.contains(where: { $0.id != id && Self.sameName($0.name, trimmed) }) {
            throw .duplicateName
        }
        return trimmed
    }

    /// Разбирает ключ собеседника только через `PublicKey(string:)` и проверяет, что он не свой и не сохранён.
    public func validatedKey(_ text: String, own: PublicKey?) throws(ContactError) -> PublicKey {
        let key: PublicKey
        do {
            key = try PublicKey(string: text)
        } catch CipherError.unsupportedVersion {
            throw .unsupportedVersion
        } catch {
            throw .notAKey
        }
        if let own, key == own { throw .ownKey }
        if let existing = contact(publicKey: key) { throw .duplicateKey(existingName: existing.name) }
        return key
    }

    /// Добавляет контакт с новым `id`. Проверки ключа и имени — как у `validatedKey` и `validatedName`.
    @discardableResult
    public mutating func add(name: String, key text: String, own: PublicKey?) throws(ContactError) -> Contact {
        let key = try validatedKey(text, own: own)
        let trimmed = try validatedName(name)
        let contact = Contact(id: UUID(), name: trimmed, publicKey: key)
        contacts = Self.sorted(contacts + [contact])
        return contact
    }

    /// Переименовывает контакт; ключ не меняется. Своё прежнее имя в другом регистре — не дубль.
    public mutating func rename(id: UUID, to name: String) throws(ContactError) {
        guard let index = contacts.firstIndex(where: { $0.id == id }) else { throw .notFound }
        let trimmed = try validatedName(name, excluding: id)
        var updated = contacts
        updated[index].name = trimmed
        contacts = Self.sorted(updated)
    }

    /// Удаляет контакт по `id`.
    public mutating func remove(id: UUID) throws(ContactError) {
        guard let index = contacts.firstIndex(where: { $0.id == id }) else { throw .notFound }
        contacts.remove(at: index)
    }

    /// Порядок как в Контактах iOS: `localizedStandardCompare`, без учёта регистра.
    static func sorted(_ contacts: [Contact]) -> [Contact] {
        contacts.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    static func sameName(_ first: String, _ second: String) -> Bool {
        first.localizedCaseInsensitiveCompare(second) == .orderedSame
    }
}
