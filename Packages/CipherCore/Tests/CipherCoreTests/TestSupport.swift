import CryptoKit
import Foundation
import Testing

@testable import CipherCore

// Вспомогательные функции тестов. base64 здесь — через Foundation, независимо от кодировщика ядра.

/// Байты из hex-строки; `nil` при нечётной длине или не-hex символе.
func bytes(hex: String) -> [UInt8]? {
    let chars = Array(hex.utf8)
    guard chars.count % 2 == 0 else { return nil }
    var result: [UInt8] = []
    var index = 0
    while index < chars.count {
        guard let byte = UInt8(String(decoding: chars[index..<index + 2], as: UTF8.self), radix: 16) else {
            return nil
        }
        result.append(byte)
        index += 2
    }
    return result
}

func hex(_ bytes: [UInt8], uppercase: Bool = false) -> String {
    bytes.map { String(format: uppercase ? "%02X" : "%02x", $0) }.joined()
}

/// Стандартный base64 (с `+`, `/`) без паддинга — через Foundation.
func base64(_ bytes: [UInt8]) -> String {
    Data(bytes).base64EncodedString().replacingOccurrences(of: "=", with: "")
}

/// base64url без паддинга — через Foundation.
func base64url(_ bytes: [UInt8]) -> String {
    base64(bytes).replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
}

/// Разбор base64url (с паддингом или без) — через Foundation.
func decodeBase64url(_ text: Substring) -> [UInt8]? {
    var standard = text.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
    standard += String(repeating: "=", count: (4 - standard.count % 4) % 4)
    return Data(base64Encoded: standard).map { Array($0) }
}

/// Тело сообщения `ckmsg1` или `ckmsg2` в байтах.
func decodedMessage(_ message: String) -> [UInt8]? {
    guard message.hasPrefix("ckmsg1:") || message.hasPrefix("ckmsg2:") else { return nil }
    return decodeBase64url(message.dropFirst(7))
}

/// 64 байта открытого ключа из его строки `ckpub1:…`.
func rawKey(_ key: PublicKey) -> [UInt8]? {
    decodeBase64url(key.string.dropFirst(7))
}

/// Есть ли `needle` в `haystack` как непрерывный кусок.
func contains(_ haystack: [UInt8], _ needle: [UInt8]) -> Bool {
    guard !needle.isEmpty, needle.count <= haystack.count else { return needle.isEmpty }
    for start in 0...(haystack.count - needle.count) where haystack[start] == needle[0] {
        if Array(haystack[start..<start + needle.count]) == needle { return true }
    }
    return false
}

/// Алфавит base64url в порядке `A–Z a–z 0–9 - _`.
let base64urlAlphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_")

/// Следующий символ base64url по кругу.
func nextBase64urlCharacter(after character: Character) -> Character? {
    guard let index = base64urlAlphabet.firstIndex(of: character) else { return nil }
    return base64urlAlphabet[(index + 1) % base64urlAlphabet.count]
}

/// Строка, в которой символ на позиции `offset` заменён.
func replacingCharacter(in text: String, at offset: Int, with character: Character) -> String {
    var chars = Array(text)
    chars[offset] = character
    return String(chars)
}

/// Кодировки точек малого порядка Ed25519 (8-кручение), little-endian `y`, знаковый бит 0.
/// Посчитаны независимо (python3: все 8 точек кручения через l·P для случайной P) и сверены
/// со списком `ge25519_has_small_order` в libsodium; последние две — неканонические `y = p` и `y = p + 1`.
enum SmallOrderEd25519 {
    static let encodings = [
        "0000000000000000000000000000000000000000000000000000000000000000",
        "0100000000000000000000000000000000000000000000000000000000000000",
        "26e8958fc2b227b045c3f489f2ef98f0d5dfac05d3c63339b13802886d53fc05",
        "c7176a703d4dd84fba3c0b760d10670f2a2053fa2c39ccc64ec7fd7792ac037a",
        "ecffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff7f",
        "edffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff7f",
        "eeffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff7f",
    ]
}

