import Foundation
import Testing

@testable import CipherCore

@Suite("Шифротекст находится в тексте с переносами и словами вокруг")
struct FindInTextTests {
    private let a = Identity.generate()
    private let b = Identity.generate()

    private func opened(_ text: String) throws -> String {
        try CipherMessage.open(text, as: b, contacts: []).text
    }

    @Test("Все варианты вставки открываются в «Тест»")
    func variants() throws {
        let m = try CipherMessage.seal("Тест", from: a, to: [b.publicKey])
        let chars = Array(m)
        let newlineEvery10 = stride(from: 0, to: chars.count, by: 10)
            .map { String(chars[$0..<min($0 + 10, chars.count)]) }
            .joined(separator: "\n")
        let spacedPrefix = "ck msg2:\u{00A0}" + m.dropFirst("ckmsg2:".count)

        #expect(try opened(m) == "Тест", "как есть")
        #expect(try opened(newlineEvery10) == "Тест", "\\n каждые 10 символов")
        #expect(try opened(spacedPrefix) == "Тест", "пробел после ck и неразрывный пробел после двоеточия")
        #expect(try opened(m + "==") == "Тест", "паддинг ==")
        #expect(try opened("Привет! " + m + " спасибо") == "Тест", "слова вокруг")
        #expect(try opened(m + "ok") == "Тест", "слово сразу после, без пробела")
        #expect(try opened(m + "\nok") == "Тест", "слово на следующей строке")
        #expect(try opened(m + " ckmsg2:AAAA") == "Тест", "обрывок второго сообщения после")
        #expect(try opened("🔒 CipherKeyboard: " + m) == "Тест", "подпись перед сообщением")
    }

    @Test("Из двух сообщений подряд открывается первое")
    func firstOfTwo() throws {
        let first = try CipherMessage.seal("Первое", from: a, to: [b.publicKey])
        let second = try CipherMessage.seal("Второе", from: a, to: [b.publicKey])
        #expect(try opened(first + "\n" + second) == "Первое")
    }
}

@Suite("Испорченный или чужой текст — точная ошибка без падения")
struct MalformedInputTests {
    private let a = Identity.generate()
    private let b = Identity.generate()

    private func message() throws -> String {
        try CipherMessage.seal("Проверка разбора", from: a, to: [b.publicKey])
    }

    private func body(_ message: String) -> Substring {
        message.dropFirst("ckmsg2:".count)
    }

    private func open(_ text: String) throws {
        _ = try CipherMessage.open(text, as: b, contacts: [])
    }

    @Test("Нет ckmsg<цифры>: → noMessage")
    func noMessage() throws {
        let m = try message()
        #expect(throws: CipherError.noMessage) { try open("") }
        #expect(throws: CipherError.noMessage) { try open("Привет, как дела?") }
        #expect(throws: CipherError.noMessage) { try open(b.publicKey.string) }
        #expect(throws: CipherError.noMessage) { try open("ckmsg:" + body(m)) }
    }

    @Test("Другая версия → unsupportedVersion")
    func unsupportedVersion() throws {
        let m = try message()
        #expect(throws: CipherError.unsupportedVersion) { try open("ckmsg3:" + body(m)) }
        #expect(throws: CipherError.unsupportedVersion) { try open("ckmsg10:" + body(m)) }
    }

    @Test("Только префикс → malformed")
    func prefixOnly() {
        #expect(throws: CipherError.malformed) { try open("ckmsg2:") }
    }

    @Test("Без последнего символа → malformed")
    func missingLastCharacter() throws {
        let m = try message()
        #expect(throws: CipherError.malformed) { try open(String(m.dropLast())) }
    }

    @Test("Первая половина → malformed")
    func firstHalf() throws {
        let m = try message()
        #expect(throws: CipherError.malformed) { try open(String(m.prefix(m.count / 2))) }
    }

    @Test("50 символов «A» → malformed")
    func fiftyAs() {
        #expect(throws: CipherError.malformed) { try open("ckmsg2:" + String(repeating: "A", count: 50)) }
    }

    @Test("* вместо символа в середине → malformed")
    func asteriskInMiddle() throws {
        let m = try message()
        let broken = replacingCharacter(in: m, at: m.count / 2, with: "*")
        #expect(throws: CipherError.malformed) { try open(broken) }
    }

    @Test("1 000 000 символов «A» → malformed быстрее 1 секунды")
    func megabyteOfGarbage() {
        let garbage = "ckmsg2:" + String(repeating: "A", count: 1_000_000)
        let clock = ContinuousClock()
        let elapsed = clock.measure {
            #expect(throws: CipherError.malformed) { try open(garbage) }
        }
        #expect(elapsed < .seconds(1), "заняло \(elapsed)")
    }

    @Test("Верный заголовок настоящего сообщения + 1 000 000 «A» → ошибка быстрее 1 секунды")
    func realHeaderThenMegabyte() throws {
        let m = try message()
        let header = m.dropFirst("ckmsg2:".count).prefix(8)
        let garbage = "ckmsg2:" + header + String(repeating: "A", count: 1_000_000)
        let clock = ContinuousClock()
        let elapsed = clock.measure {
            do {
                _ = try open(garbage)
                Issue.record("огромное тело открылось")
            } catch let error as CipherError {
                #expect(error == .malformed || error == .tampered, "\(error)")
            } catch {
                Issue.record("не CipherError: \(error)")
            }
        }
        #expect(elapsed < .seconds(1), "заняло \(elapsed)")
    }

    @Test("Эфемерный ключ — точка малого порядка, подпись пересчитана отправителем → malformed")
    func smallOrderEphemeralKey() throws {
        let honest = try Envelope(bytes: try #require(decodedMessage(try message())))
        for point in [[UInt8](repeating: 0, count: 32), [1] + [UInt8](repeating: 0, count: 31)] {
            var forged = honest
            forged.ephemeralKey = point
            forged.signature = Array(try a.signingKey().signature(for: forged.signedBytes))
            #expect(throws: CipherError.malformed, "\(hex(point))") { try open(forged.string) }
        }
    }

    @Test("17 записей получателей в заголовке → malformed")
    func seventeenEntries() throws {
        let honest = try Envelope(bytes: try #require(decodedMessage(try message())))
        var forged = honest
        forged.entries = (0..<17).map { _ in [UInt8](repeating: 0x11, count: Envelope.entryCount) }
        forged.signature = Array(try a.signingKey().signature(for: forged.signedBytes))
        let decoded = try #require(decodedMessage(forged.string))
        #expect(decoded[1] == 17)
        #expect(throws: CipherError.malformed) { try open(forged.string) }
    }
}
