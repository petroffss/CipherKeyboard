import Foundation
import Testing

@testable import CipherCore

struct SetupStateTests {
    @Test func resolvesStates() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let old = now.addingTimeInterval(-60)
        let valid = try KeyboardAccessRecord(date: old).encoded()
        let future = try KeyboardAccessRecord(date: now.addingTimeInterval(1)).encoded()
        let unsupported = Data(#"{"version":2,"date":1}"#.utf8)
        let corrupt = Data("broken".utf8)
        for record in [nil, valid, corrupt, future, unsupported] as [Data?] {
            #expect(KeyboardSetupState.resolve(presence: .absent, record: record, now: now) == .absent)
            #expect(KeyboardSetupState.resolve(presence: .unknown, record: record, now: now) == .unknown)
            #expect(
                KeyboardSetupState.resolve(presence: .present, record: record, now: now)
                    == (record == valid ? .confirmed(old) : .needsOpening))
        }
        let identifier = KeyboardPresence.extensionIdentifier
        #expect(KeyboardPresence.parse(["en_US@sw=QWERTY;hw=Automatic", identifier]) == .present)
        #expect(KeyboardPresence.parse([identifier + ".other"]) == .absent)
        #expect(KeyboardPresence.parse(["prefix." + identifier]) == .absent)
        #expect(KeyboardPresence.parse(["emoji@sw=Emoji"]) == .absent)
        for unknown: Any? in [nil, [], "", [17], ["new-format"], [identifier, "???"]] {
            #expect(KeyboardPresence.parse(unknown) == .unknown)
        }
    }

    @Test func recordsOnlySuccessfulAccess() throws {
        let storage = RecordingSetupStorage()
        var factoryCalls = 0
        let factory = {
            factoryCalls += 1
            return storage as any KeyboardSetupStorage
        }
        #expect(!KeyboardAccessRecorder.record(hasFullAccess: false, storage: factory))
        #expect(factoryCalls == 0)
        #expect(storage.writes == 0)
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        #expect(KeyboardAccessRecorder.record(hasFullAccess: true, now: now, storage: factory))
        #expect(factoryCalls == 1)
        #expect(storage.writes == 1)
        let data = try #require(storage.data)
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(Set(json.keys) == ["version", "date"])
        #expect(json["version"] as? Int == 1)
        #expect(KeyboardAccessRecord.validDate(in: data, now: now) == now)
        storage.fails = true
        #expect(!KeyboardAccessRecorder.record(hasFullAccess: true, now: now.addingTimeInterval(2), storage: factory))
        #expect(storage.data == data)
        #expect(storage.reads == 0)
        #expect(storage.removes == 0)
    }

    @Test func failedRemovalCannotReviveEvidenceAfterRelaunch() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let shared = RecordingSetupStorage()
        let local = RecordingSetupStorage()
        shared.data = try KeyboardAccessRecord(date: now.addingTimeInterval(-60)).encoded()
        shared.removeFails = true
        let first = KeyboardSetupTracker(shared: shared, invalidation: local)
        #expect(first.refresh(presence: .absent, now: now) == .absent)
        #expect(local.data != nil)
        #expect(shared.data != nil)
        // A new instance represents a terminated and relaunched app, with no retained in-memory state.
        let relaunched = KeyboardSetupTracker(shared: shared, invalidation: local)
        #expect(relaunched.refresh(presence: .present, now: now.addingTimeInterval(1)) == .needsOpening)
        shared.data = try KeyboardAccessRecord(date: now.addingTimeInterval(2)).encoded()
        #expect(
            relaunched.refresh(presence: .present, now: now.addingTimeInterval(3))
                == .confirmed(now.addingTimeInterval(2)))
        #expect(local.data == nil)
    }

    @Test func failedCutoffWriteStillDeletesSharedEvidence() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let shared = RecordingSetupStorage()
        let local = RecordingSetupStorage()
        shared.data = try KeyboardAccessRecord(date: now.addingTimeInterval(-60)).encoded()
        local.fails = true
        let tracker = KeyboardSetupTracker(shared: shared, invalidation: local)
        #expect(tracker.refresh(presence: .absent, now: now) == .absent)
        #expect(shared.data == nil)
        #expect(shared.removes == 1)
        let relaunched = KeyboardSetupTracker(shared: shared, invalidation: local)
        #expect(relaunched.refresh(presence: .present, now: now) == .needsOpening)
        shared.data = try KeyboardAccessRecord(date: now.addingTimeInterval(-60)).encoded()
        shared.removeFails = true
        #expect(tracker.refresh(presence: .absent, now: now) == .unknown)
        #expect(tracker.refresh(presence: .present, now: now) == .unknown)
    }

    @Test func fileRoundTripAndRemoval() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let sentinel = directory.appendingPathComponent("contacts.v1.json")
        let untouched = Data("unrelated data".utf8)
        try untouched.write(to: sentinel)
        let storage = FileKeyboardSetupStorage(url: directory.appendingPathComponent(FileKeyboardSetupStorage.fileName))
        #expect(try storage.read() == nil)
        let data = try KeyboardAccessRecord(date: Date()).encoded()
        try storage.write(data)
        #expect(try storage.read() == data)
        try storage.remove()
        try storage.remove()
        #expect(try storage.read() == nil)
        #expect(try Data(contentsOf: sentinel) == untouched)
        #expect(!KeyboardAccessRecorder.record(hasFullAccess: true) { FileKeyboardSetupStorage(url: nil) })
    }
}

private final class RecordingSetupStorage: KeyboardSetupStorage {
    var data: Data?
    var writes = 0
    var reads = 0
    var removes = 0
    var fails = false
    var removeFails = false
    func read() throws -> Data? {
        reads += 1
        return data
    }
    func write(_ data: Data) throws {
        writes += 1
        if fails { throw CocoaError(.fileWriteNoPermission) }
        self.data = data
    }
    func remove() throws {
        removes += 1
        if removeFails { throw CocoaError(.fileWriteNoPermission) }
        data = nil
    }
}
