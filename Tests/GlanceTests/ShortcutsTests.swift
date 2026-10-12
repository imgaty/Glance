//
//  ShortcutsTests.swift
//  GlanceTests
//
//  Created by Gaty on 12/10/2026.
//

import Carbon.HIToolbox
import Testing

@testable import Glance

/// The keyboard shortcuts: Control-Option-Command and a number, so no app loses its own ⌘ shortcuts.
@MainActor
@Suite("Keyboard shortcuts")
struct ShortcutsTests {
    @Test("Every shortcut takes Control, Option and Command")
    func modifiers() {
        #expect(Shortcuts.modifiers == UInt32(controlKey | optionKey | cmdKey))
    }

    @Test("The player is ⌃⌥⌘1")
    func music() {
        #expect(Shortcuts.Action.music.key == kVK_ANSI_1)
        #expect(Shortcuts.Action.music.symbols == "⌃⌥⌘1")
    }

    @Test("No two shortcuts share a key")
    func distinctKeys() {
        let keys = Shortcuts.Action.allCases.map(\.key)
        #expect(Set(keys).count == keys.count)
    }

    @Test("Glance's hotkeys carry its own mark, GLNC")
    func signature() {
        #expect(Shortcuts.signature == 0x474C_4E43)
    }
}
