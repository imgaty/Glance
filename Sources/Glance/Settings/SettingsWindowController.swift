//
//  SettingsWindowController.swift
//  Glance
//
//  Created by Gaty on 07/10/2026.
//

import AppKit
import SwiftUI

/// The Settings window, drawn like System Settings: as wide, the same sidebar with a search field
/// and icon tiles, back and forward beside the page's title, and each page a grouped form. It
/// brings in the Dock icon while it's open.
@MainActor
final class SettingsWindowController {
    var nowPlaying: NowPlaying?
    var onShowPermissions: (() -> Void)?

    private var window: NSWindow?

    /// System Settings' window: a 232-point sidebar and a 508-point page, never narrower or wider;
    /// at least 470 points tall, the 52-point toolbar included, and as tall as the screen allows.
    static let width: CGFloat = 740
    /// The sidebar's width, fixed, as System Settings' is.
    static let sidebarWidth: CGFloat = 232
    static let minHeight: CGFloat = 470 - 52

    func show() {
        guard let nowPlaying else { return }
        let window = self.window ?? makeWindow()
        self.window = window
        // Closed, it gave up its pages (see makeWindow); they're built again.
        if window.contentViewController == nil { fill(window, nowPlaying: nowPlaying) }
        AppWindows.bringForward(window)
    }

    /// Styled, with its toolbar, before the pages go in, so the toolbar is whole from the start:
    /// the sidebar runs to the top of the window, under the window buttons.
    private func makeWindow() -> NSWindow {
        let window = SettingsWindow(
            contentRect: NSRect(x: 0, y: 0, width: Self.width, height: 700),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered, defer: false)
        window.toolbar = NSToolbar()
        window.toolbarStyle = .unified
        window.titlebarSeparatorStyle = .none
        // No band behind back, forward and the title: the page's own background runs up behind
        // them, as in System Settings.
        window.titlebarAppearsTransparent = true
        // Like System Settings: the green button zooms to the screen's height, never full screen.
        window.collectionBehavior.insert(.fullScreenNone)
        window.isReleasedWhenClosed = false
        NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) {
            [weak self] _ in
            MainActor.assumeIsolated {
                AppWindows.didClose(window)
                // A closed window is only hidden, and its pages' notches and the page scrolling
                // behind them would go on moving, unseen, at full frame rate. Once it's gone, they go
                // too, and its size is kept for next time.
                DispatchQueue.main.async {
                    guard !window.isVisible else { return }
                    self?.lastFrame = window.frame
                    window.contentViewController = nil
                }
            }
        }
        // The sidebar's selection is in the accent color while the window is in front, and Glance
        // the app in use.
        for name in [NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification] {
            NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { _ in
                MainActor.assumeIsolated { FixedSidebar.refreshEmphasis(in: window) }
            }
        }
        for name in [NSApplication.didBecomeActiveNotification, NSApplication.didResignActiveNotification] {
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated {
                    // Back in front with nothing taking the keys (the menu bar menu had them), the
                    // window takes them again.
                    if NSApp.isActive, window.isVisible, NSApp.keyWindow == nil { window.makeKey() }
                    FixedSidebar.refreshEmphasis(in: window)
                }
            }
        }
        return window
    }

    /// Where the window was when it closed, to open there again, as tall as it was.
    private var lastFrame: NSRect?

    private func fill(_ window: NSWindow, nowPlaying: NowPlaying) {
        let view = SettingsView(onShowPermissions: { [weak self] in self?.onShowPermissions?() }) { [weak window] pane in
            window?.title = pane.title
        }
        .environmentObject(nowPlaying)
        let controller = NSHostingController(rootView: view)
        // As wide as System Settings, always; as tall as you make it, within its limits. (Its
        // preferred size would hold the height at the page's ideal.)
        controller.sizingOptions = [.minSize, .maxSize]
        // It opens on General, which is shown before the window could take its title.
        window.title = SettingsPane.general.title
        window.contentViewController = controller
        // Taking the pages shrinks the window to its smallest: it opens where it was, or, the first
        // time, as tall as System Settings does, in the middle of the screen.
        if let lastFrame {
            window.setFrame(lastFrame, display: false)
        } else {
            window.setContentSize(NSSize(width: Self.width, height: 700))
            window.center()
        }
        window.contentView?.layoutSubtreeIfNeeded()
        FixedSidebar.apply(in: window)
    }
}

/// Settings' window, which makes Glance the app in use, and itself the window in front, whenever it's
/// clicked. Glance runs in the background, and after its menu bar menu (a panel that takes the keys
/// without making Glance the app in use) a click on the window could leave it looking behind:
/// window buttons and sidebar selection gray.
private final class SettingsWindow: NSWindow {
    override func sendEvent(_ event: NSEvent) {
        if [.leftMouseDown, .rightMouseDown, .otherMouseDown].contains(event.type) {
            if !NSApp.isActive { AppWindows.comeForward() }
            if !isKeyWindow { makeKey() }
        }
        super.sendEvent(event)
    }
}

/// System Settings' sidebar can't be dragged wider, narrower or shut, and its edge offers no
/// handle. SwiftUI's split view still offers one with the sidebar's width fixed, so its controller
/// is told to report the divider as having no area to drag, the way AppKit lets a split view's
/// delegate lock it.
@MainActor
private enum FixedSidebar {
    static func apply(in window: NSWindow) {
        guard let controller = splitController(in: window) else { return }
        controller.splitViewItems.first?.canCollapse = false
        lock(controller)
        window.invalidateCursorRects(for: controller.splitView)
        if let table = sidebarTable(of: controller) { emphasize(table) }
    }

