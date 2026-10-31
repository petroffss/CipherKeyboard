import CipherCore
import Foundation

// Вспомогательные функции тестов. base64 здесь — через Foundation, независимо от кодировщика ядра.

/// Байты из hex-строки; `nil` при нечётной длине или не-hex символе.
func bytes(hex: String) -> [UInt8]? {
    let chars = Array(hex.utf8)
    guard chars.count % 2 == 0 else { return nil }
    var result: [UInt8] = []
    var index = 0
    while index < chars.count {
        guard let byte = UInt8(String(decoding: chars[index..<index + 2], as: UTF8.self), radix: 16) else {
            return nil
        }
        result.append(byte)
        index += 2
    }
    return result
}

func hex(_ bytes: [UInt8], uppercase: Bool = false) -> String {
    bytes.map { String(format: uppercase ? "%02X" : "%02x", $0) }.joined()
}

/// Стандартный base64 (с `+`, `/`) без паддинга — через Foundation.
func base64(_ bytes: [UInt8]) -> String {
    Data(bytes).base64EncodedString().replacingOccurrences(of: "=", with: "")
}

/// base64url без паддинга — через Foundation.
func base64url(_ bytes: [UInt8]) -> String {
    base64(bytes).replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
}

/// Разбор base64url (с паддингом или без) — через Foundation.
func decodeBase64url(_ text: Substring) -> [UInt8]? {
    var standard = text.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
    standard += String(repeating: "=", count: (4 - standard.count % 4) % 4)
    return Data(base64Encoded: standard).map { Array($0) }
}

/// Тело сообщения `ckmsg1:…` в байтах.
func decodedMessage(_ message: String) -> [UInt8]? {
    guard message.hasPrefix("ckmsg1:") else { return nil }
    return decodeBase64url(message.dropFirst(7))
}

/// 64 байта открытого ключа из его строки `ckpub1:…`.
func rawKey(_ key: PublicKey) -> [UInt8]? {
    decodeBase64url(key.string.dropFirst(7))
}

/// Есть ли `needle` в `haystack` как непрерывный кусок.
func contains(_ haystack: [UInt8], _ needle: [UInt8]) -> Bool {
    guard !needle.isEmpty, needle.count <= haystack.count else { return needle.isEmpty }
    for start in 0...(haystack.count - needle.count) where haystack[start] == needle[0] {
        if Array(haystack[start..<start + needle.count]) == needle { return true }
    }
    return false
}

/// Алфавит base64url в порядке `A–Z a–z 0–9 - _`.
let base64urlAlphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_")

/// Следующий символ base64url по кругу.
func nextBase64urlCharacter(after character: Character) -> Character? {
    guard let index = base64urlAlphabet.firstIndex(of: character) else { return nil }
    return base64urlAlphabet[(index + 1) % base64urlAlphabet.count]
}

/// Строка, в которой символ на позиции `offset` заменён.
func replacingCharacter(in text: String, at offset: Int, with character: Character) -> String {
    var chars = Array(text)
    chars[offset] = character
    return String(chars)
}
