//
//  PlayerKeysTests.swift
//  GlanceTests
//
//  Created by Gaty on 04/11/2026.
//

import Carbon.HIToolbox
import Testing

@testable import Glance

/// The open player with the keys alone: Tab goes from control to control, Space or Return presses
/// the one it's on, and with none, the keys work the song as they always did.
@MainActor
@Suite("Player keys")
struct PlayerKeysTests {
    private let all: [PlayerControl] = [.cover, .lyrics, .position, .left, .previous, .playPause, .next, .right]

    private func keys(_ usable: [PlayerControl]? = nil) -> PlayerKeys {
        let keys = PlayerKeys()
        keys.usable = usable ?? all
        return keys
    }

    private func tab(_ keys: PlayerKeys, times: Int = 1, shift: Bool = false) {
        for _ in 0..<times { _ = keys.typed(key: kVK_Tab, shift: shift, hasMedia: true) }
    }

    @Test("Tab starts at the first control, Shift-Tab at the last")
    func start() {
        let forward = keys()
        tab(forward)
        #expect(forward.focus == .cover)
        let backward = keys()
        tab(backward, shift: true)
        #expect(backward.focus == .right)
    }

    @Test("Tab goes through every control and round from end to end")
    func round() {
        let keys = keys()
        var visited: [PlayerControl] = []
        for _ in all.indices {
            tab(keys)
            if let focus = keys.focus { visited.append(focus) }
        }
        #expect(visited == all)
        tab(keys)
        #expect(keys.focus == .cover)
        tab(keys, shift: true)
        #expect(keys.focus == .right)
    }

    @Test("A control that can't be used is passed over, and the ring leaves one that stops being usable")
    func unusable() {
        let keys = keys([.previous, .playPause, .next, .right])
        tab(keys, times: 4)
        #expect(keys.focus == .right)
        keys.usable = [.previous, .playPause, .next]
        #expect(keys.focus == nil)
    }

    @Test("With nothing to go to, Tab has no use")
    func nothing() {
        let keys = keys([])
        #expect(keys.typed(key: kVK_Tab, shift: false, hasMedia: false) == .none)
        #expect(keys.focus == nil)
    }

    @Test("With no ring, the keys work the song")
    func withoutRing() {
        let keys = keys()
        #expect(keys.typed(key: kVK_Space, shift: false, hasMedia: true) == .playPause)
        #expect(keys.typed(key: kVK_LeftArrow, shift: false, hasMedia: true) == .previous)
        #expect(keys.typed(key: kVK_RightArrow, shift: false, hasMedia: true) == .next)
        #expect(keys.typed(key: kVK_Return, shift: false, hasMedia: true) == .none)
        #expect(keys.typed(key: kVK_Space, shift: false, hasMedia: false) == .none)
    }

    @Test("Space and Return press the control with the ring, each press counted once")
    func pressing() {
        let keys = keys()
        tab(keys)
        #expect(keys.typed(key: kVK_Space, shift: false, hasMedia: true) == .pressed)
        #expect(keys.typed(key: kVK_Return, shift: false, hasMedia: true) == .pressed)
        #expect(keys.typed(key: kVK_ANSI_KeypadEnter, shift: false, hasMedia: true) == .pressed)
        #expect(keys.presses == 3)
    }

    @Test("On the progress bar, the arrows move through the song and Space still plays or pauses")
    func progressBar() {
        let keys = keys()
        tab(keys, times: 3)
        #expect(keys.focus == .position)
        #expect(keys.typed(key: kVK_LeftArrow, shift: false, hasMedia: true) == .seekBack)
        #expect(keys.typed(key: kVK_RightArrow, shift: false, hasMedia: true) == .seekAhead)
        #expect(keys.typed(key: kVK_Space, shift: false, hasMedia: true) == .playPause)
        #expect(keys.typed(key: kVK_Return, shift: false, hasMedia: true) == .none)
        #expect(keys.presses == 0)
    }

    @Test("Off the progress bar, the arrows still go to the song before or after")
    func arrowsElsewhere() {
        let keys = keys()
        tab(keys)
        #expect(keys.typed(key: kVK_LeftArrow, shift: false, hasMedia: true) == .previous)
        #expect(keys.typed(key: kVK_RightArrow, shift: false, hasMedia: true) == .next)
    }

    @Test("A click or the notch closing takes the ring away")
    func clearing() {
        let keys = keys()
        tab(keys)
        keys.clear()
        #expect(keys.focus == nil)
        #expect(keys.typed(key: kVK_Space, shift: false, hasMedia: true) == .playPause)
    }
}
