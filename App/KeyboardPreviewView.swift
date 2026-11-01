import CipherCore
import KeyboardTyping
import SwiftUI

struct KeyboardPreviewView: View {
    @State private var adapter = KeyboardInputAdapter()
    @State private var height: CGFloat = 320
    @Environment(\.scenePhase) private var scenePhase
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Набирайте текст внутри клавиатуры. При выходе черновик будет стёрт")
                .font(.subheadline).foregroundStyle(.secondary).padding(.horizontal, 20)
            Spacer(minLength: 0)
            Text("Поле приложения").font(.footnote).foregroundStyle(.secondary).padding(.horizontal, 20)
            Text("До встречи!")
                .frame(maxWidth: .infinity, alignment: .leading).padding(12)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
                .padding(.horizontal, 14).accessibilityIdentifier("preview.host")
            KeyboardPreviewPanel(adapter: adapter, height: $height)
                .frame(height: height)
        }
        .padding(.top, 8)
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Попробовать клавиатуру")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear { adapter.hide() }
        .onChange(of: scenePhase) { _, phase in if phase != .active { adapter.hide() } }
    }
}

private struct KeyboardPreviewPanel: UIViewRepresentable {
    let adapter: KeyboardInputAdapter
    @Binding var height: CGFloat
    func makeUIView(context: Context) -> KeyboardPanel {
        let panel = KeyboardPanel(adapter: adapter)
        let status = KeyboardSharedStatus.read(hasFullAccess: true)
        panel.statusText = status.identity
        panel.contactsText = status.contacts
        #if DEBUG
            if let fixture = ProcessInfo.processInfo.environment["CIPHER_TYPING_FIXTURE"] {
                KeyboardDebugFixture.apply(to: panel, name: fixture)
            }
        #endif
        panel.heightChanged = { value in
            // UIKit layout callbacks must not synchronously mutate SwiftUI's current update.
            DispatchQueue.main.async { height = value }
        }
        return panel
    }
    func updateUIView(_ uiView: KeyboardPanel, context: Context) {}
    static func dismantleUIView(_ uiView: KeyboardPanel, coordinator: ()) { uiView.clearSession() }
}
