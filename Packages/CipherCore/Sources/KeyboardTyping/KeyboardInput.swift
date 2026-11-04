import Foundation

public enum KeyboardLanguage: Sendable { case russian, english }
public enum KeyboardPage: Sendable { case letters, numbers, symbols }
public enum KeyboardShift: Sendable { case automatic, off, once, caps }

/// Session-local editing state. Cursor counts extended grapheme clusters, never UTF-16 units.
public struct KeyboardInput: Sendable {
    public private(set) var text = ""
    public private(set) var cursor = 0
    public private(set) var language = KeyboardLanguage.russian
    public private(set) var page = KeyboardPage.letters
    public private(set) var shift = KeyboardShift.automatic
    public private(set) var limitError = false
    private var lastShiftTap: TimeInterval?
    public init() {}
    public var byteCount: Int { text.utf8.count }
    public var counter: String? { byteCount >= 2000 ? "\(byteCount) / 4096 байт" : nil }
    public static let limitMessage = "Сообщение не должно превышать 4096 байт"
    public var uppercase: Bool {
        switch shift {
        case .off: return false
        case .once, .caps: return true
        case .automatic:
            let prefix = String(text.prefix(cursor))
            return prefix.isEmpty || prefix.hasSuffix("\n") || [". ", "! ", "? "].contains(where: prefix.hasSuffix)
        }
    }
    public var rows: [[String]] {
        let source: [String]
        switch page {
        case .letters:
            source =
                language == .russian
                ? ["й ц у к е н г ш щ з х", "ф ы в а п р о л д ж э", "я ч с м и т ь б ю"]
                : ["q w e r t y u i o p", "a s d f g h j k l", "z x c v b n m"]
        case .numbers: source = ["1 2 3 4 5 6 7 8 9 0", "- / : ; ( ) ₽ & @ \"", ". , ? ! '"]
        case .symbols: source = ["[ ] { } # % ^ * + =", "_ \\ | ~ < > € £ ¥ •", ". , ? ! '"]
        }
        return source.map { $0.split(separator: " ").map(String.init) }
    }
    public mutating func moveCursor(to position: Int) { cursor = max(0, min(position, text.count)) }
    @discardableResult public mutating func insert(_ value: String) -> Bool {
        guard byteCount + value.utf8.count <= 4096 else { limitError = true; return false }
        let index = text.index(text.startIndex, offsetBy: cursor)
        let prefix = String(text[..<index]) + value
        text.insert(contentsOf: value, at: index)
        // Insertion can join neighboring graphemes. Snap forward to the next valid boundary.
        let target = prefix.utf16.count
        var offset = 0
        cursor = 0
        for character in text {
            if offset >= target { break }
            offset += String(character).utf16.count
            cursor += 1
        }
        limitError = false
        return true
    }
    public mutating func typeKey(_ key: String) {
        let letter = key.unicodeScalars.contains { CharacterSet.letters.contains($0) }
        if insert(letter && uppercase ? key.uppercased() : key), letter {
            if shift != .caps { shift = .automatic }
            lastShiftTap = nil
        }
    }
    public mutating func deleteBackward() {
        limitError = false
        guard cursor > 0 else { return }
        let end = text.index(text.startIndex, offsetBy: cursor)
        text.removeSubrange(text.index(before: end)..<end)
        cursor -= 1
    }
    public mutating func tapShift(at time: TimeInterval) {
        if shift == .caps { shift = .off; lastShiftTap = nil; return }
        if let previous = lastShiftTap, time - previous <= 0.300, time >= previous {
            shift = .caps
            lastShiftTap = nil
        } else {
            shift = uppercase ? .off : .once
            lastShiftTap = time
        }
    }
    public mutating func toggleLanguage() {
        language = language == .russian ? .english : .russian
        page = .letters
    }
    public mutating func toggleNumbers() { page = page == .letters ? .numbers : .letters }
    public mutating func toggleSymbols() { page = page == .symbols ? .numbers : .symbols }
    public mutating func reset() { self = KeyboardInput() }
    #if DEBUG
        fileprivate static func defensiveLimitFixture() -> Self {
            var value = KeyboardInput()
            let prefix = "Синтетический черновик: 4097 байт…\n(полный текст — в тестовой зависимости)\n"
            value.text = prefix + String(repeating: "a", count: 4097 - prefix.utf8.count); value.cursor = 0
            return value
        }
    #endif
}

/// Injectable monotonic clock. Cancellation must also remove pending callbacks.
@MainActor public protocol KeyboardClock: AnyObject {
    var now: TimeInterval { get }
    func schedule(after delay: TimeInterval, _ action: @escaping @MainActor () -> Void) -> UUID
    func cancel(_ token: UUID)
}

