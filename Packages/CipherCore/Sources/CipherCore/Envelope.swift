import Foundation

/// Байтовая раскладка `ckmsg1` и `ckmsg2` (см. FORMAT.md). Только формат — без криптографии.
struct Envelope: Equatable, Sendable {
    enum Version: UInt8, Sendable {
        case legacy = 1
        case timestamped = 2

        var timestampCount: Int { self == .timestamped ? MemoryLayout<UInt64>.size : 0 }
        var prefix: String { "ckmsg\(rawValue):" }
        var domain: [UInt8] { Array("CipherKeyboard v\(rawValue)".utf8) }
    }
    static let headerCount = 4  // версия, число записей, дополненная длина текста (UInt16 BE)
    static let senderKeyCount = PublicKey.rawCount  // 64
    static let ephemeralKeyCount = 32
    static let entryCount = 48  // завёрнутый ключ сообщения 32 + тег 16
    static let commitmentCount = 32  // обязательство на ключ сообщения
    static let nonceCount = 12
    /// Настоящая длина текста (UInt16 BE) — первые байты зашифрованной части, в открытом заголовке её нет.
    static let lengthCount = 2
    static let tagCount = 16
    static let signatureCount = 64
    /// Текст дополняется нулями до длины, кратной этому числу байт: точная длина не видна.
    static let paddingBlock = 32
    /// Всё, кроме записей получателей и дополненного текста.
    static let fixedCount =
        headerCount + senderKeyCount + ephemeralKeyCount + commitmentCount + nonceCount + lengthCount + tagCount
        + signatureCount  // 226
    /// Дальше этого числа символов после префикса тело не читается ни при каком заголовке.
    static let maxBodyCharacters = 20_000

    let version: Version
    var senderKey: [UInt8]
    var ephemeralKey: [UInt8]
    var entries: [[UInt8]]
    var commitment: [UInt8]
    var nonce: [UInt8]
    /// Зашифрованные дата (только v2), настоящая длина (2) и дополненный текст + тег Poly1305 (16).
    var ciphertext: [UInt8]
    var signature: [UInt8]

    /// Полная длина сообщения в байтах по полям заголовка.
    static func totalCount(version: Version, entries: Int, paddedCount: Int) -> Int {
        fixedCount + version.timestampCount + entries * entryCount + paddedCount
    }

    /// Дополненная длина текста для настоящей длины `textCount`: ближайшее сверху кратное 32.
    static func paddedCount(for textCount: Int) -> Int {
        (textCount + paddingBlock - 1) / paddingBlock * paddingBlock
    }

    /// Допустимая дополненная длина в заголовке: 32, 64, …, 4096.
    static func isValidPaddedCount(_ count: Int) -> Bool {
        count % paddingBlock == 0 && (paddingBlock...CipherMessage.maxPlaintextBytes).contains(count)
    }

    /// Дополненная длина текста по длине зашифрованной части.
    var paddedCount: Int { ciphertext.count - version.timestampCount - Self.lengthCount - Self.tagCount }

    var header: [UInt8] {
        Self.header(version: version, entries: entries.count, paddedCount: paddedCount)
    }

    /// Версия (1 байт), число записей (1 байт), дополненная длина текста в байтах (UInt16, big-endian).
    static func header(version: Version, entries: Int, paddedCount: Int) -> [UInt8] {
        [
            version.rawValue, UInt8(truncatingIfNeeded: entries), UInt8(truncatingIfNeeded: paddedCount >> 8),
            UInt8(truncatingIfNeeded: paddedCount),
        ]
    }

    /// AAD шифрования текста: заголовок, ключ отправителя, эфемерный ключ, записи, обязательство.
    static func textAAD(
        header: [UInt8], senderKey: [UInt8], ephemeralKey: [UInt8], entries: [[UInt8]], commitment: [UInt8]
    ) -> [UInt8] {
        header + senderKey + ephemeralKey + entries.flatMap { $0 } + commitment
    }

    /// AAD шифрования текста для этого сообщения (совпадает с байтами до nonce).
    var textAAD: [UInt8] {
        Self.textAAD(
            header: header, senderKey: senderKey, ephemeralKey: ephemeralKey, entries: entries, commitment: commitment)
    }

    /// Все байты до подписи в порядке раскладки FORMAT.md.
    var unsignedBytes: [UInt8] {
        textAAD + nonce + ciphertext
    }

    /// Что подписывает Ed25519: доменная строка + все байты до подписи.
    var signedBytes: [UInt8] {
        version.domain + unsignedBytes
    }

    var bytes: [UInt8] {
        unsignedBytes + signature
    }

    var string: String {
        version.prefix + Base64URL.encode(bytes)
    }

    /// Разбор декодированных байт. Длина должна точно совпадать с заголовком.
    init(bytes: [UInt8]) throws(CipherError) {
        guard bytes.count >= Self.headerCount, let version = Version(rawValue: bytes[0]) else {
            throw .malformed
        }
        self.version = version
        let entryCount = Int(bytes[1])
        let paddedCount = Int(bytes[2]) << 8 | Int(bytes[3])
        guard (1...CipherMessage.maxRecipients).contains(entryCount), Self.isValidPaddedCount(paddedCount),
            bytes.count == Self.totalCount(version: version, entries: entryCount, paddedCount: paddedCount)
        else { throw .malformed }
        var offset = Self.headerCount
        func take(_ count: Int) -> [UInt8] {
            defer { offset += count }
            return Array(bytes[offset..<offset + count])
        }
        senderKey = take(Self.senderKeyCount)
        ephemeralKey = take(Self.ephemeralKeyCount)
        entries = (0..<entryCount).map { _ in take(Self.entryCount) }
        commitment = take(Self.commitmentCount)
        nonce = take(Self.nonceCount)
        ciphertext = take(version.timestampCount + Self.lengthCount + paddedCount + Self.tagCount)
        signature = take(Self.signatureCount)
    }

    init(
        version: Version, senderKey: [UInt8], ephemeralKey: [UInt8], entries: [[UInt8]], commitment: [UInt8],
        nonce: [UInt8], ciphertext: [UInt8], signature: [UInt8]
    ) {
        self.version = version
        self.senderKey = senderKey
        self.ephemeralKey = ephemeralKey
        self.entries = entries
        self.commitment = commitment
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
        let version: Version
        switch found.version {
        case Array("1".utf8): version = .legacy
        case Array("2".utf8): version = .timestamped
        default: throw .unsupportedVersion
        }

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
            let head = Base64URL.decode(bytes[bodyStart..<bodyStart + headerChars]), head[0] == version.rawValue
        else { throw .malformed }
        let entryCount = Int(head[1])
        let paddedCount = Int(head[2]) << 8 | Int(head[3])
        guard (1...CipherMessage.maxRecipients).contains(entryCount), isValidPaddedCount(paddedCount) else {
            throw .malformed
        }
        let byteCount = totalCount(version: version, entries: entryCount, paddedCount: paddedCount)
        let needed = Base64URL.encodedLength(byteCount: byteCount)
        guard needed <= maxBodyCharacters, runLength(limit: needed) == needed,
            let decoded = Base64URL.decode(bytes[bodyStart..<bodyStart + needed])
        else { throw .malformed }
        return try Envelope(bytes: decoded)
    }
}
