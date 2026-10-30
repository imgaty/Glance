//
//  LyricsSearchTests.swift
//  GlanceTests
//
//  Created by Gaty on 30/10/2026.
//

import Foundation
import Testing

@testable import Glance

/// Looking for a song's lyrics several ways at once, and never for long.
@Suite("Lyrics search")
struct LyricsSearchTests {
    typealias Answer = LyricsStore.Answer

    static func after(_ seconds: Double, _ answer: Answer) -> @Sendable () async -> Answer {
        {
            try? await Task.sleep(for: .seconds(seconds))
            return answer
        }
    }

    /// Nothing that finishes: it only ends when it's cancelled.
    static let never: @Sendable () async -> Answer = {
        try? await Task.sleep(for: .seconds(3600))
        return .unreachable
    }

    static func isFound(_ answer: Answer, _ words: [String]) -> Bool {
        if case .found(.plain(let lines)) = answer { lines == words } else { false }
    }

    @Test("A way of asking that never answers holds nothing up: the first to find lyrics shows")
    func slowQuery() async {
        let start = Date.now
        let answer = await LyricsStore.firstAnswer([Self.after(0.01, .nothing), Self.after(0.02, .found(.plain(["Found"]))), Self.never], patience: 5)
        #expect(Self.isFound(answer, ["Found"]))
        #expect(Date.now.timeIntervalSince(start) < 1)
    }

    @Test("It gives up after its patience, however long LRCLIB takes")
    func givesUp() async {
        let start = Date.now
        let answer = await LyricsStore.firstAnswer([Self.never, Self.never, Self.never], patience: 0.1)
        if case .unreachable = answer {} else { Issue.record("expected unreachable") }
        #expect(Date.now.timeIntervalSince(start) < 1)
    }

    @Test("The better way of asking wins when both find lyrics, if it answers in time")
    func order() async {
        let answer = await LyricsStore.firstAnswer([Self.after(0.05, .found(.plain(["Best"]))), Self.after(0, .found(.plain(["Other"])))], patience: 5)
        #expect(Self.isFound(answer, ["Best"]))
        // What's been found is taken when the better way runs out of time.
        let late = await LyricsStore.firstAnswer([Self.never, Self.after(0, .found(.plain(["Other"])))], patience: 0.1)
        #expect(Self.isFound(late, ["Other"]))
    }

    @Test("Paused, a song stays where it's shown, unless the report says it was moved")
    func pausedPosition() {
        // Players report where they were a moment ago: the lyrics don't step back for it.
        #expect(NowPlaying.pausedPosition(reported: 41.2, shown: 42) == 42)
        #expect(NowPlaying.pausedPosition(reported: 42.6, shown: 42) == 42)
        // Moved while paused.
        #expect(NowPlaying.pausedPosition(reported: 90, shown: 42) == 90)
        #expect(NowPlaying.pausedPosition(reported: 0, shown: 42) == 0)
    }

    @Test("Nothing found is told from LRCLIB not answering")
    func nothing() async {
        if case .nothing = await LyricsStore.firstAnswer([Self.after(0, .unreachable), Self.after(0, .nothing)], patience: 5) {} else {
            Issue.record("expected nothing")
        }
        if case .unreachable = await LyricsStore.firstAnswer([Self.after(0, .unreachable)], patience: 5) {} else {
            Issue.record("expected unreachable")
        }
    }
}
