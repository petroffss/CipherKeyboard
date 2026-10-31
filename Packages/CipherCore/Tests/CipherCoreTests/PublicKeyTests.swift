import CipherCore
import Foundation
import Testing

/// Фиксированный вектор ключа: сгенерирован один раз, отпечаток сверен независимо (python3 + hashlib).
enum FixedKeyVector {
    static let privateKeyHex =
        "7dd2194a143a8b6f7fd2d014c7ecb479cc07c59e31bd000c629fb39c0c234d66"
        + "6399c84b3c43470db5260e1f77a40ba508300b7a4a364c158419eb694feda2fc"
    static let publicKeyString =
        "ckpub1:nw2N-r13YwD1lXTt4NGrkPCikw1gT6qfuwgDrAbOVy2IdXVxWwF5pDvEo61t7wYXDs1pencI1Nu_PMEic2NYoQ"
    static let fingerprint = "3CE9 D861 1272 B2A6 0720 1589 E865 3A98"
    static let fingerprintShort = "3CE9 D861"
}

@Suite("Открытый ключ: строка ckpub1 и обратно")
struct PublicKeyTests {
    @Test("Строка ключа — ckpub1: и 86 символов base64url, всего 93")
    func stringShape() {
        let k = Identity.generate().publicKey
        #expect(k.string.wholeMatch(of: /ckpub1:[A-Za-z0-9_-]{86}/) != nil)
        #expect(k.string.count == 93)
    }

    @Test("Строка разбирается обратно в равный ключ")
    func roundTrip() throws {
        let k = Identity.generate().publicKey
        #expect(try PublicKey(string: k.string) == k)
    }

    @Test("Пробел после двоеточия не мешает")
    func spaceAfterColon() throws {
        let k = Identity.generate().publicKey
        let text = "ckpub1: " + k.string.dropFirst(7)
        #expect(try PublicKey(string: text) == k)
    }

    @Test("Перевод строки каждые 20 символов не мешает")
    func newlineEvery20Characters() throws {
        let k = Identity.generate().publicKey
        let chars = Array(k.string)
        let text = stride(from: 0, to: chars.count, by: 20).map { String(chars[$0..<min($0 + 20, chars.count)]) }
            .joined(separator: "\n")
        #expect(text.contains("\n"))
        #expect(try PublicKey(string: text) == k)
    }

    @Test("Неразрывный пробел внутри ckpub1 не мешает")
    func noBreakSpaceInsidePrefix() throws {
        let k = Identity.generate().publicKey
        let text = "ckp\u{00A0}ub1" + k.string.dropFirst(6)
        #expect(try PublicKey(string: text) == k)
    }

    @Test("Паддинг == на конце принимается")
    func paddingAccepted() throws {
        let k = Identity.generate().publicKey
        #expect(try PublicKey(string: k.string + "==") == k)
    }

    @Test("JSON: ключ кодируется строкой ckpub1 и декодируется обратно")
    func jsonCoding() throws {
        let k = Identity.generate().publicKey
        let json = try JSONEncoder().encode(k)
        #expect(String(decoding: json, as: UTF8.self) == "\"" + k.string + "\"")
        #expect(try JSONDecoder().decode(PublicKey.self, from: json) == k)
    }

    @Test("Фиксированный вектор: приватные байты → строка ckpub1 и отпечаток")
    func fixedVector() throws {
        let privateBytes = try #require(bytes(hex: FixedKeyVector.privateKeyHex))
        #expect(privateBytes.count == 64)
        let identity = try Identity(privateKeyData: Data(privateBytes))
        #expect(identity.publicKey.string == FixedKeyVector.publicKeyString)
        #expect(identity.publicKey.fingerprint.description == FixedKeyVector.fingerprint)
        #expect(identity.publicKey.fingerprint.short == FixedKeyVector.fingerprintShort)
        #expect(try PublicKey(string: FixedKeyVector.publicKeyString) == identity.publicKey)
    }

    @Test("Отпечаток — 8 групп по 4 HEX через пробел, short — первые 9 символов")
    func fingerprintShape() {
        let fingerprint = Identity.generate().publicKey.fingerprint
        #expect(fingerprint.description.wholeMatch(of: /[0-9A-F]{4}( [0-9A-F]{4}){7}/) != nil)
        #expect(fingerprint.description.count == 39)
        #expect(fingerprint.short == String(fingerprint.description.prefix(9)))
        #expect(FixedKeyVector.fingerprintShort == String(FixedKeyVector.fingerprint.prefix(9)))
    }
}

@Suite("Открытый ключ: неверный ввод")
struct InvalidPublicKeyTests {
    private let key = Identity.generate().publicKey
    private var body: Substring { key.string.dropFirst(7) }

    /// Строка ключа с заданной частью X25519 и настоящей частью Ed25519, в корректном base64url.
    private func keyString(agreementPart: [UInt8]) throws -> String {
        let raw = try #require(rawKey(key))
        return "ckpub1:" + base64url(agreementPart + raw[32..<64])
    }

