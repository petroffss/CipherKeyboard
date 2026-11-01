import CryptoKit
import Foundation
import Testing

@testable import CipherCore
@testable import CipherCoreContactStore

/// Книга контактов и её хранилище: сортировка, формат файла, проверки имени и ключа, нечитаемый файл.
@Suite("ContactBook")
struct ContactBookTests {
    private func newKey() -> String { Identity.generate().publicKey.string }

    private func names(_ book: ContactBook) -> [String] { book.contacts.map(\.name) }

    // MARK: - E1

    @Test func addsSortsAndPersists() throws {
        let storage = InMemoryContactStorage()
        let store = ContactStore(storage: storage)
        let keys = [newKey(), newKey(), newKey()]

        // 1) После каждого добавления список отсортирован без учёта регистра.
        let afterFirst = try store.add(name: "Яна", key: keys[0], own: nil)
        #expect(names(afterFirst) == ["Яна"])
        let afterSecond = try store.add(name: "анна", key: keys[1], own: nil)
        #expect(names(afterSecond) == ["анна", "Яна"])
        let afterThird = try store.add(name: "Борис", key: keys[2], own: nil)
        #expect(names(afterThird) == ["анна", "Борис", "Яна"])
        #expect(Set(afterThird.contacts.map(\.id)).count == 3)

        // 2) Ридер на том же хранилище видит то же, что стор.
        guard case .contacts(let read) = ContactsReader(storage: storage).read() else {
            Issue.record("ридер не прочитал контакты")
            return
        }
        #expect(read.map(\.id) == afterThird.contacts.map(\.id))
        #expect(read.map(\.name) == afterThird.contacts.map(\.name))
        #expect(read.map(\.publicKey) == afterThird.contacts.map(\.publicKey))

        // 3) Формат файла.
        let data = try #require(storage.data)
        let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(json["version"] as? Int == 1)
        #expect(Set(json.keys) == ["version", "contacts"])
        let contacts = try #require(json["contacts"] as? [[String: Any]])
        #expect(contacts.count == 3)
        for object in contacts {
            #expect(Set(object.keys) == ["id", "name", "publicKey"])
            let key = try #require(object["publicKey"] as? String)
            #expect(key.count == 93)
            #expect(key.hasPrefix("ckpub1:"))
            #expect(object["name"] is String)
            #expect(UUID(uuidString: try #require(object["id"] as? String)) != nil)
        }
    }

    // MARK: - E2

    @Test func validatesName() throws {
        var book = ContactBook()

        for empty in ["", "   ", "\n\t"] {
            let before = book
            #expect(throws: ContactError.emptyName) { try book.add(name: empty, key: newKey(), own: nil) }
            #expect(book == before)
        }

        try book.add(name: "  Анна  ", key: newKey(), own: nil)
        #expect(names(book) == ["Анна"])

        let forty = String(repeating: "А", count: 40)
        try book.add(name: forty, key: newKey(), own: nil)
        #expect(book.contacts.contains { $0.name == forty })

        let fortyOne = String(repeating: "А", count: 41)
        let beforeLong = book
        #expect(throws: ContactError.nameTooLong) { try book.add(name: fortyOne, key: newKey(), own: nil) }
        #expect(book == beforeLong)

        let emoji = "👩‍💻 Аня"
        #expect(emoji.count == 5)
        #expect(emoji.utf8.count > 5)
        try book.add(name: emoji, key: newKey(), own: nil)
        #expect(book.contacts.contains { $0.name == emoji })

        let fortyEmoji = String(repeating: "😀", count: 40)
        try book.add(name: fortyEmoji, key: newKey(), own: nil)
        #expect(book.contacts.contains { $0.name == fortyEmoji })
    }

    // MARK: - E3

