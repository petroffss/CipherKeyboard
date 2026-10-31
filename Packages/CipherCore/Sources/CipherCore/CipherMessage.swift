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

    /// Доменная строка: HKDF для ключей записей и префикс подписываемых байт.
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

            var envelope = Envelope(
                senderKey: sender.publicKey.raw, ephemeralKey: ephemeralRaw, entries: entries,
                nonce: Array(ChaChaPoly.Nonce()), ciphertext: [], signature: [])
            let aad = Envelope.textAAD(
                header: Envelope.header(entries: entries.count, textCount: plaintext.count),
                senderKey: envelope.senderKey, ephemeralKey: envelope.ephemeralKey, entries: entries)
            let box = try ChaChaPoly.seal(
                plaintext, using: messageKey, nonce: ChaChaPoly.Nonce(data: envelope.nonce), authenticating: aad)
            envelope.ciphertext = Array(box.ciphertext) + Array(box.tag)
            envelope.signature = Array(try sender.signingKey().signature(for: envelope.signedBytes))
            return envelope.string
        } catch {
            // Ключи проверены при разборе, поэтому сюда попадает только непригодный ключ.
            throw CipherError.invalidKey
        }
    }

    /// Находит в `text` первое сообщение, проверяет формат, подпись, ищет свою запись и расшифровывает.
    public static func open(_ text: String, as identity: Identity, contacts: [Contact]) throws -> OpenedMessage {
        // 1. Формат.
        let envelope = try Envelope.find(in: text)
        let senderKey: PublicKey
        do {
            senderKey = try PublicKey(validatingRaw: envelope.senderKey)
        } catch {
            throw CipherError.malformed
        }

        // 2. Подпись ключом отправителя из сообщения — до любых попыток расшифровки.
        guard let verifier = try? Curve25519.Signing.PublicKey(rawRepresentation: senderKey.signingRaw),
            verifier.isValidSignature(envelope.signature, for: envelope.signedBytes)
        else { throw CipherError.tampered }

        // 3. Своя запись: перебор всех записей ключом, выведенным из своего X25519.
        guard let messageKey = unwrapMessageKey(envelope, as: identity) else {
            throw CipherError.notARecipient
        }

        // 4. Текст. Ключ отправителя входит в AAD: подмена отправителя с переподписью ломает расшифровку.
        let plaintext: [UInt8]
        do {
            let box = try ChaChaPoly.SealedBox(
                nonce: ChaChaPoly.Nonce(data: envelope.nonce),
                ciphertext: envelope.ciphertext.prefix(envelope.textCount),
                tag: envelope.ciphertext.suffix(Envelope.tagCount))
            plaintext = Array(try ChaChaPoly.open(box, using: messageKey, authenticating: envelope.textAAD))
        } catch {
            throw CipherError.tampered
        }
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

    /// Ключ сообщения из своей записи или `nil`, если ни одна запись не раскрылась.
    private static func unwrapMessageKey(_ envelope: Envelope, as identity: Identity) -> SymmetricKey? {
        let ownRaw = identity.publicKey.agreementRaw
        guard let own = try? identity.agreementKey(),
            let ephemeral = try? Curve25519.KeyAgreement.PublicKey(rawRepresentation: envelope.ephemeralKey),
            let secret = try? own.sharedSecretFromKeyAgreement(with: ephemeral),
            let nonce = try? ChaChaPoly.Nonce(data: wrapNonce)
        else { return nil }
        let wrapKey = wrappingKey(secret: secret, ephemeralRaw: envelope.ephemeralKey, recipientRaw: ownRaw)
        for entry in envelope.entries {
            guard
                let box = try? ChaChaPoly.SealedBox(
                    nonce: nonce, ciphertext: entry.prefix(32), tag: entry.suffix(Envelope.tagCount)),
                let key = try? ChaChaPoly.open(box, using: wrapKey), key.count == 32
            else { continue }
            return SymmetricKey(data: key)
        }
        return nil
    }

    /// HKDF-SHA256(общий секрет, salt пустой, info = домен ‖ эфемерный X25519 ‖ X25519 получателя) → 32 байта.
    private static func wrappingKey(secret: SharedSecret, ephemeralRaw: [UInt8], recipientRaw: [UInt8])
        -> SymmetricKey
    {
        secret.hkdfDerivedSymmetricKey(
            using: SHA256.self, salt: [UInt8](), sharedInfo: domain + ephemeralRaw + recipientRaw,
            outputByteCount: 32)
    }
}
