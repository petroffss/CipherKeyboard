import CipherCore
import Foundation
import Observation
import UIKit

@MainActor @Observable
final class SetupModel {
    private(set) var state = KeyboardSetupState.unknown
    private(set) var settingsFailed = false
    private let presence: () -> KeyboardPresence
    private let tracker: KeyboardSetupTracker
    private let opener: (URL) async -> Bool

    init(
        presence: @escaping () -> KeyboardPresence,
        storage: any KeyboardSetupStorage,
        invalidation: any KeyboardSetupStorage,
        opener: @escaping (URL) async -> Bool
    ) {
        self.presence = presence
        self.tracker = KeyboardSetupTracker(shared: storage, invalidation: invalidation)
        self.opener = opener
    }

    var confirmed: Bool {
        if case .confirmed = state { return true }
        return false
    }

    func refresh() {
        state = tracker.refresh(presence: presence(), now: Date())
    }

    func openSettings() async {
        guard let url = URL(string: UIApplication.openSettingsURLString) else {
            settingsFailed = true
            return
        }
        settingsFailed = !(await opener(url))
    }

    private static func localInvalidationStorage() -> FileKeyboardSetupStorage {
        // App sandbox only. The extension cannot access this deletion cutoff.
        let directory = try? FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        return FileKeyboardSetupStorage(url: directory?.appendingPathComponent("keyboard-removed.v1.json"))
    }

    static func live() -> SetupModel {
        #if DEBUG
            if let fake = SetupTestDependencies.make() { return fake }
        #endif
        return SetupModel(
            presence: {
                // Public APIs do not identify our extension reliably, and CA92.1 does not cover reading the
                // system keyboard list. "Confirmed" comes only from the record the extension writes with full access.
                .unknown
            },
            storage: FileKeyboardSetupStorage.appGroup,
            invalidation: localInvalidationStorage(),
            opener: { _ in await SystemSettings.open() }
        )
    }
}

#if DEBUG
    /// Isolated UI-test dependencies. Neither keychain nor the real shared setup file is touched.
    @MainActor
    private enum SetupTestDependencies {
        static func make() -> SetupModel? {
            let args = ProcessInfo.processInfo.arguments
            func argument(_ flag: String) -> String? {
                guard let index = args.firstIndex(of: flag), index + 1 < args.count else { return nil }
                return args[index + 1]
            }
            guard let initial = argument("-setup-state") else { return nil }
            let storage = SetupMemoryStorage()
            if initial == "confirmed" {
                storage.data = try? KeyboardAccessRecord(date: Date().addingTimeInterval(-60)).encoded()
            }
            let sequence = (argument("-setup-sequence") ?? initial).split(separator: ",").map(String.init)
            var index = 0
            let openResult = argument("-setup-open") != "failure"
            return SetupModel(
                presence: {
                    let value = sequence[min(index, sequence.count - 1)]
                    index += 1
                    switch value {
                    case "absent": return .absent
                    case "confirmed", "present": return .present
                    default: return .unknown
                    }
                }, storage: storage, invalidation: SetupMemoryStorage(),
                opener: { url in
                    // Tests verify that the real action supplies the public Settings URL.
                    openResult && url.absoluteString == UIApplication.openSettingsURLString
                }
            )
        }
    }

    private final class SetupMemoryStorage: KeyboardSetupStorage {
        var data: Data?
        func read() throws -> Data? { data }
        func write(_ data: Data) throws { self.data = data }
        func remove() throws { data = nil }
    }
#endif
