import Foundation
import Testing

@testable import Glance

/// Shortcuts run outside Glance, from Terminal, the Shortcuts app or anywhere else, followed by
/// their published progress and named by Shortcuts' library.
@Suite("Shortcuts started elsewhere", .serialized)
@MainActor
struct ShortcutElsewhereTests {
    private let definition = ShortcutDefinition(id: UUID(uuidString: "00000000-0000-0000-0000-0000000000E1")!, name: "Glance Test Wait")

    private final class Source: ShortcutRunning {
        var catalogEntries: [ShortcutDefinition] = []
        var catalogReads = 0
        func catalog() async throws -> [ShortcutDefinition] {
            catalogReads += 1
            return catalogEntries
        }
        func launch(_ shortcut: ShortcutDefinition, completion: @escaping @MainActor (ShortcutExit) -> Void) throws -> any ShortcutRunHandle {
            throw ShortcutError.unavailable
        }
    }

    @Test("The library's note names the shortcut: only shortcuts updated, objectType 0, as seen on macOS 27.3")
    func libraryNote() {
        let shortcut = UUID()
        let userInfo: [AnyHashable: Any] = [
            "processIdentifier": 876, "inserted": [] as [Any],
            "updated": [["identifier": shortcut.uuidString, "objectType": 0], ["identifier": UUID().uuidString, "objectType": 5]],
        ]
        #expect(ShortcutRunPairing.shortcuts(updatedIn: userInfo) == [shortcut])
        // A run event inserted, or a run's end, names no shortcut.
        #expect(ShortcutRunPairing.shortcuts(updatedIn: ["inserted": [["identifier": shortcut.uuidString, "objectType": 5]]]).isEmpty)
        #expect(ShortcutRunPairing.shortcuts(updatedIn: nil).isEmpty)
    }

    @Test("A run's progress takes the note that came within a second of it, before or after, each note once")
    func pairing() {
        var pairing = ShortcutRunPairing()
        let start = Date(timeIntervalSince1970: 1_000)
        let a = UUID(), b = UUID()
        // Seen live: the progress came 3 ms before the note.
        #expect(pairing.published(1, at: start) == nil)
        #expect(pairing.saved([a], at: start + 0.003) == [1])
        #expect(pairing.shortcut(of: 1) == a)
        // A note first, then the progress.
        #expect(pairing.saved([b], at: start + 10).isEmpty)
        #expect(pairing.published(2, at: start + 10.2) == b)
        // A note from long before (Shortcuts opened, a shortcut edited) names nothing.
        #expect(pairing.saved([a], at: start + 20).isEmpty)
        #expect(pairing.published(3, at: start + 25) == nil)
        #expect(pairing.isWaiting(3))
        pairing.stopWaiting(3)
        #expect(pairing.saved([a], at: start + 25.1).isEmpty)
        #expect(pairing.shortcut(of: 3) == nil)
        pairing.forget(1)
        #expect(pairing.shortcut(of: 1) == nil)
    }

    @Test("A run started elsewhere shows by its name, fills, and closes by itself once done")
    func elsewhereRun() async throws {
        let source = Source()
        source.catalogEntries = [definition]
        let activity = ShortcutActivity(source: source, closeDelay: .milliseconds(80))
        activity.progress(.began(publication: 7, shortcut: definition.id, fraction: 0))
        let run = try #require(activity.shown?.run)
        #expect(run.elsewhere == 7)
        #expect(run.state == .running)
        // Named once the catalog is read.
        try await Task.sleep(for: .milliseconds(50))
        #expect(activity.shown?.run.shortcut.name == "Glance Test Wait")
        activity.progress(.progressed(publication: 7, fraction: 0.5))
        #expect(activity.shown?.run.progress == 0.5)
        activity.progress(.ended(publication: 7, cancelled: false))
        #expect(activity.shown?.run.state == .completed)
        try await Task.sleep(for: .milliseconds(400))
        #expect(activity.shown == nil)
        #expect(activity.runs.isEmpty)
    }

    @Test("Stop cancels a run started elsewhere through its progress, and it ends stopped")
    func stopElsewhere() {
        var cancelled: [Int] = []
        let activity = ShortcutActivity(source: Source(), cancelPublication: { cancelled.append($0) })
        activity.progress(.began(publication: 3, shortcut: nil, fraction: 0.2))
        let run = try! #require(activity.shown?.run)
        #expect(run.identified == false)
        #expect(run.shortcut.name == String(localized: "Shortcut"))
        #expect(run.canStop)
        activity.stop(run.id)
        #expect(cancelled == [3])
        #expect(activity.shown?.run.state == .stopping)
        activity.progress(.ended(publication: 3, cancelled: true))
        #expect(activity.shown?.run.state == .stopped)
    }

    @Test("A run started from the notch takes its own progress, named or not, and none shows twice")
    func ownRunKeepsItsProgress() {
        final class Launching: ShortcutRunning {
            final class Handle: ShortcutRunHandle {
                var processIdentifier: Int32 { 1 }
                var isRunning: Bool { true }
                func requestStop() {}
            }
            func catalog() async throws -> [ShortcutDefinition] { [] }
            func launch(_ shortcut: ShortcutDefinition, completion: @escaping @MainActor (ShortcutExit) -> Void) throws -> any ShortcutRunHandle { Handle() }
        }
        let activity = ShortcutActivity(source: Launching())
        let mine = activity.run(definition)
        activity.progress(.began(publication: 1, shortcut: definition.id, fraction: 0.25))
        #expect(activity.runs.count == 1)
        #expect(activity.runs.first { $0.id == mine }?.progress == 0.25)
        let other = activity.run(ShortcutDefinition(id: UUID(), name: "Other"))
        // Unnamed, it goes to the one Glance just started.
        activity.progress(.began(publication: 2, shortcut: nil, fraction: 0.1))
        #expect(activity.runs.count == 2)
        #expect(activity.runs.first { $0.id == other }?.progress == 0.1)
        // A third, of a shortcut Glance isn't running, is a run of its own.
        activity.progress(.began(publication: 3, shortcut: UUID(), fraction: 0))
        #expect(activity.runs.count == 3)
        #expect(activity.runs.filter { $0.elsewhere != nil }.count == 1)
    }

    @Test("Runs started elsewhere stay out of the notch while they're not to show there")
    func hiddenElsewhere() {
        var shows = false
        let activity = ShortcutActivity(source: Source(), showsElsewhere: { shows })
        activity.progress(.began(publication: 1, shortcut: nil, fraction: 0))
        #expect(activity.runs.isEmpty)
        #expect(activity.shown == nil)
        // Its progress afterwards doesn't bring it in.
        activity.progress(.progressed(publication: 1, fraction: 0.5))
        #expect(activity.runs.isEmpty)
        shows = true
        activity.progress(.began(publication: 2, shortcut: nil, fraction: 0))
        #expect(activity.shown?.run.elsewhere == 2)
        shows = false
        activity.settingsChanged()
        #expect(activity.shown == nil)
    }
}
