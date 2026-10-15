//
//  TileInteraction.swift
//  Glance
//
//  Created by Gaty on 12/10/2026.
//

import AppKit
import Quartz
import SwiftUI

/// What a tray tile does under the pointer, done by AppKit, which the notch's window still gives
/// every event to: a click to select, ⌘ or Shift to choose several, a double-click to paste, a drag
/// out with every chosen item in it, and the menu.
struct TileInteraction: NSViewRepresentable {
    let item: TrayItem
    let tray: Tray
    /// Its page is showing, so the notch hands it the clicks on it (see `NotchEventView`).
    let live: Bool

    func makeNSView(context: Context) -> TileInteractionView { TileInteractionView() }

    func updateNSView(_ view: TileInteractionView, context: Context) {
        view.item = item
        view.tray = tray
        view.live = live
    }
}

final class TileInteractionView: NSView, NSDraggingSource {
    var item: TrayItem?
    var tray: Tray?
    var live = false
    private var downAt: NSPoint?
    private var dragged = false

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        NotificationCenter.default.post(name: Tray.didTouch, object: self)
        if event.modifierFlags.contains(.control) { return showMenu(event) }
        downAt = event.locationInWindow
        dragged = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard let downAt, !dragged, let item, let tray else { return }
        let moved = hypot(event.locationInWindow.x - downAt.x, event.locationInWindow.y - downAt.y)
        guard moved > 4 else { return }
        dragged = true
        // A chosen item takes every chosen one with it; any other goes alone.
        if !tray.selection.contains(item.id) { tray.deselect() }
        var items: [NSDraggingItem] = []
        let side = Shelf.icon
        for target in tray.targets(of: item) {
            let picture = TrayThumbnails.cached(target) ?? TileDrag.picture(for: target, in: tray)
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
        guard !dragged, let item, let tray else { return }
        let flags = event.modifierFlags
        if flags.contains(.command) {
            tray.choose(item.id, toggling: true)
        } else if flags.contains(.shift) {
            tray.choose(item.id, extending: true)
        } else if event.clickCount >= 2 {
            tray.paste(item)
        } else {
            // As in Finder: this one alone. ⌘ above adds it to the others or takes it out.
            tray.choose(item.id)
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        NotificationCenter.default.post(name: Tray.didTouch, object: self)
        showMenu(event)
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        guard let item else { return [] }
        // Not back onto the notch, where it came from; out to other apps, files go as Finder takes
        // them, and the tray's own copies are only ever copied out.
        if context == .withinApplication { return [] }
        return item.kind == .files ? [.copy, .move, .link, .generic] : [.copy, .generic]
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        tray?.draggingOut = false
    }

    // MARK: The menu

    private func showMenu(_ event: NSEvent) {
        guard let item, let tray else { return }
        // Right-clicked outside the chosen items: the menu is for this one alone, chosen, as Finder
        // chooses a file it shows the menu for.
        if !tray.selection.contains(item.id) { tray.choose(item.id) }
        NSMenu.popUpContextMenu(TrayMenu(items: tray.targets(of: item), tray: tray, anchor: self).menu, with: event, for: self)
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

    /// Without a thumbnail, as text and links are, an item is dragged as the tray draws it: a note
    /// as its page of words, a link as its site's icon.
    static func picture(for item: TrayItem, in tray: Tray) -> NSImage {
        let renderer = ImageRenderer(content: TrayItemPicture(item: item, tray: tray, side: Shelf.icon).environment(\.colorScheme, .dark))
        renderer.scale = NSScreen.main?.backingScaleFactor ?? 2
        return renderer.nsImage ?? NSImage(size: CGSize(width: Shelf.icon, height: Shelf.icon))
    }
}

/// The menu for items in the tray, laid out as Finder's is for files, in three groups: opening and
/// looking first, then copying and sharing (AirDrop is in Share), then removing; each with its
/// symbol, and named for how many items it acts on.
@MainActor
final class TrayMenu: NSObject, NSSharingServicePickerDelegate {
    let items: [TrayItem]
    let tray: Tray
    private(set) var menu = NSMenu()
    /// The item the menu is for, where Share's picker shows.
    private weak var anchor: NSView?
    /// Share's picker, kept while it's up: it tells this when it's done.
    private var picker: NSSharingServicePicker?
    /// The menu last shown, kept until the next one, so its picker can finish after the menu's gone.
    private static var shown: TrayMenu?

    init(items: [TrayItem], tray: Tray, anchor: NSView?) {
        self.items = items
        self.tray = tray
        self.anchor = anchor
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
        if CGPreflightPostEventAccess() { add("Paste" + many, "doc.on.clipboard", #selector(pasteItems)) }
        // As Finder's Share…: the share picker, with AirDrop, Messages, Mail and the rest. macOS's
        // own menu item for it shows the picker beside nothing in particular, which from the notch
        // was nowhere at all; this one shows it on the item.
        if !tray.shareable(items).isEmpty, anchor != nil { add("Share…", "square.and.arrow.up", #selector(share)) }
        separate()
        add(count > 1 ? "Remove\(many) from Tray" : "Remove from Tray", "minus.circle", #selector(remove))
        // The menu holds its items' target weakly; it keeps this alive while it's up.
        objc_setAssociatedObject(menu, &Self.key, self, .OBJC_ASSOCIATION_RETAIN)
        Self.shown = self
    }

    /// The picker, under the item, once the menu has gone, with Glance in front so it can be used.
    /// The notch stays open under it until a service is chosen, or it's dismissed.
    @objc private func share() {
        let shared = tray.shareable(items)
        guard !shared.isEmpty else { return }
        let picker = NSSharingServicePicker(items: shared)
        picker.delegate = self
        self.picker = picker
        tray.sharing = true
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(50))
            guard let self, let anchor = self.anchor, anchor.window != nil else {
                self?.tray.sharing = false
                return
            }
            NSApp.activate()
            picker.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .minY)
        }
    }

    /// A service chosen, which shows its own window, or the picker dismissed: either way, the notch
    /// is free to close.
    nonisolated func sharingServicePicker(_ picker: NSSharingServicePicker, didChoose service: NSSharingService?) {
        MainActor.assumeIsolated {
            tray.sharing = false
            self.picker = nil
        }
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
        case .image: _ = item.files.first.map { NSWorkspace.shared.open(tray.file($0, of: item)) }
        case .link: _ = item.text.flatMap(URL.init(string:)).map { NSWorkspace.shared.open($0) }
        case .text: break
        }
    }

    @objc private func reveal() {
        NSWorkspace.shared.activateFileViewerSelecting(items.filter { $0.kind == .files }.flatMap(tray.urls))
    }

    @objc private func quickLook() { TrayQuickLook.shared.show(TrayQuickLook.urls(for: items, in: tray)) }
    @objc private func copyItems() { tray.copy(items) }
    @objc private func pasteItems() { tray.paste(items) }
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