/// Сборка сообщений `ckmsg1` из полей формата — для подделок злонамеренного отправителя, который подписывает
/// их своим настоящим ключом. Производные ключа сообщения и дополнение посчитаны здесь по FORMAT.md,
/// независимо от функций ядра.
enum Forge {
    static let domain = Array("CipherKeyboard v1".utf8)

    /// Запись получателя: ключ сообщения, завёрнутый для `recipient` эфемерным ключом `ephemeral`.
    static func entry(
        _ messageKey: [UInt8], ephemeral: Curve25519.KeyAgreement.PrivateKey, to recipient: PublicKey
    ) throws -> [UInt8] {
        let recipientRaw = Array(try #require(rawKey(recipient))[0..<32])
        let ephemeralRaw = Array(ephemeral.publicKey.rawRepresentation)
        let secret = try ephemeral.sharedSecretFromKeyAgreement(
            with: Curve25519.KeyAgreement.PublicKey(rawRepresentation: recipientRaw))
        let wrapKey = secret.hkdfDerivedSymmetricKey(
            using: SHA256.self, salt: [UInt8](), sharedInfo: domain + ephemeralRaw + recipientRaw,
            outputByteCount: 32)
        let box = try ChaChaPoly.seal(
            messageKey, using: wrapKey, nonce: ChaChaPoly.Nonce(data: [UInt8](repeating: 0, count: 12)))
        return Array(box.ciphertext) + Array(box.tag)
    }

    private static func derived(_ messageKey: [UInt8], _ label: String) -> SymmetricKey {
        HKDF<SHA256>.deriveKey(
            inputKeyMaterial: SymmetricKey(data: messageKey), salt: [UInt8](), info: domain + Array(label.utf8),
            outputByteCount: 32)
    }

    /// Ключ шифрования текста: HKDF-SHA256(K, info = домен ‖ "text").
    static func textKey(_ messageKey: [UInt8]) -> SymmetricKey { derived(messageKey, "text") }

    /// Обязательство на ключ сообщения: HKDF-SHA256(K, info = домен ‖ "commit").
    static func commitment(_ messageKey: [UInt8]) -> [UInt8] {
        derived(messageKey, "commit").withUnsafeBytes { Array($0) }
    }

    /// Честная открытая часть: настоящая длина (UInt16 BE) ‖ текст ‖ нули до кратного 32.
    static func padded(_ text: [UInt8]) -> [UInt8] {
        let paddedCount = (text.count + 31) / 32 * 32
        return [UInt8(text.count >> 8), UInt8(text.count & 0xFF)] + text
            + [UInt8](repeating: 0, count: paddedCount - text.count)
    }

    static func randomKey() -> [UInt8] {
        SymmetricKey(size: .bits256).withUnsafeBytes { Array($0) }
    }

    /// Сообщение от `sender`: записи как есть, обязательство как есть, открытая часть `plain` (уже с длиной
    /// и дополнением) зашифрована ключом текста от `textMessageKey`; подпись — настоящим ключом `sender`.
    static func message(
        from sender: Identity, ephemeral: Curve25519.KeyAgreement.PrivateKey, entries: [[UInt8]],
        commitment: [UInt8], textMessageKey: [UInt8], plain: [UInt8]
    ) throws -> Envelope {
        var envelope = Envelope(
            version: .legacy, senderKey: try #require(rawKey(sender.publicKey)),
            ephemeralKey: Array(ephemeral.publicKey.rawRepresentation),
            entries: entries, commitment: commitment, nonce: Array(ChaChaPoly.Nonce()),
            ciphertext: [UInt8](repeating: 0, count: plain.count + 16), signature: [])
        // AAD — байты до nonce; длина шифротекста уже верная, поэтому заголовок совпадает с итоговым.
        let box = try ChaChaPoly.seal(
            plain, using: textKey(textMessageKey), nonce: ChaChaPoly.Nonce(data: envelope.nonce),
            authenticating: envelope.textAAD)
        envelope.ciphertext = Array(box.ciphertext) + Array(box.tag)
        envelope.signature = Array(try sender.signingKey().signature(for: envelope.signedBytes))
        return envelope
    }
}
