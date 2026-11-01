import CipherCore
import SwiftUI

struct SetupView: View {
    let model: SetupModel
    @State private var showsSteps = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Настройка")
                    .font(.largeTitle.bold())
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("setup.title")
                status
                if model.confirmed {
                    Button(showsSteps ? "Скрыть шаги" : "Показать шаги") { showsSteps.toggle() }
                        .buttonStyle(SecondaryButtonStyle())
                        .accessibilityIdentifier("setup.showSteps")
                }
                if !model.confirmed || showsSteps {
                    steps
                    Button("Открыть Настройки") { Task { await model.openSettings() } }
                        .buttonStyle(PrimaryButtonStyle())
                        .accessibilityIdentifier("setup.openSettings")
                }
                explanation
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
            .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityIdentifier("setup.scroll")
        .background(Color(.systemGroupedBackground))
    }

    private var status: some View {
        VStack(alignment: .leading, spacing: 8) {
            if model.settingsFailed {
                Text("Не удалось открыть Настройки")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.red)
                    .accessibilityIdentifier("setup.settingsError")
                Text("Настройки → Основные → Клавиатура → Клавиатуры")
                    .font(.subheadline)
            } else {
                switch model.state {
                case .absent:
                    Text("Подключите клавиатуру").font(.title2.weight(.semibold))
                    Text("Добавьте CipherKeyboard в настройках iPhone.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                case .needsOpening:
                    Text("Откройте клавиатуру").font(.title2.weight(.semibold))
                    Text("Включите «Полный доступ» и откройте клавиатуру в любом приложении")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                case .unknown:
                    Text("Не удалось проверить подключение").font(.title2.weight(.semibold))
                    Text("Проверьте настройки и откройте клавиатуру в любом приложении.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                case .confirmed:
                    Label("Подключение проверено", systemImage: "checkmark.circle.fill")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(.green)
                    Text(
                        "Полный доступ был включён при последнем открытии клавиатуры. Если вы меняли настройки, откройте клавиатуру снова"
                    )
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("setup.historicalNote")
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
        .accessibilityIdentifier("setup.status")
    }

    private var steps: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("1. Откройте Настройки → CipherKeyboard → Клавиатуры")
            Text("2. Включите CipherKeyboard")
            Text("3. Включите «Полный доступ»")
        }
        .accessibilityIdentifier("setup.steps")
    }

    private var explanation: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Зачем полный доступ").font(.title2.weight(.semibold))
            Text("Клавиатуре нужны ваши ключи и контакты из приложения и доступ к скопированному шифротексту.")
            Text("CipherKeyboard не подключается к интернету и ничего никуда не отправляет.")
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }
}
