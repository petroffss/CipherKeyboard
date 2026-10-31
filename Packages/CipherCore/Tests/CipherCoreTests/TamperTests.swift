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
        // Производные ключа сообщения и дополнение — по FORMAT.md, без функций ядра.
        func derived(_ label: String) -> SymmetricKey {
            HKDF<SHA256>.deriveKey(
                inputKeyMaterial: messageKey, salt: [UInt8](),
                info: Array("CipherKeyboard v1".utf8) + Array(label.utf8), outputByteCount: 32)
        }
        let commitment = derived("commit").withUnsafeBytes { Array($0) }
        let paddedCount = (plaintext.count + 31) / 32 * 32
        let padded =
            [UInt8(plaintext.count >> 8), UInt8(plaintext.count & 0xFF)] + plaintext
            + [UInt8](repeating: 0, count: paddedCount - plaintext.count)
        var forged = Envelope(
            senderKey: senderKey, ephemeralKey: ephemeralRaw, entries: entries, commitment: commitment,
            nonce: Array(ChaChaPoly.Nonce()), ciphertext: [], signature: [])
        let aad =
            [1, 1, UInt8(paddedCount >> 8), UInt8(paddedCount & 0xFF)] + senderKey + ephemeralRaw + entries[0]
            + commitment
        let box = try ChaChaPoly.seal(
            padded, using: derived("text"), nonce: ChaChaPoly.Nonce(data: forged.nonce), authenticating: aad)
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

    @Test("Ключ отправителя A с неканонической частью X25519 (старший бит), подпись пересчитана A → malformed")
    func nonCanonicalSenderAgreementKey() throws {
        var forged = try envelope(of: CipherMessage.seal(text, from: a, to: [b.publicKey]))
        #expect(forged.senderKey[31] & 0x80 == 0)
        forged.senderKey[31] |= 0x80
        forged.signature = Array(try a.signingKey().signature(for: forged.signedBytes))
        let contacts = [Contact(name: "A", publicKey: a.publicKey)]
        #expect(throws: CipherError.malformed) { _ = try CipherMessage.open(forged.string, as: b, contacts: contacts) }
    }

    @Test("Неканонический эфемерный ключ (старший бит), подпись пересчитана A → malformed")
    func nonCanonicalEphemeralKey() throws {
        var forged = try envelope(of: CipherMessage.seal(text, from: a, to: [b.publicKey]))
        #expect(forged.ephemeralKey[31] & 0x80 == 0)
        forged.ephemeralKey[31] |= 0x80
        forged.signature = Array(try a.signingKey().signature(for: forged.signedBytes))
        #expect(throws: CipherError.malformed) { _ = try CipherMessage.open(forged.string, as: b, contacts: []) }
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

/// Атака на ключ без обязательства (по пробе security-review): A подбирает K2 и 16 байт «мусорной» записи так,
/// что один и тот же шифротекст с одним тегом Poly1305 проходит и под ключом текста от K1, и от K2,
/// и оба раскрытия — честно дополненные тексты в UTF-8. Подбор сделан один раз вне тестов (перебор K2 до
/// совпадения двух байт длины, затем линейное решение для блока AAD по модулю 2^130 − 5); здесь — его результат.
enum TagCollisionVector {
    static let privateKeyA =
        "10cd141dabfaaa45d9421c228ec0dd9b436126fe68f6df4ef59b56eda5f16259"
        + "e7e24e3b7a3f02334722779cdd5b6859c1f777c821e70ac52cfa944da49df80f"
    static let privateKeyB =
        "c0365f3798288b0e19fe19f55c239dbf224a59c6d8556de7c08977079d477367"
        + "a4fa6798d5e6d44043f871fc055c8e125f2cd1cf720022524ffa4816dbd64f82"
    static let privateKeyC =
        "38b5d0ddff467f4fe4fc4169828bac79aebf34041cc50c32cd7c71dfeef18d4c"
        + "924eb95b71b522b8a7407128f27b07fa23c5c4d2044f0b570eebeb151f2e36bc"
    static let ephemeralPrivateKey = "70bfeac59cec7d927ecbc5dc7b0845c4ae5c099e7b6f2220ac57e9dc69c27945"
    /// Ключ сообщения в записи B и в обязательстве.
    static let k1 = "6c0010d05e2be27b4b284e1e407918caaac5e4740b4b0ea568507a670d2bccaa"
    /// Ключ сообщения в записи C.
    static let k2 = "18f3530a55e85562486f92bba149f4b02558e100cbecc018f4856880a9d3b957"
    static let nonce = "b6856736428e1cc149d31a3e"
    /// Третья запись: 48 байт, из них байты 12..<28 — подобранный блок AAD.
    static let junkEntry =
        "5b135f458a92e7e79a59da89b255b3982471a7d11dc817bca493184c726ed0d5"
        + "2d3390850cf3f49d40097297b16bda01"
    /// Шифротекст (2 + 32 байта) и общий тег (16).
    static let ciphertextAndTag =
        "4b9a0dd3180aa98a0585ae329a78db7b179439a693dc434b15daeeb2016043cd"
        + "d2a6e251f2e1f39dbca1a819370ce0fb0d2f"
    /// Что видит B: 32 байта текста под K1.
    static let textUnderK1 = "412041416120614141446120422020206141204141f0a08080412024d080c280"
    /// Что увидел бы C без обязательства: другие 32 байта под K2.
    static let textUnderK2 = "71757052cfb9cbb54159d09d63434264deac584bcbbf237428787658ef81a04d"
}

@Suite("Одно сообщение не расшифровывается в разные тексты у разных получателей")
struct KeyCommitmentTests {
    private let text = Array("Встреча отменяется".utf8)
    private let a = Identity.generate()
    private let b = Identity.generate()
    private let c = Identity.generate()

    private func identity(_ hex: String) throws -> Identity {
        try Identity(privateKeyData: Data(try #require(bytes(hex: hex))))
    }

    @Test("Записи B и C с разными K1 и K2, обязательство от K1, подпись A верна → у C tampered")
    func differentKeysForTwoRecipients() throws {
        let k1 = Forge.randomKey()
        let k2 = Forge.randomKey()
        #expect(k1 != k2)
        let ephemeral = Curve25519.KeyAgreement.PrivateKey()
        let entries = [
            try Forge.entry(k1, ephemeral: ephemeral, to: b.publicKey),
            try Forge.entry(k2, ephemeral: ephemeral, to: c.publicKey),
        ]
        let forged = try Forge.message(
            from: a, ephemeral: ephemeral, entries: entries, commitment: Forge.commitment(k1), textMessageKey: k1,
            plain: Forge.padded(text))
        // Контроль: подделка собрана верно — B (его ключ совпадает с обязательством) читает текст.
        #expect(Array(try CipherMessage.open(forged.string, as: b, contacts: []).text.utf8) == text)
        #expect(throws: CipherError.tampered) { _ = try CipherMessage.open(forged.string, as: c, contacts: []) }
    }

    @Test("Общий тег Poly1305 под K1 и K2 (подбор блока «мусорной» записи) → текст получает не больше одного")
    func polyTagCollision() throws {
        let v = TagCollisionVector.self
        let a = try identity(v.privateKeyA)
        let b = try identity(v.privateKeyB)
        let c = try identity(v.privateKeyC)
        let ephemeral = try Curve25519.KeyAgreement.PrivateKey(
            rawRepresentation: try #require(bytes(hex: v.ephemeralPrivateKey)))
        let k1 = try #require(bytes(hex: v.k1))
        let k2 = try #require(bytes(hex: v.k2))
        let sealedText = try #require(bytes(hex: v.ciphertextAndTag))
        let textB = try #require(bytes(hex: v.textUnderK1))
        let textC = try #require(bytes(hex: v.textUnderK2))
        #expect(k1 != k2)

        var forged = Envelope(
            senderKey: try #require(rawKey(a.publicKey)), ephemeralKey: Array(ephemeral.publicKey.rawRepresentation),
            entries: [
                try Forge.entry(k1, ephemeral: ephemeral, to: b.publicKey),
                try Forge.entry(k2, ephemeral: ephemeral, to: c.publicKey),
                try #require(bytes(hex: v.junkEntry)),
            ],
            commitment: Forge.commitment(k1), nonce: try #require(bytes(hex: v.nonce)), ciphertext: sealedText,
            signature: [])
        forged.signature = Array(try a.signingKey().signature(for: forged.signedBytes))

        // Подделка настоящая: тот же шифротекст и тег проходят ChaCha20-Poly1305 (CryptoKit) под обоими ключами,
        // и оба раскрытия — правильно дополненные разные тексты в UTF-8. Без обязательства B и C увидели бы разное.
        let box = try ChaChaPoly.SealedBox(
            nonce: ChaChaPoly.Nonce(data: forged.nonce), ciphertext: sealedText.dropLast(16),
            tag: sealedText.suffix(16))
        let underK1 = try? ChaChaPoly.open(box, using: Forge.textKey(k1), authenticating: forged.textAAD)
        let underK2 = try? ChaChaPoly.open(box, using: Forge.textKey(k2), authenticating: forged.textAAD)
        #expect(underK1 != nil && underK2 != nil, "тег сходится под K1 и под K2")
        #expect(underK1.map(Array.init) == Forge.padded(textB))
        #expect(underK2.map(Array.init) == Forge.padded(textC))
        #expect(textB != textC)
        #expect(String(validating: textB, as: UTF8.self) != nil)
        #expect(String(validating: textC, as: UTF8.self) != nil)

        let contacts = [Contact(name: "A", publicKey: a.publicKey)]
        var readers: [String] = []
        for (name, who) in [("B", b), ("C", c)] {
            do {
                let opened = try CipherMessage.open(forged.string, as: who, contacts: contacts)
                readers.append(name)
                #expect(name == "B" && Array(opened.text.utf8) == textB, "\(name) прочитал текст")
            } catch let error as CipherError {
                #expect(error == .tampered, "\(name): \(error)")
            }
        }
        #expect(readers.count <= 1, "текст получили: \(readers)")
        #expect(throws: CipherError.tampered) { _ = try CipherMessage.open(forged.string, as: c, contacts: contacts) }
    }

    @Test("Для B раскрываются две записи → tampered", arguments: [false, true])
    func twoEntriesOpenForOneRecipient(differentKeys: Bool) throws {
        let k1 = Forge.randomKey()
        let second = differentKeys ? Forge.randomKey() : k1
        let ephemeral = Curve25519.KeyAgreement.PrivateKey()
        let entries = [
            try Forge.entry(k1, ephemeral: ephemeral, to: b.publicKey),
            try Forge.entry(second, ephemeral: ephemeral, to: b.publicKey),
            try Forge.entry(k1, ephemeral: ephemeral, to: a.publicKey),
        ]
        let forged = try Forge.message(
            from: a, ephemeral: ephemeral, entries: entries, commitment: Forge.commitment(k1), textMessageKey: k1,
            plain: Forge.padded(text))
        #expect(throws: CipherError.tampered) { _ = try CipherMessage.open(forged.string, as: b, contacts: []) }
        // Контроль: у A своя запись одна — сообщение собрано верно.
        #expect(Array(try CipherMessage.open(forged.string, as: a, contacts: []).text.utf8) == text)
    }

    @Test("Обязательство с изменённым байтом и пересчитанной подписью A → tampered у всех", arguments: [0, 13, 31])
    func changedCommitment(index: Int) throws {
        let m = try CipherMessage.seal(String(decoding: text, as: UTF8.self), from: a, to: [b.publicKey, c.publicKey])
        var forged = try Envelope(bytes: try #require(decodedMessage(m)))
        forged.commitment[index] ^= 0x01
        forged.signature = Array(try a.signingKey().signature(for: forged.signedBytes))
        for (name, who) in [("B", b), ("C", c), ("A", a)] {
            #expect(throws: CipherError.tampered, "\(name)") {
                _ = try CipherMessage.open(forged.string, as: who, contacts: [])
            }
        }
    }

    @Test("Обязательство от другого ключа при честных записях, тексте и подписи A → tampered")
    func commitmentToOtherKey() throws {
        let key = Forge.randomKey()
        let ephemeral = Curve25519.KeyAgreement.PrivateKey()
        let entries = [try Forge.entry(key, ephemeral: ephemeral, to: b.publicKey)]
        let honest = try Forge.message(
            from: a, ephemeral: ephemeral, entries: entries, commitment: Forge.commitment(key), textMessageKey: key,
            plain: Forge.padded(text))
        #expect(Array(try CipherMessage.open(honest.string, as: b, contacts: []).text.utf8) == text)
        // Текст зашифрован с AAD, где уже лежит чужое обязательство, — тег текста верен, ошибку даёт только сверка.
        let forged = try Forge.message(
            from: a, ephemeral: ephemeral, entries: entries, commitment: Forge.commitment(Forge.randomKey()),
            textMessageKey: key, plain: Forge.padded(text))
        #expect(throws: CipherError.tampered) { _ = try CipherMessage.open(forged.string, as: b, contacts: []) }
    }

    @Test("Честное seal для B и C открывается у обоих одним текстом байт в байт")
    func honestMessageSameForAll() throws {
        let original = "Один текст для всех 👍"
        let m = try CipherMessage.seal(original, from: a, to: [b.publicKey, c.publicKey])
        let byB = try CipherMessage.open(m, as: b, contacts: [])
        let byC = try CipherMessage.open(m, as: c, contacts: [])
        #expect(Array(byB.text.utf8) == Array(original.utf8))
        #expect(Array(byC.text.utf8) == Array(original.utf8))
        #expect(Array(byB.text.utf8) == Array(byC.text.utf8))
    }
}