    /// The window takes the keys, and Glance is the app in use: an app in the background keeps its
    /// key window, but draws it, window buttons and sidebar selection, gray, as System Settings does.
    private static func inFront(_ window: NSWindow?) -> Bool {
        (window?.isKeyWindow ?? false) && NSApp.isActive
    }

    static func refreshEmphasis(in window: NSWindow) {
        guard let controller = splitController(in: window), let table = sidebarTable(of: controller) else { return }
        table.enumerateAvailableRowViews { row, _ in
            row.isEmphasized = inFront(window)
            row.needsDisplay = true
        }
    }

    private static func splitController(in window: NSWindow) -> NSSplitViewController? {
        func splitView(in view: NSView?) -> NSSplitView? {
            guard let view else { return nil }
            return view as? NSSplitView ?? view.subviews.lazy.compactMap(splitView).first
        }
        return splitView(in: window.contentView)?.delegate as? NSSplitViewController
    }

    private static func sidebarTable(of controller: NSSplitViewController) -> NSTableView? {
        func tableView(in view: NSView) -> NSTableView? {
            view as? NSTableView ?? view.subviews.lazy.compactMap(tableView).first
        }
        return controller.splitViewItems.first.flatMap { tableView(in: $0.viewController.view) }
    }

    /// Gives the controller, alone, a subclass whose divider has no draggable area.
    private static func lock(_ controller: NSSplitViewController) {
        subclass(controller, prefix: "GlanceFixedSidebar_") { made, base in
            let selector = #selector(NSSplitViewDelegate.splitView(_:effectiveRect:forDrawnRect:ofDividerAt:))
            guard let method = class_getInstanceMethod(base, selector) else { return }
            let noArea: @convention(block) (AnyObject, NSSplitView, NSRect, NSRect, Int) -> NSRect = { _, _, _, _, _ in .zero }
            class_addMethod(made, selector, imp_implementationWithBlock(noArea), method_getTypeEncoding(method))
        }
    }

    // MARK: Selection in the accent color

    /// System Settings' sidebar shows its selection in the accent color whenever its window is in
    /// front, wherever the focus is; a sidebar normally turns it gray once the focus moves into the
    /// page, as it does when a slider or a switch there is used. So the sidebar's rows draw as
    /// emphasized exactly while the window is key: the table, alone, gets a subclass that does this
    /// to each row it adds, and each row one whose emphasis follows the window.
    private static func emphasize(_ table: NSTableView) {
        table.enumerateAvailableRowViews { row, _ in emphasize(row) }
        subclass(table, prefix: "GlanceKeySidebar_") { made, base in
            let selector = #selector(NSTableView.didAdd(_:forRow:))
            guard let method = class_getInstanceMethod(base, selector) else { return }
            typealias DidAdd = @convention(c) (AnyObject, Selector, NSTableRowView, Int) -> Void
            let original = unsafeBitCast(method_getImplementation(method), to: DidAdd.self)
            let added: @convention(block) (AnyObject, NSTableRowView, Int) -> Void = { table, row, index in
                original(table, selector, row, index)
                MainActor.assumeIsolated { emphasize(row) }
            }
            class_addMethod(made, selector, imp_implementationWithBlock(added), method_getTypeEncoding(method))
        }
    }

    private static func emphasize(_ row: NSTableRowView) {
        let changed = subclass(row, prefix: "GlanceKeyRow_") { made, base in
            let getter = #selector(getter: NSTableRowView.isEmphasized)
            let setter = #selector(setter: NSTableRowView.isEmphasized)
            guard let get = class_getInstanceMethod(base, getter), let set = class_getInstanceMethod(base, setter) else { return }
            let isKey: @convention(block) (NSView) -> Bool = { row in MainActor.assumeIsolated { inFront(row.window) } }
            class_addMethod(made, getter, imp_implementationWithBlock(isKey), method_getTypeEncoding(get))
            typealias SetEmphasized = @convention(c) (AnyObject, Selector, Bool) -> Void
            let original = unsafeBitCast(method_getImplementation(set), to: SetEmphasized.self)
            // Whatever the table says, emphasized while the window is in front.
            let follow: @convention(block) (NSView, Bool) -> Void = { row, _ in
                original(row, setter, MainActor.assumeIsolated { inFront(row.window) })
            }
            class_addMethod(made, setter, imp_implementationWithBlock(follow), method_getTypeEncoding(set))
        }
        if changed {
            row.isEmphasized = true
            row.needsDisplay = true
        }
    }

    /// Gives one object a subclass of its own class, as key-value observing does, made once per
    /// class with the methods `add` puts in it. Returns whether the object was given it.
    @discardableResult
    private static func subclass(_ object: AnyObject, prefix: String, add: (_ made: AnyClass, _ base: AnyClass) -> Void) -> Bool {
        guard let base = object_getClass(object), !NSStringFromClass(base).hasPrefix(prefix) else { return false }
        let name = prefix + NSStringFromClass(base)
        var made: AnyClass? = NSClassFromString(name)
        if made == nil, let subclass = objc_allocateClassPair(base, name, 0) {
            add(subclass, base)
            objc_registerClassPair(subclass)
            made = subclass
        }
        guard let made else { return false }
        object_setClass(object, made)
        return true
    }
}
