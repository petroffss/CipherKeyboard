#if DEBUG
    import CipherCore
    import Foundation

    /// Debug-only dependency used with the production stores, access gate and document proxy.
    @MainActor final class KeyboardEncryptFaults {
        var delay: TimeInterval = 0
        var fails = false
        func seal(_ text: String, sender: Identity, recipient: PublicKey) async throws -> String {
            let pause = delay, failure = fails
            if pause > 0 { try await Task.sleep(for: .seconds(pause)) }
            if failure { throw CipherError.tampered }
            return try await Task.detached { try CipherMessage.seal(text, from: sender, to: [recipient]) }.value
        }
    }
#endif
