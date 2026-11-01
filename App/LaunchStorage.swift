import CipherCore
import CipherCoreContactStore
import CipherCoreIdentityStore
import Foundation

#if DEBUG
    import Security
#endif

/// Какое хранилище личности и контактов использует приложение. В Release — всегда общий Keychain и файл в группе.
enum LaunchStorage {
    static func identityStore() -> IdentityStore {
        #if DEBUG
            // Только для UI-тестов (AC17): хранилище в памяти, пустое при каждом запуске; настоящий Keychain не трогается.
            if argument(after: "-keystore") == "memory" {
                let faults: [OSStatus] =
                    argument(after: "-keystore-fault") == "read" ? [errSecInteractionNotAllowed] : []
                let delay = argument(after: "-keystore-delay").flatMap(TimeInterval.init) ?? 0
                return IdentityStore(storage: InMemorySecretStorage(failingReads: faults, addDelay: delay))
            }
        #endif
        return .keychain
    }

    static func contactStore() -> ContactStore {
        #if DEBUG
            // Только для UI-тестов (03 AC20): хранилище контактов в памяти, настоящий файл не трогается.
            let seed = argument(after: "-contacts-seed").flatMap(Int.init)
            let fault = argument(after: "-contacts-fault") == "read"
            if argument(after: "-contacts") == "memory" || seed != nil || fault {
                let storage = seed.map { InMemoryContactStorage.seeded(count: $0) } ?? InMemoryContactStorage()
                if fault { return ContactStore(storage: InMemoryContactStorage(data: storage.data, failingReads: 1)) }
                return ContactStore(storage: storage)
            }
        #endif
        return .appGroup
    }

    /// Строка, которую сканер отдаёт вместо камеры (03 AC20, `-contacts-scan`). В Release всегда `nil`.
    static var scannerOverride: String? {
        #if DEBUG
            return argument(after: "-contacts-scan")
        #else
            return nil
        #endif
    }

    #if DEBUG
        private static func argument(after flag: String) -> String? {
            let arguments = ProcessInfo.processInfo.arguments
            guard let index = arguments.firstIndex(of: flag), index + 1 < arguments.count else { return nil }
            return arguments[index + 1]
        }
    #endif
}
