import CipherCore
import CipherCoreIdentityStore
import Foundation
import Security
import Testing

/// Поддельное хранилище: записывает каждый вызов и позволяет подменить ответы `read`/`add`.
/// В протоколе `SecretStorage` нет `update`/`delete`, поэтому журнал операций содержит только `read` и `add`.
final class FakeSecretStorage: SecretStorage, @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Data?
    private var queuedReadStatuses: [OSStatus]
    private let addOverride: OSStatus?
    private let onAdd: (@Sendable (FakeSecretStorage) -> Void)?
    private var log: [String] = []
    private var added: [Data] = []

    init(
        data: Data? = nil, readStatuses: [OSStatus] = [], addStatus: OSStatus? = nil,
        onAdd: (@Sendable (FakeSecretStorage) -> Void)? = nil
    ) {
        stored = data
        queuedReadStatuses = readStatuses
        addOverride = addStatus
        self.onAdd = onAdd
    }

    var data: Data? { lock.withLock { stored } }
    var operations: [String] { lock.withLock { log } }
    var readCount: Int { operations.filter { $0 == "read" }.count }
    var addCount: Int { operations.filter { $0 == "add" }.count }
    var addedData: [Data] { lock.withLock { added } }

    /// Запись, которая «появилась» от другого запуска.
    func put(_ data: Data) {
        lock.withLock { stored = data }
    }

    func read() -> (status: OSStatus, data: Data?) {
        lock.withLock {
            log.append("read")
            if !queuedReadStatuses.isEmpty {
                let status = queuedReadStatuses.removeFirst()
                return (status, status == errSecSuccess ? stored : nil)
            }
            guard let stored else { return (errSecItemNotFound, nil) }
            return (errSecSuccess, stored)
        }
    }

    func add(_ data: Data) -> OSStatus {
        lock.withLock {
            log.append("add")
            added.append(data)
        }
        onAdd?(self)
        if let addOverride { return addOverride }
        return lock.withLock {
            guard stored == nil else { return errSecDuplicateItem }
            stored = data
            return errSecSuccess
        }
    }
}

@Suite("Хранилище личности: прочитать или создать")
struct IdentityStoreTests {
    @Test("Пустое хранилище: личность создаётся и записывается одной записью из 64 байт")
    func createsOnEmptyStorage() throws {
        let storage = FakeSecretStorage()
        let identity = try IdentityStore(storage: storage).loadOrCreate()

        #expect(storage.addCount == 1)
        let written = try #require(storage.addedData.first)
        #expect(written.count == 64)
        #expect(try Identity(privateKeyData: written).publicKey == identity.publicKey)
        #expect(storage.data == written)
    }

    @Test("Повторная загрузка и перезапуск читают ту же личность, без новой записи")
    func secondLoadReadsSameIdentity() throws {
        let storage = FakeSecretStorage()
        let store = IdentityStore(storage: storage)
        let first = try store.loadOrCreate()

        let second = try store.loadOrCreate()
        #expect(second.publicKey == first.publicKey)
        #expect(storage.addCount == 1)

        let relaunched = try IdentityStore(storage: storage).loadOrCreate()
        #expect(relaunched.publicKey == first.publicKey)
        #expect(storage.addCount == 1)
    }

    @Test("Два разных пустых хранилища дают разные личности")
    func differentStoragesDiffer() throws {
        let a = try IdentityStore(storage: FakeSecretStorage()).loadOrCreate()
        let b = try IdentityStore(storage: FakeSecretStorage()).loadOrCreate()
        #expect(a.publicKey != b.publicKey)
    }

    @Test(
        "Ошибка чтения Keychain — ошибка, а не новый ключ; запись A не тронута",
        arguments: [errSecInteractionNotAllowed, errSecMissingEntitlement, errSecAuthFailed, errSecParam, OSStatus(-1)]
    )
    func readFailureDoesNotCreate(status: OSStatus) throws {
        let a = Identity.generate()
        let recordA = a.privateKeyData()
        let storage = FakeSecretStorage(data: recordA, readStatuses: [status])
        let store = IdentityStore(storage: storage)

        #expect(throws: IdentityStorageError.unavailable(status: status)) {
            try store.loadOrCreate()
        }
        #expect(storage.addCount == 0)
        #expect(storage.data == recordA)

