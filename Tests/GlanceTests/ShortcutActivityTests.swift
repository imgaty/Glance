import AppKit
import Darwin
import Testing

@testable import Glance

@Suite("Glance-launched Shortcuts", .serialized)
@MainActor
struct ShortcutActivityTests {
    private let definition = ShortcutDefinition(id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!, name: "My Shortcut")

    private final class Handle: ShortcutRunHandle {
        let processIdentifier: Int32
        var isRunning = true
        var interrupts = 0
        init(_ processIdentifier: Int32) { self.processIdentifier = processIdentifier }
        func requestStop() { interrupts += 1 }
    }

    private final class Source: ShortcutRunning {
        var handles: [Handle] = []
        var launches: [ShortcutDefinition] = []
        var completions: [@MainActor (ShortcutExit) -> Void] = []
        var fails = false
        var catalogReads = 0
        var catalogEntries: [ShortcutDefinition] = []
        func catalog() async throws -> [ShortcutDefinition] {
            catalogReads += 1
            return catalogEntries
        }
        func launch(_ shortcut: ShortcutDefinition, completion: @escaping @MainActor (ShortcutExit) -> Void) throws -> any ShortcutRunHandle {
            if fails { throw ShortcutError.unavailable }
            launches.append(shortcut)
            completions.append(completion)
            let handle = Handle(Int32(1_000 + handles.count))
            handles.append(handle)
            return handle
        }
        func finish(_ index: Int, status: Int32 = 0, reason: ShortcutExit.Reason = .exit) {
            handles[index].isRunning = false
            completions[index](.init(status: status, reason: reason))
        }
    }

    @Test("Catalog uses the final UUID suffix and preserves punctuation in shortcut names")
    func catalogParsing() throws {
        let id = definition.id.uuidString
        let entries = try ShortcutDefinition.catalog("Name (with parentheses) (\(id))\nName (with parentheses) (\(id))\n")
        #expect(entries == [.init(id: definition.id, name: "Name (with parentheses)")])
        #expect(try ShortcutDefinition.catalog("").isEmpty)
        #expect(throws: ShortcutError.self) { try ShortcutDefinition.catalog("A name without an identifier") }
        #expect(throws: ShortcutError.self) { try ShortcutDefinition.catalog(" (\(id))") }
        #expect(throws: ShortcutError.self) { try ShortcutDefinition.catalog("Name (not-a-uuid)") }
    }

    @Test("Concurrent runs of the same shortcut stop only the captured run")
    func exactRunCancellation() {
        let source = Source()
        let activity = ShortcutActivity(source: source)
        let first = activity.run(definition)
        let second = activity.run(definition)
        #expect(first != second)
        #expect(source.launches == [definition, definition])
        #expect(activity.runs.map(\.processIdentifier) == [1_000, 1_001])
        activity.stop(first)
        activity.stop(first)
        #expect(source.handles[0].interrupts == 1)
        #expect(source.handles[1].interrupts == 0)
        #expect(activity.runs.first?.state == .stopping)
        #expect(activity.runs.last?.state == .running)
        source.finish(0, status: SIGINT, reason: .signal)
        #expect(activity.runs.first?.state == .stopped)
        #expect(activity.runs.last?.state == .running)
        activity.stop(first)
        #expect(source.handles[0].interrupts == 1)
        source.finish(1)
    }

    @Test("Stop does not claim cancellation before exit or overwrite a successful completion")
    func cancellationOutcome() {
        let source = Source()
        let activity = ShortcutActivity(source: source)
        let id = activity.run(definition)
        activity.stop(id)
        #expect(activity.shown?.run.state == .stopping)
        source.finish(0)
        #expect(activity.shown?.run.state == .completed)
        let next = activity.run(definition)
        activity.stop(next)
        source.finish(1, status: 1)
        #expect(activity.shown?.run.state == .endedAfterStop)
        #expect(activity.shown?.run.exit?.status == 1)
    }

    @Test("A nonresponsive stop remains active and offers another scoped request")
    func delayedStop() async throws {
        let source = Source()
        let activity = ShortcutActivity(source: source, stopDelay: .milliseconds(10))
        let id = activity.run(definition)
        activity.stop(id)
        // Other suites can occupy the main actor before the delayed task starts or publishes.
        // Wait for its observable result, bounded so a missing update still fails the test.
        let deadline = ContinuousClock.now + .seconds(5)
        while activity.shown?.run.state == .stopping, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(activity.shown?.run.state == .stopDelayed)
        #expect(activity.shown?.run.canStop == true)
        activity.stop(id)
        #expect(source.handles[0].interrupts == 2)
        source.finish(0, status: SIGINT, reason: .signal)
    }

    @Test("Launch failures remain visible without an actionable Stop")
    func launchFailure() {
        let source = Source()
        source.fails = true
        let activity = ShortcutActivity(source: source)
        let id = activity.run(definition)
        #expect(activity.shown?.run.state == .failed)
        #expect(activity.shown?.run.processIdentifier == nil)
        #expect(activity.shown?.run.canStop == false)
        activity.stop(id)
        #expect(source.handles.isEmpty)
        activity.dismiss(id)
        #expect(activity.shown == nil)
    }

    @Test("Finished and stale run actions cannot affect a newer invocation")
    func staleActions() {
        let source = Source()
        let activity = ShortcutActivity(source: source)
        let old = activity.run(definition)
        source.finish(0, status: 1)
        activity.dismiss(old)
        let current = activity.run(definition)
        activity.stop(old)
        activity.dismiss(current)
        activity.select(old)
        #expect(activity.shown?.run.id == current)
        #expect(source.handles[1].interrupts == 0)
        source.finish(1)
        activity.dismiss(current)
        #expect(activity.shown == nil)
    }

