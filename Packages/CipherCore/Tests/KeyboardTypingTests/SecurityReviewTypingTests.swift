import CipherCore
import Foundation
import Testing
import KeyboardTyping

@Suite("Security review typing regressions") @MainActor
struct SecurityReviewTypingTests {
    @Test func unknownSenderUsesFullFingerprintByDefault() async throws {
        let sender = Identity.generate(), recipient = Identity.generate()
        let sealed = try CipherMessage.seal("Проверка", from: sender, to: [recipient.publicKey])
        let model = DecryptCoordinator(
            surface: .app, access: { true }, identity: { .identity(recipient) }, contacts: { .contacts([]) })
        model.activate()
        #expect(model.setInput(sealed))
        model.start()
        for _ in 0..<2000 {
            if !model.busy { break }
            try await Task.sleep(for: .milliseconds(1))
        }
        #expect(model.result?.sender == "От неизвестного ключа " + sender.publicKey.fingerprint.description)
        #expect(model.result?.unknown == true)
    }

    @Test func counterAppearsBeforeSingleMessageBoundary() {
        var input = KeyboardInput()
        let initial = input.insert(String(repeating: "я", count: 999))
        #expect(initial)
        #expect(input.counter == nil)
        let next = input.insert("я")
        #expect(next)
        #expect(input.counter == "2000 / 4096 байт")
    }
}
