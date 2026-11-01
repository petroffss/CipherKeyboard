import CipherCore
import SwiftUI

@main
struct CipherKeyboardApp: App {
    @State private var model = MyKeyModel(store: LaunchStorage.identityStore())

    var body: some Scene {
        WindowGroup {
            RootView(model: model)
                .task { model.loadIfNeeded() }
        }
    }
}
