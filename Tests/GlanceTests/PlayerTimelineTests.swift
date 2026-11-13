//
//  PlayerTimelineTests.swift
//  GlanceTests
//
//  Created by Gaty on 13/11/2026.
//

import Carbon.HIToolbox
import Testing

@testable import Glance

@MainActor
@Suite("Player timeline availability")
struct PlayerTimelineTests {
    @Test("Unknown and invalid durations have no seekable timeline", arguments: [0.0, -1, .infinity, -.infinity, .nan])
    func unknownDuration(_ duration: Double) {
        #expect(!NowPlayingView.timelineAvailable(hasMedia: true, duration: duration, djTalking: false))
    }

    @Test("A duration only belongs to loaded media, and not to the DJ's speech")
    func context() {
        #expect(NowPlayingView.timelineAvailable(hasMedia: true, duration: 180, djTalking: false))
        #expect(!NowPlayingView.timelineAvailable(hasMedia: false, duration: 180, djTalking: false))
        #expect(!NowPlayingView.timelineAvailable(hasMedia: true, duration: 180, djTalking: true))
    }

    @Test("Losing the duration clears the seek focus and leaves playback reachable")
    func durationChanges() {
        let keys = PlayerKeys()
        keys.usable = [.position, .playPause]
        keys.focus(on: .position)
        let timed = NowPlayingView.timelineAvailable(hasMedia: true, duration: 0, djTalking: false)
        keys.usable = (timed ? [.position] : []) + [.playPause]
        #expect(keys.focus == nil)
        #expect(keys.typed(key: kVK_Tab, shift: false, hasMedia: true) == .moved)
        #expect(keys.focus == .playPause)
        #expect(keys.typed(key: kVK_Space, shift: false, hasMedia: true) == .pressed)
    }
}
