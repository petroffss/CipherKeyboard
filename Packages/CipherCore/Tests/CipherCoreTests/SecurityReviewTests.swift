import Foundation
import Testing

@testable import CipherCore
@testable import CipherCoreContactStore

@Suite("Security review regressions")
struct SecurityReviewTests {
    @Test func rejectsMixedAgreementKeysWithoutMutatingContacts() throws {
        let own = Identity.generate().publicKey
        let anna = Identity.generate().publicKey
        let other = Identity.generate().publicKey
        var book = ContactBook()
        try book.add(name: "Анна", key: anna.string, own: own)
        let before = book
        let mixedOwn = try PublicKey(validatingRaw: own.agreementRaw + other.signingRaw)
        #expect(throws: ContactError.ownKey) { try book.add(name: "Подмена", key: mixedOwn.string, own: own) }
        let mixedAnna = try PublicKey(validatingRaw: anna.agreementRaw + other.signingRaw)
        #expect(throws: ContactError.sharedAgreementKey(existingName: "Анна")) {
            try book.add(name: "Подмена Анны", key: mixedAnna.string, own: own)
        }
        #expect(book == before)
    }

    @Test func existingMixedKeyBookRemainsReadableAndRepairable() throws {
        let anna = Identity.generate().publicKey
        let other = Identity.generate().publicKey
        let mixed = try PublicKey(validatingRaw: anna.agreementRaw + other.signingRaw)
        let first = Contact(name: "Анна", publicKey: anna)
        let second = Contact(name: "Старая запись", publicKey: mixed)
        let storage = InMemoryContactStorage()
        try storage.write(encodeContactsFile(ContactBook(contacts: [first, second])))
        let store = ContactStore(storage: storage)
        #expect(store.read() == .contacts([first, second]))
        let renamed = try store.rename(id: second.id, to: "Другая запись")
        #expect(renamed.count == 2)
        let removed = try store.remove(id: second.id)
        #expect(removed.contacts == [first])
    }

    @Test func singleMessageBoundaryUsesRealTimestampedCiphertext() throws {
        let sender = Identity.generate(), recipient = Identity.generate()
        for count in [2720, 2721, 4096] {
            let text = String(repeating: "a", count: count)
            let sealed = try CipherMessage.seal(text, from: sender, to: [recipient.publicKey])
            #expect((sealed.count <= 4096) == (count <= 2720))
            #expect(try CipherMessage.open(sealed, as: recipient, contacts: []).text == text)
        }
    }
}