@MainActor public final class SystemKeyboardClock: KeyboardClock {
    private var tasks: [UUID: Task<Void, Never>] = [:]
    public init() {}
    public var now: TimeInterval { ProcessInfo.processInfo.systemUptime }
    public func schedule(after delay: TimeInterval, _ action: @escaping @MainActor () -> Void) -> UUID {
        let id = UUID()
        tasks[id] = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(delay)) } catch { return }
            guard !Task.isCancelled else { return }
            self?.tasks[id] = nil
            action()
        }
        return id
    }
    public func cancel(_ token: UUID) { tasks.removeValue(forKey: token)?.cancel() }
    deinit { for task in tasks.values { task.cancel() } }
}

public enum KeyboardAction: Equatable, Sendable {
    case character(String), delete, shift, language, numbers, symbols, space, enter
}

/// Production adapter used by both UIKit shells. Intentionally has no host document capability.
@MainActor public final class KeyboardInputAdapter {
    public private(set) var input = KeyboardInput()
    public var alternative: String? {
        gestureOrder.reversed().compactMap { gestures[$0]?.alternative }.first
    }
    public var onChange: (() -> Void)?
    public var interactionEnabled = true { didSet { if !interactionEnabled { cancelGesture() } } }
    private let clock: any KeyboardClock
    private struct Gesture {
        let action: KeyboardAction
        var timer: UUID?
        var alternative: String?
    }
    private var gestures: [UUID: Gesture] = [:]
    private var gestureOrder: [UUID] = []
    public var activeTimerCount: Int { gestures.values.filter { $0.timer != nil }.count }
    public init(clock: any KeyboardClock = SystemKeyboardClock()) { self.clock = clock }
    public func moveCursor(to position: Int) {
        guard interactionEnabled else { return }; input.moveCursor(to: position); onChange?()
    }
    @discardableResult public func press(_ action: KeyboardAction) -> UUID {
        let token = UUID()
        guard interactionEnabled else { return token }
        gestures[token] = Gesture(action: action)
        gestureOrder.append(token)
        if action == .delete {
            input.deleteBackward()
            scheduleDelete(token, after: 0.400)
        } else if case .character(let key) = action, key == "е" || key == "ь" {
            gestures[token]?.timer = clock.schedule(after: 0.450) { [weak self] in
                guard let self, self.gestures[token] != nil else { return }
                self.gestures[token]?.timer = nil
                self.gestures[token]?.alternative = key == "е" ? "ё" : "ъ"
                self.onChange?()
            }
        }
        onChange?()
        return token
    }
    public func release(_ token: UUID, inside: Bool) {
        guard let gesture = gestures[token] else { return }
        cancelGesture(token)
        guard inside else { return }
        switch gesture.action {
        case .character(let value): input.typeKey(gesture.alternative ?? value)
        case .delete: break
        case .shift: input.tapShift(at: clock.now)
        case .language: input.toggleLanguage()
        case .numbers: input.toggleNumbers()
        case .symbols: input.toggleSymbols()
        case .space: input.typeKey(" ")
        case .enter: input.typeKey("\n")
        }
        onChange?()
    }
    public func activate(_ action: KeyboardAction) { let token = press(action); release(token, inside: true) }
    public func cancelGesture(_ token: UUID? = nil) {
        let cancelled = token.map { [$0] } ?? gestureOrder
        for id in cancelled {
            if let timer = gestures.removeValue(forKey: id)?.timer { clock.cancel(timer) }
        }
        gestureOrder.removeAll { gestures[$0] == nil }
        onChange?()
    }
    public func hide() { cancelGesture(); input.reset(); onChange?() }
    public func rotate() { cancelGesture() }
    private func scheduleDelete(_ token: UUID, after delay: TimeInterval) {
        gestures[token]?.timer = clock.schedule(after: delay) { [weak self] in
            guard let self, self.gestures[token]?.action == .delete else { return }
            self.gestures[token]?.timer = nil
            self.input.deleteBackward()
            self.scheduleDelete(token, after: 0.080)
            self.onChange?()
        }
    }
    #if DEBUG
        /// Synthetic fixtures only. This API is not compiled in Release.
        public func seedDefensiveLimitForTesting() {
            hide(); input = .defensiveLimitFixture(); onChange?()
        }
        public func seedForTesting(_ text: String, cursor: Int? = nil) {
            hide()
            input.insert(text)
            if let cursor { input.moveCursor(to: cursor) }
            onChange?()
        }
    #endif
}
