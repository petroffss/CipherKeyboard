import CipherCore
import SwiftUI

@main
struct CipherKeyboardApp: App {
    @State private var model = MyKeyModel(store: LaunchStorage.identityStore())

    var body: some Scene {
        WindowGroup {
            #if DEBUG
                if ProcessInfo.processInfo.arguments.contains("-encrypt-self-open") {
                    Text(
                        KeyboardEncryptProbe.openInserted(
                            ProcessInfo.processInfo.environment["CIPHER_INSERTED_SYNTHETIC_CIPHERTEXT"] ?? "")
                    ).accessibilityIdentifier("encrypt.selfOpenResult")
                } else if ProcessInfo.processInfo.arguments.contains("-encrypt-probe") {
                    EncryptProbeView()
                } else if ProcessInfo.processInfo.arguments.contains("-encrypt-seed") {
                    Text(EncryptSetupProbe.run()).accessibilityIdentifier("encrypt.seedResult").accessibilityValue(
                        EncryptSetupProbe.publicKey)
                } else if ProcessInfo.processInfo.arguments.contains("-typing-isolation") {
                    Text(KeyboardIsolationProbe.run()).accessibilityIdentifier("typing.isolationResult")
                } else if ProcessInfo.processInfo.arguments.contains("-typing-identity-metadata") {
                    Text(KeyboardIdentityMetadataProbe.run()).accessibilityIdentifier("typing.identityMetadata")
                } else {
                    RootView(model: model).task { model.loadIfNeeded() }
                }
            #else
                RootView(model: model).task { model.loadIfNeeded() }
            #endif
        }
    }
}

#if DEBUG
    private struct EncryptProbeView: View {
        @State private var result = "Проверяем…"
        var body: some View {
            Text(result).accessibilityIdentifier("encrypt.probeResult").task {
                result = await KeyboardEncryptProbe.run()
            }
        }
    }
#endif
