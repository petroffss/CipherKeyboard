import CryptoKit
import Foundation

/// Своя личность: приватные X25519 и Ed25519. Не `Codable` — приватная часть отдаётся только `privateKeyData()`.
/// В описаниях и `dump` видно только `Identity(<отпечаток>)`.
public struct Identity: Sendable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    private let agreement: Curve25519.KeyAgreement.PrivateKey
    private let signing: Curve25519.Signing.PrivateKey
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
        do {
            let agreement = try Curve25519.KeyAgreement.PrivateKey(rawRepresentation: privateKeyData.prefix(32))
            let signing = try Curve25519.Signing.PrivateKey(rawRepresentation: privateKeyData.suffix(32))
            self.init(agreement: agreement, signing: signing)
        } catch {
            throw CipherError.invalidKey
        }
    }

    private init(agreement: Curve25519.KeyAgreement.PrivateKey, signing: Curve25519.Signing.PrivateKey) {
        self.agreement = agreement
        self.signing = signing
        publicKey = PublicKey(
            trustedRaw: Array(agreement.publicKey.rawRepresentation) + Array(signing.publicKey.rawRepresentation))
    }

    /// 64 байта: приватный X25519 (32) + приватный Ed25519 (32). Только для хранения в Keychain.
    /// `package`: приложению и клавиатуре приватные байты недоступны — их пишет в Keychain только `IdentityStore`.
    package func privateKeyData() -> Data {
        agreement.rawRepresentation + signing.rawRepresentation
    }

    func agreementKey() -> Curve25519.KeyAgreement.PrivateKey { agreement }
    func signingKey() -> Curve25519.Signing.PrivateKey { signing }

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
