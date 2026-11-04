@testable import CipherCore
import Foundation
import Testing
@testable import KeyboardTyping

@MainActor private final class Host: CiphertextHost {
    var documentIdentifier = UUID()
    var hasSelection = false
    var inserted: [String] = []
    var afterInsert: (() -> Void)?
    func insertCiphertext(_ ciphertext: String) { inserted.append(ciphertext); afterInsert?() }
}
@MainActor private final class Preference: RecipientPreference {
    var reads = 0, writes = 0
    var writtenValues: [UUID?] = []
    private var value: UUID?
    var recipientID: UUID? {
        get { reads += 1; return value }
        set { writes += 1; writtenValues.append(newValue); value = newValue }
    }
}
private actor SealCounter {
    var calls = 0
    func run(_ text: String, _ sender: Identity, _ key: PublicKey) throws -> String {
        calls += 1
        return try CipherMessage.seal(text, from: sender, to: [key])
    }
}
private actor SealGate {
    var calls = 0
    private var continuation: CheckedContinuation<Void, Never>?
    func run(_ text: String, _ sender: Identity, _ key: PublicKey) async throws -> String {
        calls += 1
        await withCheckedContinuation { continuation = $0 }
        return try CipherMessage.seal(text, from: sender, to: [key])
    }
    func finish() { continuation?.resume(); continuation = nil }
}
@MainActor private final class Rig {
    let a = Identity.generate(), b = Identity.generate(), c = Identity.generate()
    let host = Host(), preference = Preference(), input = KeyboardInputAdapter()
    var permitted = true
    var identity: IdentityReadResult!
    var book: ContactsReadResult!
    var identityReads = 0, bookReads = 0
    var coordinator: EncryptInsertCoordinator!
    var contact: Contact!
    init(seal: EncryptInsertCoordinator.Sealer? = nil) {
        identity = .identity(a)
        contact = Contact(id: UUID(), name: "Анна", publicKey: b.publicKey)
        book = .contacts([contact])
        if let seal {
            coordinator = EncryptInsertCoordinator(
                adapter: input, host: host, preference: preference, access: { [unowned self] in permitted },
                identity: { [unowned self] in
                    identityReads += 1; return identity
                },
                contacts: { [unowned self] in
                    bookReads += 1; return book
                }, seal: seal)
        } else {
            coordinator = EncryptInsertCoordinator(
                adapter: input, host: host, preference: preference, access: { [unowned self] in permitted },
                identity: { [unowned self] in
                    identityReads += 1; return identity
                },
                contacts: { [unowned self] in
                    bookReads += 1; return book
                })
        }
    }
    func ready(_ text: String = "Привет, Анна!") {
        coordinator.open(); coordinator.select(contact.id); input.seedForTesting(text, cursor: 2)
    }
    func settle() async {
        for _ in 0..<2000 {
            if !coordinator.busy { return }
            try? await Task.sleep(for: .milliseconds(1))
        }
        Issue.record("Coordinator failed to settle")
    }
}

