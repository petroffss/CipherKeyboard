import CipherCore
import Testing

@Suite("Вердикт отправителя: я, контакт или неизвестный ключ")
struct SenderVerdictTests {
    private let text = "Кто это написал?"
    private let a = Identity.generate()
    private let b = Identity.generate()
    private let c = Identity.generate()

    @Test("Ключ отправителя совпал с контактом → contact(тот же контакт)")
    func matchingContact() throws {
        let anya = Contact(name: "Аня", publicKey: a.publicKey)
        let vasya = Contact(name: "Вася", publicKey: c.publicKey)
        let m = try CipherMessage.seal(text, from: a, to: [b.publicKey])
        let opened = try CipherMessage.open(m, as: b, contacts: [anya, vasya])
        #expect(opened.sender == .contact(anya))
        if case .contact(let contact) = opened.sender {
            #expect(contact.id == anya.id)
        }
        #expect(opened.senderKey == a.publicKey)
    }

    @Test("Без контактов → unknown(отпечаток A)")
    func noContacts() throws {
        let m = try CipherMessage.seal(text, from: a, to: [b.publicKey])
        let opened = try CipherMessage.open(m, as: b, contacts: [])
        #expect(opened.sender == .unknown(a.publicKey.fingerprint))
        #expect(opened.senderKey == a.publicKey)
    }

    @Test("Контакт с тем же именем, но другим ключом → unknown(отпечаток A)")
    func sameNameOtherKey() throws {
        let m = try CipherMessage.seal(text, from: a, to: [b.publicKey])
        let opened = try CipherMessage.open(m, as: b, contacts: [Contact(name: "Аня", publicKey: c.publicKey)])
        #expect(opened.sender == .unknown(a.publicKey.fingerprint))
        #expect(opened.senderKey == a.publicKey)
    }

    @Test("Отправитель открывает своё сообщение → me при любых контактах")
    func ownMessageIsMe() throws {
        let m = try CipherMessage.seal(text, from: a, to: [b.publicKey])
        let contactLists: [[Contact]] = [
            [],
            [Contact(name: "Аня", publicKey: a.publicKey)],
            [Contact(name: "Вася", publicKey: c.publicKey), Contact(name: "Боря", publicKey: b.publicKey)],
        ]
        for contacts in contactLists {
            let opened = try CipherMessage.open(m, as: a, contacts: contacts)
            #expect(opened.sender == .me)
            #expect(opened.senderKey == a.publicKey)
        }
    }
}
