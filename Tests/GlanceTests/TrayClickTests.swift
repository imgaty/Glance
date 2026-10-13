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

    /// A tray of its own with `count` notes, open in a notch in a window off the screen, put
    /// together as the notch's own window is: the notch's view, which decides where clicks go,
    /// around SwiftUI's. A song plays, so the player's lyrics button, under the tray, is live too.
    private func notch(count: Int = 4) async throws -> (Tray, NotchModel, NotchEventView, NSWindow) {
        let tray = Tray(
            folder: FileManager.default.temporaryDirectory.appending(path: "GlanceTrayClicks-\(UUID().uuidString)"),
            pasteboard: NSPasteboard(name: .init("dev.vibe.Glance.tests.\(UUID().uuidString)")))
        for index in (0..<count).reversed() {
            let board = NSPasteboard(name: .init("dev.vibe.Glance.tests.\(UUID().uuidString)"))
            board.clearContents()
            board.setString("Note \(index)", forType: .string)
            tray.add(try #require(TrayCapture.make(from: board, kept: true)))
        }
        let model = NotchModel(closedSize: CGSize(width: 185, height: 32), layout: .top, hasCamera: true)
        model.songPlaying = true
        model.trayItems = count
        model.page = .tray
        model.state = .open
        let size = CGSize(width: 900, height: 260)
        let events = NotchEventView(frame: CGRect(origin: .zero, size: size))
        let host = NotchHostingView(rootView: NotchView(model: model, display: "tests").environment(\.tray, tray).environmentObject(NowPlaying()))
        host.frame = events.bounds
        events.addSubview(host)
        events.passesThrough = { point in model.state == .open && model.controlFrames.contains { $0.contains(point) } }
        let window = NSWindow(
            contentRect: CGRect(origin: CGPoint(x: -4000, y: -4000), size: size), styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = events
        #expect(await eventually { model.controlFrames.filter { $0.size == Shelf.tile }.count >= min(count, 7) })
        // The window is handed back too: let go of, it would leave the notch with nowhere to be.
        return (tray, model, events, window)
    }

    /// What a click at a point, in the notch's points, lands on.
    private func target(_ point: CGPoint, in events: NotchEventView) -> NSView? {
        events.hitTest(events.convert(point, to: events.superview))
    }

    /// The items in sight, left to right.
    private func tiles(_ model: NotchModel, width: CGFloat) -> [CGRect] {
        let left = (900 - width) / 2
        return model.controlFrames.filter { $0.size == Shelf.tile && $0.minX >= left && $0.maxX <= left + width }.sorted { $0.minX < $1.minX }
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

    @Test("Every point of every item in sight takes the click for that item", arguments: [4, 12])
    func everyPointLands(count: Int) async throws {
        let (tray, model, events, window) = try await notch(count: count)
        defer { withExtendedLifetime(window) {} }
        for tile in tiles(model, width: model.trayWidth) {
            let item = try #require((target(CGPoint(x: tile.midX, y: tile.midY), in: events) as? TileInteractionView)?.item)
            for y in stride(from: tile.minY + 1, to: tile.maxY, by: 6) {
                for x in stride(from: tile.minX + 1, to: tile.maxX, by: 6) {
                    #expect((target(CGPoint(x: x, y: y), in: events) as? TileInteractionView)?.item?.id == item.id, "at \(x), \(y)")
                }
            }
            #expect(tray.items.contains(item))
        }
    }

    @Test("On the player, a click where the tray's items were goes to the player, never to them")
    func playerPage() async throws {
        let (_, model, events, window) = try await notch()
        defer { withExtendedLifetime(window) {} }
        let tile = try #require(tiles(model, width: model.trayWidth).first)
        model.page = .player
        #expect(await eventually { !(target(CGPoint(x: tile.midX, y: tile.midY), in: events) is TileInteractionView) })
    }

    @Test("A click chooses the item alone, and again keeps it; ⌘ adds one or takes it out")
    func clicksChoose() async throws {
        let (tray, model, events, window) = try await notch()
        defer { withExtendedLifetime(window) {} }
        let views = try tiles(model, width: model.trayWidth).map {
            try #require(target(CGPoint(x: $0.midX, y: $0.midY), in: events) as? TileInteractionView)
        }
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

    @Test("The tray is as wide as its items, from the player's width up to seven items, then scrolls")
    func width() {
        let model = NotchModel(closedSize: CGSize(width: 185, height: 32), layout: .top, hasCamera: true)
        #expect(model.trayWidth == model.openSize.width)
        model.trayItems = 5
        #expect(model.trayWidth == Shelf.width(count: 5))
        model.trayItems = 30
        #expect(model.trayWidth == Shelf.width(count: 7))
        model.page = .tray
        model.state = .open
        #expect(model.metrics.bodyWidth == Shelf.width(count: 7))
    }
}
