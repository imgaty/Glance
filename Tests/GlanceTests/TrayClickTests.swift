//
//  TrayClickTests.swift
//  GlanceTests
//
//  Created by Gaty on 13/10/2026.
//

import AppKit
import SwiftUI
import Testing

@testable import Glance

/// The tray in the open notch, drawn for real in a window: every point of every item takes the
/// click for that item, and clicks choose as Finder does.
@MainActor
@Suite("Clicking the tray", .serialized)
struct TrayClickTests {
    private func eventually(_ condition: () -> Bool) async -> Bool {
        for _ in 0..<60 {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(50))
        }
        return condition()
    }

    /// A tray of its own with four notes, open in a notch in a window off the screen, with a song
    /// playing, so the player's lyrics button, under the tray, is live too.
    private func notch() async throws -> (Tray, NotchModel, NSView, NSWindow) {
        let tray = Tray(
            folder: FileManager.default.temporaryDirectory.appending(path: "GlanceTrayClicks-\(UUID().uuidString)"),
            pasteboard: NSPasteboard(name: .init("dev.vibe.Glance.tests.\(UUID().uuidString)")))
        for text in ["four", "three", "two", "one"] {
            let board = NSPasteboard(name: .init("dev.vibe.Glance.tests.\(UUID().uuidString)"))
            board.clearContents()
            board.setString(text, forType: .string)
            tray.add(try #require(TrayCapture.make(from: board, kept: true)))
        }
        let model = NotchModel(closedSize: CGSize(width: 185, height: 32), layout: .top, hasCamera: true)
        model.songPlaying = true
        model.page = .tray
        model.state = .open
        let host = NotchHostingView(rootView: NotchView(model: model, display: "tests").environment(\.tray, tray).environmentObject(NowPlaying()))
        let window = NSWindow(
            contentRect: CGRect(x: -4000, y: -4000, width: 700, height: 260), styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = host
        #expect(await eventually { model.controlFrames.filter { $0.size == Shelf.tile }.count == 4 })
        // The window is handed back too: let go of, it would leave the notch with nowhere to be.
        return (tray, model, host, window)
    }

    /// What a click at a point, in the notch's points, lands on.
    private func target(_ point: CGPoint, in host: NSView) -> TileInteractionView? {
        host.hitTest(host.convert(point, to: host.superview)) as? TileInteractionView
    }

    /// A click on a tile, as AppKit hands it to the view under the pointer.
    private func click(_ view: TileInteractionView, flags: NSEvent.ModifierFlags = []) {
        let location = view.convert(CGPoint(x: view.bounds.midX, y: view.bounds.midY), to: nil)
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            let event = NSEvent.mouseEvent(
                with: type, location: location, modifierFlags: flags, timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: view.window?.windowNumber ?? 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
            type == .leftMouseDown ? view.mouseDown(with: event) : view.mouseUp(with: event)
        }
    }

    @Test("Every point of every item takes the click for that item, nothing over it")
    func everyPointLands() async throws {
        let (tray, model, host, window) = try await notch()
        defer { withExtendedLifetime(window) {} }
        let tiles = model.controlFrames.filter { $0.size == Shelf.tile }.sorted { $0.minX < $1.minX }
        for (index, tile) in tiles.enumerated() {
            for y in stride(from: tile.minY + 1, to: tile.maxY, by: 6) {
                for x in stride(from: tile.minX + 1, to: tile.maxX, by: 6) {
                    #expect(target(CGPoint(x: x, y: y), in: host)?.item?.id == tray.items[index].id, "item \(index) at \(x), \(y)")
                }
            }
        }
    }

    @Test("A click chooses the item alone, and again keeps it; ⌘ adds one or takes it out")
    func clicksChoose() async throws {
        let (tray, model, host, window) = try await notch()
        defer { withExtendedLifetime(window) {} }
        let tiles = model.controlFrames.filter { $0.size == Shelf.tile }.sorted { $0.minX < $1.minX }
        let views = try tiles.map { try #require(target(CGPoint(x: $0.midX, y: $0.midY), in: host)) }
        let ids = tray.items.map(\.id)
        for (index, view) in views.enumerated() {
            click(view)
            #expect(tray.selection == [ids[index]])
            click(view)
            #expect(tray.selection == [ids[index]])
        }
        click(views[0])
        click(views[2], flags: .command)
        #expect(tray.selection == [ids[0], ids[2]])
        click(views[2], flags: .command)
        #expect(tray.selection == [ids[0]])
    }
}