    /// Строка ключа с настоящей частью X25519 и заданной частью Ed25519, в корректном base64url.
    private func keyString(signingPart: [UInt8]) throws -> String {
        let raw = try #require(rawKey(key))
        return "ckpub1:" + base64url(Array(raw[0..<32]) + signingPart)
    }

    @Test("Пустая строка → invalidKey")
    func empty() {
        #expect(throws: CipherError.invalidKey) { _ = try PublicKey(string: "") }
    }

    @Test("Только префикс → invalidKey")
    func prefixOnly() {
        #expect(throws: CipherError.invalidKey) { _ = try PublicKey(string: "ckpub1:") }
    }

    @Test("Без последнего символа → invalidKey")
    func missingLastCharacter() {
        #expect(throws: CipherError.invalidKey) { _ = try PublicKey(string: String(key.string.dropLast())) }
    }

    @Test("С лишним символом → invalidKey")
    func extraCharacter() {
        #expect(throws: CipherError.invalidKey) { _ = try PublicKey(string: key.string + "A") }
    }

    @Test("Текст вокруг ключа → invalidKey")
    func textAround() {
        #expect(throws: CipherError.invalidKey) { _ = try PublicKey(string: "Мой ключ: " + key.string) }
    }

    @Test("Чужой префикс → invalidKey")
    func foreignPrefix() {
        #expect(throws: CipherError.invalidKey) { _ = try PublicKey(string: "ckpkx1:" + body) }
    }

    @Test("Строка сообщения ckmsg1 → invalidKey")
    func messageString() throws {
        let message = try CipherMessage.seal("Привет", from: Identity.generate(), to: [key])
        #expect(throws: CipherError.invalidKey) { _ = try PublicKey(string: message) }
    }

    @Test("Неканонический base64: изменены только неиспользуемые биты последнего символа → invalidKey")
    func nonCanonicalLastCharacter() throws {
        let last = try #require(key.string.last)
        let value = try #require(base64urlAlphabet.firstIndex(of: last))
        // 64 байта = 85 полных символов + 1 символ, у которого используются только 2 старших бита из 6.
        #expect(value & 0x0F == 0)
        let changed = base64urlAlphabet[value | 0x01]
        #expect(changed != last)
        let text = String(key.string.dropLast()) + String(changed)
        // Те же байты при «нестрогом» разборе — разница только в неиспользуемых битах.
        #expect(decodeBase64url(text.dropFirst(7)) == rawKey(key))
        #expect(throws: CipherError.invalidKey) { _ = try PublicKey(string: text) }
    }

    @Test("Часть X25519 из 32 нулевых байт → invalidKey")
    func zeroAgreementKey() throws {
        let text = try keyString(agreementPart: [UInt8](repeating: 0, count: 32))
        #expect(text.wholeMatch(of: /ckpub1:[A-Za-z0-9_-]{86}/) != nil)
        #expect(throws: CipherError.invalidKey) { _ = try PublicKey(string: text) }
    }

    @Test("Часть X25519 — точка малого порядка 01 00…00 → invalidKey")
    func smallOrderAgreementKey() throws {
        let text = try keyString(agreementPart: [1] + [UInt8](repeating: 0, count: 31))
        #expect(text.wholeMatch(of: /ckpub1:[A-Za-z0-9_-]{86}/) != nil)
        // Ключ, который не разбирается, нельзя получить и передать в seal: у PublicKey нет других публичных init.
        #expect(throws: CipherError.invalidKey) { _ = try PublicKey(string: text) }
    }

    @Test("Часть Ed25519 — нейтральная точка 01 00…00 → invalidKey")
    func identitySigningKey() throws {
        let text = try keyString(signingPart: [1] + [UInt8](repeating: 0, count: 31))
        #expect(text.wholeMatch(of: /ckpub1:[A-Za-z0-9_-]{86}/) != nil)
        #expect(throws: CipherError.invalidKey) { _ = try PublicKey(string: text) }
    }

    @Test(
        "Часть Ed25519 — любая точка малого порядка (и со знаковым битом) → invalidKey",
        arguments: SmallOrderEd25519.encodings)
    func smallOrderSigningKey(point: String) throws {
        let part = try #require(bytes(hex: point))
        #expect(part.count == 32)
        var signed = part
        signed[31] |= 0x80
        for variant in [part, signed] {
            let text = try keyString(signingPart: variant)
            #expect(text.wholeMatch(of: /ckpub1:[A-Za-z0-9_-]{86}/) != nil)
            #expect(throws: CipherError.invalidKey, "\(hex(variant))") { _ = try PublicKey(string: text) }
        }
    }

    @Test("Контроль: та же сборка с настоящей частью Ed25519 разбирается")
    func realSigningPartAccepted() throws {
        let raw = try #require(rawKey(key))
        #expect(try PublicKey(string: try keyString(signingPart: Array(raw[32..<64]))) == key)
    }

    @Test("Другая версия ckpub2 → unsupportedVersion")
    func otherVersion() {
        #expect(throws: CipherError.unsupportedVersion) { _ = try PublicKey(string: "ckpub2:" + body) }
    }
}
