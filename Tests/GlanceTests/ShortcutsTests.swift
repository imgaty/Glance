//
//  ShortcutsTests.swift
//  GlanceTests
//
//  Created by Gaty on 12/10/2026.
//

import AppKit
import Carbon.HIToolbox
import Foundation
import Testing

@testable import Glance

/// The keyboard shortcuts: ⇧⌘1 and ⇧⌘2 out of the box, any other a person chooses, kept as they chose it.
@MainActor
@Suite("Keyboard shortcuts")
struct ShortcutsTests {
    @Test("The player opens with ⇧⌘1 out of the box")
    func standard() {
        let combo = Shortcuts.Action.music.standard
        #expect(combo.keyCode == UInt32(kVK_ANSI_1))
        #expect(combo.modifiers == UInt32(shiftKey | cmdKey))
        #expect(combo.symbols == "⇧⌘1")
    }

    @Test("The tray opens with ⇧⌘2 out of the box")
    func trayStandard() {
        let combo = Shortcuts.Action.tray.standard
        #expect(combo.keyCode == UInt32(kVK_ANSI_2))
        #expect(combo.modifiers == UInt32(shiftKey | cmdKey))
        #expect(combo.symbols == "⇧⌘2")
        #expect(Shortcuts.Action.tray.defaultsKey == Preferences.shortcutTray)
    }

    @Test("Shortcuts are written as Apple writes them: ⌃⌥⇧⌘, then the key")
    func symbols() {
        let all = KeyCombo(keyCode: UInt32(kVK_ANSI_K), modifiers: UInt32(cmdKey | shiftKey | optionKey | controlKey), key: "K")
        #expect(all.symbols == "⌃⌥⇧⌘K")
    }

    @Test("A shortcut needs Command, Option or Control; Shift alone won't do")
    func validity() {
        #expect(KeyCombo(keyCode: 0, modifiers: UInt32(cmdKey), key: "A").isValid)
        #expect(KeyCombo(keyCode: 0, modifiers: UInt32(optionKey), key: "A").isValid)
        #expect(!KeyCombo(keyCode: 0, modifiers: UInt32(shiftKey), key: "A").isValid)
        #expect(!KeyCombo(keyCode: 0, modifiers: 0, key: "A").isValid)
    }

    @Test("Modifier keys held become the hotkeys' own flags")
    func modifiers() {
        #expect(KeyCombo.modifiers(of: [.command, .shift]) == UInt32(cmdKey | shiftKey))
        #expect(KeyCombo.modifiers(of: [.control, .option]) == UInt32(controlKey | optionKey))
        #expect(KeyCombo.modifiers(of: [.capsLock, .function]) == 0)
    }

    @Test("A chosen shortcut is kept as it was chosen")
    func kept() throws {
        let combo = KeyCombo(keyCode: UInt32(kVK_ANSI_M), modifiers: UInt32(controlKey | optionKey), key: "M")
        let data = try JSONEncoder().encode(combo)
        #expect(try JSONDecoder().decode(KeyCombo.self, from: data) == combo)
    }

    @Test("Keys that print nothing go by the names menus give them")
    func specialKeys() {
        #expect(KeyCombo.name(ofKey: UInt16(kVK_Space)) == "Space")
        #expect(KeyCombo.name(ofKey: UInt16(kVK_Return)) == "↩")
        #expect(KeyCombo.name(ofKey: UInt16(kVK_F5)) == "F5")
    }

    @Test("Glance's hotkeys carry its own mark, GLNC")
    func signature() {
        #expect(Shortcuts.signature == 0x474C_4E43)
    }
}
