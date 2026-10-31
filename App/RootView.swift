import SwiftUI

/// Корень приложения: создание ключа → вкладки, или экран ошибки хранилища. Таб-бар — только когда ключ готов.
struct RootView: View {
    let model: MyKeyModel

    var body: some View {
        switch model.state {
        case .loading:
            LoadingView()
        case .failed:
            StorageErrorView(retry: model.retry)
        case .ready(let info):
            MainTabs(info: info)
        }
    }
}

enum AppTab: Hashable {
    case myKey, contacts, decrypt, setup
}

struct MainTabs: View {
    let info: MyKeyInfo
    @State private var selection: AppTab = .myKey

    var body: some View {
        TabView(selection: $selection) {
            MyKeyView(info: info)
                .tabItem { tabLabel("Мой ключ", systemImage: "key", id: "tab.myKey") }
                .tag(AppTab.myKey)
            PlaceholderTabView(title: "Контакты")
                .tabItem { tabLabel("Контакты", systemImage: "person.2", id: "tab.contacts") }
                .tag(AppTab.contacts)
            PlaceholderTabView(title: "Расшифровать")
                .tabItem { tabLabel("Расшифровать", systemImage: "lock.open", id: "tab.decrypt") }
                .tag(AppTab.decrypt)
            PlaceholderTabView(title: "Настройка")
                .tabItem { tabLabel("Настройка", systemImage: "gearshape", id: "tab.setup") }
                .tag(AppTab.setup)
        }
    }

    private func tabLabel(_ title: String, systemImage: String, id: String) -> some View {
        Label(title, systemImage: systemImage)
            .accessibilityIdentifier(id)
    }
}

/// Вкладки, которые появятся в следующих фичах.
struct PlaceholderTabView: View {
    let title: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.largeTitle.bold())
            Text("Появится в следующей версии")
                .font(.body)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemGroupedBackground))
    }
}

struct LoadingView: View {
    var body: some View {
        VStack(spacing: 16) {
            ProgressView()
                .controlSize(.large)
            Text("Создаём ваш ключ…")
                .font(.body)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("mykey.loading")
        .padding(.horizontal, 32)
        .padding(.bottom, 80)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
    }
}

struct StorageErrorView: View {
    let retry: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 0) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 52))
                    .foregroundStyle(.red)
                    .accessibilityHidden(true)
                Text("Не удалось открыть хранилище ключей")
                    .font(.title2.weight(.semibold))
                    .padding(.top, 14)
                Text("Разблокируйте iPhone и попробуйте ещё раз. Ваш ключ не удалён.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.top, 8)
            }
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("mykey.error")
            Button("Повторить", action: retry)
                .buttonStyle(PrimaryButtonStyle(fullWidth: false))
                .accessibilityIdentifier("mykey.retry")
                .padding(.top, 12)
        }
        .padding(.horizontal, 32)
        .padding(.bottom, 80)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
    }
}

/// Основная кнопка: залита акцентом, белый текст 17 semibold, высота 50.
struct PrimaryButtonStyle: ButtonStyle {
    var fullWidth = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, fullWidth ? 16 : 36)
            .frame(maxWidth: fullWidth ? .infinity : nil, minHeight: 50)
            .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 14))
            .opacity(configuration.isPressed ? 0.8 : 1)
            .contentShape(RoundedRectangle(cornerRadius: 14))
    }
}

/// Вторичная кнопка: контур 1,5 pt акцентом, текст акцентом, высота 50.
struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .foregroundStyle(Color.accentColor)
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, minHeight: 50)
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.accentColor, lineWidth: 1.5))
            .opacity(configuration.isPressed ? 0.6 : 1)
            .contentShape(RoundedRectangle(cornerRadius: 14))
    }
}
