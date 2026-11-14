import Foundation
import Testing

@testable import Glance

@MainActor
@Suite("Compact activity status")
struct ActivityStatusPresentationTests {
    @Test("Running detached activities keep recognizable distinct identities")
    func runningIdentities() {
        let symbols = [ShortcutRunGlyph.symbol(for: .running), PrintJobGlyph.symbol(for: ActivityBench.printFixture()), MusicRecognitionGlyph.symbol(for: .recognizing)]
        #expect(Set(symbols).count == symbols.count)
    }

    @Test("Shortcut terminal states remain distinct without animation or a text wing")
    func shortcutStates() {
        let states: [ShortcutRun.State] = [.running, .stopping, .completed, .stopped, .failed]
        #expect(Set(states.map(ShortcutRunGlyph.symbol(for:))).count == states.count)
        let finished = ShortcutShown(run: .fixture(state: .completed))
        let detailed = ShortcutShown(run: .fixture(state: .failed), additionalRuns: 1)
        #expect(ShortcutRunView.height(restingHeight: 32, shown: finished) < ShortcutRunView.height(restingHeight: 32, shown: detailed))
    }

    @Test("Print attention states replace the normal printer mark without relying on color")
    func printStates() {
        let normal = ActivityBench.printFixture()
        var held = normal
        held.job.state = .held
        var unavailable = normal
        unavailable.sourceAvailable = false
        var failed = normal
        failed.cancellation = .failed
        let symbols = [normal, held, unavailable, failed].map(PrintJobGlyph.symbol(for:))
        #expect(Set(symbols).count == symbols.count)
    }

    @Test("Recognition success, failure and microphone denial differ from listening in minimal mode")
    func recognitionStates() {
        let states: [MusicRecognitionActivity.State] = [.recognizing, .match(.init(title: "Song", artist: nil)), .failure(.recognition), .denied, .cancelled]
        #expect(Set(states.map(MusicRecognitionGlyph.symbol(for:))).count == states.count)
    }
}
