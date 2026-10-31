import CipherCore
import CipherCoreIdentityStore
import Foundation

#if DEBUG
    import Security
#endif

/// Какое хранилище личности использует приложение. В Release — всегда общий Keychain.
enum LaunchStorage {
    static func identityStore() -> IdentityStore {
        #if DEBUG
            // Только для UI-тестов (AC17): хранилище в памяти, пустое при каждом запуске; настоящий Keychain не трогается.
            let arguments = ProcessInfo.processInfo.arguments
            func value(after flag: String) -> String? {
                guard let index = arguments.firstIndex(of: flag), index + 1 < arguments.count else { return nil }
                return arguments[index + 1]
            }
            if value(after: "-keystore") == "memory" {
                let faults: [OSStatus] = value(after: "-keystore-fault") == "read" ? [errSecInteractionNotAllowed] : []
                let delay = value(after: "-keystore-delay").flatMap(TimeInterval.init) ?? 0
                return IdentityStore(storage: InMemorySecretStorage(failingReads: faults, addDelay: delay))
            }
        #endif
        return .keychain
    }
}
