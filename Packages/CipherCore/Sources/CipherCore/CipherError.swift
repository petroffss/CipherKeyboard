/// Ошибки крипто-ядра. Каждая ошибка — точная причина, по которой приложение и клавиатура показывают понятный текст.
public enum CipherError: Error, Equatable, Sendable {
    /// Ключ не разобран: неверная длина, чужой префикс, текст вокруг, неканонический base64, слабая точка X25519.
    case invalidKey
    /// Префикс `ckpub<N>:` / `ckmsg<N>:` с версией, которую эта сборка не знает.
    case unsupportedVersion
    /// В тексте нет `ckmsg<цифры>:`.
    case noMessage
    /// Сообщение обрезано, не base64url, неканонично или с невозможным заголовком.
    case malformed
    /// Подпись или шифрование не сходятся: сообщение изменено или подделано.
    case tampered
    /// Сообщение подлинное, но не зашифровано для этой личности.
    case notARecipient
    /// Пустой текст нельзя зашифровать.
    case emptyMessage
    /// Текст длиннее `CipherMessage.maxPlaintextBytes` байт UTF-8.
    case messageTooLong(byteCount: Int)
    /// Список получателей пуст.
    case noRecipients
    /// Различных получателей вместе с отправителем больше `CipherMessage.maxRecipients`.
    case tooManyRecipients
}
