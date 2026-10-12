//
//  TileInteraction.swift
//  Glance
//
//  Created by Gaty on 12/10/2026.
//

import AppKit
import SwiftUI

/// What a tray tile does under the pointer, done by AppKit, which the notch's window, never the key
/// one, still gives every event to: the pointer coming and going, a click to copy, a double-click to
/// paste, a drag out with every file in it, and the menu.
struct TileInteraction: NSViewRepresentable {
    let item: TrayItem
    let tray: Tray
    let hover: (Bool) -> Void

    func makeNSView(context: Context) -> TileInteractionView { TileInteractionView() }

    func updateNSView(_ view: TileInteractionView, context: Context) {
        view.item = item
        view.tray = tray
        view.hover = hover
    }
}

final class TileInteractionView: NSView, NSDraggingSource {
    var item: TrayItem?
    var tray: Tray?
    var hover: ((Bool) -> Void)?
    private var downAt: NSPoint?
    private var dragged = false

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
    }

    override func mouseEntered(with event: NSEvent) { hover?(true) }
    override func mouseExited(with event: NSEvent) { hover?(false) }

    override func mouseDown(with event: NSEvent) {
        if event.modifierFlags.contains(.control) { return showMenu(event) }
        downAt = event.locationInWindow
        dragged = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard let downAt, !dragged, let item, let tray else { return }
        let moved = hypot(event.locationInWindow.x - downAt.x, event.locationInWindow.y - downAt.y)
        guard moved > 4 else { return }
        dragged = true
        let writers = dragWriters(for: item, in: tray)
        guard !writers.isEmpty else { return }
        let picture = TrayThumbnails.cached(item) ?? fallbackPicture(for: item)
        let side = Shelf.picture
        let items = writers.enumerated().map { index, writer in
            let dragging = NSDraggingItem(pasteboardWriter: writer)
            // Fanned a little, as Finder fans files dragged together.
            let frame = CGRect(
                x: (bounds.width - side) / 2 + CGFloat(index) * 3, y: bounds.height - side - 4 - CGFloat(index) * 3, width: side,
                height: side)
            dragging.setDraggingFrame(frame, contents: picture)
            return dragging
        }
        let session = beginDraggingSession(with: items, event: event, source: self)
        session.animatesToStartingPositionsOnCancelOrFail = true
        session.draggingFormation = .pile
    }

    override func mouseUp(with event: NSEvent) {
        defer { downAt = nil }
        guard !dragged, let item, let tray else { return }
        if event.clickCount >= 2 {
            tray.paste(item)
        } else if event.clickCount == 1 {
            tray.copy(item)
            Opening.tap()
        }
    }

    override func rightMouseDown(with event: NSEvent) { showMenu(event) }

    // MARK: Dragging out

    /// Files are dragged as themselves, so Finder moves or copies them as it would its own; a
    /// picture as the file the tray keeps it in; text and links as they were copied.
    private func dragWriters(for item: TrayItem, in tray: Tray) -> [NSPasteboardWriting] {
        switch item.kind {
        case .files: tray.urls(of: item).map { $0 as NSURL }
        case .image: item.files.first.map { [tray.file($0, of: item) as NSURL] } ?? []
        case .link, .text: tray.writers(for: item)
        }
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        guard context == .outsideApplication, let item else { return [] }
        // The tray's own copies are only ever copied out; files go as Finder takes them.
        return item.kind == .files ? [.copy, .move, .link, .generic] : [.copy, .generic]
    }

    /// Text and links are dragged as their card: a symbol on a gray tile, the size of the picture.
    private func fallbackPicture(for item: TrayItem) -> NSImage {
        let side = Shelf.picture
        let symbol = NSImage(systemSymbolName: item.kind == .link ? "link" : "text.alignleft", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 20, weight: .medium).applying(.init(paletteColors: [.white])))
        return NSImage(size: CGSize(width: side, height: side), flipped: false) { rect in
            NSColor(white: 0.28, alpha: 0.95).setFill()
            NSBezierPath(roundedRect: rect, xRadius: 10, yRadius: 10).fill()
            if let symbol {
                symbol.draw(
                    in: CGRect(
                        x: (side - symbol.size.width) / 2, y: (side - symbol.size.height) / 2, width: symbol.size.width,
                        height: symbol.size.height))
            }
            return true
        }
    }

    // MARK: The menu

    private func showMenu(_ event: NSEvent) {
        guard let item, let tray else { return }
        NSMenu.popUpContextMenu(TileMenu(item: item, tray: tray).menu, with: event, for: self)
    }
}

/// A tile's menu, as Finder's and Spotlight's put theirs: opening first, then copying and sharing,
/// then removing.
@MainActor
private final class TileMenu: NSObject {
    let item: TrayItem
    let tray: Tray
    private(set) var menu = NSMenu()

    init(item: TrayItem, tray: Tray) {
        self.item = item
        self.tray = tray
        super.init()
        let urls = tray.urls(of: item)
        switch item.kind {
        case .files:
            add("Open", #selector(open))
            add("Show in Finder", #selector(reveal))
        case .image:
            add("Open", #selector(open))
        case .link:
            add("Open Link", #selector(open))
        case .text:
            break
        }
        if menu.numberOfItems > 0 { menu.addItem(.separator()) }
        add("Copy", #selector(copyItem))
        if CGPreflightPostEventAccess() { add("Paste", #selector(pasteItem)) }
        let shared: [Any] =
            switch item.kind {
            case .files: urls
            case .image: item.files.first.map { [tray.file($0, of: item)] } ?? []
            case .link: item.text.flatMap(URL.init(string:)).map { [$0] } ?? []
            case .text: [item.text ?? ""]
            }
        if !shared.isEmpty { menu.addItem(NSSharingServicePicker(items: shared).standardShareMenuItem) }
        menu.addItem(.separator())
        add("Remove from Tray", #selector(remove))
        add("Clear Tray", #selector(clear))
        // The menu holds its items' target weakly; it's kept alive by the menu while it's up.
        objc_setAssociatedObject(menu, &Self.key, self, .OBJC_ASSOCIATION_RETAIN)
    }

    private static var key = 0

    private func add(_ title: String, _ action: Selector) {
        menu.addItem(withTitle: title, action: action, keyEquivalent: "").target = self
    }

    @objc private func open() {
        switch item.kind {
        case .files: tray.urls(of: item).forEach { NSWorkspace.shared.open($0) }
        case .image: item.files.first.map { NSWorkspace.shared.open(tray.file($0, of: item)) }
        case .link: item.text.flatMap(URL.init(string:)).map { NSWorkspace.shared.open($0) }
        case .text: break
        }
    }

    @objc private func reveal() { NSWorkspace.shared.activateFileViewerSelecting(tray.urls(of: item)) }
    @objc private func copyItem() { tray.copy(item) }
    @objc private func pasteItem() { tray.paste(item) }
    @objc private func remove() { tray.remove(item.id) }
    @objc private func clear() { tray.clear() }
}
