import CipherCore
import SwiftUI

/// Стартовый экран каркаса. Вкладки «Мой ключ», «Контакты», «Расшифровать», «Настройка» появятся с фичами 02–07.
struct ContentView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "lock.shield")
                .font(.system(size: 56))
                .foregroundStyle(.tint)
            Text(CipherCore.productName)
                .font(.largeTitle.bold())
                .accessibilityIdentifier("app.title")
            Text("Клавиатура, которая шифрует сообщения")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }
}

#Preview {
    ContentView()
}
