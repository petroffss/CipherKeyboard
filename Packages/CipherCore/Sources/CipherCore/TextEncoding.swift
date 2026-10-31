import Foundation

/// base64url (RFC 4648 §5) без паддинга, строгий разбор: только канонические строки.
enum Base64URL {
    private static let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_".utf8)

    /// Значение символа алфавита base64url или `nil`, если символ не из алфавита.
    static func value(of byte: UInt8) -> UInt8? {
        switch byte {
        case UInt8(ascii: "A")...UInt8(ascii: "Z"): return byte - UInt8(ascii: "A")
        case UInt8(ascii: "a")...UInt8(ascii: "z"): return byte - UInt8(ascii: "a") + 26
        case UInt8(ascii: "0")...UInt8(ascii: "9"): return byte - UInt8(ascii: "0") + 52
        case UInt8(ascii: "-"): return 62
        case UInt8(ascii: "_"): return 63
        default: return nil
        }
    }

    /// Число символов base64url без паддинга для `byteCount` байт.
    static func encodedLength(byteCount: Int) -> Int {
        (byteCount * 4 + 2) / 3
    }

    static func encode<Bytes: Collection>(_ bytes: Bytes) -> String where Bytes.Element == UInt8 {
        let input = Array(bytes)
        var output: [UInt8] = []
        output.reserveCapacity(encodedLength(byteCount: input.count))
        var index = 0
        while index < input.count {
            let remaining = input.count - index
            let b0 = UInt32(input[index])
            let b1 = remaining > 1 ? UInt32(input[index + 1]) : 0
            let b2 = remaining > 2 ? UInt32(input[index + 2]) : 0
            let group = (b0 << 16) | (b1 << 8) | b2
            output.append(alphabet[Int((group >> 18) & 0x3F)])
            output.append(alphabet[Int((group >> 12) & 0x3F)])
            if remaining > 1 { output.append(alphabet[Int((group >> 6) & 0x3F)]) }
            if remaining > 2 { output.append(alphabet[Int(group & 0x3F)]) }
            index += 3
        }
        return String(decoding: output, as: UTF8.self)
    }

    /// Строгий разбор base64url без паддинга. `nil`, если есть символ не из алфавита, длина невозможна
    /// (`count % 4 == 1`) или неиспользуемые биты последнего символа не нулевые (неканоническая запись).
    static func decode<Chars: Collection>(_ chars: Chars) -> [UInt8]? where Chars.Element == UInt8 {
        let input = Array(chars)
        if input.count % 4 == 1 { return nil }
        var output: [UInt8] = []
        output.reserveCapacity(input.count * 3 / 4)
        var index = 0
        while index < input.count {
            let chunk = min(4, input.count - index)
            var group: UInt32 = 0
            for offset in 0..<4 {
                var sextet: UInt8 = 0
                if offset < chunk {
                    guard let value = value(of: input[index + offset]) else { return nil }
                    sextet = value
                }
                group = (group << 6) | UInt32(sextet)
            }
            let b0 = UInt8((group >> 16) & 0xFF)
            let b1 = UInt8((group >> 8) & 0xFF)
            let b2 = UInt8(group & 0xFF)
            switch chunk {
            case 4:
                output.append(contentsOf: [b0, b1, b2])
            case 3:
                guard b2 == 0 else { return nil }
                output.append(contentsOf: [b0, b1])
            default:  // 2
                guard b1 == 0, b2 == 0 else { return nil }
                output.append(b0)
            }
            index += 4
        }
        return output
    }
}

/// Подготовка вставленного текста к разбору.
enum CompactText {
    /// Байт-заменитель для любого не-ASCII символа: не входит ни в префиксы, ни в алфавит base64url.
    static let placeholder: UInt8 = 0

    /// Удаляет все символы `CharacterSet.whitespacesAndNewlines` в любом месте строки. ASCII-символы
    /// остаются как есть, любой другой символ заменяется одним байтом `placeholder` — он разрывает
    /// префикс и base64url так же, как исходный символ.
    static func bytes(_ text: String) -> [UInt8] {
        var output: [UInt8] = []
        output.reserveCapacity(text.utf8.count)
        for scalar in text.unicodeScalars {
            let value = scalar.value
            if value < 0x80 {
                switch value {
                case 0x09...0x0D, 0x20: continue
                default: output.append(UInt8(value))
                }
            } else if CharacterSet.whitespacesAndNewlines.contains(scalar) {
                continue
            } else {
                output.append(placeholder)
            }
        }
        return output
    }

    /// Начинается ли `bytes` с `prefix` начиная с позиции `start`.
    static func hasPrefix(_ bytes: [UInt8], _ prefix: [UInt8], at start: Int) -> Bool {
        guard start >= 0, start + prefix.count <= bytes.count else { return false }
        for (offset, byte) in prefix.enumerated() where bytes[start + offset] != byte {
            return false
        }
        return true
    }

    /// Разбор `<имя><цифры>:` с позиции `start`. Возвращает цифры версии и позицию сразу после двоеточия.
    static func versionedPrefix(_ bytes: [UInt8], name: [UInt8], at start: Int) -> (version: [UInt8], bodyStart: Int)? {
        guard hasPrefix(bytes, name, at: start) else { return nil }
        var index = start + name.count
        let digitsStart = index
        while index < bytes.count, (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(bytes[index]) {
            index += 1
        }
        guard index > digitsStart, index < bytes.count, bytes[index] == UInt8(ascii: ":") else { return nil }
        return (Array(bytes[digitsStart..<index]), index + 1)
    }
}