@Suite @MainActor struct EncryptInsertTests {
    @Test func singleMessageWarningDoesNotOverrideErrorsOrChangeDraft() async throws {
        let r = Rig()
        r.ready(String(repeating: "я", count: 1360))
        #expect(r.coordinator.status == "Готово к шифрованию")
        r.input.activate(.character("a"))
        #expect(r.coordinator.status == "Для Telegram сократите до 2720 байт")
        #expect(r.coordinator.canEncrypt)
        let draft = r.input.input.text
        r.permitted = false
        #expect(r.coordinator.status == EncryptInsertCoordinator.accessMessage)
        #expect(r.input.input.text == draft)
        r.permitted = true
        r.input.activate(.delete)
        #expect(r.coordinator.status == "Готово к шифрованию")
        #expect(r.input.input.byteCount == 2720)
    }
    @Test func rememberedRecipientID() {
        let r = Rig(); r.coordinator.open()
        #expect(r.coordinator.selected == nil)
        r.input.seedForTesting("черновик", cursor: 3)
        r.coordinator.openPicker(); #expect(r.coordinator.pickerOpen)
        r.coordinator.closePicker(); #expect(r.coordinator.selected == nil)
        r.coordinator.select(r.contact.id)
        #expect(r.input.input.text == "черновик"); #expect(r.input.input.cursor == 3)
        #expect(r.preference.recipientID == r.contact.id)
        r.coordinator.hide(); r.coordinator.open()
        #expect(r.coordinator.selected?.id == r.contact.id)
        r.book = .contacts([Contact(id: r.contact.id, name: "Анна новая", publicKey: r.b.publicKey)])
        r.coordinator.hide(); r.coordinator.open()
        #expect(r.coordinator.selected?.name == "Анна новая")
        #expect(r.coordinator.selected?.id == r.contact.id)
        r.book = .contacts([Contact(id: UUID(), name: "Анна новая", publicKey: r.c.publicKey)])
        r.coordinator.hide(); r.coordinator.open()
        #expect(r.preference.recipientID == nil); #expect(r.coordinator.selected == nil)
        #expect(r.preference.writtenValues.count == 2)
        #expect(r.preference.writtenValues.first == r.contact.id)
        #expect(r.preference.writtenValues.last == .some(nil))
    }
    @Test func eligibility() async throws {
        for text in ["", " ", "\n\t ", "\u{00A0}", " а\n "] {
            for selected in [false, true] {
                for identityState in 0..<3 {
                    let counter = SealCounter()
                    let r = Rig(seal: { try await counter.run($0, $1, $2) })
                    if identityState == 1 { r.identity = .missing }
                    if identityState == 2 { r.identity = .unavailable(.unavailable(status: -1)) }
                    r.coordinator.open()
                    if selected { r.coordinator.select(r.contact.id) }
                    r.input.seedForTesting(text)
                    let expected =
                        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && selected && identityState == 0
                    #expect(r.coordinator.canEncrypt == expected)
                    r.coordinator.encrypt()  // Directly exercise the boundary even when UI would be disabled.
                    await r.settle()
                    #expect(await counter.calls == (expected ? 1 : 0))
                    #expect(r.host.inserted.count == (expected ? 1 : 0))
                    if expected {
                        #expect(
                            try CipherMessage.open(#require(r.host.inserted.only), as: r.b, contacts: []).text == text)
                    } else {
                        #expect(r.input.input.text == text)
                    }
                }
            }
        }
    }
    @Test func insertedCiphertextRoundTrip() async throws {
        for text in ["Привет, Анна!", "  👨‍👩‍👧‍👦 е\u{301}\nПривет  \n", String(repeating: "a", count: 4096)] {
            let r = Rig(); r.ready(text); r.coordinator.encrypt(); await r.settle()
            let value = try #require(r.host.inserted.only)
            #expect(value.hasPrefix("ckmsg2:")); #expect(!value.contains(where: { $0.isWhitespace }))
            let opened = try CipherMessage.open(value, as: r.b, contacts: [])
            #expect(Array(opened.text.utf8) == Array(text.utf8)); #expect(opened.senderKey == r.a.publicKey)
            #expect(opened.sender == .unknown(r.a.publicKey.fingerprint))
            let sender = Contact(id: UUID(), name: "Алексей", publicKey: r.a.publicKey)
            #expect(
                try CipherMessage.open(value, as: r.b, contacts: [sender]).sender
                    == .contact(sender))
            #expect(try CipherMessage.open(value, as: r.a, contacts: []).sender == .me)
            #expect(throws: CipherError.notARecipient) { try CipherMessage.open(value, as: r.c, contacts: []) }
            #expect(r.input.input.text.isEmpty); #expect(r.input.input.cursor == 0)
            #expect(r.coordinator.selected?.id == r.contact.id)
        }
    }
    @Test func singleFlight() async {
        let gate = SealGate(), r = Rig(seal: { try await gate.run($0, $1, $2) })
        r.ready(); let text = r.input.input.text, cursor = r.input.input.cursor
        r.coordinator.encrypt(); r.coordinator.encrypt()
        #expect(r.coordinator.status == "Шифруем…")
        r.input.activate(.character("х")); r.input.activate(.delete)
        r.coordinator.select(UUID()); r.coordinator.openPicker()
        #expect(r.input.input.text == text); #expect(r.input.input.cursor == cursor)
        while await gate.calls == 0 { await Task.yield() }
        #expect(await gate.calls == 1)
        await gate.finish(); await r.settle()
        #expect(r.host.inserted.count == 1)
        r.coordinator.encrypt(); #expect(r.host.inserted.count == 1)
        r.input.activate(.character("а")); r.coordinator.encrypt()
        while await gate.calls < 2 { await Task.yield() }
        await gate.finish(); await r.settle(); #expect(r.host.inserted.count == 2)
    }
    @Test func failurePreservesDraft() async {
        for state in 0..<3 {
            let failing: EncryptInsertCoordinator.Sealer = { _, _, _ in throw CipherError.tampered }
            let r = Rig(seal: state == 2 ? failing : nil)
            r.ready(); let text = r.input.input.text, cursor = r.input.input.cursor
            if state == 0 { r.identity = .missing }
            if state == 1 { r.identity = .unavailable(.unavailable(status: -1)) }
            r.coordinator.encrypt(); await r.settle()
            #expect(r.host.inserted.isEmpty); #expect(r.input.input.text == text);
            #expect(r.input.input.cursor == cursor)
            #expect(
                r.coordinator.error
                    == [
                        EncryptInsertCoordinator.missingMessage, EncryptInsertCoordinator.keyErrorMessage,
                        EncryptInsertCoordinator.failureMessage,
                    ][state])
            if state < 2 {
                r.identity = .identity(r.a); r.coordinator.encrypt(); await r.settle();
                #expect(r.host.inserted.count == 1)
            }
        }
    }
    @Test func utf8Boundaries() async throws {
        for count in [3500, 3501, 4096] {
            for text in [
                String(repeating: "a", count: count),
                String(repeating: "я", count: count / 2) + (count % 2 == 1 ? "a" : ""),
            ] {
                let r = Rig(); r.ready(text)
                #expect(r.input.input.byteCount == count)
                #expect(r.input.input.counter == (count >= 2000 ? "\(count) / 4096 байт" : nil))
            }
        }
        let r = Rig(); r.ready(String(repeating: "😀", count: 1024)); r.input.activate(.character("a"))
        #expect(r.input.input.byteCount == 4096); #expect(r.input.input.limitError)
        #expect(r.coordinator.status == KeyboardInput.limitMessage)
        r.coordinator.encrypt(); await r.settle()
        #expect(try CipherMessage.open(#require(r.host.inserted.only), as: r.b, contacts: []).text.utf8.count == 4096)
        r.ready("текст"); let cursor = r.input.input.cursor
        r.coordinator.encryptForTesting(text: String(repeating: "a", count: 4097))
        #expect(r.host.inserted.count == 1); #expect(r.input.input.text == "текст");
        #expect(r.input.input.cursor == cursor)
        #expect(r.coordinator.error == "Слишком длинное сообщение: 4097 из 4096 байт")
    }
    @Test func recipientRevalidation() async throws {
        for delayed in [false, true] {
            for mutation in 0..<5 {
                let gate = SealGate(), r = Rig(seal: { try await gate.run($0, $1, $2) })
                r.ready()
                if delayed { r.coordinator.encrypt(); while await gate.calls == 0 { await Task.yield() } }
                switch mutation {
                case 0: r.book = .contacts([])
                case 1: r.book = .contacts([Contact(id: r.contact.id, name: "Анна", publicKey: r.c.publicKey)])
                case 2: r.book = .unreadable
                case 4:
                    let signingOnly = try PublicKey(
                        validatingRaw: r.b.publicKey.agreementRaw + r.c.publicKey.signingRaw)
                    r.book = .contacts([Contact(id: r.contact.id, name: "Анна", publicKey: signingOnly)])
                default: r.book = .contacts([Contact(id: r.contact.id, name: "Анна новая", publicKey: r.b.publicKey)])
                }
                if !delayed { r.coordinator.encrypt() }
                if delayed || mutation == 3 {
                    while await gate.calls == 0 { await Task.yield() }; await gate.finish(); await r.settle()
                }
                if mutation == 3 {
                    #expect(r.host.inserted.count == 1); #expect(r.coordinator.selected?.name == "Анна новая")
                } else {
                    #expect(r.host.inserted.isEmpty); #expect(!r.input.input.text.isEmpty)
                    #expect(
                        r.coordinator.error
                            == (mutation == 2
                                ? EncryptInsertCoordinator.contactsErrorMessage
                                : EncryptInsertCoordinator.changedMessage))
                    if mutation != 2 {
                        #expect(r.coordinator.selected == nil); #expect(r.preference.recipientID == nil)
                    }
                    if mutation == 2 {
                        r.book = .contacts([r.contact]); r.coordinator.refresh(); #expect(r.coordinator.canEncrypt)
                    }
                }
            }
        }
    }
    @Test func metadataDrivesStatusAndCommitWithoutReadingTheSecret() async throws {
        let sender = Identity.generate(), foreign = Identity.generate(), recipient = Identity.generate()
        let host = Host(), input = KeyboardInputAdapter(), preference = Preference(), gate = SealGate()
        let contact = Contact(name: "Анна", publicKey: recipient.publicKey)
        var secret = sender, secretReads = 0
        let model = EncryptInsertCoordinator(
            adapter: input, host: host, preference: preference, access: { true },
            identity: {
                secretReads += 1; return .identity(secret)
            },
            identityMetadata: { .publicKey(sender.publicKey) },
            contacts: { .contacts([contact]) },
            seal: { try await gate.run($0, $1, $2) })
        model.open(); model.refresh(); model.openPicker(); model.select(contact.id)
        input.seedForTesting("черновик", cursor: 3)
        #expect(model.canEncrypt)
        #expect(secretReads == 0)

        model.encrypt()
        while await gate.calls == 0 { await Task.yield() }
        #expect(secretReads == 1)
        await gate.finish()
        while model.busy { await Task.yield() }
        #expect(secretReads == 1)
        #expect(try CipherMessage.open(#require(host.inserted.only), as: recipient, contacts: []).text == "черновик")

        secret = foreign
        input.seedForTesting("другой черновик", cursor: 5)
        model.encrypt()
        while model.busy { await Task.yield() }
        #expect(secretReads == 2)
        #expect(await gate.calls == 1)
        #expect(host.inserted.count == 1)
        #expect(input.input.text == "другой черновик")
        #expect(model.error == EncryptInsertCoordinator.changedMessage)
        #expect(model.selected == nil)
    }

    @Test func identityRevalidation() async throws {
        for mutation in 0..<4 {
            let gate = SealGate(), r = Rig(seal: { try await gate.run($0, $1, $2) })
            r.ready(); r.coordinator.encrypt(); while await gate.calls == 0 { await Task.yield() }
            r.identity =
                mutation == 0 ? .identity(r.c) : (mutation == 1 ? .missing : .unavailable(.unavailable(status: -1)))
            if mutation == 3 {
                r.identity = .identity(
                    try Identity(
                        privateKeyData: Data(r.a.privateKeyData().prefix(32) + r.c.privateKeyData().suffix(32))))
            }
            await gate.finish(); await r.settle()
            #expect(r.host.inserted.isEmpty); #expect(!r.input.input.text.isEmpty)
            #expect(
                r.coordinator.error
                    == [
                        EncryptInsertCoordinator.changedMessage, EncryptInsertCoordinator.missingMessage,
                        EncryptInsertCoordinator.keyErrorMessage, EncryptInsertCoordinator.changedMessage,
                    ][mutation])
        }
    }
    @Test func identityRecoveryRequiresExplicitSelection() async throws {
        for failedRead in 0..<3 {
            for signingOnly in [false, true] {
                for recovery in 0..<5 {
                    let counter = SealCounter(), r = Rig(seal: { try await counter.run($0, $1, $2) })
                    r.ready("  Привет 👋\n  ")
                    let text = r.input.input.text, cursor = r.input.input.cursor
                    var replacement = r.c
                    if signingOnly {
                        replacement = try Identity(
                            privateKeyData: Data(r.a.privateKeyData().prefix(32) + r.c.privateKeyData().suffix(32)))
                        #expect(replacement.publicKey.agreementRaw == r.a.publicKey.agreementRaw)
                        #expect(replacement.publicKey.signingRaw != r.a.publicKey.signingRaw)
                    }
                    if failedRead < 2 {
                        // Repeated failures through every synchronous reader entry must retain the baseline.
                        for attempt in 0..<4 {
                            r.identity =
                                (failedRead + attempt) % 2 == 0
                                ? .missing : .unavailable(.unavailable(status: -1))
                            switch attempt {
                            case 0: r.coordinator.encrypt()
                            case 1: r.coordinator.refresh()
                            case 2: r.coordinator.openPicker(); r.coordinator.closePicker()
                            default: r.coordinator.select(r.contact.id)
                            }
                            #expect(
                                r.coordinator.error
                                    == ((failedRead + attempt) % 2 == 0
                                        ? EncryptInsertCoordinator.missingMessage
                                        : EncryptInsertCoordinator.keyErrorMessage))
                            #expect(r.coordinator.identityKey == nil)
                            #expect(!r.coordinator.canEncrypt)
                            #expect(r.coordinator.selected?.id == r.contact.id)
                            #expect(r.preference.recipientID == r.contact.id)
                            #expect(r.input.input.text == text); #expect(r.input.input.cursor == cursor)
                            #expect(r.host.inserted.isEmpty); #expect(await counter.calls == 0)
                        }
                    }
                    r.identity = .identity(replacement)
                    switch recovery {
                    case 0: r.coordinator.encrypt()
                    case 1: r.coordinator.refresh()
                    case 2: r.coordinator.openPicker(); r.coordinator.closePicker()
                    case 3: r.coordinator.select(r.contact.id)
                    default: r.coordinator.open()  // An already active open performs refresh.
                    }
                    await r.settle()
                    #expect(r.coordinator.error == EncryptInsertCoordinator.changedMessage)
                    #expect(r.coordinator.selected == nil); #expect(r.preference.recipientID == nil)
                    #expect(r.preference.writtenValues.last == .some(nil))
                    #expect(r.coordinator.identityKey == replacement.publicKey)
                    #expect(!r.coordinator.canEncrypt)
                    #expect(r.host.inserted.isEmpty); #expect(await counter.calls == 0)
                    #expect(r.input.input.text == text); #expect(r.input.input.cursor == cursor)
                    // A direct retry must not accept a remembered choice; a new explicit choice must.
                    r.coordinator.encrypt(); await r.settle()
                    #expect(r.host.inserted.isEmpty); #expect(await counter.calls == 0)
                    r.coordinator.select(r.contact.id)
                    #expect(r.coordinator.canEncrypt)
                    #expect(r.preference.recipientID == r.contact.id)
                    #expect(r.input.input.text == text); #expect(r.input.input.cursor == cursor)
                    r.coordinator.encrypt(); await r.settle()
                    #expect(await counter.calls == 1)
                    let opened = try CipherMessage.open(#require(r.host.inserted.only), as: r.b, contacts: [])
                    #expect(opened.senderKey == replacement.publicKey)
                    #expect(Array(opened.text.utf8) == Array(text.utf8))
                    #expect(r.input.input.text.isEmpty); #expect(r.input.input.cursor == 0)
                }
            }
        }
    }
    @Test func identityRecoveryWithSameKeyRetries() async throws {
        for failedRead in 0..<2 {
            for recovery in 0..<3 {
                let counter = SealCounter(), r = Rig(seal: { try await counter.run($0, $1, $2) })
                r.ready(); let text = r.input.input.text, cursor = r.input.input.cursor
                r.identity = failedRead == 0 ? .missing : .unavailable(.unavailable(status: -1))
                r.coordinator.encrypt(); r.coordinator.refresh()
                #expect(r.coordinator.identityKey == nil); #expect(!r.coordinator.canEncrypt)
                #expect(r.coordinator.selected?.id == r.contact.id)
                #expect(r.preference.recipientID == r.contact.id)
                #expect(r.input.input.text == text); #expect(r.input.input.cursor == cursor)
                #expect(r.host.inserted.isEmpty); #expect(await counter.calls == 0)
                r.identity = .identity(r.a)
                if recovery == 1 { r.coordinator.refresh() }
                if recovery == 2 { r.coordinator.openPicker(); r.coordinator.closePicker() }
                if recovery > 0 {
                    #expect(r.coordinator.error == nil); #expect(r.coordinator.canEncrypt)
                    #expect(r.input.input.text == text); #expect(r.input.input.cursor == cursor)
                }
                r.coordinator.encrypt(); await r.settle()
                #expect(await counter.calls == 1); #expect(r.preference.writes == 1)
                let opened = try CipherMessage.open(#require(r.host.inserted.only), as: r.b, contacts: [])
                #expect(opened.senderKey == r.a.publicKey); #expect(opened.text == text)
            }
        }
    }
    @Test func identityReadFailureAtCommitRetainsBaseline() async throws {
        for failedRead in 0..<2 {
            for replacement in 0..<3 {
                let gate = SealGate(), r = Rig(seal: { try await gate.run($0, $1, $2) })
                r.ready(); let text = r.input.input.text, cursor = r.input.input.cursor
                r.coordinator.encrypt(); while await gate.calls == 0 { await Task.yield() }
                r.identity = failedRead == 0 ? .missing : .unavailable(.unavailable(status: -1))
                await gate.finish(); await r.settle()
                #expect(
                    r.coordinator.error
                        == (failedRead == 0
                            ? EncryptInsertCoordinator.missingMessage : EncryptInsertCoordinator.keyErrorMessage))
                #expect(r.host.inserted.isEmpty); #expect(r.coordinator.selected?.id == r.contact.id)
                #expect(r.coordinator.identityKey == nil); #expect(!r.coordinator.canEncrypt)
                #expect(r.preference.recipientID == r.contact.id)
                #expect(r.input.input.text == text); #expect(r.input.input.cursor == cursor)
                let restored: Identity
                switch replacement {
                case 0: restored = r.a
                case 1: restored = r.c
                default:
                    restored = try Identity(
                        privateKeyData: Data(r.a.privateKeyData().prefix(32) + r.c.privateKeyData().suffix(32)))
                }
                r.identity = .identity(restored); r.coordinator.encrypt()
                if replacement > 0 {
                    #expect(r.coordinator.error == EncryptInsertCoordinator.changedMessage)
                    #expect(r.coordinator.selected == nil); #expect(r.preference.recipientID == nil)
                    #expect(r.host.inserted.isEmpty); #expect(await gate.calls == 1)
                    #expect(r.input.input.text == text); #expect(r.input.input.cursor == cursor)
                    r.coordinator.select(r.contact.id); r.coordinator.encrypt()
                }
                while await gate.calls < 2 { await Task.yield() }
                await gate.finish(); await r.settle()
                let opened = try CipherMessage.open(#require(r.host.inserted.only), as: r.b, contacts: [])
                #expect(opened.senderKey == restored.publicKey); #expect(opened.text == text)
            }
        }
    }
    @Test func firstAvailableIdentityDoesNotCountAsReplacement() async throws {
        for failedRead in 0..<2 {
            for remembered in [false, true] {
                let r = Rig()
                if remembered { r.preference.recipientID = r.contact.id }
                r.identity = failedRead == 0 ? .missing : .unavailable(.unavailable(status: -1))
                r.coordinator.open()
                #expect((r.coordinator.selected != nil) == remembered)
                if !remembered { r.coordinator.select(r.contact.id) }
                r.input.seedForTesting("черновик", cursor: 3)
                r.coordinator.refresh(); r.identity = .identity(r.a); r.coordinator.refresh()
                #expect(r.coordinator.error == nil); #expect(r.coordinator.canEncrypt)
                #expect(r.coordinator.selected?.id == r.contact.id)
                #expect(r.preference.recipientID == r.contact.id)
                #expect(r.input.input.text == "черновик"); #expect(r.input.input.cursor == 3)
                r.coordinator.encrypt(); await r.settle()
                let opened = try CipherMessage.open(#require(r.host.inserted.only), as: r.b, contacts: [])
                #expect(opened.senderKey == r.a.publicKey); #expect(opened.text == "черновик")
            }
        }
    }
    @Test func identityBaselineEndsWithSession() async throws {
        for failedRead in 0..<2 {
            let r = Rig(); r.ready()
            r.identity = failedRead == 0 ? .missing : .unavailable(.unavailable(status: -1))
            r.coordinator.encrypt(); r.coordinator.hide()
            #expect(r.input.input.text.isEmpty); #expect(r.input.input.cursor == 0)
            #expect(r.coordinator.identityKey == nil); #expect(r.coordinator.selected == nil)
            r.identity = .identity(r.c); r.coordinator.open()
            #expect(r.coordinator.error == nil); #expect(r.coordinator.selected?.id == r.contact.id)
            r.input.seedForTesting("новая сессия", cursor: 4)
            r.coordinator.encrypt(); await r.settle()
            let opened = try CipherMessage.open(#require(r.host.inserted.only), as: r.b, contacts: [])
            #expect(opened.senderKey == r.c.publicKey); #expect(opened.text == "новая сессия")
        }
    }
    @Test func identityMetadataTracksCurrentReadWithoutLosingRecoveryBaseline() {
        let r = Rig(); r.ready()
        let valid = "Ваш ключ: " + r.a.publicKey.fingerprint.short
        #expect(r.coordinator.identityMetadata == valid + " · Контактов: 1")
        for failure in 0..<2 {
            r.identity = failure == 0 ? .missing : .unavailable(.unavailable(status: -1))
            r.coordinator.refresh()
            #expect(r.coordinator.identityKey == nil); #expect(!r.coordinator.canEncrypt)
            #expect(
                r.coordinator.identityMetadata
                    == (failure == 0
                        ? "Личный ключ ещё не создан" : "Не удалось открыть хранилище ключей"))
            #expect(r.coordinator.selected?.id == r.contact.id)
        }
        r.identity = .identity(r.a); r.book = .unreadable; r.coordinator.refresh()
        #expect(r.coordinator.identityMetadata == valid)
        #expect(r.coordinator.selected?.id == r.contact.id)
        r.book = .contacts([r.contact]); r.coordinator.refresh()
        #expect(r.coordinator.identityMetadata == valid + " · Контактов: 1")
        r.permitted = false
        let reads = r.identityReads + r.bookReads, preferences = r.preference.reads + r.preference.writes
        r.coordinator.refresh()
        #expect(r.coordinator.identityMetadata == "Общие данные недоступны")
        #expect(r.identityReads + r.bookReads == reads)
        #expect(r.preference.reads + r.preference.writes == preferences)
    }
    @Test func defensiveLimitFixtureContainsRealApprovedExcerptAnd4097Bytes() {
        let r = Rig(); r.ready()
        r.input.seedDefensiveLimitForTesting()
        let excerpt = "Синтетический черновик: 4097 байт…\n(полный текст — в тестовой зависимости)\n"
        #expect(r.input.input.text.hasPrefix(excerpt))
        #expect(r.input.input.byteCount == 4097); #expect(r.input.input.counter == "4097 / 4096 байт")
        let text = r.input.input.text, cursor = r.input.input.cursor
        r.coordinator.encrypt()
        #expect(r.coordinator.error == "Слишком длинное сообщение: 4097 из 4096 байт")
        #expect(r.host.inserted.isEmpty); #expect(!r.coordinator.busy)
        #expect(r.input.input.text == text); #expect(r.input.input.cursor == cursor)
    }
    @Test func accessGate() async {
        let r = Rig(); r.permitted = false
        r.coordinator.open(); r.coordinator.openPicker(); r.coordinator.select(r.contact.id)
        r.input.activate(.character("а")); r.coordinator.encrypt()
        #expect(r.input.input.text == "А")
        #expect(r.identityReads == 0); #expect(r.bookReads == 0); #expect(r.preference.reads == 0);
        #expect(r.preference.writes == 0)
        let gate = SealGate(), s = Rig(seal: { try await gate.run($0, $1, $2) })
        s.ready(); s.coordinator.encrypt(); while await gate.calls == 0 { await Task.yield() }
        let reads = s.identityReads + s.bookReads, prefs = s.preference.reads + s.preference.writes
        s.permitted = false; await gate.finish(); await s.settle()
        #expect(s.host.inserted.isEmpty); #expect(s.identityReads + s.bookReads == reads)
        #expect(s.preference.reads + s.preference.writes == prefs);
        #expect(s.coordinator.status == EncryptInsertCoordinator.accessMessage)
    }
    @Test func sessionAndDocumentCancellation() async {
        for event in 0..<5 {
            let gate = SealGate(), r = Rig(seal: { try await gate.run($0, $1, $2) })
            r.ready(); r.coordinator.encrypt(); while await gate.calls == 0 { await Task.yield() }
            if event < 3 {
                r.coordinator.hide(); r.coordinator.open()
            } else if event == 3 {
                r.host.documentIdentifier = UUID()
            } else {
                r.input.rotate()
            }
            await gate.finish(); await r.settle()
            if event == 4 { #expect(r.host.inserted.count == 1) } else { #expect(r.host.inserted.isEmpty) }
            if event < 3 { #expect(r.input.input.text.isEmpty) }
            if event == 3 {
                #expect(r.coordinator.error == EncryptInsertCoordinator.documentMessage);
                #expect(!r.input.input.text.isEmpty)
            }
        }
    }
    @Test func selectionRechecked() async {
        let gate = SealGate(), r = Rig(seal: { try await gate.run($0, $1, $2) })
        r.ready(); r.host.hasSelection = true; r.coordinator.encrypt(); #expect(!r.coordinator.busy)
        #expect(r.coordinator.error == EncryptInsertCoordinator.selectionMessage)
        r.host.hasSelection = false; r.coordinator.encrypt(); while await gate.calls == 0 { await Task.yield() }
        r.host.hasSelection = true; await gate.finish(); await r.settle()
        #expect(r.host.inserted.isEmpty); #expect(!r.input.input.text.isEmpty)
    }
    @Test func tamperedInsertedMessage() async throws {
        let r = Rig(); r.ready(); r.coordinator.encrypt(); await r.settle()
        let value = try #require(r.host.inserted.only)
        let payload = String(value.dropFirst(7)).replacingOccurrences(of: "-", with: "+").replacingOccurrences(
            of: "_", with: "/")
        var data = try #require(
            Data(base64Encoded: payload + String(repeating: "=", count: (4 - payload.count % 4) % 4)))
        for offset in [1, data.count / 2, data.count - 1] {
            data[offset] ^= 1
            let tampered =
                "ckmsg2:"
                + data.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(
                    of: "/", with: "_"
                ).replacingOccurrences(of: "=", with: "")
            #expect(throws: (any Error).self) { try CipherMessage.open(tampered, as: r.b, contacts: []) }
            data[offset] ^= 1
        }
        #expect(throws: (any Error).self) { try PublicKey(string: "ckpub1:invalid") }
    }
}
private extension Array { var only: Element? { count == 1 ? first : nil } }
