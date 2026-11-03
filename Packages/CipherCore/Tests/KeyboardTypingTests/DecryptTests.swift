@testable import CipherCore
@testable import KeyboardTyping
import Foundation
import Testing

@MainActor private final class DecryptClipboardSpy: DecryptClipboardReading {
    var value: ClipboardText = .empty
    var metadataReads = 0, contentReads = 0
    var suspended = false
    var continuation: CheckedContinuation<Void, Never>?
    func readText() async -> ClipboardText {
        metadataReads += 1; contentReads += 1
        let snapshot = value
        if suspended { await withCheckedContinuation { continuation = $0 } }
        return snapshot
    }
    func release() { continuation?.resume(); continuation = nil }
}
private actor DecryptOpenGate {
    var calls = 0
    private var continuations: [CheckedContinuation<Void, Never>] = []
    func run(_ text: String, _ identity: Identity, _ contacts: [Contact]) async throws -> OpenedMessage {
        calls += 1
        await withCheckedContinuation { continuations.append($0) }
        return try CipherMessage.open(text, as: identity, contacts: contacts)
    }
    func release(_ index: Int = 0) { continuations.remove(at: index).resume() }
}
@MainActor private final class DecryptRig {
    let a = Identity.generate(), b = Identity.generate(), c = Identity.generate()
    let clipboard = DecryptClipboardSpy()
    var permitted = true, blocked = false
    var document = UUID()
    var own: IdentityReadResult!
    var book: ContactsReadResult!
    var identityReads = 0, contactsReads = 0
    var model: DecryptCoordinator!
    init(
        surface: DecryptCoordinator.Surface = .keyboard,
        fingerprintText: @escaping (PublicKey) -> String = { $0.fingerprint.short },
        opener: DecryptCoordinator.Opener? = nil
    ) {
        own = .identity(b); book = .contacts([Contact(name: "Анна", publicKey: a.publicKey)])
        let real: DecryptCoordinator.Opener = { try CipherMessage.open($0, as: $1, contacts: $2) }
        model = DecryptCoordinator(
            surface: surface, access: { [unowned self] in permitted },
            identity: { [unowned self] in
                identityReads += 1; return own
            },
            contacts: { [unowned self] in
                contactsReads += 1; return book
            }, clipboard: clipboard,
            blocked: { [unowned self] in blocked }, document: { [unowned self] in document },
            fingerprintText: fingerprintText, opener: opener ?? real)
    }
    func ready(_ text: String = "  Привет, Анна!\nЗавтра в 19:30 👨‍👩‍👧‍👦  ") throws {
        clipboard.value = .text(try CipherMessage.seal(text, from: a, to: [b.publicKey]))
        model.activate()
    }
    func settle() async {
        for _ in 0..<2000 {
            if !model.busy { return }
            try? await Task.sleep(for: .milliseconds(1))
        }
        Issue.record("Decrypt operation failed to settle")
    }
}

