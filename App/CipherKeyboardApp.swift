import CipherCore
import SwiftUI

@main
struct CipherKeyboardApp: App {
    @State private var model = MyKeyModel(store: LaunchStorage.identityStore())

    var body: some Scene {
        WindowGroup {
            #if DEBUG
                if ProcessInfo.processInfo.arguments.contains("-typing-isolation") {
                    Text(KeyboardIsolationProbe.run()).accessibilityIdentifier("typing.isolationResult")
                } else {
                    RootView(model: model).task { model.loadIfNeeded() }
                }
            #else
                RootView(model: model).task { model.loadIfNeeded() }
            #endif
        }
    }
}
