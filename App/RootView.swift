import SwiftUI
import UIKit

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
    @State private var contacts: ContactsModel
    @State private var setup = SetupModel.live()
    @Environment(\.scenePhase) private var scenePhase

    init(info: MyKeyInfo) {
        self.info = info
        _contacts = State(initialValue: ContactsModel(store: LaunchStorage.contactStore(), ownKey: info.publicKey))
    }

    var body: some View {
        TabView(selection: $selection) {
            MyKeyView(info: info, setupNeeded: !setup.confirmed, openSetup: { selection = .setup })
                .background(TabBarIdentifiers(identifiers: Self.identifiers).allowsHitTesting(false))
                .tabItem { tabLabel("Мой ключ", systemImage: "key", id: "tab.myKey") }
                .tag(AppTab.myKey)
            ContactsView(model: contacts)
                .tabItem { tabLabel("Контакты", systemImage: "person.2", id: "tab.contacts") }
                .tag(AppTab.contacts)
            PlaceholderTabView(title: "Расшифровать")
                .tabItem { tabLabel("Расшифровать", systemImage: "lock.open", id: "tab.decrypt") }
                .tag(AppTab.decrypt)
            NavigationStack { SetupView(model: setup) }
                .tabItem { tabLabel("Настройка", systemImage: "gearshape", id: "tab.setup") }
                .tag(AppTab.setup)
        }
        .onChange(of: scenePhase, initial: true) { _, phase in
            if phase == .active { setup.refresh() }
        }
    }

    private static let identifiers = [
        "Мой ключ": "tab.myKey", "Контакты": "tab.contacts", "Расшифровать": "tab.decrypt", "Настройка": "tab.setup",
    ]

    private func tabLabel(_ title: String, systemImage: String, id: String) -> some View {
        Label(title, systemImage: systemImage)
            .accessibilityIdentifier(id)
    }
}

/// Идентификаторы кнопок таб-бара для UI-тестов. SwiftUI переносит `accessibilityIdentifier` из `.tabItem`
/// (и из `Tab`) на кнопки таб-бара не при каждом запуске: в части запусков у `UITabBarItem` идентификатор пуст,
/// и кнопки видны в дереве доступности только с подписями. Поэтому идентификатор ставится прямо на `UITabBarItem`.
struct TabBarIdentifiers: UIViewControllerRepresentable {
    let identifiers: [String: String]

    func makeUIViewController(context: Context) -> IdentifierController {
        IdentifierController(identifiers: identifiers)
    }

    func updateUIViewController(_ controller: IdentifierController, context: Context) {
        controller.identifiers = identifiers
        controller.scheduleIdentifiers()
    }

    /// SwiftUI может заменить UITabBarItem после первого появления бара. Назначение связано с раскладкой
    /// и появлением контроллера, а не с одноразовым поиском, который завершался до этой замены.
    final class IdentifierController: UIViewController {
        var identifiers: [String: String]

        init(identifiers: [String: String]) {
            self.identifiers = identifiers
            super.init(nibName: nil, bundle: nil)
        }

        required init?(coder: NSCoder) { return nil }

        override func loadView() {
            view = UIView()
            view.isUserInteractionEnabled = false
        }

        override func viewDidLayoutSubviews() {
            super.viewDidLayoutSubviews()
            scheduleIdentifiers()
        }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            scheduleIdentifiers()
        }

        func scheduleIdentifiers() {
            // TabView завершает создание и замену UITabBarItem после callbacks дочернего контроллера.
            DispatchQueue.main.async { [weak self] in self?.applyIdentifiers() }
        }

        private func applyIdentifiers() {
            guard let window = viewIfLoaded?.window else { return }
            let bars = tabBarController.map { [$0.tabBar] } ?? Self.tabBars(in: window)
            for item in bars.flatMap({ $0.items ?? [] }) {
                if let title = item.title, let id = identifiers[title] {
                    item.accessibilityIdentifier = id
                }
            }
        }

        private static func tabBars(in view: UIView) -> [UITabBar] {
            if let bar = view as? UITabBar { return [bar] }
            return view.subviews.flatMap(tabBars(in:))
        }
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

/// Основная кнопка: залита акцентом, белый текст 17 semibold, высота 50. Недоступная — прозрачность 0,4.
struct PrimaryButtonStyle: ButtonStyle {
    var fullWidth = true

    func makeBody(configuration: Configuration) -> some View {
        StyledLabel(configuration: configuration) { label, isEnabled in
            label
                .font(.body.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, fullWidth ? 16 : 36)
                .frame(maxWidth: fullWidth ? .infinity : nil, minHeight: 50)
                .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 14))
                .opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1) : 0.4)
                .contentShape(RoundedRectangle(cornerRadius: 14))
        }
    }
}

/// Подпись кнопки с доступностью из окружения: стиль кнопки сам `isEnabled` не получает.
private struct StyledLabel<Content: View>: View {
    let configuration: ButtonStyleConfiguration
    let content: (ButtonStyleConfiguration.Label, Bool) -> Content
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        content(configuration.label, isEnabled)
    }
}

/// Вторичная кнопка: контур 1,5 pt акцентом (или другим цветом — красным для «Удалить»), текст тем же цветом, высота 50.
struct SecondaryButtonStyle: ButtonStyle {
    var color: Color = .accentColor
    var minHeight: CGFloat = 50
    var font: Font = .body.weight(.semibold)

    func makeBody(configuration: Configuration) -> some View {
        StyledLabel(configuration: configuration) { label, isEnabled in
            label
                .font(font)
                .foregroundStyle(color)
                .padding(.horizontal, 16)
                .frame(maxWidth: .infinity, minHeight: minHeight)
                .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(color, lineWidth: 1.5))
                .opacity(isEnabled ? (configuration.isPressed ? 0.6 : 1) : 0.4)
                .contentShape(RoundedRectangle(cornerRadius: 14))
        }
    }
}
