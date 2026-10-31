import CipherCore
import Foundation
import Testing

/// Золотой вектор `ckmsg1`: сгенерирован один раз и сохранён литералами. Если тест упал после правки ядра —
/// формат изменился, и старые сообщения пользователей перестанут открываться. Меняйте версию, а не вектор.
enum GoldenVector {
    static let privateKeyA =
        "81704c3f21021ea95ae4134f08b75e1542cda3ba7eb03d4f72c501fcb1bcc00a"
        + "998580c92b3eb7186bf11ff1f2910a524e126fe5e0e7810a245f021b3ef5a46f"
    static let privateKeyB =
        "b16e5ffd17018bce6afcbc03c2c8c617a3436de1f0f4d5052b3a8fa7c7850460"
        + "715627c95cd7222c95e38ab464e0606e0a2ef578d123af123014f74dfc6ba0e2"
    static let publicKeyA =
        "ckpub1:fVntxqkaxIr0CmIZRdL01DK0sMzDpAnXftE9HqmQiWbsmOpXeFBjdjTH_wWUhMO_LXfxblAJL-QvZK06itB6ew"
    static let publicKeyB =
        "ckpub1:NJOEnWGGyDoHykLBDlCD7URnjVE9tZbVWjeCYzUz_2Kcw55wrHm0NeQ2cCen_kX3viIwGRPwDfhpeV2HiOQq0g"
    /// От A для B (и для самого A). Две записи получателей, текст 62 байта дополнен до 64.
    /// Перегенерирован один раз в раунде 3 (обязательство на ключ, дополнение) — формат ещё не был у пользователей.
    static let message =
        "ckmsg1:AQIAQH1Z7capGsSK9ApiGUXS9NQytLDMw6QJ137RPR6pkIlm7JjqV3hQY3Y0x_8FlITDvy138W5QCS_kL2StOorQens6pe1yQ"
        + "IuORYZbz4yOVyP6FqEHARfT4YTlBh5445bhHIWkZjliw0AY0H6QkeTKxp9ewdWQACO0z5po91a5kYfk4tqSMSM0vuwduki3UhWxn-lhS"
        + "0KW-vfhdGAQEowFMhH8DGebdxXIomCCr_qn31S8lLc6nri0UmxpM-GO-ymy4FhUq8Zvt3zbUa7WyG7dhZ9Yhnf4suX0erGrT5A_qkp_O"
        + "KDU0VHA-xN_pS4Yx3lrwB8-A0_uY25wWyPKdEmQyCYXLUprepY4fsSRmoipXkxcg1t4qgYcjiSCavSgKEAY8-yXxavU_7YzG3t3S3q9E"
        + "nGR7QNeK-06Tft0cIcGz-aipRBfTgEocVhAB_3-wDczvXDVhNXscSYI4pJRSRc3IBnO7uAUrtyhNk-mD_YCX1FCeHMWcbF7JZIgzGdum"
        + "QE"
    static let text = "Золотой вектор CipherKeyboard 🔐\nстрока 2"
}

@Suite("Золотой вектор ckmsg1")
struct GoldenVectorTests {
    private func identity(_ hex: String) throws -> Identity {
        try Identity(privateKeyData: Data(try #require(bytes(hex: hex))))
    }

    @Test("Литералы ключей A и B соответствуют приватным данным")
    func keysMatchLiterals() throws {
        #expect(try identity(GoldenVector.privateKeyA).publicKey.string == GoldenVector.publicKeyA)
        #expect(try identity(GoldenVector.privateKeyB).publicKey.string == GoldenVector.publicKeyB)
    }

    @Test("B открывает вектор: тот же текст байт в байт, отправитель — контакт «A»")
    func openedByRecipient() throws {
        let a = try identity(GoldenVector.privateKeyA)
        let b = try identity(GoldenVector.privateKeyB)
        let contactA = Contact(name: "A", publicKey: a.publicKey)
        let opened = try CipherMessage.open(GoldenVector.message, as: b, contacts: [contactA])
        #expect(Array(opened.text.utf8) == Array(GoldenVector.text.utf8))
        #expect(opened.sender == .contact(contactA))
        guard case .contact(let contact) = opened.sender else {
            Issue.record("ожидался .contact, получено \(opened.sender)")
            return
        }
        #expect(contact.name == "A")
        #expect(opened.senderKey == a.publicKey)
    }

    @Test("A открывает свой вектор: тот же текст, отправитель — me")
    func openedBySender() throws {
        let a = try identity(GoldenVector.privateKeyA)
        let opened = try CipherMessage.open(GoldenVector.message, as: a, contacts: [])
        #expect(Array(opened.text.utf8) == Array(GoldenVector.text.utf8))
        #expect(opened.sender == .me)
    }

    @Test("Вектор с одним изменённым символом в середине не открывается")
    func changedCharacterFails() throws {
        let b = try identity(GoldenVector.privateKeyB)
        let middle = GoldenVector.message.count / 2
        let original = Array(GoldenVector.message)[middle]
        let replacement = try #require(nextBase64urlCharacter(after: original))
        let changed = replacingCharacter(in: GoldenVector.message, at: middle, with: replacement)
        #expect(changed != GoldenVector.message)
        #expect(throws: (any Error).self) { _ = try CipherMessage.open(changed, as: b, contacts: []) }
    }
}