    @Test func rejectsBadKeysAndDuplicates() throws {
        let own = Identity.generate()
        let key1 = newKey()
        let key2 = newKey()
        var book = ContactBook()
        try book.add(name: "Анна", key: key1, own: own.publicKey)
        let snapshot = book

        // 1) мусор
        #expect(throws: ContactError.notAKey) { try book.add(name: "Б", key: "привет", own: own.publicKey) }
        // 2) ключ внутри текста
        #expect(throws: ContactError.notAKey) { try book.add(name: "Б", key: "Мой ключ: " + key2, own: own.publicKey) }
        // 3) испорченный base64: последний символ заменён (неканонические биты)
        let last = try #require(key2.last)
        let damaged = String(key2.dropLast()) + String(try #require(nextBase64urlCharacter(after: last)))
        #expect(throws: ContactError.notAKey) { try book.add(name: "Б", key: damaged, own: own.publicKey) }
        // 4) X25519-часть — точка малого порядка (нули), Ed25519-часть настоящая
        let signing = Array(Curve25519.Signing.PrivateKey().publicKey.rawRepresentation)
        let smallOrder = "ckpub1:" + base64url([UInt8](repeating: 0, count: 32) + signing)
        #expect(throws: ContactError.notAKey) { try book.add(name: "Б", key: smallOrder, own: own.publicKey) }
        // 5) неизвестная версия
        let newer = "ckpub2:" + key2.dropFirst("ckpub1:".count)
        #expect(throws: ContactError.unsupportedVersion) {
            try book.add(name: "Б", key: newer, own: own.publicKey)
        }
        // 6) свой ключ
        #expect(throws: ContactError.ownKey) {
            try book.add(name: "Б", key: own.publicKey.string, own: own.publicKey)
        }
        // 7) тот же ключ под другим именем
        #expect(throws: ContactError.duplicateKey(existingName: "Анна")) {
            try book.add(name: "Аня", key: key1, own: own.publicKey)
        }
        // 8) другое имя в другом регистре
        #expect(throws: ContactError.duplicateName) { try book.add(name: "анна", key: key2, own: own.publicKey) }
        // 9) тот же ключ с пробелами и переносами внутри — это всё ещё K1
        var spaced = key1
        spaced.insert(contentsOf: " \n", at: spaced.index(spaced.startIndex, offsetBy: 20))
        spaced.insert(contentsOf: "\n ", at: spaced.index(spaced.startIndex, offsetBy: 60))
        #expect(throws: ContactError.duplicateKey(existingName: "Анна")) {
            try book.add(name: "Аня", key: spaced, own: own.publicKey)
        }

        #expect(book == snapshot)
        #expect(book.contacts.count == 1)
        #expect(book.contacts.first?.name == "Анна")
        #expect(book.contacts.first?.publicKey.string == key1)
    }

    // MARK: - E4

    @Test func unreadableFileIsNeverOverwritten() throws {
        let valid = newKey()
        let sameID = UUID().uuidString
        let smallOrderKey =
            "ckpub1:"
            + base64url(
                [UInt8](repeating: 0, count: 32) + Array(Curve25519.Signing.PrivateKey().publicKey.rawRepresentation))
        let contents: [(String, Data)] = [
            ("не json", Data("не json".utf8)),
            ("версия 2", Data(#"{"version":2,"contacts":[]}"#.utf8)),
            (
                "плохой ключ",
                Data(
                    #"{"version":1,"contacts":[{"id":"\#(UUID().uuidString)","name":"А","publicKey":"ckpub1:AAAA"}]}"#
                        .utf8)
            ),
            (
                "повтор id",
                Data(
                    #"{"version":1,"contacts":[{"id":"\#(sameID)","name":"А","publicKey":"\#(newKey())"},{"id":"\#(sameID)","name":"Б","publicKey":"\#(newKey())"}]}"#
                        .utf8)
            ),
            ("0 байт", Data()),
            (
                "малый порядок",
                Data(
                    #"{"version":1,"contacts":[{"id":"\#(UUID().uuidString)","name":"А","publicKey":"\#(smallOrderKey)"}]}"#
                        .utf8)
            ),
        ]

        for (label, original) in contents {
            let storage = InMemoryContactStorage(data: original)
            // 1) чтение
            #expect(ContactsReader(storage: storage).read() == .unreadable, "чтение: \(label)")
            // 2) запись отказана
            let store = ContactStore(storage: storage)
            #expect(throws: ContactError.storeUnreadable, "запись: \(label)") {
                try store.add(name: "Анна", key: valid, own: nil)
            }
            #expect(store.read() == .unreadable, "после попытки: \(label)")
            // 3) байты не изменились
            #expect(storage.data == original, "байты: \(label)")
        }

        // Нет файла → пустой список, add создаёт файл с одним контактом.
        let empty = InMemoryContactStorage(data: nil)
        #expect(ContactsReader(storage: empty).read() == .contacts([]))
        #expect(empty.data == nil)
        let created = try ContactStore(storage: empty).add(name: "Анна", key: valid, own: nil)
        #expect(created.contacts.count == 1)
        #expect(empty.data != nil)
        guard case .contacts(let read) = ContactsReader(storage: empty).read() else {
            Issue.record("файл после первого контакта не прочитан")
            return
        }
        #expect(read.count == 1)
        #expect(read.first?.name == "Анна")
        #expect(read.first?.publicKey.string == valid)
    }

    // MARK: - E5

    @Test func renamesAndRemoves() throws {
        let key1 = newKey()
        let key2 = newKey()
        var book = ContactBook()
        let anna = try book.add(name: "Анна", key: key1, own: nil)
        let boris = try book.add(name: "Борис", key: key2, own: nil)

        // 1) переименование с пробелами по краям; ключ не изменился; список пересортирован
        try book.rename(id: boris.id, to: "  Аркадий  ")
        #expect(book.contact(id: boris.id)?.name == "Аркадий")
        #expect(book.contact(id: boris.id)?.publicKey.string == key2)
        #expect(names(book) == ["Анна", "Аркадий"])

        // 2) дубль имени в другом регистре
        #expect(throws: ContactError.duplicateName) { try book.rename(id: boris.id, to: "анна") }
        #expect(book.contact(id: boris.id)?.name == "Аркадий")

        // 3) своё имя в другом регистре — не дубль
        try book.rename(id: boris.id, to: "АРКАДИЙ")
        #expect(book.contact(id: boris.id)?.name == "АРКАДИЙ")

        // 4) удаление по id
        try book.remove(id: anna.id)
        #expect(names(book) == ["АРКАДИЙ"])
        #expect(book.contacts.first?.publicKey.string == key2)

        // 5) повторное удаление
        let before = book
        #expect(throws: ContactError.notFound) { try book.remove(id: anna.id) }
        #expect(book == before)
    }
}
