//
//  StatusMenuTests.swift
//  GlanceTests
//
//  Created by Gaty on 04/11/2026.
//

import Testing

@testable import Glance

/// The menu bar menu with the keys alone: the arrows go through its rows as a menu's do, past
/// dimmed ones and round from end to end, and a letter goes to the next row it starts.
@MainActor
@Suite("Menu bar menu keys")
struct StatusMenuTests {
    private func rows(canCheck: Bool = true, rebuild: Bool = false) -> [StatusMenu.Row] {
        let state = StatusMenuState()
        state.canRebuild = rebuild
        return StatusMenu.rows(state, canCheck: canCheck)
    }

    @Test("Down from nothing goes to the switch, up from nothing to Quit")
    func fromNothing() {
        #expect(StatusMenu.step(rows(), from: nil, by: 1) == .toggle)
        #expect(StatusMenu.step(rows(), from: nil, by: -1) == .quit)
    }

    @Test("The arrows go row by row and round from end to end")
    func round() {
        let rows = rows()
        #expect(StatusMenu.step(rows, from: .toggle, by: 1) == .checkForUpdates)
        #expect(StatusMenu.step(rows, from: .checkForUpdates, by: 1) == .settings)
        #expect(StatusMenu.step(rows, from: .quit, by: 1) == .toggle)
        #expect(StatusMenu.step(rows, from: .toggle, by: -1) == .quit)
    }

    @Test("A dimmed row is passed over")
    func dimmed() {
        let rows = rows(canCheck: false)
        #expect(StatusMenu.step(rows, from: .toggle, by: 1) == .settings)
        #expect(StatusMenu.step(rows, from: .settings, by: -1) == .toggle)
    }

    @Test("Rebuild is among the rows only in builds from source")
    func rebuild() {
        #expect(!rows().map(\.action).contains(.rebuild))
        #expect(StatusMenu.step(rows(rebuild: true), from: .checkForUpdates, by: 1) == .rebuild)
    }

    @Test("A letter goes to the next row it starts, round from the end")
    func typing() {
        let rows = rows()
        #expect(StatusMenu.typed("q", in: rows, from: nil) == .quit)
        #expect(StatusMenu.typed("G", in: rows, from: nil) == .toggle)
        #expect(StatusMenu.typed("g", in: rows, from: .toggle) == .settings)
        #expect(StatusMenu.typed("g", in: rows, from: .settings) == .toggle)
        #expect(StatusMenu.typed("x", in: rows, from: nil) == nil)
        #expect(StatusMenu.typed("c", in: self.rows(canCheck: false), from: nil) == nil)
    }
}
