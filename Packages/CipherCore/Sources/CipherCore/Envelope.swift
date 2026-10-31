import Foundation

/// Байтовая раскладка `ckmsg1` (см. FORMAT.md). Только формат — без криптографии.
struct Envelope: Equatable, Sendable {
    static let version: UInt8 = 1
    static let headerCount = 4  // версия, число записей, длина текста (UInt16 BE)
    static let senderKeyCount = PublicKey.rawCount  // 64
    static let ephemeralKeyCount = 32
    static let entryCount = 48  // завёрнутый ключ сообщения 32 + тег 16
    static let nonceCount = 12
    static let tagCount = 16
    static let signatureCount = 64
    /// Всё, кроме записей получателей и текста.
    static let fixedCount =
        headerCount + senderKeyCount + ephemeralKeyCount + nonceCount + tagCount + signatureCount  // 192
    /// Дальше этого числа символов после префикса тело не читается ни при каком заголовке.
    static let maxBodyCharacters = 20_000

    var senderKey: [UInt8]
    var ephemeralKey: [UInt8]
    var entries: [[UInt8]]
    var nonce: [UInt8]
    /// Шифротекст (длина текста) + тег Poly1305 (16).
    var ciphertext: [UInt8]
    var signature: [UInt8]

    /// Полная длина сообщения в байтах по полям заголовка.
    static func totalCount(entries: Int, textCount: Int) -> Int {
        fixedCount + entries * entryCount + textCount
    }

    var textCount: Int { ciphertext.count - Self.tagCount }

    var header: [UInt8] {
        Self.header(entries: entries.count, textCount: textCount)
    }

    /// Версия (1 байт), число записей (1 байт), длина текста в байтах (UInt16, big-endian).
    static func header(entries: Int, textCount: Int) -> [UInt8] {
        [
            version, UInt8(truncatingIfNeeded: entries), UInt8(truncatingIfNeeded: textCount >> 8),
            UInt8(truncatingIfNeeded: textCount),
        ]
    }

    /// AAD шифрования текста: заголовок, ключ отправителя, эфемерный ключ, записи.
    static func textAAD(header: [UInt8], senderKey: [UInt8], ephemeralKey: [UInt8], entries: [[UInt8]]) -> [UInt8] {
        header + senderKey + ephemeralKey + entries.flatMap { $0 }
    }

    /// AAD шифрования текста для этого сообщения (совпадает с байтами до nonce).
    var textAAD: [UInt8] {
        Self.textAAD(header: header, senderKey: senderKey, ephemeralKey: ephemeralKey, entries: entries)
    }

    /// Все байты до подписи в порядке раскладки FORMAT.md.
    var unsignedBytes: [UInt8] {
        header + senderKey + ephemeralKey + entries.flatMap { $0 } + nonce + ciphertext
    }

    /// Что подписывает Ed25519: доменная строка + все байты до подписи.
    var signedBytes: [UInt8] {
        CipherMessage.signatureDomain + unsignedBytes
    }

    var bytes: [UInt8] {
        unsignedBytes + signature
    }

    var string: String {
        "ckmsg1:" + Base64URL.encode(bytes)
    }

    /// Разбор декодированных байт. Длина должна точно совпадать с заголовком.
    init(bytes: [UInt8]) throws(CipherError) {
        guard bytes.count >= Self.headerCount, bytes[0] == Self.version else { throw .malformed }
        let entryCount = Int(bytes[1])
        let textCount = Int(bytes[2]) << 8 | Int(bytes[3])
        guard (1...CipherMessage.maxRecipients).contains(entryCount),
            (1...CipherMessage.maxPlaintextBytes).contains(textCount),
            bytes.count == Self.totalCount(entries: entryCount, textCount: textCount)
        else { throw .malformed }
        var offset = Self.headerCount
        func take(_ count: Int) -> [UInt8] {
            defer { offset += count }
            return Array(bytes[offset..<offset + count])
        }
        senderKey = take(Self.senderKeyCount)
        ephemeralKey = take(Self.ephemeralKeyCount)
        entries = (0..<entryCount).map { _ in take(Self.entryCount) }
        nonce = take(Self.nonceCount)
        ciphertext = take(textCount + Self.tagCount)
        signature = take(Self.signatureCount)
    }

    init(
        senderKey: [UInt8], ephemeralKey: [UInt8], entries: [[UInt8]], nonce: [UInt8], ciphertext: [UInt8],
        signature: [UInt8]
    ) {
        self.senderKey = senderKey
        self.ephemeralKey = ephemeralKey
        self.entries = entries
        self.nonce = nonce
        self.ciphertext = ciphertext
        self.signature = signature
    }

    /// Находит первое `ckmsg<цифры>:` в тексте и разбирает ровно столько символов, сколько требует заголовок.
    static func find(in text: String) throws(CipherError) -> Envelope {
        let bytes = CompactText.bytes(text)
        let name = Array("ckmsg".utf8)
        var start = 0
        var found: (version: [UInt8], bodyStart: Int)?
        while start + name.count < bytes.count {
            if let prefix = CompactText.versionedPrefix(bytes, name: name, at: start) {
                found = prefix
                break
            }
            start += 1
        }
        guard let found else { throw .noMessage }
        guard found.version == Array("1".utf8) else { throw .unsupportedVersion }

        // Символы base64url подряд после префикса — но не дальше, чем может понадобиться.
        let bodyStart = found.bodyStart
        func runLength(limit: Int) -> Int {
            var index = bodyStart
            while index < bytes.count, index - bodyStart < limit, Base64URL.value(of: bytes[index]) != nil {
                index += 1
            }
            return index - bodyStart
        }

        // Заголовок: первые 8 символов дают 6 байт, из них нужны 4.
        let headerChars = 8
        guard runLength(limit: headerChars) == headerChars,
            let head = Base64URL.decode(bytes[bodyStart..<bodyStart + headerChars]), head[0] == Self.version
        else { throw .malformed }
        let entryCount = Int(head[1])
        let textCount = Int(head[2]) << 8 | Int(head[3])
        guard (1...CipherMessage.maxRecipients).contains(entryCount),
            (1...CipherMessage.maxPlaintextBytes).contains(textCount)
        else { throw .malformed }
        let needed = Base64URL.encodedLength(byteCount: totalCount(entries: entryCount, textCount: textCount))
        guard needed <= maxBodyCharacters, runLength(limit: needed) == needed,
            let decoded = Base64URL.decode(bytes[bodyStart..<bodyStart + needed])
        else { throw .malformed }
        return try Envelope(bytes: decoded)
    }
}
