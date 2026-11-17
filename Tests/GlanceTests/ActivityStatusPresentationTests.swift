import Foundation
import SwiftUI
import Testing

@testable import Glance

@MainActor
@Suite("Compact activity status")
struct ActivityStatusPresentationTests {
    @Test("Each task shows its own app beside the camera, and its ring says how it stands")
    func runningIdentities() {
        #expect(Set([PrintJobView.app, ShortcutRunView.app]).count == 2)
        #expect(ShortcutRunGlyph.status(for: .running).spinning)
        #expect(MusicRecognitionGlyph.status(for: .recognizing).spinning)
        #expect(PrintJobGlyph.status(for: ActivityBench.printFixture()) == .counting(ActivityBench.printFixture().job.progress!.fraction))
        // Beside the camera the notch keeps one width however the task stands: no words to fit.
        let wing = TaskCompactMark<EmptyView>.wing(restingHeight: 32)
        // Shortcuts' own measures, the same however the run stands.
        #expect(
            ShortcutRunMark.wing(for: ShortcutShown(run: .fixture(state: .running)), restingHeight: 32)
                == ShortcutRunMark.wing(for: ShortcutShown(run: .fixture(state: .failed)), restingHeight: 32))
        #expect(MusicRecognitionCompactView.wing(for: .noMatch, restingHeight: 32) == wing)
    }

    @Test("Shortcut terminal states remain distinct without animation or a text wing")
    func shortcutStates() {
        #expect(ShortcutRunGlyph.status(for: .stopping) == .working)
        #expect(ShortcutRunGlyph.status(for: .completed) == .done)
        #expect(ShortcutRunGlyph.status(for: .stopped) == .stopped)
        #expect(ShortcutRunGlyph.status(for: .endedAfterStop) == .stopped)
        #expect(ShortcutRunGlyph.status(for: .failed) == .failed)
        let finished = ShortcutShown(run: .fixture(state: .completed))
        let detailed = ShortcutShown(run: .fixture(state: .failed), additionalRuns: 1)
        // One row as tall as the Timer's either way; what doesn't fit is said under the pointer.
        #expect(ShortcutRunView.height(restingHeight: 32) == TimerLayout.tallHeight(32))
        #expect(ShortcutRunView.explanation(for: detailed).count > ShortcutRunView.explanation(for: finished).count)
    }

    @Test("Print states: the ring fills, stands still on hold, checks when printed and warns when unread")
    func printStates() {
        let normal = ActivityBench.printFixture()
        var held = normal
        held.job.state = .held
        #expect(PrintJobGlyph.status(for: held).outcome == .working)
        #expect(!PrintJobGlyph.status(for: held).spinning)
        var queued = normal
        queued.job.state = .queued
        #expect(PrintJobGlyph.status(for: queued).spinning)
        var unavailable = normal
        unavailable.sourceAvailable = false
        #expect(PrintJobGlyph.status(for: unavailable).outcome == .failed)
        var printed = normal
        printed.job.state = .completed
        #expect(PrintJobGlyph.status(for: printed) == .done)
        #expect(PrintJobGlyph.word(for: printed) == "Complete")
    }

    @Test("Recognition success, failure and canceling differ from listening")
    func recognitionStates() {
        #expect(MusicRecognitionGlyph.status(for: .match(.init(title: "Song", artist: nil))) == .done)
        #expect(MusicRecognitionGlyph.status(for: .failure(.recognition)) == .failed)
        #expect(MusicRecognitionGlyph.status(for: .denied) == .failed)
        #expect(MusicRecognitionGlyph.status(for: .noMatch) == .failed)
        #expect(MusicRecognitionGlyph.status(for: .cancelled) == .stopped)
    }
}
