import CryptoKit
import Foundation
import Testing

@testable import CipherCore

@Suite("Не получатель не читает сообщение")
struct NotARecipientTests {
    private let text = "Только для B"
    private let a = Identity.generate()
    private let b = Identity.generate()
    private let c = Identity.generate()

    @Test("Посторонний C без контактов → notARecipient")
    func strangerWithoutContacts() throws {
        let m = try CipherMessage.seal(text, from: a, to: [b.publicKey])
        #expect(throws: CipherError.notARecipient) { _ = try CipherMessage.open(m, as: c, contacts: []) }
    }

    @Test("Посторонний C с контактами A и B → notARecipient")
    func strangerWithContacts() throws {
        let m = try CipherMessage.seal(text, from: a, to: [b.publicKey])
        let contacts = [Contact(name: "A", publicKey: a.publicKey), Contact(name: "B", publicKey: b.publicKey)]
        #expect(throws: CipherError.notARecipient) { _ = try CipherMessage.open(m, as: c, contacts: contacts) }
    }

    @Test("Личность, восстановленная из данных C, → notARecipient")
    func restoredStranger() throws {
        let m = try CipherMessage.seal(text, from: a, to: [b.publicKey])
        let restored = try Identity(privateKeyData: c.privateKeyData())
        #expect(throws: CipherError.notARecipient) { _ = try CipherMessage.open(m, as: restored, contacts: []) }
    }

    @Test("Личность из X25519 от C и Ed25519 от B → notARecipient (запись ищется по ключу согласования)")
    func mixedHalves() throws {
        let m = try CipherMessage.seal(text, from: a, to: [b.publicKey])
        let mixed = try Identity(privateKeyData: c.privateKeyData()[0..<32] + b.privateKeyData()[32..<64])
        #expect(throws: CipherError.notARecipient) { _ = try CipherMessage.open(m, as: mixed, contacts: []) }
    }
}

@Suite("Изменение любого байта или символа не проходит")
struct ByteTamperTests {
    @Test("Каждый байт с инвертированным младшим битом → tampered или malformed, для B и для A")
    func everyByteFlipped() throws {
        let a = Identity.generate()
        let b = Identity.generate()
        let m = try CipherMessage.seal("Переведи 100 рублей Пете", from: a, to: [b.publicKey])
        let decoded = try #require(decodedMessage(m))
        var checked = 0
        for index in decoded.indices {
            var corrupted = decoded
            corrupted[index] ^= 0x01
            let text = "ckmsg1:" + base64url(corrupted)
            for (name, identity) in [("B", b), ("A", a)] {
                do {
                    _ = try CipherMessage.open(text, as: identity, contacts: [])
                    Issue.record("байт \(index), \(name): изменённое сообщение открылось")
                } catch let error as CipherError {
                    #expect(error == .tampered || error == .malformed, "байт \(index), \(name): \(error)")
                    #expect(error != .notARecipient, "байт \(index), \(name)")
                }
            }
            checked += 1
        }
        #expect(checked == decoded.count)
    }

    @Test("Каждый символ после ckmsg1:, заменённый следующим символом base64url, → ошибка")
    func everyCharacterReplaced() throws {
        let a = Identity.generate()
        let b = Identity.generate()
        let m = try CipherMessage.seal("Переведи 100 рублей Пете", from: a, to: [b.publicKey])
        let prefixLength = "ckmsg1:".count
        let chars = Array(m)
        var checked = 0
        for offset in prefixLength..<chars.count {
            let replacement = try #require(nextBase64urlCharacter(after: chars[offset]))
            let text = replacingCharacter(in: m, at: offset, with: replacement)
            #expect(throws: (any Error).self, "символ \(offset)") {
                _ = try CipherMessage.open(text, as: b, contacts: [])
            }
            checked += 1
        }
        #expect(checked == chars.count - prefixLength)
    }
}

@Suite("Отправителя нельзя подменить")
struct SenderSpoofTests {
    private let text = "Это написал A"
    private let a = Identity.generate()
    private let b = Identity.generate()
    private let mallory = Identity.generate()

    private func envelope(of message: String) throws -> Envelope {
        try Envelope(bytes: try #require(decodedMessage(message)))
    }

    @Test("Разобранное и собранное заново сообщение открывается — подделки ниже собраны верно")
    func reassembledMessageOpens() throws {
        let m = try CipherMessage.seal(text, from: a, to: [b.publicKey])
        let rebuilt = try envelope(of: m).string
        #expect(rebuilt == m)
        #expect(try CipherMessage.open(rebuilt, as: b, contacts: []).text == text)
    }

    @Test("Подпись M над теми же байтами при ключе отправителя A → tampered")
    func signatureReplacedByMallory() throws {
        var forged = try envelope(of: CipherMessage.seal(text, from: a, to: [b.publicKey]))
        forged.signature = Array(try mallory.signingKey().signature(for: forged.signedBytes))
        #expect(throws: CipherError.tampered) { _ = try CipherMessage.open(forged.string, as: b, contacts: []) }
    }

    @Test("Ключ отправителя заменён на ключ M и подпись пересчитана M → tampered")
    func senderKeyReplacedAndResigned() throws {
        var forged = try envelope(of: CipherMessage.seal(text, from: a, to: [b.publicKey]))
        forged.senderKey = try #require(rawKey(mallory.publicKey))
        forged.signature = Array(try mallory.signingKey().signature(for: forged.signedBytes))
        let contacts = [Contact(name: "M", publicKey: mallory.publicKey)]
        #expect(throws: CipherError.tampered) {
            _ = try CipherMessage.open(forged.string, as: b, contacts: contacts)
        }
    }

