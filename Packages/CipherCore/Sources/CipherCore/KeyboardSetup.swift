import Foundation

/// The system list is best-effort: missing or unfamiliar data is never evidence of removal.
public enum KeyboardPresence: Equatable, Sendable {
    case absent, present, unknown

    public static let extensionIdentifier = "dev.cipherkeyboard.app.keyboard"

    public static func parse(_ value: Any?) -> Self {
        guard let identifiers = value as? [String], !identifiers.isEmpty else { return .unknown }
        for identifier in identifiers {
            // Observed iOS 27 formats: bundle identifiers, or language@sw=Layout;hw=Hardware.
            let bundle = identifier.range(of: #"^[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)+$"#, options: .regularExpression)
            let system = identifier.range(
                of: #"^[A-Za-z0-9_-]+@sw=[A-Za-z0-9_-]+(?:;hw=[A-Za-z0-9_-]+)?$"#,
                options: .regularExpression)
            guard bundle != nil || system != nil else { return .unknown }
        }
        return identifiers.contains(extensionIdentifier) ? .present : .absent
    }
}

public enum KeyboardSetupState: Equatable, Sendable {
    case absent, needsOpening, confirmed(Date), unknown

    public static func resolve(presence: KeyboardPresence, record: Data?, now: Date) -> Self {
        switch presence {
        case .unknown: return .unknown
        case .absent: return .absent
        case .present:
            guard let record, let date = KeyboardAccessRecord.validDate(in: record, now: now) else {
                return .needsOpening
            }
            return .confirmed(date)
        }
    }
}

/// No permission boolean: this is only evidence of a successful opening in the past.
public struct KeyboardAccessRecord: Codable, Sendable {
    public let version: Int
    public let date: Date

    public init(date: Date) {
        version = 1
        self.date = date
    }

    public func encoded() throws -> Data { try JSONEncoder().encode(self) }

    public static func validDate(in data: Data, now: Date) -> Date? {
        guard let record = try? JSONDecoder().decode(Self.self, from: data),
            record.version == 1, record.date.timeIntervalSince1970.isFinite,
            record.date.timeIntervalSince1970 > 0, record.date <= now
        else { return nil }
        return record.date
    }
}

public protocol KeyboardSetupStorage {
    func read() throws -> Data?
    func write(_ data: Data) throws
    func remove() throws
}

public enum KeyboardAccessRecorder {
    /// The factory itself is behind the permission guard: even locating the container is forbidden without access.
    @discardableResult
    public static func record(
        hasFullAccess: Bool, now: Date = Date(), storage: () -> any KeyboardSetupStorage
    ) -> Bool {
        guard hasFullAccess else { return false }
        do {
            try storage().write(KeyboardAccessRecord(date: now).encoded())
            return true
        } catch {
            return false
        }
    }
}

public struct FileKeyboardSetupStorage: KeyboardSetupStorage {
    public static let fileName = "keyboard-access.v1.json"
    private let url: URL?

    public init(url: URL?) { self.url = url }

    public static var appGroup: Self {
        let container = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: "group.dev.cipherkeyboard")
        return Self(url: container?.appendingPathComponent(fileName))
    }

    public func read() throws -> Data? {
        guard let url else { throw CocoaError(.fileReadNoPermission) }
        do { return try Data(contentsOf: url) } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return nil
        }
    }

    public func write(_ data: Data) throws {
        guard let url else { throw CocoaError(.fileWriteNoPermission) }
        try data.write(to: url, options: .atomic)
    }

    public func remove() throws {
        guard let url else { throw CocoaError(.fileWriteNoPermission) }
        do { try FileManager.default.removeItem(at: url) } catch let error as CocoaError
            where error.code == .fileNoSuchFile
        {
            return
        }
    }
}

/// The app owns a separate durable invalidation file. It never adds fields to the extension's shared record.
/// Persist the cutoff before deleting the shared record, so a failed deletion cannot revive old evidence on relaunch.
public final class KeyboardSetupTracker {
    private var volatileCutoff: Date?
    private var persistenceFailed = false
    private let shared: any KeyboardSetupStorage
    private let invalidation: any KeyboardSetupStorage

    public init(shared: any KeyboardSetupStorage, invalidation: any KeyboardSetupStorage) {
        self.shared = shared
        self.invalidation = invalidation
    }

    public func refresh(presence: KeyboardPresence, now: Date) -> KeyboardSetupState {
        do {
            if presence == .unknown { return .unknown }
            if presence == .absent {
                volatileCutoff = now
                var savedCutoff = false
                do {
                    try invalidation.write(KeyboardAccessRecord(date: now).encoded())
                    savedCutoff = true
                } catch {
                    // Still attempt shared deletion: either durable operation can invalidate old evidence.
                }
                do {
                    try shared.remove()
                    persistenceFailed = false
                    return .absent
                } catch {
                    // If both writes fail there is no durable channel; retain uncertainty in this session.
                    persistenceFailed = !savedCutoff
                    return savedCutoff ? .absent : .unknown
                }
            }
            let record = try shared.read()
            let state = KeyboardSetupState.resolve(presence: presence, record: record, now: now)
            if let cutoff = volatileCutoff {
                guard case .confirmed(let date) = state, date > cutoff else {
                    return persistenceFailed ? .unknown : .needsOpening
                }
            }
            if let barrier = try invalidation.read() {
                guard let cutoff = KeyboardAccessRecord.validDate(in: barrier, now: now) else { return .unknown }
                guard case .confirmed(let date) = state, date > cutoff else { return .needsOpening }
                // A newer successful opening is sufficient even if cleanup fails: the cutoff still rejects older evidence.
                try? invalidation.remove()
            }
            if case .confirmed = state { volatileCutoff = nil }
            return state
        } catch {
            return .unknown
        }
    }
}
