import CryptoKit
import Foundation

/// Своя личность: приватные X25519 и Ed25519. Не `Codable` — приватная часть отдаётся только `privateKeyData()`.
/// В описаниях и `dump` видно только `Identity(<отпечаток>)`.
public struct Identity: Sendable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    /// 32 байта приватного X25519 + 32 байта приватного Ed25519.
    private let secret: [UInt8]
    public let publicKey: PublicKey

    /// Новая случайная личность. `package`: создаётся только через `IdentityStore` (или в тестах ядра).
    package static func generate() -> Identity {
        let agreement = Curve25519.KeyAgreement.PrivateKey()
        let signing = Curve25519.Signing.PrivateKey()
        return Identity(agreement: agreement, signing: signing)
    }

    /// Восстанавливает личность из 64 байт `privateKeyData()`. Другая длина → `CipherError.invalidKey`.
    public init(privateKeyData: Data) throws {
        guard privateKeyData.count == 64 else { throw CipherError.invalidKey }
        let bytes = Array(privateKeyData)
        do {
            let agreement = try Curve25519.KeyAgreement.PrivateKey(rawRepresentation: bytes[0..<32])
            let signing = try Curve25519.Signing.PrivateKey(rawRepresentation: bytes[32..<64])
            self.init(agreement: agreement, signing: signing)
        } catch {
            throw CipherError.invalidKey
        }
    }

    private init(agreement: Curve25519.KeyAgreement.PrivateKey, signing: Curve25519.Signing.PrivateKey) {
        secret = Array(agreement.rawRepresentation) + Array(signing.rawRepresentation)
        publicKey = PublicKey(
            trustedRaw: Array(agreement.publicKey.rawRepresentation) + Array(signing.publicKey.rawRepresentation))
    }

    /// 64 байта: приватный X25519 (32) + приватный Ed25519 (32). Только для хранения в Keychain.
    /// `package`: приложению и клавиатуре приватные байты недоступны — их пишет в Keychain только `IdentityStore`.
    package func privateKeyData() -> Data {
        Data(secret)
    }

    func agreementKey() throws -> Curve25519.KeyAgreement.PrivateKey {
        try Curve25519.KeyAgreement.PrivateKey(rawRepresentation: secret[0..<32])
    }

    func signingKey() throws -> Curve25519.Signing.PrivateKey {
        try Curve25519.Signing.PrivateKey(rawRepresentation: secret[32..<64])
    }

    public var description: String { "Identity(\(publicKey.fingerprint.description))" }
    public var debugDescription: String { description }
    public var customMirror: Mirror {
        Mirror(self, children: EmptyCollection<Mirror.Child>(), displayStyle: .struct)
    }
}

/// Контакт: имя и открытый ключ собеседника. Ключ решает, кто прочитает сообщение.
public struct Contact: Hashable, Sendable, Codable, Identifiable {
    public var id: UUID
    public var name: String
    public var publicKey: PublicKey

    public init(id: UUID = UUID(), name: String, publicKey: PublicKey) {
        self.id = id
        self.name = name
        self.publicKey = publicKey
    }
}
