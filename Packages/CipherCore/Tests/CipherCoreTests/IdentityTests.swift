import CipherCore
import Foundation
import Testing

@Suite("Личность: создание и восстановление")
struct IdentityTests {
    @Test("Две генерации дают разные открытые ключи и отпечатки")
    func twoGenerationsDiffer() {
        let a = Identity.generate()
        let b = Identity.generate()
        #expect(a.publicKey != b.publicKey)
        #expect(a.publicKey.fingerprint != b.publicKey.fingerprint)
    }

    @Test("privateKeyData — ровно 64 байта")
    func privateKeyDataIs64Bytes() {
        let a = Identity.generate()
        #expect(a.privateKeyData().count == 64)
    }

    @Test("Восстановленная личность имеет тот же открытый ключ")
    func restoredIdentityHasSamePublicKey() throws {
        let a = Identity.generate()
        let restored = try Identity(privateKeyData: a.privateKeyData())
        #expect(restored.publicKey == a.publicKey)
    }

    @Test("Восстановленная личность расшифровывает сообщение для исходной и подписывает как она")
    func restoredIdentityOpensAndSigns() throws {
        let a = Identity.generate()
        let b = Identity.generate()
        let restored = try Identity(privateKeyData: a.privateKeyData())

        let toA = try CipherMessage.seal("Для исходной личности", from: b, to: [a.publicKey])
        let opened = try CipherMessage.open(toA, as: restored, contacts: [])
        #expect(Array(opened.text.utf8) == Array("Для исходной личности".utf8))

        let contactA = Contact(name: "A", publicKey: a.publicKey)
        let fromRestored = try CipherMessage.seal("От восстановленной", from: restored, to: [b.publicKey])
        let openedByB = try CipherMessage.open(fromRestored, as: b, contacts: [contactA])
        #expect(openedByB.sender == .contact(contactA))
    }

    @Test("Приватные данные не из 64 байт → invalidKey", arguments: [0, 63, 65])
    func wrongLengthIsInvalidKey(count: Int) {
        let data = Data(repeating: 0x42, count: count)
        #expect(throws: CipherError.invalidKey) {
            _ = try Identity(privateKeyData: data)
        }
    }
}

@Suite("Личность: приватный ключ не утекает")
struct IdentityRedactionTests {
    /// Все представления личности, которые может вывести отладка или журнал.
    private func renderings(of identity: Identity) -> [String] {
        var dumped = ""
        dump(identity, to: &dumped)
        return [String(describing: identity), String(reflecting: identity), "\(identity)", dumped]
    }

    @Test("Описание, отладочное описание, интерполяция и dump показывают только отпечаток")
    func renderingsShowOnlyFingerprint() {
        let a = Identity.generate()
        let expected = "Identity(" + a.publicKey.fingerprint.description + ")"
        let rendered = renderings(of: a)
        #expect(rendered[0].contains(expected), "String(describing:)")
        #expect(rendered[1].contains(expected), "String(reflecting:)")
        #expect(rendered[2].contains(expected), "интерполяция")
        #expect(rendered[3].contains(expected), "dump")
    }

    @Test("Ни одна половина приватного ключа не видна в hex, base64 и base64url")
    func renderingsContainNoPrivateBytes() {
        let a = Identity.generate()
        let secret = Array(a.privateKeyData())
        let halves = [Array(secret[0..<32]), Array(secret[32..<64])]
        let names = ["String(describing:)", "String(reflecting:)", "интерполяция", "dump"]
        for (name, text) in zip(names, renderings(of: a)) {
            for (half, bytes) in halves.enumerated() {
                #expect(!text.contains(hex(bytes)), "\(name): половина \(half) в hex (нижний регистр)")
                #expect(!text.contains(hex(bytes, uppercase: true)), "\(name): половина \(half) в HEX")
                #expect(!text.contains(base64(bytes)), "\(name): половина \(half) в base64")
                #expect(!text.contains(base64url(bytes)), "\(name): половина \(half) в base64url")
            }
        }
    }

    @Test("Личность не Encodable")
    func identityIsNotEncodable() {
        let a = Identity.generate()
        #expect(((a as Any) is any Encodable) == false)
    }
}
