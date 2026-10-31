import CipherCore
import Testing

@Suite("Шифрование: лимиты и неверный ввод")
struct SealLimitsTests {
    private let a = Identity.generate()
    private let b = Identity.generate()

    @Test("Пустой текст → emptyMessage")
    func empty() {
        #expect(throws: CipherError.emptyMessage) {
            _ = try CipherMessage.seal("", from: a, to: [b.publicKey])
        }
    }

    @Test("4097 байт ASCII → messageTooLong(byteCount: 4097)")
    func tooLongAscii() {
        #expect(throws: CipherError.messageTooLong(byteCount: 4097)) {
            _ = try CipherMessage.seal(String(repeating: "a", count: 4097), from: a, to: [b.publicKey])
        }
    }

    @Test("2049 символов «ж» (4098 байт) → messageTooLong(byteCount: 4098)")
    func tooLongCyrillic() {
        #expect(throws: CipherError.messageTooLong(byteCount: 4098)) {
            _ = try CipherMessage.seal(String(repeating: "ж", count: 2049), from: a, to: [b.publicKey])
        }
    }

    @Test("Ровно 4096 байт (2048 «ж») шифруется и открывается")
    func exactlyMaximum() throws {
        let text = String(repeating: "ж", count: 2048)
        #expect(text.utf8.count == CipherMessage.maxPlaintextBytes)
        let m = try CipherMessage.seal(text, from: a, to: [b.publicKey])
        #expect(Array(try CipherMessage.open(m, as: b, contacts: []).text.utf8) == Array(text.utf8))
    }

    @Test("Пустой список получателей → noRecipients")
    func noRecipients() {
        #expect(throws: CipherError.noRecipients) {
            _ = try CipherMessage.seal("Привет", from: a, to: [])
        }
    }

    @Test("15 получателей + отправитель (16) шифруется")
    func sixteenRecipients() throws {
        let others = (0..<15).map { _ in Identity.generate() }
        let m = try CipherMessage.seal("Всем", from: a, to: others.map(\.publicKey))
        #expect(try CipherMessage.open(m, as: others[14], contacts: []).text == "Всем")
        #expect(try CipherMessage.open(m, as: a, contacts: []).text == "Всем")
    }

    @Test("16 получателей + отправитель (17) → tooManyRecipients")
    func seventeenRecipients() {
        let others = (0..<16).map { _ in Identity.generate().publicKey }
        #expect(throws: CipherError.tooManyRecipients) {
            _ = try CipherMessage.seal("Всем", from: a, to: others)
        }
    }

    @Test("Текст из пробелов и один символ шифруются и открываются", arguments: ["   ", "a"])
    func whitespaceAndSingleCharacter(text: String) throws {
        let m = try CipherMessage.seal(text, from: a, to: [b.publicKey])
        #expect(Array(try CipherMessage.open(m, as: b, contacts: []).text.utf8) == Array(text.utf8))
    }
}