@Suite @MainActor struct DecryptTests {
    @Test func explicitReadOnly() async throws {
        let r = DecryptRig(); try r.ready()
        r.model.refresh(); r.model.activate()
        let input = KeyboardInputAdapter(); input.activate(.language); input.rotate()
        for _ in 0..<20 { await Task.yield() }
        #expect(r.clipboard.metadataReads == 0); #expect(r.clipboard.contentReads == 0)
        #expect(r.model.canStart)
        r.model.start(); await r.settle()
        #expect(r.clipboard.metadataReads == 1); #expect(r.clipboard.contentReads == 1)
        #expect(r.model.result?.text == "  Привет, Анна!\nЗавтра в 19:30 👨‍👩‍👧‍👦  ")
        r.model.refresh(); #expect(r.clipboard.contentReads == 1)
    }
    @Test func senderIdentity() async throws {
        let r = DecryptRig(); try r.ready()
        r.model.start(); await r.settle(); #expect(r.model.result?.sender == "От: Анна")
        r.model.deactivate(); r.own = .identity(r.a); r.model.activate(); r.model.start(); await r.settle()
        #expect(r.model.result?.sender == "От: вы"); #expect(r.model.result?.unknown == false)
        r.model.deactivate(); r.own = .identity(r.b); r.model.activate()
        r.book = .contacts([Contact(name: "Анна", publicKey: r.c.publicKey)])
        r.model.start(); await r.settle()
        #expect(r.model.result?.sender == "От неизвестного ключа " + r.a.publicKey.fingerprint.short)
        #expect(r.model.result?.unknown == true)
        // Same agreement part with a different signing key must not acquire the contact's name.
        let changed = try PublicKey(string: "ckpub1:" + String(r.a.publicKey.string.dropFirst(7)))
        #expect(changed == r.a.publicKey)
        let parts = r.a.publicKey.agreementRaw + r.c.publicKey.signingRaw
        let other = try PublicKey(validatingRaw: parts)
        r.model.close(); r.book = .contacts([Contact(name: "Анна", publicKey: other)])
        r.model.start(); await r.settle(); #expect(r.model.result?.unknown == true)
    }
    @Test func displayFingerprintCollisionDoesNotAssignContact() async throws {
        let r = DecryptRig(fingerprintText: { _ in "A1B2 C3D4" })
        try r.ready()
        r.book = .contacts([Contact(name: "Анна", publicKey: r.c.publicKey)])
        r.model.start(); await r.settle()
        #expect(r.model.result?.sender == "От неизвестного ключа A1B2 C3D4")
        #expect(r.model.result?.unknown == true)
        for parts in [
            r.a.publicKey.agreementRaw + r.c.publicKey.signingRaw,
            r.c.publicKey.agreementRaw + r.a.publicKey.signingRaw,
        ] {
            let other = try PublicKey(validatingRaw: parts)
            r.model.close(); r.book = .contacts([Contact(name: "Анна", publicKey: other)])
            r.model.start(); await r.settle()
            #expect(r.model.result?.unknown == true)
        }
    }
    @Test func contactsRefresh() async throws {
        for event in 0..<5 {
            let gate = DecryptOpenGate(), r = DecryptRig(opener: { try await gate.run($0, $1, $2) })
            try r.ready(); if event == 4 { r.model.deactivate(); r.own = .identity(r.a); r.model.activate() }
            r.model.start(); while await gate.calls == 0 { await Task.yield() }
            switch event {
            case 0: r.book = .contacts([Contact(name: "Анна переименована", publicKey: r.a.publicKey)])
            case 1: r.book = .contacts([])
            case 2: r.book = .contacts([Contact(name: "Анна", publicKey: r.c.publicKey)])
            default: r.book = .unreadable
            }
            await gate.release(); await r.settle()
            #expect(r.contactsReads == 2)
            #expect(r.model.result?.text != nil)
            if event == 0 {
                #expect(r.model.result?.sender == "От: Анна переименована")
            } else if event == 4 {
                #expect(r.model.result?.sender == "От: вы"); #expect(r.model.result?.contactsWarning == false)
            } else {
                #expect(r.model.result?.unknown == true); #expect(r.model.result?.contactsWarning == (event == 3))
            }
        }
    }
    @Test func firstEnvelopeMatchesCore() async throws {
        let r = DecryptRig(); try r.ready()
        let valid = try CipherMessage.seal("первое", from: r.a, to: [r.b.publicKey])
        let second = try CipherMessage.seal("второе", from: r.a, to: [r.b.publicKey])
        let foreign = try CipherMessage.seal("чужое", from: r.a, to: [r.c.publicKey])
        let wrapped = valid.enumerated().map {
            $0.offset.isMultiple(of: 24) ? " \n" + String($0.element) : String($0.element)
        }.joined()
        for value in [
            "до " + valid + " после", wrapped, valid + " " + second,
            "ckmsg1:invalid " + second, foreign + " " + second, "ckmsg2:AA " + second, "", "фраза",
        ] {
            r.model.close(); r.clipboard.value = .text(value); r.model.start(); await r.settle()
            do {
                let direct = try CipherMessage.open(value, as: r.b, contacts: [])
                #expect(r.model.result?.text == direct.text); #expect(r.model.error == nil)
            } catch {
                #expect(r.model.result == nil); #expect(r.model.error != nil)
            }
        }
        let app = DecryptRig(surface: .app); app.model.activate(); app.model.setInput("фраза")
        app.model.start(); await app.settle()
        #expect(app.model.error == "В тексте нет зашифрованного сообщения")
        #expect(app.clipboard.contentReads == 0)
    }
    @Test func rejectedMessagesNeverPublishText() async throws {
        let r = DecryptRig(); try r.ready("SecretCanary07")
        let foreign = try CipherMessage.seal("чужое", from: r.a, to: [r.c.publicKey])
        for (value, expected) in [
            ("ckmsg1:invalid", "Сообщение повреждено или подделано"),
            (foreign, "Сообщение зашифровано не для вас"),
            ("ckmsg2:AA", "Сообщение из более новой версии CipherKeyboard — обновите приложение"),
            ("фраза", "В буфере нет зашифрованного сообщения. Скопируйте его в чате"),
        ] {
            r.model.start(); await r.settle(); #expect(r.model.result?.text == "SecretCanary07")
            r.clipboard.value = .text(value); r.model.start(); await r.settle()
            #expect(r.model.result == nil); #expect(r.model.error == expected)
            r.clipboard.value = .text(try CipherMessage.seal("SecretCanary07", from: r.a, to: [r.b.publicKey]))
        }
        let failing = DecryptRig(opener: { _, _, _ in throw CocoaError(.coderInvalidValue) })
        try failing.ready(); failing.model.start(); await failing.settle()
        #expect(failing.model.error == DecryptCoordinator.failureMessage); #expect(failing.model.result == nil)
    }
    @Test func tamperedBytesAndSenderNeverPublish() async throws {
        let r = DecryptRig(); try r.ready("VerifiedCanary07")
        let valid = try CipherMessage.seal("VerifiedCanary07", from: r.a, to: [r.b.publicKey])
        let raw = try #require(Base64URL.decode(Array(valid.dropFirst(7).utf8)))
        var envelope = try Envelope(bytes: raw)
        envelope.senderKey = r.c.publicKey.raw
        let forged = envelope.string
        var variants = [String(valid.dropLast()), forged]
        for index in [raw.count / 2, raw.count - 1] {
            var changed = raw; changed[index] ^= 1
            variants.append("ckmsg1:" + Base64URL.encode(changed))
        }
        for invalid in variants {
            r.clipboard.value = .text(valid); r.model.start(); await r.settle()
            #expect(r.model.result?.text == "VerifiedCanary07")
            r.clipboard.value = .text(invalid); r.model.start(); await r.settle()
            #expect(r.model.result == nil)
            #expect(r.model.error == "Сообщение повреждено или подделано")
        }
    }
    @Test func accessAndIdentity() async throws {
        let r = DecryptRig(); r.permitted = false; r.model.activate(); r.model.start()
        #expect(r.identityReads == 0); #expect(r.contactsReads == 0); #expect(r.clipboard.contentReads == 0)
        #expect(r.model.error == DecryptCoordinator.accessMessage)
        r.permitted = true; r.own = .missing; r.model.refresh()
        #expect(r.model.error == EncryptInsertCoordinator.missingMessage); #expect(!r.model.canStart)
        r.own = .unavailable(.corruptedRecord(byteCount: 3)); r.model.refresh()
        #expect(r.model.error == EncryptInsertCoordinator.keyErrorMessage)
        for event in 0..<2 {
            let gate = DecryptOpenGate(), s = DecryptRig(opener: { try await gate.run($0, $1, $2) })
            try s.ready(); s.model.start(); while await gate.calls == 0 { await Task.yield() }
            if event == 0 { s.permitted = false } else { s.own = .identity(s.c) }
            await gate.release(); await s.settle(); #expect(s.model.result == nil)
            if event == 1 { #expect(s.model.error == DecryptCoordinator.changedMessage) }
        }
    }
    @Test func singleFlightAndCancel() async throws {
        let gate = DecryptOpenGate(), r = DecryptRig(opener: { try await gate.run($0, $1, $2) })
        try r.ready("old"); r.clipboard.suspended = true
        r.model.start(); r.model.start()
        while r.clipboard.contentReads == 0 { await Task.yield() }
        #expect(r.model.busy); #expect(r.model.status == "Расшифровываем…")
        r.clipboard.value = .text(try CipherMessage.seal("new", from: r.a, to: [r.b.publicKey]))
        r.clipboard.release(); while await gate.calls == 0 { await Task.yield() }
        #expect(r.clipboard.contentReads == 1)
        r.model.close(); #expect(!r.model.busy); #expect(r.model.result == nil)
        r.clipboard.suspended = false; r.model.start()
        while await gate.calls < 2 { await Task.yield() }
        await gate.release(1); await r.settle(); #expect(r.model.result?.text == "new")
        await gate.release(); for _ in 0..<50 { await Task.yield() }
        #expect(r.model.result?.text == "new"); #expect(!r.model.busy)
        r.model.close(); r.blocked = true; r.model.start(); #expect(r.clipboard.contentReads == 2)
    }
    @Test func preservesComposeAndHost() async throws {
        let r = DecryptRig(); try r.ready()
        let adapter = KeyboardInputAdapter(); adapter.seedForTesting("До встречи!\nВозьми документы.", cursor: 5)
        let snapshot = adapter.input
        let host = DecryptHostSpy()
        let encrypt = EncryptInsertCoordinator(
            adapter: adapter, host: host, preference: DecryptPreference(),
            access: { true }, identity: { .identity(r.b) }, contacts: { r.book })
        encrypt.open()
        let contact = encrypt.contacts[0]
        encrypt.select(contact.id)
        let recipient = encrypt.selected
        encrypt.externallyBlocked = { r.model.presenting }
        #expect(encrypt.canEncrypt)
        r.model.start(); #expect(!encrypt.canEncrypt); encrypt.encrypt()
        await r.settle(); r.model.close()
        #expect(encrypt.canEncrypt)
        #expect(adapter.input.text == snapshot.text); #expect(adapter.input.cursor == snapshot.cursor)
        #expect(host.insertions == 0); #expect(encrypt.selected == recipient)
        #expect(host.field == "до | после"); #expect(host.selection == NSRange(location: 3, length: 1))
    }
    @Test func lifecycleInvalidatesGeneration() async throws {
        for event in 0..<6 {
            let gate = DecryptOpenGate(), r = DecryptRig(opener: { try await gate.run($0, $1, $2) })
            try r.ready(); r.model.start(); while await gate.calls == 0 { await Task.yield() }
            if event == 4 {
                r.document = UUID()
            } else if event == 5 {
                r.permitted = false; r.model.refresh()
            } else {
                r.model.deactivate(); r.model.activate()
            }
            await gate.release(); await r.settle()
            #expect(r.model.result == nil); #expect(r.model.input.isEmpty); #expect(!r.model.busy)
        }
    }
    @Test func utf8Bounds() async throws {
        let r = DecryptRig(surface: .app); r.model.activate()
        let plain = String(repeating: "🙂", count: 1024)
        #expect(plain.utf8.count == 4096)
        let envelope = try CipherMessage.seal(plain, from: r.a, to: [r.b.publicKey])
        let atLimit = String(repeating: " ", count: 65536 - envelope.utf8.count) + envelope
        #expect(r.model.setInput(atLimit)); r.model.start(); await r.settle()
        #expect(r.model.result?.text == plain)
        r.model.close(); #expect(r.model.setInput("старый ввод"))
        #expect(!r.model.setInput(atLimit + "a")); #expect(r.model.input == "старый ввод")
        #expect(r.model.error == DecryptCoordinator.oversize)
        #expect(!r.model.setInput(String(repeating: "🙂", count: 16385)))
        #expect(r.model.input == "старый ввод")
        let keyboard = DecryptRig(); try keyboard.ready(); keyboard.clipboard.value = .text(atLimit + "a")
        keyboard.model.start(); await keyboard.settle(); #expect(keyboard.model.error == DecryptCoordinator.oversize)
        #expect(keyboard.model.result == nil)
        #expect(throws: CipherError.messageTooLong(byteCount: 4097)) {
            try CipherMessage.seal(plain + "a", from: r.a, to: [r.b.publicKey])
        }
    }
    @Test func cancelledCoordinatorIsReleased() async throws {
        let gate = DecryptOpenGate()
        var rig: DecryptRig? = DecryptRig(opener: { try await gate.run($0, $1, $2) })
        try rig?.ready(); rig?.model.start()
        while await gate.calls == 0 { await Task.yield() }
        weak let weakModel = rig?.model
        rig?.model.deactivate(); rig = nil
        #expect(weakModel == nil)
        await gate.release()
    }
    @Test func clipboardClassification() async throws {
        let r = DecryptRig(); try r.ready()
        for (value, expected) in [
            (ClipboardText.empty, "В буфере нет зашифрованного сообщения. Скопируйте его в чате"),
            (.denied, DecryptCoordinator.clipboardMessage),
        ] {
            r.clipboard.value = value; r.model.start(); await r.settle()
            #expect(r.model.error == expected); #expect(r.model.result == nil)
        }
        #expect(r.clipboard.contentReads == 2)
    }
}
@MainActor private final class DecryptHostSpy: CiphertextHost {
    var documentIdentifier = UUID(), hasSelection = true
    var field = "до | после", selection = NSRange(location: 3, length: 1), insertions = 0
    func insertCiphertext(_ ciphertext: String) { insertions += 1; field = ciphertext }
}
@MainActor private final class DecryptPreference: RecipientPreference { var recipientID: UUID? }
