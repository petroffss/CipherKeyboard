import CryptoKit
import Foundation

/// Результат расшифровки: текст, ключ отправителя и вердикт, кто он.
public struct OpenedMessage: Sendable {
    public let text: String
    public let senderKey: PublicKey
    public let sender: Sender
}

/// Кто отправил сообщение. Подпись к этому моменту уже проверена.
public enum Sender: Sendable, Equatable {
    /// Отправитель — личность, которой открыли сообщение.
    case me
    /// Ключ отправителя совпал с ключом контакта (обе части).
    case contact(Contact)
    /// Подпись верна, но отправителя нет в контактах.
    case unknown(Fingerprint)
}

/// Шифрование и расшифровка сообщений `ckmsg1:…` (раскладка — FORMAT.md).
public enum CipherMessage: Sendable {
    public static let maxPlaintextBytes = 4096
    /// Вместе с отправителем.
    public static let maxRecipients = 16

    /// Доменная строка: HKDF для ключей записей и производных ключа сообщения, префикс подписываемых байт.
    static let domain = Array("CipherKeyboard v1".utf8)
    static let signatureDomain = domain
    private static let wrapNonce = [UInt8](repeating: 0, count: Envelope.nonceCount)

    /// Шифрует `text` для `to` и для самого отправителя (его ядро добавляет само), подписывает ключом отправителя.
    public static func seal(_ text: String, from sender: Identity, to recipients: [PublicKey]) throws -> String {
        let plaintext = Array(text.utf8)
        guard !plaintext.isEmpty else { throw CipherError.emptyMessage }
        guard plaintext.count <= maxPlaintextBytes else {
            throw CipherError.messageTooLong(byteCount: plaintext.count)
        }
        guard !recipients.isEmpty else { throw CipherError.noRecipients }

        // Получатель определяется ключом согласования: повторы и сам отправитель — одна запись.
        var unique: [PublicKey] = []
        var seen = Set<[UInt8]>()
        for key in recipients + [sender.publicKey] where seen.insert(key.agreementRaw).inserted {
            unique.append(key)
        }
        guard unique.count <= maxRecipients else { throw CipherError.tooManyRecipients }

        do {
            let messageKey = SymmetricKey(size: .bits256)
            let ephemeral = Curve25519.KeyAgreement.PrivateKey()
            let ephemeralRaw = Array(ephemeral.publicKey.rawRepresentation)
            var entries: [[UInt8]] = []
            for key in unique {
                let point = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: key.agreementRaw)
                let wrapKey = try wrappingKey(
                    secret: ephemeral.sharedSecretFromKeyAgreement(with: point),
                    ephemeralRaw: ephemeralRaw, recipientRaw: key.agreementRaw)
                let box = try ChaChaPoly.seal(
                    messageKey.withUnsafeBytes { Array($0) }, using: wrapKey,
                    nonce: ChaChaPoly.Nonce(data: wrapNonce))
                entries.append(Array(box.ciphertext) + Array(box.tag))
            }

            // Настоящая длина и текст, дополненный нулями до кратного 32: в открытом заголовке — только дополненная.
            let padded = pad(plaintext)
            var envelope = Envelope(
                senderKey: sender.publicKey.raw, ephemeralKey: ephemeralRaw, entries: entries,
                commitment: commitment(to: messageKey), nonce: Array(ChaChaPoly.Nonce()), ciphertext: [],
                signature: [])
            let aad = Envelope.textAAD(
                header: Envelope.header(entries: entries.count, paddedCount: padded.count - Envelope.lengthCount),
                senderKey: envelope.senderKey, ephemeralKey: envelope.ephemeralKey, entries: entries,
                commitment: envelope.commitment)
            let box = try ChaChaPoly.seal(
                padded, using: textKey(from: messageKey), nonce: ChaChaPoly.Nonce(data: envelope.nonce),
                authenticating: aad)
            envelope.ciphertext = Array(box.ciphertext) + Array(box.tag)
            envelope.signature = Array(try sender.signingKey().signature(for: envelope.signedBytes))
            return envelope.string
        } catch {
            // Ключи проверены при разборе, поэтому сюда попадает только непригодный ключ.
            throw CipherError.invalidKey
        }
    }

    /// Находит в `text` первое сообщение, проверяет формат, подпись, ищет свою запись, сверяет обязательство
    /// на ключ сообщения и расшифровывает.
    public static func open(_ text: String, as identity: Identity, contacts: [Contact]) throws -> OpenedMessage {
        // 1. Формат.
        let envelope = try Envelope.find(in: text)
        let senderKey: PublicKey
        do {
            senderKey = try PublicKey(validatingRaw: envelope.senderKey)
        } catch {
            throw CipherError.malformed
        }
        // Эфемерный ключ малого порядка дал бы всем записям известный общий секрет; неканонический —
        // вторую запись того же ключа.
        guard PublicKey.isUsableAgreementKey(envelope.ephemeralKey) else { throw CipherError.malformed }

        // 2. Подпись ключом отправителя из сообщения — до любых попыток расшифровки.
        guard let verifier = try? Curve25519.Signing.PublicKey(rawRepresentation: senderKey.signingRaw),
            verifier.isValidSignature(envelope.signature, for: envelope.signedBytes)
        else { throw CipherError.tampered }

        // 3. Своя запись: перебор всех записей ключом, выведенным из своего X25519. Раскрылось больше
        // одной — сообщение собрано нечестно (разные ключи для одного получателя).
        let opened = unwrapMessageKeys(envelope, as: identity)
        guard let messageKey = opened.first else { throw CipherError.notARecipient }
        guard opened.count == 1 else { throw CipherError.tampered }

        // 4. Обязательство на ключ сообщения: ChaCha20-Poly1305 не привязывает шифротекст к ключу, поэтому без
        // этой сверки отправитель мог бы дать разным получателям разные ключи и разные тексты под одной подписью.
        guard constantTimeEquals(commitment(to: messageKey), envelope.commitment) else {
            throw CipherError.tampered
        }

        // 5. Текст. Ключ отправителя входит в AAD: подмена отправителя с переподписью ломает расшифровку.
        let padded: [UInt8]
        do {
            let box = try ChaChaPoly.SealedBox(
                nonce: ChaChaPoly.Nonce(data: envelope.nonce),
                ciphertext: envelope.ciphertext.dropLast(Envelope.tagCount),
                tag: envelope.ciphertext.suffix(Envelope.tagCount))
            padded = Array(
                try ChaChaPoly.open(box, using: textKey(from: messageKey), authenticating: envelope.textAAD))
        } catch {
            throw CipherError.tampered
        }
        let plaintext = try unpad(padded)
        guard let message = String(validating: plaintext, as: UTF8.self) else { throw CipherError.malformed }

        let sender: Sender
        if senderKey == identity.publicKey {
            sender = .me
        } else if let contact = contacts.first(where: { $0.publicKey == senderKey }) {
            sender = .contact(contact)
        } else {
            sender = .unknown(senderKey.fingerprint)
        }
        return OpenedMessage(text: message, senderKey: senderKey, sender: sender)
    }

    /// Открытая часть для шифрования: настоящая длина (UInt16 BE) ‖ текст ‖ нули до кратного 32.
    static func pad(_ text: [UInt8]) -> [UInt8] {
        let padding = Envelope.paddedCount(for: text.count) - text.count
        return [UInt8(truncatingIfNeeded: text.count >> 8), UInt8(truncatingIfNeeded: text.count)] + text
            + [UInt8](repeating: 0, count: padding)
    }

    /// Текст из расшифрованной части. Дополнение не из нулей, настоящая длина 0, больше дополненной или
    /// дополнение длиннее необходимого → `tampered`: честный `seal` такого не создаёт.
    static func unpad(_ padded: [UInt8]) throws(CipherError) -> [UInt8] {
        guard padded.count >= Envelope.lengthCount else { throw .tampered }
        let body = padded.dropFirst(Envelope.lengthCount)
        let textCount = Int(padded[0]) << 8 | Int(padded[1])
        guard textCount >= 1, textCount <= body.count, Envelope.paddedCount(for: textCount) == body.count,
            body.dropFirst(textCount).allSatisfy({ $0 == 0 })
        else { throw .tampered }
        return Array(body.prefix(textCount))
    }

    /// Все ключи сообщения, которые раскрылись своим ключом записи. Перебираются все записи, без досрочного выхода.
    private static func unwrapMessageKeys(_ envelope: Envelope, as identity: Identity) -> [SymmetricKey] {
        let ownRaw = identity.publicKey.agreementRaw
        guard let own = try? identity.agreementKey(),
            let ephemeral = try? Curve25519.KeyAgreement.PublicKey(rawRepresentation: envelope.ephemeralKey),
            let secret = try? own.sharedSecretFromKeyAgreement(with: ephemeral),
            let nonce = try? ChaChaPoly.Nonce(data: wrapNonce)
        else { return [] }
        let wrapKey = wrappingKey(secret: secret, ephemeralRaw: envelope.ephemeralKey, recipientRaw: ownRaw)
        var keys: [SymmetricKey] = []
        for entry in envelope.entries {
            guard
                let box = try? ChaChaPoly.SealedBox(
                    nonce: nonce, ciphertext: entry.prefix(32), tag: entry.suffix(Envelope.tagCount)),
                let key = try? ChaChaPoly.open(box, using: wrapKey), key.count == 32
            else { continue }
            keys.append(SymmetricKey(data: key))
        }
        return keys
    }

    /// HKDF-SHA256(общий секрет, salt пустой, info = домен ‖ эфемерный X25519 ‖ X25519 получателя) → 32 байта.
    private static func wrappingKey(secret: SharedSecret, ephemeralRaw: [UInt8], recipientRaw: [UInt8])
        -> SymmetricKey
    {
        secret.hkdfDerivedSymmetricKey(
            using: SHA256.self, salt: [UInt8](), sharedInfo: domain + ephemeralRaw + recipientRaw,
            outputByteCount: 32)
    }

    /// Производная ключа сообщения `K`: HKDF-SHA256(ikm = K, salt пустой, info = домен ‖ метка) → 32 байта.
    private static func derive(from messageKey: SymmetricKey, label: String) -> SymmetricKey {
        HKDF<SHA256>.deriveKey(
            inputKeyMaterial: messageKey, salt: [UInt8](), info: domain + Array(label.utf8), outputByteCount: 32)
    }

    /// Ключ ChaCha20-Poly1305 для текста: производная `K` с меткой `text`.
    static func textKey(from messageKey: SymmetricKey) -> SymmetricKey {
        derive(from: messageKey, label: "text")
    }

    /// Обязательство на ключ сообщения: производная `K` с меткой `commit`. Лежит в сообщении под подписью;
    /// два разных `K` с одним обязательством — коллизия SHA-256.
    static func commitment(to messageKey: SymmetricKey) -> [UInt8] {
        derive(from: messageKey, label: "commit").withUnsafeBytes { Array($0) }
    }

    /// Сравнение без досрочного выхода: время не зависит от того, в каком байте расхождение.
    static func constantTimeEquals(_ lhs: [UInt8], _ rhs: [UInt8]) -> Bool {
        guard lhs.count == rhs.count else { return false }
        var difference: UInt8 = 0
        for index in lhs.indices {
            difference |= lhs[index] ^ rhs[index]
        }
        return difference == 0
    }
}