        // Keychain снова доступен — та же личность A.
        let restored = try store.loadOrCreate()
        #expect(restored.publicKey == a.publicKey)
        #expect(storage.addCount == 0)
        #expect(storage.data == recordA)
    }

    @Test("Запись не той длины — ошибка, запись не меняется и новая не создаётся", arguments: [0, 63, 65])
    func corruptedRecordIsError(length: Int) throws {
        let record = Data(repeating: 0x5A, count: length)
        let storage = FakeSecretStorage(data: record)

        #expect(throws: IdentityStorageError.corruptedRecord(byteCount: length)) {
            try IdentityStore(storage: storage).loadOrCreate()
        }
        #expect(storage.addCount == 0)
        #expect(storage.data == record)
    }

    @Test("Запись появилась у другого запуска (errSecDuplicateItem) — используется она, а не перезаписывается")
    func duplicateOnAddReadsExisting() throws {
        let b = Identity.generate()
        let recordB = b.privateKeyData()
        let storage = FakeSecretStorage(
            readStatuses: [errSecItemNotFound], addStatus: errSecDuplicateItem,
            onAdd: { $0.put(recordB) })

        let identity = try IdentityStore(storage: storage).loadOrCreate()

        #expect(identity.publicKey == b.publicKey)
        #expect(storage.data == recordB)
        #expect(storage.addCount == 1)
        #expect(storage.operations == ["read", "add", "read"])
    }

    /// `errSecIO` (-36) — в Security.framework так называется ошибка ввода-вывода `errSecIOErr`.
    @Test("Ошибка записи новой личности (errSecIOErr) — ошибка, а не несохранённая личность")
    func addFailureThrows() {
        let storage = FakeSecretStorage(addStatus: errSecIO)

        #expect(throws: IdentityStorageError.unavailable(status: errSecIO)) {
            try IdentityStore(storage: storage).loadOrCreate()
        }
        #expect(storage.data == nil)
        #expect(storage.operations == ["read", "add"])
    }

    @Test("Хранилище в памяти для UI-тестов: сбой чтения один раз, затем работает; дубликат не перезаписывает")
    func inMemoryStorage() throws {
        let storage = InMemorySecretStorage(failingReads: [errSecInteractionNotAllowed])
        let store = IdentityStore(storage: storage)

        #expect(throws: IdentityStorageError.unavailable(status: errSecInteractionNotAllowed)) {
            try store.loadOrCreate()
        }
        let created = try store.loadOrCreate()
        #expect(try store.loadOrCreate().publicKey == created.publicKey)
        #expect(storage.add(Identity.generate().privateKeyData()) == errSecDuplicateItem)
        #expect(try store.loadOrCreate().publicKey == created.publicKey)
    }
}

@Suite("Чтение личности для клавиатуры")
struct IdentityReaderTests {
    @Test("Записи нет — «ключа нет», ничего не создаётся")
    func missing() {
        let storage = FakeSecretStorage()
        let result = IdentityReader(storage: storage).read()

        guard case .missing = result else {
            Issue.record("ожидалось .missing, получено \(result)")
            return
        }
        #expect(storage.addCount == 0)
        #expect(storage.data == nil)
    }

    @Test("Запись A есть — личность A")
    func readsIdentity() {
        let a = Identity.generate()
        let storage = FakeSecretStorage(data: a.privateKeyData())
        let result = IdentityReader(storage: storage).read()

        guard case .identity(let identity) = result else {
            Issue.record("ожидалась личность, получено \(result)")
            return
        }
        #expect(identity.publicKey == a.publicKey)
        #expect(storage.addCount == 0)
    }

    @Test(
        "Keychain недоступен — «хранилище недоступно», а не «ключа нет»",
        arguments: [errSecInteractionNotAllowed, errSecMissingEntitlement])
    func unavailable(status: OSStatus) {
        let storage = FakeSecretStorage(data: Identity.generate().privateKeyData(), readStatuses: [status])
        let result = IdentityReader(storage: storage).read()

        guard case .unavailable(let error) = result else {
            Issue.record("ожидалось .unavailable, получено \(result)")
            return
        }
        #expect(error == .unavailable(status: status))
        #expect(storage.addCount == 0)
    }

    @Test("Запись из 63 байт — «хранилище недоступно»")
    func corrupted() {
        let record = Data(repeating: 1, count: 63)
        let storage = FakeSecretStorage(data: record)
        let result = IdentityReader(storage: storage).read()

        guard case .unavailable(let error) = result else {
            Issue.record("ожидалось .unavailable, получено \(result)")
            return
        }
        #expect(error == .corruptedRecord(byteCount: 63))
        #expect(storage.addCount == 0)
        #expect(storage.data == record)
    }
}
