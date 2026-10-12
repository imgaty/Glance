//
//  TileInteraction.swift
//  Glance
//
//  Created by Gaty on 12/10/2026.
//

import AppKit
import Quartz
import SwiftUI

/// What a tray tile does under the pointer, done by AppKit, which the notch's window, never the key
/// one, still gives every event to: the pointer coming and going, a click to copy, ⌘ or Shift to
/// choose several, a double-click to paste, a drag out with every chosen item in it, and the menu.
struct TileInteraction: NSViewRepresentable {
    let item: TrayItem
    let tray: Tray
    /// Whose chosen items a click with ⌘ or Shift changes, and a drag or the menu acts on: the
    /// notch's, or the history window's.
    let selector: TraySelecting
    /// In the history window, as in Finder, a click chooses an item; in the notch, it copies it.
    let clickSelects: Bool
    let hover: (Bool) -> Void

    func makeNSView(context: Context) -> TileInteractionView { TileInteractionView() }

    func updateNSView(_ view: TileInteractionView, context: Context) {
        view.item = item
        view.tray = tray
        view.selector = selector
        view.clickSelects = clickSelects
        view.hover = hover
    }
}

/// Items chosen together, with ⌘ or Shift, to copy, drag, share or remove at once.
@MainActor
protocol TraySelecting: AnyObject {
    var selection: Set<UUID> { get }
    func choose(_ id: UUID, toggling: Bool, extending: Bool)
    func deselect()
    /// Every chosen item, when the item is one of them; otherwise it alone.
    func targets(of item: TrayItem) -> [TrayItem]
}

extension Tray: TraySelecting {
    func choose(_ id: UUID, toggling: Bool, extending: Bool) {
        choose(id, toggling: toggling, extending: extending, in: nil)
    }
}

final class TileInteractionView: NSView, NSDraggingSource {
    var item: TrayItem?
    var tray: Tray?
    weak var selector: TraySelecting?
    var clickSelects = false
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
        guard let downAt, !dragged, let item, let tray, let selector else { return }
        let moved = hypot(event.locationInWindow.x - downAt.x, event.locationInWindow.y - downAt.y)
        guard moved > 4 else { return }
        dragged = true
        // A chosen item takes every chosen one with it; any other goes alone.
        if !selector.selection.contains(item.id) { selector.deselect() }
        var items: [NSDraggingItem] = []
        let side = Shelf.tile
        for target in selector.targets(of: item) {
            let picture = TrayThumbnails.cached(target) ?? TileDrag.picture(for: target)
            for writer in TileDrag.writers(for: target, in: tray) {
                let dragging = NSDraggingItem(pasteboardWriter: writer)
                // Fanned a little, as Finder fans files dragged together.
                let step = CGFloat(min(items.count, 4)) * 3
                dragging.setDraggingFrame(
                    CGRect(x: (bounds.width - side) / 2 + step, y: (bounds.height - side) / 2 - step, width: side, height: side),
                    contents: picture)
                items.append(dragging)
            }
        }
        guard !items.isEmpty else { return }
        tray.draggingOut = true
        let session = beginDraggingSession(with: items, event: event, source: self)
        session.animatesToStartingPositionsOnCancelOrFail = true
        session.draggingFormation = .pile
    }

    override func mouseUp(with event: NSEvent) {
        defer { downAt = nil }
        guard !dragged, let item, let tray, let selector else { return }
        let flags = event.modifierFlags
        if flags.contains(.command) {
            selector.choose(item.id, toggling: true, extending: false)
        } else if flags.contains(.shift) {
            selector.choose(item.id, toggling: false, extending: true)
        } else if event.clickCount >= 2 {
            tray.paste(item)
        } else if event.clickCount == 1, clickSelects {
            selector.choose(item.id, toggling: false, extending: false)
        } else if event.clickCount == 1 {
            selector.deselect()
            tray.copy(item)
            Opening.tap()
        }
    }

    override func rightMouseDown(with event: NSEvent) { showMenu(event) }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        guard let item else { return [] }
        // Onto the notch's AirDrop well, a copy; out to other apps, files go as Finder takes them,
        // and the tray's own copies are only ever copied out.
        if context == .withinApplication { return .copy }
        return item.kind == .files ? [.copy, .move, .link, .generic] : [.copy, .generic]
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        tray?.draggingOut = false
    }

    // MARK: The menu

    private func showMenu(_ event: NSEvent) {
        guard let item, let tray, let selector else { return }
        // Right-clicked outside the chosen items: the menu is for this one alone, chosen, as Finder
        // chooses a file it shows the menu for.
        if !selector.selection.contains(item.id) {
            clickSelects ? selector.choose(item.id, toggling: false, extending: false) : selector.deselect()
        }
        NSMenu.popUpContextMenu(TrayMenu(items: selector.targets(of: item), tray: tray).menu, with: event, for: self)
    }
}

/// What goes out with items dragged from the tray, and what they look like on the way.
@MainActor
enum TileDrag {
    /// Files as themselves, so Finder moves or copies them as it would its own; a picture as the file
    /// the tray keeps it in; text and links as they were copied.
    static func writers(for item: TrayItem, in tray: Tray) -> [NSPasteboardWriting] {
        switch item.kind {
        case .files: tray.urls(of: item).map { $0 as NSURL }
        case .image: item.files.first.map { [tray.file($0, of: item) as NSURL] } ?? []
        case .link, .text: tray.writers(for: item)
        }
    }

