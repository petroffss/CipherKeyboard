import CipherCore
import Foundation

/// Offline proof for synthetic results exported from the actual installed extension's host.
/// This executable is not a dependency of either shipping target.
struct Record: Decodable {
    let ciphertext: String
    let expectedText: String
    let senderPublicKey: String
}
struct ProofFailure: Error {}
let records = try JSONDecoder().decode(
    [Record].self, from: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1])))
guard !records.isEmpty else { throw ProofFailure() }
let recipient = try Identity(privateKeyData: Data(repeating: 22, count: 64))
let third = try Identity(privateKeyData: Data(repeating: 77, count: 64))
for record in records {
    let trustedSender = try PublicKey(string: record.senderPublicKey)
    let contact = Contact(id: UUID(), name: "Синтетический отправитель", publicKey: trustedSender)
    let opened = try CipherMessage.open(record.ciphertext, as: recipient, contacts: [contact])
    guard Array(opened.text.utf8) == Array(record.expectedText.utf8), opened.senderKey == trustedSender,
        opened.sender == .contact(contact)
    else { throw ProofFailure() }
    let unknown = try CipherMessage.open(record.ciphertext, as: recipient, contacts: [])
    guard unknown.sender == .unknown(trustedSender.fingerprint) else { throw ProofFailure() }
    do {
        _ = try CipherMessage.open(record.ciphertext, as: third, contacts: []); throw ProofFailure()
    } catch CipherError.notARecipient {}
}
print(
    "PASS: \(records.count) actual inserted ciphertexts; exact UTF-8; full sender key; known/unknown sender; third rejected"
)