    @Test("Подпись из 64 нулевых байт → tampered")
    func zeroSignature() throws {
        var forged = try envelope(of: CipherMessage.seal(text, from: a, to: [b.publicKey]))
        forged.signature = [UInt8](repeating: 0, count: 64)
        #expect(throws: CipherError.tampered) { _ = try CipherMessage.open(forged.string, as: b, contacts: []) }
    }

    /// Нейтральная точка Ed25519 и «подпись» R = нейтральная точка, S = 0: верна для любых байт при таком ключе.
    private static let identityPoint: [UInt8] = [1] + [UInt8](repeating: 0, count: 31)
    private static let identitySignature: [UInt8] = identityPoint + [UInt8](repeating: 0, count: 32)

    /// Сообщение для B, собранное вручную по FORMAT.md (без `seal`), с любым ключом отправителя и подписью.
    private func handmade(senderKey: [UInt8], sign: ([UInt8]) throws -> [UInt8]) throws -> String {
        let plaintext = Array(text.utf8)
        let messageKey = SymmetricKey(size: .bits256)
        let ephemeral = Curve25519.KeyAgreement.PrivateKey()
        let ephemeralRaw = Array(ephemeral.publicKey.rawRepresentation)
        let recipientRaw = Array(try #require(rawKey(b.publicKey))[0..<32])
        let secret = try ephemeral.sharedSecretFromKeyAgreement(
            with: Curve25519.KeyAgreement.PublicKey(rawRepresentation: recipientRaw))
        let wrapKey = secret.hkdfDerivedSymmetricKey(
            using: SHA256.self, salt: [UInt8](),
            sharedInfo: Array("CipherKeyboard v1".utf8) + ephemeralRaw + recipientRaw,
            outputByteCount: 32)
        let wrapped = try ChaChaPoly.seal(
            messageKey.withUnsafeBytes { Array($0) }, using: wrapKey,
            nonce: ChaChaPoly.Nonce(data: [UInt8](repeating: 0, count: 12)))
        let entries = [Array(wrapped.ciphertext) + Array(wrapped.tag)]
        var forged = Envelope(
            senderKey: senderKey, ephemeralKey: ephemeralRaw, entries: entries, nonce: Array(ChaChaPoly.Nonce()),
            ciphertext: [], signature: [])
        let aad = Envelope.header(entries: 1, textCount: plaintext.count) + senderKey + ephemeralRaw + entries[0]
        let box = try ChaChaPoly.seal(
            plaintext, using: messageKey, nonce: ChaChaPoly.Nonce(data: forged.nonce), authenticating: aad)
        forged.ciphertext = Array(box.ciphertext) + Array(box.tag)
        forged.signature = try sign(forged.signedBytes)
        return forged.string
    }

    @Test("Контроль: сообщение, собранное вручную с честным ключом и подписью M, открывается как contact(M)")
    func handmadeHonestMessageOpens() throws {
        let contactM = Contact(name: "M", publicKey: mallory.publicKey)
        let m = try handmade(senderKey: try #require(rawKey(mallory.publicKey))) {
            Array(try mallory.signingKey().signature(for: $0))
        }
        let opened = try CipherMessage.open(m, as: b, contacts: [contactM])
        #expect(opened.text == text)
        #expect(opened.sender == .contact(contactM))
    }

    @Test("Ключ отправителя с Ed25519 = 01 00…00 и подпись 01 00…00 ‖ 00…00 → malformed, не contact")
    func identitySigningKeyForgery() throws {
        // X25519 от A — настоящий, Ed25519 — нейтральная точка: такой «контакт» можно подделать без приватного ключа.
        let forgedKey = Array(try #require(rawKey(a.publicKey))[0..<32]) + Self.identityPoint
        let contact = Contact(name: "Аня", publicKey: PublicKey(trustedRaw: forgedKey))
        var signedBytes: [UInt8] = []
        let m = try handmade(senderKey: forgedKey) {
            signedBytes = $0
            return Self.identitySignature
        }
        // Без проверки ключа подпись прошла бы: CryptoKit принимает её для нейтральной точки.
        let verifier = try Curve25519.Signing.PublicKey(rawRepresentation: Self.identityPoint)
        #expect(verifier.isValidSignature(Self.identitySignature, for: signedBytes))
        #expect(throws: CipherError.malformed) { _ = try CipherMessage.open(m, as: b, contacts: [contact]) }
    }

    @Test(
        "Ключ отправителя с Ed25519 любой точки малого порядка → malformed",
        arguments: SmallOrderEd25519.encodings)
    func smallOrderSigningKeyForgery(point: String) throws {
        var part = try #require(bytes(hex: point))
        for signBit in [UInt8(0x00), 0x80] {
            part[31] = part[31] & 0x7F | signBit
            let forgedKey = Array(try #require(rawKey(a.publicKey))[0..<32]) + part
            let contact = Contact(name: "Аня", publicKey: PublicKey(trustedRaw: forgedKey))
            let m = try handmade(senderKey: forgedKey) { _ in part + [UInt8](repeating: 0, count: 32) }
            #expect(throws: CipherError.malformed, "\(hex(part))") {
                _ = try CipherMessage.open(m, as: b, contacts: [contact])
            }
        }
    }

    @Test("Честное сообщение M при контакте A → unknown(отпечаток M), а не contact(A)")
    func honestMalloryIsUnknown() throws {
        let contactA = Contact(name: "A", publicKey: a.publicKey)
        let m = try CipherMessage.seal(text, from: mallory, to: [b.publicKey])
        let opened = try CipherMessage.open(m, as: b, contacts: [contactA])
        #expect(opened.sender == .unknown(mallory.publicKey.fingerprint))
        #expect(opened.sender != .contact(contactA))
    }
}
