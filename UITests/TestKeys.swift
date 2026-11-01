import Foundation

/// Заранее сгенерированные открытые ключи чужих личностей для UI-тестов контактов (фича 03).
/// Приватные половины выброшены: ключи нужны только как валидные строки `ckpub1:…` с известным отпечатком.
/// Отпечатки посчитаны независимо от приложения: SHA-256 от 64 байт ключа, первые 16 байт, HEX группами по 4.
enum TestKeys {
    struct Key {
        let publicKey: String
        let fingerprint: String

        /// Первые две группы отпечатка — как в строке списка контактов.
        var shortFingerprint: String { String(fingerprint.prefix(9)) }
        /// Тело ключа без префикса `ckpub1:`.
        var body: String { String(publicKey.dropFirst("ckpub1:".count)) }
    }

    static let k1 = Key(
        publicKey: "ckpub1:1CaIBDyUoMgA0wGm7yx2wOqF6PRpx_an0WZ_5r1rECDf2fp554ik8b_jWJP4kr-KXhUkMgqiQ8OvHZUQFNww_w",
        fingerprint: "8C86 0ABA C3B4 4445 583F 564B 56D4 163E")

    static let k2 = Key(
        publicKey: "ckpub1:an09GOAKRMMcgpTDlr_QcBbkWM83KY3qvS9k5p9awQ_-skUXURM-k0OV9eownA7Mi98U8Zq45HUFR_wpnSgADA",
        fingerprint: "3ACE 2038 934B 38C9 D0EB 8078 951A 8AB6")

    static let k3 = Key(
        publicKey: "ckpub1:bG7rJXss0Vh6R2Q8Lh2Zm0csIp6bjgbmTopB6JP9gmzwnQHTwLW5mMh8hWukjebIK31-k2d4Bi5V5cmBFRLESA",
        fingerprint: "2C48 1499 9838 CD61 B084 ADD4 AE48 D763")
}
