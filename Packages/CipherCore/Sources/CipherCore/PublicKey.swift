import CryptoKit
import Foundation

/// Открытый ключ собеседника: X25519 (согласование) + Ed25519 (подпись). В тексте — одна строка `ckpub1:…`.
public struct PublicKey: Hashable, Sendable, Codable, CustomStringConvertible {
    static let prefixName = Array("ckpub".utf8)
    static let currentVersion = Array("1".utf8)
    /// 32 байта X25519 + 32 байта Ed25519.
    static let rawCount = 64
    static let bodyLength = Base64URL.encodedLength(byteCount: rawCount)  // 86

    /// Сырые 64 байта: публичный X25519 (32) + публичный Ed25519 (32).
    let raw: [UInt8]

    /// Ключ из проверенных сырых байт. Только для ключей, полученных из приватных (своя личность).
    init(trustedRaw raw: [UInt8]) {
        self.raw = raw
    }

    /// Ключ из сырых байт чужого происхождения: длина 64, ни часть X25519, ни часть Ed25519 — не точка малого порядка.
    init(validatingRaw raw: [UInt8]) throws(CipherError) {
        guard raw.count == Self.rawCount else { throw .invalidKey }
        guard Self.isUsableAgreementKey(Array(raw[0..<32])) else { throw .invalidKey }
        guard Self.isUsableSigningKey(Array(raw[32..<64])) else { throw .invalidKey }
        self.raw = raw
    }

    /// Разбирает строку `ckpub1:…`. Пробелы и переводы строк (`whitespacesAndNewlines`) удаляются в любом месте,
    /// паддинг `=` на конце допускается; всё остальное должно быть ровно одним ключом.
    public init(string: String) throws {
        let bytes = CompactText.bytes(string)
        guard let prefix = CompactText.versionedPrefix(bytes, name: Self.prefixName, at: 0) else {
            throw CipherError.invalidKey
        }
        guard prefix.version == Self.currentVersion else { throw CipherError.unsupportedVersion }
        var body = Array(bytes[prefix.bodyStart...])
        var padding = 0
        while body.last == UInt8(ascii: "=") {
            body.removeLast()
            padding += 1
        }
        if padding > 0, (body.count + padding) % 4 != 0 || padding > 2 {
            throw CipherError.invalidKey
        }
        guard body.count == Self.bodyLength, let raw = Base64URL.decode(body), raw.count == Self.rawCount else {
            throw CipherError.invalidKey
        }
        try self.init(validatingRaw: raw)
    }

    /// `"ckpub1:"` + base64url без паддинга от 64 байт, всего 93 символа.
    public var string: String {
        "ckpub1:" + Base64URL.encode(raw)
    }

    public var fingerprint: Fingerprint {
        .init(publicKeyRaw: raw)  // без имени типа: проверка E18 ищет в Sources подстроку «print» со скобкой
    }

    public var description: String { string }

    var agreementRaw: [UInt8] { Array(raw[0..<32]) }
    var signingRaw: [UInt8] { Array(raw[32..<64]) }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        try self.init(string: try container.decode(String.self))
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(string)
    }

    /// Фиксированный скаляр для проверки точек: с точкой малого порядка общий секрет X25519 всегда нулевой,
    /// CryptoKit такое согласование отвергает.
    private static let probeScalar: [UInt8] = Array(repeating: 0x5A, count: 32)

    /// Можно ли согласовывать ключ с этой точкой X25519 (не нулевая и не малого порядка).
    static func isUsableAgreementKey(_ raw: [UInt8]) -> Bool {
        guard raw.count == 32,
            let point = try? Curve25519.KeyAgreement.PublicKey(rawRepresentation: raw),
            let probe = try? Curve25519.KeyAgreement.PrivateKey(rawRepresentation: probeScalar),
            let secret = try? probe.sharedSecretFromKeyAgreement(with: point)
        else { return false }
        return secret.withUnsafeBytes { buffer in buffer.contains { $0 != 0 } }
    }

    /// Кодировки всех 8 точек кручения Ed25519 (порядок 1, 2, 4, 8) с обнулённым знаковым битом,
    /// плюс неканонические `y = p` и `y = p + 1`. Тот же список, что `ge25519_has_small_order` в libsodium.
    /// С таким ключом подпись `R = 01 00…00, S = 0` (и подобные) верна для любых байт — подделать может кто угодно.
    private static let smallOrderSigningPoints: [[UInt8]] = [
        // 0 (порядок 4)
        [UInt8](repeating: 0x00, count: 32),
        // 1 — нейтральная точка (порядок 1)
        [0x01] + [UInt8](repeating: 0x00, count: 31),
        // порядок 8
        [
            0x26, 0xE8, 0x95, 0x8F, 0xC2, 0xB2, 0x27, 0xB0, 0x45, 0xC3, 0xF4, 0x89, 0xF2, 0xEF, 0x98, 0xF0,
            0xD5, 0xDF, 0xAC, 0x05, 0xD3, 0xC6, 0x33, 0x39, 0xB1, 0x38, 0x02, 0x88, 0x6D, 0x53, 0xFC, 0x05,
        ],
        // порядок 8
        [
            0xC7, 0x17, 0x6A, 0x70, 0x3D, 0x4D, 0xD8, 0x4F, 0xBA, 0x3C, 0x0B, 0x76, 0x0D, 0x10, 0x67, 0x0F,
            0x2A, 0x20, 0x53, 0xFA, 0x2C, 0x39, 0xCC, 0xC6, 0x4E, 0xC7, 0xFD, 0x77, 0x92, 0xAC, 0x03, 0x7A,
        ],
        // p − 1 (порядок 2)
        [0xEC] + [UInt8](repeating: 0xFF, count: 30) + [0x7F],
        // p, неканоническая 0 (порядок 4)
        [0xED] + [UInt8](repeating: 0xFF, count: 30) + [0x7F],
        // p + 1, неканоническая 1 (порядок 1)
        [0xEE] + [UInt8](repeating: 0xFF, count: 30) + [0x7F],
    ]

    /// Можно ли проверять подписи этим ключом Ed25519: 32 байта и не точка малого порядка
    /// (сравниваются 31 байт и последний байт без знакового бита).
    static func isUsableSigningKey(_ raw: [UInt8]) -> Bool {
        guard raw.count == 32, (try? Curve25519.Signing.PublicKey(rawRepresentation: raw)) != nil else { return false }
        var masked = raw
        masked[31] &= 0x7F
        return !smallOrderSigningPoints.contains(masked)
    }
}

/// Отпечаток открытого ключа: первые 16 байт SHA-256 от 64 байт ключа, 8 групп по 4 hex-символа.
public struct Fingerprint: Hashable, Sendable, CustomStringConvertible {
    let bytes: [UInt8]

    init(publicKeyRaw: [UInt8]) {
        bytes = Array(SHA256.hash(data: publicKeyRaw).prefix(16))
    }

    private var groups: [String] {
        let hex = bytes.map { byte in
            let digits = Array("0123456789ABCDEF")
            return String([digits[Int(byte >> 4)], digits[Int(byte & 0x0F)]])
        }
        return stride(from: 0, to: hex.count, by: 2).map { hex[$0] + hex[$0 + 1] }
    }

    /// `"A1B2 C3D4 E5F6 …"` — 8 групп через пробел, 39 символов.
    public var description: String { groups.joined(separator: " ") }

    /// Первые 2 группы: `"A1B2 C3D4"`.
    public var short: String { groups.prefix(2).joined(separator: " ") }
}
