import Foundation
import Testing

@testable import Glance

@Suite("Shortcut temporary result retention")
struct ShortcutRunStorageTests {
    private let date = Date(timeIntervalSince1970: 1_800_000_000)

    private func root() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("Glance-ShortcutStorageTests-\(UUID().uuidString)", isDirectory: true)
    }

    @Test("Only a bounded stderr message remains after completion; Done removes an empty result")
    func stderrAndEmptyResult() throws {
        let root = root()
        defer { try? FileManager.default.removeItem(at: root) }
        let storage = try ShortcutRunStorage.create(in: root)
        try Data().write(to: storage.output)
        try Data(repeating: 65, count: 8_192).write(to: storage.errors)
        let result = storage.finish(at: date)
        #expect(result.message?.utf8.count == 4_096)
        #expect(result.output == nil)
        #expect(!FileManager.default.fileExists(atPath: storage.errors.path))
        storage.discardEmptyResult()
        #expect(!FileManager.default.fileExists(atPath: storage.directory.path))
    }

    @Test("Done retains a nonempty result until startup cleanup at the 24-hour boundary")
    func finiteResultRetention() throws {
        let root = root()
        defer { try? FileManager.default.removeItem(at: root) }
        let storage = try ShortcutRunStorage.create(in: root)
        let content = Data("A real result".utf8)
        try content.write(to: storage.output)
        #expect(storage.finish(at: date).output == storage.output)
        storage.discardEmptyResult()
        #expect(try Data(contentsOf: storage.output) == content)
        ShortcutRunStorage.cleanupExpired(in: root, now: date + ShortcutRunStorage.retention - 1)
        #expect(FileManager.default.fileExists(atPath: storage.output.path))
        ShortcutRunStorage.cleanupExpired(in: root, now: date + ShortcutRunStorage.retention)
        #expect(!FileManager.default.fileExists(atPath: storage.directory.path))
    }

    @Test("Cleanup does not infer completion from the age of an active or legacy folder")
    func unfinishedFolder() throws {
        let root = root()
        defer { try? FileManager.default.removeItem(at: root) }
        let storage = try ShortcutRunStorage.create(in: root)
        try Data("Active output".utf8).write(to: storage.output)
        try Data("Still writing".utf8).write(to: storage.errors)
        try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: storage.directory.path)
        ShortcutRunStorage.cleanupExpired(in: root, now: date + ShortcutRunStorage.retention * 2)
        #expect(FileManager.default.fileExists(atPath: storage.output.path))
        #expect(FileManager.default.fileExists(atPath: storage.errors.path))
    }

    @Test("Edited results and user-added files are preserved instead of recursively removed")
    func preserveUserChanges() throws {
        let root = root()
        defer { try? FileManager.default.removeItem(at: root) }
        let edited = try ShortcutRunStorage.create(in: root)
        try Data("Original".utf8).write(to: edited.output)
        _ = edited.finish(at: date)
        let revised = Data("User revised this result".utf8)
        try revised.write(to: edited.output)
        let extra = try ShortcutRunStorage.create(in: root)
        try Data().write(to: extra.output)
        _ = extra.finish(at: date)
        let added = extra.directory.appendingPathComponent("User Notes.txt")
        try Data("Keep".utf8).write(to: added)
        extra.discardEmptyResult()
        ShortcutRunStorage.cleanupExpired(in: root, now: date + ShortcutRunStorage.retention)
        #expect(try Data(contentsOf: edited.output) == revised)
        #expect(FileManager.default.fileExists(atPath: added.path))
        #expect(FileManager.default.fileExists(atPath: extra.output.path))
    }

    @Test("Moving a result outside its run folder keeps the exported file untouched")
    func exportedResult() throws {
        let root = root()
        defer { try? FileManager.default.removeItem(at: root) }
        let storage = try ShortcutRunStorage.create(in: root)
        let content = Data("Saved result".utf8)
        try content.write(to: storage.output)
        _ = storage.finish(at: date)
        let exported = root.appendingPathComponent("Saved.txt")
        try FileManager.default.moveItem(at: storage.output, to: exported)
        ShortcutRunStorage.cleanupExpired(in: root, now: date + ShortcutRunStorage.retention)
        #expect(try Data(contentsOf: exported) == content)
        #expect(!FileManager.default.fileExists(atPath: storage.directory.path))
    }

    @Test("A symlink replacement cannot redirect cleanup to another file")
    func symlinkResult() throws {
        let root = root()
        defer { try? FileManager.default.removeItem(at: root) }
        let storage = try ShortcutRunStorage.create(in: root)
        try Data("Original".utf8).write(to: storage.output)
        _ = storage.finish(at: date)
        try FileManager.default.removeItem(at: storage.output)
        let outside = root.appendingPathComponent("Keep.txt")
        let content = Data("Private file".utf8)
        try content.write(to: outside)
        try FileManager.default.createSymbolicLink(at: storage.output, withDestinationURL: outside)
        ShortcutRunStorage.cleanupExpired(in: root, now: date + ShortcutRunStorage.retention)
        #expect(try Data(contentsOf: outside) == content)
        #expect(FileManager.default.fileExists(atPath: storage.directory.path))
    }
}
