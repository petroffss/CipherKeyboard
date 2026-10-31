import CipherCore
import CoreGraphics
import Observation

/// Что показывает экран «Мой ключ»: только открытая часть личности.
struct MyKeyInfo {
    /// Свой открытый ключ: `publicKey.string` — ровно то, что уходит в QR, буфер обмена и «Поделиться».
    let publicKey: PublicKey
    let qrCode: CGImage?

    init(publicKey: PublicKey) {
        self.publicKey = publicKey
        qrCode = QRCode.image(for: publicKey.string)
    }

    /// `Fingerprint.description`: 8 групп по 4 символа через пробел.
    var fingerprint: String { publicKey.fingerprint.description }

    /// Отпечаток в две строки по 4 группы — только для показа.
    var fingerprintTwoLines: String {
        let groups = fingerprint.split(separator: " ")
        return groups.prefix(4).joined(separator: " ") + "\n" + groups.dropFirst(4).joined(separator: " ")
    }
}

/// Загрузка своей личности: прочитать из хранилища или создать при первом запуске.
@MainActor
@Observable
final class MyKeyModel {
    enum State {
        case loading
        case ready(MyKeyInfo)
        case failed
    }

    private(set) var state: State = .loading
    private var isLoading = false
    private var started = false
    private let store: IdentityStore

    init(store: IdentityStore) {
        self.store = store
    }

    /// Первая загрузка при появлении экрана.
    func loadIfNeeded() {
        guard !started else { return }
        started = true
        load()
    }

    /// «Повторить»: заново читает хранилище. Пока чтение идёт, повторные нажатия игнорируются.
    func retry() {
        load()
    }

    private func load() {
        guard !isLoading else { return }
        isLoading = true
        state = .loading
        let store = store
        Task {
            let result = await Task.detached { () -> PublicKey? in
                // Keychain — синхронный вызов, поэтому не на главном потоке.
                try? store.loadOrCreate().publicKey
            }.value
            if let result {
                state = .ready(MyKeyInfo(publicKey: result))
            } else {
                state = .failed
            }
            isLoading = false
        }
    }
}
