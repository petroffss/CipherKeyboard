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
    /// От A для B (и для самого A). Две записи получателей.
    static let message =
        "ckmsg1:AQIAPn1Z7capGsSK9ApiGUXS9NQytLDMw6QJ137RPR6pkIlm7JjqV3hQY3Y0x_8FlITDvy138W5QCS_kL2StOorQentL4q91"
        + "BpRbj87cB1McKK_Z0OjjsfQxMzJXz93e9xhNIpvEfZ7R-2ZHwJVR0OYKL3Cp6ICiSTobBo33la9AGE9Wrp0zSMp2WNK0HZKIs3YXFDsq"
        + "o0C9bu4O-cvMxVI_OCOlWFM58RA0KCYk4mmkD3tnXX4nRw7JNUTJqg4GS-YOIjSapCUqVztbBgK1Go6c2iaUPQ0uSL50SGZ6fzNFo-sa"
        + "xvnDdsGh_WQAbXsS3S_hPRngMvXaFVEMyIGzT8cBjH8qe_qgVH70LaK_Zbwav1FqgpHx-pyL7zAMvETlB0RnwY7K_kLbQZr2gk50HVMa"
        + "2G_qM6oU36iUSMPKAlt6dfDYaSj708Ah1CnCcfX53UyD9h-jKrb7CjoTxAY"
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