    /// Text and links are dragged as their card: a symbol on a gray tile, the size of the picture.
    static func picture(for item: TrayItem) -> NSImage {
        let side = Shelf.tile
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
}

/// The menu for items in the tray, laid out as Finder's is for files: opening and looking first,
/// then copying, then sending, then removing; each with its symbol, and named for how many items it
/// acts on.
@MainActor
final class TrayMenu: NSObject {
    let items: [TrayItem]
    let tray: Tray
    private(set) var menu = NSMenu()

    init(items: [TrayItem], tray: Tray) {
        self.items = items
        self.tray = tray
        super.init()
        let count = items.count
        let many = count > 1 ? " \(count) Items" : ""
        let single = count == 1 ? items.first : nil

        if let single, single.kind != .text {
            add(single.kind == .link ? "Open Link" : "Open", "arrow.up.forward.app", #selector(open))
        }
        if items.contains(where: { $0.kind == .files }) {
            add("Show in Finder", "folder", #selector(reveal))
        }
        if !TrayQuickLook.urls(for: items, in: tray).isEmpty { add("Quick Look" + many, "eye", #selector(quickLook)) }
        separate()
        add("Copy" + many, "doc.on.doc", #selector(copyItems))
        if single != nil, CGPreflightPostEventAccess() { add("Paste", "doc.on.clipboard", #selector(pasteItem)) }
        separate()
        let shared = tray.shareable(items)
        if !shared.isEmpty {
            if let airDrop = NSSharingService(named: .sendViaAirDrop), airDrop.canPerform(withItems: shared) {
                let item = menu.addItem(withTitle: "AirDrop", action: #selector(sendWithAirDrop), keyEquivalent: "")
                item.target = self
                item.image = airDrop.image
            }
            let share = NSSharingServicePicker(items: shared).standardShareMenuItem
            share.image = NSImage(systemSymbolName: "square.and.arrow.up", accessibilityDescription: nil)
            menu.addItem(share)
        }
        separate()
        add(count > 1 ? "Remove\(many) from Tray" : "Remove from Tray", "minus.circle", #selector(remove))
        // The menu holds its items' target weakly; it keeps this alive while it's up.
        objc_setAssociatedObject(menu, &Self.key, self, .OBJC_ASSOCIATION_RETAIN)
    }

    private static var key = 0

    private func add(_ title: String, _ symbol: String, _ action: Selector) {
        let item = menu.addItem(withTitle: title, action: action, keyEquivalent: "")
        item.target = self
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
    }

    /// A line between groups, never two together or one at either end.
    private func separate() {
        guard let last = menu.items.last, !last.isSeparatorItem else { return }
        menu.addItem(.separator())
    }

    @objc private func open() {
        guard let item = items.first else { return }
        switch item.kind {
        case .files: tray.urls(of: item).forEach { NSWorkspace.shared.open($0) }
        case .image: item.files.first.map { NSWorkspace.shared.open(tray.file($0, of: item)) }
        case .link: item.text.flatMap(URL.init(string:)).map { NSWorkspace.shared.open($0) }
        case .text: break
        }
    }

    @objc private func reveal() {
        NSWorkspace.shared.activateFileViewerSelecting(items.filter { $0.kind == .files }.flatMap(tray.urls))
    }

    @objc private func quickLook() { TrayQuickLook.shared.show(TrayQuickLook.urls(for: items, in: tray)) }
    @objc private func copyItems() { tray.copy(items) }
    @objc private func pasteItem() { items.first.map(tray.paste) }
    @objc private func sendWithAirDrop() { tray.airDrop(tray.shareable(items)) }
    @objc private func remove() { tray.remove(Set(items.map(\.id))) }
}

/// Quick Look, as Finder shows it, for what's in the tray: files and pictures. Glance takes charge of
/// the panel (see AppDelegate), and this gives it what to show.
@MainActor
final class TrayQuickLook: NSObject, QLPreviewPanelDataSource {
    static let shared = TrayQuickLook()
    private(set) var urls: [URL] = []

    static func urls(for items: [TrayItem], in tray: Tray) -> [URL] {
        items.flatMap { item -> [URL] in
            switch item.kind {
            case .files: tray.urls(of: item)
            case .image: item.files.first.map { [tray.file($0, of: item)] } ?? []
            case .link, .text: []
            }
        }
    }

    func show(_ urls: [URL]) {
        guard !urls.isEmpty, let panel = QLPreviewPanel.shared() else { return }
        self.urls = urls
        NSApp.activate()
        if panel.isVisible {
            panel.reloadData()
        } else {
            panel.makeKeyAndOrderFront(nil)
        }
        // With no window of Glance's in front to take charge of it, it's given its items directly.
        if panel.dataSource == nil {
            panel.dataSource = self
            panel.reloadData()
        }
    }

    nonisolated func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        MainActor.assumeIsolated { urls.count }
    }

    nonisolated func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> (any QLPreviewItem)! {
        MainActor.assumeIsolated { urls.indices.contains(index) ? urls[index] as NSURL : nil }
    }
}
