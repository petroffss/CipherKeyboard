import UIKit

/// The only external URL action accepts no caller-provided destination or payload.
@MainActor enum SystemSettings {
    @discardableResult static func open() async -> Bool {
        guard let settings = URL(string: UIApplication.openSettingsURLString) else { return false }
        return await UIApplication.shared.open(settings)
    }
}
