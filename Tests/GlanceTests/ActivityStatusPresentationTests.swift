import Foundation
import SwiftUI
import Testing

@testable import Glance

@MainActor
@Suite("Compact activity status")
struct ActivityStatusPresentationTests {
    @Test("A running shortcut's ring goes round, and the notch keeps one width however it stands")
    func runningIdentities() {
        #expect(ShortcutRunGlyph.status(for: .running).spinning)
        // Shortcuts' own measures, the same however the run stands.
        #expect(
            ShortcutRunMark.wing(for: ShortcutShown(run: .fixture(state: .running)), restingHeight: 32)
                == ShortcutRunMark.wing(for: ShortcutShown(run: .fixture(state: .failed)), restingHeight: 32))
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

    @Test("Listening says it's still at it, as the iPhone does, and the notch holds still as the words change")
    func recognitionStates() {
        #expect(MusicRecognitionActivityView.listening(after: 0) == "Listening…")
        #expect(MusicRecognitionActivityView.listening(after: ShazamLook.workingAfter) == "Working on it…")
        #expect(MusicRecognitionActivityView.listening(after: ShazamLook.tryingAfter + 5) == "Still trying…")
        #expect(MusicRecognitionActivityView.detail(for: .recognizing).isEmpty)
        #expect(MusicRecognitionCompactView.wing(for: .recognizing, restingHeight: 32) == MusicRecognitionCompactView.wing(for: .noMatch, restingHeight: 32))
    }
}