    @Test("Disabling the display preserves the exact run and never sends Stop")
    func visibilityPreference() {
        let source = Source()
        var enabled = true
        let activity = ShortcutActivity(source: source, isEnabled: { enabled })
        let id = activity.run(definition)
        enabled = false
        activity.settingsChanged()
        #expect(activity.shown == nil)
        #expect(activity.runs.first?.id == id)
        #expect(activity.runs.first?.state == .running)
        #expect(source.handles[0].interrupts == 0)
        enabled = true
        activity.settingsChanged()
        #expect(activity.shown?.run.id == id)
        source.finish(0)
    }

    @Test("The bench cannot launch a shortcut, read its catalog, or open external apps")
    func isolatedBenchActions() async throws {
        let source = Source()
        let activity = ShortcutActivity(source: source)
        let first = ShortcutRun.fixture()
        let second = ShortcutRun.fixture(state: .completed, ordinal: 1, withOutput: true)
        activity.bench([first, second])
        #expect(try await activity.loadCatalog() == [first.shortcut, second.shortcut])
        activity.stop(first.id)
        activity.select(second.id)
        activity.showResult(second.id)
        activity.openShortcuts()
        let simulated = activity.run(first.shortcut)
        #expect(source.catalogReads == 0)
        #expect(source.launches.isEmpty)
        #expect(activity.runs.first?.state == .stopped)
        #expect(activity.shown?.run.id == simulated)
        #expect(activity.benchActions.contains("showResult:\(second.id.uuidString)"))
        #expect(activity.benchActions.contains("openShortcuts"))
    }

    @Test("A menu opened earlier rechecks its visible destination and display preference before running")
    func staleLauncherAvailability() async throws {
        let source = Source()
        source.catalogEntries = [definition]
        var enabled = true
        var available = true
        let activity = ShortcutActivity(source: source, isEnabled: { enabled })
        _ = try await activity.loadCatalog()
        let menu = activity.makeRunMenu(canRun: { available })
        let index = try #require(menu.items.firstIndex { ($0.representedObject as? ShortcutDefinition)?.id == definition.id })
        #expect(menu.items[index].isEnabled)
        available = false
        menu.performActionForItem(at: index)
        #expect(source.launches.isEmpty)
        available = true
        enabled = false
        menu.performActionForItem(at: index)
        #expect(source.launches.isEmpty)
        enabled = true
        menu.performActionForItem(at: index)
        #expect(source.launches == [definition])
        source.finish(0)
    }

    @Test("Existing runs can be stopped and dismissed through their native menu while their display is disabled")
    func hiddenRunMenuControls() throws {
        let source = Source()
        var enabled = true
        let activity = ShortcutActivity(source: source, isEnabled: { enabled })
        let first = activity.run(definition)
        let second = activity.run(definition)
        enabled = false
        activity.settingsChanged()
        #expect(activity.shown == nil)
        let menu = activity.makeRunMenu(canRun: { false })
        let group = try #require(menu.items.first { ($0.representedObject as? UUID) == first }?.submenu)
        #expect(group.items.first { $0.identifier?.rawValue == "show-shortcut-activity" }?.isEnabled == false)
        let stop = try #require(group.items.firstIndex { $0.identifier?.rawValue == "stop-shortcut" })
        #expect(group.items[stop].isEnabled)
        group.performActionForItem(at: stop)
        #expect(source.handles[0].interrupts == 1)
        #expect(source.handles[1].interrupts == 0)
        source.finish(0, status: SIGINT, reason: .signal)
        group.performActionForItem(at: stop)
        #expect(source.handles[0].interrupts == 1)
        let refreshed = activity.makeRunMenu(canRun: { false })
        let ended = try #require(refreshed.items.first { ($0.representedObject as? UUID) == first }?.submenu)
        let done = try #require(ended.items.firstIndex { $0.identifier?.rawValue == "dismiss-shortcut" })
        ended.performActionForItem(at: done)
        #expect(activity.runs.map(\.id) == [second])
        source.finish(1)
    }

    @Test("The native result action targets its captured completed run without a visible notch")
    func hiddenResultMenuControl() throws {
        let activity = ShortcutActivity(source: Source(), isEnabled: { false })
        let first = ShortcutRun.fixture(state: .completed, withOutput: true)
        let second = ShortcutRun.fixture(state: .completed, ordinal: 1, withOutput: true)
        activity.bench([first, second], selected: second.id)
        let menu = activity.makeRunMenu(canRun: { false })
        let group = try #require(menu.items.first { ($0.representedObject as? UUID) == first.id }?.submenu)
        let result = try #require(group.items.firstIndex { $0.identifier?.rawValue == "show-shortcut-result" })
        group.performActionForItem(at: result)
        #expect(activity.benchActions == ["showResult:\(first.id.uuidString)"])
        #expect(activity.shown?.run.id == second.id)
    }

    @Test("Keyboard controls match visible enabled controls in their visual order")
    func controlStates() {
        func shown(_ state: ShortcutRun.State, output: Bool = false) -> ShortcutShown {
            .init(run: .fixture(state: state, withOutput: output))
        }
        #expect(ShortcutRunView.controls(for: shown(.running)) == [.activityFirst, .activitySecond])
        #expect(ShortcutRunView.controls(for: shown(.stopping)) == [.activityFirst])
        #expect(ShortcutRunView.controls(for: shown(.stopDelayed)) == [.activityFirst, .activitySecond])
        #expect(ShortcutRunView.controls(for: shown(.completed, output: true)) == [.activityFirst, .activityThird, .activitySecond])
        #expect(ShortcutRunView.controls(for: shown(.failed)) == [.activityFirst, .activitySecond])
    }

}
