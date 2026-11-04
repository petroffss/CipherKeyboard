import CryptoKit
import Foundation

/// Результат расшифровки: текст, ключ отправителя и вердикт, кто он.
public struct OpenedMessage: Sendable {
    public let text: String
    public let senderKey: PublicKey
    public let sender: Sender
    /// Дата по часам отправителя, защищённая шифрованием и подписью. У ckmsg1 даты нет.
    public let createdAt: Date?
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

/// Создаёт сообщения `ckmsg2`, открывает `ckmsg1` и `ckmsg2` (раскладка — FORMAT.md).
public enum CipherMessage: Sendable {
    public static let maxPlaintextBytes = 4096
    /// ckmsg2 для одного контакта и себя: 7 + ceil(4 * (330 + paddedBytes) / 3) символов.
    /// При 2720 байтах это 4074 символа; следующий блок (2752) даёт 4117, больше 4096.
    /// Ориентир для обычного сообщения Telegram, не лимит формата и не для подписей к медиа.
    public static let singleMessageBytes = 2720
    /// Вместе с отправителем.
    public static let maxRecipients = 16

    public static let outputPrefix = Envelope.Version.timestamped.prefix
    /// Последняя секунда 9999-12-31 UTC. Даты вне диапазона календаря формата не принимаются.
    private static let maxTimestamp: UInt64 = 253_402_300_799
    private static let wrapNonce = [UInt8](repeating: 0, count: Envelope.nonceCount)

    /// Шифрует `text` для `to` и для самого отправителя (его ядро добавляет само), подписывает ключом отправителя.
    public static func seal(_ text: String, from sender: Identity, to recipients: [PublicKey]) throws -> String {
        try seal(text, from: sender, to: recipients, createdAt: Date())
    }

    static func seal(_ text: String, from sender: Identity, to recipients: [PublicKey], createdAt: Date) throws
        -> String
    {
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
        guard let timestamp = UInt64(exactly: floor(createdAt.timeIntervalSince1970)),
            timestamp <= maxTimestamp
        else { throw CipherError.malformed }

        let version = Envelope.Version.timestamped
        do {
            let messageKey = SymmetricKey(size: .bits256)
            let ephemeral = Curve25519.KeyAgreement.PrivateKey()
            let ephemeralRaw = Array(ephemeral.publicKey.rawRepresentation)
            var entries: [[UInt8]] = []
            for key in unique {
                let point = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: key.agreementRaw)
                let wrapKey = try wrappingKey(
                    secret: ephemeral.sharedSecretFromKeyAgreement(with: point),
                    ephemeralRaw: ephemeralRaw, recipientRaw: key.agreementRaw, version: version)
                let box = try ChaChaPoly.seal(
                    messageKey.withUnsafeBytes { Array($0) }, using: wrapKey,
                    nonce: ChaChaPoly.Nonce(data: wrapNonce))
                entries.append(Array(box.ciphertext) + Array(box.tag))
            }

            let payload = withUnsafeBytes(of: timestamp.bigEndian) { Array($0) } + pad(plaintext)
            var envelope = Envelope(
                version: version, senderKey: sender.publicKey.raw, ephemeralKey: ephemeralRaw, entries: entries,
                commitment: commitment(to: messageKey, version: version), nonce: Array(ChaChaPoly.Nonce()),
                ciphertext: [UInt8](repeating: 0, count: payload.count + Envelope.tagCount), signature: [])
            let box = try ChaChaPoly.seal(
                payload, using: textKey(from: messageKey, version: version),
                nonce: ChaChaPoly.Nonce(data: envelope.nonce),
                authenticating: envelope.textAAD)
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
        guard constantTimeEquals(commitment(to: messageKey, version: envelope.version), envelope.commitment) else {
            throw CipherError.tampered
        }

        // 5. Текст. Ключ отправителя входит в AAD: подмена отправителя с переподписью ломает расшифровку.
        let payload: [UInt8]
        do {
            let box = try ChaChaPoly.SealedBox(
                nonce: ChaChaPoly.Nonce(data: envelope.nonce),
                ciphertext: envelope.ciphertext.dropLast(Envelope.tagCount),
                tag: envelope.ciphertext.suffix(Envelope.tagCount))
            payload = Array(
                try ChaChaPoly.open(
                    box, using: textKey(from: messageKey, version: envelope.version), authenticating: envelope.textAAD))
        } catch {
            throw CipherError.tampered
        }
        let timestampCount = envelope.version.timestampCount
        let createdAt: Date?
        if envelope.version == .timestamped {
            let timestamp = payload.prefix(timestampCount).reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }
            guard timestamp <= maxTimestamp else { throw CipherError.malformed }
            createdAt = Date(timeIntervalSince1970: TimeInterval(timestamp))
        } else {
            createdAt = nil
        }
        let plaintext = try unpad(Array(payload.dropFirst(timestampCount)))
        guard let message = String(validating: plaintext, as: UTF8.self) else { throw CipherError.malformed }

        let sender: Sender
        if senderKey == identity.publicKey {
            sender = .me
        } else if let contact = contacts.first(where: { $0.publicKey == senderKey }) {
            sender = .contact(contact)
        } else {
            sender = .unknown(senderKey.fingerprint)
        }
        return OpenedMessage(text: message, senderKey: senderKey, sender: sender, createdAt: createdAt)
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
        let own = identity.agreementKey()
        guard let ephemeral = try? Curve25519.KeyAgreement.PublicKey(rawRepresentation: envelope.ephemeralKey),
            let secret = try? own.sharedSecretFromKeyAgreement(with: ephemeral),
            let nonce = try? ChaChaPoly.Nonce(data: wrapNonce)
        else { return [] }
        let wrapKey = wrappingKey(
            secret: secret, ephemeralRaw: envelope.ephemeralKey, recipientRaw: ownRaw, version: envelope.version)
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
    private static func wrappingKey(
        secret: SharedSecret, ephemeralRaw: [UInt8], recipientRaw: [UInt8], version: Envelope.Version
    ) -> SymmetricKey {
        secret.hkdfDerivedSymmetricKey(
            using: SHA256.self, salt: [UInt8](), sharedInfo: version.domain + ephemeralRaw + recipientRaw,
            outputByteCount: 32)
    }

    /// Производная ключа сообщения `K`: HKDF-SHA256(ikm = K, salt пустой, info = домен ‖ метка) → 32 байта.
    private static func derive(from messageKey: SymmetricKey, label: String, version: Envelope.Version) -> SymmetricKey
    {
        HKDF<SHA256>.deriveKey(
            inputKeyMaterial: messageKey, salt: [UInt8](), info: version.domain + Array(label.utf8), outputByteCount: 32
        )
    }

    /// Ключ ChaCha20-Poly1305 для текста: производная `K` с меткой `text`.
    private static func textKey(from messageKey: SymmetricKey, version: Envelope.Version) -> SymmetricKey {
        derive(from: messageKey, label: "text", version: version)
    }

    /// Обязательство на ключ сообщения: производная `K` с меткой `commit`. Лежит в сообщении под подписью;
    /// два разных `K` с одним обязательством — коллизия SHA-256.
    private static func commitment(to messageKey: SymmetricKey, version: Envelope.Version) -> [UInt8] {
        derive(from: messageKey, label: "commit", version: version).withUnsafeBytes { Array($0) }
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
